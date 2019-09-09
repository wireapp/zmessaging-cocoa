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
@import WireDataModel;
@import WireTransport;

#import "MessagingTest.h"
#import "ZMUserSessionRegistrationNotification.h"
#import "ZMCredentials.h"
#import "NSError+ZMUserSessionInternal.h"
#import <WireSyncEngine/WireSyncEngine-Swift.h>
#import "WireSyncEngine_iOS_Tests-Swift.h"


@interface ZMAuthenticationStatusTests : MessagingTest

@property (nonatomic) ZMAuthenticationStatus *sut;

@property (nonatomic) id authenticationObserverToken;
@property (nonatomic, copy) void(^authenticationCallback)(enum PreLoginAuthenticationEventObjc event, NSError *error);

@property (nonatomic) id registrationObserverToken;
@property (nonatomic, copy) void(^registrationCallback)(ZMUserSessionRegistrationNotificationType type, NSError *error);
@property (nonatomic) MockUserInfoParser *userInfoParser;

@end

@implementation ZMAuthenticationStatusTests

- (void)setUp {
    [super setUp];

    self.userInfoParser = [[MockUserInfoParser alloc] init];
    DispatchGroupQueue *groupQueue = [[DispatchGroupQueue alloc] initWithQueue:dispatch_get_main_queue()];
    self.sut = [[ZMAuthenticationStatus alloc] initWithGroupQueue:groupQueue userInfoParser:self.userInfoParser];

    // If a test fires any notification and it's not listening for it, this will fail
    ZM_WEAK(self);
    self.authenticationCallback = ^(enum PreLoginAuthenticationEventObjc event, NSError *error){
        NOT_USED(error);
        ZM_STRONG(self);
        XCTFail(@"Unexpected notification: %li", event);
    };
    // If a test fires any notification and it's not listening for it, this will fail
    self.registrationCallback = ^(ZMUserSessionRegistrationNotificationType type, NSError *error){
        NOT_USED(error);
        ZM_STRONG(self);
        XCTFail(@"Unexpected notification %li", type);
    }; // forces to overwrite if a test fires this
    
    self.authenticationObserverToken = [[PreLoginAuthenticationObserverToken alloc] initWithAuthenticationStatus:self.sut handler:^(enum PreLoginAuthenticationEventObjc event, NSError *error) {
        ZM_STRONG(self);
        self.authenticationCallback(event, error);
    }];
    
    self.registrationObserverToken = [ZMUserSessionRegistrationNotification addObserverInContext:self.sut withBlock:^(ZMUserSessionRegistrationNotificationType event, NSError *error) {
        ZM_STRONG(self);
        self.registrationCallback(event, error);
    }];
}

- (void)tearDown
{
    self.sut = nil;
    self.authenticationObserverToken = nil;
    self.registrationObserverToken = nil;
    self.userInfoParser = nil;
    [super tearDown];
}

- (void)testThatAllValuesAreEmptyAfterInit
{
    XCTAssertEqual(self.sut.currentPhase, ZMAuthenticationPhaseUnauthenticated);
    
    XCTAssertNil(self.sut.registrationPhoneNumberThatNeedsAValidationCode);
    XCTAssertNil(self.sut.loginPhoneNumberThatNeedsAValidationCode);
    XCTAssertNil(self.sut.loginCredentials);
    XCTAssertNil(self.sut.registrationPhoneValidationCredentials);
}


- (void)testThatItIsLoggedInWhenThereIsAuthenticationDataSelfUserSyncedAndClientIsAlreadyRegistered
{
    // when
    self.sut.authenticationCookieData = NSData.data;
    [self.uiMOC setPersistentStoreMetadata:@"someID" forKey:ZMPersistedClientIdKey];
    ZMUser *selfUser = [ZMUser selfUserInContext:self.uiMOC];
    selfUser.remoteIdentifier = [NSUUID new];
    
    // then
    XCTAssertEqual(self.sut.currentPhase, ZMAuthenticationPhaseAuthenticated);
    [self.uiMOC setPersistentStoreMetadata:nil forKey:@"PersistedClientId"];
}

@end

@implementation ZMAuthenticationStatusTests (PrepareMethods)

- (void)testThatItCanLoginWithEmailAfterSettingCredentials
{
    // given
    NSString *email = @"foo@foo.bar";
    NSString *pass = @"123456xcxc";
    
    ZMCredentials *credentials = [ZMEmailCredentials credentialsWithEmail:email password:pass];
    
    // when
    [self performPretendingUiMocIsSyncMoc:^{
        [self.sut prepareForLoginWithCredentials:credentials];
    }];
    
    // then
    XCTAssertEqual(self.sut.currentPhase, ZMAuthenticationPhaseLoginWithEmail);
    XCTAssertEqual(self.sut.loginCredentials, credentials);
}

- (void)testThatItCanLoginWithPhoneAfterSettingCredentials
{
    // given
    NSString *phone = @"+4912345678900";
    NSString *code = @"123456";
    
    ZMCredentials *credentials = [ZMPhoneCredentials credentialsWithPhoneNumber:phone verificationCode:code];
    
    // when
    [self performPretendingUiMocIsSyncMoc:^{
        [self.sut prepareForLoginWithCredentials:credentials];
    }];
    // then
    XCTAssertEqual(self.sut.currentPhase, ZMAuthenticationPhaseLoginWithPhone);
    XCTAssertEqual(self.sut.loginCredentials, credentials);

}

@end


@implementation ZMAuthenticationStatusTests (CompletionMethods)

- (void)testThatItResetsWhenCompletingTheRequestForPhoneLoginCode
{
    // expect
    XCTestExpectation *expectation = [self expectationWithDescription:@"notification"];
    ZM_WEAK(self);
    
    self.authenticationCallback = ^(enum PreLoginAuthenticationEventObjc event, __unused NSError *error) {
        ZM_STRONG(self);
        XCTAssertEqual(event, PreLoginAuthenticationEventObjcLoginCodeRequestDidSucceed);
        [expectation fulfill];
    };
    
    // when
    [self.sut prepareForRequestingPhoneVerificationCodeForLogin:@"+4912345678"];
    [self.sut didCompleteRequestForLoginCodeSuccessfully];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(self.sut.currentPhase, ZMAuthenticationPhaseUnauthenticated);
    XCTAssertNil(self.sut.loginPhoneNumberThatNeedsAValidationCode);
    
    XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0]);
}

- (void)testThatItResetsWhenFailingTheRequestForPhoneLoginCode
{
    // expect
    XCTestExpectation *expectation = [self expectationWithDescription:@"notification"];
    NSError *expectedError = [NSError userSessionErrorWithErrorCode:ZMUserSessionInvalidPhoneNumber userInfo:nil];
    ZM_WEAK(self);
    self.authenticationCallback = ^(enum PreLoginAuthenticationEventObjc event, NSError *error) {
        ZM_STRONG(self);
        XCTAssertEqual(event, PreLoginAuthenticationEventObjcLoginCodeRequestDidFail);
        XCTAssertEqual(error, expectedError);
        [expectation fulfill];
    };
    
    // when
    [self.sut prepareForRequestingPhoneVerificationCodeForLogin:@"+4912345678"];
    [self.sut didFailRequestForLoginCode:expectedError];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(self.sut.currentPhase, ZMAuthenticationPhaseUnauthenticated);
    XCTAssertNil(self.sut.loginPhoneNumberThatNeedsAValidationCode);
    
    XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0]);
}

- (void)testThatItResetsWhenFailingEmailLogin
{
    // expect
    XCTestExpectation *expectation = [self expectationWithDescription:@"notification"];
    ZM_WEAK(self);
    self.authenticationCallback = ^(enum PreLoginAuthenticationEventObjc event, NSError *error) {
        ZM_STRONG(self);
        XCTAssertEqual(event, PreLoginAuthenticationEventObjcAuthenticationDidFail);
        XCTAssertEqualObjects(error, [NSError userSessionErrorWithErrorCode:ZMUserSessionInvalidCredentials userInfo:nil]);
        [expectation fulfill];
    };
    
    // given
    NSString *email = @"gfdgfgdfg@fds.sgf";
    NSString *password = @"#$4tewt343$";
    
    // when
    [self performPretendingUiMocIsSyncMoc:^{
        [self.sut prepareForLoginWithCredentials:[ZMEmailCredentials credentialsWithEmail:email password:password]];
    }];
    [self.sut didFailLoginWithEmail:YES];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(self.sut.currentPhase, ZMAuthenticationPhaseUnauthenticated);
    XCTAssertNil(self.sut.loginCredentials);
    
    XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0]);
}

- (void)testThatItResetsWhenFailingPhoneLogin
{
    // expect
    XCTestExpectation *expectation = [self expectationWithDescription:@"notification"];
    ZM_WEAK(self);
    self.authenticationCallback = ^(enum PreLoginAuthenticationEventObjc event, NSError *error) {
        ZM_STRONG(self);
        XCTAssertEqual(event, PreLoginAuthenticationEventObjcAuthenticationDidFail);
        XCTAssertEqualObjects(error, [NSError userSessionErrorWithErrorCode:ZMUserSessionInvalidCredentials userInfo:nil]);
        [expectation fulfill];
    };
    
    // given
    NSString *phone = @"+49123456789000";
    NSString *code = @"324543";
    
    // when
    [self performPretendingUiMocIsSyncMoc:^{
        [self.sut prepareForLoginWithCredentials:[ZMPhoneCredentials credentialsWithPhoneNumber:phone verificationCode:code]];
    }];
    [self.sut didFailLoginWithPhone:YES];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(self.sut.currentPhase, ZMAuthenticationPhaseUnauthenticated);
    XCTAssertNil(self.sut.loginCredentials);
    
    XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0]);
}

- (void)testThatItResetsWhenTimingOutLoginWithTheSameCredentials
{
    // expect
    XCTestExpectation *expectation = [self expectationWithDescription:@"notification"];
    ZM_WEAK(self);
    self.authenticationCallback = ^(enum PreLoginAuthenticationEventObjc event, NSError *error) {
        ZM_STRONG(self);
        XCTAssertEqual(event, PreLoginAuthenticationEventObjcAuthenticationDidFail);
        XCTAssertEqualObjects(error, [NSError userSessionErrorWithErrorCode:ZMUserSessionNetworkError userInfo:nil]);
        [expectation fulfill];
    };
    
    // given
    NSString *email = @"gfdgfgdfg@fds.sgf";
    NSString *password = @"#$4tewt343$";
    ZMCredentials *credentials = [ZMEmailCredentials credentialsWithEmail:email password:password];
    
    // when
    [self performPretendingUiMocIsSyncMoc:^{
        [self.sut prepareForLoginWithCredentials:credentials];
    }];
    [self.sut didTimeoutLoginForCredentials:credentials];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(self.sut.currentPhase, ZMAuthenticationPhaseUnauthenticated);
    XCTAssertNil(self.sut.loginCredentials);
    
    XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0]);
}

- (void)testThatItDoesNotResetsWhenTimingOutLoginWithDifferentCredentials
{
    // given
    NSString *email = @"gfdgfgdfg@fds.sgf";
    NSString *password = @"#$4tewt343$";
    ZMCredentials *credentials1 = [ZMEmailCredentials credentialsWithEmail:email password:password];
    ZMCredentials *credentials2 = [ZMPhoneCredentials credentialsWithPhoneNumber:@"+4912345678900" verificationCode:@"123456"];
    
    // when
    [self performPretendingUiMocIsSyncMoc:^{
        [self.sut prepareForLoginWithCredentials:credentials1];
    }];
    [self.sut didTimeoutLoginForCredentials:credentials2];
    
    // then
    XCTAssertEqual(self.sut.currentPhase, ZMAuthenticationPhaseLoginWithEmail);
    XCTAssertEqualObjects(self.sut.loginCredentials, credentials1);
}

- (void)testThatItWaitsForBackupImportAfterLoggingInWithEmail
{
    // expect
    XCTestExpectation *expectation = [self expectationWithDescription:@"notification"];
    ZM_WEAK(self);
    self.authenticationCallback = ^(enum PreLoginAuthenticationEventObjc event, NSError *error) {
        ZM_STRONG(self);
        XCTAssertEqual(event, PreLoginAuthenticationEventObjcReadyToImportBackupNewAccount);
        XCTAssertNil(error);
        [expectation fulfill];
    };

    // given
    NSString *email = @"gfdgfgdfg@fds.sgf";
    NSString *password = @"#$4tewt343$";

    // when
    [self performPretendingUiMocIsSyncMoc:^{
        [self.sut prepareForLoginWithCredentials:[ZMEmailCredentials credentialsWithEmail:email password:password]];
    }];
    [self.sut loginSucceededWithResponse:nil];
    WaitForAllGroupsToBeEmpty(0.5);

    // then
    XCTAssertEqual(self.sut.currentPhase, ZMAuthenticationPhaseWaitingToImportBackup);
    XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0]);
}

- (void)testThatItAsksForUserInfoParserIfAccountForBackupExists
{
    // expect
    XCTestExpectation *expectation = [self expectationWithDescription:@"notification"];
    ZM_WEAK(self);
    self.authenticationCallback = ^(enum PreLoginAuthenticationEventObjc event, NSError *error) {
        ZM_STRONG(self);
        XCTAssertEqual(event, PreLoginAuthenticationEventObjcReadyToImportBackupExistingAccount);
        XCTAssertNil(error);
        [expectation fulfill];
    };

    // given
    NSString *email = @"gfdgfgdfg@fds.sgf";
    NSString *password = @"#$4tewt343$";
    
    UserInfo *info = [[UserInfo alloc] initWithIdentifier:NSUUID.createUUID cookieData:NSData.data];
    self.userInfoParser.existingAccounts = [self.userInfoParser.existingAccounts arrayByAddingObject:info];

    // when
    [self performPretendingUiMocIsSyncMoc:^{
        [self.sut prepareForLoginWithCredentials:[ZMEmailCredentials credentialsWithEmail:email password:password]];
    }];

    [self.sut loginSucceededWithUserInfo:info];
    WaitForAllGroupsToBeEmpty(0.5);

    // then
    XCTAssertEqual(self.sut.currentPhase, ZMAuthenticationPhaseWaitingToImportBackup);
    XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0]);
    XCTAssertEqual(self.userInfoParser.accountExistsLocallyCalled, 1);
}

@end


@implementation ZMAuthenticationStatusTests (CredentialProvider)

- (void)testThatItDoesNotReturnCredentialsIfItIsNotLoggedIn
{
    // given
    [self.sut setAuthenticationCookieData:nil];
    
    // then
    XCTAssertNil(self.sut.emailCredentials);
}

- (void)testThatItReturnsCredentialsIfLoggedIn
{
    // given
    [self.sut setAuthenticationCookieData:[NSData data]];
    [self performPretendingUiMocIsSyncMoc:^{
        [self.sut prepareForLoginWithCredentials:[ZMEmailCredentials credentialsWithEmail:@"foo@example.com" password:@"boo"]];
    }];

    // then
    XCTAssertNotNil(self.sut.emailCredentials);
}

- (void)testThatItClearsCredentialsIfInPhaseAuthenticated
{
    // given
    [self performPretendingUiMocIsSyncMoc:^{
        [self.sut prepareForLoginWithCredentials:[ZMEmailCredentials credentialsWithEmail:@"foo@example.com" password:@"boo"]];
    }];
    [self.sut setAuthenticationCookieData:[NSData data]];
    
    XCTAssertNotNil(self.sut.loginCredentials);

    // when
    [self.sut credentialsMayBeCleared];
    
    // then
    XCTAssertNil(self.sut.loginCredentials);
}

- (void)testThatItDoesNotClearCredentialsIfNotAuthenticated
{
    // given
    [self performPretendingUiMocIsSyncMoc:^{
        [self.sut prepareForLoginWithCredentials:[ZMEmailCredentials credentialsWithEmail:@"foo@example.com" password:@"boo"]];
    }];
    
    XCTAssertNotNil(self.sut.loginCredentials);
    
    // when
    [self.sut credentialsMayBeCleared];
    
    // then
    XCTAssertNotNil(self.sut.loginCredentials);
}

@end

@implementation ZMAuthenticationStatusTests (UserInfoParser)

- (void)testThatItCallsUserInfoParserAfterSuccessfulAuthentication
{
    // given
    NSString *email = @"foo@foo.bar";
    NSString *pass = @"123456xcxc";

    ZMCredentials *credentials = [ZMEmailCredentials credentialsWithEmail:email password:pass];
    ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:nil HTTPStatus:200 transportSessionError:nil];

    XCTestExpectation *expectation = [self expectationWithDescription:@"notification"];
    ZM_WEAK(self);
    self.authenticationCallback = ^(enum PreLoginAuthenticationEventObjc event, NSError *error) {
        ZM_STRONG(self);
        if (!(event == PreLoginAuthenticationEventObjcReadyToImportBackupNewAccount ||
              event == PreLoginAuthenticationEventObjcAuthenticationDidSucceed)) {
            XCTFail(@"Unexpected event");
        }
        XCTAssertEqual(error, nil);
        [expectation fulfill];
    };

    // when
    [self performPretendingUiMocIsSyncMoc:^{
        [self.sut prepareForLoginWithCredentials:credentials];
        [self.sut loginSucceededWithResponse:response];
        [self.sut continueAfterBackupImportStep];
    }];

    // then
    XCTAssertEqual(self.userInfoParser.upgradeToAuthenticatedSessionCallCount, 1);
    XCTAssertEqual(self.userInfoParser.upgradeToAuthenticatedSessionUserInfos.firstObject, response.extractUserInfo);
}

@end


@implementation ZMAuthenticationStatusTests (CookieLabel)

- (void)testThatItReturnsTheSameCookieLabel
{
    // when
    CookieLabel *cookieLabel1 = CookieLabel.current;
    CookieLabel *cookieLabel2 = CookieLabel.current;
    
    // then
    XCTAssertNotNil(cookieLabel1);
    XCTAssertEqualObjects(cookieLabel1, cookieLabel2);
}

@end
