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
#import "ZMCallFlowRequestStrategy.h"
#import "WireSyncEngineLogs.h"
#import "ZMClientRegistrationStatus.h"
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
@property (nonatomic) ZMCallFlowRequestStrategy *callFlowRequestStrategy;
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


- (instancetype)initWithStoreProvider:(id<LocalStoreProviderProtocol>)storeProvider
                        cookieStorage:(ZMPersistentCookieStorage *)cookieStorage
                         mediaManager:(AVSMediaManager *)mediaManager
                          flowManager:(id<FlowManagerType>)flowManager
                    syncStateDelegate:(id<ZMSyncStateDelegate>)syncStateDelegate
         localNotificationsDispatcher:(LocalNotificationDispatcher *)localNotificationsDispatcher
             taskCancellationProvider:(id <ZMRequestCancellation>)taskCancellationProvider
                          application:(id<ZMApplication>)application
{
    self = [super init];
    if (self) {
        self.syncStateDelegate = syncStateDelegate;
        self.notificationDispatcher = [[NotificationDispatcher alloc] initWithManagedObjectContext: storeProvider.contextDirectory.uiContext];
        self.application = application;
        self.localNotificationDispatcher = localNotificationsDispatcher;
        self.syncMOC = storeProvider.contextDirectory.syncContext;
        self.uiMOC = storeProvider.contextDirectory.uiContext;
        self.hotFix = [[ZMHotFix alloc] initWithSyncMOC:self.syncMOC];

        self.eventMOC = [NSManagedObjectContext createEventContextWithSharedContainerURL:storeProvider.applicationContainer userIdentifier:storeProvider.userIdentifier];
        [self.eventMOC addGroup:self.syncMOC.dispatchGroup];
        
        self.applicationStatusDirectory = [[ZMApplicationStatusDirectory alloc] initWithManagedObjectContext:self.syncMOC
                                                                                               cookieStorage:cookieStorage
                                                                                         requestCancellation:taskCancellationProvider
                                                                                                 application:application
                                                                                           syncStateDelegate:self];
        
        [self createTranscodersWithLocalNotificationsDispatcher:localNotificationsDispatcher mediaManager:mediaManager flowManager:flowManager];
        
        self.eventsBuffer = [[ZMUpdateEventsBuffer alloc] initWithUpdateEventConsumer:self];
        self.userClientRequestStrategy = [[UserClientRequestStrategy alloc] initWithClientRegistrationStatus:self.applicationStatusDirectory.clientRegistrationStatus
                                                                                          clientUpdateStatus:self.applicationStatusDirectory.clientUpdateStatus
                                                                                                     context:self.syncMOC
                                                                                               userKeysStore:self.syncMOC.zm_cryptKeyStore];
        self.missingClientsRequestStrategy = [[MissingClientsRequestStrategy alloc] initWithManagedObjectContext:self.syncMOC applicationStatus:self.applicationStatusDirectory];
        self.fetchingClientRequestStrategy = [[FetchingClientRequestStrategy alloc] initWithManagedObjectContext:self.syncMOC applicationStatus:self.applicationStatusDirectory];
        
        self.requestStrategies = @[
                                   self.userClientRequestStrategy,
                                   self.missingClientsRequestStrategy,
                                   self.missingUpdateEventsTranscoder,
                                   self.fetchingClientRequestStrategy,
                                   [[ProxiedRequestStrategy alloc] initWithManagedObjectContext:self.syncMOC applicationStatus:self.applicationStatusDirectory requestsStatus:self.applicationStatusDirectory.proxiedRequestStatus],
                                   [[DeleteAccountRequestStrategy alloc] initWithManagedObjectContext:self.syncMOC applicationStatus:self.applicationStatusDirectory cookieStorage: cookieStorage],
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
                                   [[UserImageStrategy alloc] initWithManagedObjectContext:self.syncMOC applicationStatus:self.applicationStatusDirectory],
                                   [[LinkPreviewUploadRequestStrategy alloc] initWithManagedObjectContext:self.syncMOC applicationStatus:self.applicationStatusDirectory],
                                   self.selfStrategy,
                                   self.callingRequestStrategy,
                                   self.callFlowRequestStrategy,
                                   [[GenericMessageNotificationRequestStrategy alloc] initWithManagedObjectContext:self.syncMOC clientRegistrationDelegate:self.applicationStatusDirectory.clientRegistrationStatus],
                                   [[UserImageAssetUpdateStrategy alloc] initWithManagedObjectContext:self.syncMOC applicationStatusDirectory:self.applicationStatusDirectory],
                                   [[TeamDownloadRequestStrategy alloc] initWithManagedObjectContext:self.syncMOC applicationStatus:self.applicationStatusDirectory syncStatus:self.applicationStatusDirectory.syncStatus],
                                   [[TeamSyncRequestStrategy alloc] initWithManagedObjectContext:self.syncMOC applicationStatus:self.applicationStatusDirectory syncStatus:self.applicationStatusDirectory.syncStatus],
                                   [[MemberDownloadRequestStrategy alloc] initWithManagedObjectContext:self.syncMOC applicationStatus:self.applicationStatusDirectory],
                                   [[PermissionsDownloadRequestStrategy alloc] initWithManagedObjectContext:self.syncMOC applicationStatus:self.applicationStatusDirectory]
                                   ];
        
        self.changeTrackerBootStrap = [[ZMChangeTrackerBootstrap alloc] initWithManagedObjectContext:self.syncMOC changeTrackers:self.allChangeTrackers];

        ZM_ALLOW_MISSING_SELECTOR([[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(managedObjectContextDidSave:) name:NSManagedObjectContextDidSaveNotification object:self.syncMOC]);
        ZM_ALLOW_MISSING_SELECTOR([[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(managedObjectContextDidSave:) name:NSManagedObjectContextDidSaveNotification object:storeProvider.contextDirectory.uiContext]);

        [application registerObserverForDidEnterBackground:self selector:@selector(appDidEnterBackground:)];
        [application registerObserverForWillEnterForeground:self selector:@selector(appWillEnterForeground:)];
        [application registerObserverForApplicationWillTerminate:self selector:@selector(appTerminated:)];
    }
    return self;
}

- (void)createTranscodersWithLocalNotificationsDispatcher:(LocalNotificationDispatcher *)localNotificationsDispatcher
                                             mediaManager:(AVSMediaManager *)mediaManager
                                              flowManager:(id<FlowManagerType>)flowManager
{
    self.eventDecoder = [[EventDecoder alloc] initWithEventMOC:self.eventMOC syncMOC:self.syncMOC];
    self.connectionTranscoder = [[ZMConnectionTranscoder alloc] initWithManagedObjectContext:self.syncMOC applicationStatus:self.applicationStatusDirectory syncStatus:self.applicationStatusDirectory.syncStatus];
    self.userTranscoder = [[ZMUserTranscoder alloc] initWithManagedObjectContext:self.syncMOC applicationStatus:self.applicationStatusDirectory syncStatus:self.applicationStatusDirectory.syncStatus];
    self.selfStrategy = [[ZMSelfStrategy alloc] initWithManagedObjectContext:self.syncMOC applicationStatus:self.applicationStatusDirectory clientRegistrationStatus:self.applicationStatusDirectory.clientRegistrationStatus syncStatus:self.applicationStatusDirectory.syncStatus];
    self.conversationTranscoder = [[ZMConversationTranscoder alloc] initWithSyncStrategy:self applicationStatus:self.applicationStatusDirectory syncStatus:self.applicationStatusDirectory.syncStatus];
    self.systemMessageEventConsumer = [[SystemMessageEventsConsumer alloc] initWithMoc:self.syncMOC localNotificationDispatcher:localNotificationsDispatcher];
    self.clientMessageTranscoder = [[ClientMessageTranscoder alloc] initIn:self.syncMOC localNotificationDispatcher:localNotificationsDispatcher applicationStatus:self.applicationStatusDirectory];
    self.missingUpdateEventsTranscoder = [[ZMMissingUpdateEventsTranscoder alloc] initWithSyncStrategy:self previouslyReceivedEventIDsCollection:self.eventDecoder application:self.application backgroundAPNSPingbackStatus:self.applicationStatusDirectory.pingBackStatus syncStatus:self.applicationStatusDirectory.syncStatus];
    self.lastUpdateEventIDTranscoder = [[ZMLastUpdateEventIDTranscoder alloc] initWithManagedObjectContext:self.syncMOC applicationStatus:self.applicationStatusDirectory syncStatus:self.applicationStatusDirectory.syncStatus objectDirectory:self];
    self.callFlowRequestStrategy = [[ZMCallFlowRequestStrategy alloc] initWithMediaManager:mediaManager flowManager:flowManager managedObjectContext:self.syncMOC applicationStatus:self.applicationStatusDirectory application:self.application];
    self.callingRequestStrategy = [[CallingRequestStrategy alloc] initWithManagedObjectContext:self.syncMOC clientRegistrationDelegate:self.applicationStatusDirectory.clientRegistrationStatus flowManager:flowManager];
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
    self.localNotificationDispatcher = nil;
    self.applicationStatusDirectory = nil;
    self.connectionTranscoder = nil;
    self.missingUpdateEventsTranscoder = nil;
    self.changeTrackerBootStrap = nil;
    self.callingRequestStrategy = nil;
    self.callFlowRequestStrategy = nil;
    self.connectionTranscoder = nil;
    self.conversationTranscoder = nil;
    self.eventsBuffer = nil;
    self.userTranscoder = nil;
    self.selfStrategy = nil;
    self.clientMessageTranscoder = nil;
    self.lastUpdateEventIDTranscoder = nil;
    self.systemMessageEventConsumer = nil;
    self.allChangeTrackers = nil;
    self.eventDecoder = nil;
    [self.eventMOC tearDownEventMOC];
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
    self.requestStrategies = nil;
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


