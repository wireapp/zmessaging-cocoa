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


@import WireTransport;
@import WireDataModel;

#import "ZMCallStateLogger.h"
#import "ZMCallFlowRequestStrategy.h"
#import "ZMOperationLoop.h"
#import "ZMUserSession+Internal.h"

#import <WireSyncEngine/WireSyncEngine-Swift.h>

@interface ZMCallStateLogger ()

@property (nonatomic) ZMCallFlowRequestStrategy *callFlowRequestStrategy;

@end

@implementation ZMCallStateLogger


- (instancetype)initWithFlowSync:(ZMCallFlowRequestStrategy *)callFlowRequestStrategy
{
    self = [super init];
    if (self) {
        self.callFlowRequestStrategy = callFlowRequestStrategy;
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(appendLogMessageWithNotification:) name:ZMAppendAVSLogNotificationName object:nil];
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (NSString *)descriptionForFlowManagerCategory:(ZMFlowManagerCategory)category
{
    switch (category) {
        case ZMFlowManagerCategoryCallInProgress:
            return @"CallInProgess";
        case ZMFlowManagerCategoryIdle:
            return @"Idle";
        default:
            return @"Unknown category";
    }
}

- (NSString *)descriptionForVoiceChannelState:(VoiceChannelV2State)state
{
    
    switch (state) {
        case VoiceChannelV2StateDeviceTransferReady:
            return @"TransferReady";
        case VoiceChannelV2StateInvalid:
            return @"Invalid";
        case VoiceChannelV2StateNoActiveUsers:
            return @"NoActiveUsers";
        case VoiceChannelV2StateIncomingCall:
            return @"IncomingCall";
        case VoiceChannelV2StateIncomingCallDegraded:
            return @"IncomingCallDegraded";
        case VoiceChannelV2StateIncomingCallInactive:
            return @"IncomingCallInactive";
        case VoiceChannelV2StateSelfConnectedToActiveChannel:
            return @"ConnectedToActiveChannel";
        case VoiceChannelV2StateOutgoingCall:
            return @"OutgoingCall";
        case VoiceChannelV2StateOutgoingCallDegraded:
            return @"OutgoingCallDegraded";
        case VoiceChannelV2StateOutgoingCallInactive:
            return @"OutgoingCallInactive";
        case VoiceChannelV2StateSelfIsJoiningActiveChannel:
            return @"SelfIsJoiningActiveChannel";
        case VoiceChannelV2StateSelfIsJoiningActiveChannelDegraded:
            return @"SelfIsJoiningActiveChannelDegraded";
    }
}

- (void)logCallInterruptionForConversation:(ZMConversation *)conversation
                             isInterrupted:(BOOL)isInterrupted;
{
    NSString *state = isInterrupted ? @"interrupted by" : @"resumed after";
    [self logCurrentStateForConversation:conversation withMessage:[NSString stringWithFormat:@"Wire call %@ GSM call", state]];
}

- (void)logPushChannelChangesForNotification:(NSNotification *)note conversation:(ZMConversation *)conversation
{
    BOOL newValue = [note.userInfo[ZMPushChannelIsOpenKey] boolValue];
    NSString *pushChannelChange = newValue ? @"did open" : @"did close";
    NSString *responseStatusCode = [(NSNumber *)note.userInfo[ZMPushChannelResponseStatusKey] stringValue];
    
    [self logCurrentStateForConversation:conversation
                             withMessage:[NSString stringWithFormat:@"PushChannel %@ with status code %@", pushChannelChange, responseStatusCode]];
}

- (void)appendLogMessageWithNotification:(NSNotification *)note
{
    [self logCurrentStateForConversation:note.object withMessage:note.userInfo[@"message"]];
}


- (void)logCurrentStateForConversation:(ZMConversation *)conversation withMessage:(NSString *)message
{
    NSString *finalMessage = [self messageForConversation:conversation withMessage:message];
    if (finalMessage != nil) {
        [self.callFlowRequestStrategy appendLogForConversationID:conversation.remoteIdentifier message:finalMessage];
    }
}

- (NSString *)messageForConversation:(ZMConversation *)conversation withMessage:(NSString *)message
{
    if (conversation == nil) {
        return nil;
    }
    if (message == nil) {
        message = @"Logging conversation";
    }
    
    ZMUser *selfUser = [ZMUser selfUserInContext:conversation.managedObjectContext];
    ZMUser *otherUser = [conversation.callParticipants.array firstObjectMatchingWithBlock:^BOOL(ZMUser *user) {
        return !user.isSelfUser;
    }];
    
    const BOOL selfJoined = [conversation.callParticipants containsObject:selfUser];
    const BOOL otherJoined = (otherUser != nil);
    const BOOL isFlowActive = conversation.activeFlowParticipants.count > 0;
    
    NSString *finalMessage = [NSString stringWithFormat:@"%@ \n"
                              @"-->  conversation remoteID: %@ \n"
                              @"-->  current voiceChannel state: %@ \n"
                              @"-->  current callDeviceIsActive: %@ \n"
                              @"-->  current hasLocalModificationsForCallDeviceIsActive: %@ \n"
                              @"-->  current is flow active: %@ \n"
                              @"-->  current self isJoined: %@ \n"
                              @"-->  current other isJoined: %@ \n"
                              @"-->  current isIgnoringCall: %@ \n"
                              @"-->  conversation.isOutgoingCall: %@\n"
                              @"-->  websocket is open: %@",
                              message,
                              conversation.remoteIdentifier.transportString,
                              [self descriptionForVoiceChannelState:conversation.voiceChannel.state],
                              @(conversation.callDeviceIsActive),
                              @(conversation.hasLocalModificationsForCallDeviceIsActive),
                              @(isFlowActive),
                              @(selfJoined),
                              @(otherJoined),
                              @(conversation.isIgnoringCall),
                              @(conversation.isOutgoingCall),
                              @(self.pushChannelIsOpen)];
    
    return finalMessage;
}


- (void)logSessionIDFromPayload:(NSDictionary *)payload forConversation:(ZMConversation *)conversation
{
    NSString *sessionID = [payload optionalStringForKey:@"session"];
    if (sessionID == nil || conversation == nil) {
        return;
    }
    
    [VoiceChannelV2 setLastSessionIdentifier:sessionID];
    [VoiceChannelV2 setLastSessionStartDate:[NSDate date]];
    if (sessionID != nil) {
        [self.callFlowRequestStrategy setSessionIdentifier:sessionID forConversationIdentifier:conversation.remoteIdentifier];
    }
}

- (void)logSelfInfoForConversation:(ZMConversation *)conversation oldCallDeviceIsActive:(BOOL)oldCallDeviceIsActive state:(NSString *)state
{
    if (conversation == nil) {
        return;
    }
    
    NSString *message = [NSString stringWithFormat:@"Received self call state '%@' \n"
                         @"-->  conversation remoteID: %@ \n"
                         @"-->  current callDeviceIsActive: %@ \n",
                         state,
                         conversation.remoteIdentifier.transportString,
                         @(oldCallDeviceIsActive)];
    
    [self.callFlowRequestStrategy appendLogForConversationID:conversation.remoteIdentifier message:message];
    
    if (conversation.hasLocalModificationsForCallDeviceIsActive) {
        [self.callFlowRequestStrategy appendLogForConversationID:conversation.remoteIdentifier message:[NSString stringWithFormat:@"Rejecting state change - conversation has local modifications for call device is active (local: %@)",@(conversation.callDeviceIsActive)]];
    }
    if (!conversation.callDeviceIsActive && oldCallDeviceIsActive) {
        [self.callFlowRequestStrategy appendLogForConversationID:conversation.remoteIdentifier message:@"Setting callDeviceIsActive to NO"];
    }
}


- (void)logParticipantInfoForParticipant:(ZMUser *)participant
                            conversation:(ZMConversation *)conversation
                                   state:(NSString *)state
                             oldIsJoined:(BOOL)oldIsJoined
{
    if (participant == nil) {
        return;
    }
    
    const BOOL participantIsActive = [conversation.callParticipants containsObject:participant];
    NSString *change;
    if (oldIsJoined && !participantIsActive) {
        change = @"left the voiceChannel";
    } else if (!oldIsJoined && participantIsActive){
        change = @"joined the voiceChannel";
    } else  {
        change = oldIsJoined ? @"stayed in voiceChannel" : @"did not join voiceChannel";
    }
    
    NSString *message = [NSString stringWithFormat:@"Received participant state '%@' \n"
                         @"-->  conversation remoteID: %@ \n"
                         @"-->  previous isJoined: %@ \n"
                         @"-->  Participant with remoteID %@ %@ \n",
                         state,
                         conversation.remoteIdentifier.transportString,
                         @(oldIsJoined),
                         participant.remoteIdentifier.transportString, change];
    
    [self.callFlowRequestStrategy appendLogForConversationID:conversation.remoteIdentifier message:message];
}


- (void)traceSelfInfoForConversation:(ZMConversation *)conversation withState:(NSString *)state eventSource:(ZMCallEventSource)eventSource
{
    NOT_USED(conversation);
    NOT_USED(eventSource);
    NOT_USED(state);
}

- (void)logFinalStateOfConversation:(ZMConversation *)conversation forEventSource:(ZMCallEventSource)eventSource
{
    switch (eventSource) {
        case ZMCallEventSourceUpstream:
            [self logCurrentStateForConversation:conversation
                                     withMessage:@"Done pushing call state to BE"];
            break;
        case ZMCallEventSourceDownstream:
            //[self logCurrentStateForConversation:conversation withMessage:@"Finished updating conversation"];
            break;
        case ZMCallEventSourcePushChannel:
            [self logCurrentStateForConversation:conversation
                                     withMessage:@"Finished updating call state from push event"];
            break;
        default:
            break;
    }
}

@end
