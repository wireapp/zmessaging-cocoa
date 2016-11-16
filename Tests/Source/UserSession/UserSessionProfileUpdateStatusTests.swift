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


import XCTest
@testable import zmessaging
import ZMUtilities

class UserProfileUpdateStatusTests : MessagingTest {
    
    var sut : UserProfileUpdateStatus! = nil
    
    /// Number of time the new request callback was invoked
    var newRequestCallbackCount = 0
    
    override func setUp() {
        super.setUp()
        self.newRequestCallbackCount = 0
        self.sut = UserProfileUpdateStatus(managedObjectContext: self.uiMOC, newRequestCallback: { self.newRequestCallbackCount += 1 })
        // TODO MARCO: observing
    }
    
    override func tearDown() {
        self.sut = nil
        super.tearDown()
    }
}

// MARK: - Set email and password
extension UserProfileUpdateStatusTests {
    
    func testThatItIsNotUpdatingEmail() {
        XCTAssertFalse(sut.currentlySettingEmail)
        XCTAssertFalse(sut.currentlySettingPassword)
        XCTAssertNil(self.sut.emailCredentials())
    }
    
    func testThatItPreparesForEmailAndPasswordChangeIfTheSelfUserHasNoEmail() {
        
        // GIVEN
        let selfUser = ZMUser.selfUser(in: self.uiMOC)
        XCTAssertNil(selfUser.emailAddress)
        let credentials = ZMEmailCredentials(email: "foo@example.com", password: "%$#@11111")
        
        // WHEN
        do {
            try self.sut.requestSettingEmailAndPassword(credentials: credentials)
        } catch {
            XCTFail()
            return
        }
        
        // THEN
        XCTAssertFalse(self.sut.currentlySettingEmail)
        XCTAssertTrue(self.sut.currentlySettingPassword)
        XCTAssertNil(self.sut.emailCredentials())

    }
    
    func testThatItReturnsErrorWhenPreparingForEmailAndPasswordChangeAndUserUserHasEmail() {
        
        // GIVEN
        let selfUser = ZMUser.selfUser(in: self.uiMOC)
        selfUser.emailAddress = "my@fo.example.com"
        let credentials = ZMEmailCredentials(email: "foo@example.com", password: "%$#@11111")
        
        // WHEN
        do {
            try self.sut.requestSettingEmailAndPassword(credentials: credentials)
            XCTFail("Should have thrown")
        } catch {
            return
        }
    }
    
    func testThatItNotifiesOfNewRequestWhenPreparesForEmailAndPasswordChange() {
        
        // GIVEN
        let credentials = ZMEmailCredentials(email: "foo@example.com", password: "%$#@11111")
        XCTAssertEqual(self.newRequestCallbackCount, 0)
        
        // WHEN
        try? self.sut.requestSettingEmailAndPassword(credentials: credentials)
        
        // THEN
        XCTAssertEqual(self.newRequestCallbackCount, 1)
    }
    
    func testThatItCanCancelSettingEmailAndPassword() {
        
        // GIVEN
        let credentials = ZMEmailCredentials(email: "foo@example.com", password: "%$#@11111")
        try? self.sut.requestSettingEmailAndPassword(credentials: credentials)
        
        // WHEN
        self.sut.cancelSettingEmailAndPassword()
        
        // THEN
        XCTAssertFalse(sut.currentlySettingEmail)
        XCTAssertFalse(sut.currentlySettingPassword)
        XCTAssertNil(self.sut.emailCredentials())
    }
    
    func testThatItNeedsToSetEmailAfterSuccessfullySettingPassword() {
        
        // GIVEN
        let credentials = ZMEmailCredentials(email: "foo@example.com", password: "%$#@11111")
        try? self.sut.requestSettingEmailAndPassword(credentials: credentials)
        
        // WHEN
        self.sut.didUpdatePasswordSuccessfully()
        
        // THEN
        XCTAssertTrue(sut.currentlySettingEmail)
        XCTAssertFalse(sut.currentlySettingPassword)
        XCTAssertNil(self.sut.emailCredentials())
    }
    
    func testThatItCompletesAfterSuccessfullySettingPasswordAndEmail() {
        
        // GIVEN
        let credentials = ZMEmailCredentials(email: "foo@example.com", password: "%$#@11111")
        try? self.sut.requestSettingEmailAndPassword(credentials: credentials)

        
        // WHEN
        self.sut.didUpdatePasswordSuccessfully()
        self.sut.didUpdateEmailSuccessfully()
        
        // THEN
        XCTAssertFalse(sut.currentlySettingEmail)
        XCTAssertFalse(sut.currentlySettingPassword)
        XCTAssertEqual(self.sut.emailCredentials(), credentials)
    }
    
    func testThatItIsNotSettingEmailAnymoreAsSoonAsTheSelfUserHasEmail() {
        
        // GIVEN
        let credentials = ZMEmailCredentials(email: "foo@example.com", password: "%$#@11111")
        try? self.sut.requestSettingEmailAndPassword(credentials: credentials)

        
        // WHEN
        let selfUser = ZMUser.selfUser(in: self.uiMOC)
        selfUser.emailAddress = "bar@example.com"
        
        // THEN
        XCTAssertFalse(self.sut.currentlySettingEmail)
        XCTAssertFalse(self.sut.currentlySettingPassword)
    }
    
    func testThatItIsNotSettingPasswordAnymoreAsSoonAsTheSelfUserHasEmail() {
        
        // GIVEN
        let credentials = ZMEmailCredentials(email: "foo@example.com", password: "%$#@11111")
        try? self.sut.requestSettingEmailAndPassword(credentials: credentials)
        self.sut.didUpdatePasswordSuccessfully()

        // WHEN
        let selfUser = ZMUser.selfUser(in: self.uiMOC)
        selfUser.emailAddress = "bar@example.com"
        
        // THEN
        XCTAssertFalse(self.sut.currentlySettingEmail)
        XCTAssertFalse(self.sut.currentlySettingPassword)
    }
    
    func testThatItIsNotSettingEmailAndPasswordAnymoreIfItFailsToUpdatePassword() {
        
        // GIVEN
        let credentials = ZMEmailCredentials(email: "foo@example.com", password: "%$#@11111")
        try? self.sut.requestSettingEmailAndPassword(credentials: credentials)
        
        // WHEN
        self.sut.didFailPasswordUpdate()
        
        // THEN
        XCTAssertFalse(self.sut.currentlySettingEmail)
        XCTAssertFalse(self.sut.currentlySettingPassword)
        XCTAssertNil(self.sut.emailCredentials())
    }
    
    func testThatItIsNotSettingEmailAnymoreIfItFailsToUpdateEmail() {
        
        // GIVEN
        let credentials = ZMEmailCredentials(email: "foo@example.com", password: "%$#@11111")
        try? self.sut.requestSettingEmailAndPassword(credentials: credentials)
        
        // WHEN
        self.sut.didUpdateEmailSuccessfully()
        self.sut.didFailEmailUpdate(error: NSError())
        
        // THEN
        XCTAssertFalse(self.sut.currentlySettingEmail)
        XCTAssertFalse(self.sut.currentlySettingPassword)
        XCTAssertNil(self.sut.emailCredentials())
    }
}
 /*
 TODO MARCO
 @import ZMUtilities;
 
 #import "MessagingTest.h"
 #import "NSError+ZMUserSessionInternal.h"
 
 @interface ZMUserProfileUpdateStatusTests : MessagingTest
 
 @property (nonatomic) ZMUserProfileUpdateStatus *sut;
 
 @property (nonatomic) id profileObserverToken;
 @property (nonatomic, copy) void(^profileCallback)(ZMUserProfileUpdateNotification *note);
 @property (nonatomic) BOOL ignoreNotifications;
 
 @end
 
 @implementation ZMUserProfileUpdateStatusTests
 
 - (void)setUp
 {
 [super setUp];
 self.sut = [[ZMUserProfileUpdateStatus alloc] initWithManagedObjectContext:self.uiMOC];
 self.ignoreNotifications = NO;
 
 ZM_WEAK(self);
 // If a test fires any notification and it's not listening for it, this will fail
 self.profileCallback = ^(id note ZM_UNUSED){
 ZM_STRONG(self);
 if (self.ignoreNotifications) {
 return;
 }
 XCTFail(@"Unexpected notification: %@", note);
 };
 
 self.profileObserverToken = [ZMUserProfileUpdateNotification addObserverWithBlock:^(ZMUserProfileUpdateNotification *note) {
 self.profileCallback(note);
 }];
 }
 
 - (void)tearDown
 {
 XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0]);
 
 self.sut = nil;
 [super tearDown];
 
 [ZMUserProfileUpdateNotification removeObserver:self.profileObserverToken];
 self.profileObserverToken = nil;
 }
 
 - (void)testThatItStartsIdle
 {
 XCTAssertEqual(self.sut.currentPhase, ZMUserProfilePhaseIdle);
 }
 
 @end
 
 
 
 @implementation ZMUserProfileUpdateStatusTests (PrepareMethods)
 
 - (void)testThatItPreparesForRequestingPhoneVerificationCodeForRegistraiton
 {
 // given
 NSString *phoneNumber = @"+49-123-4567-890";
 NSString *normalizedPhoneNumber = [phoneNumber copy];
 [ZMPhoneNumberValidator validateValue:&normalizedPhoneNumber error:nil];
 
 // when
 [self.sut prepareForRequestingPhoneVerificationCodeForRegistration:phoneNumber];
 
 // then
 XCTAssertEqual(self.sut.currentPhase, ZMUserProfilePhaseRequestPhoneVerificationCode);
 XCTAssertEqualObjects(self.sut.profilePhoneNumberThatNeedsAValidationCode, normalizedPhoneNumber);
 XCTAssertNotEqualObjects(phoneNumber, normalizedPhoneNumber, @"Should not have changed original");
 }
 
 - (void)testThatItPreparesForPhoneChangeWithCredentials
 {
 // given
 ZMPhoneCredentials *credentials = [ZMPhoneCredentials credentialsWithPhoneNumber:@"+4912345678900" verificationCode:@"654321"];
 
 // when
 [self.sut prepareForPhoneChangeWithCredentials:credentials];
 
 // then
 XCTAssertEqual(self.sut.currentPhase, ZMUserProfilePhaseChangePhone);
 XCTAssertEqualObjects(self.sut.phoneCredentialsToUpdate, credentials);
 }
 
 @end
 
 
 
 @implementation ZMUserProfileUpdateStatusTests (CompletionMethods)
 
 - (void)testThatItGoesIdleAfterItDidRequestPhoneVerificationCodeSuccessfully
 {
 // given
 NSString *phoneNumber = @"+4912345678900";
 
 // expect
 XCTestExpectation *expectation = [self expectationWithDescription:@"Notification"];
 ZM_WEAK(self);
 self.profileCallback = ^(ZMUserProfileUpdateNotification *note) {
 ZM_STRONG(self);
 XCTAssertEqual(note.type, ZMUserProfileNotificationPhoneNumberVerificationCodeRequestDidSucceed);
 [expectation fulfill];
 };
 
 // when
 [self.sut prepareForRequestingPhoneVerificationCodeForRegistration:phoneNumber];
 [self.sut didRequestPhoneVerificationCodeSuccessfully];
 
 // then
 XCTAssertEqual(self.sut.currentPhase, ZMUserProfilePhaseIdle);
 XCTAssertNil(self.sut.profilePhoneNumberThatNeedsAValidationCode);
 XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0]);
 
 }
 
 - (void)testThatItGoesIdleAfterItDidFailPhoneVerificationCodeRequest
 {
 // given
 NSString *phoneNumber = @"+4912345678900";
 
 // expect
 XCTestExpectation *expectation = [self expectationWithDescription:@"Notification"];
 ZM_WEAK(self);
 self.profileCallback = ^(ZMUserProfileUpdateNotification *note) {
 ZM_STRONG(self);
 XCTAssertEqual(note.type, ZMUserProfileNotificationPhoneNumberVerificationCodeRequestDidFail);
 [expectation fulfill];
 };
 
 // when
 [self.sut prepareForRequestingPhoneVerificationCodeForRegistration:phoneNumber];
 [self.sut didFailPhoneVerificationCodeRequestWithError:nil];
 
 // then
 XCTAssertEqual(self.sut.currentPhase, ZMUserProfilePhaseIdle);
 XCTAssertNil(self.sut.profilePhoneNumberThatNeedsAValidationCode);
 
 XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0]);
 
 }
 
 - (void)testThatItGoesIdleAfterItDidVerifyPhoneSuccessfully
 {
 // given
 ZMPhoneCredentials *credentials = [ZMPhoneCredentials credentialsWithPhoneNumber:@"+4912345678900" verificationCode:@"654321"];
 
 // when
 [self.sut prepareForPhoneChangeWithCredentials:credentials];
 [self.sut didVerifyPhoneSuccessfully];
 
 // then
 XCTAssertEqual(self.sut.currentPhase, ZMUserProfilePhaseIdle);
 XCTAssertNil(self.sut.phoneCredentialsToUpdate);
 }
 
 - (void)testThatItGoesIdleAfterItDidFailPhoneVerification
 {
 // given
 ZMPhoneCredentials *credentials = [ZMPhoneCredentials credentialsWithPhoneNumber:@"+4912345678900" verificationCode:@"654321"];
 
 // expect
 NSError *error = [NSError userSessionErrorWithErrorCode:ZMUserSessionPhoneNumberIsAlreadyRegistered userInfo:nil];
 XCTestExpectation *expectation = [self expectationWithDescription:@"Notification"];
 ZM_WEAK(self);
 self.profileCallback = ^(ZMUserProfileUpdateNotification *note) {
 ZM_STRONG(self);
 XCTAssertEqual(note.type, ZMUserProfileNotificationPhoneNumberVerificationDidFail);
 XCTAssertEqual(note.error, error);
 [expectation fulfill];
 };
 
 // when
 [self.sut prepareForPhoneChangeWithCredentials:credentials];
 [self.sut didFailPhoneVerification:error];
 
 // then
 XCTAssertEqual(self.sut.currentPhase, ZMUserProfilePhaseIdle);
 XCTAssertNil(self.sut.phoneCredentialsToUpdate);
 
 XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0]);
 
 }
 
 - (void)testThatItChangesTheEmailAfterUpdatingThePasswordSuccessfully
 {
 // given
 ZMEmailCredentials *credentials = [ZMEmailCredentials credentialsWithEmail:@"foo@foo.bar" password:@"%$#%1233"];
 
 // when
 [self.sut prepareForEmailAndPasswordChangeWithCredentials:credentials];
 [self.sut didUpdatePasswordSuccessfully];
 
 // then
 XCTAssertEqual(self.sut.currentPhase, ZMUserProfilePhaseChangeEmail);
 XCTAssertEqualObjects(self.sut.emailToUpdate, credentials.email);
 XCTAssertNil(self.sut.passwordToUpdate);
 }
 
 - (void)testThatItGoesIdleAfterItDidFailPasswordUpdate
 {
 // given
 ZMEmailCredentials *credentials = [ZMEmailCredentials credentialsWithEmail:@"foo@foo.bar" password:@"%$#%1233"];
 
 // expect
 XCTestExpectation *expectation = [self expectationWithDescription:@"Notification"];
 ZM_WEAK(self);
 self.profileCallback = ^(ZMUserProfileUpdateNotification *note) {
 ZM_STRONG(self);
 XCTAssertEqual(note.type, ZMUserProfileNotificationPasswordUpdateDidFail);
 [expectation fulfill];
 };
 
 // when
 [self.sut prepareForEmailAndPasswordChangeWithCredentials:credentials];
 [self.sut didFailPasswordUpdate];
 
 // then
 XCTAssertEqual(self.sut.currentPhase, ZMUserProfilePhaseIdle);
 XCTAssertNil(self.sut.emailToUpdate);
 XCTAssertNil(self.sut.passwordToUpdate);
 
 XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0]);
 
 }
 
 - (void)testThatItGoesIdleAfterItDidUpdateEmailSuccessfully
 {
 // given
 ZMEmailCredentials *credentials = [ZMEmailCredentials credentialsWithEmail:@"foo@foo.bar" password:@"%$#%1233"];
 
 // expect
 XCTestExpectation *expectation = [self expectationWithDescription:@"Notification"];
 ZM_WEAK(self);
 self.profileCallback = ^(ZMUserProfileUpdateNotification *note) {
 ZM_STRONG(self);
 XCTAssertEqual(note.type, ZMUserProfileNotificationEmailDidSendVerification);
 XCTAssertNil(note.error);
 [expectation fulfill];
 };
 
 // when
 [self.sut prepareForEmailAndPasswordChangeWithCredentials:credentials];
 [self.sut didUpdatePasswordSuccessfully];
 [self.sut didUpdateEmailSuccessfully];
 
 // then
 XCTAssertEqual(self.sut.currentPhase, ZMUserProfilePhaseIdle);
 XCTAssertNil(self.sut.emailToUpdate);
 XCTAssertNil(self.sut.passwordToUpdate);
 
 XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0]);
 }
 
 - (void)testThatItGoesIdleAfterItDidFailEmailUpdate
 {
 // given
 ZMEmailCredentials *credentials = [ZMEmailCredentials credentialsWithEmail:@"foo@foo.bar" password:@"%$#%1233"];
 NSError *error = [NSError userSessionErrorWithErrorCode:ZMUserSessionUnkownError userInfo:nil];
 
 // expect
 XCTestExpectation *expectation = [self expectationWithDescription:@"Notification"];
 ZM_WEAK(self);
 self.profileCallback = ^(ZMUserProfileUpdateNotification *note) {
 ZM_STRONG(self);
 XCTAssertEqual(note.error, error);
 XCTAssertEqual(note.type, ZMUserProfileNotificationEmailUpdateDidFail);
 [expectation fulfill];
 };
 
 // when
 [self.sut prepareForEmailAndPasswordChangeWithCredentials:credentials];
 [self.sut didUpdatePasswordSuccessfully];
 [self.sut didFailEmailUpdate:error];
 
 // then
 XCTAssertEqual(self.sut.currentPhase, ZMUserProfilePhaseIdle);
 XCTAssertNil(self.sut.emailToUpdate);
 XCTAssertNil(self.sut.passwordToUpdate);
 
 XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0]);
 
 }
 
 
 @end
 
 
 @implementation ZMUserProfileUpdateStatusTests (CredentialProvider)
 
 - (void)testThatItDoesNotReturnCredentialsIfOnlyPasswordIsVerified
 {
 // given
 self.ignoreNotifications = YES;
 
 ZMEmailCredentials *credentials = [ZMEmailCredentials credentialsWithEmail:@"jon@example.com" password:@"12345678"];
 [self.sut prepareForEmailAndPasswordChangeWithCredentials:credentials];
 
 // when
 [self.sut didUpdatePasswordSuccessfully];
 
 // then
 XCTAssertNil(self.sut.emailCredentials);
 }
 
 
 - (void)testThatItDoesNotReturnCredentialsIfOnlyEmailIsVerified
 {
 // given
 self.ignoreNotifications = YES;
 
 ZMEmailCredentials *credentials = [ZMEmailCredentials credentialsWithEmail:@"jon@example.com" password:@"12345678"];
 [self.sut prepareForEmailAndPasswordChangeWithCredentials:credentials];
 
 // when
 [self.sut didUpdateEmailSuccessfully];
 
 // then
 XCTAssertNil(self.sut.emailCredentials);
 }
 
 
 - (void)testThatItReturnsCredentialsIfEmailAndPasswordAreVerified
 {
 // given
 self.ignoreNotifications = YES;
 
 ZMEmailCredentials *credentials = [ZMEmailCredentials credentialsWithEmail:@"jon@example.com" password:@"12345678"];
 [self.sut prepareForEmailAndPasswordChangeWithCredentials:credentials];
 
 // when
 [self.sut didUpdatePasswordSuccessfully];
 [self.sut didUpdateEmailSuccessfully];
 
 // then
 XCTAssertEqual(self.sut.emailCredentials, credentials);
 }
 
 - (void)testThatItDeletesCredentials
 {
 // given
 self.ignoreNotifications = YES;
 
 ZMEmailCredentials *credentials = [ZMEmailCredentials credentialsWithEmail:@"jon@example.com" password:@"12345678"];
 [self.sut prepareForEmailAndPasswordChangeWithCredentials:credentials];
 
 // when
 [self.sut credentialsMayBeCleared];
 [self.sut didUpdatePasswordSuccessfully];
 [self.sut didUpdateEmailSuccessfully];
 
 // then
 XCTAssertNil(self.sut.emailCredentials);
 }
 
 
 @end
 
 */
