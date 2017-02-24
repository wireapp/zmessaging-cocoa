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
@import zimages;
@import ZMUtilities;
@import ZMTransport;
@import ZMCDataModel;
@import WireMessageStrategy;
@import WireRequestStrategy;

#import "ZMSyncStrategy+Internal.h"
#import "ZMSyncStrategy+ManagedObjectChanges.h"
#import "ZMSyncStrategy+EventProcessing.h"
#import "ZMSyncStateManager.h"


#import "ZMUserSession+Internal.h"

#import "ZMConnectionTranscoder.h"
#import "ZMUserTranscoder.h"
#import "ZMSelfStrategy.h"
#import "ZMConversationTranscoder.h"
#import "ZMSyncStateMachine.h"
#import "ZMAuthenticationStatus.h"
#import "ZMMissingUpdateEventsTranscoder.h"
#import "ZMLastUpdateEventIDTranscoder.h"
#import "ZMRegistrationTranscoder.h"
#import "ZMCallFlowRequestStrategy.h"
#import "ZMLoginTranscoder.h"
#import "ZMCallStateRequestStrategy.h"
#import "ZMPhoneNumberVerificationTranscoder.h"
#import "ZMLoginCodeRequestTranscoder.h"
#import "ZMClientRegistrationStatus.h"
#import "ZMOnDemandFlowManager.h"
#import "ZMLocalNotificationDispatcher.h"
#import "ZMHotFix.h"

#import <zmessaging/zmessaging-Swift.h>

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
@property (nonatomic) ZMMessageTranscoder *systemMessageTranscoder;
@property (nonatomic) ZMMessageTranscoder *clientMessageTranscoder;
@property (nonatomic) ZMMissingUpdateEventsTranscoder *missingUpdateEventsTranscoder;
@property (nonatomic) ZMLastUpdateEventIDTranscoder *lastUpdateEventIDTranscoder;
@property (nonatomic) ZMRegistrationTranscoder *registrationTranscoder;
@property (nonatomic) ZMPhoneNumberVerificationTranscoder *phoneNumberVerificationTranscoder;
@property (nonatomic) ZMLoginTranscoder *loginTranscoder;
@property (nonatomic) ZMLoginCodeRequestTranscoder *loginCodeRequestTranscoder;
@property (nonatomic) ZMCallFlowRequestStrategy *callFlowRequestStrategy;
@property (nonatomic) ZMCallStateRequestStrategy *callStateRequestStrategy;
@property (nonatomic) LinkPreviewAssetUploadRequestStrategy *linkPreviewAssetUploadRequestStrategy;
@property (nonatomic) ImageUploadRequestStrategy *imageUploadRequestStrategy;
@property (nonatomic) ImageDownloadRequestStrategy *imageDownloadRequestStrategy;

@property (nonatomic) ZMSyncStateMachine *stateMachine;
@property (nonatomic) ZMUpdateEventsBuffer *eventsBuffer;
@property (nonatomic) ZMChangeTrackerBootstrap *changeTrackerBootStrap;
@property (nonatomic) ConversationStatusStrategy *conversationStatusSync;
@property (nonatomic) UserClientRequestStrategy *userClientRequestStrategy;
@property (nonatomic) FetchingClientRequestStrategy *fetchingClientRequestStrategy;
@property (nonatomic) MissingClientsRequestStrategy *missingClientsRequestStrategy;
@property (nonatomic) FileUploadRequestStrategy *fileUploadRequestStrategy;
@property (nonatomic) LinkPreviewAssetDownloadRequestStrategy *linkPreviewAssetDownloadRequestStrategy;
@property (nonatomic) PushTokenStrategy *pushTokenStrategy;
@property (nonatomic) SearchUserImageStrategy *searchUserImageStrategy;

@property (nonatomic) CallingRequestStrategy *callingRequestStrategy;

@property (nonatomic) NSManagedObjectContext *eventMOC;
@property (nonatomic) EventDecoder *eventDecoder;
@property (nonatomic, weak) ZMLocalNotificationDispatcher *localNotificationDispatcher;

// Statuus
@property (nonatomic) ZMSyncStateManager *syncStateManager;
@property (nonatomic) NSArray *allChangeTrackers;

@property (nonatomic) NSArray<ZMObjectSyncStrategy *> *requestStrategies;

@property (atomic) BOOL tornDown;
@property (nonatomic) BOOL contextMergingDisabled;

@property (nonatomic, weak) id<ZMSyncStateDelegate> syncStateDelegate;
@property (nonatomic) ZMHotFix *hotFix;
@property (nonatomic) NotificationDispatcher *notificationDispatcher;

@end


@interface ZMSyncStrategy (Registration) <ZMClientRegistrationStatusDelegate>
@end

@interface ZMLocalNotificationDispatcher (Push) <ZMPushMessageHandler>
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
                          topConversationsDirectory:(TopConversationsDirectory *)topConversationsDirectory
                                       mediaManager:(id<AVSMediaManager>)mediaManager
                                onDemandFlowManager:(ZMOnDemandFlowManager *)onDemandFlowManager
                                  syncStateDelegate:(id<ZMSyncStateDelegate>)syncStateDelegate
                              backgroundableSession:(id<ZMBackgroundable>)backgroundableSession
                       localNotificationsDispatcher:(ZMLocalNotificationDispatcher *)localNotificationsDispatcher
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
        
        self.syncStateManager = [[ZMSyncStateManager alloc] initWithSyncManagedObjectContextMOC:syncMOC cookie:cookie syncStateDelegate:self taskCancellationProvider:taskCancellationProvider application:application];
        
        [self createTranscodersWithLocalNotificationsDispatcher:localNotificationsDispatcher mediaManager:mediaManager onDemandFlowManager:onDemandFlowManager];
        
        self.stateMachine = [[ZMSyncStateMachine alloc] initWithAuthenticationStatus:self.syncStateManager.authenticationStatus
                                                            clientRegistrationStatus:self.syncStateManager.clientRegistrationStatus
                                                             objectStrategyDirectory:self
                                                                   syncStateDelegate:syncStateDelegate
                                                               backgroundableSession:backgroundableSession
                                                                         application:application
                                                                       slowSynStatus:self.syncStateManager.syncStatus];

        self.eventsBuffer = [[ZMUpdateEventsBuffer alloc] initWithUpdateEventConsumer:self];
        self.userClientRequestStrategy = [[UserClientRequestStrategy alloc] initWithAuthenticationStatus:self.syncStateManager.authenticationStatus
                                                                                clientRegistrationStatus:self.syncStateManager.clientRegistrationStatus
                                                                                      clientUpdateStatus:self.syncStateManager.clientUpdateStatus
                                                                                                 context:self.syncMOC
                                                                                           userKeysStore:self.syncMOC.zm_cryptKeyStore];
        self.missingClientsRequestStrategy = [[MissingClientsRequestStrategy alloc] initWithManagedObjectContext:self.syncMOC appStateDelegate:self.syncStateManager];
        self.fetchingClientRequestStrategy = [[FetchingClientRequestStrategy alloc] initWithManagedObjectContext:self.syncMOC appStateDelegate:self.syncStateManager];
        
        NSOperationQueue *imageProcessingQueue = [ZMImagePreprocessor createSuitableImagePreprocessingQueue];
        self.requestStrategies = @[
                                   self.userClientRequestStrategy,
                                   self.missingClientsRequestStrategy,
                                   self.missingUpdateEventsTranscoder,
                                   self.fetchingClientRequestStrategy,
                                   [[ProxiedRequestStrategy alloc] initWithManagedObjectContext:self.syncMOC appStateDelegate:self.syncStateManager requestsStatus:self.syncStateManager.proxiedRequestStatus],
                                   [[DeleteAccountRequestStrategy alloc] initWithManagedObjectContext:self.syncMOC appStateDelegate:self.syncStateManager],
                                   [[AssetDownloadRequestStrategy alloc] initWithManagedObjectContext:self.syncMOC appStateDelegate:self.syncStateManager],
                                   [[AssetV3DownloadRequestStrategy alloc] initWithManagedObjectContext:self.syncMOC appStateDelegate:self.syncStateManager],
                                   [[AssetClientMessageRequestStrategy alloc] initWithManagedObjectContext:self.syncMOC appStateDelegate:self.syncStateManager],
                                   [[AssetV3ImageUploadRequestStrategy alloc] initWithManagedObjectContext:self.syncMOC appStateDelegate:self.syncStateManager],
                                   [[AssetV3PreviewDownloadRequestStrategy alloc] initWithManagedObjectContext:self.syncMOC appStateDelegate:self.syncStateManager],
                                   [[AssetV3FileUploadRequestStrategy alloc] initWithManagedObjectContext:self.syncMOC appStateDelegate:self.syncStateManager],
                                   [[AddressBookUploadRequestStrategy alloc] initWithManagedObjectContext:self.syncMOC appStateDelegate:self.syncStateManager],
                                   [[UserProfileRequestStrategy alloc] initWithManagedObjectContext:self.syncMOC
                                                                            appStateDelegate:self.syncStateManager
                                                                            userProfileUpdateStatus:self.syncStateManager.userProfileUpdateStatus],
                                   [[SelfContactCardUploadStrategy alloc] initWithAuthenticationStatus:self.syncStateManager.authenticationStatus
                                                                              clientRegistrationStatus:self.syncStateManager.clientRegistrationStatus
                                                                                  managedObjectContext:self.syncMOC],
                                   self.fileUploadRequestStrategy,
                                   self.linkPreviewAssetDownloadRequestStrategy,
                                   self.linkPreviewAssetUploadRequestStrategy,
                                   self.imageDownloadRequestStrategy,
                                   self.imageUploadRequestStrategy,
                                   [[PushTokenStrategy alloc] initWithManagedObjectContext:self.syncMOC appStateDelegate:self.syncStateManager],
                                   [[TypingStrategy alloc] initWithAppStateDelegate:self.syncStateManager managedObjectContext:self.syncMOC],
                                   [[SearchUserImageStrategy alloc] initWithAppStateDelegate:self.syncStateManager managedObjectContext:self.syncMOC ],
                                   self.connectionTranscoder,
                                   self.conversationTranscoder,
                                   self.userTranscoder,
                                   self.lastUpdateEventIDTranscoder,
                                   self.missingUpdateEventsTranscoder,
                                   [[UserImageStrategy alloc] initWithManagedObjectContext:self.syncMOC appStateDelegate:self.syncStateManager imageProcessingQueue:imageProcessingQueue],
                                   [[TopConversationsRequestStrategy alloc] initWithManagedObjectContext:uiMOC appStateDelegate:self.syncStateManager conversationDirectory:topConversationsDirectory],
                                   [[LinkPreviewUploadRequestStrategy alloc] initWithManagedObjectContext:self.syncMOC clientRegistrationDelegate:self.syncStateManager.clientRegistrationStatus],
                                   self.selfStrategy,
                                   self.systemMessageTranscoder,
                                   self.clientMessageTranscoder,
                                   self.callingRequestStrategy,
                                   self.callStateRequestStrategy,
                                   self.callFlowRequestStrategy,
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

- (void)createTranscodersWithLocalNotificationsDispatcher:(ZMLocalNotificationDispatcher *)localNotificationsDispatcher
                                         mediaManager:(id<AVSMediaManager>)mediaManager
                                  onDemandFlowManager:(ZMOnDemandFlowManager *)onDemandFlowManager
{
    self.eventDecoder = [[EventDecoder alloc] initWithEventMOC:self.eventMOC syncMOC:self.syncMOC];
    self.connectionTranscoder = [[ZMConnectionTranscoder alloc] initWithManagedObjectContext:self.syncMOC appStateDelegate:self.syncStateManager syncStatus:self.syncStateManager.syncStatus];
    self.userTranscoder = [[ZMUserTranscoder alloc] initWithManagedObjectContext:self.syncMOC appStateDelegate:self.syncStateManager syncStatus:self.syncStateManager.syncStatus];
    self.selfStrategy = [[ZMSelfStrategy alloc] initWithManagedObjectContext:self.syncMOC appStateDelegate:self.syncStateManager clientRegistrationStatus:self.syncStateManager.clientRegistrationStatus];
    self.conversationTranscoder = [[ZMConversationTranscoder alloc] initWithSyncStrategy:self appStateDelegate:self.syncStateManager syncStatus:self.syncStateManager.syncStatus];
    self.systemMessageTranscoder = [ZMMessageTranscoder systemMessageTranscoderWithManagedObjectContext:self.syncMOC appStateDelegate:self.syncStateManager localNotificationDispatcher:localNotificationsDispatcher];
    self.clientMessageTranscoder = [[ZMClientMessageTranscoder alloc] initWithManagedObjectContext:self.syncMOC appStateDelegate:self.syncStateManager localNotificationDispatcher:localNotificationsDispatcher];
    self.registrationTranscoder = [[ZMRegistrationTranscoder alloc] initWithManagedObjectContext:self.syncMOC authenticationStatus:self.syncStateManager.authenticationStatus];
    self.missingUpdateEventsTranscoder = [[ZMMissingUpdateEventsTranscoder alloc] initWithSyncStrategy:self previouslyReceivedEventIDsCollection:self.eventDecoder application:self.application backgroundAPNSPingbackStatus:self.syncStateManager.pingBackStatus syncStatus:self.syncStateManager.syncStatus];
    self.lastUpdateEventIDTranscoder = [[ZMLastUpdateEventIDTranscoder alloc] initWithManagedObjectContext:self.syncMOC appStateDelegate:self.syncStateManager syncStatus:self.syncStateManager.syncStatus objectDirectory:self];
    self.callFlowRequestStrategy = [[ZMCallFlowRequestStrategy alloc] initWithMediaManager:mediaManager onDemandFlowManager:onDemandFlowManager managedObjectContext:self.syncMOC appStateDelegate:self.syncStateManager application:self.application];
    self.callingRequestStrategy = [[CallingRequestStrategy alloc] initWithManagedObjectContext:self.syncMOC clientRegistrationDelegate:self.syncStateManager.clientRegistrationStatus];
    self.callStateRequestStrategy = [[ZMCallStateRequestStrategy alloc] initWithManagedObjectContext:self.syncMOC appStateDelegate:self.syncStateManager objectStrategyDirectory:self];
    self.loginTranscoder = [[ZMLoginTranscoder alloc] initWithManagedObjectContext:self.syncMOC authenticationStatus:self.syncStateManager.authenticationStatus clientRegistrationStatus:self.syncStateManager.clientRegistrationStatus];
    self.loginCodeRequestTranscoder = [[ZMLoginCodeRequestTranscoder alloc] initWithManagedObjectContext:self.syncMOC authenticationStatus:self.syncStateManager.authenticationStatus];
    self.phoneNumberVerificationTranscoder = [[ZMPhoneNumberVerificationTranscoder alloc] initWithManagedObjectContext:self.syncMOC authenticationStatus:self.syncStateManager.authenticationStatus];
    self.conversationStatusSync = [[ConversationStatusStrategy alloc] initWithManagedObjectContext:self.syncMOC];
    self.fileUploadRequestStrategy = [[FileUploadRequestStrategy alloc] initWithManagedObjectContext:self.syncMOC appStateDelegate:self.syncStateManager];
    self.linkPreviewAssetDownloadRequestStrategy = [[LinkPreviewAssetDownloadRequestStrategy alloc] initWithManagedObjectContext:self.syncMOC appStateDelegate:self.syncStateManager];
    self.linkPreviewAssetUploadRequestStrategy = [[LinkPreviewAssetUploadRequestStrategy alloc] initWithManagedObjectContext:self.syncMOC appStateDelegate:self.syncStateManager linkPreviewPreprocessor:nil previewImagePreprocessor:nil];
    self.imageDownloadRequestStrategy = [[ImageDownloadRequestStrategy alloc] initWithManagedObjectContext:self.syncMOC appStateDelegate:self.syncStateManager];
    self.imageUploadRequestStrategy = [[ImageUploadRequestStrategy alloc] initWithManagedObjectContext:self.syncMOC appStateDelegate:self.syncStateManager maxConcurrentImageOperation:nil];
}

- (void)appDidEnterBackground:(NSNotification *)note
{
    NOT_USED(note);
    ZMBackgroundActivity *activity = [[BackgroundActivityFactory sharedInstance] backgroundActivityWithName:@"enter background"];
    [self.notificationDispatcher applicationDidEnterBackground];
    [self.syncMOC performGroupedBlock:^{
        [self.stateMachine enterBackground];
        [ZMRequestAvailableNotification notifyNewRequestsAvailable:self];
        [self updateBadgeCount];
        [self.syncStateManager.syncStatus didEnterBackground];
        [activity endActivity];
    }];
}

- (void)appWillEnterForeground:(NSNotification *)note
{
    NOT_USED(note);
    ZMBackgroundActivity *activity = [[BackgroundActivityFactory sharedInstance] backgroundActivityWithName:@"enter foreground"];
    [self.notificationDispatcher applicationWillEnterForeground];
    [self.syncMOC performGroupedBlock:^{
        [self.stateMachine enterForeground];
        [ZMRequestAvailableNotification notifyNewRequestsAvailable:self];
        [self.syncStateManager.syncStatus didEnterForeground];
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
    [self.syncStateManager.syncStatus pushChannelDidOpen];
}

- (void)didInterruptUpdateEventsStream
{
    [self.syncStateManager.syncStatus pushChannelDidClose];
}

- (void)tearDown
{
    [self.syncStateManager tearDown];
    self.tornDown = YES;
    self.eventDecoder = nil;
    [self.eventMOC tearDown];
    self.eventMOC = nil;
    [self.stateMachine tearDown];
    [self.application unregisterObserverForStateChange:self];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self appTerminated:nil];

    for (ZMObjectSyncStrategy *s in [self.allTranscoders arrayByAddingObjectsFromArray:self.requestStrategies]) {
        if ([s respondsToSelector:@selector((tearDown))]) {
            [s tearDown];
        }
    }
    [self.notificationDispatcher tearDown];
    [self.conversationStatusSync tearDown];
    [self.fileUploadRequestStrategy tearDown];
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

- (void)startBackgroundFetchWithCompletionHandler:(ZMBackgroundFetchHandler)handler;
{
    [self.stateMachine startBackgroundFetchWithCompletionHandler:handler];
}

- (void)startBackgroundTaskWithCompletionHandler:(ZMBackgroundTaskHandler)handler;
{
    [self.stateMachine startBackgroundTaskWithCompletionHandler:handler];
}

- (NSArray<ZMObjectSyncStrategy *> *)allTranscoders;
{
    return @[
             self.registrationTranscoder,
             self.phoneNumberVerificationTranscoder,
             self.loginCodeRequestTranscoder,
             self.loginTranscoder,
             ];
}

- (NSArray *)allChangeTrackers
{
    if (_allChangeTrackers == nil) {
        _allChangeTrackers = [self.allTranscoders flattenWithBlock:^id(id<ZMObjectStrategy> objectSync) {
            return objectSync.contextChangeTrackers;
        }];
        
        _allChangeTrackers = [_allChangeTrackers arrayByAddingObjectsFromArray:[self.requestStrategies flattenWithBlock:^NSArray *(id <ZMObjectStrategy> objectSync) {
            if ([objectSync conformsToProtocol:@protocol(ZMContextChangeTrackerSource)]) {
                return objectSync.contextChangeTrackers;
            }
            return nil;
        }]];
        _allChangeTrackers = [_allChangeTrackers arrayByAddingObject:self.conversationStatusSync];
    }
    
    return _allChangeTrackers;
}

- (ZMTransportRequest *)nextRequest
{
    dispatch_once(&_didFetchObjects, ^{
        [self.changeTrackerBootStrap fetchObjectsForChangeTrackers];
    });
    
    if(self.tornDown) {
        return nil;
    }

    ZMTransportRequest* request = [self.stateMachine nextRequest];
    if(request == nil) {
        request = [self.requestStrategies firstNonNilReturnedFromSelector:@selector(nextRequest)];
    }
    return request;
}

- (ZMFetchRequestBatch *)fetchRequestBatchForEvents:(NSArray<ZMUpdateEvent *> *)events
{
    NSMutableSet <NSUUID *>*nonces = [NSMutableSet set];
    NSMutableSet <NSUUID *>*remoteIdentifiers = [NSMutableSet set];
    
    NSArray *allObjectStrategies = [self.allTranscoders arrayByAddingObjectsFromArray:self.requestStrategies];
    
    for(id<ZMEventConsumer> obj in allObjectStrategies) {
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

- (void)dataDidChange;
{
    [self.stateMachine dataDidChange];
}

- (void)transportSessionAccessTokenDidSucceedWithToken:(NSString *)token ofType:(NSString *)type;
{
    [self.callFlowRequestStrategy accessTokenDidChangeWithToken:token ofType:type];
}

- (void)updateBadgeCount;
{
    self.application.applicationIconBadgeNumber = (NSInteger)[ZMConversation unreadConversationCountInContext:self.syncMOC];
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


