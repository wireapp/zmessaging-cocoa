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

#import "ZMVoiceChannel+Internal.h"
#import "ZMVoiceChannel+Testing.h"
#import <zmessaging/zmessaging-Swift.h>


@implementation ZMVoiceChannelParticipantState

- (BOOL)isEqual:(id)object;
{
    if (! [object isKindOfClass:[ZMVoiceChannelParticipantState class]]) {
        return NO;
    }
    ZMVoiceChannelParticipantState *other = object;
    return ((other.connectionState == self.connectionState) &&
            (other.muted == self.muted));
}

- (NSString *)description;
{
    NSString *d;
    switch (self.connectionState) {
        default:
        case ZMVoiceChannelConnectionStateInvalid:
            d = @"Invalid";
            break;
        case ZMVoiceChannelConnectionStateNotConnected:
            d = @"NotConnected";
            break;
        case ZMVoiceChannelConnectionStateConnecting:
            d = @"Connecting";
            break;
        case ZMVoiceChannelConnectionStateConnected:
            d = @"Connected";
            break;
    }
    return [NSString stringWithFormat:@"<%@: %p> %@%@", self.class, self,
            d,
            self.muted ? @" muted" : @""];
}

@end




@interface ZMVoiceChannel ()

- (ZMVoiceChannelState)stateForIsSelfJoined:(BOOL)selfJoined otherJoined:(BOOL)otherJoined isDeviceActive:(BOOL)isDeviceActive flowActive:(BOOL)flowActive isIgnoringCall:(BOOL)isIgnoringCall;


@property (nonatomic) ZMTimer *timer;

@property (nonatomic) CTCallCenter *callCenter;

@end



@implementation ZMVoiceChannel

- (instancetype)initWithConversation:(ZMConversation *)conversation;
{
    VerifyReturnNil(conversation != nil);
    self = [super init];
    if (self) {
        _conversation = conversation;
        NSManagedObjectContext *context = self.conversation.managedObjectContext;
        if (context.zm_isUserInterfaceContext) {
            self.callCenter = context.globalManagedObjectContextObserver.callCenter;
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
        queue = dispatch_queue_create("ZMVoiceChannel.lastSessionIdentifier", DISPATCH_QUEUE_CONCURRENT);
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


- (ZMVoiceChannelState)stateForIsSelfJoined:(BOOL)selfJoined otherJoined:(BOOL)otherJoined isDeviceActive:(BOOL)isDeviceActive flowActive:(BOOL)flowActive isIgnoringCall:(BOOL)isIgnoringCall
{
    const BOOL selfActiveInCall = selfJoined || isDeviceActive;
    ZMConversation *conversation = self.conversation;
    
    if (!conversation.isSelfAnActiveMember) {
        return ZMVoiceChannelStateNoActiveUsers;
    }
    else if (isIgnoringCall) {
        if (conversation.conversationType == ZMConversationTypeOneOnOne ||
            (conversation.isOutgoingCall && !otherJoined)) // we cancelled an outgoing call
        {
            return ZMVoiceChannelStateNoActiveUsers;
        }
        
        if (otherJoined) {
            return ZMVoiceChannelStateIncomingCallInactive;
        }
        else {
            return ZMVoiceChannelStateNoActiveUsers;
        }
    }
    else if (selfJoined && !isDeviceActive && !conversation.isOutgoingCall)
    {
        return ZMVoiceChannelStateDeviceTransferReady;
    }
    else if(selfActiveInCall && !otherJoined) {
        return [self currentOutgoingCallState];
    }
    else if (!selfActiveInCall && otherJoined) {
        return [self currentIncomingCallState];
    }
    else if (selfActiveInCall && otherJoined) {
        if (flowActive) {
            return ZMVoiceChannelStateSelfConnectedToActiveChannel;
        } else {
            return ZMVoiceChannelStateSelfIsJoiningActiveChannel;
        }
    } else {
        return  ZMVoiceChannelStateNoActiveUsers;
    }
    
}


- (ZMVoiceChannelState)currentOutgoingCallState
{
    return self.conversation.callTimedOut ? ZMVoiceChannelStateOutgoingCallInactive :ZMVoiceChannelStateOutgoingCall;
}

- (ZMVoiceChannelState)currentIncomingCallState
{
    return self.conversation.callTimedOut ? ZMVoiceChannelStateIncomingCallInactive : ZMVoiceChannelStateIncomingCall;
    
}

- (ZMVoiceChannelState)state;
{
    ZMConversation *conversation = self.conversation;
    
    VerifyReturnValue(conversation.managedObjectContext != nil, ZMVoiceChannelStateInvalid);
    
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



- (void)enumerateParticipantStatesWithBlock:(void(^)(ZMUser *user, ZMVoiceChannelConnectionState connectionState, BOOL muted))block;
{
    [self.conversation.callParticipants.array enumerateObjectsUsingBlock:^(ZMUser *user, ZM_UNUSED NSUInteger idx, ZM_UNUSED BOOL *stop) {
        if(block) {
            ZMVoiceChannelParticipantState *state = [self stateForParticipant:user];
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

+ (ZMVoiceChannelParticipantState *)participantStateForCallUserWithIsJoined:(BOOL)joined flowActive:(BOOL)flowActive
{
    ZMVoiceChannelParticipantState *state = [[ZMVoiceChannelParticipantState alloc] init];
    if (! joined) {
        state.connectionState = ZMVoiceChannelConnectionStateNotConnected;
    } else if (flowActive) {
        state.connectionState = ZMVoiceChannelConnectionStateConnected;
    } else {
        state.connectionState = ZMVoiceChannelConnectionStateConnecting;
    }
    return state;
}


- (ZMVoiceChannelParticipantState *)stateForParticipant:(ZMUser *)user
{
    ZMConversation *conversation = self.conversation;
    const BOOL joined = [conversation.callParticipants containsObject:user];
    const BOOL flowActive = user.isSelfUser ? conversation.isFlowActive : [conversation.activeFlowParticipants containsObject:user];
    ZMVoiceChannelParticipantState *state = [self.class participantStateForCallUserWithIsJoined:joined flowActive:flowActive];
    state.isSendingVideo = user.isSelfUser ? conversation.isSendingVideo : [conversation.otherActiveVideoCallParticipants containsObject:user];
    return state;
}

- (ZMVoiceChannelConnectionState)selfUserConnectionState;
{
    ZMConversation *conv = self.conversation;
    ZMVoiceChannelParticipantState *state = [self stateForParticipant:[ZMUser selfUserInContext:conv.managedObjectContext]];
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



@implementation ZMVoiceChannel (ZMDebug)


+ (NSAttributedString *)voiceChannelDebugInformation;
{
    NSMutableAttributedString *result = [[NSMutableAttributedString alloc] init];
    
    UIFont *font = [UIFont systemFontOfSize:11];
    UIFont *boldFont = [UIFont boldSystemFontOfSize:11];
    
    NSDictionary *attributes = @{NSFontAttributeName: font};
    NSDictionary *boldAttributes = @{NSFontAttributeName: boldFont};
    
    void(^append)(NSString *) = ^(NSString *text){
        NSAttributedString *s = [[NSAttributedString alloc] initWithString:text ?: @"" attributes:attributes];
        [result appendAttributedString:s];
    };
    void(^appendBold)(NSString *) = ^(NSString *text){
        NSAttributedString *s = [[NSAttributedString alloc] initWithString:text ?: @"" attributes:boldAttributes];
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
