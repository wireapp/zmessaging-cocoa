// 
// Wire
// Copyright (C) 2016 Wire Swiss GmbH
// 
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
// 
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
// 
// You should have received a copy of the GNU General Public License
// along with this program. If not, see http://www.gnu.org/licenses/.
// 


@import zimages;
@import ZMCSystem;
@import ZMTransport;

#import "ZMSelfTranscoder+Internal.h"
#import "ZMSyncStrategy.h"
#import "ZMUpstreamModifiedObjectSync.h"
#import "ZMSingleRequestSync.h"
#import "ZMUpstreamTranscoder.h"
#import "ZMUserSession+Internal.h"
#import "ZMClientRegistrationStatus.h"
#import "ZMTimedSingleRequestSync.h"

static NSString *SelfPath = @"/self";

static NSString * const MediumRemoteIdentifierDataKey = @"mediumRemoteIdentifier_data";
static NSString * const SmallProfileRemoteIdentifierDataKey = @"smallProfileRemoteIdentifier_data";

static NSString * const AccentColorValueKey = @"accentColorValue";
static NSString * const NameKey = @"name";
static NSString * const TrackingIdentifierKey = @"tracking_id";

static NSString * const ImageMediumDataKey = @"imageMediumData";
static NSString * const ImageSmallProfileDataKey = @"imageSmallProfileData";

NSTimeInterval ZMSelfTranscoderPendingValidationRequestInterval = 5;

@interface ZMSelfTranscoder ()
{
    dispatch_once_t didCheckNeedsToBeUdpatedFromBackend;
}

@property (nonatomic) ZMUpstreamModifiedObjectSync *upstreamObjectSync;
@property (nonatomic) ZMSingleRequestSync *downstreamSelfUserSync;
@property (nonatomic) NSPredicate *needsToBeUdpatedFromBackend;
@property (nonatomic, weak) ZMClientRegistrationStatus *clientStatus;

@end

@interface ZMSelfTranscoder (SingleRequestTranscoder) <ZMSingleRequestTranscoder>
@end

@interface ZMSelfTranscoder (UpstreamTranscoder) <ZMUpstreamTranscoder>
@end



@implementation ZMSelfTranscoder

- (instancetype)initWithClientRegistrationStatus:(ZMClientRegistrationStatus *)clientStatus
                            managedObjectContext:(NSManagedObjectContext *)moc
{
    NSArray<NSString *> *keysToSync = @[NameKey, AccentColorValueKey, SmallProfileRemoteIdentifierDataKey, MediumRemoteIdentifierDataKey];
    
    
    ZMUpstreamModifiedObjectSync *upstreamObjectSync = [[ZMUpstreamModifiedObjectSync alloc]
                                                        initWithTranscoder:self entityName:ZMUser.entityName
                                                        keysToSync:keysToSync
                                                        managedObjectContext:moc];
    
    return [self initWithClientRegistrationStatus:clientStatus
                         managedObjectContext:moc
                           upstreamObjectSync:upstreamObjectSync];
}

- (instancetype)initWithClientRegistrationStatus:(ZMClientRegistrationStatus *)clientStatus
                            managedObjectContext:(NSManagedObjectContext *)moc
                              upstreamObjectSync:(ZMUpstreamModifiedObjectSync *)upstreamObjectSync
{
    self = [super initWithManagedObjectContext:moc];
    if(self) {
        self.clientStatus = clientStatus;
        self.upstreamObjectSync = upstreamObjectSync;
        self.downstreamSelfUserSync = [[ZMSingleRequestSync alloc] initWithSingleRequestTranscoder:self managedObjectContext:self.managedObjectContext];
        self.needsToBeUdpatedFromBackend = [ZMUser predicateForNeedingToBeUpdatedFromBackend];
        _timedDownstreamSync = [[ZMTimedSingleRequestSync alloc] initWithSingleRequestTranscoder:self everyTimeInterval:ZMSelfTranscoderPendingValidationRequestInterval managedObjectContext:self.managedObjectContext];
    }
    return self;
}

- (NSArray *)contextChangeTrackers
{
    return @[self.upstreamObjectSync, self];
}

- (void)tearDown
{
    [self.timedDownstreamSync invalidate];
    self.clientStatus = nil;
    [super tearDown];
}

- (NSArray *)requestGenerators;
{
    if (self.clientStatus.currentPhase == ZMClientRegistrationPhaseWaitingForEmailVerfication) {
        [self.timedDownstreamSync readyForNextRequestIfNotBusy];
        return @[self.timedDownstreamSync];
    }
    if (! self.isSlowSyncDone) {
        return @[self.downstreamSelfUserSync];
    }
    return @[self.downstreamSelfUserSync, self.upstreamObjectSync];
}


- (void)checkIfNeedsToBeUdpatedFromBackend;
{
    dispatch_once(&didCheckNeedsToBeUdpatedFromBackend, ^{
        ZMUser *selfUser = [ZMUser selfUserInContext:self.managedObjectContext];
        if ([self.needsToBeUdpatedFromBackend evaluateWithObject:selfUser]) {
            [self.downstreamSelfUserSync readyForNextRequest];
        }
    });
}

- (BOOL)isSlowSyncDone;
{
    return (self.downstreamSelfUserSync.status != ZMSingleRequestInProgress);
}

- (void)setNeedsSlowSync
{
    [self.downstreamSelfUserSync readyForNextRequest];
}

- (void)processEvents:(NSArray<ZMUpdateEvent *> __unused *)events
           liveEvents:(BOOL __unused)liveEvents
       prefetchResult:(__unused ZMFetchRequestBatchResult *)prefetchResult;
{
    // no-op
}

- (BOOL)isSelfUserComplete
{
    ZMUser *selfUser = [ZMUser selfUserInContext:self.managedObjectContext];
    return selfUser.remoteIdentifier != nil;
}

@end



@implementation ZMSelfTranscoder (UpstreamTranscoder)

- (BOOL)shouldProcessUpdatesBeforeInserts;
{
    return NO;
}

- (ZMUpstreamRequest *)requestForUpdatingObject:(ZMManagedObject *)managedObject forKeys:(NSSet *)keys;
{
    ZMUser *user = (ZMUser *)managedObject;
    Require(user.isSelfUser);

    if ([keys containsObject:AccentColorValueKey] || [keys containsObject:NameKey]) {
        return [self requestForSettingBasicProfileDataOfUser:user changedKeys:keys];
    }
    else if([keys containsObject:SmallProfileRemoteIdentifierDataKey] && [keys containsObject:MediumRemoteIdentifierDataKey]) {
        
        if(user.smallProfileRemoteIdentifier == nil && user.mediumRemoteIdentifier == nil) {
            return [self requestForDeletingImageData];
        }
        else {
            return [self requestForSettingImageDataForSelfUser:user];
        }
    }
    
    ZMTrapUnableToGenerateRequest(keys, self);
    return nil;
}

- (ZMUpstreamRequest *)requestForSettingBasicProfileDataOfUser:(ZMUser *)user changedKeys:(NSSet *)keys
{
    NSMutableDictionary *payload = [NSMutableDictionary dictionary];
    
    if([keys containsObject:NameKey]) {
        payload[@"name"] = user.name;
    }
    if([keys containsObject:AccentColorValueKey]) {
        payload[@"accent_id"] = @(user.accentColorValue);
    }
    
    ZMTransportRequest *request = [ZMTransportRequest requestWithPath:@"/self" method:ZMMethodPUT payload:payload];
    return [[ZMUpstreamRequest alloc] initWithKeys:keys transportRequest:request];
}


- (ZMUpstreamRequest *)requestForSettingImageDataForSelfUser:(ZMUser *)user
{
    NSUUID *correlationID = user.imageCorrelationIdentifier;
    return [self requestWithPicturePayload:@[
                                      [ZMAssetMetaDataEncoder createAssetDataWithID:user.smallProfileRemoteIdentifier imageOwner:user format:ZMImageFormatProfile correlationID:correlationID],
                                      [ZMAssetMetaDataEncoder createAssetDataWithID:user.mediumRemoteIdentifier imageOwner:user format:ZMImageFormatMedium correlationID:correlationID]
                                      ]];
}


- (ZMUpstreamRequest *)requestForDeletingImageData
{
    return [self requestWithPicturePayload:@[]];
}

static NSString * const DeletionRequestKey = @"";

- (ZMUpstreamRequest *)requestWithPicturePayload:(NSArray *)picturePayload
{
    NSDictionary *payload = @{@"picture": picturePayload};
    ZMTransportRequest *request = [ZMTransportRequest requestWithPath:@"/self" method:ZMMethodPUT payload:payload];
    BOOL isDeletionRequest = (picturePayload.count < 1);
    return [[ZMUpstreamRequest alloc] initWithKeys:[NSSet setWithObjects:SmallProfileRemoteIdentifierDataKey, MediumRemoteIdentifierDataKey, nil] transportRequest:request userInfo:@{DeletionRequestKey: @(isDeletionRequest)}];
}

- (ZMUpstreamRequest *)requestForInsertingObject:(ZMManagedObject *)managedObject forKeys:(NSSet *)keys;
{
    NOT_USED(managedObject);
    NOT_USED(keys);
    return nil;
}

- (void)updateInsertedObject:(ZMManagedObject * __unused)managedObject request:(ZMUpstreamRequest *__unused)upstreamRequest response:(ZMTransportResponse *__unused)response;
{
    // we will never create a user on the backend with this sync
}


- (BOOL)updateUpdatedObject:(ZMUser *)selfUser
            requestUserInfo:(NSDictionary *)requestUserInfo
                   response:(ZMTransportResponse *__unused)response
                keysToParse:(NSSet *)keysToParse
{
    if ([keysToParse isEqual:[NSSet setWithObjects:MediumRemoteIdentifierDataKey, SmallProfileRemoteIdentifierDataKey, nil]])
    {
        BOOL wasDeletionRequest = [requestUserInfo[DeletionRequestKey] boolValue];
        if (wasDeletionRequest) {
            selfUser.imageMediumData = nil;
            selfUser.imageSmallProfileData = nil;
            [self.managedObjectContext enqueueDelayedSave];
        }
        
    }
    return NO;
}

- (ZMManagedObject *)objectToRefetchForFailedUpdateOfObject:(ZMManagedObject *)managedObject;
{
    NOT_USED(managedObject);
    return nil;
}

@end



@implementation ZMSelfTranscoder (SingleRequestTranscoder)


- (ZMTransportRequest *)requestForSingleRequestSync:(ZMSingleRequestSync *)sync;
{
    NOT_USED(sync);
    return [ZMTransportRequest requestGetFromPath:SelfPath];
}

- (void)didReceiveResponse:(ZMTransportResponse *)response forSingleRequest:(ZMSingleRequestSync *)sync;
{
    NOT_USED(sync);
    ZMUser *selfUser = [ZMUser selfUserInContext:self.managedObjectContext];

    if (response.result == ZMTransportResponseStatusSuccess) {
        
        ZMClientRegistrationStatus *clientStatus = self.clientStatus;
        ZMClientRegistrationPhase clientPhase = clientStatus.currentPhase;
        
        NSDictionary *payload = [response.payload asDictionary];
        [selfUser updateWithTransportData:payload authoritative:YES];
        [self updateTrackingIdentifierFromPayload:payload];
        
        // TODO: Write tests for all cases
        BOOL selfUserHasEmail = (selfUser.emailAddress != nil);
        BOOL needToNotifyAuthState = (clientPhase == ZMClientRegistrationPhaseWaitingForSelfUser) ||
                                     (clientPhase == ZMClientRegistrationPhaseWaitingForEmailVerfication && selfUserHasEmail);

        if (needToNotifyAuthState) {
            [clientStatus didFetchSelfUser];
        }
        
        if (sync == self.timedDownstreamSync) {
            if(!selfUserHasEmail) {
                if(self.timedDownstreamSync.timeInterval != ZMSelfTranscoderPendingValidationRequestInterval) {
                    self.timedDownstreamSync.timeInterval = ZMSelfTranscoderPendingValidationRequestInterval;
                }
            }
            else {
                self.timedDownstreamSync.timeInterval = 0;
            }
        }
    }
}

- (void)updateTrackingIdentifierFromPayload:(NSDictionary *)payload;
{
    NSString *identifier = [payload optionalStringForKey:TrackingIdentifierKey];
    if (identifier != nil) {
        self.managedObjectContext.userSessionTrackingIdentifier = identifier;
        ZMSDispatchGroup *group = [ZMSDispatchGroup groupWithLabel:@"ZMSelfTranscoder"];
        [self.managedObjectContext enqueueDelayedSaveWithGroup:group];
        [group notifyOnQueue:dispatch_get_main_queue() block:^{
            [[NSNotificationCenter defaultCenter] postNotificationName:ZMUserSessionTrackingIdentifierDidChangeNotification object:@1];
        }];
    }
}

@end



@implementation ZMSelfTranscoder (ContextChangeTracker)

- (NSFetchRequest *)fetchRequestForTrackedObjects
{
    [self checkIfNeedsToBeUdpatedFromBackend];
    return [self.upstreamObjectSync fetchRequestForTrackedObjects];
}

- (void)addTrackedObjects:(NSSet *)objects;
{
    [self.upstreamObjectSync addTrackedObjects:objects];
}

- (void)objectsDidChange:(NSSet *)objects
{
    ZMUser *selfUser = [ZMUser selfUserInContext:self.managedObjectContext];
    if ([objects containsObject:selfUser] && selfUser.needsToBeUpdatedFromBackend) {
        [self.downstreamSelfUserSync readyForNextRequest];
    }
}

@end
