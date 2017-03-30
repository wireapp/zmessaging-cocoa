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


@import Foundation;

#import "ZMSyncStateDelegate.h"

@class ZMSyncState;

@protocol ZMStateMachineDelegate <NSObject>

@property (nonatomic, readonly) ZMSyncState *unauthenticatedState; ///< need to log in. Will sturtup timer to try to login while waiting for email verification.
@property (nonatomic, readonly) ZMSyncState *unauthenticatedBackgroundState; ///< need to log in, but we are in the background. In background we don't keep trying to login on timer waiting for email verification.
@property (nonatomic, readonly) ZMSyncState *eventProcessingState; ///< can normally process events
@property (nonatomic, readonly) ZMSyncState *currentState;

- (void)goToState:(ZMSyncState *)state;

@end
