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
#import "ZMFlowSync.h"
#import "ZMLoginTranscoder.h"
#import "ZMCallStateTranscoder.h"
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
@property (nonatomic) ZMFlowSync *flowTranscoder;
@property (nonatomic) ZMCallStateTranscoder *callStateTranscoder;
@property (nonatomic) LinkPreviewAssetUploadRequestStrategy *linkPreviewAssetUploadRequestStrategy;
@property (nonatomic) ImageUploadRequestStrategy *imageUploadRequestStrategy;
@property (nonatomic) ImageDownloadRequestStrategy *imageDownloadRequestStrategy;

@property (nonatomic) ZMSyncStateMachine *stateMachine;
@property (nonatomic) ZMUpdateEventsBuffer *eventsBuffer;
@property (nonatomic) ZMChangeTrackerBootstrap *changeTrackerBootStrap;
@property (nonatomic) ConversationStatusStrategy *conversationStatusSync;
@property (nonatomic) UserClientRequestStrategy *userClientRequestStrategy;
@property (nonatomic) MissingClientsRequestStrategy *missingClientsRequestStrategy;
@property (nonatomic) FileUploadRequestStrategy *fileUploadRequestStrategy;
@property (nonatomic) LinkPreviewAssetDownloadRequestStrategy *linkPreviewAssetDownloadRequestStrategy;
@property (nonatomic) PushTokenStrategy *pushTokenStrategy;
@property (nonatomic) SearchUserImageStrategy *searchUserImageStrategy;

@property (nonatomic) NSManagedObjectContext *eventMOC;
@property (nonatomic) EventDecoder *eventDecoder;
@property (nonatomic, weak) ZMLocalNotificationDispatcher *localNotificationDispatcher;

// Statuus
@property (nonatomic) BackgroundAPNSConfirmationStatus *apnsConfirmationStatus;
@property (nonatomic) ZMAuthenticationStatus *authenticationStatus;
@property (nonatomic) UserProfileUpdateStatus *userProfileUpdateStatus;
@property (nonatomic) ZMClientRegistrationStatus *clientRegistrationStatus;
@property (nonatomic) ClientUpdateStatus *clientUpdateStatus;
@property (nonatomic) BackgroundAPNSPingBackStatus *pingBackStatus;
@property (nonatomic) ZMAccountStatus *accountStatus;
@property (nonatomic) ProxiedRequestsStatus *proxiedRequestStatus;
@property (nonatomic) SyncStatus *syncStatus;


@property (nonatomic) NSArray *allChangeTrackers;

@property (nonatomic) NSArray<ZMObjectSyncStrategy *> *requestStrategies;

@property (atomic) BOOL tornDown;
@property (nonatomic) BOOL contextMergingDisabled;


@property (nonatomic, weak) id<ZMSyncStateDelegate> syncStateDelegate;
@property (nonatomic) ZMHotFix *hotFix;

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
        self.application = application;
        self.localNotificationDispatcher = localNotificationsDispatcher;
        self.syncMOC = syncMOC;
        self.uiMOC = uiMOC;
        self.hotFix = [[ZMHotFix alloc] initWithSyncMOC:self.syncMOC];

        self.eventMOC = [NSManagedObjectContext createEventContextWithAppGroupIdentifier:appGroupIdentifier];
        [self.eventMOC addGroup:self.syncMOC.dispatchGroup];
        
        // Statuus
        self.apnsConfirmationStatus = [[BackgroundAPNSConfirmationStatus alloc] initWithApplication:application
                                                                               managedObjectContext:self.syncMOC
                                                                          backgroundActivityFactory:[BackgroundActivityFactory sharedInstance]];
        self.syncStatus = [[SyncStatus alloc] initWithManagedObjectContext:self.syncMOC syncStateDelegate:self];

        self.authenticationStatus = [[ZMAuthenticationStatus alloc] initWithManagedObjectContext:syncMOC cookie:cookie];
        self.userProfileUpdateStatus = [[UserProfileUpdateStatus alloc] initWithManagedObjectContext:syncMOC];
        self.clientUpdateStatus = [[ClientUpdateStatus alloc] initWithSyncManagedObjectContext:syncMOC];
        
        self.clientRegistrationStatus = [[ZMClientRegistrationStatus alloc] initWithManagedObjectContext:syncMOC
                                                                                 loginCredentialProvider:self.authenticationStatus
                                                                                updateCredentialProvider:self.userProfileUpdateStatus
                                                                                                  cookie:cookie
                                                                              registrationStatusDelegate:self];
        
        self.accountStatus = [[ZMAccountStatus alloc] initWithManagedObjectContext: syncMOC cookieStorage: cookie];
        
        self.pingBackStatus = [[BackgroundAPNSPingBackStatus alloc] initWithSyncManagedObjectContext:syncMOC
                                                                              authenticationProvider:self.authenticationStatus];
        self.proxiedRequestStatus = [[ProxiedRequestsStatus alloc] initWithRequestCancellation:taskCancellationProvider];
        
        [self createTranscodersWithLocalNotificationsDispatcher:localNotificationsDispatcher
                                               mediaManager:mediaManager
                                        onDemandFlowManager:onDemandFlowManager
                                   taskCancellationProvider:taskCancellationProvider];
        
        self.stateMachine = [[ZMSyncStateMachine alloc] initWithAuthenticationStatus:self.authenticationStatus
                                                            clientRegistrationStatus:self.clientRegistrationStatus
                                                             objectStrategyDirectory:self
                                                                   syncStateDelegate:syncStateDelegate
                                                               backgroundableSession:backgroundableSession
                                                                         application:application
                                                                       slowSynStatus:self.syncStatus];

        self.eventsBuffer = [[ZMUpdateEventsBuffer alloc] initWithUpdateEventConsumer:self];
        self.userClientRequestStrategy = [[UserClientRequestStrategy alloc] initWithAuthenticationStatus:self.authenticationStatus
                                                                                clientRegistrationStatus:self.clientRegistrationStatus
                                                                                      clientUpdateStatus:self.clientUpdateStatus
                                                                                                 context:self.syncMOC];
        self.missingClientsRequestStrategy = [[MissingClientsRequestStrategy alloc] initWithClientRegistrationStatus:self.clientRegistrationStatus apnsConfirmationStatus: self.apnsConfirmationStatus managedObjectContext:self.syncMOC];
        
        NSOperationQueue *imageProcessingQueue = [ZMImagePreprocessor createSuitableImagePreprocessingQueue];
        self.requestStrategies = @[
                                   self.userClientRequestStrategy,
                                   self.missingClientsRequestStrategy,
                                   self.missingUpdateEventsTranscoder,
                                   [[ProxiedRequestStrategy alloc] initWithRequestsStatus:self.proxiedRequestStatus
                                                                     managedObjectContext:self.syncMOC],
                                   [[DeleteAccountRequestStrategy alloc] initWithAuthStatus:self.authenticationStatus
                                                                       managedObjectContext:self.syncMOC],
                                   [[AssetDownloadRequestStrategy alloc] initWithAuthStatus:self.clientRegistrationStatus
                                                                   taskCancellationProvider:taskCancellationProvider
                                                                       managedObjectContext:self.syncMOC],
                                   [[AssetV3DownloadRequestStrategy alloc] initWithAuthStatus:self.clientRegistrationStatus
                                                                     taskCancellationProvider:taskCancellationProvider
                                                                         managedObjectContext:self.syncMOC],
                                   [[AssetClientMessageRequestStrategy alloc] initWithClientRegistrationStatus:self.clientRegistrationStatus
                                                                                          managedObjectContext:self.syncMOC],
                                   [[AssetV3ImageUploadRequestStrategy alloc] initWithClientRegistrationStatus:self.clientRegistrationStatus
                                                                                      taskCancellationProvider:taskCancellationProvider
                                                                                          managedObjectContext:self.syncMOC],
                                   [[AssetV3PreviewDownloadRequestStrategy alloc] initWithAuthStatus:self.clientRegistrationStatus
                                                                                managedObjectContext:self.syncMOC],
                                   [[AssetV3FileUploadRequestStrategy alloc] initWithClientRegistrationStatus:self.clientRegistrationStatus
                                                                       taskCancellationProvider:taskCancellationProvider
                                                                           managedObjectContext:self.syncMOC],
                                   [[AddressBookUploadRequestStrategy alloc] initWithAuthenticationStatus:self.authenticationStatus
                                                                                 clientRegistrationStatus:self.clientRegistrationStatus
                                                                                                      moc:self.syncMOC],
                                   [[UserProfileRequestStrategy alloc] initWithManagedObjectContext:self.syncMOC
                                                                            userProfileUpdateStatus:self.userProfileUpdateStatus
                                                                               authenticationStatus:self.authenticationStatus],
                                   self.fileUploadRequestStrategy,
                                   self.linkPreviewAssetDownloadRequestStrategy,
                                   self.linkPreviewAssetUploadRequestStrategy,
                                   self.imageDownloadRequestStrategy,
                                   self.imageUploadRequestStrategy,
                                   [[PushTokenStrategy alloc] initWithManagedObjectContext:self.syncMOC clientRegistrationDelegate:self.clientRegistrationStatus],
                                   [[TypingStrategy alloc] initWithManagedObjectContext:self.syncMOC clientRegistrationDelegate:self.clientRegistrationStatus],
                                   [[SearchUserImageStrategy alloc] initWithManagedObjectContext:self.syncMOC clientRegistrationDelegate:self.clientRegistrationStatus],
                                   self.connectionTranscoder,
                                   self.conversationTranscoder,
                                   self.userTranscoder,
                                   self.lastUpdateEventIDTranscoder,
                                   self.missingUpdateEventsTranscoder,
                                   [[UserImageStrategy alloc] initWithManagedObjectContext:self.syncMOC imageProcessingQueue:imageProcessingQueue clientRegistrationDelegate:self.clientRegistrationStatus],
                                   [[TopConversationsRequestStrategy alloc] initWithManagedObjectContext:uiMOC authenticationStatus:self.authenticationStatus conversationDirectory:topConversationsDirectory],
                                   self.selfStrategy
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
                             taskCancellationProvider:(id <ZMRequestCancellation>)taskCancellationProvider

{
    NSManagedObjectContext *uiMOC = self.uiMOC;
    
    self.eventDecoder = [[EventDecoder alloc] initWithEventMOC:self.eventMOC syncMOC:self.syncMOC];
    self.connectionTranscoder = [[ZMConnectionTranscoder alloc] initWithManagedObjectContext:self.syncMOC syncStatus:self.syncStatus clientRegistrationDelegate:self.clientRegistrationStatus];
    self.userTranscoder = [[ZMUserTranscoder alloc] initWithManagedObjectContext:self.syncMOC syncStatus:self.syncStatus clientRegistrationDelegate:self.clientRegistrationStatus];
    self.selfStrategy = [[ZMSelfStrategy alloc] initWithClientRegistrationStatus:self.clientRegistrationStatus managedObjectContext:self.syncMOC];
    self.conversationTranscoder = [[ZMConversationTranscoder alloc] initWithManagedObjectContext:self.syncMOC authenticationStatus:self.authenticationStatus accountStatus:self.accountStatus syncStrategy:self syncStatus:self.syncStatus clientRegistrationDelegate:self.clientRegistrationStatus];
    self.systemMessageTranscoder = [ZMMessageTranscoder systemMessageTranscoderWithManagedObjectContext:self.syncMOC localNotificationDispatcher:localNotificationsDispatcher];
    self.clientMessageTranscoder = [[ZMClientMessageTranscoder alloc ] initWithManagedObjectContext:self.syncMOC localNotificationDispatcher:localNotificationsDispatcher clientRegistrationStatus:self.clientRegistrationStatus apnsConfirmationStatus: self.apnsConfirmationStatus];
    self.registrationTranscoder = [[ZMRegistrationTranscoder alloc] initWithManagedObjectContext:self.syncMOC authenticationStatus:self.authenticationStatus];
    self.missingUpdateEventsTranscoder = [[ZMMissingUpdateEventsTranscoder alloc] initWithSyncStrategy:self previouslyReceivedEventIDsCollection:self.eventDecoder application:self.application backgroundAPNSPingbackStatus:self.pingBackStatus syncStatus:self.syncStatus clientRegistrationDelegate:self.clientRegistrationStatus];
    self.lastUpdateEventIDTranscoder = [[ZMLastUpdateEventIDTranscoder alloc] initWithManagedObjectContext:self.syncMOC objectDirectory:self syncStatus:self.syncStatus clientRegistrationDelegate:self.clientRegistrationStatus];
    self.flowTranscoder = [[ZMFlowSync alloc] initWithMediaManager:mediaManager onDemandFlowManager:onDemandFlowManager syncManagedObjectContext:self.syncMOC uiManagedObjectContext:uiMOC application:self.application];
    self.callStateTranscoder = [[ZMCallStateTranscoder alloc] initWithSyncManagedObjectContext:self.syncMOC uiManagedObjectContext:uiMOC objectStrategyDirectory:self];
    self.loginTranscoder = [[ZMLoginTranscoder alloc] initWithManagedObjectContext:self.syncMOC authenticationStatus:self.authenticationStatus clientRegistrationStatus:self.clientRegistrationStatus];
    self.loginCodeRequestTranscoder = [[ZMLoginCodeRequestTranscoder alloc] initWithManagedObjectContext:self.syncMOC authenticationStatus:self.authenticationStatus];
    self.phoneNumberVerificationTranscoder = [[ZMPhoneNumberVerificationTranscoder alloc] initWithManagedObjectContext:self.syncMOC authenticationStatus:self.authenticationStatus];
    self.conversationStatusSync = [[ConversationStatusStrategy alloc] initWithManagedObjectContext:self.syncMOC];
    self.fileUploadRequestStrategy = [[FileUploadRequestStrategy alloc] initWithClientRegistrationStatus:self.clientRegistrationStatus managedObjectContext:self.syncMOC taskCancellationProvider:taskCancellationProvider];
    self.linkPreviewAssetDownloadRequestStrategy = [[LinkPreviewAssetDownloadRequestStrategy alloc] initWithAuthStatus:self.clientRegistrationStatus managedObjectContext:self.syncMOC];
    self.linkPreviewAssetUploadRequestStrategy = [[LinkPreviewAssetUploadRequestStrategy alloc] initWithClientRegistrationDelegate:self.clientRegistrationStatus managedObjectContext:self.syncMOC];
    self.imageDownloadRequestStrategy = [[ImageDownloadRequestStrategy alloc] initWithClientRegistrationStatus:self.clientRegistrationStatus  managedObjectContext:self.syncMOC];
    self.imageUploadRequestStrategy = [[ImageUploadRequestStrategy alloc] initWithClientRegistrationStatus:self.clientRegistrationStatus managedObjectContext:self.syncMOC];
}

- (void)appDidEnterBackground:(NSNotification *)note
{
    NOT_USED(note);
    ZMBackgroundActivity *activity = [[BackgroundActivityFactory sharedInstance] backgroundActivityWithName:@"enter background"];
    [self.syncMOC performGroupedBlock:^{
        [self.stateMachine enterBackground];
        [ZMRequestAvailableNotification notifyNewRequestsAvailable:self];
        [self updateBadgeCount];
        [self.syncStatus didEnterBackground];
        [activity endActivity];
    }];
}

- (void)appWillEnterForeground:(NSNotification *)note
{
    NOT_USED(note);
    ZMBackgroundActivity *activity = [[BackgroundActivityFactory sharedInstance] backgroundActivityWithName:@"enter foreground"];
    [self.syncMOC performGroupedBlock:^{
        [self.stateMachine enterForeground];
        [ZMRequestAvailableNotification notifyNewRequestsAvailable:self];
        [self.syncStatus didEnterForeground];
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
    [self.syncStatus pushChannelDidOpen];
}

- (void)didInterruptUpdateEventsStream
{
    [self.syncStatus pushChannelDidClose];
}

- (void)tearDown
{
    self.tornDown = YES;
    [self.apnsConfirmationStatus tearDown];
    [self.clientUpdateStatus tearDown];
    self.clientUpdateStatus = nil;
    [self.clientRegistrationStatus tearDown];
    self.clientRegistrationStatus = nil;
    self.authenticationStatus = nil;
    self.userProfileUpdateStatus = nil;
    self.proxiedRequestStatus = nil;
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
             self.systemMessageTranscoder,
             self.clientMessageTranscoder,
             self.registrationTranscoder,
             self.flowTranscoder,
             self.callStateTranscoder,
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
    
    for(id<ZMObjectStrategy> obj in allObjectStrategies) {
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
    [self.flowTranscoder accessTokenDidChangeWithToken:token ofType:type];
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
    [[NSNotificationCenter defaultCenter] postNotificationName:ZMApplicationDidEnterEventProcessingStateNotificationName object:nil];
}

- (void)didRegisterUserClient:(UserClient *)userClient
{
    [self.syncStateDelegate didRegisterUserClient:userClient];
}

@end


