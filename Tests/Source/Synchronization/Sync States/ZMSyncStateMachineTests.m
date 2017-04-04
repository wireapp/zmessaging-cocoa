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
        
    [[self.unauthenticatedState expect] didEnterState];
    
    self.syncStateDelegate = [OCMockObject niceMockForProtocol:@protocol(ZMSyncStateDelegate)];
    [self.syncStateDelegate verify];
    _syncStatus = [[SyncStatus alloc] initWithManagedObjectContext:self.uiMOC syncStateDelegate:self.syncStateDelegate];
    
    _sut = [[ZMSyncStateMachine alloc] initWithAuthenticationStatus:self.authenticationStatus
                                           clientRegistrationStatus:self.clientRegistrationStatus
                                            objectStrategyDirectory:self.objectDirectory
                                                  syncStateDelegate:self.syncStateDelegate
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
    WaitForAllGroupsToBeEmpty(0.5);
    
    [self.unauthenticatedState verify];
    [self.eventProcessingState verify];
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

- (void)testThatWhenItReceivesDataChangeItForwardsItToTheCurrentState
{
    // expect
    [[(id) self.sut.currentState expect] dataDidChange];
    
    // when
    [self.sut dataDidChange];
}

@end
