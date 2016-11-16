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


@import ZMCDataModel;

@class ZMCallTimer;
@class AVSFlowManager;

@protocol ZMCallImplementation <NSObject>

- (void)join;
- (void)leave;
- (void)leaveOnAVSError;
- (void)ignoreIncomingCall;

@end



@interface ZMVoiceChannel (CallFlow)

- (void)join;
- (void)leave;
- (void)leaveOnAVSError;
- (void)ignoreIncomingCall;

- (void)updateActiveFlowParticipants:(nullable NSArray<ZMUser *>*)newParticipants;
- (void)addCallParticipant:(nonnull ZMUser *)participant;
- (void)removeCallParticipant:(nonnull ZMUser *)participant;
- (void)removeAllCallParticipants;


- (void)updateForStateChange;
// removes call participants and resets state to no call whatsoever
- (void)resetCallState;
- (void)tearDown;


+ (nullable NSComparator)conferenceComparator;
- (nullable AVSFlowManager *)flowManager;

@end

