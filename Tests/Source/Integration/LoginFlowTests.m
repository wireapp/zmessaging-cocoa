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

@import WireTransport;
@import WireMockTransport;
@import WireDataModel;

#import "NSError+ZMUserSessionInternal.h"
#import "ZMUserSession+Internal.h"
#import "ZMUserSession+OTR.h"
#import <WireSyncEngine/WireSyncEngine-Swift.h>
#import "WireSyncEngine_iOS_Tests-Swift.h"

#import "ZMCredentials.h"
#import <WireSyncEngine/ZMAuthenticationStatus.h>

extern NSTimeInterval DebugLoginFailureTimerOverride;

@interface LoginFlowTests : IntegrationTest <ZMAuthenticationObserver>

@property (nonatomic) NSMutableArray *authenticationFailures;

@end


@implementation LoginFlowTests

- (void)setUp
{
    [super setUp];
    
    self.authenticationFailures = [NSMutableArray array];
    [self createSelfUserAndConversation];
}

- (void)tearDown
{
    self.authenticationFailures = nil;
    DebugLoginFailureTimerOverride = 0;
    
    [super tearDown];
}

- (void)authenticationDidFail:(NSError *)error
{
    [self.authenticationFailures addObject:error];
}

- (void)testThatItNotifiesIfTheClientNeedsToBeRegistered
{
    // given
    NSString *email = @"expected@example.com";
    NSString *password = @"valid-password-837246";
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        NOT_USED(session);
        self.selfUser.name = @"Self User";
        self.selfUser.email = email;
        self.selfUser.password = password;
    }];
    
    // expect
    id authenticationObserver = [OCMockObject mockForProtocol:@protocol(ZMAuthenticationObserver)];
    id token = [ZMUserSessionAuthenticationNotification addObserver:authenticationObserver];
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"Login did succeed"];
    [[authenticationObserver expect] authenticationDidSucceed]; // authentication
    [[[authenticationObserver expect] andDo:^(NSInvocation *invocation ZM_UNUSED) {
        [expectation fulfill];
    }] clientRegistrationDidSucceed]; // client registration
    
    // when
    ZMCredentials *credentials = [ZMEmailCredentials credentialsWithEmail:email password:password];
    [self.unauthenticatedSession loginWithCredentials:credentials];
    
    // then
    XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0.5]);
    [authenticationObserver verify];
    XCTAssertNotNil([self.mockTransportSession.cookieStorage authenticationCookieData]);
    XCTAssertTrue(self.userSession.isLoggedIn);
    WaitForAllGroupsToBeEmpty(0.5);
    
    [ZMUserSessionAuthenticationNotification removeObserverForToken:token];
}

- (void)testThatWeCanLogInWithEmail
{
    // given
    NSString *email = @"expected@example.com";
    NSString *password = @"valid-password-837246";
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        NOT_USED(session);
        self.selfUser.name = @"Self User";
        self.selfUser.email = email;
        self.selfUser.password = password;
    }];
    
    id authenticationObserver = [OCMockObject mockForProtocol:@protocol(ZMAuthenticationObserver)];
    id token = [ZMUserSessionAuthenticationNotification addObserver:authenticationObserver];
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"Login did succeed"];
    [[authenticationObserver expect] authenticationDidSucceed]; // authentication
    [[[authenticationObserver expect] andDo:^(NSInvocation *invocation ZM_UNUSED) {
        [expectation fulfill];
    }] clientRegistrationDidSucceed]; // client registration
    
    // when
    ZMCredentials *credentials = [ZMEmailCredentials credentialsWithEmail:email password:password];
    [self.unauthenticatedSession loginWithCredentials:credentials];

    // then
    XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0.5]);
    [authenticationObserver verify];
    XCTAssertNotNil([self.mockTransportSession.cookieStorage authenticationCookieData]);
    XCTAssertTrue(self.userSession.isLoggedIn);
    WaitForAllGroupsToBeEmpty(0.5);
    
    [ZMUserSessionAuthenticationNotification removeObserverForToken:token];
}

- (void)testThatWeCanLoginWithAValidPreExistingCookie
{
    // given
    XCTAssertTrue([self login]);

    // when
    [self recreateSessionManager];
    
    // then
    WaitForAllGroupsToBeEmpty(0.5);
    XCTAssertNotNil([self.mockTransportSession.cookieStorage authenticationCookieData]);
    XCTAssertTrue(self.userSession.isLoggedIn);
}

- (void)testThatWeReceiveAuthenticationErrorWithWrongCredentials
{
    // given
    NSString *email = @"expected@example.com";
    NSString *password = @"valid-password-837246";
    __block MockUser *selfUser;
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        selfUser = [session insertUserWithName:@"Self User"];
        selfUser.email = email;
        selfUser.password = password;
    }];
    
    id authenticationObserver = [OCMockObject mockForProtocol:@protocol(ZMAuthenticationObserver)];
    id token = [ZMUserSessionAuthenticationNotification addObserver:authenticationObserver];

    XCTestExpectation *expectation = [self expectationWithDescription:@"Authentication did fail"];
    [[[authenticationObserver expect] andDo:^(NSInvocation *invocation ZM_UNUSED) {
        [expectation fulfill];
    }] authenticationDidFail:[NSError userSessionErrorWithErrorCode:ZMUserSessionInvalidCredentials userInfo:nil]];
    
    // when
    ZMCredentials *credentials = [ZMEmailCredentials credentialsWithEmail:email password:@"wrong-password"];
    [self.unauthenticatedSession loginWithCredentials:credentials];
    
    // then
    XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0.5]);
    [authenticationObserver verify];
    [ZMUserSessionAuthenticationNotification removeObserverForToken:token];
}

- (void)testThatWhenTransportSessionDeletesCookieInResponseToFailedLoginWeDoNotContinueSendingMoreRequests
{
    // given
    NSString *email = @"expected@example.com";
    NSString *password = @"valid-password-837246";
    __block MockUser *selfUser;
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        selfUser = [session insertUserWithName:@"Self User"];
        selfUser.email = email;
        selfUser.password = password;
    }];

    id authenticationObserver = [OCMockObject mockForProtocol:@protocol(ZMAuthenticationObserver)];
    [[authenticationObserver expect] authenticationDidSucceed]; // authentication
    [[authenticationObserver stub] authenticationDidFail:OCMOCK_ANY];

    id token = [ZMUserSessionAuthenticationNotification addObserver:authenticationObserver];
    
    // getting access token fails
    __block NSInteger numberOfRequests = 0;
    ZM_WEAK(self);
    self.mockTransportSession.responseGeneratorBlock = ^ZMTransportResponse *(ZMTransportRequest *request) {
        ZM_STRONG(self);
        NOT_USED(request);
        ++numberOfRequests;
        if (numberOfRequests == 1) {
            return nil; // allow authentication ...
        }
        //  ... but no request after it
        NSError *error = [NSError errorWithDomain:ZMTransportSessionErrorDomain code:ZMTransportSessionErrorCodeAuthenticationFailed userInfo:nil];
        [self.mockTransportSession.cookieStorage setAuthenticationCookieData:nil];
        [ZMPersistentCookieStorage deleteAllKeychainItems];
        return [ZMTransportResponse responseWithPayload:nil HTTPStatus:0 transportSessionError:error];
    };
    
    // when
    ZMCredentials *credentials = [ZMEmailCredentials credentialsWithEmail:email password:password];
    [self.unauthenticatedSession loginWithCredentials:credentials];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // should not make more requests
    XCTAssertLessThanOrEqual(numberOfRequests, 2);
    XCTAssertFalse(self.userSession.isLoggedIn);
    [authenticationObserver verify];
    
    [ZMUserSessionAuthenticationNotification removeObserverForToken:token];
}

- (void)testThatWhenTransportSessionDeletesCookieInResponseToFailedRenewTokenWeGoToUnathorizedState
{
    // given
    NSString *email = @"expected@example.com";
    NSString *password = @"valid-password-837246";
    __block MockUser *selfUser;
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        selfUser = [session insertUserWithName:@"Self User"];
        selfUser.email = email;
        selfUser.password = password;
    }];
    
    id authenticationObserver = [OCMockObject mockForProtocol:@protocol(ZMAuthenticationObserver)];
    [[authenticationObserver stub] authenticationDidSucceed];
    [[authenticationObserver stub] authenticationDidFail:OCMOCK_ANY];
    id token = [ZMUserSessionAuthenticationNotification addObserver:authenticationObserver];
    
    // getting access token fails
    __block NSInteger numberOfRequests = 0;
    ZM_WEAK(self);
    self.mockTransportSession.responseGeneratorBlock = ^ZMTransportResponse *(ZMTransportRequest *request) {
        ZM_STRONG(self);
        NOT_USED(request);
        ++numberOfRequests;
        if (numberOfRequests == 1) {
            return nil; // allow login ...
        }
        //  ... but no request after it
        NSError *error = [NSError errorWithDomain:ZMTransportSessionErrorDomain code:ZMTransportSessionErrorCodeAuthenticationFailed userInfo:nil];
        [self.mockTransportSession.cookieStorage setAuthenticationCookieData:nil];
        return [ZMTransportResponse responseWithPayload:nil HTTPStatus:0 transportSessionError:error];
    };
    
    // when
    ZMCredentials *credentials = [ZMEmailCredentials credentialsWithEmail:email password:password];
    [self.unauthenticatedSession loginWithCredentials:credentials];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // should not make more requests
    XCTAssertLessThanOrEqual(numberOfRequests, 2);
    XCTAssertFalse(self.userSession.isLoggedIn);
    [authenticationObserver verify];
    
    [ZMUserSessionAuthenticationNotification removeObserverForToken:token];
}


- (void)testThatTheLoginTimesOutOnNetworkErrors
{
    // given
    NSError *error = [NSError errorWithDomain:ZMTransportSessionErrorDomain code:ZMTransportSessionErrorCodeTryAgainLater userInfo:nil];
    ZM_WEAK(self);
    self.mockTransportSession.responseGeneratorBlock = ^ZMTransportResponse*(ZMTransportRequest *request) {
        ZM_STRONG(self);
        NOT_USED(request);
        self.mockTransportSession.disableEnqueueRequests = YES;
        return [ZMTransportResponse responseWithPayload:nil HTTPStatus:0 transportSessionError:error];
    };
    id token = [ZMUserSessionAuthenticationNotification addObserver:self];
    DebugLoginFailureTimerOverride = 0.2;
    
    // when
    ZMCredentials *cred = [ZMEmailCredentials credentialsWithEmail:@"janet@fo.example.com" password:@"::FsdF:#$:fgsdAG"];
    [self.unauthenticatedSession loginWithCredentials:cred];
    
    // then
    XCTAssertTrue([self waitOnMainLoopUntilBlock:^BOOL{
        return self.authenticationFailures.count > 0u;
    } timeout:0.5]);
    WaitForAllGroupsToBeEmpty(0.5);
    XCTAssertGreaterThanOrEqual(self.authenticationFailures.count, 1u);
    NSError *failure1 = self.authenticationFailures.firstObject;
    XCTAssertEqual(failure1.code, (long)ZMUserSessionNetworkError);
    XCTAssertLessThan(self.mockTransportSession.receivedRequests.count, 2u);
    
    // after
    DebugLoginFailureTimerOverride = 0;
    [ZMUserSessionAuthenticationNotification removeObserverForToken:token];
}

- (void)testThatWhenWeLoginItChecksForTheHistory
{
    // given
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        [session insertGroupConversationWithSelfUser:self.selfUser otherUsers:@[]];
        [session insertGroupConversationWithSelfUser:self.selfUser otherUsers:@[]];
    }];
    
    XCTAssertTrue([self login]);
    XCTAssertFalse(self.userSession.hadHistoryAtLastLogin);
    
    // when
    [self destroySessionManager];
    [self deleteAuthenticationCookie];
    [self createSessionManager];
    
    WaitForAllGroupsToBeEmpty(0.5);
    XCTAssertTrue([self login]);

    // then
    XCTAssertTrue(self.userSession.hadHistoryAtLastLogin);
    WaitForAllGroupsToBeEmpty(0.5);
}

@end


@implementation LoginFlowTests (PushToken)

- (void)testThatItRegisteresThePushTokenWithTheBackend;
{
    NSData *deviceToken = [@"asdfasdf" dataUsingEncoding:NSUTF8StringEncoding];
    NSString *deviceTokenAsHex = @"6173646661736466";
    XCTAssertTrue([self login]);
    
    [self.userSession setPushToken:deviceToken];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    NSArray *registeredTokens = self.mockTransportSession.pushTokens;
    XCTAssertEqual(registeredTokens.count, 1u);
    NSDictionary *registeredToken = registeredTokens.firstObject;
    XCTAssertEqualObjects(registeredToken[@"token"], deviceTokenAsHex);
    XCTAssertNotNil(registeredToken[@"app"]);
    XCTAssertTrue([registeredToken[@"app"] hasPrefix:@"com.wire."]);
}

@end


@implementation LoginFlowTests (PhoneLogin)

- (void)testThatWeCanLogInWithPhoneNumber
{
    // given
    NSString *phone = @"+4912345678900";
    NSString *code = self.mockTransportSession.phoneVerificationCodeForLogin;
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        NOT_USED(session);
        self.selfUser.phone = phone;
    }];
    id authenticationObserver = [OCMockObject mockForProtocol:@protocol(ZMAuthenticationObserver)];
    id token = [ZMUserSessionAuthenticationNotification addObserver:authenticationObserver];
    
    XCTestExpectation *loginCodeRequestExpectation = [self expectationWithDescription:@"login code request completed"];
    
    // expect
    [[[authenticationObserver expect] andDo:^(NSInvocation *inv) {
        NOT_USED(inv);
        [loginCodeRequestExpectation fulfill];
    }] loginCodeRequestDidSucceed];
    [[authenticationObserver expect] authenticationDidSucceed]; // authentication
    [[authenticationObserver expect] clientRegistrationDidSucceed]; // client registration

    // when
    [self.unauthenticatedSession requestPhoneVerificationCodeForLogin:phone];
    XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0.5]);
    
    // then
    XCTAssertEqual(self.mockTransportSession.receivedRequests.count, 1u);
    
    // and when
    [self.unauthenticatedSession loginWithCredentials:[ZMPhoneCredentials credentialsWithPhoneNumber:phone verificationCode:code]];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    [authenticationObserver verify];
    ZMUser *selfUser = [ZMUser selfUserInUserSession:self.userSession];
    XCTAssertEqualObjects(selfUser.name, self.selfUser.name);
    XCTAssertEqualObjects(selfUser.phoneNumber, phone);
    
    [ZMUserSessionAuthenticationNotification removeObserverForToken:token];
}

- (void)testThatItNotifiesIfTheLoginCodeCanNotBeRequested
{
    // given
    NSString *phone = @"+4912345678900";
    
    self.mockTransportSession.responseGeneratorBlock = ^ZMTransportResponse*(ZMTransportRequest *request) {
        if([request.path isEqualToString:@"/login/send"]) {
            return [ZMTransportResponse responseWithPayload:nil HTTPStatus:400 transportSessionError:nil];
        }
        return nil;
    };
    
    id authenticationObserver = [OCMockObject mockForProtocol:@protocol(ZMAuthenticationObserver)];
    id token = [ZMUserSessionAuthenticationNotification addObserver:authenticationObserver];
    
    // expect
    [[authenticationObserver expect] loginCodeRequestDidFail:OCMOCK_ANY];
    
    // when
    [self.unauthenticatedSession requestPhoneVerificationCodeForLogin:phone];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(self.mockTransportSession.receivedRequests.count, 1u);
    [authenticationObserver verify];
    
    [ZMUserSessionAuthenticationNotification removeObserverForToken:token];
}

- (void)testThatItNotifiesIfTheLoginFails
{
    // given
    NSString *phone = @"+4912345678900";
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        NOT_USED(session);
        self.selfUser.phone = phone;
    }];
    id authenticationObserver = [OCMockObject mockForProtocol:@protocol(ZMAuthenticationObserver)];
    id token = [ZMUserSessionAuthenticationNotification addObserver:authenticationObserver];
    
    // expect
    [[authenticationObserver expect] loginCodeRequestDidSucceed];
    [[authenticationObserver expect] authenticationDidFail:[NSError userSessionErrorWithErrorCode:ZMUserSessionInvalidCredentials userInfo:nil]];
    
    // when
    [self.unauthenticatedSession requestPhoneVerificationCodeForLogin:phone];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(self.mockTransportSession.receivedRequests.count, 1u);
    
    // and when
    [self.unauthenticatedSession loginWithCredentials:[ZMPhoneCredentials credentialsWithPhoneNumber:phone verificationCode:self.mockTransportSession.invalidPhoneVerificationCode]];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    [authenticationObserver verify];
    [ZMUserSessionAuthenticationNotification removeObserverForToken:token];
}

@end


@implementation LoginFlowTests (ClientRegistration_Errors)

- (void)testThatItFetchesSelfUserBeforeRegisteringSelfClient
{
    // expect
    __block BOOL didCreateSelfClient = NO;
    __block BOOL didFetchSelfUser = NO;
    ZM_WEAK(self);
    self.mockTransportSession.responseGeneratorBlock = ^ZMTransportResponse*(ZMTransportRequest *request) {
        ZM_STRONG(self);
        
        if([request.path isEqualToString:@"/clients"] && request.method == ZMMethodPOST) {
            XCTAssertTrue(didFetchSelfUser);
            didCreateSelfClient = YES;
        }
        if (!didFetchSelfUser && [request.path isEqualToString:@"/self"] && request.method == ZMMethodGET) {
            XCTAssertFalse(didCreateSelfClient);
            didFetchSelfUser = YES;
        }
        return nil;
    };
    
    // and when
    XCTAssertTrue([self login]);
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertTrue(didCreateSelfClient);
    XCTAssertTrue(didFetchSelfUser);
}

- (void)testThatWeCanLoginAfterRegisteringAnEmailAddressAndClient
{
    // given
    NSString *phone = @"+4912345678900";
    NSString *email = @"email@example.com";
    NSString *password = @"newPassword";
    
    self.selfUser.phone = phone;
    
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        [session whiteListPhone:phone];
        self.selfUser.email = nil;
        self.selfUser.password = nil;
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    id authenticationObserver = [OCMockObject mockForProtocol:@protocol(ZMAuthenticationObserver)];
    id token = [ZMUserSessionAuthenticationNotification addObserver:authenticationObserver];
    
    // expect
    id provideCredentials = ^(NSInvocation *invocation ZM_UNUSED) {
        ZMEmailCredentials *credentials = [ZMEmailCredentials credentialsWithEmail:email password:password];
        [self.userSession performChanges:^{
            [self.userSession.userProfileUpdateStatus requestSettingEmailAndPasswordWithCredentials:credentials error:nil];
        }];
    };
    
    id verifyEmailAddress = ^(NSInvocation *invocation ZM_UNUSED) {
        [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
            // simulate user click on email
            NOT_USED(session);
            self.selfUser.email = email;
        }];
    };
    
    [[[[authenticationObserver expect] andDo:provideCredentials] andDo:verifyEmailAddress] authenticationDidFail:[NSError userSessionErrorWithErrorCode:ZMUserSessionNeedsToRegisterEmailToRegisterClient userInfo:nil]];
    
    [[authenticationObserver expect] authenticationDidSucceed]; // authentication
    [[authenticationObserver expect] clientRegistrationDidSucceed]; // client registration
    
    __block BOOL didRun = NO;
    self.mockTransportSession.responseGeneratorBlock = ^ZMTransportResponse*(ZMTransportRequest *request) {
        // when trying to register without email credentials, the BE tells us we need credentials
        if(!didRun && [request.path isEqualToString:@"/clients"] && request.method == ZMMethodPOST) {
            didRun = YES;
        }
        // the user updates the email address (currently does not work in MockTransportsession for some reason)
        if ([request.path isEqualToString:@"/self/email"]) {
            return [ZMTransportResponse responseWithPayload:nil HTTPStatus:200 transportSessionError:nil];
        }
        return nil;
    };
    
    // and when
    ZMPhoneCredentials *credentials = [ZMPhoneCredentials credentialsWithPhoneNumber:phone verificationCode:self.mockTransportSession.phoneVerificationCodeForLogin];
    XCTAssertTrue([self loginWithCredentials:credentials ignoreAuthenticationFailures:YES]);
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    [authenticationObserver verify];
    ZMUser *selfUser = [ZMUser selfUserInUserSession:self.userSession];
    
    XCTAssertEqualObjects(selfUser.name, self.selfUser.name);
    XCTAssertEqualObjects(selfUser.phoneNumber, phone);
    XCTAssertEqualObjects(selfUser.emailAddress, email);
    
    [ZMUserSessionAuthenticationNotification removeObserverForToken:token];
}

- (void)testThatWeRecoverFromEnteringAWrongEmailAddressWhenRegisteringAClientAfterLoggingInWithPhone
{
    // given
    NSString *phone = @"+4912345678900";
    NSString *wrongPassword = @"wrongPassword";

    self.selfUser.phone = phone;
    
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        [session whiteListPhone:phone];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    id authenticationObserver = [OCMockObject mockForProtocol:@protocol(ZMAuthenticationObserver)];
    id token = [ZMUserSessionAuthenticationNotification addObserver:authenticationObserver];
    __block NSUInteger runCount = 0;
    
    // expect
    // first provide the wrong credentials
    id provideWrongCredentials = ^(NSInvocation *invocation ZM_UNUSED) {
        [self.mockTransportSession resetReceivedRequests];
        ZMEmailCredentials *credentials = [ZMEmailCredentials credentialsWithEmail:IntegrationTest.SelfUserEmail password:wrongPassword];
        [self.unauthenticatedSession loginWithCredentials:credentials];
    };
    
    NSDictionary *credentialsUserInfo = @{ ZMPhoneCredentialKey: phone, ZMEmailCredentialKey: IntegrationTest.SelfUserEmail };
    [[authenticationObserver expect] authenticationDidSucceed]; // authentication
    [[[authenticationObserver expect] andDo:provideWrongCredentials] authenticationDidFail:[NSError userSessionErrorWithErrorCode:ZMUserSessionNeedsPasswordToRegisterClient userInfo:credentialsUserInfo]];
    [[authenticationObserver expect] authenticationDidFail:[NSError errorWithDomain:@"ZMUserSession" code:ZMUserSessionInvalidCredentials userInfo:nil]];
    
    ZM_WEAK(self);
    self.mockTransportSession.responseGeneratorBlock = ^ZMTransportResponse*(ZMTransportRequest *request) {
        ZM_STRONG(self);
        
        // when trying to register without email credentials, the BE tells us we need credentials
        if(runCount <= 2 && [request.path isEqualToString:@"/clients"] && request.method == ZMMethodPOST) {
            NSDictionary *payload;
            if (runCount == 0) {
                payload = @{@"label" : @"missing-auth"};
            } else {
                payload = @{@"label" : @"invalid-credentials"};
            }
            runCount++;
            return [ZMTransportResponse responseWithPayload:payload HTTPStatus:400 transportSessionError:nil];
        }
        return nil;
    };

    // and when
    [self.unauthenticatedSession loginWithCredentials:[ZMPhoneCredentials credentialsWithPhoneNumber:phone verificationCode:self.mockTransportSession.phoneVerificationCodeForLogin]];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(runCount, 2lu);
    [authenticationObserver verify];
    [ZMUserSessionAuthenticationNotification removeObserverForToken:token];
}

- (void)testThatItCanRegisterNewClientAfterDeletingSelfClient
{
    // given
    id authenticationObserver = [OCMockObject mockForProtocol:@protocol(ZMAuthenticationObserver)];
    id token = [ZMUserSessionAuthenticationNotification addObserver:authenticationObserver];
    [[authenticationObserver expect] authenticationDidSucceed];
    [[authenticationObserver expect] clientRegistrationDidSucceed]; // client creation
    XCTAssertTrue([self login]);
    
    // expect
    [[authenticationObserver expect] authenticationDidFail:[NSError userSessionErrorWithErrorCode:ZMUserSessionClientDeletedRemotely userInfo:@{ ZMEmailCredentialKey: IntegrationTest.SelfUserEmail }]];
    
    // when we delete self client
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        MockUserClient *selfClient = self.selfUser.clients.anyObject;
        [session deleteUserClientWithIdentifier:selfClient.identifier forUser:self.selfUser];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // expect
    [[authenticationObserver expect] authenticationDidSucceed];
    [[authenticationObserver expect] clientRegistrationDidSucceed]; // client creation
    
    // when login 2nd time
    XCTAssertTrue([self login]); ;
    
    [ZMUserSessionAuthenticationNotification removeObserverForToken:token];
}

- (void)testThatItCanRegisterNewClientAfterDeletingSelfClientAndReceivingNeedsPasswordToRegisterClient
{
    // given
    NSString *phone = @"+4912345678900";
    NSString *code = self.mockTransportSession.phoneVerificationCodeForLogin;
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        NOT_USED(session);
        self.selfUser.phone = phone;
    }];

    id authenticationObserver = [OCMockObject mockForProtocol:@protocol(ZMAuthenticationObserver)];
    id token = [ZMUserSessionAuthenticationNotification addObserver:authenticationObserver];
    [[authenticationObserver expect] authenticationDidSucceed]; // authentication
    [[authenticationObserver expect] clientRegistrationDidSucceed]; // client registration
    
    // (1) register client and recreate session
    {
        XCTAssertTrue([self login]);
        
        // "delete" the self client
        [self.userSession.managedObjectContext setPersistentStoreMetadata:nil forKey:ZMPersistedClientIdKey];
        [self.userSession.managedObjectContext saveOrRollback];

        [self destroySessionManager];
        [self deleteAuthenticationCookie];
        [self createSessionManager];
        WaitForAllGroupsToBeEmpty(0.5);
    }
    
    // (2) login again after losing our client (BE will ask for password on 2nd client)
    {
        // expect
        id provideCredentials = ^(NSInvocation *invocation ZM_UNUSED) {
            ZMEmailCredentials *credentials = [ZMEmailCredentials credentialsWithEmail:IntegrationTest.SelfUserEmail password:IntegrationTest.SelfUserPassword];
            [self.userSession performChanges:^{
                [self.unauthenticatedSession loginWithCredentials:credentials];
            }];
        };

        NSDictionary *credentialsUserInfo = @{ ZMPhoneCredentialKey : phone, ZMEmailCredentialKey : IntegrationTest.SelfUserEmail };
        [[authenticationObserver expect] loginCodeRequestDidSucceed]; // authentication
        [[authenticationObserver expect] authenticationDidSucceed]; // authentication
        [[[authenticationObserver expect] andDo:provideCredentials] authenticationDidFail:[NSError userSessionErrorWithErrorCode:ZMUserSessionNeedsPasswordToRegisterClient userInfo:credentialsUserInfo]];
        [[authenticationObserver expect] clientRegistrationDidSucceed]; // client registration
        
        // when
        [self.unauthenticatedSession requestPhoneVerificationCodeForLogin:phone];
        XCTAssertTrue([self loginWithCredentials:[ZMPhoneCredentials credentialsWithPhoneNumber:phone verificationCode:code] ignoreAuthenticationFailures:YES]);
        WaitForAllGroupsToBeEmpty(0.5);
        
        // then
        [authenticationObserver verify];
        ZMUser *selfUser = [ZMUser selfUserInUserSession:self.userSession];
        XCTAssertEqualObjects(selfUser.name, self.selfUser.name);
    }
    
    [ZMUserSessionAuthenticationNotification removeObserverForToken:token];
}

- (void)testThatItCanRegisterANewClientAfterDeletingClients
{
    // given
    __block NSString *idToDelete;
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        MockUserClient *client = [session registerClientForUser:self.selfUser label:@"idToDelete" type:@"permanent"];
        idToDelete = client.identifier;
    }];
    WaitForAllGroupsToBeEmpty(0.5);

    id authenticationObserver = [OCMockObject mockForProtocol:@protocol(ZMAuthenticationObserver)];
    id token = [ZMUserSessionAuthenticationNotification addObserver:authenticationObserver];
    
    // expect
    id deleteClients = ^(NSInvocation *invocation ZM_UNUSED) {
        // simulate the user selecting a client to delete
        [self.userSession performChanges:^{
            ZMUser *selfUser = [self userForMockUser:self.selfUser];
            [selfUser.managedObjectContext saveOrRollback];
            UserClient *clientToDelete = [selfUser.clients.allObjects firstObjectMatchingWithBlock:^BOOL(UserClient *client) {
                return [client.remoteIdentifier isEqualToString:idToDelete];
            }];
            XCTAssertNotNil(clientToDelete);
            [self.userSession deleteClient:clientToDelete];
        }];
    };
    
    [[authenticationObserver expect] authenticationDidSucceed]; // authentication
    [[[authenticationObserver expect] andDo:deleteClients] authenticationDidFail:[OCMArg checkWithBlock:^BOOL(NSError *error) {
        return error.code == ZMUserSessionCanNotRegisterMoreClients;
    }]];
    [[authenticationObserver expect] clientRegistrationDidSucceed]; // client registration

    __block BOOL didTryToRegister = NO;
    __block BOOL didDeleteClient = NO;

    self.mockTransportSession.responseGeneratorBlock = ^ZMTransportResponse*(ZMTransportRequest *request) {
        NSString *clientsPath = @"/clients";
        // BE tells us to select one of the clients to delete
        if(!didTryToRegister && [request.path isEqualToString:clientsPath] && request.method == ZMMethodPOST) {
            didTryToRegister = YES;
            NSDictionary *tooManyClients = @{@"label" : @"too-many-clients"};
            return [ZMTransportResponse responseWithPayload:tooManyClients HTTPStatus:400 transportSessionError:nil];
        }
        // we successfully delete the selected client (currently not working with MocktransportSession)
        if(!didDeleteClient && [request.path isEqualToString:[NSString stringWithFormat:@"%@/%@",clientsPath, idToDelete]] && request.method == ZMMethodDELETE) {
            didDeleteClient = YES;
            return [ZMTransportResponse responseWithPayload:nil HTTPStatus:200 transportSessionError:nil];
        }
        return nil;
    };
    
    // and when
    XCTAssertTrue([self loginAndIgnoreAuthenticationFailures:YES]);
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssert(didTryToRegister);
    [authenticationObserver verify];
    ZMUser *selfUser = [ZMUser selfUserInUserSession:self.userSession];
    XCTAssertEqualObjects(selfUser.name, self.selfUser.name);
    
    [ZMUserSessionAuthenticationNotification removeObserverForToken:token];
}

@end
