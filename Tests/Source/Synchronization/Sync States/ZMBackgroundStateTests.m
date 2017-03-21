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


@import ZMTransport;

#import "MessagingTest.h"
#import "ZMSyncState.h"
#import "ZMStateMachineDelegate.h"
#import "StateBaseTest.h"
#import "ZMBackgroundState.h"



@interface ZMBackgroundStateTests : StateBaseTest

@property (nonatomic, readonly) ZMBackgroundState *sut;
@property (nonatomic) id backgroundableSession;

@end



@implementation ZMBackgroundStateTests

- (void)setUp
{
    [super setUp];
    self.backgroundableSession = [OCMockObject mockForProtocol:@protocol(ZMBackgroundable)];
    _sut = [[ZMBackgroundState alloc] initWithAuthenticationCenter:self.authenticationStatus
                                          clientRegistrationStatus:self.clientRegistrationStatus
                                           objectStrategyDirectory:self.objectDirectory
                                              stateMachineDelegate:self.stateMachine
                                             backgroundableSession:self.backgroundableSession];
    
    [self verifyMockLater:self.backgroundableSession];

}

- (void)tearDown {
    _sut = nil;
    self.backgroundableSession = nil;
    [super tearDown];
}

- (void)testThatItSupportsBackgroundFetch;
{
    XCTAssertTrue(self.sut.supportsBackgroundFetch);
}

- (void)testThatThePolicyIsToDiscardEvents
{
    XCTAssertEqual(self.sut.updateEventsPolicy, ZMUpdateEventPolicyIgnore);
}

- (void)testThatItDoesNotSwitchesToSlowSyncState
{
    // expectation
    [[(id)self.stateMachine reject] startQuickSync];
    
    // when
    [self.sut didRequestSynchronization];
}

- (void)testThatItDoesNotSwitchesToBackgroundState
{
    // expectation
    [[(id)self.stateMachine reject] goToState:OCMOCK_ANY];
    
    // when
    [self.sut didEnterBackground];
}

- (void)testThatItDoesSwitchToQuickSyncOnEnteringForeground
{
    // expectation
    [[(id)self.stateMachine expect] startQuickSync];
    
    // when
    [self.sut didEnterForeground];
}

- (NSArray *)syncObjectsUsedByState
{
    return  @[ /* Note: these must be in the same order as in the class */
              self.objectDirectory.flowTranscoder,
              self.objectDirectory.selfTranscoder,
              ];
}

- (void)testThatItReturnsTheFirstRequestReturnedByASync
{
    /*
     NOTE: a failure here might mean that you either forgot to add a new sync to
     self.syncObjectsUsedByThisState, or that the order of that array doesn't match
     the order used by the ZMEventProcessingState
     */
    
    [self checkThatItCallsRequestGeneratorsOnObjectsOfClass:[self syncObjectsUsedByState] creationOfStateBlock:^ZMSyncState *(id<ZMObjectStrategyDirectory> directory) {
        return [[ZMBackgroundState alloc] initWithAuthenticationCenter:self.authenticationStatus clientRegistrationStatus:self.clientRegistrationStatus objectStrategyDirectory:directory stateMachineDelegate:self.stateMachine backgroundableSession:self.backgroundableSession];
    }];
    
}

- (void)testThatItSendsPrepareForSuspendedStateWhenAllTranscodersReturnNil;
{
    // given
    for (id transcoder in self.syncObjectsUsedByState) {
        if([transcoder conformsToProtocol:@protocol(ZMRequestGeneratorSource)]) {
            [[[transcoder stub] andReturn:@[]] requestGenerators];
        } else {
            [[transcoder stub] nextRequest];
        }
    }
    
    // expect
    [[self.backgroundableSession expect] prepareForSuspendedState];
    
    // when
    [self.sut nextRequest];
    
    // finally
    [self.backgroundableSession verify];
}

- (void)testThatItDoesNotSendPrepareForSuspendedStateWhenATranscodersDoesNotReturnNil;
{
    // given
    id<ZMRequestGenerator> generator = [self generatorReturningNiceMockRequest];
    ZMTransportRequest *dummyRequest = [ZMTransportRequest requestGetFromPath:@"foobar"];
    
    for (id transcoder in self.syncObjectsUsedByState) {
        if([transcoder conformsToProtocol:@protocol(ZMRequestGeneratorSource)]) {
            [[[transcoder stub] andReturn:@[generator]] requestGenerators];
        } else {
            [[[transcoder stub] andReturn:dummyRequest] nextRequest];
        }
    }
    
    // expect
    [[self.backgroundableSession reject] prepareForSuspendedState];
    
    // when
    [self.sut nextRequest];
    
    // finally
    [self.backgroundableSession verify];
}

- (void)testThatItOnlySendsPrepareForSuspendedStateOnce;
{
    // given
    for (id transcoder in self.syncObjectsUsedByState) {
        if([transcoder conformsToProtocol:@protocol(ZMRequestGeneratorSource)]) {
            [[[transcoder stub] andReturn:@[]] requestGenerators];
        } else {
            [[transcoder stub] nextRequest];
        }
    }
    
    // expect
    [[self.backgroundableSession expect] prepareForSuspendedState];
    [[self.backgroundableSession reject] prepareForSuspendedState];
    
    // when
    [self.sut nextRequest];
    [self.sut nextRequest];
    [self.sut nextRequest];
    
    // finally
    [self.backgroundableSession verify];
}

- (void)testThatItSendsPrepareForSuspendedAgainAfterReEnteringTheState
{
    // given
    for (id transcoder in self.syncObjectsUsedByState) {
        if([transcoder conformsToProtocol:@protocol(ZMRequestGeneratorSource)]) {
            [[[transcoder stub] andReturn:@[]] requestGenerators];
        } else {
            [[transcoder stub] nextRequest];
        }
    }
    
    // expect
    [[self.backgroundableSession expect] prepareForSuspendedState];
    [[self.backgroundableSession stub] enterForeground];
    [[self.backgroundableSession stub] enterBackground];
    [[self.backgroundableSession expect] prepareForSuspendedState];
    
    // when
    [self.sut nextRequest];
    [self.sut didLeaveState];
    [self.sut didEnterState];
    [self.sut nextRequest];
    
    // finally
    [self.backgroundableSession verify];
}

- (void)testThatItCallsEnterBackgroundOnTheSessionWhenItEnters
{
    // expect
    [[self.backgroundableSession expect] enterBackground];
    
    // when
    [self.sut didEnterState];
    
    // then
    [self.backgroundableSession verify];
}

- (void)testThatItCallsEnterForegroundOnTheSessionWhenItLeaves
{
    // expect
    [[self.backgroundableSession expect] enterForeground];
    
    // when
    [self.sut didLeaveState];
    
    // then
    [self.backgroundableSession verify];
}

@end
