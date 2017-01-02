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

#import "ZMEventProcessingState.h"
#import "ZMUnauthenticatedState.h"
#import "ZMBackgroundState.h"

#import "ZMUserTranscoder.h"
#import "ZMConversationTranscoder.h"
#import "ZMSelfStrategy.h"
#import "ZMConnectionTranscoder.h"

#import "ZMObjectStrategyDirectory.h"
#import "ZMUserSession.h"
#import "ZMSyncStateMachine+internal.h"
#import "ZMSyncState.h"
#import "ZMBackgroundFetchState.h"
#import "ZMBackgroundTaskState.h"

#import "ZMUserSessionAuthenticationNotification.h"
#import "zmessaging_iOS_Tests-Swift.h"

@interface ZMSyncStateMachineTests : MessagingTest

@property (nonatomic, readonly) id objectDirectory;
@property (nonatomic, readonly) ZMAuthenticationStatus *authenticationStatus;
@property (nonatomic, readonly) ZMClientRegistrationStatus *clientRegistrationStatus;
@property (nonatomic, readonly) SyncStatus *syncStatus;
@property (nonatomic, readonly) id backgroundableSession;
@property (nonatomic, readonly) ZMSyncStateMachine *sut;

@property (nonatomic,readonly) id eventProcessingState;
@property (nonatomic,readonly) id unauthenticatedState;
@property (nonatomic,readonly) id backgroundState;
@property (nonatomic,readonly) id backgroundFetchState;
@property (nonatomic,readonly) id backgroundTaskState;


@property (nonatomic) id syncStateDelegate;

@property (nonatomic) ZMSyncState *dummyState;

@end

@implementation ZMSyncStateMachineTests

- (void)setUp {
    [super setUp];
    
    _objectDirectory = [self createMockObjectStrategyDirectoryInMoc:self.uiMOC];
    _backgroundableSession = [OCMockObject mockForProtocol:@protocol(ZMBackgroundable)];
    [self verifyMockLater:self.backgroundableSession];
    
    ZMCookie *cookie = [[ZMCookie alloc] initWithManagedObjectContext:self.uiMOC cookieStorage:[ZMPersistentCookieStorage storageForServerName:@"test"]];
    
    _authenticationStatus = [[ZMAuthenticationStatus alloc] initWithManagedObjectContext:self.uiMOC cookie:cookie];
    _clientRegistrationStatus = [[ZMClientRegistrationStatus alloc] initWithManagedObjectContext:self.uiMOC loginCredentialProvider:self.authenticationStatus updateCredentialProvider:nil cookie:cookie registrationStatusDelegate:nil];
    
    _eventProcessingState = [OCMockObject mockForClass:ZMEventProcessingState.class];
    [[[[self.eventProcessingState expect] andReturn:self.eventProcessingState] classMethod] alloc];
    (void) [[[self.eventProcessingState expect] andReturn:self.eventProcessingState] initWithAuthenticationCenter:self.authenticationStatus clientRegistrationStatus:self.clientRegistrationStatus objectStrategyDirectory:self.objectDirectory stateMachineDelegate:OCMOCK_ANY slowSynStatus:OCMOCK_ANY];
    [[self.eventProcessingState stub] tearDown];
    [self verifyMockLater:self.eventProcessingState];
    
    _unauthenticatedState = [OCMockObject mockForClass:ZMUnauthenticatedState.class];
    [[[[self.unauthenticatedState expect] andReturn:self.unauthenticatedState] classMethod] alloc];
    (void) [[[self.unauthenticatedState expect] andReturn:self.unauthenticatedState] initWithAuthenticationCenter:self.authenticationStatus clientRegistrationStatus:self.clientRegistrationStatus objectStrategyDirectory:self.objectDirectory stateMachineDelegate:OCMOCK_ANY application:self.application];
    [[self.unauthenticatedState stub] tearDown];
    [self verifyMockLater:self.unauthenticatedState];
    
    _backgroundState = [OCMockObject mockForClass:ZMBackgroundState.class];
    [[[[self.backgroundState expect] andReturn:self.backgroundState] classMethod] alloc];
    (void) [[[self.backgroundState expect] andReturn:self.backgroundState] initWithAuthenticationCenter:self.authenticationStatus clientRegistrationStatus:self.clientRegistrationStatus objectStrategyDirectory:self.objectDirectory stateMachineDelegate:OCMOCK_ANY backgroundableSession:self.backgroundableSession];
    [[self.backgroundState stub] tearDown];
    [self verifyMockLater:self.backgroundState];
    
    _backgroundFetchState = [OCMockObject mockForClass:ZMBackgroundFetchState.class];
    [[[[self.backgroundFetchState expect] andReturn:self.backgroundFetchState] classMethod] alloc];
    (void) [[[self.backgroundFetchState expect] andReturn:self.backgroundFetchState] initWithAuthenticationCenter:self.authenticationStatus clientRegistrationStatus:self.clientRegistrationStatus objectStrategyDirectory:self.objectDirectory stateMachineDelegate:OCMOCK_ANY];
    [[self.backgroundFetchState stub] tearDown];
    [self verifyMockLater:self.backgroundFetchState];
    
    _backgroundTaskState = [OCMockObject mockForClass:ZMBackgroundTaskState.class];
    [[[[self.backgroundTaskState expect] andReturn:self.backgroundTaskState] classMethod] alloc];
    (void) [[[self.backgroundTaskState expect] andReturn:self.backgroundTaskState] initWithAuthenticationCenter:self.authenticationStatus clientRegistrationStatus:self.clientRegistrationStatus objectStrategyDirectory:self.objectDirectory stateMachineDelegate:OCMOCK_ANY];
    [[self.backgroundTaskState stub] tearDown];
    [self verifyMockLater:self.backgroundTaskState];
    
    [[self.unauthenticatedState expect] didEnterState];
    
    self.syncStateDelegate = [OCMockObject niceMockForProtocol:@protocol(ZMSyncStateDelegate)];
    [self.syncStateDelegate verify];
    _syncStatus = [[SyncStatus alloc] initWithManagedObjectContext:self.uiMOC syncStateDelegate:self.syncStateDelegate];
    
    _sut = [[ZMSyncStateMachine alloc] initWithAuthenticationStatus:self.authenticationStatus
                                           clientRegistrationStatus:self.clientRegistrationStatus
                                            objectStrategyDirectory:self.objectDirectory
                                                  syncStateDelegate:self.syncStateDelegate
                                              backgroundableSession:self.backgroundableSession
                                                        application:self.application
                                                      slowSynStatus:self.syncStatus];
    WaitForAllGroupsToBeEmpty(0.5);
    
    self.dummyState = [OCMockObject mockForClass:ZMSyncState.class];
}

- (void)tearDown
{
    [self.eventProcessingState stopMocking];
    [self.unauthenticatedState stopMocking];
    [self.backgroundState stopMocking];
    [self.backgroundFetchState stopMocking];
    [self.backgroundTaskState stopMocking];

    [self.clientRegistrationStatus tearDown];
    
    _clientRegistrationStatus = nil;
    _eventProcessingState = nil;
    _unauthenticatedState = nil;
    _backgroundState = nil;
    
    self.dummyState = nil;
    _authenticationStatus = nil;
    _objectDirectory = nil;
    
    [self.sut tearDown];
    _sut = nil;
    
    [super tearDown];
}

- (void)testThatItCreatesStates
{
    XCTAssertEqual(self.sut.eventProcessingState, self.eventProcessingState);
    XCTAssertEqual(self.sut.unauthenticatedState, self.unauthenticatedState);
    XCTAssertEqual(self.sut.backgroundState, self.backgroundState);
}

- (void)testThatItStartsInTheLoginState
{
    XCTAssertEqual(self.sut.currentState, self.unauthenticatedState);
}

- (void)testThatItGoesToUnauthorizedStateWhenAuthorizationFailedNotificationIsPosted
{
    //given
    [[self.unauthenticatedState expect] didLeaveState];
    [[self.eventProcessingState expect] didEnterState];
    [self.sut goToState:self.eventProcessingState];
    
    //expect
    [[self.eventProcessingState expect] didFailAuthentication];
    
    //when
    [ZMUserSessionAuthenticationNotification notifyAuthenticationDidFail:[NSError errorWithDomain:@"" code:0 userInfo:nil]];
    
    [self.unauthenticatedState verify];
    [self.eventProcessingState verify];
}

- (void)testThatItStartsBackgroundFetchWhenTheCurrentStateSupportsIt;
{
    // given
    ZMBackgroundFetchHandler handler = ^(ZMBackgroundFetchResult ZM_UNUSED result) {
        XCTFail(@"Should not get called.");
    };
    id originalState = self.sut.currentState;
    
    // expect
    [[[(id) originalState expect] andReturnValue:@(YES)] supportsBackgroundFetch];
    [[(id) originalState expect] didLeaveState];
    [[self.backgroundFetchState expect] didEnterState];
    [[self.backgroundFetchState expect] setFetchCompletionHandler:handler];
    
    // when
    [self.sut startBackgroundFetchWithCompletionHandler:handler];
    
    // then
    XCTAssertEqual(self.sut.currentState, self.backgroundFetchState);
    [originalState verify];
    [self.backgroundFetchState verify];
}

- (void)testThatItDoesNotStartBackgroundFetchWhenTheCurrentStateDoesNotSupportsIt;
{
    // given
    XCTestExpectation *expectation = [self expectationWithDescription:@"Background fetch completed"];
    ZMBackgroundFetchHandler handler = ^(ZMBackgroundFetchResult result) {
        XCTAssertEqual(result, ZMBackgroundFetchResultNoData);
        [expectation fulfill];
    };
    
    // expect
    [[[(id) self.sut.currentState expect] andReturnValue:@(NO)] supportsBackgroundFetch];
    [[(id) self.sut.currentState reject] didLeaveState];
    
    // when
    [self.sut startBackgroundFetchWithCompletionHandler:handler];
    
    // then
    XCTAssert([self waitForCustomExpectationsWithTimeout:0.5]);
}

- (void)testThatItStartsBackgroundTaskWhenTheCurrentStateSupportsIt;
{
    // given
    ZMBackgroundTaskHandler handler = ^(ZMBackgroundTaskResult ZM_UNUSED result) {
        XCTFail(@"Should not get called.");
    };
    id originalState = self.sut.currentState;
    
    // expect
    [[[(id) originalState expect] andReturnValue:@(YES)] supportsBackgroundFetch];
    [[(id) originalState expect] didLeaveState];
    [[self.backgroundTaskState expect] didEnterState];
    [[self.backgroundTaskState expect] setTaskCompletionHandler:handler];
    
    // when
    [self.sut startBackgroundTaskWithCompletionHandler:handler];
    
    // then
    XCTAssertEqual(self.sut.currentState, self.backgroundTaskState);
    [originalState verify];
    [self.backgroundTaskState verify];
}

- (void)testThatItDoesNotStartBackgroundTaskWhenTheCurrentStateDoesNotSupportsIt;
{
    // given
    XCTestExpectation *expectation = [self expectationWithDescription:@"Background fetch completed"];
    ZMBackgroundTaskHandler handler = ^(ZMBackgroundTaskResult result) {
        XCTAssertEqual(result, ZMBackgroundTaskResultUnavailable);
        [expectation fulfill];
    };
    
    // expect
    [[[(id) self.sut.currentState expect] andReturnValue:@(NO)] supportsBackgroundFetch];
    [[(id) self.sut.currentState reject] didLeaveState];
    
    // when
    [self.sut startBackgroundTaskWithCompletionHandler:handler];
    
    // then
    XCTAssert([self waitForCustomExpectationsWithTimeout:0.5]);
}


- (void)testThatItCallsNextRequestOnTheCurrentState
{
    // given
    [self.authenticationStatus setAuthenticationCookieData:[NSData data]];
    ZMTransportRequest *request = [ZMTransportRequest requestGetFromPath:@"bla"];
    
    // expect
    [[[(id)self.sut.currentState expect] andReturn:request] nextRequest];
    
    // when
    XCTAssertEqual(request, [self.sut nextRequest]);
}

- (void)testThatItCallsUpdateEventPolicyOnTheCurrentState
{
    // expect
    [[[(id)self.sut.currentState expect] andReturnValue:OCMOCK_VALUE(ZMUpdateEventPolicyBuffer)] updateEventsPolicy];
    [[[(id)self.sut.currentState expect] andReturnValue:OCMOCK_VALUE(ZMUpdateEventPolicyIgnore)] updateEventsPolicy];
    [[[(id)self.sut.currentState expect] andReturnValue:OCMOCK_VALUE(ZMUpdateEventPolicyProcess)] updateEventsPolicy];
    
    // when
    XCTAssertEqual(self.sut.updateEventsPolicy, ZMUpdateEventPolicyBuffer);
    XCTAssertEqual(self.sut.updateEventsPolicy, ZMUpdateEventPolicyIgnore);
    XCTAssertEqual(self.sut.updateEventsPolicy, ZMUpdateEventPolicyProcess);
}


- (void)testThatItCallsdidFailAuthenticationOnTheCurrentState
{
    // expect
    [[(id)self.sut.currentState expect] didFailAuthentication];
    
    // when
    [self.sut didFailAuthentication];
}

- (void)testThatItCallsDidEnterStateWhenSwitchingState
{
    // expect
    [[(id) self.sut.currentState stub] didLeaveState];
    [[(id) self.dummyState expect] didEnterState];
    
    // when
    [self.sut goToState:self.dummyState];
    
    // then
    XCTAssertEqual(self.sut.currentState, self.dummyState);
    
}

- (void)testThatItCallsDidLeaveStateWhenSwitchingState
{
    // expect
    [[(id) self.sut.currentState expect] didLeaveState];
    [[(id) self.dummyState stub] didEnterState];
    
    // when
    [self.sut goToState:self.dummyState];
    
    // then
    XCTAssertEqual(self.sut.currentState, self.dummyState);
    
}

- (void)testThatItCallsDidFailAuthenticationIfTheLoggedInStatusSwitchesFromYesToNo
{
    // given
    [self.authenticationStatus setAuthenticationCookieData:[NSData data]];
    [[[(id)self.sut.currentState expect] andReturn:nil] nextRequest];
    [[[(id)self.sut.currentState expect] andReturn:nil] nextRequest];
    
    // expect
    [[(id)self.sut.currentState expect] didFailAuthentication];

    // when
    [self.sut nextRequest];
    [self.sut.currentState didFailAuthentication];
    [self.sut nextRequest];
}

- (void)testThatItCallsNextRequestOnANewStateIfTheCurrentStateSwitchesToAnotherStateAndItReturnsNil
{
    // given
    [self.authenticationStatus setAuthenticationCookieData:[NSData data]];
    ZMTransportRequest *request = [ZMTransportRequest requestGetFromPath:@"bla"];
    
    [[(id) self.sut.currentState stub] didLeaveState];
    [[[(id) self.dummyState expect] andReturn:request] nextRequest];
    [[(id) self.dummyState stub] didEnterState];
    
    [[[[(id) self.sut.currentState expect] andDo:^(NSInvocation *i ZM_UNUSED) {
        [self.sut goToState:self.dummyState];
    }] andReturn:nil] nextRequest];
    
    // when
    XCTAssertEqual(request, [self.sut nextRequest]);
}

- (void)testThatItDoesNotCallsNextRequestOnANewStateIfTheCurrentStateSwitchesToAnotherStateAndItReturnsARequest
{
    // given
    [self.authenticationStatus setAuthenticationCookieData:[NSData data]];
    ZMTransportRequest *request = [ZMTransportRequest requestGetFromPath:@"bla"];
    
    [[(id) self.sut.currentState stub] didLeaveState];
    [[[(id) self.dummyState reject] andReturn:nil] nextRequest];
    [[(id) self.dummyState stub] didEnterState];
    
    [[[[(id) self.sut.currentState expect] andDo:^(NSInvocation *i ZM_UNUSED) {
        [self.sut goToState:self.dummyState];
    }] andReturn:request] nextRequest];
    
    // when
    XCTAssertEqual(request, [self.sut nextRequest]);
}

- (void)testThatItForwardsDidStartSyncToSyncStateDelegate
{
    // expect
    [[self.syncStateDelegate expect] didStartSync];
    
    // when
    [self.sut didStartSync];
    
    // then
    [self.syncStateDelegate verify];
}

- (void)testThatItForwardsDidFinishSyncToSyncStateDelegate
{
    // expect
    [[self.syncStateDelegate expect] didFinishSync];
    
    // when
    [self.sut didFinishSync];
    
    // then
    [self.syncStateDelegate verify];
}

- (void)testThatItForwardsDidEnterBackgroundToTheCurrentState
{
    // expect
    [[(id) self.sut.currentState expect] didEnterBackground];
    
    // when
    [self.sut enterBackground];
}

- (void)testThatItForwardsDidEnterForegroundToTheCurrentState
{
    // expect
    [[(id) self.sut.currentState expect] didEnterForeground];
    
    // when
    [self.sut enterForeground];
}

- (void)testThatWhenItReceivesDataChangeItForwardsItToTheCurrentState
{
    // expect
    [[(id) self.sut.currentState expect] dataDidChange];
    
    // when
    [self.sut dataDidChange];
}

@end
