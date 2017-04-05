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
#import <WireTransport/ZMUpdateEvent.h>
#import "ZMAuthenticationStatus.h"
#import "ZMUpdateEventsBuffer.h"


@protocol ZMStateMachineDelegate;
@class ZMTransportRequest;
@class ZMSyncStrategy;
@class ZMClientRegistrationStatus;
@protocol ZMObjectStrategyDirectory;

@interface ZMSyncState : NSObject

@property (nonatomic, readonly) ZMUpdateEventsPolicy updateEventsPolicy;
@property (nonatomic, readonly, weak) id<ZMStateMachineDelegate> stateMachineDelegate;
@property (nonatomic, readonly, weak) id<ZMObjectStrategyDirectory> objectStrategyDirectory;
@property (nonatomic, readonly, weak) ZMAuthenticationStatus * authenticationStatus;
@property (nonatomic, readonly, weak) ZMClientRegistrationStatus *clientRegistrationStatus;
@property (nonatomic, readonly) id<ZMUpdateEventsFlushableCollection> eventBuffer;
@property (nonatomic, readonly) BOOL supportsBackgroundFetch;

- (instancetype)initWithAuthenticationCenter:(ZMAuthenticationStatus *)authenticationStatus
                    clientRegistrationStatus:(ZMClientRegistrationStatus *)clientRegistrationStatus
                     objectStrategyDirectory:(id<ZMObjectStrategyDirectory>)objectStrategyDirectory
                        stateMachineDelegate:(id<ZMStateMachineDelegate>)stateMachineDelegate NS_DESIGNATED_INITIALIZER;

- (void)didRequestSynchronization;
- (void)didFailAuthentication; //we need it in each state cause at some point cookies can become invalid (if future we will clear cookies on logout)
- (void)didEnterBackground;
- (void)didEnterForeground;

- (void)didEnterState;
- (void)didLeaveState;

- (void)dataDidChange;

- (ZMTransportRequest *)nextRequest;

- (void)tearDown;

@end



@interface ZMSyncState (Subclasses)

- (ZMTransportRequest *)nextRequestFromTranscoders:(NSArray *)transcoders;

@end
