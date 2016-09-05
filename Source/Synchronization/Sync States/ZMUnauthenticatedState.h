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


@import ZMUtilities;

#import "ZMSyncState.h"
#import "ZMUserSession.h"
#import "ZMAuthenticationStatus.h"
#import <zmessaging/zmessaging-Swift.h>

@class ZMTimer;

extern NSTimeInterval DebugLoginFailureTimerOverride;



@interface ZMUnauthenticatedState : ZMSyncState <ZMTimerClient, ZMAuthenticationStatusObserver>

@property (nonatomic, readonly) ZMTimer*  _Nonnull loginFailureTimer;

+ (NSTimeInterval)loginTimeout;

- (instancetype _Nonnull)initWithAuthenticationCenter:(ZMAuthenticationStatus * _Nonnull)authenticationStatus
                    clientRegistrationStatus:(ZMClientRegistrationStatus * _Nonnull)clientRegistrationStatus
                     objectStrategyDirectory:(id<ZMObjectStrategyDirectory> _Nonnull)objectStrategyDirectory
                        stateMachineDelegate:(id<ZMStateMachineDelegate> _Nonnull)stateMachineDelegate NS_UNAVAILABLE;

- (instancetype _Nonnull)initWithAuthenticationCenter:(ZMAuthenticationStatus * _Nonnull)authenticationStatus
                    clientRegistrationStatus:(ZMClientRegistrationStatus * _Nonnull)clientRegistrationStatus
                     objectStrategyDirectory:(id<ZMObjectStrategyDirectory> _Nonnull)objectStrategyDirectory
                        stateMachineDelegate:(id<ZMStateMachineDelegate> _Nonnull)stateMachineDelegate
                                 application:(id<ZMApplication> _Nonnull)application NS_DESIGNATED_INITIALIZER;

@end
