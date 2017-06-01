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


@import UIKit;
@import WireImages;
@import WireUtilities;
@import WireTransport;
@import WireDataModel;
@import WireMessageStrategy;
@import WireRequestStrategy;

#import "ZMSyncStrategy+Internal.h"
#import "ZMSyncStrategy+ManagedObjectChanges.h"
#import "ZMSyncStrategy+EventProcessing.h"
#import "ZMUserSession+Internal.h"
#import "ZMConnectionTranscoder.h"
#import "ZMUserTranscoder.h"
#import "ZMSelfStrategy.h"
#import "ZMConversationTranscoder.h"
#import "ZMAuthenticationStatus.h"
#import "ZMMissingUpdateEventsTranscoder.h"
#import "ZMLastUpdateEventIDTranscoder.h"
#import "ZMRegistrationTranscoder.h"
#import "ZMCallFlowRequestStrategy.h"
#import "ZMLoginTranscoder.h"
#import "ZMCallStateRequestStrategy.h"
#import "ZMPhoneNumberVerificationTranscoder.h"
#import "ZMLoginCodeRequestTranscoder.h"
#import "WireSyncEngineLogs.h"
#import "ZMClientRegistrationStatus.h"
#import "ZMOnDemandFlowManager.h"
#import "ZMHotFix.h"
#import <WireSyncEngine/WireSyncEngine-Swift.h>

@interface ZMSyncStrategy ()
{
    dispatch_once_t _didFetchObjects;
}

@property (nonatomic) NSManagedObjectContext *syncMOC;
@property (nonatomic, weak) NSManagedObjectContext *uiMOC;

@property (nonatomic) id<ZMApplication> application;

@property (nonatomic) ZMConnectionTranscoder *connectionTranscoder;
@property (nonatomic) ZMUserTranscoder *userTranscoder;
@property (nonatomic) ZMSelfStrategy *selfStrategy;
@property (nonatomic) ZMConversationTranscoder *conversationTranscoder;
@property (nonatomic) SystemMessageEventsConsumer *systemMessageEventConsumer;
@property (nonatomic) ClientMessageTranscoder *clientMessageTranscoder;
@property (nonatomic) ZMMissingUpdateEventsTranscoder *missingUpdateEventsTranscoder;
@property (nonatomic) ZMLastUpdateEventIDTranscoder *lastUpdateEventIDTranscoder;
@property (nonatomic) ZMRegistrationTranscoder *registrationTranscoder;
@property (nonatomic) ZMPhoneNumberVerificationTranscoder *phoneNumberVerificationTranscoder;
@property (nonatomic) ZMLoginTranscoder *loginTranscoder;
@property (nonatomic) ZMLoginCodeRequestTranscoder *loginCodeRequestTranscoder;
@property (nonatomic) ZMCallFlowRequestStrategy *callFlowRequestStrategy;
@property (nonatomic) ZMCallStateRequestStrategy *callStateRequestStrategy;
@property (nonatomic) LinkPreviewAssetUploadRequestStrategy *linkPreviewAssetUploadRequestStrategy;
@property (nonatomic) ImageDownloadRequestStrategy *imageDownloadRequestStrategy;

@property (nonatomic) ZMUpdateEventsBuffer *eventsBuffer;
@property (nonatomic) ZMChangeTrackerBootstrap *changeTrackerBootStrap;
@property (nonatomic) ConversationStatusStrategy *conversationStatusSync;
@property (nonatomic) UserClientRequestStrategy *userClientRequestStrategy;
@property (nonatomic) FetchingClientRequestStrategy *fetchingClientRequestStrategy;
@property (nonatomic) MissingClientsRequestStrategy *missingClientsRequestStrategy;
@property (nonatomic) LinkPreviewAssetDownloadRequestStrategy *linkPreviewAssetDownloadRequestStrategy;
@property (nonatomic) PushTokenStrategy *pushTokenStrategy;
@property (nonatomic) SearchUserImageStrategy *searchUserImageStrategy;

@property (nonatomic, readwrite) CallingRequestStrategy *callingRequestStrategy;

@property (nonatomic) NSManagedObjectContext *eventMOC;
@property (nonatomic) EventDecoder *eventDecoder;
@property (nonatomic, weak) LocalNotificationDispatcher *localNotificationDispatcher;

@property (nonatomic) ZMApplicationStatusDirectory *applicationStatusDirectory;
@property (nonatomic) NSArray *allChangeTrackers;

@property (nonatomic) NSArray<ZMObjectSyncStrategy *> *requestStrategies;
@property (nonatomic) NSArray<id<ZMEventConsumer>> *eventConsumers;

@property (atomic) BOOL tornDown;
@property (nonatomic) BOOL contextMergingDisabled;

@property (nonatomic, weak) id<ZMSyncStateDelegate> syncStateDelegate;
@property (nonatomic) ZMHotFix *hotFix;
@property (nonatomic) NotificationDispatcher *notificationDispatcher;

@end


@interface ZMSyncStrategy (Registration) <ZMClientRegistrationStatusDelegate>
@end

@interface LocalNotificationDispatcher (Push) <PushMessageHandler>
@end

@interface BackgroundAPNSConfirmationStatus (Protocol) <DeliveryConfirmationDelegate>
@end

@interface ZMClientRegistrationStatus (Protocol) <ClientRegistrationDelegate>
@end


@implementation ZMSyncStrategy

ZM_EMPTY_ASSERTING_INIT()


- (instancetype)initWithSyncManagedObjectContextMOC:(NSManagedObjectContext *)syncMOC
                             uiManagedObjectContext:(NSManagedObjectContext *)uiMOC
                                             cookie:(ZMCookie *)cookie
                                       mediaManager:(id<AVSMediaManager>)mediaManager
                                onDemandFlowManager:(ZMOnDemandFlowManager *)onDemandFlowManager
                                  syncStateDelegate:(id<ZMSyncStateDelegate>)syncStateDelegate
                       localNotificationsDispatcher:(LocalNotificationDispatcher *)localNotificationsDispatcher
                           taskCancellationProvider:(id <ZMRequestCancellation>)taskCancellationProvider
                                 appGroupIdentifier:(NSString *)appGroupIdentifier
                                        application:(id<ZMApplication>)application;
{
    self = [super init];
    if (self) {
        self.syncStateDelegate = syncStateDelegate;
        self.notificationDispatcher = [[NotificationDispatcher alloc] initWithManagedObjectContext: uiMOC];
        self.application = application;
        self.localNotificationDispatcher = localNotificationsDispatcher;
        self.syncMOC = syncMOC;
        self.uiMOC = uiMOC;
        self.hotFix = [[ZMHotFix alloc] initWithSyncMOC:self.syncMOC];

        self.eventMOC = [NSManagedObjectContext createEventContextWithAppGroupIdentifier:appGroupIdentifier];
        [self.eventMOC addGroup:self.syncMOC.dispatchGroup];
        
        self.applicationStatusDirectory = [[ZMApplicationStatusDirectory alloc] initWithManagedObjectContext:syncMOC
                                                                                                      cookie:cookie
                                                                                         requestCancellation:taskCancellationProvider
                                                                                                 application:application
                                                                                           syncStateDelegate:self];
        
        [self createTranscodersWithLocalNotificationsDispatcher:localNotificationsDispatcher mediaManager:mediaManager onDemandFlowManager:onDemandFlowManager];
        
        self.eventsBuffer = [[ZMUpdateEventsBuffer alloc] initWithUpdateEventConsumer:self];
        self.userClientRequestStrategy = [[UserClientRequestStrategy alloc] initWithAuthenticationStatus:self.applicationStatusDirectory.authenticationStatus
                                                                                clientRegistrationStatus:self.applicationStatusDirectory.clientRegistrationStatus
                                                                                      clientUpdateStatus:self.applicationStatusDirectory.clientUpdateStatus
                                                                                                 context:self.syncMOC
                                                                                           userKeysStore:self.syncMOC.zm_cryptKeyStore];
        self.missingClientsRequestStrategy = [[MissingClientsRequestStrategy alloc] initWithManagedObjectContext:self.syncMOC applicationStatus:self.applicationStatusDirectory];
        self.fetchingClientRequestStrategy = [[FetchingClientRequestStrategy alloc] initWithManagedObjectContext:self.syncMOC applicationStatus:self.applicationStatusDirectory];
        
        NSOperationQueue *imageProcessingQueue = [ZMImagePreprocessor createSuitableImagePreprocessingQueue];
        
        self.requestStrategies = @[
                                   self.registrationTranscoder,
                                   self.phoneNumberVerificationTranscoder,
                                   self.loginCodeRequestTranscoder,
                                   self.loginTranscoder,
                                   self.userClientRequestStrategy,
                                   self.missingClientsRequestStrategy,
                                   self.missingUpdateEventsTranscoder,
                                   self.fetchingClientRequestStrategy,
                                   [[ProxiedRequestStrategy alloc] initWithManagedObjectContext:self.syncMOC applicationStatus:self.applicationStatusDirectory requestsStatus:self.applicationStatusDirectory.proxiedRequestStatus],
                                   [[DeleteAccountRequestStrategy alloc] initWithManagedObjectContext:self.syncMOC applicationStatus:self.applicationStatusDirectory],
                                   [[AssetDownloadRequestStrategy alloc] initWithManagedObjectContext:self.syncMOC applicationStatus:self.applicationStatusDirectory],
                                   [[AssetV3DownloadRequestStrategy alloc] initWithManagedObjectContext:self.syncMOC applicationStatus:self.applicationStatusDirectory],
                                   [[AssetClientMessageRequestStrategy alloc] initWithManagedObjectContext:self.syncMOC applicationStatus:self.applicationStatusDirectory],
                                   [[AssetV3ImageUploadRequestStrategy alloc] initWithManagedObjectContext:self.syncMOC applicationStatus:self.applicationStatusDirectory],
                                   [[AssetV3PreviewDownloadRequestStrategy alloc] initWithManagedObjectContext:self.syncMOC applicationStatus:self.applicationStatusDirectory],
                                   [[AssetV3FileUploadRequestStrategy alloc] initWithManagedObjectContext:self.syncMOC applicationStatus:self.applicationStatusDirectory],
                                   [[AddressBookUploadRequestStrategy alloc] initWithManagedObjectContext:self.syncMOC applicationStatus:self.applicationStatusDirectory],
                                   self.clientMessageTranscoder,
                                   [[UserProfileRequestStrategy alloc] initWithManagedObjectContext:self.syncMOC
                                                                                  applicationStatus:self.applicationStatusDirectory
                                                                            userProfileUpdateStatus:self.applicationStatusDirectory.userProfileUpdateStatus],
                                   [[SelfContactCardUploadStrategy alloc] initWithAuthenticationStatus:self.applicationStatusDirectory.authenticationStatus
                                                                              clientRegistrationStatus:self.applicationStatusDirectory.clientRegistrationStatus
                                                                                  managedObjectContext:self.syncMOC],
                                   self.linkPreviewAssetDownloadRequestStrategy,
                                   self.linkPreviewAssetUploadRequestStrategy,
                                   self.imageDownloadRequestStrategy,
                                   [[PushTokenStrategy alloc] initWithManagedObjectContext:self.syncMOC applicationStatus:self.applicationStatusDirectory],
                                   [[TypingStrategy alloc] initWithApplicationStatus:self.applicationStatusDirectory managedObjectContext:self.syncMOC],
                                   [[SearchUserImageStrategy alloc] initWithApplicationStatus:self.applicationStatusDirectory managedObjectContext:self.syncMOC],
                                   self.connectionTranscoder,
                                   self.conversationTranscoder,
                                   self.userTranscoder,
                                   self.lastUpdateEventIDTranscoder,
                                   self.missingUpdateEventsTranscoder,
                                   [[UserImageStrategy alloc] initWithManagedObjectContext:self.syncMOC applicationStatus:self.applicationStatusDirectory imageProcessingQueue:imageProcessingQueue],
                                   [[LinkPreviewUploadRequestStrategy alloc] initWithManagedObjectContext:self.syncMOC clientRegistrationDelegate:self.applicationStatusDirectory.clientRegistrationStatus],
                                   self.selfStrategy,
                                   self.callingRequestStrategy,
                                   self.callStateRequestStrategy,
                                   self.callFlowRequestStrategy,
                                   [[GenericMessageNotificationRequestStrategy alloc] initWithManagedObjectContext:self.syncMOC clientRegistrationDelegate:self.applicationStatusDirectory.clientRegistrationStatus],
                                   [[UserImageAssetUpdateStrategy alloc] initWithManagedObjectContext:self.syncMOC applicationStatusDirectory:self.applicationStatusDirectory],
                                   [[TeamSyncRequestStrategy alloc] initWithManagedObjectContext:self.syncMOC applicationStatus:self.applicationStatusDirectory syncStatus:self.applicationStatusDirectory.syncStatus],
                                   [[TeamDownloadRequestStrategy alloc] initWithManagedObjectContext:self.syncMOC applicationStatus:self.applicationStatusDirectory],
                                   [[MemberDownloadRequestStrategy alloc] initWithManagedObjectContext:self.syncMOC applicationStatus:self.applicationStatusDirectory]
                                   ];
        
        self.changeTrackerBootStrap = [[ZMChangeTrackerBootstrap alloc] initWithManagedObjectContext:self.syncMOC changeTrackers:self.allChangeTrackers];

        ZM_ALLOW_MISSING_SELECTOR([[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(managedObjectContextDidSave:) name:NSManagedObjectContextDidSaveNotification object:self.syncMOC]);
        ZM_ALLOW_MISSING_SELECTOR([[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(managedObjectContextDidSave:) name:NSManagedObjectContextDidSaveNotification object:uiMOC]);

        [application registerObserverForDidEnterBackground:self selector:@selector(appDidEnterBackground:)];
        [application registerObserverForWillEnterForeground:self selector:@selector(appWillEnterForeground:)];
        [application registerObserverForApplicationWillTerminate:self selector:@selector(appTerminated:)];
    }
    return self;
}

- (void)createTranscodersWithLocalNotificationsDispatcher:(LocalNotificationDispatcher *)localNotificationsDispatcher
                                         mediaManager:(id<AVSMediaManager>)mediaManager
                                  onDemandFlowManager:(ZMOnDemandFlowManager *)onDemandFlowManager
{
    self.eventDecoder = [[EventDecoder alloc] initWithEventMOC:self.eventMOC syncMOC:self.syncMOC];
    self.connectionTranscoder = [[ZMConnectionTranscoder alloc] initWithManagedObjectContext:self.syncMOC applicationStatus:self.applicationStatusDirectory syncStatus:self.applicationStatusDirectory.syncStatus];
    self.userTranscoder = [[ZMUserTranscoder alloc] initWithManagedObjectContext:self.syncMOC applicationStatus:self.applicationStatusDirectory syncStatus:self.applicationStatusDirectory.syncStatus];
    self.selfStrategy = [[ZMSelfStrategy alloc] initWithManagedObjectContext:self.syncMOC applicationStatus:self.applicationStatusDirectory clientRegistrationStatus:self.applicationStatusDirectory.clientRegistrationStatus syncStatus:self.applicationStatusDirectory.syncStatus];
    self.conversationTranscoder = [[ZMConversationTranscoder alloc] initWithSyncStrategy:self applicationStatus:self.applicationStatusDirectory syncStatus:self.applicationStatusDirectory.syncStatus];
    self.systemMessageEventConsumer = [[SystemMessageEventsConsumer alloc] initWithMoc:self.syncMOC localNotificationDispatcher:localNotificationsDispatcher];
    self.clientMessageTranscoder = [[ClientMessageTranscoder alloc] initIn:self.syncMOC localNotificationDispatcher:localNotificationsDispatcher applicationStatus:self.applicationStatusDirectory];
    self.registrationTranscoder = [[ZMRegistrationTranscoder alloc] initWithManagedObjectContext:self.syncMOC applicationStatusDirectory:self.applicationStatusDirectory];
    self.missingUpdateEventsTranscoder = [[ZMMissingUpdateEventsTranscoder alloc] initWithSyncStrategy:self previouslyReceivedEventIDsCollection:self.eventDecoder application:self.application backgroundAPNSPingbackStatus:self.applicationStatusDirectory.pingBackStatus syncStatus:self.applicationStatusDirectory.syncStatus];
    self.lastUpdateEventIDTranscoder = [[ZMLastUpdateEventIDTranscoder alloc] initWithManagedObjectContext:self.syncMOC applicationStatus:self.applicationStatusDirectory syncStatus:self.applicationStatusDirectory.syncStatus objectDirectory:self];
    self.callFlowRequestStrategy = [[ZMCallFlowRequestStrategy alloc] initWithMediaManager:mediaManager onDemandFlowManager:onDemandFlowManager managedObjectContext:self.syncMOC applicationStatus:self.applicationStatusDirectory application:self.application];
    self.callingRequestStrategy = [[CallingRequestStrategy alloc] initWithManagedObjectContext:self.syncMOC clientRegistrationDelegate:self.applicationStatusDirectory.clientRegistrationStatus];
    self.callStateRequestStrategy = [[ZMCallStateRequestStrategy alloc] initWithManagedObjectContext:self.syncMOC applicationStatus:self.applicationStatusDirectory callFlowRequestStrategy:self.callFlowRequestStrategy];
    self.loginTranscoder = [[ZMLoginTranscoder alloc] initWithManagedObjectContext:self.syncMOC applicationStatusDirectory:self.applicationStatusDirectory];
    self.loginCodeRequestTranscoder = [[ZMLoginCodeRequestTranscoder alloc] initWithManagedObjectContext:self.syncMOC applicationStatusDirectory:self.applicationStatusDirectory];
    self.phoneNumberVerificationTranscoder = [[ZMPhoneNumberVerificationTranscoder alloc] initWithManagedObjectContext:self.syncMOC applicationStatusDirectory:self.applicationStatusDirectory];
    self.conversationStatusSync = [[ConversationStatusStrategy alloc] initWithManagedObjectContext:self.syncMOC];
    self.linkPreviewAssetDownloadRequestStrategy = [[LinkPreviewAssetDownloadRequestStrategy alloc] initWithManagedObjectContext:self.syncMOC applicationStatus:self.applicationStatusDirectory];
    self.linkPreviewAssetUploadRequestStrategy = [[LinkPreviewAssetUploadRequestStrategy alloc] initWithManagedObjectContext:self.syncMOC applicationStatus:self.applicationStatusDirectory linkPreviewPreprocessor:nil previewImagePreprocessor:nil];
    self.imageDownloadRequestStrategy = [[ImageDownloadRequestStrategy alloc] initWithManagedObjectContext:self.syncMOC applicationStatus:self.applicationStatusDirectory];
}

- (void)appDidEnterBackground:(NSNotification *)note
{
    NOT_USED(note);
    ZMBackgroundActivity *activity = [[BackgroundActivityFactory sharedInstance] backgroundActivityWithName:@"enter background"];
    [self.notificationDispatcher applicationDidEnterBackground];
    [self.syncMOC performGroupedBlock:^{
        self.applicationStatusDirectory.operationStatus.isInBackground = YES;
        [ZMRequestAvailableNotification notifyNewRequestsAvailable:self];
        [self updateBadgeCount];
        [activity endActivity];
    }];
}

- (void)appWillEnterForeground:(NSNotification *)note
{
    NOT_USED(note);
    ZMBackgroundActivity *activity = [[BackgroundActivityFactory sharedInstance] backgroundActivityWithName:@"enter foreground"];
    [self.notificationDispatcher applicationWillEnterForeground];
    [self.syncMOC performGroupedBlock:^{
        self.applicationStatusDirectory.operationStatus.isInBackground = NO;
        [ZMRequestAvailableNotification notifyNewRequestsAvailable:self];
        [activity endActivity];
    }];
}

- (void)appTerminated:(NSNotification *)note
{
    NOT_USED(note);
    [self.application unregisterObserverForStateChange:self];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (NSManagedObjectContext *)moc
{
    return self.syncMOC;
}

- (void)didEstablishUpdateEventsStream
{
    [self.applicationStatusDirectory.syncStatus pushChannelDidOpen];
}

- (void)didInterruptUpdateEventsStream
{
    [self.applicationStatusDirectory.syncStatus pushChannelDidClose];
}

- (void)tearDown
{
    self.tornDown = YES;
    self.applicationStatusDirectory = nil;
    self.eventDecoder = nil;
    [self.eventMOC tearDown];
    self.eventMOC = nil;
    [self.application unregisterObserverForStateChange:self];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self appTerminated:nil];

    @autoreleasepool {
        for (ZMObjectSyncStrategy *s in self.requestStrategies) {
            if ([s respondsToSelector:@selector((tearDown))]) {
                [s tearDown];
            }
        }
    }
    
    [self.notificationDispatcher tearDown];
    [self.conversationStatusSync tearDown];
}

- (void)processAllEventsInBuffer
{
    [self.eventsBuffer processAllEventsInBuffer];
    [self.syncMOC enqueueDelayedSave];
}


#if DEBUG
- (void)dealloc
{
    RequireString(self.tornDown, "Did not tear down %p", (__bridge void *) self);
}
#endif

- (NSArray *)allChangeTrackers
{
    if (_allChangeTrackers == nil) {
        _allChangeTrackers = [self.requestStrategies flattenWithBlock:^NSArray *(id <ZMObjectStrategy> objectSync) {
            if ([objectSync conformsToProtocol:@protocol(ZMContextChangeTrackerSource)]) {
                return objectSync.contextChangeTrackers;
            }
            return nil;
        }];
        _allChangeTrackers = [_allChangeTrackers arrayByAddingObject:self.conversationStatusSync];
        _allChangeTrackers = [_allChangeTrackers arrayByAddingObject:self.applicationStatusDirectory.userProfileImageUpdateStatus];
    }
    
    return _allChangeTrackers;
}

- (NSArray<id<ZMEventConsumer>> *)eventConsumers
{
    if (_eventConsumers == nil) {
        NSMutableArray<id<ZMEventConsumer>> *eventConsumers = [NSMutableArray array];
        
        for (id<ZMObjectStrategy> objectStrategy in self.requestStrategies) {
            if ([objectStrategy conformsToProtocol:@protocol(ZMEventConsumer)]) {
                [eventConsumers addObject:objectStrategy];
            }
        }
        
        [eventConsumers addObject:self.systemMessageEventConsumer];
        _eventConsumers = eventConsumers;
    }
    
    return _eventConsumers;
}

- (ZMTransportRequest *)nextRequest
{
    dispatch_once(&_didFetchObjects, ^{
        [self.changeTrackerBootStrap fetchObjectsForChangeTrackers];
    });
    
    if(self.tornDown) {
        return nil;
    }
    
    return [self.requestStrategies firstNonNilReturnedFromSelector:@selector(nextRequest)];;
}

- (ZMFetchRequestBatch *)fetchRequestBatchForEvents:(NSArray<ZMUpdateEvent *> *)events
{
    NSMutableSet <NSUUID *>*nonces = [NSMutableSet set];
    NSMutableSet <NSUUID *>*remoteIdentifiers = [NSMutableSet set];
    
    for (id<ZMEventConsumer> obj in self.requestStrategies) {
        @autoreleasepool {
            if ([obj respondsToSelector:@selector(messageNoncesToPrefetchToProcessEvents:)]) {
                [nonces unionSet:[obj messageNoncesToPrefetchToProcessEvents:events]];
            }
            if ([obj respondsToSelector:@selector(conversationRemoteIdentifiersToPrefetchToProcessEvents:)]) {
                [remoteIdentifiers unionSet:[obj conversationRemoteIdentifiersToPrefetchToProcessEvents:events]];
            }
        }
    }
    
    ZMFetchRequestBatch *fetchRequestBatch = [[ZMFetchRequestBatch alloc] init];
    [fetchRequestBatch addNoncesToPrefetchMessages:nonces];
    [fetchRequestBatch addConversationRemoteIdentifiersToPrefetchConversations:remoteIdentifiers];
    
    return fetchRequestBatch;
}

- (void)transportSessionAccessTokenDidSucceedWithToken:(NSString *)token ofType:(NSString *)type;
{
    [self.callFlowRequestStrategy accessTokenDidChangeWithToken:token ofType:type];
}

- (void)updateBadgeCount;
{
    self.application.applicationIconBadgeNumber = (NSInteger)[ZMConversation unreadConversationCountInContext:self.syncMOC];
}

- (ZMGSMCallHandler *)gsmCallHandler
{
    return self.callStateRequestStrategy.gsmCallHandler;
}


@end


@implementation ZMSyncStrategy (SyncStateDelegate)

- (void)didStartSync
{
    [self.syncStateDelegate didStartSync];
}

- (void)didFinishSync
{
    [self processAllEventsInBuffer];
    [self.hotFix applyPatches];
    [self.syncStateDelegate didFinishSync];
}

- (void)didRegisterUserClient:(UserClient *)userClient
{
    [self.syncStateDelegate didRegisterUserClient:userClient];
}

@end


