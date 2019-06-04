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

@interface LoginFlowTests : IntegrationTest
@end

@implementation LoginFlowTests

- (void)setUp
{
    [super setUp];
    
    [self createSelfUserAndConversation];
}

- (void)tearDown
{
    DebugLoginFailureTimerOverride = 0;
    
    [super tearDown];
}

- (NSArray *)expectationsForSuccessfulRegistration
{
    XCTestExpectation *authenticationDidSucceedExpectation = [self expectationWithDescription:@"authentication did succeed"];
    XCTestExpectation *readyToImportBackup = [self expectationWithDescription:@"ready to import backup"];
    id preLoginToken = [[PreLoginAuthenticationObserverToken alloc] initWithAuthenticationStatus:self.unauthenticatedSession.authenticationStatus handler:^(enum PreLoginAuthenticationEventObjc event, NSError *error) {
        NOT_USED(error);

        if (event == PreLoginAuthenticationEventObjcAuthenticationDidSucceed) {
            [authenticationDidSucceedExpectation fulfill];
        } else if (event == PreLoginAuthenticationEventObjcReadyToImportBackupNewAccount) {
            [self.unauthenticatedSession continueAfterBackupImportStep];
            [readyToImportBackup fulfill];
        }

    }];

    XCTestExpectation *clientRegisteredExpectation = [self expectationWithDescription:@"client was registered"];
    id postLoginToken = [[PostLoginAuthenticationObserverObjCToken alloc] initWithDispatchGroup:self.dispatchGroup handler:^(enum PostLoginAuthenticationEventObjC event, NSUUID *accountId, NSError *error) {
        NOT_USED(error);
        NOT_USED(accountId);
        
        if (event == PostLoginAuthenticationEventObjCClientRegistrationDidSucceed) {
            [clientRegisteredExpectation fulfill];
        }
    }];
    
    return @[preLoginToken, postLoginToken];
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
    NSArray *tokens = [self expectationsForSuccessfulRegistration];
    
    // when
    ZMCredentials *credentials = [ZMEmailCredentials credentialsWithEmail:email password:password];
    [self.unauthenticatedSession loginWithCredentials:credentials];
    
    // then
    XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0.5]);
    XCTAssertNotNil([self.mockTransportSession.cookieStorage authenticationCookieData]);
    XCTAssertTrue(self.userSession.isLoggedIn);
    WaitForAllGroupsToBeEmpty(0.5);
    
    tokens = nil;
}

- (void)testThatItWaitsAfterEmailLoginToImportBackup
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
    XCTestExpectation *readyToImportBackup = [self expectationWithDescription:@"ready to import backup"];
    id preLoginToken = [[PreLoginAuthenticationObserverToken alloc] initWithAuthenticationStatus:self.unauthenticatedSession.authenticationStatus handler:^(enum PreLoginAuthenticationEventObjc event, NSError *error) {
        NOT_USED(error);
        if (event == PreLoginAuthenticationEventObjcReadyToImportBackupNewAccount) {
            [readyToImportBackup fulfill];
        }
    }];

    // when
    ZMCredentials *credentials = [ZMEmailCredentials credentialsWithEmail:email password:password];
    [self.unauthenticatedSession loginWithCredentials:credentials];

    // then
    XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0.5]);
    WaitForAllGroupsToBeEmpty(0.5);
    XCTAssertFalse(self.userSession.isLoggedIn);
    WaitForAllGroupsToBeEmpty(0.5);

    preLoginToken = nil;
}

- (void)testThatItWaitsAfterPhoneLoginToImportBackup
{
    // given
    NSString *phone = @"+4912345678900";
    NSString *code = self.mockTransportSession.phoneVerificationCodeForLogin;
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        NOT_USED(session);
        self.selfUser.phone = phone;
    }];

    // when
    [self.unauthenticatedSession requestPhoneVerificationCodeForLogin:phone];
    WaitForAllGroupsToBeEmpty(0.5);

    // then
    XCTAssertEqual(self.mockTransportSession.receivedRequests.count, 1u);

    // and when
    [self.unauthenticatedSession loginWithCredentials:[ZMPhoneCredentials credentialsWithPhoneNumber:phone verificationCode:code]];
    WaitForAllGroupsToBeEmpty(0.5);

    // expect
    XCTestExpectation *readyToImportBackup = [self expectationWithDescription:@"ready to import backup"];
    id preLoginToken = [[PreLoginAuthenticationObserverToken alloc] initWithAuthenticationStatus:self.unauthenticatedSession.authenticationStatus handler:^(enum PreLoginAuthenticationEventObjc event, NSError *error) {
        NOT_USED(error);
        if (event == PreLoginAuthenticationEventObjcReadyToImportBackupNewAccount) {
            [readyToImportBackup fulfill];
        }
    }];

    preLoginToken = nil;
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
    
    // expect
    NSArray *tokens = [self expectationsForSuccessfulRegistration];

    // when
    ZMCredentials *credentials = [ZMEmailCredentials credentialsWithEmail:email password:password];
    [self.unauthenticatedSession loginWithCredentials:credentials];

    // then
    XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0.5]);
    WaitForAllGroupsToBeEmpty(0.5);
    XCTAssertNotNil([self.mockTransportSession.cookieStorage authenticationCookieData]);
    XCTAssertTrue(self.userSession.isLoggedIn);
    WaitForAllGroupsToBeEmpty(0.5);
    
    tokens = nil;
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
    
    // expect
    XCTestExpectation *expectation = [self expectationWithDescription:@"Authentication did fail"];
    id token = [[PreLoginAuthenticationObserverToken alloc] initWithAuthenticationStatus:self.unauthenticatedSession.authenticationStatus handler:^(enum PreLoginAuthenticationEventObjc event, NSError *error) {
        if (event == PreLoginAuthenticationEventObjcAuthenticationDidFail && error.code == ZMUserSessionInvalidCredentials) {
            [expectation fulfill];
        }
    }];
    
    // when
    ZMCredentials *credentials = [ZMEmailCredentials credentialsWithEmail:email password:@"wrong-password"];
    [self.unauthenticatedSession loginWithCredentials:credentials];
    
    // then
    XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0.5]);
    token = nil;
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

    PreLoginAuthenticationNotificationRecorder *recorder = [[PreLoginAuthenticationNotificationRecorder alloc] initWithAuthenticationStatus:self.unauthenticatedSession.authenticationStatus];
    
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
    [self.unauthenticatedSession continueAfterBackupImportStep];
    WaitForAllGroupsToBeEmpty(0.5);

    XCTAssertFalse(self.userSession.isLoggedIn);
    
    XCTAssertEqual(recorder.notifications.count, 2lu);
    XCTAssertEqual(recorder.notifications.firstObject.event, PreLoginAuthenticationEventObjcReadyToImportBackupNewAccount);
    XCTAssertEqual(recorder.notifications.lastObject.event, PreLoginAuthenticationEventObjcAuthenticationDidSucceed);
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
    
    PreLoginAuthenticationNotificationRecorder *recorder = [[PreLoginAuthenticationNotificationRecorder alloc] initWithAuthenticationStatus:self.unauthenticatedSession.authenticationStatus];
    
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
    [self.unauthenticatedSession continueAfterBackupImportStep];
    WaitForAllGroupsToBeEmpty(0.5);
    
    XCTAssertFalse(self.userSession.isLoggedIn);
    XCTAssertEqual(recorder.notifications.count, 2lu);
    XCTAssertEqual(recorder.notifications.firstObject.event, PreLoginAuthenticationEventObjcReadyToImportBackupNewAccount);
    XCTAssertEqual(recorder.notifications.lastObject.event, PreLoginAuthenticationEventObjcAuthenticationDidSucceed);
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
    PreLoginAuthenticationNotificationRecorder *recorder = [[PreLoginAuthenticationNotificationRecorder alloc] initWithAuthenticationStatus:self.unauthenticatedSession.authenticationStatus];
    DebugLoginFailureTimerOverride = 0.2;
    
    // when
    ZMCredentials *cred = [ZMEmailCredentials credentialsWithEmail:@"janet@fo.example.com" password:@"::FsdF:#$:fgsdAG"];
    [self.unauthenticatedSession loginWithCredentials:cred];
    
    // then
    XCTAssertTrue([self waitOnMainLoopUntilBlock:^BOOL{
        return recorder.notifications.count > 0u;
    } timeout:0.5]);
    WaitForAllGroupsToBeEmpty(0.5);
    
    
    XCTAssertGreaterThanOrEqual(recorder.notifications.count, 1lu);
    XCTAssertEqual(recorder.notifications.firstObject.event, PreLoginAuthenticationEventObjcAuthenticationDidFail);
    XCTAssertEqual(recorder.notifications.firstObject.error.code, (long)ZMUserSessionNetworkError);
    XCTAssertLessThan(self.mockTransportSession.receivedRequests.count, 2u);
    
    // after
    DebugLoginFailureTimerOverride = 0;
}

@end


@implementation LoginFlowTests (PushToken)

- (void)testThatItRegistersThePushTokenWithTheBackend;
{
    // given
    NSData *deviceToken = [@"asdfasdf" dataUsingEncoding:NSUTF8StringEncoding];
    NSString *deviceTokenAsHex = @"6173646661736466";
    XCTAssertTrue([self login]);
    
    // then
    XCTAssertTrue([self.pushRegistry.desiredPushTypes containsObject:PKPushTypeVoIP]);
    
    // when
    [self.pushRegistry updatePushToken:deviceToken];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    NSDictionary *registeredTokens = self.mockTransportSession.pushTokens;
    XCTAssertEqual(registeredTokens.count, 1u);
    NSDictionary *registeredToken = registeredTokens[deviceTokenAsHex];
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
    
    PostLoginAuthenticationNotificationRecorder *recorder = [[PostLoginAuthenticationNotificationRecorder alloc] initWithDispatchGroup:self.dispatchGroup];

    // when
    [self.unauthenticatedSession requestPhoneVerificationCodeForLogin:phone];
    WaitForAllGroupsToBeEmpty(0.5);

    // then
    XCTAssertEqual(self.mockTransportSession.receivedRequests.count, 1u);
    
    // and when
    [self.unauthenticatedSession loginWithCredentials:[ZMPhoneCredentials credentialsWithPhoneNumber:phone verificationCode:code]];
    WaitForAllGroupsToBeEmpty(0.5);
    [self.unauthenticatedSession continueAfterBackupImportStep];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(recorder.notifications.count, 1lu);
    XCTAssertEqual(recorder.notifications.lastObject.event, PostLoginAuthenticationEventObjCClientRegistrationDidSucceed);
    
    ZMUser *selfUser = [ZMUser selfUserInUserSession:self.userSession];
    XCTAssertEqualObjects(selfUser.name, self.selfUser.name);
    XCTAssertEqualObjects(selfUser.phoneNumber, phone);
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
    
    // expect
    XCTestExpectation *expectation = [self expectationWithDescription:@"login code request did fail"];
    id token = [[PreLoginAuthenticationObserverToken alloc] initWithAuthenticationStatus:self.unauthenticatedSession.authenticationStatus handler:^(enum PreLoginAuthenticationEventObjc event, NSError *error) {
        NOT_USED(error);
        if (event == PreLoginAuthenticationEventObjcLoginCodeRequestDidFail) {
            [expectation fulfill];
        }
    }];
    
    // when
    [self.unauthenticatedSession requestPhoneVerificationCodeForLogin:phone];
    XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0.5]);
    
    // then
    XCTAssertEqual(self.mockTransportSession.receivedRequests.count, 1u);
    token = nil;
}

- (void)testThatItNotifiesIfTheLoginFails
{
    // given
    NSString *phone = @"+4912345678900";
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        NOT_USED(session);
        self.selfUser.phone = phone;
    }];
    PreLoginAuthenticationNotificationRecorder *recorder = [[PreLoginAuthenticationNotificationRecorder alloc] initWithAuthenticationStatus:self.unauthenticatedSession.authenticationStatus];
    
    // when
    [self.unauthenticatedSession requestPhoneVerificationCodeForLogin:phone];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(self.mockTransportSession.receivedRequests.count, 1u);
    
    // and when
    [self.unauthenticatedSession loginWithCredentials:[ZMPhoneCredentials credentialsWithPhoneNumber:phone verificationCode:self.mockTransportSession.invalidPhoneVerificationCode]];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(recorder.notifications.count, 2lu);
    XCTAssertEqual(recorder.notifications.firstObject.event, PreLoginAuthenticationEventObjcLoginCodeRequestDidSucceed);
    XCTAssertEqual(recorder.notifications.lastObject.event, PreLoginAuthenticationEventObjcAuthenticationDidFail);
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
    
    XCTestExpectation *clientRegistrationDidSucceed = [self expectationWithDescription:@"client was registered"];
    id postLoginToken = [[PostLoginAuthenticationObserverObjCToken alloc] initWithDispatchGroup:self.dispatchGroup handler:^(enum PostLoginAuthenticationEventObjC event, NSUUID *accountId, NSError *error) {
        NOT_USED(accountId);
        
        if (event == PostLoginAuthenticationEventObjCClientRegistrationDidFail && error.code == (long)ZMUserSessionNeedsToRegisterEmailToRegisterClient) {
//            [clientRegisteredDidFailExpectation fulfill];
            
            ZMEmailCredentials *credentials = [ZMEmailCredentials credentialsWithEmail:email password:password];
            [self.userSession performChanges:^{
                [self.userSession.userProfileUpdateStatus requestSettingEmailAndPasswordWithCredentials:credentials error:nil];
            }];
            
            [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
                // simulate user click on email
                NOT_USED(session);
                self.selfUser.email = email;
            }];
        }
        
        if (event == PostLoginAuthenticationEventObjCClientRegistrationDidSucceed) {
            [clientRegistrationDidSucceed fulfill];
        }
    }];
    
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
    XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0.5]);
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    ZMUser *selfUser = [ZMUser selfUserInUserSession:self.userSession];
    XCTAssertEqualObjects(selfUser.name, self.selfUser.name);
    XCTAssertEqualObjects(selfUser.phoneNumber, phone);
    XCTAssertEqualObjects(selfUser.emailAddress, email);
    
    postLoginToken = nil;
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
    __block NSUInteger runCount = 0;
    
    // expect
    XCTestExpectation *clientRegistrationDidSucceed = [self expectationWithDescription:@"client was registered"];
    id postLoginToken = [[PostLoginAuthenticationObserverObjCToken alloc] initWithDispatchGroup:self.dispatchGroup handler:^(enum PostLoginAuthenticationEventObjC event, NSUUID *accountId, NSError *error) {
        NOT_USED(accountId);
        
        if (event == PostLoginAuthenticationEventObjCClientRegistrationDidFail && error.code == (long)ZMUserSessionNeedsPasswordToRegisterClient) {
            // first provide the wrong credentials
            [self.mockTransportSession resetReceivedRequests];
            ZMEmailCredentials *credentials = [ZMEmailCredentials credentialsWithEmail:IntegrationTest.SelfUserEmail password:wrongPassword];
            [self.unauthenticatedSession loginWithCredentials:credentials];
        }
        else if (event == PostLoginAuthenticationEventObjCClientRegistrationDidFail && error.code == (long)ZMUserSessionInvalidCredentials) {
            // now we provide the right password
            [self.mockTransportSession resetReceivedRequests];
            ZMEmailCredentials *credentials = [ZMEmailCredentials credentialsWithEmail:IntegrationTest.SelfUserEmail password:IntegrationTest.SelfUserPassword];
            [self.unauthenticatedSession loginWithCredentials:credentials];
        }
        else if (event == PostLoginAuthenticationEventObjCClientRegistrationDidSucceed) {
            [clientRegistrationDidSucceed fulfill];
        }
    }];
    
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
    [self.unauthenticatedSession continueAfterBackupImportStep];
    WaitForAllGroupsToBeEmpty(0.5);

    XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0.5]);

    // then
    postLoginToken = nil;
}

- (void)testThatItCanRegisterNewClientAfterDeletingSelfClient
{
    // given
    XCTAssertTrue([self login]);
    
    
    PostLoginAuthenticationNotificationRecorder *recorder = [[PostLoginAuthenticationNotificationRecorder alloc] initWithDispatchGroup:self.dispatchGroup];
    
    // when we delete self client
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        MockUserClient *selfClient = self.selfUser.clients.anyObject;
        [session deleteUserClientWithIdentifier:selfClient.identifier forUser:self.selfUser];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // when login 2nd time
    XCTAssertTrue([self login]);
    
    // then
    XCTAssertEqual(recorder.notifications.count, 2lu);
    XCTAssertEqual(recorder.notifications.firstObject.event, PostLoginAuthenticationEventObjCAuthenticationInvalidated);
    XCTAssertEqual(recorder.notifications.lastObject.event, PostLoginAuthenticationEventObjCClientRegistrationDidSucceed);

    XCTAssertEqual(recorder.notifications.firstObject.error.code, ZMUserSessionClientDeletedRemotely);
    XCTAssertEqualObjects([recorder.notifications.firstObject.error.userInfo objectForKey:ZMEmailCredentialKey], IntegrationTest.SelfUserEmail);
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
        XCTestExpectation *clientRegistrationDidSucceed = [self expectationWithDescription:@"client was registered"];
        id postLoginToken = [[PostLoginAuthenticationObserverObjCToken alloc] initWithDispatchGroup:self.dispatchGroup handler:^(enum PostLoginAuthenticationEventObjC event, NSUUID *accountId, NSError *error) {
            NOT_USED(accountId);
            
            if (event == PostLoginAuthenticationEventObjCClientRegistrationDidFail && error.code == (long)ZMUserSessionNeedsPasswordToRegisterClient) {
                ZMEmailCredentials *credentials = [ZMEmailCredentials credentialsWithEmail:IntegrationTest.SelfUserEmail password:IntegrationTest.SelfUserPassword];
                [self.userSession performChanges:^{
                    [self.unauthenticatedSession loginWithCredentials:credentials];
                }];
            }
            else if (event == PostLoginAuthenticationEventObjCClientRegistrationDidSucceed) {
                [clientRegistrationDidSucceed fulfill];
            }
        }];
        
        // when
        [self.unauthenticatedSession requestPhoneVerificationCodeForLogin:phone];
        XCTAssertTrue([self loginWithCredentials:[ZMPhoneCredentials credentialsWithPhoneNumber:phone verificationCode:code] ignoreAuthenticationFailures:YES]);
        XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0.5]);
        WaitForAllGroupsToBeEmpty(0.5);
        
        // then
        ZMUser *selfUser = [ZMUser selfUserInUserSession:self.userSession];
        XCTAssertEqualObjects(selfUser.name, self.selfUser.name);
        postLoginToken = nil;
    }
}

- (void)testThatItCanRegisterANewClientAfterDeletingClients
{
    // given
    __block NSString *idToDelete;
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        MockUserClient *client = [session registerClientForUser:self.selfUser];
        idToDelete = client.identifier;
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // expect
    XCTestExpectation *clientRegistrationDidSucceed = [self expectationWithDescription:@"client was registered"];
    id postLoginToken = [[PostLoginAuthenticationObserverObjCToken alloc] initWithDispatchGroup:self.dispatchGroup handler:^(enum PostLoginAuthenticationEventObjC event, NSUUID *accountId, NSError *error) {
        NOT_USED(accountId);
        
        if (event == PostLoginAuthenticationEventObjCClientRegistrationDidFail && error.code == (long)ZMUserSessionCanNotRegisterMoreClients) {
            // simulate the user selecting a client to delete
            [self.userSession performChanges:^{
                ZMUser *selfUser = [self userForMockUser:self.selfUser];
                [selfUser.managedObjectContext saveOrRollback];
                UserClient *clientToDelete = [selfUser.clients.allObjects firstObjectMatchingWithBlock:^BOOL(UserClient *client) {
                    return [client.remoteIdentifier isEqualToString:idToDelete];
                }];
                XCTAssertNotNil(clientToDelete);
                [self.userSession deleteClient:clientToDelete withCredentials:nil];
            }];
        }
        else if (event == PostLoginAuthenticationEventObjCClientRegistrationDidSucceed) {
            [clientRegistrationDidSucceed fulfill];
        }
    }];
    
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
    XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0.5]);
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssert(didTryToRegister);
    ZMUser *selfUser = [ZMUser selfUserInUserSession:self.userSession];
    XCTAssertEqualObjects(selfUser.name, self.selfUser.name);
    postLoginToken = nil;
}

@end
