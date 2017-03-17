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
#import "ZMUserSession.h"
#import "ZMUserSession+Internal.h"
#import "ZMConnectionTranscoder.h"
#import "ZMUserTranscoder.h"
#import "ZMSelfTranscoder.h"
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
#import "ZMessagingLogs.h"
#import "ZMClientRegistrationStatus.h"
#import "ZMOnDemandFlowManager.h"
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
@property (nonatomic) ZMSelfTranscoder *selfTranscoder;
@property (nonatomic) ZMConversationTranscoder *conversationTranscoder;
@property (nonatomic) SystemMessageEventsConsumer *systemMessageEventConsumer;
@property (nonatomic) ClientMessageTranscoder *clientMessageTranscoder;
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
@property (nonatomic) FetchingClientRequestStrategy *fetchingClientRequestStrategy;
@property (nonatomic) MissingClientsRequestStrategy *missingClientsRequestStrategy;
@property (nonatomic) FileUploadRequestStrategy *fileUploadRequestStrategy;
@property (nonatomic) LinkPreviewAssetDownloadRequestStrategy *linkPreviewAssetDownloadRequestStrategy;
@property (nonatomic) PushTokenStrategy *pushTokenStrategy;
@property (nonatomic) SearchUserImageStrategy *searchUserImageStrategy;

@property (nonatomic, readwrite) CallingRequestStrategy *callingRequestStrategy;

@property (nonatomic) NSManagedObjectContext *eventMOC;
@property (nonatomic) EventDecoder *eventDecoder;
@property (nonatomic, weak) LocalNotificationDispatcher *localNotificationDispatcher;
@property (nonatomic) BackgroundAPNSConfirmationStatus *apnsConfirmationStatus;

@property (nonatomic) NSArray *allChangeTrackers;

@property (nonatomic) NSArray<ZMObjectSyncStrategy *> *requestStrategies;

@property (atomic) BOOL tornDown;
@property (nonatomic) BOOL contextMergingDisabled;

@property (nonatomic, weak) ZMAuthenticationStatus *authenticationStatus;
@property (nonatomic, weak) ZMClientRegistrationStatus *clientRegistrationStatus;
@property (nonatomic) NotificationDispatcher *notificationDispatcher;

@end

@interface BackgroundAPNSConfirmationStatus (Protocol) <DeliveryConfirmationDelegate>
@end

@interface ZMClientRegistrationStatus (Protocol) <ClientRegistrationDelegate>

@end

@implementation ZMSyncStrategy

ZM_EMPTY_ASSERTING_INIT()


- (instancetype)initWithAuthenticationCenter:(ZMAuthenticationStatus *)authenticationStatus
                     userProfileUpdateStatus:(UserProfileUpdateStatus *)userProfileStatus
                    clientRegistrationStatus:(ZMClientRegistrationStatus *)clientRegistrationStatus
                          clientUpdateStatus:(ClientUpdateStatus *)clientUpdateStatus
                        proxiedRequestStatus:(ProxiedRequestsStatus *)proxiedRequestStatus
                               accountStatus:(ZMAccountStatus *)accountStatus
                backgroundAPNSPingBackStatus:(BackgroundAPNSPingBackStatus *)backgroundAPNSPingBackStatus
                                mediaManager:(id<AVSMediaManager>)mediaManager
                         onDemandFlowManager:(ZMOnDemandFlowManager *)onDemandFlowManager
                                     syncMOC:(NSManagedObjectContext *)syncMOC
                                       uiMOC:(NSManagedObjectContext *)uiMOC
                           syncStateDelegate:(id<ZMSyncStateDelegate>)syncStateDelegate
                       backgroundableSession:(id<ZMBackgroundable>)backgroundableSession
                localNotificationsDispatcher:(LocalNotificationDispatcher *)localNotificationsDispatcher
                    taskCancellationProvider:(id <ZMRequestCancellation>)taskCancellationProvider
                          appGroupIdentifier:(NSString *)appGroupIdentifier
                                 application:(id<ZMApplication>)application;

{
    self = [super init];
    if (self) {
        self.notificationDispatcher = [[NotificationDispatcher alloc] initWithManagedObjectContext: uiMOC];
        self.application = application;
        self.localNotificationDispatcher = localNotificationsDispatcher;
        self.authenticationStatus = authenticationStatus;
        self.clientRegistrationStatus = clientRegistrationStatus;
        self.syncMOC = syncMOC;
        self.uiMOC = uiMOC;
        self.eventMOC = [NSManagedObjectContext createEventContextWithAppGroupIdentifier:appGroupIdentifier];
        [self.eventMOC addGroup:self.syncMOC.dispatchGroup];
        self.apnsConfirmationStatus = [[BackgroundAPNSConfirmationStatus alloc] initWithApplication:application
                                                                               managedObjectContext:self.syncMOC
                                                                          backgroundActivityFactory:[BackgroundActivityFactory sharedInstance]];
        
        [self createTranscodersWithClientRegistrationStatus:clientRegistrationStatus
                               localNotificationsDispatcher:localNotificationsDispatcher
                                       authenticationStatus:authenticationStatus
                               backgroundAPNSPingBackStatus:backgroundAPNSPingBackStatus
                                              accountStatus:accountStatus
                                               mediaManager:mediaManager
                                        onDemandFlowManager:onDemandFlowManager
                                   taskCancellationProvider:taskCancellationProvider];
        
        self.stateMachine = [[ZMSyncStateMachine alloc] initWithAuthenticationStatus:authenticationStatus
                                                            clientRegistrationStatus:clientRegistrationStatus
                                                             objectStrategyDirectory:self
                                                                   syncStateDelegate:syncStateDelegate
                                                               backgroundableSession:backgroundableSession
                                                                         application:application
                             ];

        self.eventsBuffer = [[ZMUpdateEventsBuffer alloc] initWithUpdateEventConsumer:self];
        self.userClientRequestStrategy = [[UserClientRequestStrategy alloc] initWithAuthenticationStatus:authenticationStatus
                                                                                clientRegistrationStatus:clientRegistrationStatus
                                                                                      clientUpdateStatus:clientUpdateStatus
                                                                                                 context:self.syncMOC
                                                                                                userKeysStore:self.syncMOC.zm_cryptKeyStore
                                          ];
        self.fetchingClientRequestStrategy = [[FetchingClientRequestStrategy alloc] initWithClientRegistrationStatus:clientRegistrationStatus managedObjectContext:self.syncMOC];
        self.missingClientsRequestStrategy = [[MissingClientsRequestStrategy alloc] initWithClientRegistrationStatus:clientRegistrationStatus apnsConfirmationStatus: self.apnsConfirmationStatus managedObjectContext:self.syncMOC];
        
        NSOperationQueue *imageProcessingQueue = [ZMImagePreprocessor createSuitableImagePreprocessingQueue];
        self.requestStrategies = @[
                                   self.userClientRequestStrategy,
                                   self.missingClientsRequestStrategy,
                                   self.missingUpdateEventsTranscoder,
                                   self.fetchingClientRequestStrategy,
                                   self.clientMessageTranscoder,
                                   [[ProxiedRequestStrategy alloc] initWithRequestsStatus:proxiedRequestStatus
                                                                     managedObjectContext:self.syncMOC],
                                   [[DeleteAccountRequestStrategy alloc] initWithAuthStatus:authenticationStatus
                                                                       managedObjectContext:self.syncMOC],
                                   [[AssetDownloadRequestStrategy alloc] initWithAuthStatus:clientRegistrationStatus
                                                                   taskCancellationProvider:taskCancellationProvider
                                                                       managedObjectContext:self.syncMOC],
                                   [[AssetV3DownloadRequestStrategy alloc] initWithAuthStatus:clientRegistrationStatus
                                                                     taskCancellationProvider:taskCancellationProvider
                                                                         managedObjectContext:self.syncMOC],
                                   [[AssetClientMessageRequestStrategy alloc] initWithClientRegistrationStatus:clientRegistrationStatus
                                                                                          managedObjectContext:self.syncMOC],
                                   [[AssetV3ImageUploadRequestStrategy alloc] initWithClientRegistrationStatus:clientRegistrationStatus
                                                                                      taskCancellationProvider:taskCancellationProvider
                                                                                          managedObjectContext:self.syncMOC],
                                   [[AssetV3PreviewDownloadRequestStrategy alloc] initWithAuthStatus:clientRegistrationStatus
                                                                                managedObjectContext:self.syncMOC],
                                   [[AssetV3FileUploadRequestStrategy alloc] initWithClientRegistrationStatus:clientRegistrationStatus
                                                                       taskCancellationProvider:taskCancellationProvider
                                                                           managedObjectContext:self.syncMOC],
                                   [[AddressBookUploadRequestStrategy alloc] initWithAuthenticationStatus:authenticationStatus
                                                                                 clientRegistrationStatus:clientRegistrationStatus
                                                                                                      moc:self.syncMOC],
                                   [[UserProfileRequestStrategy alloc] initWithManagedObjectContext:self.syncMOC
                                                                            userProfileUpdateStatus:userProfileStatus
                                                                               authenticationStatus:authenticationStatus],
                                   [[SelfContactCardUploadStrategy alloc] initWithAuthenticationStatus:authenticationStatus
                                                                              clientRegistrationStatus:clientRegistrationStatus
                                                                                  managedObjectContext:self.syncMOC],
                                   self.fileUploadRequestStrategy,
                                   self.linkPreviewAssetDownloadRequestStrategy,
                                   self.linkPreviewAssetUploadRequestStrategy,
                                   self.imageDownloadRequestStrategy,
                                   self.imageUploadRequestStrategy,
                                   self.callingRequestStrategy,
                                   [[PushTokenStrategy alloc] initWithManagedObjectContext:self.syncMOC clientRegistrationDelegate:clientRegistrationStatus],
                                   [[TypingStrategy alloc] initWithManagedObjectContext:self.syncMOC clientRegistrationDelegate:clientRegistrationStatus],
                                   [[SearchUserImageStrategy alloc] initWithManagedObjectContext:self.syncMOC clientRegistrationDelegate:clientRegistrationStatus],
                                   [[UserImageStrategy alloc] initWithManagedObjectContext:self.syncMOC imageProcessingQueue:imageProcessingQueue clientRegistrationDelegate:clientRegistrationStatus],
                                   [[LinkPreviewUploadRequestStrategy alloc] initWithManagedObjectContext:self.syncMOC clientRegistrationDelegate:clientRegistrationStatus],
                                   [[GenericMessageNotificationRequestStrategy alloc] initWithManagedObjectContext:self.syncMOC clientRegistrationDelegate:clientRegistrationStatus]
                                   ];

        self.changeTrackerBootStrap = [[ZMChangeTrackerBootstrap alloc] initWithManagedObjectContext:self.syncMOC changeTrackers:self.allChangeTrackers];

        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(managedObjectContextDidSave:) name:NSManagedObjectContextDidSaveNotification object:self.syncMOC];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(managedObjectContextDidSave:) name:NSManagedObjectContextDidSaveNotification object:uiMOC];

        [application registerObserverForDidEnterBackground:self selector:@selector(appDidEnterBackground:)];
        [application registerObserverForWillEnterForeground:self selector:@selector(appWillEnterForeground:)];
        [application registerObserverForApplicationWillTerminate:self selector:@selector(appTerminated:)];
    }
    return self;
}

- (void)createTranscodersWithClientRegistrationStatus:(ZMClientRegistrationStatus *)clientRegistrationStatus
                         localNotificationsDispatcher:(LocalNotificationDispatcher *)localNotificationsDispatcher
                                 authenticationStatus:(ZMAuthenticationStatus *)authenticationStatus
                         backgroundAPNSPingBackStatus:(BackgroundAPNSPingBackStatus *)backgroundAPNSPingBackStatus
                                        accountStatus:(ZMAccountStatus *)accountStatus
                                         mediaManager:(id<AVSMediaManager>)mediaManager
                                  onDemandFlowManager:(ZMOnDemandFlowManager *)onDemandFlowManager
                             taskCancellationProvider:(id <ZMRequestCancellation>)taskCancellationProvider
{
    NSManagedObjectContext *uiMOC = self.uiMOC;

    self.eventDecoder = [[EventDecoder alloc] initWithEventMOC:self.eventMOC syncMOC:self.syncMOC];
    self.connectionTranscoder = [[ZMConnectionTranscoder alloc] initWithManagedObjectContext:self.syncMOC];
    self.userTranscoder = [[ZMUserTranscoder alloc] initWithManagedObjectContext:self.syncMOC];
    self.selfTranscoder = [[ZMSelfTranscoder alloc] initWithClientRegistrationStatus:clientRegistrationStatus managedObjectContext:self.syncMOC];
    self.conversationTranscoder = [[ZMConversationTranscoder alloc] initWithManagedObjectContext:self.syncMOC authenticationStatus:authenticationStatus accountStatus:accountStatus syncStrategy:self];
    self.systemMessageEventConsumer = [[SystemMessageEventsConsumer alloc] initWithMoc:self.syncMOC localNotificationDispatcher:localNotificationsDispatcher];
    self.clientMessageTranscoder = [[ClientMessageTranscoder alloc] initIn:self.syncMOC localNotificationDispatcher:localNotificationsDispatcher clientRegistrationStatus:clientRegistrationStatus apnsConfirmationStatus:self.apnsConfirmationStatus];
    self.registrationTranscoder = [[ZMRegistrationTranscoder alloc] initWithManagedObjectContext:self.syncMOC authenticationStatus:authenticationStatus];
    self.missingUpdateEventsTranscoder = [[ZMMissingUpdateEventsTranscoder alloc] initWithSyncStrategy:self previouslyReceivedEventIDsCollection:self.eventDecoder application:self.application backgroundAPNSPingbackStatus:backgroundAPNSPingBackStatus];
    self.lastUpdateEventIDTranscoder = [[ZMLastUpdateEventIDTranscoder alloc] initWithManagedObjectContext:self.syncMOC objectDirectory:self];
    self.flowTranscoder = [[ZMFlowSync alloc] initWithMediaManager:mediaManager onDemandFlowManager:onDemandFlowManager syncManagedObjectContext:self.syncMOC uiManagedObjectContext:uiMOC application:self.application];
    self.callingRequestStrategy = [[CallingRequestStrategy alloc] initWithManagedObjectContext:self.syncMOC clientRegistrationDelegate:clientRegistrationStatus];
    self.callStateTranscoder = [[ZMCallStateTranscoder alloc] initWithSyncManagedObjectContext:self.syncMOC uiManagedObjectContext:uiMOC objectStrategyDirectory:self];
    self.loginTranscoder = [[ZMLoginTranscoder alloc] initWithManagedObjectContext:self.syncMOC authenticationStatus:authenticationStatus clientRegistrationStatus:clientRegistrationStatus];
    self.loginCodeRequestTranscoder = [[ZMLoginCodeRequestTranscoder alloc] initWithManagedObjectContext:self.syncMOC authenticationStatus:authenticationStatus];
    self.phoneNumberVerificationTranscoder = [[ZMPhoneNumberVerificationTranscoder alloc] initWithManagedObjectContext:self.syncMOC authenticationStatus:authenticationStatus];
    self.conversationStatusSync = [[ConversationStatusStrategy alloc] initWithManagedObjectContext:self.syncMOC];
    self.fileUploadRequestStrategy = [[FileUploadRequestStrategy alloc] initWithClientRegistrationStatus:clientRegistrationStatus managedObjectContext:self.syncMOC taskCancellationProvider:taskCancellationProvider];
    self.linkPreviewAssetDownloadRequestStrategy = [[LinkPreviewAssetDownloadRequestStrategy alloc] initWithAuthStatus:clientRegistrationStatus managedObjectContext:self.syncMOC];
    self.linkPreviewAssetUploadRequestStrategy = [[LinkPreviewAssetUploadRequestStrategy alloc] initWithClientRegistrationDelegate:clientRegistrationStatus managedObjectContext:self.syncMOC];
    self.imageDownloadRequestStrategy = [[ImageDownloadRequestStrategy alloc] initWithClientRegistrationStatus:clientRegistrationStatus  managedObjectContext:self.syncMOC];
    self.imageUploadRequestStrategy = [[ImageUploadRequestStrategy alloc] initWithClientRegistrationStatus:clientRegistrationStatus managedObjectContext:self.syncMOC];
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
    [self.stateMachine didEstablishUpdateEventsStream];
}

- (void)didInterruptUpdateEventsStream
{
    [self.stateMachine didInterruptUpdateEventsStream];
}

- (void)tearDown
{
    self.tornDown = YES;
    [self.apnsConfirmationStatus tearDown];
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


- (void)logDidSaveNotification:(NSNotification *)note;
{
    NSManagedObjectContext * ZM_UNUSED moc = note.object;
    ZMLogWithLevelAndTag(ZMLogLevelDebug, ZMTAG_CORE_DATA, @"<%@: %p> did save. Context type = %@",
               moc.class, moc,
               moc.zm_isUserInterfaceContext ? @"UI" : moc.zm_isSyncContext ? @"Sync" : @"");
    NSSet *inserted = note.userInfo[NSInsertedObjectsKey];
    if (inserted.count > 0) {
        NSString * ZM_UNUSED description = [[inserted.allObjects mapWithBlock:^id(NSManagedObject *mo) {
            return mo.objectID.URIRepresentation;
        }] componentsJoinedByString:@", "];
        ZMLogWithLevelAndTag(ZMLogLevelDebug, ZMTAG_CORE_DATA, @"    Inserted: %@", description);
    }
    NSSet *updated = note.userInfo[NSUpdatedObjectsKey];
    if (updated.count > 0) {
        NSString * ZM_UNUSED description = [[updated.allObjects mapWithBlock:^id(NSManagedObject *mo) {
            return mo.objectID.URIRepresentation;
        }] componentsJoinedByString:@", "];
        ZMLogWithLevelAndTag(ZMLogLevelDebug, ZMTAG_CORE_DATA, @"    Updated: %@", description);
    }
    NSSet *deleted = note.userInfo[NSDeletedObjectsKey];
    if (deleted.count > 0) {
        NSString * ZM_UNUSED description = [[deleted.allObjects mapWithBlock:^id(NSManagedObject *mo) {
            return mo.objectID.URIRepresentation;
        }] componentsJoinedByString:@", "];
        ZMLogWithLevelAndTag(ZMLogLevelDebug, ZMTAG_CORE_DATA, @"    Deleted: %@", description);
    }
}

- (void)managedObjectContextDidSave:(NSNotification *)note;
{
    if(self.tornDown || self.contextMergingDisabled) {
        return;
    }
    
    if([ZMSLog getLevelWithTag:ZMTAG_CORE_DATA] == ZMLogLevelDebug) {
        [self logDidSaveNotification:note];
    }
    
    NSManagedObjectContext *mocThatSaved = note.object;
    NSManagedObjectContext *strongUiMoc = self.uiMOC;
    ZMCallState *callStateChanges = mocThatSaved.zm_callState.createCopyAndResetHasChanges;
    NSDictionary *userInfo = [mocThatSaved.userInfo copy];
    
    if (mocThatSaved.zm_isUserInterfaceContext && strongUiMoc != nil) {
        if(mocThatSaved != strongUiMoc) {
            RequireString(mocThatSaved == strongUiMoc, "Not the right MOC!");
        }
        
        NSSet *conversationsWithCallChanges = [callStateChanges allContainedConversationsInContext:strongUiMoc];
        if (conversationsWithCallChanges != nil) {
            [strongUiMoc.wireCallCenterV2 callStateDidChangeWithConversations:conversationsWithCallChanges];
        }
        
        ZM_WEAK(self);
        [self.syncMOC performGroupedBlock:^{
            ZM_STRONG(self);
            if(self == nil || self.tornDown) {
                return;
            }
            [self.syncMOC mergeUserInfoFromUserInfo:userInfo];
            NSSet *changedConversations = [self.syncMOC mergeCallStateChanges:callStateChanges];
            [self.syncMOC mergeChangesFromContextDidSaveNotification:note];
            [self processSaveWithInsertedObjects:[NSSet set] updateObjects:changedConversations];
            [self.syncMOC processPendingChanges]; // We need this because merging sometimes leaves the MOC in a 'dirty' state
        }];
    } else if (mocThatSaved.zm_isSyncContext) {
        RequireString(mocThatSaved == self.syncMOC, "Not the right MOC!");
        
        NSSet<NSManagedObjectID*>* changedObjectsIDs = [self extractManagedObjectIDsFrom:note];

        ZM_WEAK(self);
        [strongUiMoc performGroupedBlock:^{
            ZM_STRONG(self);
            if(self == nil || self.tornDown) {
                return;
            }

            [strongUiMoc mergeUserInfoFromUserInfo:userInfo];
            NSSet *changedConversations = [strongUiMoc mergeCallStateChanges:callStateChanges];
            if (changedConversations != nil) {
                [strongUiMoc.wireCallCenterV2 callStateDidChangeWithConversations: changedConversations];
            }
           
            [strongUiMoc mergeChangesFromContextDidSaveNotification:note];
            
            [strongUiMoc processPendingChanges]; // We need this because merging sometimes leaves the MOC in a 'dirty' state
            [self.notificationDispatcher didMergeChanges:changedObjectsIDs];
        }];
    }
}

- (NSSet<NSManagedObjectID*>*)extractManagedObjectIDsFrom:(NSNotification *)note
{
    NSSet<NSManagedObjectID*>* changedObjectsIDs;
    if (note.userInfo[NSUpdatedObjectsKey] != nil) {
        NSSet<NSManagedObject *>* changedObjects = note.userInfo[NSUpdatedObjectsKey];
        changedObjectsIDs = [changedObjects mapWithBlock:^id(NSManagedObject* obj) {
            return obj.objectID;
        }];
    } else {
        changedObjectsIDs = [NSSet set];
    }
    return changedObjectsIDs;
}

- (BOOL)shouldForwardCallStateChangeDirectlyForNote:(NSNotification *)note
{
    if ([(NSSet *)note.userInfo[NSInsertedObjectsKey] count] == 0 &&
        [(NSSet *)note.userInfo[NSDeletedObjectsKey] count] == 0 &&
        [(NSSet *)note.userInfo[NSUpdatedObjectsKey] count] == 0 &&
        [(NSSet *)note.userInfo[NSRefreshedObjectsKey] count] == 0) {
        return YES;
    }
    return NO;
}

- (NSArray<ZMObjectSyncStrategy *> *)allTranscoders;
{
    return @[
             self.connectionTranscoder,
             self.userTranscoder,
             self.selfTranscoder,
             self.conversationTranscoder,
             self.missingUpdateEventsTranscoder,
             self.lastUpdateEventIDTranscoder,
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

- (BOOL)processSaveWithInsertedObjects:(NSSet *)insertedObjects updateObjects:(NSSet *)updatedObjects
{
    NSSet *allObjects = [NSSet zmSetByCompiningSets:insertedObjects, updatedObjects, nil];

    for(id<ZMContextChangeTracker> tracker in self.allChangeTrackers)
    {
        [tracker objectsDidChange:allObjects];
    }
    
    return YES;
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

- (void)processUpdateEvents:(NSArray *)events ignoreBuffer:(BOOL)ignoreBuffer;
{
    if(ignoreBuffer) {
        [self consumeUpdateEvents:events];
        return;
    }
    
    NSArray *flowEvents = [events filterWithBlock:^BOOL(ZMUpdateEvent* event) {
        return event.isFlowEvent;
    }];
    if(flowEvents.count > 0) {
        [self consumeUpdateEvents:flowEvents];
    }
    NSArray *callstateEvents = [events filterWithBlock:^BOOL(ZMUpdateEvent* event) {
        return event.type == ZMUpdateEventCallState;
    }];
    NSArray *notFlowEvents = [events filterWithBlock:^BOOL(ZMUpdateEvent* event) {
        return !event.isFlowEvent;
    }];
    
    switch(self.stateMachine.updateEventsPolicy) {
        case ZMUpdateEventPolicyIgnore: {
            if(callstateEvents.count > 0) {
                [self consumeUpdateEvents:callstateEvents];
            }
            break;
        }
        case ZMUpdateEventPolicyBuffer: {
            for(ZMUpdateEvent *event in notFlowEvents) {
                [self.eventsBuffer addUpdateEvent:event];
            }
            break;
        }
        case ZMUpdateEventPolicyProcess: {
            if(notFlowEvents.count > 0) {
                [self consumeUpdateEvents:notFlowEvents];
            }
            break;
        }
    }
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

- (void)consumeUpdateEvents:(NSArray<ZMUpdateEvent *>*)events
{
    ZM_WEAK(self);
    [self.eventDecoder processEvents:events block:^(NSArray<ZMUpdateEvent *> * decryptedEvents) {
        ZM_STRONG(self);
        if (self == nil){
            return;
        }
        
        ZMFetchRequestBatch *fetchRequest = [self fetchRequestBatchForEvents:decryptedEvents];
        ZMFetchRequestBatchResult *prefetchResult = [self.syncMOC executeFetchRequestBatchOrAssert:fetchRequest];
        for(id obj in [self eventConsumers]) {
            @autoreleasepool {
                if ([obj conformsToProtocol:@protocol(ZMEventConsumer)]) {
                    [obj processEvents:decryptedEvents liveEvents:YES prefetchResult:prefetchResult];
                }
            }
        }
        [self.localNotificationDispatcher processEvents:decryptedEvents liveEvents:YES prefetchResult:nil];
        [self.syncMOC enqueueDelayedSave];
    }];
}

- (NSArray *)eventConsumers {
    return [[self.allTranscoders arrayByAddingObjectsFromArray:self.requestStrategies]
            arrayByAddingObject:self.systemMessageEventConsumer];
}

- (void)processDownloadedEvents:(NSArray <ZMUpdateEvent *>*)events;
{
    ZM_WEAK(self);
    [self.eventDecoder processEvents:events block:^(NSArray<ZMUpdateEvent *> * decryptedEvents) {
        ZM_STRONG(self);
        if (self  == nil){
            return;
        }
        
        ZMFetchRequestBatch *fetchRequest = [self fetchRequestBatchForEvents:decryptedEvents];
        ZMFetchRequestBatchResult *prefetchResult = [self.moc executeFetchRequestBatchOrAssert:fetchRequest];
        
        for(id<ZMEventConsumer> obj in [self eventConsumers]) {
            @autoreleasepool {
                if ([obj conformsToProtocol:@protocol(ZMEventConsumer)]) {
                    [obj processEvents:decryptedEvents liveEvents:NO prefetchResult:prefetchResult];
                }
            }
        }
    }];
}

- (NSArray *)conversationIdsThatHaveBufferedUpdatesForCallState;
{
    return [[self.eventsBuffer updateEvents] mapWithBlock:^id(ZMUpdateEvent *event) {
        if (event.type == ZMUpdateEventCallState) {
            return event.conversationUUID;
        }
        return nil;
    }];
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
