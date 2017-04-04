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


#import "ZMUserSessionTestsBase.h"
#import "ZMUserSession+Registration.h"
@import WireMockTransport;

static NSString *const ValidPhoneNumber = @"+491234567890";
static NSString *const ShortPhoneNumber = @"+491";
static NSString *const LongPhoneNumber = @"+4912345678901234567890";
static NSString *const ValidPassword = @"pA$$W0Rd";
static NSString *const ShortPassword = @"pa";
static NSString *const LongPassword =
@"ppppppppppppaaaaaaaaaaassssssssswwwwwwwwwwoooooooooooorrrrrrrrrddddddddddddddd"
"ppppppppppppaaaaaaaaaaassssssssswwwwwwwwwwoooooooooooorrrrrrrrrddddddddddddddd"
"ppppppppppppaaaaaaaaaaassssssssswwwwwwwwwwoooooooooooorrrrrrrrrddddddddddddddd"
"ppppppppppppaaaaaaaaaaassssssssswwwwwwwwwwoooooooooooorrrrrrrrrddddddddddddddd";
static NSString *const ValidPhoneCode = @"123456";
static NSString *const ShortPhoneCode = @"1";
static NSString *const LongPhoneCode = @"123456789012345678901234567890";
static NSString *const ValidEmail = @"foo77@example.com";
static NSString *const InvitationCode = @"90askdpaosdkaso";


@interface ZMUserSession(RegistrationTests)

+ (BOOL)finallyValidatePhoneNumber:(NSString **)ioPhoneNumber environment:(ZMBackendEnvironment *)env error:(NSError **)outError;

@end

@interface ZMUserSessionRegistrationTests : ZMUserSessionTestsBase
@end



@implementation ZMUserSessionRegistrationTests

- (void)setUp
{
    [super setUp];
}

@end



@implementation ZMUserSessionRegistrationTests (PhoneRegistration)


- (void)testThatItSetsTheRegistrationPhoneNumberAndCode
{
    // expect
    [[self.requestAvailableNotification expect] notifyNewRequestsAvailable:OCMOCK_ANY]; // FIXME
    [[self.transportSession stub] attemptToEnqueueSyncRequestWithGenerator:OCMOCK_ANY];
    
    // when
    ZMCompleteRegistrationUser *regUser = [ZMCompleteRegistrationUser registrationUserWithPhoneNumber:ValidPhoneNumber phoneVerificationCode:ValidPhoneCode];
    [self.sut registerSelfUser:regUser];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(self.sut.authenticationStatus.registrationUser, regUser);
    
    // after
    [self.requestAvailableNotification verify];
}

- (void)testThatItCopiesThePhoneRegistrationUserDataToTheSelfUser
{
    // when
    ZMCompleteRegistrationUser *regUser = [ZMCompleteRegistrationUser registrationUserWithPhoneNumber:ValidPhoneNumber phoneVerificationCode:ValidPhoneCode];
    regUser.name = @"The name";
    regUser.accentColorValue = ZMAccentColorBrightOrange;
    regUser.originalProfileImageData = [@"foo" dataUsingEncoding:NSUTF8StringEncoding];
    [self.sut registerSelfUser:regUser];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    ZMUser *selfUser = [ZMUser selfUserInUserSession:self.sut];
    XCTAssertEqualObjects(selfUser.phoneNumber, regUser.phoneNumber);
    XCTAssertEqualObjects(selfUser.name, regUser.name);
    XCTAssertEqual(selfUser.accentColorValue, regUser.accentColorValue);
    XCTAssertEqualObjects(selfUser.originalProfileImageData, regUser.originalProfileImageData);
}

- (void)testThatItFiresRegistrationFailForShortCode
{
    // expect
    [[self.transportSession stub] attemptToEnqueueSyncRequestWithGenerator:OCMOCK_ANY];
    [[(id) self.registrationObserver expect] registrationDidFail:OCMOCK_ANY];
    
    // when
    ZMCompleteRegistrationUser *regUser = [ZMCompleteRegistrationUser registrationUserWithPhoneNumber:ValidPhoneNumber phoneVerificationCode:ShortPhoneCode];
    [self.sut registerSelfUser:regUser];
}

- (void)testThatItFiresRegistrationFailForLongCode
{
    // expect
    [[self.transportSession stub] attemptToEnqueueSyncRequestWithGenerator:OCMOCK_ANY];
    [[(id) self.registrationObserver expect] registrationDidFail:OCMOCK_ANY];
    
    // when
    ZMCompleteRegistrationUser *regUser = [ZMCompleteRegistrationUser registrationUserWithPhoneNumber:ValidPhoneNumber phoneVerificationCode:LongPhoneCode];
    [self.sut registerSelfUser:regUser];
}

- (void)testThatItDoesNotFireRegistrationFailForAValidCode
{
    // expect
    [[self.transportSession stub] attemptToEnqueueSyncRequestWithGenerator:OCMOCK_ANY];
    [[(id) self.registrationObserver reject] registrationDidFail:OCMOCK_ANY];
    
    
    // when
    ZMCompleteRegistrationUser *regUser = [ZMCompleteRegistrationUser registrationUserWithPhoneNumber:ValidPhoneNumber phoneVerificationCode:ValidPhoneCode];
    [self.sut registerSelfUser:regUser];
}


- (void)testThatIfItTriesToRequestARegistrationPhoneValidationCodeForAPhoneThatExistsItDoesALoginInstead
{
    // ginve
    NSString *phone = @"+3912345678900";
    
    // expect
    [[self.requestAvailableNotification expect] notifyNewRequestsAvailable:OCMOCK_ANY];
    [[self.transportSession stub] attemptToEnqueueSyncRequestWithGenerator:OCMOCK_ANY];
    
    // when
    [self.sut requestPhoneVerificationCodeForRegistration:phone];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // and when
    [self.sut.authenticationStatus didFailRequestForPhoneRegistrationCode:[NSError userSessionErrorWithErrorCode:ZMUserSessionPhoneNumberIsAlreadyRegistered userInfo:nil]];
    
    // then
    XCTAssertEqual(self.sut.authenticationStatus.loginPhoneNumberThatNeedsAValidationCode, phone);
    
    // after
    [self.requestAvailableNotification verify];
}

- (void)testThatIfItTriesToRequestARegistrationPhoneValidationCodeForAPhoneThatExistsAndDoesALoginInstead_ItNotifiesIfItItFails
{
    // ginve
    NSString *phone = @"+3912345678900";
    
    // expect
    [[self.requestAvailableNotification expect] notifyNewRequestsAvailable:OCMOCK_ANY];
    [[self.transportSession stub] attemptToEnqueueSyncRequestWithGenerator:OCMOCK_ANY];
    [[(id) self.registrationObserver expect] registrationDidFail:OCMOCK_ANY];
    
    // when
    [self.sut requestPhoneVerificationCodeForRegistration:phone];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // and when
    [self.sut.authenticationStatus didFailRequestForPhoneRegistrationCode:[NSError userSessionErrorWithErrorCode:ZMUserSessionPhoneNumberIsAlreadyRegistered userInfo:nil]];
    [self.sut.authenticationStatus prepareForLoginWithCredentials:[ZMPhoneCredentials credentialsWithPhoneNumber:phone verificationCode:self.mockTransportSession.invalidPhoneVerificationCode]];
    [self.sut.authenticationStatus didFailLoginWithPhone:YES];
    
    // after
    [self.requestAvailableNotification verify];
}

@end


@implementation ZMUserSessionRegistrationTests (PhoneValidationCodeRequest)

- (void)testThatItSetThePhoneNumberToVerifyAndNotifiesOfANewRequestWhenRequestingAVerificationCode
{
    // expect
    [[self.requestAvailableNotification expect] notifyNewRequestsAvailable:OCMOCK_ANY]; // FIXME
    
    // when
    [self.sut requestPhoneVerificationCodeForRegistration:ValidPhoneNumber];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqualObjects(self.sut.authenticationStatus.registrationPhoneNumberThatNeedsAValidationCode, ValidPhoneNumber);
    XCTAssertEqual(self.sut.authenticationStatus.currentPhase, ZMAuthenticationPhaseRequestPhoneVerificationCodeForRegistration);
    [self.requestAvailableNotification verify];
}

- (void)testThatRequestingToVerifyTheCodeStoresPhoneNumberAndPhoneNumberVerificationCodeAndNotifiesOfANewRequest
{
    // expect
    [[self.requestAvailableNotification expect] notifyNewRequestsAvailable:OCMOCK_ANY]; // FIXME
    
    // when
    [self.sut verifyPhoneNumberForRegistration:ValidPhoneNumber verificationCode:ValidPhoneCode];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqualObjects(self.sut.authenticationStatus.registrationPhoneValidationCredentials.phoneNumber, ValidPhoneNumber);
    XCTAssertEqualObjects(self.sut.authenticationStatus.registrationPhoneValidationCredentials.phoneNumberVerificationCode, ValidPhoneCode);
    XCTAssertEqual(self.sut.authenticationStatus.currentPhase, ZMAuthenticationPhaseVerifyPhoneForRegistration);
    [self.requestAvailableNotification verify];
}

@end


@implementation ZMUserSessionRegistrationTests (EmailRegistration)

- (void)testThatItSetsTheRegistrationPassword
{
    // expect
    [[self.requestAvailableNotification expect] notifyNewRequestsAvailable:OCMOCK_ANY];
    [[self.transportSession stub] attemptToEnqueueSyncRequestWithGenerator:OCMOCK_ANY];
    
    // when
    ZMCompleteRegistrationUser *regUser = [ZMCompleteRegistrationUser registrationUserWithEmail:ValidEmail password:ValidPassword];
    [self.sut registerSelfUser:regUser];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqualObjects(self.sut.authenticationStatus.registrationUser.password, ValidPassword);
    XCTAssertEqual(self.sut.authenticationStatus.currentPhase, ZMAuthenticationPhaseRegisterWithEmail);
    
    // after
    [self.requestAvailableNotification verify];
}

- (void)testThatItCopiesTheRegistrationUserDataToTheSelfUser
{
    // when
    ZMCompleteRegistrationUser *regUser = [ZMCompleteRegistrationUser registrationUserWithEmail:ValidEmail password:ValidPassword];
    regUser.name = @"The name";
    regUser.accentColorValue = ZMAccentColorBrightOrange;
    regUser.originalProfileImageData = [@"foo" dataUsingEncoding:NSUTF8StringEncoding];
    [self.sut registerSelfUser:regUser];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    ZMUser *selfUser = [ZMUser selfUserInUserSession:self.sut];
    XCTAssertEqualObjects(selfUser.emailAddress, regUser.emailAddress);
    XCTAssertEqualObjects(selfUser.name, regUser.name);
    XCTAssertEqual(selfUser.accentColorValue, regUser.accentColorValue);
    XCTAssertEqualObjects(selfUser.originalProfileImageData, regUser.originalProfileImageData);
}

- (void)testThatWhenCancellingTheWaitForAutomaticLoginWeInvalidateCredentials
{
    // given
    ZMCredentials *credentials = [ZMEmailCredentials credentialsWithEmail:@"foo@foo.bar" password:ValidPassword];
    [self.sut.authenticationStatus prepareForLoginWithCredentials:credentials];
    
    // when
    [self.sut cancelWaitForEmailVerification];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertNil(self.sut.authenticationStatus.loginCredentials);
    XCTAssertEqual(self.sut.authenticationStatus.currentPhase, ZMAuthenticationPhaseUnauthenticated);
}

- (void)testThatItFiresRegistrationFailForShortPassword
{
    // expect
    [[self.transportSession stub] attemptToEnqueueSyncRequestWithGenerator:OCMOCK_ANY];
    [[(id) self.registrationObserver expect] registrationDidFail:OCMOCK_ANY];
    
    // when
    ZMCompleteRegistrationUser *regUser = [ZMCompleteRegistrationUser registrationUserWithEmail:ValidEmail password:ShortPassword];
    [self.sut registerSelfUser:regUser];
}

- (void)testThatItFiresRegistrationFailForLongPassword
{
    // expect
    [[self.transportSession stub] attemptToEnqueueSyncRequestWithGenerator:OCMOCK_ANY];
    [[(id) self.registrationObserver expect] registrationDidFail:OCMOCK_ANY];
    
    // when
    ZMCompleteRegistrationUser *regUser = [ZMCompleteRegistrationUser registrationUserWithEmail:ValidEmail password:LongPassword];
    [self.sut registerSelfUser:regUser];
}

- (void)testThatItDoesNotFireRegistrationFailForAValidPassword
{
    // expect
    [[self.transportSession stub] attemptToEnqueueSyncRequestWithGenerator:OCMOCK_ANY];
    [[(id) self.registrationObserver reject] registrationDidFail:OCMOCK_ANY];
    
    // when
    ZMCompleteRegistrationUser *regUser = [ZMCompleteRegistrationUser registrationUserWithEmail:ValidEmail password:ValidPassword];
    [self.sut registerSelfUser:regUser];
}


@end

@implementation ZMUserSessionRegistrationTests (InvitationRegistration)

- (void)testThatItSetsTheRegistrationPhoneNumberAndCodeAndInvitationCode
{
    // expect
    [[self.requestAvailableNotification expect] notifyNewRequestsAvailable:OCMOCK_ANY];
    [[self.transportSession stub] attemptToEnqueueSyncRequestWithGenerator:OCMOCK_ANY];
    
    // when
    ZMCompleteRegistrationUser *regUser = [ZMCompleteRegistrationUser registrationUserWithPhoneNumber:ValidPhoneNumber invitationCode:InvitationCode];
    [self.sut registerSelfUser:regUser];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqualObjects(self.sut.authenticationStatus.registrationUser.invitationCode, InvitationCode);
    XCTAssertEqual(self.sut.authenticationStatus.registrationUser, regUser);
    XCTAssertEqual(self.sut.authenticationStatus.currentPhase, ZMAuthenticationPhaseRegisterWithPhone);
    
    // after
    [self.requestAvailableNotification verify];
}

- (void)testThatItSetsTheRegistrationPasswordAndInvitationCode
{
    // expect
    [[self.requestAvailableNotification expect] notifyNewRequestsAvailable:OCMOCK_ANY];
    [[self.transportSession stub] attemptToEnqueueSyncRequestWithGenerator:OCMOCK_ANY];
    
    // when
    ZMCompleteRegistrationUser *regUser = [ZMCompleteRegistrationUser registrationUserWithEmail:ValidEmail password:ValidPassword invitationCode:InvitationCode];
    [self.sut registerSelfUser:regUser];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqualObjects(self.sut.authenticationStatus.registrationUser.invitationCode, InvitationCode);
    XCTAssertEqualObjects(self.sut.authenticationStatus.registrationUser.password, ValidPassword);
    XCTAssertEqual(self.sut.authenticationStatus.currentPhase, ZMAuthenticationPhaseRegisterWithEmail);
    
    // after
    [self.requestAvailableNotification verify];
}

- (void)testThatItFiresRegistrationFailForPhoneWithoutInvitationCode
{
    // expect
    [[self.transportSession stub] attemptToEnqueueSyncRequestWithGenerator:OCMOCK_ANY];
    [[(id) self.registrationObserver expect] registrationDidFail:OCMOCK_ANY];
    
    // when
    ZMCompleteRegistrationUser *regUser = [ZMCompleteRegistrationUser registrationUserWithPhoneNumber:ValidPhoneNumber invitationCode:nil];
    [self.sut registerSelfUser:regUser];
}

@end
