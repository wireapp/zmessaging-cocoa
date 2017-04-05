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
#import "IntegrationTestBase.h"

#import "ZMUserSession+Internal.h"
#import "ZMUserSession+Authentication.h"
#import "ZMUserSession+Registration.h"
#import "ZMUserSession+OTR.h"

#import "ZMCredentials.h"
#import <WireSyncEngine/ZMAuthenticationStatus.h>

extern NSTimeInterval DebugLoginFailureTimerOverride;

@interface LoginFlowTests : IntegrationTestBase <ZMAuthenticationObserver>

@property (atomic) NSUInteger authenticationSuccessCount;
@property (nonatomic) NSMutableArray *authenticationFailures;
@property (nonatomic) NSMutableArray *loginCodeRequestFailures;

@end



@implementation LoginFlowTests

- (void)setUp
{
    self.authenticationFailures = [NSMutableArray array];
    self.loginCodeRequestFailures = [NSMutableArray array];
    self.authenticationSuccessCount = 0;
    [super setUp];
}

- (void)tearDown
{
    self.authenticationFailures = nil;
    self.loginCodeRequestFailures = [NSMutableArray array];
    self.authenticationSuccessCount = 0;
    DebugLoginFailureTimerOverride = 0;
    [super tearDown];
}

- (void)loginCodeRequestDidFail:(NSError *)error
{
    [self.loginCodeRequestFailures addObject:error];
}

- (void)authenticationDidFail:(NSError *)error
{
    [self.authenticationFailures addObject:error];
}

- (void)authenticationDidSucceed
{
    ++self.authenticationSuccessCount;
}


- (void)testThatItNotifiesIfTheClientNeedsToBeRegistered
{
    // given
    [self.syncMOC setPersistentStoreMetadata:nil forKey:@"PersistedClientId"];
    
    NSString *email = @"expected@example.com";
    NSString *password = @"valid-password-837246";
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        NOT_USED(session);
        self.selfUser.name = @"Self User";
        self.selfUser.email = email;
        self.selfUser.password = password;
    }];
    
    
    id provideCredentials = ^(NSInvocation *invocation ZM_UNUSED) {
        ZMCredentials *cred = [ZMEmailCredentials credentialsWithEmail:email password:password];
        [self.userSession loginWithCredentials:cred];
    };
    
    
    id authenticationObserver = [OCMockObject mockForProtocol:@protocol(ZMAuthenticationObserver)];
    [[[authenticationObserver expect] andDo:provideCredentials] authenticationDidFail:[NSError userSessionErrorWithErrorCode:ZMUserSessionNeedsCredentials userInfo:nil]];
    id token = [self.userSession addAuthenticationObserver:authenticationObserver];
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"Authentication did succeed"];
    [[[authenticationObserver expect] andDo:^(NSInvocation *invocation ZM_UNUSED) {
        [expectation fulfill];
    }] authenticationDidSucceed];
    
    // when
    [self.userSession start];
    
    // then
    XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0.5]);
    [authenticationObserver verify];
    XCTAssertNotNil([self.mockTransportSession.cookieStorage authenticationCookieData]);
    XCTAssertTrue(self.userSession.isLoggedIn);
    WaitForEverythingToBeDone();
    
    [self.userSession removeAuthenticationObserverForToken:token];
}

- (void)testThatWeCanLogInWithEmail
{
    // given
    [self.syncMOC setPersistentStoreMetadata:@"someID" forKey:@"PersistedClientId"];

    NSString *email = @"expected@example.com";
    NSString *password = @"valid-password-837246";
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        NOT_USED(session);
        self.selfUser.name = @"Self User";
        self.selfUser.email = email;
        self.selfUser.password = password;
    }];
    

    id provideCredentials = ^(NSInvocation *invocation ZM_UNUSED) {
        ZMCredentials *cred = [ZMEmailCredentials credentialsWithEmail:email password:password];
        [self.userSession loginWithCredentials:cred];
    };
    
    
    id authenticationObserver = [OCMockObject mockForProtocol:@protocol(ZMAuthenticationObserver)];
    [[[authenticationObserver expect] andDo:provideCredentials] authenticationDidFail:[NSError userSessionErrorWithErrorCode:ZMUserSessionNeedsCredentials userInfo:nil]];
    id token = [self.userSession addAuthenticationObserver:authenticationObserver];
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"Authentication did succeed"];
    [[[authenticationObserver expect] andDo:^(NSInvocation *invocation ZM_UNUSED) {
        [expectation fulfill];
    }] authenticationDidSucceed];
    
    // when
    [self.userSession start];

    // then
    XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0.5]);
    [authenticationObserver verify];
    XCTAssertNotNil([self.mockTransportSession.cookieStorage authenticationCookieData]);
    XCTAssertTrue(self.userSession.isLoggedIn);
    WaitForEverythingToBeDone();
    
    [self.userSession removeAuthenticationObserverForToken:token];
}

- (void)testThatWeCanLoginWithAValidPreExistingCookie
{
    // given
    [self.syncMOC setPersistentStoreMetadata:@"someID" forKey:@"PersistedClientId"];
    
    [self.userSession.authenticationStatus setAuthenticationCookieData:[@"cookieData" dataUsingEncoding:NSUTF8StringEncoding]];
    
    id authenticationObserver = [OCMockObject mockForProtocol:@protocol(ZMAuthenticationObserver)];
    id token = [self.userSession addAuthenticationObserver:authenticationObserver];

    // expect
    XCTestExpectation *expectation = [self expectationWithDescription:@"Authentication did succeed"];
    [[[authenticationObserver expect] andDo:^(NSInvocation *invocation ZM_UNUSED) {
        [expectation fulfill];
    }] authenticationDidSucceed];
    
    // when
    [self.userSession start];
    
    // then
    XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0.5]);
    [authenticationObserver verify];
    XCTAssertNotNil([self.mockTransportSession.cookieStorage authenticationCookieData]);
    XCTAssertTrue(self.userSession.isLoggedIn);
    
    [self.userSession removeAuthenticationObserverForToken:token];
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
    
    
    id provideCredentials = ^(NSInvocation *invocation ZM_UNUSED) {
        ZMCredentials *cred = [ZMEmailCredentials credentialsWithEmail:email password:@"wrong-password"];
        [self.userSession loginWithCredentials:cred];
    };


    id authenticationObserver = [OCMockObject mockForProtocol:@protocol(ZMAuthenticationObserver)];
    [[[authenticationObserver expect] andDo:provideCredentials] authenticationDidFail:[NSError userSessionErrorWithErrorCode:ZMUserSessionNeedsCredentials userInfo:nil]];
    id token = [self.userSession addAuthenticationObserver:authenticationObserver];

    XCTestExpectation *expectation = [self expectationWithDescription:@"Authentication did fail"];
    [[[authenticationObserver expect] andDo:^(NSInvocation *invocation ZM_UNUSED) {
        [expectation fulfill];
    }] authenticationDidFail:[NSError userSessionErrorWithErrorCode:ZMUserSessionInvalidCredentials userInfo:nil]];
    
    
    // when
    [self.userSession start];
    
    
    // then
    XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0.5]);
    [authenticationObserver verify];
    [self.userSession removeAuthenticationObserverForToken:token];
}

- (void)testThatWhenTransportSessionDeletesCookieInResponseToFailedLoginWeDoNotContinueSendingMoreRequests
{
    NSString *email = @"expected@example.com";
    NSString *password = @"valid-password-837246";
    __block MockUser *selfUser;
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        selfUser = [session insertUserWithName:@"Self User"];
        selfUser.email = email;
        selfUser.password = password;
    }];

    
    id provideCredentials = ^(NSInvocation *invocation ZM_UNUSED) {
        ZMCredentials *cred = [ZMEmailCredentials credentialsWithEmail:email password:password];
        [self.userSession loginWithCredentials:cred];
    };

    id authenticationObserver = [OCMockObject mockForProtocol:@protocol(ZMAuthenticationObserver)];
    [[[authenticationObserver expect] andDo:provideCredentials] authenticationDidFail:[NSError userSessionErrorWithErrorCode:ZMUserSessionNeedsCredentials userInfo:nil]];
    [[authenticationObserver stub] authenticationDidFail:OCMOCK_ANY];
    
    
    id token = [self.userSession addAuthenticationObserver:authenticationObserver];
    
    
    // getting access token fails
    __block NSInteger numberOfRequests = 0;
    self.mockTransportSession.responseGeneratorBlock = ^ZMTransportResponse *(ZMTransportRequest *request) {
        NOT_USED(request);
        ++numberOfRequests;
        if (numberOfRequests == 1) {
            return nil; // allow login ...
        }
        //  ... but no request after it
        NSError *error = [NSError errorWithDomain:ZMTransportSessionErrorDomain code:ZMTransportSessionErrorCodeAuthenticationFailed userInfo:nil];
        [self.userSession.authenticationStatus setAuthenticationCookieData:nil];
        return [ZMTransportResponse responseWithPayload:nil HTTPStatus:0 transportSessionError:error];
    };
    
    // when
    [self.userSession start];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // should not make more requests
    XCTAssertLessThanOrEqual(numberOfRequests, 2);
    XCTAssertFalse(self.userSession.isLoggedIn);
    [authenticationObserver verify];
    
    [self.userSession removeAuthenticationObserverForToken:token];
}

- (void)testThatWhenTransportSessionDeletesCookieInResponseToFailedRenewTokenWeGoToUnathorizedState
{
    NSString *email = @"expected@example.com";
    NSString *password = @"valid-password-837246";
    __block MockUser *selfUser;
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        selfUser = [session insertUserWithName:@"Self User"];
        selfUser.email = email;
        selfUser.password = password;
    }];
    
    
    id provideCredentials = ^(NSInvocation *invocation ZM_UNUSED) {
        ZMCredentials *cred = [ZMEmailCredentials credentialsWithEmail:email password:password];
        [self.userSession loginWithCredentials:cred];
    };
    
    id authenticationObserver = [OCMockObject mockForProtocol:@protocol(ZMAuthenticationObserver)];
    [[[authenticationObserver expect] andDo:provideCredentials] authenticationDidFail:[NSError userSessionErrorWithErrorCode:ZMUserSessionNeedsCredentials userInfo:nil]];
    [[authenticationObserver stub] authenticationDidSucceed];
    
    
    id token = [self.userSession addAuthenticationObserver:authenticationObserver];
    
    
    // getting access token fails
    __block NSInteger numberOfRequests = 0;
    self.mockTransportSession.responseGeneratorBlock = ^ZMTransportResponse *(ZMTransportRequest *request) {
        NOT_USED(request);
        ++numberOfRequests;
        if (numberOfRequests == 1) {
            return nil; // allow login ...
        }
        //  ... but no request after it
        NSError *error = [NSError errorWithDomain:ZMTransportSessionErrorDomain code:ZMTransportSessionErrorCodeAuthenticationFailed userInfo:nil];
        [self.userSession.authenticationStatus setAuthenticationCookieData:nil];
        return [ZMTransportResponse responseWithPayload:nil HTTPStatus:0 transportSessionError:error];
    };
    
    // when
    [self.userSession start];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // should not make more requests
    XCTAssertLessThanOrEqual(numberOfRequests, 2);
    XCTAssertFalse(self.userSession.isLoggedIn);
    [authenticationObserver verify];
    
    [self.userSession removeAuthenticationObserverForToken:token];
}


- (void)testThatTheLoginTimesOutOnNetworkErrors
{
    // given

    NSError *error = [NSError errorWithDomain:ZMTransportSessionErrorDomain code:ZMTransportSessionErrorCodeTryAgainLater userInfo:nil];
    self.mockTransportSession.responseGeneratorBlock = ^ZMTransportResponse*(ZMTransportRequest *request) {
        NOT_USED(request);
        self.mockTransportSession.disableEnqueueRequests = YES;
        return [ZMTransportResponse responseWithPayload:nil HTTPStatus:0 transportSessionError:error];
    };
    id token = [self.userSession addAuthenticationObserver:self];
    DebugLoginFailureTimerOverride = 0.2;
    
    // when
    ZMCredentials *cred = [ZMEmailCredentials credentialsWithEmail:@"janet@fo.example.com" password:@"::FsdF:#$:fgsdAG"];
    [self.userSession loginWithCredentials:cred];
    
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
    [self.userSession removeAuthenticationObserverForToken:token];
}

- (void)testThatWhenWeLoginItChecksForTheHistory
{
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    WaitForAllGroupsToBeEmpty(0.5);
    
    XCTAssertFalse(self.userSession.hadHistoryAtLastLogin);
    
    // when
    [self recreateUserSessionAndWipeCache:NO];
    WaitForAllGroupsToBeEmpty(0.5);

    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    WaitForAllGroupsToBeEmpty(0.5);

    // then
    XCTAssertTrue(self.userSession.hadHistoryAtLastLogin);
}

@end



@implementation LoginFlowTests (PushToken)

- (void)testThatItRegisteresThePushTokenWithTheBackend;
{
    NSData *deviceToken = [@"asdfasdf" dataUsingEncoding:NSUTF8StringEncoding];
    NSString *deviceTokenAsHex = @"6173646661736466";
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    
    [self.userSession setPushToken:deviceToken];
    WaitForEverythingToBeDone();
    
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
    id token = [self.userSession addAuthenticationObserver:authenticationObserver];
    
    XCTestExpectation *loginCodeRequestExpectation = [self expectationWithDescription:@"login code request completed"];
    
    // expect
    [[[authenticationObserver expect] andDo:^(NSInvocation *inv) {
        NOT_USED(inv);
        [loginCodeRequestExpectation fulfill];
    }] loginCodeRequestDidSucceed];
    [[authenticationObserver expect] authenticationDidSucceed];

    // when
    [self.userSession requestPhoneVerificationCodeForLogin:phone];
    XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0.5]);
    
    // then
    XCTAssertEqual(self.mockTransportSession.receivedRequests.count, 1u);
    
    // and when
    [self.userSession loginWithCredentials:[ZMPhoneCredentials credentialsWithPhoneNumber:phone verificationCode:code]];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    [authenticationObserver verify];
    ZMUser *selfUser = [ZMUser selfUserInUserSession:self.userSession];
    XCTAssertEqualObjects(selfUser.name, self.selfUser.name);
    XCTAssertEqualObjects(selfUser.phoneNumber, phone);
    
    [self.userSession removeAuthenticationObserverForToken:token];
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
    id token = [self.userSession addAuthenticationObserver:authenticationObserver];
    
    // expect
    [[authenticationObserver expect] loginCodeRequestDidFail:OCMOCK_ANY];
    
    // when
    [self.userSession requestPhoneVerificationCodeForLogin:phone];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(self.mockTransportSession.receivedRequests.count, 1u);
    [authenticationObserver verify];
    
    [self.userSession removeAuthenticationObserverForToken:token];
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
    id token = [self.userSession addAuthenticationObserver:authenticationObserver];
    
    // expect
    [[authenticationObserver expect] loginCodeRequestDidSucceed];
    [[authenticationObserver expect] authenticationDidFail:[NSError userSessionErrorWithErrorCode:ZMUserSessionInvalidCredentials userInfo:nil]];
    
    // when
    [self.userSession requestPhoneVerificationCodeForLogin:phone];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(self.mockTransportSession.receivedRequests.count, 1u);
    
    // and when
    [self.userSession loginWithCredentials:[ZMPhoneCredentials credentialsWithPhoneNumber:phone verificationCode:self.mockTransportSession.invalidPhoneVerificationCode]];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    [authenticationObserver verify];
    [self.userSession removeAuthenticationObserverForToken:token];
}

@end




@implementation LoginFlowTests (ClientRegistration_Errors)

- (void)testThatItFetchesSelfUserBeforeRegisteringSelfClient
{
    // expect
    __block BOOL didCreateSelfClient = NO;
    __block BOOL didFetchSelfUser = NO;
    self.mockTransportSession.responseGeneratorBlock = ^ZMTransportResponse*(ZMTransportRequest *request) {
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
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
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
    WaitForEverythingToBeDone();
    
    id authenticationObserver = [OCMockObject mockForProtocol:@protocol(ZMAuthenticationObserver)];
    id token = [self.userSession addAuthenticationObserver:authenticationObserver];
    
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
    
    [[authenticationObserver expect] authenticationDidSucceed];
    
    __block BOOL didRun = NO;
    self.mockTransportSession.responseGeneratorBlock = ^ZMTransportResponse*(ZMTransportRequest *request) {
        // when trying to register without email credentials, the BE tells us we need credentials
        if(!didRun && [request.path isEqualToString:@"/clients"] && request.method == ZMMethodPOST) {
            didRun = YES;
            NSDictionary *payload = @{@"label" : @"missing-auth"};
            return [ZMTransportResponse responseWithPayload:payload HTTPStatus:400 transportSessionError:nil];
        }
        // the user updates the email address (currently does not work in MockTransportsession for some reason)
        if ([request.path isEqualToString:@"/self/email"]) {
            return [ZMTransportResponse responseWithPayload:nil HTTPStatus:200 transportSessionError:nil];
        }
        return nil;
    };
    
    // and when
    XCTAssertTrue([self loginAndWaitForSyncToBeCompleteWithPhone:phone ignoringAuthenticationFailure:YES]);
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    [authenticationObserver verify];
    ZMUser *selfUser = [ZMUser selfUserInUserSession:self.userSession];
    
    XCTAssertEqualObjects(selfUser.name, self.selfUser.name);
    XCTAssertEqualObjects(selfUser.phoneNumber, phone);
    XCTAssertEqualObjects(selfUser.emailAddress, email);
    
    [self.userSession removeAuthenticationObserverForToken:token];
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
    WaitForEverythingToBeDone();
    
    id authenticationObserver = [OCMockObject mockForProtocol:@protocol(ZMAuthenticationObserver)];
    id token = [self.userSession addAuthenticationObserver:authenticationObserver];
    __block BOOL didCallTooManyTimes = NO;
    __block NSUInteger runCount = 0;
    
    // expect
    // first provide the wrong credentials
    id provideWrongCredentials = ^(NSInvocation *invocation ZM_UNUSED) {
        [self.mockTransportSession resetReceivedRequests];
        ZMEmailCredentials *credentials = [ZMEmailCredentials credentialsWithEmail:SelfUserEmail password:wrongPassword];
        [self.userSession performChanges:^{
            [self.userSession loginWithCredentials:credentials];
        }];
    };
    
    // second check how often the request to register the client with the wrong credentials is sent
    id checkCallCount = ^(NSInvocation *invocation ZM_UNUSED) {
        // If everything goes right, we only send one request
        XCTAssertEqual(self.mockTransportSession.receivedRequests.count, 1u);
        didCallTooManyTimes = (runCount > 2);
        // If didCallTooManyTimes is true that means that we are still sending out requests while waiting for the user to enter the correct password
        // This should not happen!
        XCTAssertFalse(didCallTooManyTimes);
    };
    
    [[[authenticationObserver expect] andDo:provideWrongCredentials] authenticationDidFail:[NSError userSessionErrorWithErrorCode:ZMUserSessionNeedsPasswordToRegisterClient userInfo:nil]];
    [[[authenticationObserver stub] andDo:checkCallCount] authenticationDidFail:[NSError errorWithDomain:@"ZMUserSession" code:ZMUserSessionInvalidCredentials userInfo:nil]];
    
    self.mockTransportSession.responseGeneratorBlock = ^ZMTransportResponse*(ZMTransportRequest *request) {
        // when trying to register without email credentials, the BE tells us we need credentials
        if(!didCallTooManyTimes && [request.path isEqualToString:@"/clients"] && request.method == ZMMethodPOST) {
            NSDictionary *payload;
            if (runCount == 0) {
                payload = @{@"label" : @"missing-auth"};
            } else {
                payload = @{@"label" : @"invalid-credentials"};
            }
            runCount++;
            return [ZMTransportResponse responseWithPayload:payload HTTPStatus:400 transportSessionError:nil];
        }
        if (didCallTooManyTimes) {
            XCTFail("We sent too many requests trying to register a client.");
            // Without this catch the test might crash
            [[authenticationObserver expect] authenticationDidSucceed];
        }
        return nil;
    };
    
    // and when
    [self.userSession performChanges:^{
        [self.userSession loginWithCredentials:[ZMPhoneCredentials credentialsWithPhoneNumber:phone verificationCode:self.mockTransportSession.phoneVerificationCodeForLogin]];
    }];
    WaitForEverythingToBeDoneWithTimeout(0.5);
    
    // then
    [authenticationObserver verify];
    
    [self.userSession removeAuthenticationObserverForToken:token];
}


- (void)testThatItCanRegisterNewClientAfterDeletingSelfClient
{
    // given
    id authenticationObserver = [OCMockObject mockForProtocol:@protocol(ZMAuthenticationObserver)];
    id token = [self.userSession addAuthenticationObserver:authenticationObserver];
    [[authenticationObserver expect] authenticationDidSucceed];
    
    // (1) register client and recreate session
    {
        XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
        WaitForEverythingToBeDone();
        
        [self recreateUserSessionAndWipeCache:NO];
        WaitForEverythingToBeDone();
    }
    
    // (2) login again after the client was deleted from the backend
    {
        // expect
        id provideCredentials = ^(NSInvocation *invocation ZM_UNUSED) {
            ZMEmailCredentials *credentials = [ZMEmailCredentials credentialsWithEmail:SelfUserEmail password:SelfUserPassword];
            [self.userSession performChanges:^{
                [self.userSession loginWithCredentials:credentials];
            }];
        };
        [[[authenticationObserver expect] andDo:provideCredentials] authenticationDidFail:[NSError userSessionErrorWithErrorCode:ZMUserSessionClientDeletedRemotely userInfo:nil]];

        [[authenticationObserver expect] authenticationDidSucceed];
        [[authenticationObserver expect] authenticationDidSucceed];
        
        __block BOOL didVerifySelfClient = NO;
        self.mockTransportSession.responseGeneratorBlock = ^ZMTransportResponse*(ZMTransportRequest *request) {
            // when logging with a verified client, we fetch the client list from the BE to verify the client is still verified
            // here we return a list that DOES NOT include the current selfClient
            if(!didVerifySelfClient && [request.path isEqualToString:@"/clients"] && request.method == ZMMethodGET) {
                didVerifySelfClient = YES;
                NSArray *emptyClientList = @[];
                return [ZMTransportResponse responseWithPayload:emptyClientList HTTPStatus:200 transportSessionError:nil];
            }
            return nil;
        };
        
        // and when
        XCTAssertTrue([self logInAndWaitForSyncToBeCompleteIgnoringAuthenticationFailures:YES]);
        WaitForAllGroupsToBeEmpty(0.5);
    
        // then
        XCTAssert(didVerifySelfClient);
        [authenticationObserver verify];
        ZMUser *selfUser = [ZMUser selfUserInUserSession:self.userSession];
        XCTAssertEqualObjects(selfUser.name, self.selfUser.name);
    }
    [self.userSession removeAuthenticationObserverForToken:token];
}


- (void)testThatItCanRegisterNewClientAfterDeletingSelfClientAndReceivingNeedsPasswordToRegisterClient
{
    // given
    self.registeredOnThisDevice = YES;
    id authenticationObserver = [OCMockObject mockForProtocol:@protocol(ZMAuthenticationObserver)];
    id token = [self.userSession addAuthenticationObserver:authenticationObserver];
    [[authenticationObserver expect] authenticationDidSucceed];
    __block BOOL didTryToRegisterClient = NO;
    
    // (1) register client and recreate session
    {
        XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
        WaitForEverythingToBeDone();
        
        self.mockTransportSession.responseGeneratorBlock = ^ZMTransportResponse*(ZMTransportRequest *request) {
            // when logging with a verified client, we fetch the client list from the BE to verify the client is still verified
            // here we return a list that DOES NOT include the current selfClient
            if(!didTryToRegisterClient && [request.path isEqualToString:@"/clients"] && request.method == ZMMethodPOST) {
                didTryToRegisterClient = YES;
                NSDictionary *payload = @{@"label" : @"missing-auth"};
                return [ZMTransportResponse responseWithPayload:payload HTTPStatus:400 transportSessionError:nil];
            }
            return nil;
        };
        
        [self recreateUserSessionAndWipeCache:NO];
        WaitForEverythingToBeDone();
    }
    
    // (2) login again after the client was deleted from the backend
    {
        // expect
        id provideCredentials = ^(NSInvocation *invocation ZM_UNUSED) {
            ZMEmailCredentials *credentials = [ZMEmailCredentials credentialsWithEmail:SelfUserEmail password:SelfUserPassword];
            [self.userSession performChanges:^{
                [self.userSession loginWithCredentials:credentials];
            }];
        };
        
        [[[authenticationObserver expect] andDo:provideCredentials] authenticationDidFail:[NSError userSessionErrorWithErrorCode:ZMUserSessionNeedsPasswordToRegisterClient userInfo:nil]];
        
        [[authenticationObserver expect] authenticationDidSucceed];
        [[authenticationObserver expect] authenticationDidSucceed];
        
        
        // and when
        [self.uiMOC setPersistentStoreMetadata:nil forKey:ZMPersistedClientIdKey];
        [self.uiMOC saveOrRollback];
        
        XCTAssertTrue([self logInAndWaitForSyncToBeCompleteIgnoringAuthenticationFailures:YES]);
        WaitForAllGroupsToBeEmpty(0.5);
        
        // then
        XCTAssert(didTryToRegisterClient);
        [authenticationObserver verify];
        ZMUser *selfUser = [ZMUser selfUserInUserSession:self.userSession];
        XCTAssertEqualObjects(selfUser.name, self.selfUser.name);
    }
    [self.userSession removeAuthenticationObserverForToken:token];
}


- (void)testThatItCanRegisterANewClientAfterDeletingClients
{
    // given
    [self recreateUserSessionAndWipeCache:YES];
    WaitForAllGroupsToBeEmpty(0.5);
    
    __block NSString *idToDelete;
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        MockUserClient *client = [session registerClientForUser:self.selfUser label:@"idToDelete" type:@"permanent"];
        idToDelete = client.identifier;
    }];
    WaitForAllGroupsToBeEmpty(0.5);

    id authenticationObserver = [OCMockObject mockForProtocol:@protocol(ZMAuthenticationObserver)];
    id token = [self.userSession addAuthenticationObserver:authenticationObserver];
    
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
    
    [[[authenticationObserver expect] andDo:deleteClients] authenticationDidFail:[OCMArg checkWithBlock:^BOOL(NSError *error) {
        return error.code == ZMUserSessionCanNotRegisterMoreClients;
    }]];
    [[authenticationObserver expect] authenticationDidSucceed];

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
    XCTAssertTrue([self logInAndWaitForSyncToBeCompleteIgnoringAuthenticationFailures:YES]);
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssert(didTryToRegister);
    [authenticationObserver verify];
    ZMUser *selfUser = [ZMUser selfUserInUserSession:self.userSession];
    XCTAssertEqualObjects(selfUser.name, self.selfUser.name);
    
    [self.userSession removeAuthenticationObserverForToken:token];
}

@end
