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


#import "VoiceChannelV2.h"
@class ZMCallTimer;
@class AVSFlowManager;
@class CTCallCenter;


@interface VoiceChannelV2 ()

- (instancetype)initWithConversation:(ZMConversation *)conversation NS_DESIGNATED_INITIALIZER;
- (instancetype)initWithConversation:(ZMConversation *)conversation callCenter:(CTCallCenter *)callCenter;
- (VoiceChannelV2State)stateForIsSelfJoined:(BOOL)selfJoined otherJoined:(BOOL)otherJoined isDeviceActive:(BOOL)isDeviceActive flowActive:(BOOL)flowActive isIgnoringCall:(BOOL)isIgnoringCall;
+ (VoiceChannelV2ParticipantState *)participantStateForCallUserWithIsJoined:(BOOL)joined flowActive:(BOOL)flowActive;

+ (void)setLastSessionIdentifier:(NSString *)sessionID; ///< Thread safe setter
+ (NSString *)lastSessionIdentifier; ///< Thread safe getter

+ (void)setLastSessionStartDate:(NSDate *)date; ///< Thread safe setter
+ (NSDate *)lastSessionStartDate; ///< Thread safe getter
- (BOOL)hasOngoingGSMCall;

@end


@interface VoiceChannelV2ParticipantState ()

@property (nonatomic) VoiceChannelV2ConnectionState connectionState;
@property (nonatomic) BOOL muted;
@property (nonatomic) BOOL isSendingVideo;

@end
