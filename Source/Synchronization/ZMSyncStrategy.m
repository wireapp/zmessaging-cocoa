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
@import WireRequestStrategy;

#import "ZMSyncStrategy+Internal.h"
#import "ZMSyncStrategy+ManagedObjectChanges.h"
#import "ZMConnectionTranscoder.h"
#import "ZMUserTranscoder.h"
#import "ZMSelfStrategy.h"
#import "ZMConversationTranscoder.h"
#import "ZMAuthenticationStatus.h"
#import "ZMMissingUpdateEventsTranscoder.h"
#import "ZMLastUpdateEventIDTranscoder.h"
#import "WireSyncEngineLogs.h"
#import "ZMClientRegistrationStatus.h"
#import "ZMHotFix.h"
#import <WireSyncEngine/WireSyncEngine-Swift.h>

@interface ZMSyncStrategy ()

@property (nonatomic) BOOL didFetchObjects;
@property (nonatomic) NSManagedObjectContext *syncMOC;
@property (nonatomic, weak) NSManagedObjectContext *uiMOC;

@property (nonatomic) id<ZMApplication> application;

@property (nonatomic) ZMConnectionTranscoder *connectionTranscoder;
@property (nonatomic) ZMUserTranscoder *userTranscoder;
@property (nonatomic) ZMSelfStrategy *selfStrategy;
@property (nonatomic) ZMConversationTranscoder *conversationTranscoder;
@property (nonatomic) ClientMessageTranscoder *clientMessageTranscoder;
@property (nonatomic) ZMMissingUpdateEventsTranscoder *missingUpdateEventsTranscoder;
@property (nonatomic) ZMLastUpdateEventIDTranscoder *lastUpdateEventIDTranscoder;
@property (nonatomic) LinkPreviewAssetUploadRequestStrategy *linkPreviewAssetUploadRequestStrategy;
@property (nonatomic) ImageV2DownloadRequestStrategy *imageV2DownloadRequestStrategy;

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

@property (nonatomic, weak) ApplicationStatusDirectory *applicationStatusDirectory;
@property (nonatomic) NSArray *allChangeTrackers;

@property (nonatomic) NSArray<ZMObjectSyncStrategy *> *requestStrategies;
@property (nonatomic) NSArray<id<ZMEventConsumer>> *eventConsumers;

@property (atomic) BOOL tornDown;
@property (nonatomic) BOOL contextMergingDisabled;

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
                          flowManager:(id<FlowManagerType>)flowManager
         localNotificationsDispatcher:(LocalNotificationDispatcher *)localNotificationsDispatcher
              notificationsDispatcher:(NotificationDispatcher *)notificationsDispatcher
           applicationStatusDirectory:(ApplicationStatusDirectory *)applicationStatusDirectory
                          application:(id<ZMApplication>)application
{
    self = [super init];
    if (self) {
        self.notificationDispatcher = notificationsDispatcher;
        self.application = application;
        self.localNotificationDispatcher = localNotificationsDispatcher;
        self.syncMOC = storeProvider.contextDirectory.syncContext;
        self.uiMOC = storeProvider.contextDirectory.uiContext;
        self.hotFix = [[ZMHotFix alloc] initWithSyncMOC:self.syncMOC];
        self.eventProcessingTracker = [[EventProcessingTracker alloc] init];

        self.eventMOC = [NSManagedObjectContext createEventContextWithSharedContainerURL:storeProvider.applicationContainer userIdentifier:storeProvider.userIdentifier];
        [self.eventMOC addGroup:self.syncMOC.dispatchGroup];
        self.applicationStatusDirectory = applicationStatusDirectory;

        [self createTranscodersWithLocalNotificationsDispatcher:localNotificationsDispatcher flowManager:flowManager applicationStatusDirectory:applicationStatusDirectory];

        self.eventsBuffer = [[ZMUpdateEventsBuffer alloc] initWithUpdateEventConsumer:self];
        self.userClientRequestStrategy = [[UserClientRequestStrategy alloc] initWithClientRegistrationStatus:applicationStatusDirectory.clientRegistrationStatus
                                                                                          clientUpdateStatus:applicationStatusDirectory.clientUpdateStatus
                                                                                                     context:self.syncMOC
                                                                                               userKeysStore:self.syncMOC.zm_cryptKeyStore];
        self.missingClientsRequestStrategy = [[MissingClientsRequestStrategy alloc] initWithManagedObjectContext:self.syncMOC applicationStatus:applicationStatusDirectory];
        self.fetchingClientRequestStrategy = [[FetchingClientRequestStrategy alloc] initWithManagedObjectContext:self.syncMOC applicationStatus:applicationStatusDirectory];

        self.requestStrategies = @[
                                   self.userClientRequestStrategy,
                                   self.missingClientsRequestStrategy,
                                   self.missingUpdateEventsTranscoder,
                                   self.fetchingClientRequestStrategy,
                                   [[VerifyLegalHoldRequestStrategy alloc] initWithManagedObjectContext:self.syncMOC applicationStatus:applicationStatusDirectory],
                                   [[ProxiedRequestStrategy alloc] initWithManagedObjectContext:self.syncMOC applicationStatus:applicationStatusDirectory requestsStatus:applicationStatusDirectory.proxiedRequestStatus],
                                   [[DeleteAccountRequestStrategy alloc] initWithManagedObjectContext:self.syncMOC applicationStatus:applicationStatusDirectory cookieStorage: cookieStorage],
                                   [[AssetV3UploadRequestStrategy alloc] initWithManagedObjectContext:self.syncMOC applicationStatus:applicationStatusDirectory],
                                   [[AssetV2DownloadRequestStrategy alloc] initWithManagedObjectContext:self.syncMOC applicationStatus:applicationStatusDirectory],
                                   [[AssetV3DownloadRequestStrategy alloc] initWithManagedObjectContext:self.syncMOC applicationStatus:applicationStatusDirectory],
                                   [[AssetClientMessageRequestStrategy alloc] initWithManagedObjectContext:self.syncMOC applicationStatus:applicationStatusDirectory],
                                   [[AssetV3PreviewDownloadRequestStrategy alloc] initWithManagedObjectContext:self.syncMOC applicationStatus:applicationStatusDirectory],
                                   self.clientMessageTranscoder,
                                   [[AvailabilityRequestStrategy alloc] initWithManagedObjectContext:self.syncMOC applicationStatus:applicationStatusDirectory],
                                   [[UserPropertyRequestStrategy alloc] initWithManagedObjectContext:self.syncMOC applicationStatus:applicationStatusDirectory],
                                   [[UserProfileRequestStrategy alloc] initWithManagedObjectContext:self.syncMOC
                                                                                  applicationStatus:applicationStatusDirectory
                                                                            userProfileUpdateStatus:applicationStatusDirectory.userProfileUpdateStatus],
                                   self.linkPreviewAssetDownloadRequestStrategy,
                                   self.linkPreviewAssetUploadRequestStrategy,
                                   self.imageV2DownloadRequestStrategy,
                                   [[PushTokenStrategy alloc] initWithManagedObjectContext:self.syncMOC applicationStatus:applicationStatusDirectory analytics:applicationStatusDirectory.analytics],
                                   [[TypingStrategy alloc] initWithApplicationStatus:applicationStatusDirectory managedObjectContext:self.syncMOC],
                                   [[SearchUserImageStrategy alloc] initWithApplicationStatus:applicationStatusDirectory managedObjectContext:self.syncMOC],
                                   self.connectionTranscoder,
                                   self.conversationTranscoder,
                                   self.userTranscoder,
                                   self.lastUpdateEventIDTranscoder,
                                   self.missingUpdateEventsTranscoder,
                                   [[LinkPreviewUploadRequestStrategy alloc] initWithManagedObjectContext:self.syncMOC applicationStatus:applicationStatusDirectory],
                                   self.selfStrategy,
                                   self.callingRequestStrategy,
                                   [[LegalHoldRequestStrategy alloc] initWithManagedObjectContext:self.syncMOC applicationStatus:applicationStatusDirectory syncStatus:applicationStatusDirectory.syncStatus],
                                   [[GenericMessageNotificationRequestStrategy alloc] initWithManagedObjectContext:self.syncMOC clientRegistrationDelegate:applicationStatusDirectory.clientRegistrationStatus],
                                   [[UserImageAssetUpdateStrategy alloc] initWithManagedObjectContext:self.syncMOC applicationStatusDirectory:applicationStatusDirectory],
                                   [[TeamDownloadRequestStrategy alloc] initWithManagedObjectContext:self.syncMOC applicationStatus:applicationStatusDirectory syncStatus:applicationStatusDirectory.syncStatus],
                                   [[TeamRolesDownloadRequestStrategy alloc] initWithManagedObjectContext:self.syncMOC applicationStatus:applicationStatusDirectory syncStatus:applicationStatusDirectory.syncStatus],
                                   [[TeamSyncRequestStrategy alloc] initWithManagedObjectContext:self.syncMOC applicationStatus:applicationStatusDirectory syncStatus:applicationStatusDirectory.syncStatus],
                                   [[TeamMembersDownloadRequestStrategy alloc] initWithManagedObjectContext:self.syncMOC applicationStatus:applicationStatusDirectory syncStatus:applicationStatusDirectory.syncStatus],
                                   [[PermissionsDownloadRequestStrategy alloc] initWithManagedObjectContext:self.syncMOC applicationStatus:applicationStatusDirectory],
                                   [[TeamInvitationRequestStrategy alloc] initWithManagedObjectContext:self.syncMOC applicationStatus:applicationStatusDirectory teamInvitationStatus:applicationStatusDirectory.teamInvitationStatus],
                                   [[AssetDeletionRequestStrategy alloc] initWithManagedObjectContext:self.syncMOC applicationStatus:applicationStatusDirectory identifierProvider:applicationStatusDirectory.assetDeletionStatus],
                                   [[UserRichProfileRequestStrategy alloc] initWithManagedObjectContext:self.syncMOC applicationStatus:applicationStatusDirectory],
                                   [[TeamImageAssetUpdateStrategy alloc] initWithManagedObjectContext:self.syncMOC applicationStatus:applicationStatusDirectory],
                                   [[LabelDownstreamRequestStrategy alloc] initWithManagedObjectContext:self.syncMOC applicationStatus:applicationStatusDirectory syncStatus:applicationStatusDirectory.syncStatus],
                                   [[LabelUpstreamRequestStrategy alloc] initWithManagedObjectContext:self.syncMOC applicationStatus:applicationStatusDirectory],
                                   [[ConversationRoleDownstreamRequestStrategy alloc] initWithManagedObjectContext:self.syncMOC applicationStatus:applicationStatusDirectory],
                                   [[VerifyPasswordRequestStrategy alloc] initWithManagedObjectContext:self.syncMOC applicationStatus:applicationStatusDirectory]
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
                                              flowManager:(id<FlowManagerType>)flowManager
                               applicationStatusDirectory:(ApplicationStatusDirectory *)applicationStatusDirectory
{
    self.eventDecoder = [[EventDecoder alloc] initWithEventMOC:self.eventMOC syncMOC:self.syncMOC];
    self.connectionTranscoder = [[ZMConnectionTranscoder alloc] initWithManagedObjectContext:self.syncMOC applicationStatus:applicationStatusDirectory syncStatus:applicationStatusDirectory.syncStatus];
    self.userTranscoder = [[ZMUserTranscoder alloc] initWithManagedObjectContext:self.syncMOC applicationStatus:applicationStatusDirectory syncStatus:applicationStatusDirectory.syncStatus];
    self.selfStrategy = [[ZMSelfStrategy alloc] initWithManagedObjectContext:self.syncMOC applicationStatus:applicationStatusDirectory clientRegistrationStatus:applicationStatusDirectory.clientRegistrationStatus syncStatus:applicationStatusDirectory.syncStatus];
    self.conversationTranscoder = [[ZMConversationTranscoder alloc] initWithManagedObjectContext:self.syncMOC applicationStatus:applicationStatusDirectory localNotificationDispatcher:self.localNotificationDispatcher syncStatus:applicationStatusDirectory.syncStatus];
    self.clientMessageTranscoder = [[ClientMessageTranscoder alloc] initIn:self.syncMOC localNotificationDispatcher:localNotificationsDispatcher applicationStatus:applicationStatusDirectory];
    self.missingUpdateEventsTranscoder = [[ZMMissingUpdateEventsTranscoder alloc] initWithManagedObjectContext:self.syncMOC
                                                                                          notificationsTracker:nil
                                                                                                eventProcessor:self
                                                                          previouslyReceivedEventIDsCollection:self.eventDecoder
                                                                                             applicationStatus:applicationStatusDirectory
                                                                                        pushNotificationStatus:applicationStatusDirectory.pushNotificationStatus
                                                                                                    syncStatus:applicationStatusDirectory.syncStatus
                                                                                               operationStatus:applicationStatusDirectory.operationStatus];
    self.lastUpdateEventIDTranscoder = [[ZMLastUpdateEventIDTranscoder alloc] initWithManagedObjectContext:self.syncMOC applicationStatus:applicationStatusDirectory syncStatus:applicationStatusDirectory.syncStatus objectDirectory:self];
    self.callingRequestStrategy = [[CallingRequestStrategy alloc] initWithManagedObjectContext:self.syncMOC clientRegistrationDelegate:applicationStatusDirectory.clientRegistrationStatus flowManager:flowManager callEventStatus:applicationStatusDirectory.callEventStatus];
    self.conversationStatusSync = [[ConversationStatusStrategy alloc] initWithManagedObjectContext:self.syncMOC];
    self.linkPreviewAssetDownloadRequestStrategy = [[LinkPreviewAssetDownloadRequestStrategy alloc] initWithManagedObjectContext:self.syncMOC applicationStatus:applicationStatusDirectory];
    self.linkPreviewAssetUploadRequestStrategy = [LinkPreviewAssetUploadRequestStrategy createWithManagedObjectContext:self.syncMOC applicationStatus:applicationStatusDirectory];
    self.imageV2DownloadRequestStrategy = [[ImageV2DownloadRequestStrategy alloc] initWithManagedObjectContext:self.syncMOC applicationStatus:applicationStatusDirectory];
}

- (void)appDidEnterBackground:(NSNotification *)note
{
    NOT_USED(note);
    BackgroundActivity *activity = [BackgroundActivityFactory.sharedFactory startBackgroundActivityWithName:@"enter background"];
    [self.notificationDispatcher applicationDidEnterBackground];
    [self.syncMOC performGroupedBlock:^{
        self.applicationStatusDirectory.operationStatus.isInBackground = YES;
        [ZMRequestAvailableNotification notifyNewRequestsAvailable:self];

        if (activity) {
            [BackgroundActivityFactory.sharedFactory endBackgroundActivity:activity];
        }
    }];
}

- (void)appWillEnterForeground:(NSNotification *)note
{
    NOT_USED(note);
    BackgroundActivity *activity = [BackgroundActivityFactory.sharedFactory startBackgroundActivityWithName:@"enter foreground"];
    [self.notificationDispatcher applicationWillEnterForeground];
    [self.syncMOC performGroupedBlock:^{
        self.applicationStatusDirectory.operationStatus.isInBackground = NO;
        [ZMRequestAvailableNotification notifyNewRequestsAvailable:self];

        if (activity) {
            [BackgroundActivityFactory.sharedFactory endBackgroundActivity:activity];
        }
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

- (void)didFinishSync
{
    [self processAllEventsInBuffer];
    [self.hotFix applyPatches];
}

- (BOOL)isReadyToProcessEvents
{
    return !self.applicationStatusDirectory.syncStatus.isSyncing;
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
    self.connectionTranscoder = nil;
    self.conversationTranscoder = nil;
    self.eventsBuffer = nil;
    self.userTranscoder = nil;
    self.selfStrategy = nil;
    self.clientMessageTranscoder = nil;
    self.lastUpdateEventIDTranscoder = nil;
    self.allChangeTrackers = nil;
    self.eventDecoder = nil;
    [self.eventMOC performGroupedBlockAndWait:^{
        [self.eventMOC tearDownEventMOC];
    }];
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
        
    ApplicationStatusDirectory *statusDirectory = self.applicationStatusDirectory;
        
    [eventConsumers addObject:[[UserClientEventConsumer alloc] initWithManagedObjectContext:self.syncMOC
                                                                   clientRegistrationStatus:statusDirectory.clientRegistrationStatus
                                                                         clientUpdateStatus:statusDirectory.clientUpdateStatus]];

        _eventConsumers = eventConsumers;
    }

    return _eventConsumers;
}

- (ZMTransportRequest *)nextRequest
{
    if (!self.didFetchObjects) {
        self.didFetchObjects = YES;
        [self.changeTrackerBootStrap fetchObjectsForChangeTrackers];
    }

    if(self.tornDown) {
        return nil;
    }

    return [self.requestStrategies firstNonNilReturnedFromSelector:@selector(nextRequest)];
}

@end
