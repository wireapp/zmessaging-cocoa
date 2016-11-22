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


#import "MessagingTest.h"
#import "ZMSlowSyncPhaseTwoState.h"
#import "ZMConnectionTranscoder.h"
#import "ZMSyncStrategy.h"
#import "ZMStateMachineDelegate.h"
#import "StateBaseTest.h"
#import "ZMMissingUpdateEventsTranscoder.h"
#import "ZMLastUpdateEventIDTranscoder.h"

@interface ZMSlowSyncPhaseTwoStateTests : StateBaseTest

@property (nonatomic, readonly) ZMSlowSyncPhaseTwoState* sut;

@end

@implementation ZMSlowSyncPhaseTwoStateTests

- (void)setUp
{
    [super setUp];
    
    _sut = [[ZMSlowSyncPhaseTwoState alloc] initWithAuthenticationCenter:self.authenticationStatus clientRegistrationStatus:self.clientRegistrationStatus objectStrategyDirectory:self.objectDirectory stateMachineDelegate:self.stateMachine];
    
    [self stubRequestsOnHighPriorityObjectSync];

}

-(void)tearDown
{
    _sut = nil;
    [super tearDown];
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
    NSArray *expectedObjectSync = @[[self.objectDirectory userTranscoder]];
    
    [self checkThatItCallsRequestGeneratorsOnObjectsOfClass:expectedObjectSync creationOfStateBlock:^ZMSyncState *(id<ZMObjectStrategyDirectory> directory) {
        
        [[[(id) directory.userTranscoder stub] andReturnValue:@NO] isSlowSyncDone];
        
        return [[ZMSlowSyncPhaseTwoState alloc] initWithAuthenticationCenter:self.authenticationStatus clientRegistrationStatus:self.clientRegistrationStatus objectStrategyDirectory:directory stateMachineDelegate:self.stateMachine];
    }];
    
}

- (void)testThatItDoesNotSwitchStateToProcessEventsWhenUserSyncSlowSyncIsNotDone
{
    // expect
    [[[(id) self.objectDirectory.userTranscoder expect] andReturnValue:@NO] isSlowSyncDone];
    
    [[(id)self.stateMachine reject] goToState:OCMOCK_ANY];
    
    // when
    [self.sut dataDidChange];
}

- (void)testThatItSwitchesStateToProcessEventsWhenUserSyncSlowSyncIsDone
{
    // expect
    [[[(id) self.objectDirectory.userTranscoder expect] andReturnValue:@YES] isSlowSyncDone];
    
    [[(id)self.stateMachine expect] goToState:self.stateMachine.eventProcessingState];
    
    // when
    [self.sut dataDidChange];
}

- (void)testThatItResetsUserAndCallStateTranscoderOnEnteringState
{
    // expect
    [[(id) self.objectDirectory.userTranscoder expect] setNeedsSlowSync];
    [[(id) self.objectDirectory.callStateTranscoder expect] setNeedsSlowSync];

    // when
    [self.sut didEnterState];
}

- (void)testThatItPersistsTheTemporaryLastUpdateEventIDWhenItLeavesTheState
{
    // expect
    [[(id) self.objectDirectory.lastUpdateEventIDTranscoder expect] persistLastUpdateEventID];
    
    // when
    [self.sut didLeaveState];
}

@end
