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


#import "ZMCallStateRequestStrategy.h"

@class ZMConversation;
@class ZMUser;


@interface ZMCallStateLogger : NSObject

@property (nonatomic) BOOL pushChannelIsOpen;


- (instancetype)initWithFlowSync:(ZMCallFlowRequestStrategy *)callFlowRequestStrategy;

- (void)logCurrentStateForConversation:(ZMConversation *)conversation
                           withMessage:(NSString *)message;

- (void)logSessionIDFromPayload:(NSDictionary *)payload
                forConversation:(ZMConversation *)conversation;

- (void)logCallInterruptionForConversation:(ZMConversation *)conversation
                             isInterrupted:(BOOL)isInterrupted;

- (void)logPushChannelChangesForNotification:(NSNotification *)note
                                conversation:(ZMConversation *)conversation;

- (void)logSelfInfoForConversation:(ZMConversation *)conversation
             oldCallDeviceIsActive:(BOOL)oldCallDeviceIsActive
                             state:(NSString *)state;

- (void)logParticipantInfoForParticipant:(ZMUser *)participant
                            conversation:(ZMConversation *)conversation
                                   state:(NSString *)state
                             oldIsJoined:(BOOL)oldIsJoined;

- (void)traceSelfInfoForConversation:(ZMConversation *)conversation
                           withState:(NSString *)state
                         eventSource:(ZMCallEventSource)eventSource;

- (void)logFinalStateOfConversation:(ZMConversation *)conversation
                     forEventSource:(ZMCallEventSource)eventSource;

@end

