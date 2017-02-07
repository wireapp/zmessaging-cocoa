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
@import CoreTelephony;
@import ZMUtilities;
@import ZMCSystem;
@import ZMTransport;

#import "VoiceChannelV2+Internal.h"
#import "VoiceChannelV2+Testing.h"
#import <zmessaging/zmessaging-Swift.h>


@implementation VoiceChannelV2ParticipantState

- (BOOL)isEqual:(id)object;
{
    if (! [object isKindOfClass:[VoiceChannelV2ParticipantState class]]) {
        return NO;
    }
    VoiceChannelV2ParticipantState *other = object;
    return ((other.connectionState == self.connectionState) &&
            (other.muted == self.muted));
}

- (NSString *)description;
{
    NSString *d;
    switch (self.connectionState) {
        default:
        case VoiceChannelV2ConnectionStateInvalid:
            d = @"Invalid";
            break;
        case VoiceChannelV2ConnectionStateNotConnected:
            d = @"NotConnected";
            break;
        case VoiceChannelV2ConnectionStateConnecting:
            d = @"Connecting";
            break;
        case VoiceChannelV2ConnectionStateConnected:
            d = @"Connected";
            break;
    }
    return [NSString stringWithFormat:@"<%@: %p> %@%@", self.class, self,
            d,
            self.muted ? @" muted" : @""];
}

@end




@interface VoiceChannelV2 ()

- (VoiceChannelV2State)stateForIsSelfJoined:(BOOL)selfJoined otherJoined:(BOOL)otherJoined isDeviceActive:(BOOL)isDeviceActive flowActive:(BOOL)flowActive isIgnoringCall:(BOOL)isIgnoringCall;


@property (nonatomic) ZMTimer *timer;

@property (nonatomic) CTCallCenter *callCenter;

@end



@implementation VoiceChannelV2

- (instancetype)initWithConversation:(ZMConversation *)conversation;
{
    VerifyReturnNil(conversation != nil);
    self = [super init];
    if (self) {
        _conversation = conversation;
        NSManagedObjectContext *context = self.conversation.managedObjectContext;
        if (context.zm_isUserInterfaceContext) {
            self.callCenter = context.zm_callCenter;
        }
    }
    return self;
}

- (instancetype)initWithConversation:(ZMConversation *)conversation callCenter:(CTCallCenter *)callCenter
{
    self = [self initWithConversation:conversation];
    self.callCenter = callCenter;
    return self;
}

static NSString *lastSessionIdentifier;
static NSDate *lastSessionStartDate;
static dispatch_queue_t lastSessionIdentifierIsolation(void)
{
    static dispatch_once_t onceToken;
    static dispatch_queue_t queue;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("VoiceChannelV2.lastSessionIdentifier", DISPATCH_QUEUE_CONCURRENT);
    });
    return queue;
}

+ (void)setLastSessionIdentifier:(NSString *)sessionID;
{
    sessionID = [sessionID copy];
    dispatch_barrier_async(lastSessionIdentifierIsolation(), ^{
        lastSessionIdentifier = sessionID;
    });
}

+ (NSString *)lastSessionIdentifier;
{
    __block NSString *result;
    dispatch_sync(lastSessionIdentifierIsolation(), ^{
        result = [lastSessionIdentifier copy];
    });
    return result;
}

+ (void)setLastSessionStartDate:(NSDate *)date;
{
    date = [date copy];
    dispatch_barrier_async(lastSessionIdentifierIsolation(), ^{
        lastSessionStartDate = date;
    });
}

+ (NSDate *)lastSessionStartDate;
{
    __block NSDate *result;
    dispatch_sync(lastSessionIdentifierIsolation(), ^{
        result = [lastSessionStartDate copy];
    });
    return result;
}


- (VoiceChannelV2State)stateForIsSelfJoined:(BOOL)selfJoined otherJoined:(BOOL)otherJoined isDeviceActive:(BOOL)isDeviceActive flowActive:(BOOL)flowActive isIgnoringCall:(BOOL)isIgnoringCall
{
    const BOOL selfActiveInCall = selfJoined || isDeviceActive;
    ZMConversation *conversation = self.conversation;
    
    if (!conversation.isSelfAnActiveMember) {
        return VoiceChannelV2StateNoActiveUsers;
    }
    else if (isIgnoringCall) {
        if (conversation.conversationType == ZMConversationTypeOneOnOne ||
            (conversation.isOutgoingCall && !otherJoined)) // we cancelled an outgoing call
        {
            return VoiceChannelV2StateNoActiveUsers;
        }
        
        if (otherJoined) {
            return VoiceChannelV2StateIncomingCallInactive;
        }
        else {
            return VoiceChannelV2StateNoActiveUsers;
        }
    }
    else if (selfJoined && !isDeviceActive && !conversation.isOutgoingCall)
    {
        return VoiceChannelV2StateDeviceTransferReady;
    }
    else if(selfActiveInCall && !otherJoined) {
        return [self currentOutgoingCallState];
    }
    else if (!selfActiveInCall && otherJoined) {
        return [self currentIncomingCallState];
    }
    else if (selfActiveInCall && otherJoined) {
        if (flowActive) {
            return VoiceChannelV2StateSelfConnectedToActiveChannel;
        } else {
            return VoiceChannelV2StateSelfIsJoiningActiveChannel;
        }
    } else {
        return  VoiceChannelV2StateNoActiveUsers;
    }
    
}


- (VoiceChannelV2State)currentOutgoingCallState
{
    return self.conversation.callTimedOut ? VoiceChannelV2StateOutgoingCallInactive :VoiceChannelV2StateOutgoingCall;
}

- (VoiceChannelV2State)currentIncomingCallState
{
    return self.conversation.callTimedOut ? VoiceChannelV2StateIncomingCallInactive : VoiceChannelV2StateIncomingCall;
    
}

- (VoiceChannelV2State)state;
{
    ZMConversation *conversation = self.conversation;
    
    VerifyReturnValue(conversation.managedObjectContext != nil, VoiceChannelV2StateInvalid);
    
    ZMUser *selfUser = [ZMUser selfUserInContext:conversation.managedObjectContext];
    ZMUser *otherUser = [conversation.callParticipants.array firstObjectMatchingWithBlock:^BOOL(ZMUser *user) {
        return user != selfUser;
    }];
    
    const BOOL selfJoined = [conversation.callParticipants containsObject:selfUser];
    const BOOL otherJoined = otherUser != nil;
    const BOOL isDeviceActive = conversation.callDeviceIsActive;
    const BOOL flowActive = conversation.isFlowActive;
    
    return [self stateForIsSelfJoined:selfJoined otherJoined:otherJoined isDeviceActive:isDeviceActive flowActive:flowActive isIgnoringCall:conversation.isIgnoringCall];
}

- (BOOL)hasOngoingGSMCall
{
    NSSet *connectedCalls = [self.callCenter.currentCalls filteredSetUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(CTCall *call, ZM_UNUSED id bindings) {
        return [call.callState isEqualToString:CTCallStateConnected];
    }]];
    if (connectedCalls.count > 0) {
        return YES;
    }
    return NO;
}



- (void)enumerateParticipantStatesWithBlock:(void(^)(ZMUser *user, VoiceChannelV2ConnectionState connectionState, BOOL muted))block;
{
    [self.conversation.callParticipants.array enumerateObjectsUsingBlock:^(ZMUser *user, ZM_UNUSED NSUInteger idx, ZM_UNUSED BOOL *stop) {
        if(block) {
            VoiceChannelV2ParticipantState *state = [self stateForParticipant:user];
            block(user, state.connectionState, state.muted);
        }
    }];
}

- (NSOrderedSet *)participants;
{
    ZMConversation *conversation = self.conversation;
    ZMUser *selfUser = [ZMUser selfUserInContext:conversation.managedObjectContext];
    NSMutableOrderedSet *participants = conversation.callParticipants.mutableCopy;
    [participants removeObject:selfUser];
    return participants;
}

+ (VoiceChannelV2ParticipantState *)participantStateForCallUserWithIsJoined:(BOOL)joined flowActive:(BOOL)flowActive
{
    VoiceChannelV2ParticipantState *state = [[VoiceChannelV2ParticipantState alloc] init];
    if (! joined) {
        state.connectionState = VoiceChannelV2ConnectionStateNotConnected;
    } else if (flowActive) {
        state.connectionState = VoiceChannelV2ConnectionStateConnected;
    } else {
        state.connectionState = VoiceChannelV2ConnectionStateConnecting;
    }
    return state;
}


- (VoiceChannelV2ParticipantState *)stateForParticipant:(ZMUser *)user
{
    ZMConversation *conversation = self.conversation;
    const BOOL joined = [conversation.callParticipants containsObject:user];
    const BOOL flowActive = user.isSelfUser ? conversation.isFlowActive : [conversation.activeFlowParticipants containsObject:user];
    VoiceChannelV2ParticipantState *state = [self.class participantStateForCallUserWithIsJoined:joined flowActive:flowActive];
    state.isSendingVideo = user.isSelfUser ? conversation.isSendingVideo : [conversation.otherActiveVideoCallParticipants containsObject:user];
    return state;
}

- (VoiceChannelV2ConnectionState)selfUserConnectionState;
{
    ZMConversation *conv = self.conversation;
    VoiceChannelV2ParticipantState *state = [self stateForParticipant:[ZMUser selfUserInContext:conv.managedObjectContext]];
    return state.connectionState;
}


- (id<CallingInitialisationObserverToken>)addCallingInitializationObserver:(id<CallingInitialisationObserver>)observer;
{
    ZM_WEAK(observer);
    return (id<CallingInitialisationObserverToken>)[CallingInitialisationNotification addObserverWithBlock:^(CallingInitialisationNotification * notification) {
        ZM_STRONG(observer);
        if ([observer respondsToSelector:@selector(couldNotInitialiseCallWithError:)]) {
            [observer couldNotInitialiseCallWithError:notification.error];
        }
    }];
}

- (void)removeCallingInitialisationObserver:(id<CallingInitialisationObserverToken>)token;
{
    [CallingInitialisationNotification removeObserver:token];
}


@end



@implementation VoiceChannelV2 (ZMDebug)


+ (NSAttributedString *)voiceChannelDebugInformation;
{
    NSMutableAttributedString *result = [[NSMutableAttributedString alloc] init];
    
    UIFont *font = [UIFont systemFontOfSize:11];
    UIFont *boldFont = [UIFont boldSystemFontOfSize:11];
    
    NSDictionary *attributes = @{NSFontAttributeName: font};
    NSDictionary *boldAttributes = @{NSFontAttributeName: boldFont};
    
    void(^append)(NSString *) = ^(NSString *text){
        NSAttributedString *s = [[NSAttributedString alloc] initWithString:text.localizedString ?: @"" attributes:attributes];
        [result appendAttributedString:s];
    };
    void(^appendBold)(NSString *) = ^(NSString *text){
        NSAttributedString *s = [[NSAttributedString alloc] initWithString:text.localizedString ?: @"" attributes:boldAttributes];
        [result appendAttributedString:s];
    };
    
    // Session ID
    append(@"Session ID: ");
    appendBold(self.lastSessionIdentifier);
    append(@"\n");
    
    // Session date:
    append(@"Session start date: ");
    NSDate *date = [self lastSessionStartDate];
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US"];
    formatter.dateStyle = kCFDateFormatterLongStyle;
    formatter.timeStyle = kCFDateFormatterLongStyle;
    appendBold(date == nil ? @"" : [formatter stringFromDate:date]);
    append(@"\n");
    // Session date in GMT:
    append(@"Session start date (GMT): ");
    formatter.timeZone = [NSTimeZone timeZoneForSecondsFromGMT:0];
    appendBold(date == nil ? @"" : [formatter stringFromDate:date]);
    append(@"\n");
    
    return result;
}

@end
