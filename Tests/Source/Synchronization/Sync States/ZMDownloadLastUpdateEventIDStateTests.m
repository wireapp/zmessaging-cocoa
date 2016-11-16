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
#import "StateBaseTest.h"
#import "ZMDownloadLastUpdateEventIDState.h"
#import "ZMStateMachineDelegate.h"
#import "ZMMissingUpdateEventsTranscoder.h"
#import "ZMLastUpdateEventIDTranscoder.h"

@interface ZMDownloadLastUpdateEventIDStateTests : StateBaseTest

@property (nonatomic) ZMDownloadLastUpdateEventIDState *sut;

@end



@implementation ZMDownloadLastUpdateEventIDStateTests

- (void)setUp {
    [super setUp];
    _sut = [[ZMDownloadLastUpdateEventIDState alloc] initWithAuthenticationCenter:self.authenticationStatus clientRegistrationStatus:self.clientRegistrationStatus objectStrategyDirectory:self.objectDirectory stateMachineDelegate:self.stateMachine];
}

- (void)tearDown {
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
    NSArray *expectedObjectSync = @[
                                    [self.objectDirectory lastUpdateEventIDTranscoder]];
    
    [self checkThatItCallsRequestGeneratorsOnObjectsOfClass:expectedObjectSync creationOfStateBlock:^ZMSyncState *(id<ZMObjectStrategyDirectory> directory)
     {
         [[[(id) directory.missingUpdateEventsTranscoder stub] andReturnValue:@NO] hasLastUpdateEventID];
         [[[(id) directory.lastUpdateEventIDTranscoder stub] andReturnValue:@YES] isDownloadingLastUpdateEventID];
         return [[ZMDownloadLastUpdateEventIDState alloc] initWithAuthenticationCenter:self.authenticationStatus clientRegistrationStatus:self.clientRegistrationStatus objectStrategyDirectory:directory stateMachineDelegate:self.stateMachine];
     }];
}

- (void)testThatItMakesTheNotificationSyncStartDowloadingTheLastUpdateEventWhenItEntersTheState
{
    // expect
    [[(id)self.objectDirectory.lastUpdateEventIDTranscoder expect] startRequestingLastUpdateEventIDWithoutPersistingIt];
    
    // when
    [self.sut didEnterState];
}

- (void)testThatItSwitchesStateToSlowSyncPhaseOneWhenWeHaveALastUpdateEventID
{
    // given
    [[[(id) self.objectDirectory.missingUpdateEventsTranscoder stub] andReturnValue:@YES] hasLastUpdateEventID];
    
    // expect
    [[(id)self.stateMachine expect] goToState:self.stateMachine.slowSyncPhaseOneState];
    
    // when
    [self.sut dataDidChange];
    [(id)self.stateMachine verify];
}


- (void)testThatItSwitchesStateToSlowSyncPhaseOneWhenItIsDoneDownloadingLastUpdateEventIDEvenIfItDoesNotRetrievedOne
{
    // given
    [[[(id) self.objectDirectory.missingUpdateEventsTranscoder stub] andReturnValue:@NO] hasLastUpdateEventID];
    [[[(id) self.objectDirectory.lastUpdateEventIDTranscoder stub] andReturnValue:@NO] isDownloadingLastUpdateEventID];

    // expect
    [[(id)self.stateMachine expect] goToState:self.stateMachine.slowSyncPhaseOneState];
    
    // when
    [self.sut dataDidChange];
}

- (void)testThatItDoesNotSwitchStateToSlowSyncPhaseOneWhenItIsStillDownloading
{
    // expect
    [[[(id) self.objectDirectory.missingUpdateEventsTranscoder stub] andReturnValue:@NO] hasLastUpdateEventID];
    [[[(id) self.objectDirectory.lastUpdateEventIDTranscoder stub] andReturnValue:@YES] isDownloadingLastUpdateEventID];
    [[[(id) self.objectDirectory.lastUpdateEventIDTranscoder stub] andReturn:@[]] requestGenerators];
    
    [[(id)self.stateMachine reject] goToState:OCMOCK_ANY];
    
    // when
    [self.sut dataDidChange];
}

@end

