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

@import WireMessageStrategy;

#import <XCTest/XCTest.h>
#import "MessagingTest.h"
#import "ZMEventProcessingState.h"
#import "ZMUserTranscoder.h"
#import "ZMConnectionTranscoder.h"
#import "ZMConversationTranscoder.h"
#import "StateBaseTest.h"
#import "ZMObjectStrategyDirectory.h"

@interface ZMEventProcessingStateTests : StateBaseTest

@property (nonatomic) ZMEventProcessingState *sut;

@end



@implementation ZMEventProcessingStateTests

- (void)setUp {
    
    [super setUp];
    
    _sut = [[ZMEventProcessingState alloc] initWithAuthenticationCenter:self.authenticationStatus clientRegistrationStatus:self.clientRegistrationStatus objectStrategyDirectory:self.objectDirectory stateMachineDelegate:self.stateMachine];
}

- (NSArray *)syncObjectsUsedByState
{
    return  @[ /* Note: these must be in the same order as in the class */
        self.objectDirectory.flowTranscoder,
        self.objectDirectory.callStateTranscoder,
        self.objectDirectory.connectionTranscoder,
        self.objectDirectory.userTranscoder,
        self.objectDirectory.selfTranscoder,
        ];
}

- (void)testThatThePolicyIsToProcessEvents
{
    XCTAssertEqual(self.sut.updateEventsPolicy, ZMUpdateEventPolicyProcess);
}

- (void)testThatItCallsDidFinishSyncOnEnter
{
    // expect
    [[(id)self.stateMachine expect] didFinishSync];
    [[(id)self.objectDirectory stub] processAllEventsInBuffer];
    
    // when
    [self.sut didEnterState];
}

- (void)testThatItSwitchesToPreBackgroundState
{
    // expectation
    [[(id)self.stateMachine expect] goToState:[self.stateMachine preBackgroundState]];
    
    // when
    [self.sut didEnterBackground];
}

- (void)testThatItDoesNotSwitchToQuickSyncOnEnteringForeground
{
    // expectation
    [[(id)self.stateMachine reject] startQuickSync];
    
    // when
    [self.sut didEnterForeground];
}

- (void)testThatItReturnsTheFirstRequestReturnedByASync
{
    /*
     NOTE: a failure here might mean that you either forgot to add a new sync to
     self.syncObjectsUsedByThisState, or that the order of that array doesn't match
     the order used by the ZMEventProcessingState
     */
    
    [self checkThatItCallsRequestGeneratorsOnObjectsOfClass:[self syncObjectsUsedByState] creationOfStateBlock:^ZMSyncState *(id<ZMObjectStrategyDirectory> directory) {
        return [[ZMEventProcessingState alloc] initWithAuthenticationCenter:self.authenticationStatus clientRegistrationStatus:self.clientRegistrationStatus objectStrategyDirectory:directory stateMachineDelegate:self.stateMachine];
    }];
}

- (void)testThatItFlushesTheUpdateEventsBufferOnEnter
{
    // expect
    [[(id)self.stateMachine stub] didFinishSync];
    [[(id)self.objectDirectory expect] processAllEventsInBuffer];
    
    // when
    [self.sut didEnterState];
    
}

- (void)testThatItNotifiesThatInitialSyncIsComplete
{
    // expect
    [[(id)self.stateMachine stub] didFinishSync];
    [[(id)self.objectDirectory expect] processAllEventsInBuffer];

    id observer = [OCMockObject mockForProtocol:@protocol(ZMInitialSyncCompletionObserver)];
    [[observer expect] initialSyncCompleted:OCMOCK_ANY];

    [ZMUserSession addInitalSyncCompletionObserver:observer];

    // when
    [self.sut didEnterState];
    WaitForAllGroupsToBeEmpty(0.5);

    // then
    [ZMUserSession removeInitalSyncCompletionObserver:observer];
    [observer verify];

}

@end
