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
@import ZMUtilities;
@import ZMCDataModel;

#import "ZMFlowSync.h"
#import "ZMAVSBridge.h"
#import <zmessaging/zmessaging-Swift.h>
#import "ZMUserSessionAuthenticationNotification.h"
#import "ZMOnDemandFlowManager.h"
#import "VoiceChannelV2+VideoCalling.h"

static NSString * const DefaultMediaType = @"application/json";
id ZMFlowSyncInternalDeploymentEnvironmentOverride;

static NSString *ZMLogTag ZM_UNUSED = @"Calling";

@interface ZMFlowSync ()

@property (nonatomic, readonly) NSMutableArray *requestStack; ///< inverted FIFO
@property (nonatomic) ZMOnDemandFlowManager *onDemandFlowManager;
@property (nonatomic, readonly) id mediaManager;
@property (nonatomic) NSNotificationQueue *voiceGainNotificationQueue;
@property (nonatomic, copy) NSArray *eventTypesToForward;
@property (nonatomic) BOOL pushChannelIsOpen;
@property (nonatomic, readonly) NSManagedObjectContext *uiManagedObjectContext;
@property (nonatomic) id authenticationObserverToken;
@property (nonatomic, strong) dispatch_queue_t avsLogQueue;
@property (nonatomic) NSMutableSet <ZMConversation*> *conversationsNeedingUpdate;
@property (nonatomic) NSMutableDictionary <NSString *, NSMutableSet<ZMUser*>*> *usersNeedingToBeAdded;
@property (nonatomic) NSMutableSet <ZMUpdateEvent *> *eventsNeedingToBeForwarded;
@property (nonatomic, readonly, weak) id<ZMApplication> application;

@end



@interface ZMFlowSync (FlowManagerDelegate) <AVSFlowManagerDelegate>
@end



@implementation ZMFlowSync

- (instancetype)initWithMediaManager:(id)mediaManager
                 onDemandFlowManager:(ZMOnDemandFlowManager *)onDemandFlowManager
            syncManagedObjectContext:(NSManagedObjectContext *)syncManagedObjectContext
              uiManagedObjectContext:(NSManagedObjectContext *)uiManagedObjectContext
                         application:(id<ZMApplication>)application
{
    self = [super initWithManagedObjectContext:syncManagedObjectContext];
    if(self != nil) {
        _uiManagedObjectContext = uiManagedObjectContext;
        _mediaManager = mediaManager;
        _requestStack = [NSMutableArray array];
        _application = application;
        self.conversationsNeedingUpdate = [NSMutableSet set];
        self.eventsNeedingToBeForwarded = [NSMutableSet set];
        self.usersNeedingToBeAdded = [NSMutableDictionary dictionary];
        self.voiceGainNotificationQueue = [[NSNotificationQueue alloc] initWithNotificationCenter:[NSNotificationCenter defaultCenter]];

        self.onDemandFlowManager = onDemandFlowManager;
        
        [self setUpFlowManagerIfNeeded];
        
        [application registerObserverForDidBecomeActive:self selector:@selector(appDidBecomeActive:)];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(pushChannelDidChange:) name:ZMPushChannelStateChangeNotificationName object:nil];
        ZM_WEAK(self);
        self.authenticationObserverToken = [ZMUserSessionAuthenticationNotification addObserverWithBlock:^(ZMUserSessionAuthenticationNotification *note){
            ZM_STRONG(self);
            if (note.type == ZMAuthenticationNotificationAuthenticationDidSuceeded) {
                [self.managedObjectContext performGroupedBlock:^{
                    [self registerSelfUser];
                }];
            }
        }];
        self.pushChannelIsOpen = NO;
        self.avsLogQueue = dispatch_queue_create("AVSLog", DISPATCH_QUEUE_SERIAL);
    }
    return self;
}

- (void)setUpFlowManagerIfNeeded
{
    [self.onDemandFlowManager initializeFlowManagerWithDelegate:self];
    if (self.eventTypesToForward == nil) {
        [self createEventTypesToForward];
    }
}

- (void)appDidBecomeActive:(NSNotification *)note
{
    NOT_USED(note);
    [self.managedObjectContext performGroupedBlock:^{
        [self setUpFlowManagerIfNeeded];
        [self processBufferedEventsIfNeeded];
    }];
}

- (void)tearDown;
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self.application unregisterObserverForStateChange:self];
    [ZMUserSessionAuthenticationNotification removeObserver:self.authenticationObserverToken];
    [super tearDown];
}

- (AVSFlowManager *)flowManager
{
    return self.onDemandFlowManager.flowManager;
}

- (void)createEventTypesToForward;
{
    NSMutableArray *types = [NSMutableArray array];
    for (NSString *name in self.flowManager.events) {
        ZMUpdateEventType type = [ZMUpdateEvent updateEventTypeForEventTypeString:name];
        if (type != ZMUpdateEventUnknown) {
            [types addObject:@(type)];
        }
    }
    self.eventTypesToForward = [types copy];
}

- (BOOL)isSlowSyncDone
{
    return YES;
}

- (NSArray *)contextChangeTrackers
{
    return @[];
}

- (void)setNeedsSlowSync
{
    // no-op
}

- (NSArray *)requestGenerators;
{
    return @[self];
}

- (ZMTransportRequest *)nextRequest
{
    if (!self.pushChannelIsOpen && ![ZMUserSession useCallKit] && ![self nextRequestIsCallsConfig]) {
        return nil;
    }
    if ((self.application.applicationState != UIApplicationStateBackground && self.flowManager == nil) || [ZMUserSession useCallKit]) {
        [self setUpFlowManagerIfNeeded];  // this should not happen, but we should recover after all
    }
    
    // we clean up buffered events that might not have been processed yet
    if (self.flowManager.isReady) {
        [self processBufferedEventsIfNeeded];
    }
    
    id firstRequest = [self.requestStack lastObject];
    [firstRequest setDebugInformationTranscoder:self];
    [firstRequest forceToVoipSession];
    [self.requestStack removeLastObject];
    
    return firstRequest;
}

- (BOOL)nextRequestIsCallsConfig
{
    ZMTransportRequest *request = self.requestStack.lastObject;
    return [request.path isEqualToString:@"/calls/config"];
}

- (void)processBufferedEventsIfNeeded
{
    if (self.conversationsNeedingUpdate.count > 0) {
        // update flows for conversations that couldn't be updated while the flow manager was not fully initialized
        
        NSSet *conversationsToUpdate = [self.conversationsNeedingUpdate copy];
        for (ZMConversation *conv in conversationsToUpdate) {
            [self updateFlowsForConversation:conv];
        }
        if (self.conversationsNeedingUpdate.count > 0) {
            // by now AVS should be ready. If that's not the case, we still want to clear whatever is stored
            ZMLogDebug(@"Could not update flows for all conversations: %@", self.conversationsNeedingUpdate);
            [self.conversationsNeedingUpdate removeAllObjects];
        }
    }
    if (self.usersNeedingToBeAdded.count > 0) {
        // update users to conversations that couldn't be updated while the flow manager was not fully initialized
        
        NSDictionary *usersToAdd = [self.usersNeedingToBeAdded copy];
        [usersToAdd enumerateKeysAndObjectsUsingBlock:^(NSString *conversationID, NSSet *users, __unused  BOOL * _Nonnull stop) {
            for (ZMUser *user in users) {
                [self addJoinedCallParticipant:user inConversationWithIdentifer:conversationID];
            }
        }];
        if (self.usersNeedingToBeAdded.count > 0) {
            // by now AVS should be ready. If that's not the case, we still want to clear whatever is stored
            ZMLogDebug(@"Could not add allUsers for conversations %@", self.usersNeedingToBeAdded);
            [self.usersNeedingToBeAdded removeAllObjects];
        }
        
    }
    if (self.eventsNeedingToBeForwarded.count > 0) {
        // process buffered events
        
        NSSet *eventsToForward = [self.eventsNeedingToBeForwarded copy];
        for (ZMUpdateEvent *event in eventsToForward) {
            [self processFlowEvent:event];
        }
        if (self.eventsNeedingToBeForwarded.count > 0) {
            // by now AVS should be ready. If that's not the case, we still want to clear whatever is stored
            ZMLogDebug(@"Could not forward all events %@", self.eventsNeedingToBeForwarded);
            [self.eventsNeedingToBeForwarded removeAllObjects];
        }
    }
}

- (void)processEvents:(NSArray<ZMUpdateEvent *> *)events
           liveEvents:(BOOL)liveEvents
       prefetchResult:(__unused ZMFetchRequestBatchResult *)prefetchResult;
{
    if(!liveEvents) {
        return;
    }
    if (self.application.applicationState != UIApplicationStateBackground || [ZMUserSession useCallKit]) {
        [self setUpFlowManagerIfNeeded];
    }
    if (!self.isFlowManagerReady) {
        NSArray *eventsToForward = [events filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(ZMUpdateEvent *event, __unused id bindings) {
            return [self.eventTypesToForward containsObject:@(event.type)];
        }]];
        [self.eventsNeedingToBeForwarded addObjectsFromArray:eventsToForward];
        return;
    }
    for(ZMUpdateEvent *event in events) {
        if (! [self.eventTypesToForward containsObject:@(event.type)]) {
            return;
        }
        [self processFlowEvent:event];
    }
}

- (void)processFlowEvent:(ZMUpdateEvent *)event
{
    if (!self.isFlowManagerReady) {
        return;
    }
    [self.eventsNeedingToBeForwarded removeObject:event];
    NSData *content = [NSJSONSerialization dataWithJSONObject:event.payload options:0 error:nil];
    [self.flowManager processEventWithMediaType:DefaultMediaType content:content];
}

- (void)requestCompletedWithResponse:(ZMTransportResponse *)response forContext:(void const*)context
{
    NSData *contentData;
    if(response.payload != nil) {
        contentData = [NSJSONSerialization dataWithJSONObject:response.payload options:0 error:nil];
    }
    [self.flowManager processResponseWithStatus:(int) response.HTTPStatus reason:[NSString stringWithFormat:@"%ld", (long)response.HTTPStatus] mediaType:DefaultMediaType content:contentData context:context];
}

- (void)acquireFlowsForConversation:(ZMConversation *)conversation;
{
    if (self.application.applicationState != UIApplicationStateBackground || [ZMUserSession useCallKit]) {
        [self setUpFlowManagerIfNeeded];
    }
    if (!self.isFlowManagerReady) {
        [self.conversationsNeedingUpdate addObject:conversation];
        return;
    }
    [self.conversationsNeedingUpdate removeObject:conversation];

    NSString *identifier = conversation.remoteIdentifier.transportString;
    if (identifier == nil) {
        ZMLogError(@"Trying to acquire flow for a conversation without a remote ID.");
    } else {
        [self.flowManager acquireFlows:identifier];
    }
}

- (void)releaseFlowsForConversation:(ZMConversation *)conversation;
{
    if (self.application.applicationState != UIApplicationStateBackground || [ZMUserSession useCallKit]) {
        [self setUpFlowManagerIfNeeded];
    }
    if (!self.isFlowManagerReady) {
        [self.conversationsNeedingUpdate addObject:conversation];
        return;
    }
    [self.conversationsNeedingUpdate removeObject:conversation];

    NSString *identifier = conversation.remoteIdentifier.transportString;
    if (identifier == nil) {
        ZMLogError(@"Trying to release flow for a conversation without a remote ID.");
    } else {
        [self.flowManager releaseFlows:identifier];
        conversation.isFlowActive = NO;
    }
}

- (void)setSessionIdentifier:(NSString *)sessionID forConversationIdentifier:(NSUUID *)conversationID;
{
    NSString *userID = [ZMUser selfUserInContext:self.managedObjectContext].remoteIdentifier.transportString ?: @"na";
    NSString *randomID = [NSUUID UUID].transportString;
    NSString *combinedID = [NSString stringWithFormat:@"%@_U-%@_D-%@", sessionID, userID, randomID];
    [self.flowManager setSessionId:combinedID forConversation:conversationID.transportString];
}

- (void)appendLogForConversationID:(NSUUID *)conversationID message:(NSString *)message;
{
    AVSFlowManager *flowManager = self.flowManager;
    dispatch_async(self.avsLogQueue, ^{
        [flowManager appendLogForConversation:conversationID.transportString message:message];
    });
}

- (void)pushChannelDidChange:(NSNotification *)note
{
    const BOOL oldValue = self.pushChannelIsOpen;
    BOOL newValue = [note.userInfo[ZMPushChannelIsOpenKey] boolValue];
    self.pushChannelIsOpen = newValue;
    
    if(self.pushChannelIsOpen) {
        [self.flowManager networkChanged];
    }
    
    if (!oldValue && newValue && self.requestStack.count > 0) {
        [ZMRequestAvailableNotification notifyNewRequestsAvailable:self];
    }
}

- (void)addJoinedCallParticipant:(ZMUser *)user inConversation:(ZMConversation *)conversation;
{
    [self addJoinedCallParticipant:user inConversationWithIdentifer:conversation.remoteIdentifier.transportString];
}

- (void)addJoinedCallParticipant:(ZMUser *)user inConversationWithIdentifer:(NSString *)remoteIDString;
{
    if (!self.isFlowManagerReady) {
        NSMutableSet *users = self.usersNeedingToBeAdded[remoteIDString] ?: [NSMutableSet set];
        [users addObject:user];
        self.usersNeedingToBeAdded[remoteIDString] = users;
        return;
    }
    
    NSMutableSet *users = self.usersNeedingToBeAdded[remoteIDString];
    if (users != nil) {
        [users removeObject:user];
        if (users.count > 0) {
            self.usersNeedingToBeAdded[remoteIDString] = users;
        } else {
            [self.usersNeedingToBeAdded removeObjectForKey:remoteIDString];
        }
    }
    
    [self.flowManager addUser:remoteIDString userId:user.remoteIdentifier.transportString name:user.name];
}

- (void)registerSelfUser
{
    NSString *selfUserID = [ZMUser selfUserInContext:self.managedObjectContext].remoteIdentifier.transportString;
    if (selfUserID == nil) {
        return;
    }
    [self.flowManager setSelfUser:selfUserID];
}

- (void)accessTokenDidChangeWithToken:(NSString *)token ofType:(NSString *)type;
{
    if (token != nil && type != nil) {
        [self.flowManager refreshAccessToken:token type:type];
    }
}

- (BOOL)isFlowManagerReady
{
    if (!self.flowManager.isReady) {
        ZMLogDebug(@"Flowmanager not ready");
        return NO;
    }
    return YES;
}

- (void)updateFlowsForConversation:(ZMConversation *)conversation;
{
    if (conversation.callDeviceIsActive) {
        if(!conversation.isFlowActive) {
            [self appendLogForConversationID:conversation.remoteIdentifier message:@"Acquiring Flows"];
        }
        [self acquireFlowsForConversation:conversation];
    } else {
        if(conversation.isFlowActive) {
            [self appendLogForConversationID:conversation.remoteIdentifier message:@"Releasing Flows"];
        }
        [self releaseFlowsForConversation:conversation];
    }
}

@end



@implementation ZMFlowSync (FlowManagerDelegate)


- (BOOL)requestWithPath:(NSString *)path
                 method:(NSString *)methodString
              mediaType:(NSString *)mtype
                content:(NSData *)content
                context:(void const *)ctx;
{
    VerifyActionString(path.length > 0,  return NO, "Path for AVSFlowManager request not set");
    VerifyActionString(methodString.length > 0, return NO, "Method for AVSFlowManager request not set");
    
    ZMTransportRequestMethod method = [ZMTransportRequest methodFromString:methodString];
    [self.managedObjectContext performGroupedBlock:^{
        ZMTransportRequest *request = [[ZMTransportRequest alloc] initWithPath:path method:method binaryData:content type:mtype contentDisposition:nil shouldCompress:YES];
        ZM_WEAK(self);
        
        [request addCompletionHandler:[ZMCompletionHandler handlerOnGroupQueue:self.managedObjectContext block:^(ZMTransportResponse *response) {
            ZM_STRONG(self);
            [self requestCompletedWithResponse:response forContext:ctx];
        }]];
        
        [self.requestStack insertObject:request atIndex:0];
        [ZMRequestAvailableNotification notifyNewRequestsAvailable:self];
    }];
    return YES;
}

- (void)didEstablishMediaInConversation:(NSString *)conversationIdentifier;
{    
    NSUUID *conversationUUID = conversationIdentifier.UUID;
    
    [self.managedObjectContext performGroupedBlock:^{
        
        ZMConversation *conversation = [ZMConversation conversationWithRemoteID:conversationUUID createIfNeeded:NO inContext:self.managedObjectContext];
        
        BOOL canSendVideo = NO;
        if (conversation.isVideoCall) {
            BOOL useCallKit = [ZMUserSession useCallKit];
            if ([self.flowManager canSendVideoForConversation:conversationIdentifier] && (!useCallKit || self.application.applicationState == UIApplicationStateActive)) {
                [self.flowManager setVideoSendState:FLOWMANAGER_VIDEO_SEND forConversation:conversationIdentifier];
                canSendVideo = YES;
            } else {
                // notify UI that a video call can not be established
                [CallingInitialisationNotification notifyCallingFailedWithErrorCode:VoiceChannelV2ErrorCodeVideoCallingNotSupported];
            }
        }
        
        if (conversation.isVideoCall) {
            conversation.isSendingVideo = canSendVideo;
            if (canSendVideo) {
                // only sync the updated state when we can send video, otherwise it breaks compatibility with older clients
                [conversation syncLocalModificationsOfIsSendingVideo];
            }
        }
        conversation.isFlowActive = YES;
        [self.managedObjectContext saveOrRollback];
    }];
}

- (void)setFlowManagerActivityState:(AVSFlowActivityState)activityState;
{
    NOT_USED(activityState);
}

- (void)networkQuality:(float)q conversation:(NSString *)convid;
{
    NOT_USED(q);
    NOT_USED(convid);
}

- (void)mediaWarningOnConversation:(NSString *)conversationIdentifier;
{
    [self leaveCallInConversationWithRemoteID:conversationIdentifier reason:@"AVS Media warning"];
}

- (void)errorHandler:(int)err
      conversationId:(NSString *)conversationIdentifier
             context:(void const*)ctx;
{
    NOT_USED(err);
    NOT_USED(ctx);
    [self leaveCallInConversationWithRemoteID:conversationIdentifier reason:[NSString stringWithFormat:@"AVS error handler with error %i", err]];
}

- (void)leaveCallInConversationWithRemoteID:(NSString *)remoteIDString reason:(NSString *)reason
{
    NSUUID *conversationID = [remoteIDString UUID];
    [self.managedObjectContext performGroupedBlock:^{
        ZMConversation *conversation = [ZMConversation conversationWithRemoteID:conversationID createIfNeeded:NO inContext:self.managedObjectContext];
        conversation.isFlowActive = NO;
        
        if (conversation.isVideoCall) {
            [self.flowManager setVideoSendState:FLOWMANAGER_VIDEO_SEND_NONE forConversation:conversation.remoteIdentifier.transportString];
        }
        
        [self.managedObjectContext saveOrRollback];
        
        // We need to leave the voiceChannel on the uiContext, otherwise hasLocalModificationsForCallDeviceIsActive won't be set
        // and we won't sync the leave with the backend
        [self.uiManagedObjectContext performGroupedBlock:^{
            ZMConversation *uiConv = [ZMConversation conversationWithRemoteID:conversationID createIfNeeded:NO inContext:self.uiManagedObjectContext];
            [ZMUserSession appendAVSLogMessageForConversation:uiConv withMessage:[NSString stringWithFormat:@"Self user wants to leave voice channel. Reason: %@", reason]];
            if (uiConv.callDeviceIsActive) {
                [uiConv.voiceChannelRouter.v2 leaveOnAVSError];
                [self.uiManagedObjectContext saveOrRollback];
            }
            else {
                [ZMUserSession appendAVSLogMessageForConversation:uiConv withMessage:@"Self user can't leave voice channel (callDeviceIsActive = NO)"];
            }
        }];
    }];
}

- (void)didUpdateVolume:(double)volume conversationId:(NSString *)convid participantId:(NSString *)participantId
{
    [self.managedObjectContext performGroupedBlock:^{
        NSUUID *conversationUUID = convid.UUID;
        ZMConversation *conversation = [ZMConversation conversationWithRemoteID:conversationUUID createIfNeeded:NO inContext:self.managedObjectContext];
        if (conversation == nil) {
            return;
        }
        ZMUser *user;
        if ([participantId isEqualToString:FlowManagerSelfUserParticipantIdentifier]) {
            user = [ZMUser selfUserInContext:self.managedObjectContext];
        }
        else if ([participantId isEqualToString:FlowManagerOtherUserParticipantIdentifier]) {
            user = conversation.connectedUser;
        }
        
        else {
            NSUUID *participantUUID = [participantId UUID];
            user = [ZMUser userWithRemoteID:participantUUID createIfNeeded:NO inContext:self.managedObjectContext];
        }
        if (user == nil) {
            return;
        }
        
        NSUUID *conversationID = conversation.remoteIdentifier;
        NSUUID *userID = user.remoteIdentifier;
        
        VoiceGainNotification *voiceGainNotification = [[VoiceGainNotification alloc] initWithVolume:(float)volume conversationId:conversationID userId:userID];
                
        [self.uiManagedObjectContext performGroupedBlock:^{
            [self.voiceGainNotificationQueue enqueueNotification:voiceGainNotification.notification
                                                    postingStyle:NSPostWhenIdle
                                                    coalesceMask:NSNotificationCoalescingOnSender | NSNotificationCoalescingOnName
                                                        forModes:nil];
        }];
    }];
}

- (void)conferenceParticipantsDidChange:(NSArray *)participantIDStrings
                         inConversation:(NSString *)convId;
{
    [self.managedObjectContext performGroupedBlock:^{
        NSUUID *conversationUUID = convId.UUID;
        ZMConversation *conversation = [ZMConversation conversationWithRemoteID:conversationUUID createIfNeeded:NO inContext:self.managedObjectContext];
        NSArray *participants = [participantIDStrings mapWithBlock:^id(NSString *userID) {
            return  [ZMUser userWithRemoteID:userID.UUID createIfNeeded:NO inContext:self.managedObjectContext];
        }];

        [conversation.voiceChannelRouter.v2 updateActiveFlowParticipants:participants];
        [self.managedObjectContext enqueueDelayedSave];
    }];
}


- (void)vmStatushandler:(BOOL)is_playing current_time:(int)cur_time_ms length:(int)file_length_ms;
{
    NOT_USED(is_playing);
    NOT_USED(cur_time_ms);
    NOT_USED(file_length_ms);
}

+ (void)logMessage:(NSString *)msg;
{
    NOT_USED(msg);
}

@end


