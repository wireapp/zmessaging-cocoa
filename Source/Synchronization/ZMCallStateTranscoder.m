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
@import ZMTransport;
@import ZMCDataModel;

#import "ZMCallStateTranscoder.h"
#import "VoiceChannelV2+CallFlow.h"
#import "ZMObjectStrategyDirectory.h"
#import "ZMUserSession+Internal.h"
#import "ZMCallStateLogger.h"
#import "ZMGSMCallHandler.h"
#import "ZMLocalNotificationDispatcher.h"
#import "ZMFlowSync.h"
#import <zmessaging/zmessaging-Swift.h>

static NSString * const StateKey = @"state";
static NSString * const StateIdle = @"idle";
static NSString * const StateActive = @"joined";

static NSString * const SelfStateIgnoredKey = @"ignored";
static NSString * const SelfStateSuspendedKey = @"suspended";
static NSString * const SelfStateVideoKey = @"videod";

static NSString * const SelfStateReasonKey = @"reason";
static NSString * const SelfStateReasonTransder = @"transfer";
static NSString * const SelfStateReasonEnded = @"ended";
static NSString * const SelfStateReasonForbidden = @"forbidden";

static NSString * const DropCauseKey = @"cause";
static NSString * const DropCauseRequested = @"requested";
static NSString * const DropCauseInterrupted = @"interrupted";
static NSString * const DropCauseDisconnected = @"disconnected";
static NSString * const DropCauseGone = @"gone";

static NSString * const SelfDictionaryKey = @"self";
static NSString * const ParticipantsDictionaryKey = @"participants";

static NSTimeInterval const UpstreamRequestTimeout = 30;


@interface ZMCallStateTranscoder () <ZMContextChangeTracker>

@property (nonatomic) ZMDownstreamObjectSync *downstreamSync;
@property (nonatomic) ZMUpstreamModifiedObjectSync *upstreamSync;
@property (nonatomic, weak) id<ZMObjectStrategyDirectory> objectStrategyDirectory;
@property (nonatomic, weak, readonly) ZMFlowSync *flowSync;
@property (nonatomic) NSMutableDictionary *convToSequenceMap;
@property (nonatomic) ZMConversation *lastConversation;
@property (nonatomic) BOOL pushChannelIsOpen;
@property (nonatomic) NSPredicate *upstreamFetchPredicate;
@property (nonatomic) NSPredicate *upstreamFilter;

@property (nonatomic) NSManagedObjectContext *uiManagedObjectContext;
@property (nonatomic) ZMCallStateLogger *callStateLogger;

@property (nonatomic) ZMGSMCallHandler *gsmCallHandler;

@end



@interface ZMCallStateTranscoder (DownstreamTranscoder) <ZMDownstreamTranscoder>

- (void)updateObject:(ZMConversation *)conversation withPayload:(id<ZMTransportData>)payload eventSource:(ZMCallEventSource)eventSource;

@end


@interface ZMCallStateTranscoder (UpstreamTranscoder) <ZMUpstreamTranscoder>
@end



@implementation ZMCallStateTranscoder

_Pragma("clang diagnostic push") \
_Pragma("clang diagnostic ignored \"-Wobjc-designated-initializers\"") \
- (instancetype)initWithManagedObjectContext:(NSManagedObjectContext *)moc
{
    NOT_USED(moc);
    Require(NO);
    return nil;
}
_Pragma("clang diagnostic pop")

- (instancetype)initWithSyncManagedObjectContext:(NSManagedObjectContext *)syncMOC
                          uiManagedObjectContext:(NSManagedObjectContext *)uiMOC
                         objectStrategyDirectory:(id<ZMObjectStrategyDirectory>)directory;
{
    return [self initWithSyncManagedObjectContext:syncMOC uiManagedObjectContext:uiMOC objectStrategyDirectory:directory gsmCallHandler:nil];
}


- (instancetype)initWithSyncManagedObjectContext:(NSManagedObjectContext *)syncMOC
                          uiManagedObjectContext:(NSManagedObjectContext *)uiMOC
                         objectStrategyDirectory:(id<ZMObjectStrategyDirectory>)directory
                                  gsmCallHandler:(ZMGSMCallHandler *)gsmCallHandler;
{
    self = [super initWithManagedObjectContext:syncMOC];
    if (self) {
        self.uiManagedObjectContext = uiMOC;
        self.objectStrategyDirectory = directory;
        self.callStateLogger = [[ZMCallStateLogger alloc] initWithFlowSync:directory.flowTranscoder];
        self.convToSequenceMap = [NSMutableDictionary dictionary];
        self.pushChannelIsOpen = NO;
        
        NSPredicate *predicateForObjectsToDownload = [ZMConversation predicateForNeedingCallStateToBeUpdatedFromBackend];
        self.downstreamSync = [[ZMDownstreamObjectSync alloc] initWithTranscoder:self entityName:ZMConversation.entityName predicateForObjectsToDownload:predicateForObjectsToDownload filter:nil managedObjectContext:self.managedObjectContext];
        
        self.upstreamFetchPredicate = [ZMConversation predicateForObjectsThatNeedCallStateToBeUpdatedUpstream];
        
        NSArray<NSString *> *keysToSync = @[ZMConversationCallDeviceIsActiveKey,
                                            ZMConversationIsSendingVideoKey,
                                            ZMConversationIsIgnoringCallKey];
        
        self.upstreamSync = [[ZMUpstreamModifiedObjectSync alloc] initWithTranscoder:self entityName:ZMConversation.entityName updatePredicate:self.upstreamFetchPredicate filter:nil keysToSync:keysToSync managedObjectContext:self.managedObjectContext];

        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(pushChannelDidChange:) name:ZMPushChannelStateChangeNotificationName object:nil];
        
        self.gsmCallHandler = gsmCallHandler ?: [[ZMGSMCallHandler alloc] initWithUIManagedObjectContext:uiMOC
                                                              syncManagedObjectContext:syncMOC
                                                                       callStateLogger:self.callStateLogger];
        [self checkForOngoingCalls];
    }
    return self;
}


- (NSNumber *)lastSequenceForConversation:(ZMConversation *)conversation;
{
    if (conversation == nil) {
        return nil;
    }
    return self.convToSequenceMap[conversation.remoteIdentifier];
}


- (void)tearDown
{
    self.lastConversation = nil;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self.gsmCallHandler tearDown];
    [super tearDown];
}

- (void)dealloc
{
    [self tearDown];
}

- (BOOL)isSlowSyncDone;
{
    return YES;
}

- (NSArray *)contextChangeTrackers;
{
    return @[self, self.downstreamSync, self.upstreamSync];
}

- (void)objectsDidChange:(NSSet *)objects
{
    for (ZMConversation *conv in objects) {
        ZMFlowSync *strongSync = self.flowSync;
        if ([conv isKindOfClass:[ZMConversation class]]){
            if ([self.upstreamFetchPredicate evaluateWithObject:conv] && !conv.callDeviceIsActive && conv.hasLocalModificationsForCallDeviceIsActive) {
                // we need to release the flows as soon as the user wants to leave the call
                // under bad network conditions we might not be able to send out the request to leave a call,
                // but we should still be able to stop the audio stream
                [strongSync updateFlowsForConversation:conv];
                [conv.voiceChannelRouter.v2 resetTimer];
            }
            if ([conv hasLocalModificationsForKey:ZMConversationIsSelfAnActiveMemberKey] && !conv.isSelfAnActiveMember) {
                // when the selfUser leaves a conversation with an ongoing call, we should reset the conversations's state
                conv.callDeviceIsActive = NO;
                [strongSync updateFlowsForConversation:conv];
                [conv.voiceChannelRouter.v2 resetCallState];
                [conv.voiceChannelRouter.v2 resetTimer];
            }
        }
        
    }
}

-(void)addTrackedObjects:(NSSet *)objects
{
    NOT_USED(objects);
}

- (NSFetchRequest *)fetchRequestForTrackedObjects
{
    return nil;
}

- (void)setNeedsSlowSync
{
    // NO-OP
}

- (void)checkForOngoingCalls;
{
    // Need to make sure we re-sync the active call participants here by setting
    // 'callStateNeedsToBeUpdatedFromBackend' on conversations that have a local call state,
    NSFetchRequest *fetchRequest = [NSFetchRequest fetchRequestWithEntityName:[ZMConversation entityName]];
    NSPredicate *predicate = [ZMConversation predicateForUpdatingCallStateDuringSlowSync];
    fetchRequest.predicate = predicate;
    NSArray *conversations = [self.managedObjectContext executeFetchRequestOrAssert:fetchRequest];

    [self.managedObjectContext performGroupedBlock:^{
        for (ZMConversation *conv in conversations){
            if (![self.gsmCallHandler isInterruptedCallConversation:conv]){
                conv.callStateNeedsToBeUpdatedFromBackend = YES;
                conv.isIgnoringCall = YES;
            }
        }
        [self.managedObjectContext enqueueDelayedSave];
    }];
}

- (NSArray *)requestGenerators;
{
    return @[self.downstreamSync, self.upstreamSync];
}

- (void)processEvents:(NSArray<ZMUpdateEvent *> *)events
           liveEvents:(BOOL)liveEvents
       prefetchResult:(ZMFetchRequestBatchResult *)prefetchResult;
{
    if(!liveEvents) {
        return;
    }
    
    NSArray *filteredEvents = [events filterWithBlock:^BOOL(ZMUpdateEvent *event) {
        return event.type == ZMUpdateEventConversationMemberJoin ||
        event.type == ZMUpdateEventConversationMemberLeave ||
        event.type == ZMUpdateEventCallState ||
        event.type == ZMUpdateEventConversationCreate;
    }];
    
    for(ZMUpdateEvent *event in filteredEvents) {
        NSUUID *conversationID = event.conversationUUID;
        ZMConversation *conversation = prefetchResult.conversationsByRemoteIdentifier[conversationID];
        
        if (nil == conversation) {
            conversation = [ZMConversation conversationWithRemoteID:conversationID createIfNeeded:NO inContext:self.managedObjectContext];
        }
        if (nil == conversation) {
            return;
        }
        
        if (event.type == ZMUpdateEventCallState) {
            [self processCallStateEvent:event inConversation:conversation];
        }
        else if ((event.type == ZMUpdateEventConversationMemberJoin || event.type == ZMUpdateEventConversationMemberLeave)
                 && conversation.conversationType == ZMConversationTypeGroup) {
            [self processMemberJoinOrLeaveEvent:event inConversation:conversation];
        }
        else if (event.type == ZMUpdateEventConversationCreate) {
            conversation.callStateNeedsToBeUpdatedFromBackend = YES;
        }
    }
}

- (void)processCallStateEvent:(ZMUpdateEvent *)event inConversation:(ZMConversation *)conversation
{
    // don't process call state update events when selfUser left the conversation
    if (conversation.conversationType == ZMConversationTypeGroup && !conversation.isSelfAnActiveMember) {
        [conversation.voiceChannelRouter.v2 removeAllCallParticipants];
        [conversation.voiceChannelRouter.v2 updateActiveFlowParticipants:@[]];
        return;
    }
    
    // if we want to sync the callState we ignore all live events in the mean time
    if (conversation.callStateNeedsToBeUpdatedFromBackend) {
        return;
    }
    [self.callStateLogger logCurrentStateForConversation:conversation withMessage:[NSString stringWithFormat:@"Received event through pushChannel: %@",event.payload]];
    [self updateObject:conversation withPayload:event.payload eventSource:ZMCallEventSourcePushChannel];
}

- (void)processMemberJoinOrLeaveEvent:(ZMUpdateEvent *)event inConversation:(ZMConversation *)conversation
{
    // If we are added to a group conversation (where potentially we were added before and then we were removed)
    // we need to fetch the call state
    
    ZMUser *selfUser = [ZMUser selfUserInContext:self.managedObjectContext];
    NSArray *userIDs = [[event.payload optionalDictionaryForKey:@"data"] optionalArrayForKey:@"user_ids"];
    for (NSString *uuidString in userIDs) {
        NSUUID *uuid = uuidString.UUID;
        if ([uuid isEqual:[selfUser remoteIdentifier]]) {
            BOOL needToUpdateCallState = (event.type == ZMUpdateEventConversationMemberJoin);
            conversation.callStateNeedsToBeUpdatedFromBackend = needToUpdateCallState;
            conversation.isIgnoringCall = needToUpdateCallState;
            if (event.type == ZMUpdateEventConversationMemberLeave) {
                // when the selfuser was removed from a conversation while in a call (which should not happen), we should reset the call state locally
                // we are not able to set the call state on the be because the be would refuse requests
                conversation.callDeviceIsActive = NO;
                [self.flowSync updateFlowsForConversation:conversation];
                [conversation.voiceChannelRouter.v2 resetCallState];
                [conversation.voiceChannelRouter.v2 resetTimer];
            }
            break;
        }
    }
}

- (ZMFlowSync *)flowSync;
{
    return self.objectStrategyDirectory.flowTranscoder;
}

- (void)pushChannelDidChange:(NSNotification *)note
{
    BOOL newValue = [note.userInfo[ZMPushChannelIsOpenKey] boolValue];
    const BOOL oldValue = self.pushChannelIsOpen;
    self.pushChannelIsOpen = newValue;
    if (!oldValue && newValue && [self.upstreamSync hasOutstandingItems]) {
        [ZMRequestAvailableNotification notifyNewRequestsAvailable:self];
    }
    [self.callStateLogger logPushChannelChangesForNotification:note conversation:self.lastConversation];
}


- (void)setPushChannelIsOpen:(BOOL)pushChannelIsOpen
{
    _pushChannelIsOpen = pushChannelIsOpen;
    self.callStateLogger.pushChannelIsOpen = pushChannelIsOpen;
}

@end



@implementation ZMCallStateTranscoder (DownstreamTranscoder)

- (NSString *)callStatePathForConversation:(ZMConversation *)conversation;
{
    NSString *path = [NSString pathWithComponents:@[@"/conversations",
                                                    conversation.remoteIdentifier.transportString,
                                                    @"call",
                                                    @"state"]];
    return path;
}

- (ZMTransportRequest *)requestForFetchingObject:(ZMConversation *)conversation downstreamSync:(id<ZMObjectSync>)downstreamSync;
{
    if (conversation.conversationType == ZMConversationTypeGroup && !conversation.isSelfAnActiveMember) {
        return nil;
    }
    
    NOT_USED(downstreamSync);
    //[self logCurrentStateForConversation:conversation withMessage:@"Creating request for getting call states"];

    ZMTransportRequest *request = [ZMTransportRequest compressedGetFromPath:[self callStatePathForConversation:conversation]];
    
    // additional completion handler to reset callState
    [request addCompletionHandler:[ZMCompletionHandler handlerOnGroupQueue:self.managedObjectContext block:^(ZMTransportResponse *response) {
        if(response.result == ZMTransportResponseStatusSuccess || response.result == ZMTransportResponseStatusPermanentError) {
            conversation.callStateNeedsToBeUpdatedFromBackend = NO;
        }
    }]];
    
    return request;
}


- (void)updateObject:(ZMConversation *)conversation withResponse:(ZMTransportResponse *)response downstreamSync:(id<ZMObjectSync>)downstreamSync;
{
    NOT_USED(downstreamSync);
    //[self logCurrentStateForConversation:conversation withMessage:@"Call state sync result"];
    [self updateObject:conversation withPayload:response.payload eventSource:ZMCallEventSourceDownstream];
}

- (void)updateObject:(ZMConversation *)conversation withPayload:(id<ZMTransportData>)payload eventSource:(ZMCallEventSource)eventSource;
{
    // The 'self' and 'participants' fields are optional, but have following constraints:
    // 1. At least one of them must be present.
    // 2. The 'self' field is only sent to the pertaining device.
    
    // we don't want to update the voiceChannel once we left the conversation
    if (!conversation.isSelfAnActiveMember) {
        [conversation.voiceChannelRouter.v2 removeAllCallParticipants];
        [conversation.voiceChannelRouter.v2 updateActiveFlowParticipants:@[]];
        return;
    }
    
    NSDictionary *payloadData = [payload asDictionary];
    NSNumber *sequence = [payloadData optionalNumberForKey:@"sequence"];
    NSNumber *storedSequence = self.convToSequenceMap[conversation.remoteIdentifier];
    if (sequence != nil && [storedSequence compare:sequence] == NSOrderedDescending) {
        return;
    }
    if (sequence != nil) {
        self.convToSequenceMap[conversation.remoteIdentifier] = sequence;
    }
    
    [self.callStateLogger logSessionIDFromPayload:payloadData forConversation:conversation];
    
    BOOL oldCallDeviceIsActive = conversation.callDeviceIsActive;
    BOOL didContainSelfInfo = [self processSelfInfoFromPayload:payloadData forConversation:conversation eventSource:eventSource];
    BOOL didContainParticipantInfo = [self processParticipantsFromPayload:payloadData forConversation:conversation eventSource:eventSource];

    [self updateIsIgnoringCallForConversation:conversation eventSource:eventSource];
    [self leaveOngoingCallAfterResyncingIfNeeded:conversation eventSource:eventSource];
    
    if (eventSource == ZMCallEventSourcePushChannel && !didContainSelfInfo && !didContainParticipantInfo) {
        ZMLogError(@"Both 'self' and 'participants' missing from call state.");
    }
    
    [self notifyUIofDroppedCallIfNecessaryForPayload:payloadData inConversation:conversation withOldCallDeviceIsActive:oldCallDeviceIsActive eventSource:eventSource];
    [self.callStateLogger logFinalStateOfConversation:conversation forEventSource:eventSource];
    self.lastConversation = conversation;
}

- (void)leaveOngoingCallAfterResyncingIfNeeded:(ZMConversation *)conversation eventSource:(ZMCallEventSource)eventSource
{
    if (eventSource != ZMCallEventSourceDownstream ) {
        return;
    }
    ZMUser *selfUser = [ZMUser selfUserInContext:self.managedObjectContext];
    if (!conversation.callDeviceIsActive && conversation.callParticipants.count > 0 && [conversation.callParticipants containsObject:selfUser]) {
        [self.uiManagedObjectContext performGroupedBlock:^{
            ZMConversation *uiConversation = [self.uiManagedObjectContext existingObjectWithID:conversation.objectID error:nil];
            if (uiConversation != nil) {
                // the backend know which clients are currently joined. Therefore calling this from a clinet that is not currently joined will not cause the call with the other client to drop
                // however this enables us to rejoin the call if the app crashed or got killed while being in a call
                [uiConversation.voiceChannelRouter.v2 leave];
                [self.uiManagedObjectContext enqueueDelayedSave];
            }
        }];
    }
}

- (void)updateIsIgnoringCallForConversation:(ZMConversation *)conversation eventSource:(ZMCallEventSource)eventSource
{
    // do not display incoming calls from slowSync
    // also when being added to a conversation with an ongoing call, the app should not ring
    if (eventSource == ZMCallEventSourceDownstream &&
        conversation.voiceChannel.participants.count != 0 &&
        conversation.conversationType == ZMConversationTypeGroup)
    {
        conversation.isIgnoringCall = YES;
    }
}

- (void)notifyUIofDroppedCallIfNecessaryForPayload:(NSDictionary *)payload inConversation:(ZMConversation *)conversation withOldCallDeviceIsActive:(BOOL)oldCallDeviceIsActive eventSource:(ZMCallEventSource)source
{
    BOOL isLeavingCall = (!oldCallDeviceIsActive && source == ZMCallEventSourceUpstream) || oldCallDeviceIsActive;
    
    if (!isLeavingCall || conversation.callDeviceIsActive || conversation.isIgnoringCall) {
        return;
    }

    NSString *reason = [payload optionalStringForKey:DropCauseKey];
    if(reason == nil) {
        if (!oldCallDeviceIsActive && source == ZMCallEventSourceUpstream) {
            reason = DropCauseRequested;
        } else {
            return;
        }
    }
    VoiceChannelV2CallEndReason endReason = [self callEndReasonForStringValue:reason];
    ZMCallStateReasonToLeave reasonToLeave = conversation.reasonToLeave;
    conversation.reasonToLeave = ZMCallStateReasonToLeaveNone;
    
    
    if (endReason == VoiceChannelV2CallEndReasonRequested) {
        switch (reasonToLeave) {
            case ZMCallStateReasonToLeaveUser:
                endReason = VoiceChannelV2CallEndReasonRequestedSelf;
                break;
                
            case ZMCallStateReasonToLeaveAvsError:
                endReason = VoiceChannelV2CallEndReasonRequestedAVS;
                break;
                
            default:
                break;
        }
    }
    
    [[[CallEndedNotification alloc] initWithReason:endReason conversationId:conversation.remoteIdentifier] post];
}

- (VoiceChannelV2CallEndReason)callEndReasonForStringValue:(NSString *)reasonString;
{
    if ([reasonString isEqualToString:DropCauseDisconnected]){
        return VoiceChannelV2CallEndReasonDisconnected;
    }
    if ([reasonString isEqualToString:DropCauseInterrupted]) {
        return VoiceChannelV2CallEndReasonInterrupted;
    }
    if ([reasonString isEqualToString:DropCauseRequested]) {
        return VoiceChannelV2CallEndReasonRequested;
    }
    if ([reasonString isEqualToString:DropCauseGone]) {
        return VoiceChannelV2CallEndReasonOtherLostMedia;
    }
    
    return VoiceChannelV2CallEndReasonRequested;
}

- (BOOL)processSelfInfoFromPayload:(NSDictionary *)payload forConversation:(ZMConversation *)conversation eventSource:(ZMCallEventSource)eventSource
{    
    NSDictionary *selfInfo = [payload optionalDictionaryForKey:SelfDictionaryKey];
    if (selfInfo == nil) {
        return NO;
    }
    
    NSString *state = [selfInfo optionalStringForKey:StateKey];
    if (state == nil){
        return NO;
    }
    
    if ([state isEqualToString:StateActive]) {
        [self.callStateLogger traceSelfInfoForConversation:conversation withState:state eventSource:eventSource];
    }
    else if ([state isEqualToString:StateIdle]) {
        if (eventSource != ZMCallEventSourcePushChannel &&
            conversation.callDeviceIsActive)
        {
            //for sync we always override state (if it differs from current)
            conversation.callDeviceIsActive = NO;
        }
        else if (eventSource == ZMCallEventSourcePushChannel &&
                 !conversation.hasLocalModificationsForCallDeviceIsActive &&
                 conversation.callDeviceIsActive)
        {
            //for pushEvent we ignore changes in state if we have unsynced local changes (to prevent race conditions)
            conversation.callDeviceIsActive = NO;
        }
        [self.callStateLogger traceSelfInfoForConversation:conversation withState:state eventSource:eventSource];
    }
    else if (![state isEqualToString:StateActive] && ![state isEqualToString:StateIdle]){
        ZMLogError(@"Unknown state '%@' in conversation call", state);
    }
    
    if(!conversation.callDeviceIsActive) { // do not "force join"
        [self.flowSync updateFlowsForConversation:conversation];
        [self.gsmCallHandler setActiveCallSyncConversation:nil];
    }
    
    return YES;
}

- (BOOL)processParticipantsFromPayload:(NSDictionary *)payload forConversation:(ZMConversation *)conversation eventSource:(ZMCallEventSource)eventSource
{
    NSDictionary *participantsDictionary = [payload optionalDictionaryForKey:ParticipantsDictionaryKey];
    if(participantsDictionary == nil || participantsDictionary.allKeys.count == 0) {
        return NO;
    }

    // keep track of who's there, so I know if I have to remove them after this change
    NSMutableOrderedSet *currentParticipants = [conversation.callParticipants mutableCopy];

    // process participants in payload
    [participantsDictionary enumerateKeysAndObjectsUsingBlock:^(NSString *userIDString, NSDictionary *participantInfo, ZM_UNUSED BOOL *stop) {
        NSUUID *userID = userIDString.UUID;
        if (userID == nil) {
            ZMLogError(@"Invalid UUID in transport data.");
            return;
        }
        ZMUser *participant = [ZMUser userWithRemoteID:userID createIfNeeded:YES inContext:self.managedObjectContext];
        [self setCallStateFromPayload:participantInfo forCallParticipant:participant inConversation:conversation eventSource:eventSource];
        [self addOrRemoveVideoParticipant:participantInfo forCallParticipant:participant inConversation:conversation];
        [currentParticipants removeObject:participant];
    }];
    
    // remove participants that don't have a state anymore
    for (ZMUser *user in currentParticipants) {
        [conversation.voiceChannelRouter.v2 removeCallParticipant:user];
        
    }
    
    return YES;
}

- (void)addOrRemoveVideoParticipant:(NSDictionary *)payload forCallParticipant:(ZMUser *)participant inConversation:(ZMConversation *)conversation
{
    const BOOL currentIsVideoCall = conversation.isVideoCall;
    BOOL isVideoActive = [[payload optionalNumberForKey:SelfStateVideoKey] boolValue];

    if (!currentIsVideoCall && isVideoActive) {
        conversation.isVideoCall = YES;
        [conversation.voiceChannelRouter.v2 updateForStateChange];
    }
    
    if (conversation.isVideoCall) {
        if (isVideoActive && !participant.isSelfUser) {
            [conversation addActiveVideoCallParticipant:participant];
        } else {
            [conversation removeActiveVideoCallParticipant:participant];
        }
    }
}

- (void)setCallStateFromPayload:(NSDictionary *)payload forCallParticipant:(ZMUser *)participant inConversation:(ZMConversation *)conversation eventSource:(ZMCallEventSource)eventSource
{
    NSString *state = [payload optionalStringForKey:StateKey];
    BOOL isIgnoringCall = (participant.isSelfUser) && ([payload optionalNumberForKey:SelfStateIgnoredKey].boolValue == YES);
    if (state == nil) {
        return;
    }
    
    const BOOL changeToActive = [state isEqualToString:StateActive];
    const BOOL changeToIdle = [state isEqualToString:StateIdle];
    const BOOL participantWasJoined = [conversation.callParticipants containsObject:participant];
    
    if (isIgnoringCall){
        conversation.isIgnoringCall = YES;
        [[NSNotificationCenter defaultCenter] postNotificationName:ZMConversationCancelNotificationForIncomingCallNotificationName object:conversation];
    }
    if(changeToActive && !participantWasJoined) {
        [conversation.voiceChannelRouter.v2 addCallParticipant:participant];
        if (eventSource == ZMCallEventSourceUpstream && conversation.callDeviceIsActive && !participant.isSelfUser) {
            [self.flowSync addJoinedCallParticipant:participant inConversation:conversation];
        }
    }
    else if(changeToIdle && participantWasJoined) {
        [conversation.voiceChannelRouter.v2 removeCallParticipant:participant];
    }
    else if(!changeToIdle && !changeToActive && !isIgnoringCall) {
        VerifyString(NO, "Unknown participant state in transport data.");
    }
    
}

- (void)deleteObject:(ZMConversation *)conversation downstreamSync:(id<ZMObjectSync>)downstreamSync;
{
    NOT_USED(downstreamSync);
    NOT_USED(conversation);
}

@end



@implementation ZMCallStateTranscoder (UpstreamTranscoder)

- (BOOL)shouldProcessUpdatesBeforeInserts
{
    return NO;
}

- (BOOL)shouldCreateRequestToSyncObject:(ZMManagedObject * __unused)managedObject forKeys:(NSSet<NSString *> * __unused)keys withSync:(id __unused)sync
{
    return self.pushChannelIsOpen || [ZMUserSession useCallKit];
}

- (ZMUpstreamRequest *)requestForUpdatingObject:(ZMConversation *)conversation forKeys:(NSSet *)keys
{
    if (conversation != nil) {
        return [self requestForUpdatingCallIsJoinedInConversation:conversation keysToUpdate:keys];
    }
    ZMTrapUnableToGenerateRequest(keys, self);
    return nil;
}

- (ZMUpstreamRequest *)requestForUpdatingCallIsJoinedInConversation:(ZMConversation *)conversation keysToUpdate:(NSSet *)keys
{
    [self.callStateLogger logCurrentStateForConversation:conversation
                                             withMessage:@"Trying to create request for setting self call state"];
    
    // If the user left the voice channel, we are supposed to release the flow immediately, before getting a
    // reply from the backend.
    if (!conversation.callDeviceIsActive) {
        [self.flowSync updateFlowsForConversation:conversation];
    }
    
    NSString *path = [self callStatePathForConversation:conversation];
    NSDictionary *payload = [self selfDictionaryForConversation:conversation];
    
    ZMTransportRequest *request = [ZMTransportRequest requestWithPath:path method:ZMMethodPUT payload:payload shouldCompress:YES];
    [request expireAfterInterval:UpstreamRequestTimeout];
    
    [self.callStateLogger logCurrentStateForConversation:conversation
                                             withMessage:[NSString stringWithFormat:@"Creating request for setting self call state: %@", payload]];

    ZM_WEAK(self);
    [request addCompletionHandler:[ZMCompletionHandler handlerOnGroupQueue:self.managedObjectContext block:^(ZMTransportResponse *response) {
        ZM_STRONG(self);
        [self handleResponse:response forConversation:conversation keysToUpdate:keys];
    }]];
    
    self.lastConversation = conversation;
    return [[ZMUpstreamRequest alloc] initWithKeys:keys transportRequest:request];
}

- (void)handleResponse:(ZMTransportResponse *)response forConversation:(ZMConversation *)conversation keysToUpdate:(NSSet *)keys
{
    [self resetKeysIfNeeded:keys conversation:conversation includingCallDeviceIsActive:NO];

    if (![keys containsObject:ZMConversationCallDeviceIsActiveKey]){
        // We don't want to cancel the call just because we couldn't tell the backend that we are now sending the video
        // TODO: What will we do under bad network conditions?
        return;
    }
    
    [self.callStateLogger logCurrentStateForConversation:conversation
                                             withMessage:[NSString stringWithFormat:@"Received response for setting self call state: %@",response]];
    if (response.result == ZMTransportResponseStatusPermanentError) {
        BOOL isVoiceChannelFull = NO;
        if (conversation.isSelfAnActiveMember) {
            // we can be no more in conversation so we can ignore any errors
            NSError *callbackError = {
                [NSError tooManyParticipantsInConversationErrorFromResponse:response] ?:
                [NSError fullVoiceChannelErrorFromResponse:response] ?:
                [NSError conversationErrorWithErrorCode:ZMConversationUnkownError userInfo:nil]
            };
            
            isVoiceChannelFull = [NSError fullVoiceChannelErrorFromResponse:response] != nil;
            
            [self.managedObjectContext.zm_userInterfaceContext performGroupedBlock:^{
                [[NSNotificationCenter defaultCenter] postNotificationName:ZMConversationVoiceChannelJoinFailedNotification
                                                                    object:conversation.objectID
                                                                  userInfo:@{@"error": callbackError}];
            }];
        }
        // the BE refused the request
        if (!conversation.callDeviceIsActive) {
            // we reset hasLocalModfications to avoid further request
            conversation.isIgnoringCall = NO;
            [conversation resetHasLocalModificationsForCallDeviceIsActive];
        }
        else {
            // we wanted to join
            // we send out a leave request in case we are joined on the BE for some reason
            conversation.callDeviceIsActive = NO;
            if (!isVoiceChannelFull) {
                [conversation.voiceChannelRouter.v2 resetCallState];
                [conversation.voiceChannelRouter.v2 resetTimer];
            }
        }
        [self.flowSync updateFlowsForConversation:conversation];
    }
}

- (NSDictionary *)selfDictionaryForConversation:(ZMConversation *)conversation
{
    NSString *newState = conversation.callDeviceIsActive ? StateActive : StateIdle;
    BOOL isInterruptedCall = [self.gsmCallHandler isInterruptedCallConversation:conversation];
    
    NSMutableDictionary *selfStateDict = [NSMutableDictionary dictionary];
    selfStateDict[StateKey] = [newState copy];
    if (conversation.callDeviceIsActive ) {
        BOOL isInitiatingCall = conversation.callParticipants.count == 0;
        BOOL isVideoCall = (conversation.isVideoCall && isInitiatingCall) || conversation.isSendingVideo;
        selfStateDict[SelfStateVideoKey] = isVideoCall ? @YES : @NO;
        selfStateDict[SelfStateSuspendedKey] = isInterruptedCall ? @YES : @NO;
    } else if (conversation.isIgnoringCall
               && conversation.hasLocalModificationsForIsIgnoringCall
               && !conversation.hasLocalModificationsForCallDeviceIsActive)
    {
        selfStateDict[SelfStateIgnoredKey] = @YES;
    }

    NSMutableDictionary *payload = [NSMutableDictionary dictionary];
    payload[SelfDictionaryKey] = selfStateDict;
    payload[DropCauseKey] = (conversation.callDeviceIsActive && isInterruptedCall) ? DropCauseInterrupted : DropCauseRequested;
    
    return [payload copy];
}

- (void)requestExpiredForObject:(ZMConversation *)conversation forKeys:(NSSet *)keys
{
    [self resetKeysIfNeeded:keys conversation:conversation includingCallDeviceIsActive:NO];

    if ([keys containsObject:ZMConversationCallDeviceIsActiveKey]) {
        
        [conversation updateLocallyModifiedCallStateKeys];
        if (conversation.callDeviceIsActive) {
            // if we are trying to join
            // (A) the request never reached the BE --> we want to reset the local call state (set callDeviceIsActive to !callDeviceIsActive)
            // (B) the response never reached the device --> we want to reset the call state on the BE (set hasLocalModificationsForCallDeviceIsActive to YES)
            conversation.callDeviceIsActive = NO;
            [conversation.voiceChannelRouter.v2 resetCallState];
            [conversation.voiceChannelRouter.v2 resetTimer];
        } else {
            // we re-add the conversation to the upstream so that it retry to upload changes
            [self.upstreamSync objectsDidChange:[NSSet setWithObject:conversation]];
        }
        // we dont need to set hasLocalModifications since it was never reset, the upstreamsync will pick this object up again
        [self.flowSync updateFlowsForConversation:conversation];
    }
}


- (ZMUpstreamRequest *)requestForInsertingObject:(ZMConversation *__unused)conversation forKeys:(NSSet *__unused)keys;
{
    // This class is not responsible for inserts. The ZMConversationSync handles those.
    return nil;
}


- (void)updateInsertedObject:(ZMConversation *__unused)conversation request:(ZMUpstreamRequest *__unused)upstreamRequest response:(ZMTransportResponse *__unused)response
{
}

- (BOOL)updateUpdatedObject:(ZMConversation *)conversation
            requestUserInfo:(NSDictionary *)requestUserInfo
                   response:(ZMTransportResponse *)response
                keysToParse:(NSSet *)keysToParse
{
    NOT_USED(requestUserInfo);
    [self resetKeysIfNeeded:keysToParse conversation:conversation includingCallDeviceIsActive:YES];
    if (![keysToParse containsObject:ZMConversationCallDeviceIsActiveKey]) {
        // we don't want to update the call state when all we did is ignoring a call or toggling the videoSending
        return NO;
    }
    
    [self updateObject:conversation withPayload:response.payload eventSource:ZMCallEventSourceUpstream];
    if (![self.gsmCallHandler isInterruptedCallConversation:conversation]) {
        [self.flowSync updateFlowsForConversation:conversation];
    }
    [self.gsmCallHandler setActiveCallSyncConversation:(conversation.callDeviceIsActive) ? conversation : nil];
    
    return NO;
}

- (ZMManagedObject *)objectToRefetchForFailedUpdateOfObject:(ZMConversation *)conversation;
{
    NOT_USED(conversation);
    return nil;
}


- (void)resetKeysIfNeeded:(NSSet *)keys conversation:(ZMConversation *)conversation includingCallDeviceIsActive:(BOOL)includingCallDeviceIsActive
{
    if (includingCallDeviceIsActive && [keys containsObject:ZMConversationCallDeviceIsActiveKey]) {
        [conversation resetHasLocalModificationsForCallDeviceIsActive];
    }
    if ([keys containsObject:ZMConversationIsSendingVideoKey]) {
        [conversation resetHasLocalModificationsForIsSendingVideo];
    }
    if ([keys containsObject:ZMConversationIsIgnoringCallKey]) {
        [conversation resetHasLocalModificationsForIsIgnoringCall];
    }
}

@end

