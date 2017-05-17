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
#import "ZMUserSessionAuthenticationNotification.h"
#import "ZMUserSessionRegistrationNotification.h"
#import "ZMAuthenticationStatus+Testing.h"
#import "ZMCredentials.h"
#import "NSError+ZMUserSessionInternal.h"
#import <WireSyncEngine/WireSyncEngine-Swift.h>


@interface ZMAuthenticationStatusTests : MessagingTest

@property (nonatomic) ZMAuthenticationStatus *sut;
@property (nonatomic) ZMPersistentCookieStorage *cookieStorage;

@property (nonatomic) id authenticationObserverToken;
@property (nonatomic, copy) void(^authenticationCallback)(ZMUserSessionAuthenticationNotification *note);

@property (nonatomic) id registrationObserverToken;
@property (nonatomic, copy) void(^registrationCallback)(ZMUserSessionRegistrationNotification *note);

@end

@implementation ZMAuthenticationStatusTests

- (void)setUp {
    [super setUp];
    
    self.cookieStorage = [ZMPersistentCookieStorage storageForServerName:@"foo.bar"];
    ZMCookie *cookie = [[ZMCookie alloc] initWithManagedObjectContext:self.uiMOC cookieStorage:self.cookieStorage];
    
    self.sut = [[ZMAuthenticationStatus alloc] initWithManagedObjectContext:self.uiMOC cookie:cookie];
    ZM_WEAK(self);
    // If a test fires any notification and it's not listening for it, this will fail
    self.authenticationCallback = ^(id note ZM_UNUSED){
        ZM_STRONG(self);
        XCTFail(@"Unexpected notification: %@", note);
    };
    // If a test fires any notification and it's not listening for it, this will fail
    self.registrationCallback = ^(id note ZM_UNUSED){
        ZM_STRONG(self);
        XCTFail(@"Unexpected notification %@", note);
    }; // forces to overrite if a test fires this
    
    self.authenticationObserverToken = [ZMUserSessionAuthenticationNotification addObserverWithBlock:^(ZMUserSessionAuthenticationNotification *note) {
        self.authenticationCallback(note);
    }];
    
    self.registrationObserverToken = [ZMUserSessionRegistrationNotification addObserverWithBlock:^(ZMUserSessionRegistrationNotification *note) {
        self.registrationCallback(note);
    }];
}

- (void)tearDown {

    self.sut = nil;
    self.cookieStorage = nil;
    
    [ZMUserSessionAuthenticationNotification removeObserver:self.authenticationObserverToken];
    self.authenticationObserverToken = nil;
    
    [ZMUserSessionRegistrationNotification removeObserver:self.registrationObserverToken];
    self.registrationObserverToken = nil;
    [super tearDown];
}

- (void)testThatAllValuesAreEmptyAfterInit
{
    XCTAssertEqual(self.sut.currentPhase, ZMAuthenticationPhaseUnauthenticated);
    
    XCTAssertNil(self.sut.registrationUser);
    XCTAssertNil(self.sut.registrationPhoneNumberThatNeedsAValidationCode);
    XCTAssertNil(self.sut.loginPhoneNumberThatNeedsAValidationCode);
    XCTAssertNil(self.sut.loginCredentials);
    XCTAssertNil(self.sut.registrationPhoneValidationCredentials);
}


- (void)testThatItIsLoggedInWhenThereIsAuthenticationDataSelfUserSyncedAndClientIsAlreadyRegistered
{
    // when
    [self.cookieStorage setAuthenticationCookieData:[NSData data]];
    [self.uiMOC setPersistentStoreMetadata:@"someID" forKey:ZMPersistedClientIdKey];
    ZMUser *selfUser = [ZMUser selfUserInContext:self.uiMOC];
    selfUser.remoteIdentifier = [NSUUID new];
    
    // then
    XCTAssertEqual(self.sut.currentPhase, ZMAuthenticationPhaseAuthenticated);
    [self.uiMOC setPersistentStoreMetadata:nil forKey:@"PersistedClientId"];
}

- (void)testThatItSetsIgnoreCookiesWhenEmailRegistrationUserIsSet
{
    XCTAssertEqual([ZMPersistentCookieStorage cookiesPolicy], NSHTTPCookieAcceptPolicyAlways);
    ZMCompleteRegistrationUser *regUser = [ZMCompleteRegistrationUser registrationUserWithEmail:@"some@example.com" password:@"password"];
    [self.sut prepareForRegistrationOfUser:regUser];
    XCTAssertEqual([ZMPersistentCookieStorage cookiesPolicy], NSHTTPCookieAcceptPolicyNever);
}

- (void)testThatItSetsAcceptCookiesWhenPhoneNumberRegistrationUserIsSet
{
    [ZMPersistentCookieStorage setCookiesPolicy:NSHTTPCookieAcceptPolicyNever];
    ZMCompleteRegistrationUser *regUser = [ZMCompleteRegistrationUser registrationUserWithPhoneNumber:@"1234567890" phoneVerificationCode:@"123456"];
    [self.sut prepareForRegistrationOfUser:regUser];
    XCTAssertEqual([ZMPersistentCookieStorage cookiesPolicy], NSHTTPCookieAcceptPolicyAlways);
}

- (void)testThatItSetsAcceptCookiesWhenLoginCredentialsAreSet
{
    //given
    ZMCompleteRegistrationUser *regUser = [ZMCompleteRegistrationUser registrationUserWithEmail:@"some@example.com" password:@"password"];
    
    // expect
    XCTestExpectation *expectation = [self expectationWithDescription:@"notification"];
    ZM_WEAK(self);
    self.registrationCallback = ^(__unused id note) {
        ZM_STRONG(self);
        XCTAssertEqual([ZMPersistentCookieStorage cookiesPolicy], NSHTTPCookieAcceptPolicyAlways);
        [expectation fulfill];
    };
    
    // when
    [self.sut prepareForRegistrationOfUser:regUser];
    [self performPretendingUiMocIsSyncMoc:^{
        [self.sut didCompleteRegistrationSuccessfully];
    }];
    
    XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0.5]);
}

@end

@implementation ZMAuthenticationStatusTests (PrepareMethods)

- (void)testThatItCanRegisterWithPhoneAfterSettingTheRegistrationUser
{
    // given
    NSString *phone = @"+49123456789000";
    NSString *code = @"123456";
    
    ZMCompleteRegistrationUser *regUser = [ZMCompleteRegistrationUser registrationUserWithPhoneNumber:phone phoneVerificationCode:code];
    
    // when
    [self.sut prepareForRegistrationOfUser:regUser];
    
    // then
    XCTAssertEqual(self.sut.currentPhase, ZMAuthenticationPhaseRegisterWithPhone);
    XCTAssertEqualObjects(self.sut.registrationUser.phoneNumber, phone);
    XCTAssertEqualObjects(self.sut.registrationUser.phoneVerificationCode, code);
}

- (void)testThatItCanRegisterWithEmailAfterSettingTheRegistrationUser
{
    // given
    NSString *email = @"foo@foo.bar";
    NSString *pass = @"123456xcxc";
    
    ZMCompleteRegistrationUser *regUser = [ZMCompleteRegistrationUser registrationUserWithEmail:email password:pass];
    
    // when
    [self.sut prepareForRegistrationOfUser:regUser];
    
    // then
    XCTAssertEqual(self.sut.currentPhase, ZMAuthenticationPhaseRegisterWithEmail);
    XCTAssertEqualObjects(self.sut.registrationUser.emailAddress, email);
    XCTAssertEqualObjects(self.sut.registrationUser.password, pass);
}

- (void)testThatItCanRegisterWithEmailInvitationAfterSettingTheRegistrationUser
{
    // given
    NSString *email = @"foo@foo.bar";
    NSString *pass = @"123456xcxc";
    NSString *code = @"12392sdksld";
    
    ZMCompleteRegistrationUser *regUser = [ZMCompleteRegistrationUser registrationUserWithEmail:email password:pass invitationCode:code];
    
    // when
    [self.sut prepareForRegistrationOfUser:regUser];
    
    // then
    XCTAssertEqual(self.sut.currentPhase, ZMAuthenticationPhaseRegisterWithEmail);
    XCTAssertEqualObjects(self.sut.registrationUser.emailAddress, email);
    XCTAssertEqualObjects(self.sut.registrationUser.password, pass);
    XCTAssertEqualObjects(self.sut.registrationUser.invitationCode, code);
}

- (void)testThatItCanRegisterWithPhoneInvitationAfterSettingTheRegistrationUser
{
    // given
    NSString *phone = @"+4923238293822";
    NSString *code = @"12392sdksld";
    
    ZMCompleteRegistrationUser *regUser = [ZMCompleteRegistrationUser registrationUserWithPhoneNumber:phone invitationCode:code];
    
    // when
    [self.sut prepareForRegistrationOfUser:regUser];
    
    // then
    XCTAssertEqual(self.sut.currentPhase, ZMAuthenticationPhaseRegisterWithPhone);
    XCTAssertEqualObjects(self.sut.registrationUser.phoneNumber, phone);
    XCTAssertEqualObjects(self.sut.registrationUser.invitationCode, code);
}

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

- (void)testThatItCanRequestPhoneVerificationCodeForRegistrationAfterRequestingTheCode
{
    // given
    NSString *phone = @"+49(123)45678900";
    NSString *normalizedPhone = [phone copy];
    [ZMPhoneNumberValidator validateValue:&normalizedPhone error:nil];
    
    // when
    [self.sut prepareForRequestingPhoneVerificationCodeForRegistration:phone];
    
    // then
    XCTAssertEqual(self.sut.currentPhase, ZMAuthenticationPhaseRequestPhoneVerificationCodeForRegistration);
    XCTAssertEqualObjects(self.sut.registrationPhoneNumberThatNeedsAValidationCode, normalizedPhone);
    XCTAssertNotEqualObjects(normalizedPhone, phone, @"Should not have changed original phone");
}

- (void)testThatItCanRequestPhoneVerificationCodeForLoginAfterRequestingTheCode
{
    // given
    NSString *phone = @"+49(123)45678900";
    NSString *normalizedPhone = [phone copy];
    [ZMPhoneNumberValidator validateValue:&normalizedPhone error:nil];
    
    // when
    [self.sut prepareForRequestingPhoneVerificationCodeForLogin:phone];
    
    // then
    XCTAssertEqual(self.sut.currentPhase, ZMAuthenticationPhaseRequestPhoneVerificationCodeForLogin);
    XCTAssertEqualObjects(self.sut.loginPhoneNumberThatNeedsAValidationCode, normalizedPhone);
    XCTAssertNotEqualObjects(normalizedPhone, phone, @"Should not have changed original phone");
}

- (void)testThatItCanVerifyPhoneCodeForRegistrationAfterSettingRegistrationCode
{
    // given
    NSString *phone = @"+49(123)45678900";
    NSString *code = @"123456";
    ZMPhoneCredentials *credentials = [ZMPhoneCredentials credentialsWithPhoneNumber:phone verificationCode:code];
    
    // when
    [self.sut prepareForRegistrationPhoneVerificationWithCredentials:credentials];
    
    // then
    XCTAssertEqual(self.sut.currentPhase, ZMAuthenticationPhaseVerifyPhoneForRegistration);
    XCTAssertEqualObjects(self.sut.registrationPhoneValidationCredentials, credentials);
}

@end


@implementation ZMAuthenticationStatusTests (CompletionMethods)

- (void)testThatItTriesToLogInAfterCompletingEmailRegistration
{
    // given
    NSString *email = @"gfdgfgdfg@fds.sgf";
    NSString *password = @"#$4tewt343$";
    
    // expect
    XCTestExpectation *expectation = [self expectationWithDescription:@"notification"];
    ZM_WEAK(self);
    self.registrationCallback = ^(ZMUserSessionRegistrationNotification *note) {
        ZM_STRONG(self);
        XCTAssertNil(note.error);
        XCTAssertEqual(note.type, ZMRegistrationNotificationEmailVerificationDidSucceed);
        [expectation fulfill];
    };
    
    // when
    [self performPretendingUiMocIsSyncMoc:^{
        [self.sut prepareForRegistrationOfUser:[ZMCompleteRegistrationUser registrationUserWithEmail:email password:password]];
        [self.sut didCompleteRegistrationSuccessfully];
    }];
    
    // then
    XCTAssertEqual(self.sut.currentPhase, ZMAuthenticationPhaseLoginWithEmail);
    XCTAssertNil(self.sut.registrationUser);
    XCTAssertEqualObjects(self.sut.loginCredentials.email, email);
    XCTAssertEqualObjects(self.sut.loginCredentials.password, password);
    XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0.5]);
}

- (void)testThatItWaitsForEmailValidationWhenRegistrationFailsBecauseOfDuplicatedEmail
{
    // given
    NSString *email = @"gfdgfgdfg@fds.sgf";
    NSString *password = @"#$4tewt343$";
    
    // when
    [self.sut prepareForRegistrationOfUser:[ZMCompleteRegistrationUser registrationUserWithEmail:email password:password]];
    [self.sut didFailRegistrationWithDuplicatedEmail];
    
    // then
    XCTAssertEqual(self.sut.currentPhase, ZMAuthenticationPhaseLoginWithEmail);
    XCTAssertNil(self.sut.registrationUser);
    XCTAssertEqualObjects(self.sut.loginCredentials.email, email);
    XCTAssertEqualObjects(self.sut.loginCredentials.password, password);
}

- (void)testThatItResetsWhenRegistrationFails
{
    // expect
    NSError *error = [NSError userSessionErrorWithErrorCode:ZMUserSessionInvalidPhoneNumber userInfo:nil];
    XCTestExpectation *expectation = [self expectationWithDescription:@"notification"];
    ZM_WEAK(self);
    self.registrationCallback = ^(ZMUserSessionRegistrationNotification *note) {
        ZM_STRONG(self);
        XCTAssertEqual(note.error, error);
        XCTAssertEqual(note.type, ZMRegistrationNotificationRegistrationDidFail);
        [expectation fulfill];
    };
    
    // when
    [self.sut prepareForRegistrationOfUser:[ZMCompleteRegistrationUser registrationUserWithEmail:@"Foo@example.com" password:@"#@$123"]];
    [self.sut didFailRegistrationForOtherReasons:error];
    
    // then
    XCTAssertEqual(self.sut.currentPhase, ZMAuthenticationPhaseUnauthenticated);
    XCTAssertNil(self.sut.registrationUser);
    XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0]);
}

- (void)testThatItResetsWhenCompletingTheRequestForPhoneRegistrationCode
{
    // expect
    XCTestExpectation *expectation = [self expectationWithDescription:@"notification"];
    ZM_WEAK(self);
    self.registrationCallback = ^(ZMUserSessionRegistrationNotification *note) {
        ZM_STRONG(self);
        XCTAssertEqual(note.type, ZMRegistrationNotificationPhoneNumberVerificationCodeRequestDidSucceed);
        [expectation fulfill];
    };
    
    // when
    [self.sut prepareForRequestingPhoneVerificationCodeForRegistration:@"+4912345678"];
    [self.sut didCompleteRequestForPhoneRegistrationCodeSuccessfully];
    
    // then
    XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0]);
    XCTAssertEqual(self.sut.currentPhase, ZMAuthenticationPhaseUnauthenticated);
    XCTAssertNil(self.sut.registrationPhoneNumberThatNeedsAValidationCode);
}

- (void)testThatItRequestsALoginPhoneVerificationCodeWhenRequestingARegistrationPhoneCodeFailsBecauseOfDuplicatedEmail
{
    // given
    NSString *phone = @"+3912345678900";
    
    // when
    [self.sut prepareForRequestingPhoneVerificationCodeForRegistration:phone];
    [self.sut didFailRequestForPhoneRegistrationCode:[NSError userSessionErrorWithErrorCode:ZMUserSessionPhoneNumberIsAlreadyRegistered userInfo:nil]];
    
    // then
    XCTAssertEqual(self.sut.currentPhase, ZMAuthenticationPhaseRequestPhoneVerificationCodeForLogin);
    XCTAssertNil(self.sut.registrationPhoneNumberThatNeedsAValidationCode);
    XCTAssertEqualObjects(self.sut.loginPhoneNumberThatNeedsAValidationCode, phone);
}

- (void)testThatItResetsWhenFailingTheRequestForPhoneRegistrationCode
{
    // expect
    XCTestExpectation *expectation = [self expectationWithDescription:@"notification"];
    ZM_WEAK(self);
    self.registrationCallback = ^(ZMUserSessionRegistrationNotification *note) {
        ZM_STRONG(self);
        XCTAssertEqual(note.type, ZMRegistrationNotificationPhoneNumberVerificationCodeRequestDidFail);
        [expectation fulfill];
    };
    
    // when
    [self.sut prepareForRequestingPhoneVerificationCodeForRegistration:@"+4912345678"];
    [self.sut didFailRequestForPhoneRegistrationCode:[NSError userSessionErrorWithErrorCode:ZMUserSessionInvalidCredentials userInfo:nil]];
    
    // then
    XCTAssertEqual(self.sut.currentPhase, ZMAuthenticationPhaseUnauthenticated);
    XCTAssertNil(self.sut.registrationPhoneNumberThatNeedsAValidationCode);
    XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0]);

}

- (void)testThatItResetsWhenCompletingTheRequestForPhoneLoginCode
{
    // expect
    XCTestExpectation *expectation = [self expectationWithDescription:@"notification"];
    ZM_WEAK(self);
    self.authenticationCallback = ^(ZMUserSessionAuthenticationNotification *note) {
        ZM_STRONG(self);
        XCTAssertEqual(note.type, ZMAuthenticationNotificationLoginCodeRequestDidSucceed);
        [expectation fulfill];
    };
    
    // when
    [self.sut prepareForRequestingPhoneVerificationCodeForLogin:@"+4912345678"];
    [self.sut didCompleteRequestForLoginCodeSuccessfully];
    
    // then
    XCTAssertEqual(self.sut.currentPhase, ZMAuthenticationPhaseUnauthenticated);
    XCTAssertNil(self.sut.loginPhoneNumberThatNeedsAValidationCode);
    
    XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0]);
}

- (void)testThatItResetsWhenFailingTheRequestForPhoneLoginCode
{
    // expect
    XCTestExpectation *expectation = [self expectationWithDescription:@"notification"];
    NSError *error = [NSError userSessionErrorWithErrorCode:ZMUserSessionInvalidPhoneNumber userInfo:nil];
    ZM_WEAK(self);
    self.authenticationCallback = ^(ZMUserSessionAuthenticationNotification *note) {
        ZM_STRONG(self);
        XCTAssertEqual(note.type, ZMAuthenticationNotificationLoginCodeRequestDidFail);
        XCTAssertEqual(note.error, error);
        [expectation fulfill];
    };
    
    // when
    [self.sut prepareForRequestingPhoneVerificationCodeForLogin:@"+4912345678"];
    [self.sut didFailRequestForLoginCode:error];
    
    // then
    XCTAssertEqual(self.sut.currentPhase, ZMAuthenticationPhaseUnauthenticated);
    XCTAssertNil(self.sut.loginPhoneNumberThatNeedsAValidationCode);
    
    XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0]);
}

- (void)testThatItResetsWhenCompletingPhoneVerification
{
    // expect
    XCTestExpectation *expectation = [self expectationWithDescription:@"notification"];
    ZM_WEAK(self);
    self.registrationCallback = ^(ZMUserSessionRegistrationNotification *note) {
        ZM_STRONG(self);
        XCTAssertEqual(note.type, ZMRegistrationNotificationPhoneNumberVerificationDidSucceed);
        [expectation fulfill];
    };
    
    // when
    [self.sut prepareForRegistrationPhoneVerificationWithCredentials:[ZMPhoneCredentials credentialsWithPhoneNumber:@"+4912345678900" verificationCode:@"123456"]];
    [self.sut didCompletePhoneVerificationSuccessfully];
    
    // then
    XCTAssertEqual(self.sut.currentPhase, ZMAuthenticationPhaseUnauthenticated);
    XCTAssertNil(self.sut.loginPhoneNumberThatNeedsAValidationCode);
    
    XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0]);

}

- (void)testThatItResetsWhenFailingPhoneVerificationNotForDuplicatedPhone
{
    // expect
    NSError *error = [NSError userSessionErrorWithErrorCode:ZMUserSessionPhoneNumberIsAlreadyRegistered userInfo:nil];
    XCTestExpectation *expectation = [self expectationWithDescription:@"notification"];
    ZM_WEAK(self);
    self.registrationCallback = ^(ZMUserSessionRegistrationNotification *note) {
        ZM_STRONG(self);
        XCTAssertEqual(note.type, ZMRegistrationNotificationPhoneNumberVerificationDidFail);
        XCTAssertEqual(note.error, error);
        [expectation fulfill];
    };
    
    // when
    [self.sut prepareForRegistrationPhoneVerificationWithCredentials:[ZMPhoneCredentials credentialsWithPhoneNumber:@"+4912345678900" verificationCode:@"123456"]];
    [self.sut didFailPhoneVerificationForRegistration:error];
    
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
    self.authenticationCallback = ^(ZMUserSessionAuthenticationNotification *note) {
        ZM_STRONG(self);
        XCTAssertEqual(note.type, ZMAuthenticationNotificationAuthenticationDidFail);
        XCTAssertEqualObjects(note.error, [NSError userSessionErrorWithErrorCode:ZMUserSessionInvalidCredentials userInfo:nil]);
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
    
    // then
    XCTAssertEqual(self.sut.currentPhase, ZMAuthenticationPhaseUnauthenticated);
    XCTAssertNil(self.sut.loginCredentials);
    
    XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0]);
}

- (void)testThatItWaitsForEmailWhenFailingLoginBecauseOfPendingValidaton
{
    // expect
    XCTestExpectation *expectation = [self expectationWithDescription:@"notification"];
    ZM_WEAK(self);
    self.authenticationCallback = ^(ZMUserSessionAuthenticationNotification *note) {
        ZM_STRONG(self);
        XCTAssertEqual(note.type, ZMAuthenticationNotificationAuthenticationDidFail);
        XCTAssertEqualObjects(note.error, [NSError userSessionErrorWithErrorCode:ZMUserSessionAccountIsPendingActivation userInfo:nil]);
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
    [self.sut didFailLoginWithEmailBecausePendingValidation];
    
    // then
    XCTAssertEqual(self.sut.currentPhase, ZMAuthenticationPhaseWaitingForEmailVerification);
    XCTAssertEqualObjects(self.sut.loginCredentials, credentials);
    
    XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0]);
}

- (void)testThatItResetsWhenFailingPhoneLogin
{
    // expect
    XCTestExpectation *expectation = [self expectationWithDescription:@"notification"];
    ZM_WEAK(self);
    self.authenticationCallback = ^(ZMUserSessionAuthenticationNotification *note) {
        ZM_STRONG(self);
        XCTAssertEqual(note.type, ZMAuthenticationNotificationAuthenticationDidFail);
        XCTAssertEqualObjects(note.error, [NSError userSessionErrorWithErrorCode:ZMUserSessionInvalidCredentials userInfo:nil]);
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
    self.authenticationCallback = ^(ZMUserSessionAuthenticationNotification *note) {
        ZM_STRONG(self);
        XCTAssertEqual(note.type, ZMAuthenticationNotificationAuthenticationDidFail);
        XCTAssertEqualObjects(note.error, [NSError userSessionErrorWithErrorCode:ZMUserSessionNetworkError userInfo:nil]);
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



@implementation ZMAuthenticationStatusTests (CookieLabel)

- (void)testThatItReturnsTheSameCookieLabel
{
    // when
    NSString *cookieLabel1 = [self.sut cookieLabel];
    NSString *cookieLabel2= [self.sut cookieLabel];
    
    // then
    XCTAssertNotNil(cookieLabel1);
    XCTAssertEqualObjects(cookieLabel1, cookieLabel2);

}

@end
