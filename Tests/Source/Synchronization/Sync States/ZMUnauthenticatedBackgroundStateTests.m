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


#import "StateBaseTest.h"
#import "ZMUnauthenticatedBackgroundState.h"

@interface ZMUnauthenticatedBackgroundStateTests : StateBaseTest

@property (nonatomic, readonly) ZMUnauthenticatedBackgroundState *sut;

@end

@implementation ZMUnauthenticatedBackgroundStateTests

- (void)setUp {
    [super setUp];
    
    _sut = [[ZMUnauthenticatedBackgroundState alloc]
            initWithAuthenticationCenter:self.authenticationStatus
            clientRegistrationStatus:self.clientRegistrationStatus
            objectStrategyDirectory:self.objectDirectory
            stateMachineDelegate:self.stateMachine];
}

- (void)tearDown {

    _sut = nil;
    
    [super tearDown];
}

- (void)testThatItReturnsNoRequest
{
    XCTAssertNil(self.sut.nextRequest);
}

- (void)testThatItDoesNotSwitchStateOnEnterBackground
{
    // expect
    [[(id)self.stateMachine reject] goToState:OCMOCK_ANY];
    
    // when
    [self.sut didEnterBackground];
    
}

- (void)testThatThePolicyIsToIgnoreEvents
{
    XCTAssertEqual(self.sut.updateEventsPolicy, ZMUpdateEventPolicyIgnore);
}

- (void)testThatItDoesNotSwitchToQuickSyncOnEnteringForeground
{
    // expectation
    [[(id)self.stateMachine reject] goToState:self.stateMachine.eventProcessingState];
    [[(id)self.stateMachine stub] goToState:self.stateMachine.unauthenticatedState];
    
    // when
    [self.sut didEnterForeground];
}


- (void)testThatItDoesNotSwitchesToToLoginState
{
    // expectation
    [[(id)self.stateMachine reject] goToState:OCMOCK_ANY];
    
    // when
    [self.sut didFailAuthentication];
}

- (void)testThatItSwitchesToLoginStateWhenEnteringForeground
{
    // expectation
    [[(id)self.stateMachine expect] goToState:self.stateMachine.unauthenticatedState];
    
    // when
    [self.sut didEnterForeground];
}

@end
