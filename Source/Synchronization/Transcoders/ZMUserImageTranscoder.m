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


@import ZMCSystem;
@import ZMTransport;
@import ZMCDataModel;

#import "ZMUserImageTranscoder.h"
#import "ZMAssetRequestFactory.h"



static NSString * const ImageMediumDataKey = @"imageMediumData";
static NSString * const ImageSmallProfileDataKey = @"imageSmallProfileData";
static NSString * const ImageOrigionalProfileDataKey = @"originalProfileImageData";
static NSString * const MediumRemoteIdentifierDataKey = @"mediumRemoteIdentifier_data";
static NSString * const SmallProfileRemoteIdentifierDataKey = @"smallProfileRemoteIdentifier_data";
static NSString * const RequestUserProfileAssetNotificationName = @"ZMRequestUserProfileAssetNotification";
static NSString * const RequestUserProfileSmallAssetNotificationName = @"ZMRequestUserProfileSmallAssetNotificationName";

@interface ZMUserImageTranscoder ()

@property (nonatomic) ZMDownstreamObjectSyncWithWhitelist *smallProfileDownstreamSync;
@property (nonatomic) ZMDownstreamObjectSyncWithWhitelist *mediumDownstreamSync;
@property (nonatomic) ZMUpstreamModifiedObjectSync *upstreamSync;
@property (nonatomic, readonly) ZMImagePreprocessingTracker *assetPreprocessingTracker;
@property (nonatomic, readonly) NSOperationQueue *imageProcessingQueue;
@end


@interface ZMUserImageTranscoder (DownstreamTranscoder) <ZMDownstreamTranscoder>
@end


@interface ZMUserImageTranscoder (UpstreamTranscoder) <ZMUpstreamTranscoder>
@end



@interface ZMUserImageTranscoder (ZMUser_Private)

- (void)requestAssetForNotification:(NSNotification *)note;
- (void)requestSmallAssetForNotification:(NSNotification *)note;

@end



@implementation ZMUserImageTranscoder

- (instancetype)initWithManagedObjectContext:(NSManagedObjectContext *)moc imageProcessingQueue:(NSOperationQueue *)imageProcessingQueue;
{
    self = [super initWithManagedObjectContext:moc];
    if (self != nil) {
        _imageProcessingQueue = imageProcessingQueue;

        // Small profiles
        NSPredicate *filterForSmallImage = [NSCompoundPredicate andPredicateWithSubpredicates:@[
                                                                                                [ZMUser predicateForSmallImageNeedingToBeUpdatedFromBackend],
                                                                                                [ZMUser predicateForSmallImageDownloadFilter]
                                                                                                ]];
        self.smallProfileDownstreamSync = [[ZMDownstreamObjectSyncWithWhitelist alloc] initWithTranscoder:self
                                                                                               entityName:ZMUser.entityName
                                                                            predicateForObjectsToDownload:filterForSmallImage
                                                                                     managedObjectContext:self.managedObjectContext];
        
        // Medium profile
        NSPredicate *filterForMediumImage = [NSCompoundPredicate andPredicateWithSubpredicates:@[
                                                                                                 [ZMUser predicateForMediumImageNeedingToBeUpdatedFromBackend],
                                                                                                 [ZMUser predicateForMediumImageDownloadFilter]
                                                                                                 ]];
        self.mediumDownstreamSync = [[ZMDownstreamObjectSyncWithWhitelist alloc] initWithTranscoder:self
                                                                                         entityName:ZMUser.entityName
                                                                      predicateForObjectsToDownload:filterForMediumImage
                                                                               managedObjectContext:self.managedObjectContext];
        
        [moc performGroupedBlock:^{
            ZMUser *selfUser = [ZMUser selfUserInContext:moc];
            [self recoverFromInconsistentUserImageStatusOfSelfUser:selfUser];
            [self.smallProfileDownstreamSync whiteListObject:selfUser];
            [self.mediumDownstreamSync whiteListObject:selfUser];
        }];
        
        // Self user upstream
        self.upstreamSync = [[ZMUpstreamAssetSync alloc] initWithTranscoder:self entityName:ZMUser.entityName keysToSync:@[ImageSmallProfileDataKey, ImageMediumDataKey] managedObjectContext:self.managedObjectContext];
        
        _assetPreprocessingTracker = [self createAssetPreprocessingTracker];
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(requestAssetForNotification:) name:RequestUserProfileAssetNotificationName object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(requestSmallAssetForNotification:) name:RequestUserProfileSmallAssetNotificationName object:nil];
    
        
    }
    return self;
}

- (void)recoverFromInconsistentUserImageStatusOfSelfUser:(ZMUser *)selfUser
{
    [self.managedObjectContext performGroupedBlock:^{
        NSSet *imageMediumKeys = [NSSet setWithArray:@[ImageMediumDataKey,ImageSmallProfileDataKey]];
        BOOL hasLocalModificationsForImageKeys = [selfUser hasLocalModificationsForKeys:imageMediumKeys];
        BOOL hasMissingImageData = selfUser.imageMediumData == nil || selfUser.imageSmallProfileData == nil;
        
        if (hasLocalModificationsForImageKeys && hasMissingImageData) {
            [selfUser resetLocallyModifiedKeys:imageMediumKeys];
        }
    }];
}

- (ZMImagePreprocessingTracker *)createAssetPreprocessingTracker
{
    NSPredicate *attributePredicate = [self.class predicateForNeedingToBePreprocessed];
    return [[ZMImagePreprocessingTracker alloc] initWithManagedObjectContext:self.managedObjectContext
                                                        imageProcessingQueue:self.imageProcessingQueue
                                                              fetchPredicate:attributePredicate
                                                    needsProcessingPredicate:attributePredicate
                                                                 entityClass:ZMUser.class];
}

- (void)tearDown;
{
    [super tearDown];
    [self.assetPreprocessingTracker tearDown];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

+ (NSString *)pathForAssetID:(NSUUID *)assetID ofUserID:(NSUUID *)userID;
{
    NSString *last = [[assetID.transportString stringByAppendingString:@"?conv_id="] stringByAppendingString:userID.transportString];
    NSString *path = [NSString pathWithComponents:@[@"/", @"assets", last]];
    return path;
}

+ (NSPredicate *)predicateForNeedingToBePreprocessed;
{
    return [NSPredicate predicateWithFormat:@"%K != NIL", ImageOrigionalProfileDataKey];
}

- (BOOL)isSlowSyncDone;
{
    return YES;
}

- (NSArray *)contextChangeTrackers;
{
    return @[self.assetPreprocessingTracker, self.smallProfileDownstreamSync, self.mediumDownstreamSync, self.upstreamSync];
}

- (void)setNeedsSlowSync;
{
    // no-op
}

- (NSArray *)requestGenerators;
{
    return @[self.smallProfileDownstreamSync, self.mediumDownstreamSync, self.upstreamSync];
}

- (void)processEvents:(NSArray<ZMUpdateEvent *> __unused *)events
           liveEvents:(BOOL __unused)liveEvents
       prefetchResult:(__unused ZMFetchRequestBatchResult *)prefetchResult;
{
    // no op
}

@end



@implementation ZMUserImageTranscoder (DownstreamTranscoder)

- (ZMTransportRequest *)requestForFetchingObject:(ZMUser *)user downstreamSync:(id<ZMObjectSync>)downstreamSync;
{
    NSUUID *remoteID;
    if (downstreamSync == self.mediumDownstreamSync) {
        if ([user.keysThatHaveLocalModifications containsObject:MediumRemoteIdentifierDataKey]) {
            return nil;
        }
        remoteID = user.mediumRemoteIdentifier;
    }
    else if (downstreamSync == self.smallProfileDownstreamSync) {
        if ([user.keysThatHaveLocalModifications containsObject:SmallProfileRemoteIdentifierDataKey]) {
            return nil;
        }
        remoteID = user.smallProfileRemoteIdentifier;
    }
    else {
        RequireString(NO, "Invalid downstream sync");
    }
    
    VerifyReturnNil(remoteID != nil); // Should not receive users with <nil> mediumRemoteIdentifier here.
    NSString *path = [ZMUserImageTranscoder pathForAssetID:remoteID ofUserID:user.remoteIdentifier];
    return [ZMTransportRequest imageGetRequestFromPath:path];
}

- (void)updateObject:(ZMUser *)user withResponse:(ZMTransportResponse *)response downstreamSync:(id<ZMObjectSync>)downstreamSync;
{
    if (downstreamSync == self.smallProfileDownstreamSync) {
        user.localSmallProfileRemoteIdentifier = user.smallProfileRemoteIdentifier;
        user.imageSmallProfileData = response.imageData;
    }
    else if (downstreamSync == self.mediumDownstreamSync) {
        user.localMediumRemoteIdentifier = user.mediumRemoteIdentifier;
        user.imageMediumData = response.imageData;
    }
    else {
        RequireString(NO, "Invalid downstream sync");
    }
}

- (void)deleteObject:(ZMUser * __unused)user downstreamSync:(ZMDownstreamObjectSync * __unused)downstreamSync;
{
    // Don't do anything
}

@end



@implementation ZMUserImageTranscoder (UpstreamTranscoder)


- (BOOL)shouldProcessUpdatesBeforeInserts;
{
    return YES;
}

- (ZMUpstreamRequest *)requestForUpdatingObject:(ZMUser *)user forKeys:(NSSet *)keys;
{
    Require(user.isSelfUser);
    
    if ([keys containsObject:ImageSmallProfileDataKey] || [keys containsObject:ImageMediumDataKey]) {
        return [self requestForUploadingImageToSelfConversationOnSelfUser:user keys:keys];
    }

    ZMTrapUnableToGenerateRequest(keys, self);
    return nil;
}

- (ZMUpstreamRequest *)requestForUploadingImageToSelfConversationOnSelfUser:(ZMUser *)user keys:(NSSet *)keys
{
    NSUUID *selfConversationID = [ZMConversation selfConversationIdentifierInContext:self.managedObjectContext];
    
    if (selfConversationID == nil) {
        return nil;
    }

    ZMImageFormat imageFormat = ZMImageFormatInvalid;
    NSString *updatedKey;
    if ([keys containsObject:ImageSmallProfileDataKey]) {
        updatedKey = ImageSmallProfileDataKey;
        imageFormat = ZMImageFormatProfile;
    }
    else if ([keys containsObject:ImageMediumDataKey]) {
        updatedKey = ImageMediumDataKey;
        imageFormat = ZMImageFormatMedium;
    }
    
    if (imageFormat == ZMImageFormatInvalid) {
        return nil;
    }
    
    ZMTransportRequest *request = [ZMAssetRequestFactory requestForImageOwner:user format:imageFormat conversationID:selfConversationID correlationID:user.imageCorrelationIdentifier resultHandler:nil];
    if (request == nil) {
        return nil;
    }
    
    return [[ZMUpstreamRequest alloc] initWithKeys:[NSSet setWithObject:updatedKey] transportRequest:request];
}



- (ZMUpstreamRequest *)requestForInsertingObject:(ZMManagedObject * __unused)managedObject forKeys:(NSSet * __unused)keys;
{
    RequireString(NO, "Should never get called.");
    return nil;
}

- (void)updateInsertedObject:(ZMManagedObject * __unused)managedObject request:(ZMUpstreamRequest * __unused)upstreamRequest response:(ZMTransportResponse *__unused)response;
{
    RequireString(NO, "Should never get called.");
}

- (ZMManagedObject *)objectToRefetchForFailedUpdateOfObject:(ZMManagedObject * __unused)managedObject
{
    return nil;
}

- (void)checkIfBothMediumAndSmallProfileHaveBeenUploaded:(ZMUser *)user;
{
    BOOL doneProcessingImage = user.originalProfileImageData == nil;
    BOOL doneUploading = ! [[NSSet setWithObjects:ImageSmallProfileDataKey, ImageMediumDataKey, nil] intersectsSet:[user keysThatHaveLocalModifications]];
    if (doneProcessingImage && doneUploading) {
        [user setLocallyModifiedKeys:[NSSet setWithObjects:SmallProfileRemoteIdentifierDataKey, MediumRemoteIdentifierDataKey, nil]];
    }
}

- (BOOL)updateUpdatedObject:(ZMUser *)user
            requestUserInfo:(NSDictionary * __unused)requestUserInfo
                   response:(ZMTransportResponse *)response
                keysToParse:(NSSet *)keysToParse
{
    NSDictionary *payloadData = response.payload.asDictionary[@"data"];
    NSDictionary *payloadInfo = payloadData[@"info"];
    NSUUID *receivedImageCorrelationID = [payloadInfo[@"correlation_id"] UUID];
    
    if (! [user.imageCorrelationIdentifier isEqual:receivedImageCorrelationID]) {
        return NO;
    }
    
    if ([keysToParse containsObject:ImageSmallProfileDataKey]) {
        VerifyString([user.imageCorrelationIdentifier isEqual:receivedImageCorrelationID],
                     "Unexpected correlation ID while uploading small profile image.");
        
        NSString *imageIDString = payloadData[@"id"];
        user.smallProfileRemoteIdentifier = [imageIDString UUID];
        user.localSmallProfileRemoteIdentifier = user.smallProfileRemoteIdentifier;
        
        [user resetLocallyModifiedKeys:[NSSet setWithObject:ImageSmallProfileDataKey]];
        [self checkIfBothMediumAndSmallProfileHaveBeenUploaded:user];
        
        return YES;
    }
    else if ([keysToParse containsObject:ImageMediumDataKey]) {
        VerifyString([user.imageCorrelationIdentifier isEqual:receivedImageCorrelationID],
                     "Unexpected correlation ID while uploading medium profile image.");
        
        NSString *imageIDString = payloadData[@"id"];
        user.mediumRemoteIdentifier = [imageIDString UUID];
        user.localMediumRemoteIdentifier = user.mediumRemoteIdentifier;
        
        [user resetLocallyModifiedKeys:[NSSet setWithObject:ImageMediumDataKey]];
        [self checkIfBothMediumAndSmallProfileHaveBeenUploaded:user];
        
        return YES;
    }
    
    return NO;
}

@end




@implementation ZMUserImageTranscoder (ZMSearchUser)

+ (ZMTransportRequest *)requestForFetchingAssetWithID:(NSUUID *)assetID forUserWithID:(NSUUID *)userRemoteIdentifier
{
    if (assetID == nil || userRemoteIdentifier == nil) {
        return nil;
    }
    
    NSString *path = [ZMUserImageTranscoder pathForAssetID:assetID ofUserID:userRemoteIdentifier];
    ZMTransportRequest *request = [ZMTransportRequest requestWithPath:path method:ZMMethodGET payload:nil];
    return request;
}

@end



@implementation ZMUserImageTranscoder (ZMUser)

+ (void)requestAssetForUserWithObjectID:(NSManagedObjectID *)objectID;
{
    [[NSNotificationCenter defaultCenter] postNotificationName:RequestUserProfileAssetNotificationName object:objectID];
}

+ (void)requestSmallAssetForUserWithObjectID:(NSManagedObjectID *)objectID;
{
    [[NSNotificationCenter defaultCenter] postNotificationName:RequestUserProfileSmallAssetNotificationName object:objectID];
}

@end



@implementation ZMUserImageTranscoder (ZMUser_Private)

- (void)requestAssetForNotification:(NSNotification *)note;
{
    [self.managedObjectContext performGroupedBlock:^{
        [self.mediumDownstreamSync whiteListObject:(ZMManagedObject *)[self.managedObjectContext objectWithID:(NSManagedObjectID *)note.object]];
    }];
}

- (void)requestSmallAssetForNotification:(NSNotification *)note;
{
    [self.managedObjectContext performGroupedBlock:^{
        [self.smallProfileDownstreamSync whiteListObject:(ZMManagedObject *)[self.managedObjectContext objectWithID:(NSManagedObjectID *)note.object]];
    }];
}

@end
