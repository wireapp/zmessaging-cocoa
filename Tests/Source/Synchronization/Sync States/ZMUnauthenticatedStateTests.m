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


@import UIKit;
@import WireSyncEngine;
@import WireDataModel;

#import "MessagingTest.h"
#import "ZMUnauthenticatedState+Tests.h"
#import "ZMStateMachineDelegate.h"
#import "ZMUserSession+Internal.h"
#import "ZMSelfTranscoder.h"
#import "ZMSyncStrategy.h"
#import "StateBaseTest.h"
#import "ZMLoginTranscoder+Internal.h"
#import "ZMCredentials+Internal.h"
#import "ZMAuthenticationStatus.h"
#import "ZMUserSessionAuthenticationNotification.h"
#import "ZMRegistrationTranscoder.h"
#import "WireSyncEngine_iOS_Tests-Swift.h"



@interface ZMUnauthenticatedStateTests : StateBaseTest

@property (nonatomic) ZMUnauthenticatedState *sut;
@property (nonatomic) id mockTimer;
@property (nonatomic) id<ZMTimerClient> timerTarget;
@property (nonatomic) NSUInteger timerCreationCount;
@property (nonatomic) NSUInteger timerCancelCount;


@property (nonatomic) NSDictionary *timerUserInfo;

@property (nonatomic, readonly) id staticMockedTimer;

@end



@implementation ZMUnauthenticatedStateTests

- (void)verifyAndRemoveTimer
{
    // verify previous
    if(self.timerTarget != nil) {
        XCTAssertEqual(self.timerTarget, self.sut);
    }
    self.mockTimer = nil;
    self.timerUserInfo = nil;
    self.timerTarget = nil;
}

- (id)createTimerWithTarget:(id)target
{
    ++self.timerCreationCount;

    // create new
    self.mockTimer = self.staticMockedTimer;
    
    // set user info
    [(ZMTimer *)[self.mockTimer stub] setUserInfo:[OCMArg checkWithBlock:^BOOL(id obj) {
        self.timerUserInfo = obj;
        return YES;
    }]];
    
    // get user info
    (void)ZM_ALLOW_MISSING_SELECTOR([(ZMTimer*) [[self.mockTimer stub] andCall:@selector(timerUserInfo) onObject:self] userInfo]);
    
    // fire
    [[self.mockTimer expect] fireAfterTimeInterval:[ZMUnauthenticatedState loginTimeout]];
    
    // cancel
    [[[self.mockTimer stub] andDo:^(NSInvocation *i ZM_UNUSED) {
        ++self.timerCancelCount;
    }] cancel];
    
    self.timerTarget = target;
    
    [self verifyMockLater:self.mockTimer];
    
    return self.mockTimer;
}

- (id)createTimerWithTarget:(id)target queue:(id)queue
{
    NOT_USED(queue);
    return [self createTimerWithTarget:target];
}


- (void)setUp
{
    [super setUp];
    
    self.timerCreationCount = 0;
    self.timerCancelCount = 0;
    
    // Make sure we capture all static timerWith... on timer
    _staticMockedTimer = [OCMockObject mockForClass:ZMTimer.class];
    [[[self.staticMockedTimer stub] andCall:@selector(createTimerWithTarget:) onObject:self] timerWithTarget:OCMOCK_ANY];
    [[[self.staticMockedTimer stub] andCall:@selector(createTimerWithTarget:queue:) onObject:self] timerWithTarget:OCMOCK_ANY operationQueue:OCMOCK_ANY];
    
    [self verifyMockLater:self.staticMockedTimer];
    
    [self recreateSUT];
    
    XCTAssertEqual(self.mockTimer, self.sut.loginFailureTimer);
}

- (void)recreateSUT
{
    _sut = [[ZMUnauthenticatedState alloc]
            initWithAuthenticationCenter:self.authenticationStatus
            clientRegistrationStatus:self.clientRegistrationStatus
            objectStrategyDirectory:self.objectDirectory
            stateMachineDelegate:self.stateMachine
            application:self.application];
}

- (void)tearDown
{
    self.timerTarget = nil;
    _staticMockedTimer = nil;
    _sut = nil;
    
    [self verifyAndRemoveTimer];
    [self.staticMockedTimer stopMocking];
    [super tearDown];
}


- (void)forceCreationOfTimer
{
    XCTAssertNil(self.sut.loginFailureTimer);
    self.sut.loginFailureTimer = [self createTimerWithTarget:self.sut];
    [self.sut.loginFailureTimer fireAfterTimeInterval:[ZMUnauthenticatedState loginTimeout]];
}

- (void)testThatThePolicyIsToIgnoreEvents
{
    XCTAssertEqual(self.sut.updateEventsPolicy, ZMUpdateEventPolicyIgnore);
}

- (void)testThatItDoesNotSupportBackgroundFetch;
{
    XCTAssertFalse(self.sut.supportsBackgroundFetch);
}

- (void)testThatItDoesNotSwitchesToSlowSyncState
{
    // expectation
    [[(id)self.stateMachine reject] goToState:OCMOCK_ANY];
    
    // when
    [self.sut didRequestSynchronization];
}

- (void)testThatItSwitchesToLoginBackgroundState
{
    // expectation
    [[(id)self.stateMachine expect] goToState:self.stateMachine.unauthenticatedBackgroundState];
    
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


- (void)testThatItDoesNotSwitchesStateOnFailedAuthentication
{
    // expectation
    [[(id)self.stateMachine reject] goToState:OCMOCK_ANY];
    
    // when
    [self.sut didFailAuthentication];
}

- (void)testThatWhenWeAreLoggedInWeAskForTheSelfUser
{
    // given
    ZMTransportRequest *selfUserRequest = [ZMTransportRequest requestWithPath:@"/mock/selfUser" method:ZMMethodGET payload:nil];
    [self.authenticationStatus setAuthenticationCookieData:[@"foo" dataUsingEncoding:NSUTF8StringEncoding]];
    
    // expect
    [[(id)self.stateMachine reject] goToState:OCMOCK_ANY];
    [[[(id)self.objectDirectory.selfTranscoder stub] andReturnValue:@NO] isSelfUserComplete];
    id<ZMRequestGenerator> generator = [self generatorReturningRequest:selfUserRequest];
    [[[(id)self.objectDirectory.selfTranscoder expect] andReturn:@[generator]] requestGenerators];
    
    // when
    ZMTransportRequest *request = [self.sut nextRequest];
    
    // then
    XCTAssertEqualObjects(request, selfUserRequest);
}

- (void)testThatWeSwitchToTheNotificationCatchUpStateWhenEnteringTheStateAndAlreadyLoggedIn
{
    // given
    [self recreateSUT];
    
    [ZMUser selfUserInContext:self.uiMOC].remoteIdentifier = [NSUUID createUUID];
    [self.uiMOC setPersistentStoreMetadata:@"someD" forKey:ZMPersistedClientIdKey];
    
    [self.authenticationStatus setAuthenticationCookieData:[@"foo" dataUsingEncoding:NSUTF8StringEncoding]];
    
    // expect
    [self.application setActive];
    [[(id)self.stateMachine expect] startQuickSync];
    [[[(id)self.objectDirectory.selfTranscoder stub] andReturnValue:@YES] isSelfUserComplete]; //we also check for remoteIdentifier directly
    
    // when
    [self.sut didEnterState];
}

- (void)testThatWeSwitchToTheBackgroundStateWhenEnteringTheStateAndAlreadyLoggedInAndInTheBackground;
{
    // given
    [self recreateSUT];
    
    [ZMUser selfUserInContext:self.uiMOC].remoteIdentifier = [NSUUID createUUID];
    [self.uiMOC setPersistentStoreMetadata:@"someD" forKey:ZMPersistedClientIdKey];

    [self.authenticationStatus setAuthenticationCookieData:[@"foo" dataUsingEncoding:NSUTF8StringEncoding]];
    
    // expect
    [self.application setBackground];
    [[(id)self.stateMachine expect] goToState:self.stateMachine.backgroundState];
    [[[(id)self.objectDirectory.selfTranscoder stub] andReturnValue:@YES] isSelfUserComplete];
    
    // when
    [self.sut didEnterState];
}


- (void)testThatWeDoNotSwitchToFollowingStateIfUserSessionIsNotLoggedIn
{
    // given
    [[[(id)self.objectDirectory.loginTranscoder stub] andReturn:@[]] requestGenerators];
    [self.authenticationStatus prepareForLoginWithCredentials:[ZMEmailCredentials credentialsWithEmail:@"foo@example.com" password:@"12345678"]];
    
    // expect
    [[(id)self.stateMachine reject] goToState:OCMOCK_ANY];
    [[(id)self.stateMachine reject] startQuickSync];
    
    // when
    [self.sut dataDidChange];
}

- (void)testThatItForwardsNextRequestToPhoneVerificationTranscoderIfRequiredToRequestCodeForRegistration
{
    ZMTransportRequest *loginCodeRequest = [ZMTransportRequest requestWithPath:@"/mock" method:ZMMethodGET payload:nil];
    [self.authenticationStatus prepareForRequestingPhoneVerificationCodeForRegistration:@"123456789"];
    
    // expectations
    [[[(id)self.objectDirectory.phoneNumberVerificationTranscoder expect] andReturn:loginCodeRequest] nextRequest];
    
    // when
    ZMTransportRequest *nextRequest = [self.sut nextRequest];
    
    // then
    XCTAssertEqual(nextRequest, loginCodeRequest);
}

- (void)testThatItForwardsNextRequestToLoginCodeTranscoderIfRequiredToRequestCodeForLogIn
{
    ZMTransportRequest *loginCodeRequest = [ZMTransportRequest requestWithPath:@"/mock" method:ZMMethodGET payload:nil];
    [self.authenticationStatus prepareForRequestingPhoneVerificationCodeForLogin:@"123456789"];
    
    // expectations
    id <ZMRequestGenerator> generator  = [self generatorReturningRequest:loginCodeRequest];
    [[[(id)self.objectDirectory.loginCodeRequestTranscoder expect] andReturn:@[generator]] requestGenerators];
    
    // when
    ZMTransportRequest *nextRequest = [self.sut nextRequest];
    
    // then
    XCTAssertEqual(nextRequest, loginCodeRequest);
}

- (void)testThatItForwardsNextRequestToPhoneNumberVerificationTranscoderIfRequiredToVerifyARegistrationPhoneNumber
{
    // given
    ZMTransportRequest *request = [ZMTransportRequest requestWithPath:@"/mock" method:ZMMethodGET payload:nil];
    [self.authenticationStatus prepareForRegistrationPhoneVerificationWithCredentials:[ZMPhoneCredentials credentialsWithPhoneNumber:@"+4912345678900" verificationCode:@"123456"]];
    
    // expectations
    [[[(id)self.objectDirectory.phoneNumberVerificationTranscoder expect] andReturn:request] nextRequest];
    
    // when
    ZMTransportRequest *nextRequest = [self.sut nextRequest];
    
    // then
    XCTAssertEqual(nextRequest, request);
}

- (void)testThatItForwardsNextRequestToRegistrationTranscoderIfRegisteringWithEmail
{
    // given
    ZMTransportRequest *request = [ZMTransportRequest requestWithPath:@"/mock" method:ZMMethodGET payload:nil];
    [self.authenticationStatus prepareForRegistrationOfUser:[ZMCompleteRegistrationUser registrationUserWithEmail:@"Foo@example.com" password:@"12345678dd"]];
    
    // expectations
    id <ZMRequestGenerator> generator  = [self generatorReturningRequest:request];
    [[[(id)self.objectDirectory.registrationTranscoder expect] andReturn:@[generator]] requestGenerators];
    
    // when
    ZMTransportRequest *nextRequest = [self.sut nextRequest];
    
    // then
    XCTAssertEqual(nextRequest, request);
}

- (void)testThatItForwardsNextRequestToRegistrationTranscoderIfRegisteringWithPhone
{
    // given
    ZMTransportRequest *request = [ZMTransportRequest requestWithPath:@"/mock" method:ZMMethodGET payload:nil];
    [self.authenticationStatus prepareForRegistrationOfUser:[ZMCompleteRegistrationUser registrationUserWithPhoneNumber:@"+4912345678900" phoneVerificationCode:@"1234567"]];
    
    // expectations
    id <ZMRequestGenerator> generator  = [self generatorReturningRequest:request];
    [[[(id)self.objectDirectory.registrationTranscoder expect] andReturn:@[generator]] requestGenerators];
    
    // when
    ZMTransportRequest *nextRequest = [self.sut nextRequest];
    
    // then
    XCTAssertEqual(nextRequest, request);
}

- (void)testThatItForwardsNextRequestToLoginTranscoderIfLoggingInWithPhone
{
    // given
    ZMTransportRequest *request = [ZMTransportRequest requestWithPath:@"/mock" method:ZMMethodGET payload:nil];
    [self.authenticationStatus prepareForLoginWithCredentials:[ZMPhoneCredentials credentialsWithPhoneNumber:@"+4912345678900" verificationCode:@"1234567"]];
    
    // expectations
    id <ZMRequestGenerator> generator  = [self generatorReturningRequest:request];
    [[[(id)self.objectDirectory.loginTranscoder expect] andReturn:@[generator]] requestGenerators];
    
    // when
    ZMTransportRequest *nextRequest = [self.sut nextRequest];
    
    // then
    XCTAssertEqual(nextRequest, request);
}

- (void)testThatItForwardsNextRequestToLoginTranscoderIfLoggingInWithEmail
{
    // given
    ZMTransportRequest *request = [ZMTransportRequest requestWithPath:@"/mock" method:ZMMethodGET payload:nil];
    [self.authenticationStatus prepareForLoginWithCredentials:[ZMEmailCredentials credentialsWithEmail:@"foo@@example.com" password:@"$#%#$^@21"]];
    
    // expectations
    id <ZMRequestGenerator> generator  = [self generatorReturningRequest:request];
    [[[(id)self.objectDirectory.loginTranscoder expect] andReturn:@[generator]] requestGenerators];
    
    // when
    ZMTransportRequest *nextRequest = [self.sut nextRequest];
    
    // then
    XCTAssertEqual(nextRequest, request);
}

- (void)testThatItForwardsNextRequestToLoginTranscoderIfWaitingForEmailVerification
{
    // given
    ZMTransportRequest *request = [ZMTransportRequest requestWithPath:@"/mock" method:ZMMethodGET payload:nil];
    [self.authenticationStatus prepareForRegistrationOfUser:[ZMCompleteRegistrationUser registrationUserWithEmail:@"Foo@example.com" password:@"12345678dd"]];
    [self.authenticationStatus didFailRegistrationWithDuplicatedEmail];
    
    // expectations
    id <ZMRequestGenerator> generator  = [self generatorReturningRequest:request];
    [[[(id)self.objectDirectory.loginTranscoder expect] andReturn:@[generator]] requestGenerators];
    
    // when
    ZMTransportRequest *nextRequest = [self.sut nextRequest];
    
    // then
    XCTAssertEqual(nextRequest, request);
}


- (void)testThatItDoesNotSendALoginRequestIfAlreadyLoggedInAndHasSelfUser
{
    // given
    [ZMUser selfUserInContext:self.uiMOC].remoteIdentifier = [NSUUID createUUID];
    
    [self.authenticationStatus setAuthenticationCookieData:[@"foo" dataUsingEncoding:NSUTF8StringEncoding]];
    [[[(id)self.objectDirectory.selfTranscoder stub] andReturnValue:@YES] isSelfUserComplete];
    [[[(id)self.objectDirectory.loginTranscoder stub] andReturn:nil] nextRequest];
    [[(id)self.stateMachine stub] startQuickSync];
    
    // when
    ZMTransportRequest *nextRequest = [self.sut nextRequest];
    
    // then
    XCTAssertNil(nextRequest);
}


@end


@implementation ZMUnauthenticatedStateTests (LoginTimer)

- (void)testThatItStopsTheTimerWhenLeavingTheState
{
    // expect
    [[self.mockTimer expect] cancel];
    
    // when
    [self.sut didLeaveState];
}

- (void)testThatItDoesNotWipeTheCredentialsIfTheCredentialsChangedOnTimerExpiration
{
    // given
    ZMCredentials *cred1 = [ZMEmailCredentials credentialsWithEmail:@"bar@example.com" password:@"gdfbdgbnd"];
    ZMCredentials *cred2 = [ZMEmailCredentials credentialsWithEmail:@"MARIO@example.com" password:@"kjhgfdss"];
    
    // expect
    [[[(id)self.objectDirectory.selfTranscoder stub] andReturnValue:@NO] isSelfUserComplete];
    [[(id)self.objectDirectory.selfTranscoder stub] setNeedsSlowSync];
    [[(id)self.objectDirectory.registrationTranscoder stub] resetRegistrationState];

    // when
    [self.sut didEnterState];
    [self.authenticationStatus prepareForLoginWithCredentials:cred1];
    id originalUserInfo = self.timerUserInfo;
    

    [self.authenticationStatus prepareForLoginWithCredentials:cred2];
    
    self.timerUserInfo = originalUserInfo;
    [self.sut timerDidFire:self.mockTimer];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(self.authenticationStatus.currentPhase, ZMAuthenticationPhaseLoginWithEmail);
    XCTAssertEqualObjects(self.authenticationStatus.loginCredentials.email, cred2.email);
    XCTAssertEqualObjects(self.authenticationStatus.loginCredentials.password, cred2.password);
}

- (void)testThatItWipesTheCredentialsIfTheCredentialsDidNotChangeOnTimerExpiration
{
    // given
    ZMCredentials *cred1 = [ZMEmailCredentials credentialsWithEmail:@"bar@baz.foo" password:@"gdfbdgbnd"];

    [self.authenticationStatus prepareForLoginWithCredentials:cred1];
    
    // expect
    [[[(id)self.objectDirectory.selfTranscoder stub] andReturnValue:@NO] isSelfUserComplete];
    [[(id)self.objectDirectory.selfTranscoder stub] setNeedsSlowSync];
    [[(id)self.objectDirectory.registrationTranscoder stub] resetRegistrationState];

    __block BOOL notified = NO;
    id<ZMAuthenticationObserverToken> token = [ZMUserSessionAuthenticationNotification addObserverWithBlock:^(ZMUserSessionAuthenticationNotification *note) {
        notified = YES;
        XCTAssertNotNil(note.error);
        XCTAssertEqual(ZMUserSessionNetworkError, (ZMUserSessionErrorCode)note.error.code);
    }];
    
    // when
    [self.sut didEnterState];
    [self.sut timerDidFire:self.mockTimer];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssert(notified);
    [ZMUserSessionAuthenticationNotification removeObserver:token];
    XCTAssertEqual(self.authenticationStatus.currentPhase, ZMAuthenticationPhaseUnauthenticated);
    XCTAssertNil(self.authenticationStatus.loginCredentials);
}

- (void)testThatItDoesNotWipeTheCredentialsIfTheTheCredentialsDidNotChangeOnTimerExpirationButIsWaitingForEmailVerification
{
    // given
    ZMCredentials *cred1 = [ZMEmailCredentials credentialsWithEmail:@"bar@baz.foo" password:@"gdfbdgbnd"];
    
    [self.authenticationStatus prepareForLoginWithCredentials:cred1];
    [self.authenticationStatus didFailLoginWithEmailBecausePendingValidation];

    
    // expect
    [[[(id)self.objectDirectory.selfTranscoder stub] andReturnValue:@NO] isSelfUserComplete];
    [[(id)self.objectDirectory.selfTranscoder stub] setNeedsSlowSync];
    [[(id)self.objectDirectory.registrationTranscoder stub] resetRegistrationState];
    
    
    // when
    [self.sut didEnterState];
    [self.sut timerDidFire:self.mockTimer];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
}

- (void)testThatItStartsTheTimerWhenTheStateIsEnteredIfTheCredentialsAreSet
{
    // given
    ZMCredentials *credentials = [ZMEmailCredentials credentialsWithEmail:@"foo" password:@"yyyyyyetth"];
    [self.authenticationStatus prepareForLoginWithCredentials:credentials];
    
    // expect
    [[[(id)self.objectDirectory.selfTranscoder stub] andReturnValue:@NO] isSelfUserComplete];
    [[(id)self.objectDirectory.selfTranscoder stub] setNeedsSlowSync];
    [[(id)self.objectDirectory.registrationTranscoder stub] resetRegistrationState];


    // when
    [self.sut didEnterState];
    
    // then
    XCTAssertEqual(self.timerCreationCount, 1u);
}


- (void)testThatItDoesNotStartTheTimerWhenTheStateIsEnteredIfTheCredentialsAreNotSet
{
    // expect
    [[[(id)self.objectDirectory.selfTranscoder stub] andReturnValue:@NO] isSelfUserComplete];
    [[(id)self.objectDirectory.selfTranscoder stub] setNeedsSlowSync];
    [[(id)self.objectDirectory.registrationTranscoder stub] resetRegistrationState];

    
    // when
    [self.sut didEnterState];
    
    // then
    XCTAssertEqual(self.timerCreationCount, 0u);

}

- (void)testThatItDoesNotStartTheTimerWhenTheStateIsEnteredIfTheCredentialsIsSetAndIsWaitingForEmailVerification
{
    // given
    ZMCredentials *credentials = [ZMEmailCredentials credentialsWithEmail:@"foo" password:@"yyyyyyetth"];
    [self.authenticationStatus prepareForLoginWithCredentials:credentials];
    [self.authenticationStatus didFailLoginWithEmailBecausePendingValidation];
    
    // expect
    [[[(id)self.objectDirectory.selfTranscoder stub] andReturnValue:@NO] isSelfUserComplete];
    [[(id)self.objectDirectory.selfTranscoder stub] setNeedsSlowSync];
    [[(id)self.objectDirectory.registrationTranscoder stub] resetRegistrationState];

    
    // when
    [self.sut didEnterState];
    
    // then
    XCTAssertEqual(self.timerCreationCount, 0u);
}

- (void)testThatItCancelsAndRestartTheTimerWhenTheAuthenticationDataChanges
{
    // given
    ZMCredentials *credentials = [ZMEmailCredentials credentialsWithEmail:@"foo" password:@"yyyyyyetth"];
    [self.authenticationStatus prepareForLoginWithCredentials:credentials];


    [self forceCreationOfTimer];
    self.timerCreationCount = 0;
    
    // when
    [self.sut didChangeAuthenticationData];
    
    // then
    XCTAssertNotNil(self.sut.loginFailureTimer);
    XCTAssertEqual(self.sut.loginFailureTimer, self.mockTimer);
    
    XCTAssertEqual(self.timerCancelCount, 1u);
    XCTAssertEqual(self.timerCreationCount, 1u);
}

- (void)testThatItCancelsButDoesNotRestartTheTimerWhenTheAuthenticationDataChangesAndTheCredentialsAreNil
{
    // given
    [self forceCreationOfTimer];
    self.timerCreationCount = 0;
    
    // when
    [self.sut didChangeAuthenticationData];
    
    // then
    XCTAssertEqual(self.timerCreationCount, 0u);
    XCTAssertEqual(self.timerCancelCount, 1u);
}

- (void)testThatWeSetAnExpirationDateOnTheLoginRequest
{
    
    // given    
    ZMCredentials *credentials = [ZMEmailCredentials credentialsWithEmail:@"ddd@dd.d" password:@"fdsfsdf"];
    id mockRequest = [OCMockObject mockForClass:ZMTransportRequest.class];
    
    [[[(id)self.objectDirectory.selfTranscoder stub] andReturnValue:@NO] isSelfUserComplete];
    [[(id)self.objectDirectory.selfTranscoder stub] setNeedsSlowSync];
    [[(id)self.objectDirectory.registrationTranscoder stub] resetRegistrationState];

    [self.authenticationStatus prepareForLoginWithCredentials:credentials];
    [self.sut didEnterState];
    
    // expect
    [[[mockRequest stub] andReturnValue:@YES] responseWillContainCookie];
    [[[mockRequest expect] ignoringNonObjectArgs] expireAfterInterval:0];
    id <ZMRequestGenerator> generator = [self generatorReturningRequest:mockRequest];
    [[[(id)self.objectDirectory.loginTranscoder expect] andReturn:@[generator]] requestGenerators];
        
    // when
    ZMTransportRequest *request = [self.sut nextRequest];
    
    // then
    XCTAssertEqual(request, mockRequest);
    [mockRequest verify];
}



- (ZMUnauthenticatedState *)mockedSUTWithLaunchInForeground:(BOOL)launchInForeground isLoggedIn:(BOOL)isLoggedIn
{
    // given
    id mockAuthCenter = [OCMockObject niceMockForClass:[ZMAuthenticationStatus class]];
    id mockClientRegStatus = [OCMockObject niceMockForClass:[ZMClientRegistrationStatus class]];
    
    // stub
    ZMAuthenticationPhase authenticationPhase = isLoggedIn ? ZMAuthenticationPhaseAuthenticated : ZMAuthenticationPhaseUnauthenticated;
    ZMClientRegistrationPhase clientPhase = isLoggedIn ? ZMClientRegistrationPhaseRegistered : ZMClientRegistrationPhaseUnregistered;
    
    [(ZMAuthenticationStatus *)[[mockAuthCenter stub] andReturnValue:OCMOCK_VALUE(authenticationPhase)] currentPhase];
    [(ZMClientRegistrationStatus *)[[mockClientRegStatus stub] andReturnValue:OCMOCK_VALUE(clientPhase)] currentPhase];
    [[[(id)self.objectDirectory.selfTranscoder stub] andReturnValue:@YES] isSelfUserComplete];
    
    
    ZMUnauthenticatedState *sut = [[ZMUnauthenticatedState alloc] initWithAuthenticationCenter:mockAuthCenter
                                                                      clientRegistrationStatus:mockClientRegStatus
                                                                       objectStrategyDirectory:self.objectDirectory
                                                                          stateMachineDelegate:self.stateMachine
                                                                                   application:self.application];
    if (launchInForeground) {
        [self.application setActive];
        [self.application simulateApplicationWillEnterForeground];
    } else {
        [self.application setBackground];
    }
    return sut;
}

- (void)testThatItStartsQuickSyncIfApplicationLaunchStateIsForeground
{
    // given
    ZMUnauthenticatedState *sut = [self mockedSUTWithLaunchInForeground:YES isLoggedIn:YES];

    // expect
    [[(id)self.stateMachine expect] startQuickSync];
    
    // when
    [sut dataDidChange];
}

- (void)testThatItDoesNotStartQuickSyncIfApplicationLaunchStateIsInBackground
{
    // when
    ZMUnauthenticatedState *sut = [self mockedSUTWithLaunchInForeground:NO isLoggedIn:YES];
    
    // expect
    [[(id)self.stateMachine reject] startQuickSync];
    
    // when
    [sut dataDidChange];
}

- (void)testThatItReturnsNilRequest_AndStartsQuickSync_IfApplicationIsLoggedInAndLaunchStateIsForeground
{
    // when
    ZMUnauthenticatedState *sut = [self mockedSUTWithLaunchInForeground:YES isLoggedIn:YES];
    
    // expect
    [[(id)self.stateMachine expect] startQuickSync];
    
    // when
    ZMTransportRequest *request = [sut nextRequest];
    
    // then
    XCTAssertNil(request);
}

- (void)testThatItReturnsNilRequest_AndDoesNotStartQuickSync_IfApplicationIsLoggedInAndLaunchStateIsBackground
{
    // when
    ZMUnauthenticatedState *sut = [self mockedSUTWithLaunchInForeground:NO isLoggedIn:YES];
    
    // expect
    [[(id)self.stateMachine reject] startQuickSync];
    
    // when
    ZMTransportRequest *request = [sut nextRequest];
    
    // then
    XCTAssertNil(request);
}

- (void)testThatItStartsQuickSyncWhenEnteringForeground_LoggedIn
{
    // when
    ZMUnauthenticatedState *sut = [self mockedSUTWithLaunchInForeground:YES isLoggedIn:YES];
    
    // expect
    [[(id)self.stateMachine expect] startQuickSync];
    
    // when
    [sut didEnterForeground];
}

- (void)testThatItDoesNotStartQuickSyncWhenEnteringForeground_NotLoggedIn
{
    // when
    ZMUnauthenticatedState *sut = [self mockedSUTWithLaunchInForeground:YES isLoggedIn:NO];
    
    // expect
    [[(id)self.stateMachine reject] startQuickSync];
    
    // when
    [sut didEnterForeground];
}


- (void)testThatItStartsQuickSyncWhenApplicationStateChanges
{
    // when
    ZMUnauthenticatedState *sut = [self mockedSUTWithLaunchInForeground:NO isLoggedIn:YES];

    // when
    ZMTransportRequest *request1 = [sut nextRequest];
    
    // then
    XCTAssertNil(request1);
    
    // expect
    [[(id)self.stateMachine expect] startQuickSync];
    
    // and when
    [self.application setActive];
    ZMTransportRequest *request2 = [sut nextRequest];
    
    // then
    XCTAssertNil(request2);
}

@end

