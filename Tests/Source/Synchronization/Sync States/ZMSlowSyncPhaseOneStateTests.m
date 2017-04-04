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


@import WireSyncEngine;
#import "ZMConnectionTranscoder.h"
#import "ZMSlowSyncPhaseOneState.h"
#import "ZMSyncStrategy.h"
#import "ZMStateMachineDelegate.h"
#import "ZMConversationTranscoder.h"
#import "StateBaseTest.h"


@interface ZMSlowSyncPhaseOneStateTests : StateBaseTest

@property (nonatomic, readonly) ZMSlowSyncPhaseOneState* sut;

@end

@implementation ZMSlowSyncPhaseOneStateTests

- (void)setUp
{
    [super setUp];
    _sut = [[ZMSlowSyncPhaseOneState alloc] initWithAuthenticationCenter:self.authenticationStatus
                                                clientRegistrationStatus:self.clientRegistrationStatus
                                                 objectStrategyDirectory:self.objectDirectory
                                                    stateMachineDelegate:self.stateMachine];
    
    [self stubRequestsOnHighPriorityObjectSync];

}

- (void)tearDown
{
    _sut = nil;
    [super tearDown];
}

- (void)testThatItCallsOnNeedToSlowSyncOnEnter
{
    // expect
    [[(id)self.stateMachine expect] didStartSlowSync];
    [[(id)self.stateMachine expect] didStartSync];
    
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

- (void)testThatThePolicyIsToBufferEvents
{
    XCTAssertEqual(self.sut.updateEventsPolicy, ZMUpdateEventPolicyBuffer);
}

- (void)testThatItAsksNextRequestToTheObjectSyncs
{
    NSArray *expectedObjectSync = @[[self.objectDirectory connectionTranscoder],
                                    [self.objectDirectory conversationTranscoder]
                                    ];
    
    [self checkThatItCallsRequestGeneratorsOnObjectsOfClass:expectedObjectSync creationOfStateBlock:^ZMSyncState *(id<ZMObjectStrategyDirectory> directory) {
        
        [[[(id)directory.connectionTranscoder stub] andReturnValue:@NO] isSlowSyncDone];
        [[[(id)directory.conversationTranscoder stub] andReturnValue:@NO] isSlowSyncDone];
        
        return [[ZMSlowSyncPhaseOneState alloc] initWithAuthenticationCenter:self.authenticationStatus clientRegistrationStatus:self.clientRegistrationStatus objectStrategyDirectory:directory stateMachineDelegate:self.stateMachine];
    }];
    
}

- (void)testThatItSwitchesStateToSlowSyncPhaseTwoWhenDone
{
    // expect
    [[[(id)self.objectDirectory.connectionTranscoder expect] andReturnValue:@YES] isSlowSyncDone];
    [[[(id)self.objectDirectory.conversationTranscoder expect] andReturnValue:@YES] isSlowSyncDone];
    
    [[(id)self.stateMachine expect] goToState:self.stateMachine.slowSyncPhaseTwoState];
    
    // when
    [self.sut dataDidChange];
}

- (void)testThatItDoesNotSwitchStateToSlowSyncIfConnectionSyncIsSlowSyncDoneIsFalse
{
    [[[(id)self.objectDirectory.connectionTranscoder stub] andReturn:@[]] requestGenerators];
    [[[(id)self.objectDirectory.conversationTranscoder stub] andReturn:@[]] requestGenerators];

    // expect
    [[[(id)self.objectDirectory.connectionTranscoder expect] andReturnValue:@NO] isSlowSyncDone];
    [[[(id)self.objectDirectory.conversationTranscoder stub] andReturnValue:@YES] isSlowSyncDone];

    [[(id)self.stateMachine reject] goToState:OCMOCK_ANY];

    // when
    [self.sut dataDidChange];
}

- (void)testThatItDoesNotSwitchStateToSlowSyncIfConversationSyncIsSlowSyncDoneIsFalse
{
    [[[(id)self.objectDirectory.connectionTranscoder stub] andReturn:@[]] requestGenerators];
    [[[(id)self.objectDirectory.conversationTranscoder stub] andReturn:@[]] requestGenerators];


    // expect
    [[[(id)self.objectDirectory.connectionTranscoder expect] andReturnValue:@YES] isSlowSyncDone];
    [[[(id)self.objectDirectory.conversationTranscoder expect] andReturnValue:@NO] isSlowSyncDone];

    [[(id)self.stateMachine reject] goToState:OCMOCK_ANY];

    // when
    [self.sut dataDidChange];
}

@end
