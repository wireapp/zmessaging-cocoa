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


@import zmessaging;
#import "ZMSyncState.h"
#import "MessagingTest.h"
#import "ZMUserSession.h"
#import "ZMObjectStrategyDirectory.h"
#import "ZMStateMachineDelegate.h"
#import "ZMAuthenticationStatus.h"
#import "ZMClientRegistrationStatus.h"
#import <zmessaging/zmessaging-Swift.h>

@protocol ZMRequestGenerator;


@interface StateBaseTest : MessagingTest

@property (nonatomic, readonly) id<ZMObjectStrategyDirectory> objectDirectory;
@property (nonatomic, readonly) id<ZMStateMachineDelegate> stateMachine;
@property (nonatomic, readonly) ZMAuthenticationStatus *authenticationStatus;
@property (nonatomic, readonly) ZMClientRegistrationStatus *clientRegistrationStatus;
@property (nonatomic, readonly) ClientUpdateStatus *clientUpdateStatus;

- (void)checkThatItCallsRequestGeneratorsOnObjectsOfClass:(NSArray *)objectsToTest creationOfStateBlock:(ZMSyncState *(^)(id<ZMObjectStrategyDirectory> directory))creationBlock;

- (void)stubRequestsOnHighPriorityObjectSync;

- (id<ZMRequestGenerator>)generatorReturningNiceMockRequest;
- (id<ZMRequestGenerator>)generatorReturningRequest:(ZMTransportRequest *)request;

@end
