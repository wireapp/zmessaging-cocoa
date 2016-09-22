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


#import "IntegrationTestBase.h"
#import "ZMUserSession.h"
#import "NSError+ZMUserSession.h"
#import "ZMSearchDirectory.h"

#import "ZMUserSession+Authentication.h"
#import "ZMUserSession+Registration.h"
#import "ZMCredentials.h"
#import "ZMUserSessionRegistrationNotification.h"

@interface PhoneRegistrationTests : IntegrationTestBase

@property (nonatomic) id registrationObserver;
@property (nonatomic) id registrationObserverToken;
@property (nonatomic) id authenticationObserver;
@property (nonatomic) id authenticationObserverToken;

@end

@implementation PhoneRegistrationTests

- (void)setUp
{
    [super setUp];
    self.registrationObserver = [OCMockObject mockForProtocol:@protocol(ZMRegistrationObserver)];
    self.registrationObserverToken = [self.userSession addRegistrationObserver:self.registrationObserver];
    self.authenticationObserver = [OCMockObject mockForProtocol:@protocol(ZMAuthenticationObserver)];
    self.authenticationObserverToken = [self.userSession addAuthenticationObserver:self.authenticationObserver];
}

- (void)tearDown
{
    [self.authenticationObserver verify];
    [self.registrationObserver verify];
    [self.userSession removeRegistrationObserverForToken:self.registrationObserverToken];
    [self.userSession removeAuthenticationObserverForToken:self.authenticationObserverToken];
    self.registrationObserver = nil;
    self.registrationObserverToken = nil;
    self.authenticationObserver = nil;
    self.authenticationObserverToken = nil;
    [super tearDown];
}


- (ZMIncompleteRegistrationUser *)createUserWithPhone:(NSString *)phone code:(NSString *)code
{
    ZMIncompleteRegistrationUser *user = [[ZMIncompleteRegistrationUser alloc] init];
    user.phoneNumber = phone;
    user.phoneVerificationCode = code;
    user.name = @"Karl";
    user.accentColorValue = ZMAccentColorStrongBlue;
    return user;
}

- (void)testThatWeCanRegisterAndLogInIfWeHaveAValidCode
{
    // given
    NSString *phone = @"+49(1234)-567.89";
    NSString *expectedPhone = @"+49123456789";
    NSString *code = self.mockTransportSession.phoneVerificationCodeForRegistration;

    // expect
    XCTestExpectation *phoneVerificationCodeRequestExpectation = [self expectationWithDescription:@"phoneVerificationCodeRequest succeed"];
    [[[self.registrationObserver expect] andDo:^(NSInvocation *i ZM_UNUSED) {
        [phoneVerificationCodeRequestExpectation fulfill];
    }] phoneVerificationCodeRequestDidSucceed];
    
    
    // when
    [self.userSession requestPhoneVerificationCodeForRegistration:phone];
    if(![self waitForCustomExpectationsWithTimeout:0.5]) {
        XCTFail(@"Failed to request verification code for phone");
        return;
    }
    
    // expect
    XCTestExpectation *phoneVerifiedExpectation = [self expectationWithDescription:@"phoneVerification succeed"];
    [[[self.registrationObserver expect] andDo:^(NSInvocation *i ZM_UNUSED) {
        [phoneVerifiedExpectation fulfill];
    }] phoneVerificationDidSucceed];
    [[self.authenticationObserver expect] authenticationDidSucceed];
    
    // when
    [self.userSession verifyPhoneNumberForRegistration:phone verificationCode:code];
    WaitForAllGroupsToBeEmpty(0.5);
    
    if(![self waitForCustomExpectationsWithTimeout:0.5]) {
        XCTFail(@"Failed to verify phone");
        return;
    }
    
    // and when
    ZMIncompleteRegistrationUser *user = [self createUserWithPhone:phone code:code];
    
    // when
    [self.userSession registerSelfUser:user.completeRegistrationUser];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertTrue(self.userSession.registeredOnThisDevice);
    ZMUser *selfUser = [ZMUser selfUserInUserSession:self.userSession];
    XCTAssertEqualObjects(selfUser.name, user.name);
    XCTAssertEqualObjects(selfUser.phoneNumber, expectedPhone);
    XCTAssertEqual(selfUser.accentColorValue, user.accentColorValue);
}

- (void)testThatItNotifiesTheAuthenticationObserver
{
    // given
    NSString *phone = @"+4912345678900";
    NSString *code = self.mockTransportSession.phoneVerificationCodeForRegistration;
    [[self.registrationObserver stub] phoneVerificationDidSucceed];
    [[self.registrationObserver stub] phoneVerificationCodeRequestDidSucceed];
    
    [self.userSession requestPhoneVerificationCodeForRegistration:phone];
    WaitForAllGroupsToBeEmpty(0.5);
    [self.userSession verifyPhoneNumberForRegistration:phone verificationCode:code];
    WaitForAllGroupsToBeEmpty(0.5);
    
    ZMIncompleteRegistrationUser *user = [self createUserWithPhone:phone code:code];
    
    // expect
    [[self.authenticationObserver expect] authenticationDidSucceed];

    // when
    [self.userSession registerSelfUser:user.completeRegistrationUser];
    WaitForAllGroupsToBeEmpty(0.5);
}


- (void)testThatItNotifiesOfAPhoneCodeRequestFailure
{
    // given
    NSString *phone = @"+4912345678900";

    self.mockTransportSession.responseGeneratorBlock = ^ZMTransportResponse*(ZMTransportRequest *request){
        if([request.path isEqualToString:@"/activate/send"]) {
            return [ZMTransportResponse responseWithPayload:nil HTTPStatus:400 transportSessionError:nil];
        }
        return nil;
    };
    
    // expect
    [[self.registrationObserver expect] phoneVerificationCodeRequestDidFail:OCMOCK_ANY];
    
    // when
    [self.userSession requestPhoneVerificationCodeForRegistration:phone];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(self.mockTransportSession.receivedRequests.count, 1u);
}


- (void)testThatItNotifiesOfAPhoneVerificationFailure
{
    // given
    NSString *phone = @"+4912345678900";
    NSString *code = self.mockTransportSession.invalidPhoneVerificationCode;
    
    // expect
    [[self.registrationObserver expect] phoneVerificationCodeRequestDidSucceed];
    [[self.registrationObserver expect] phoneVerificationDidFail:OCMOCK_ANY];
    
    // when
    [self.userSession requestPhoneVerificationCodeForRegistration:phone];
    WaitForAllGroupsToBeEmpty(0.5);
    [self.userSession verifyPhoneNumberForRegistration:phone verificationCode:code];
    WaitForAllGroupsToBeEmpty(0.5);

    // then
    
    XCTAssertEqual(self.mockTransportSession.receivedRequests.count, 2u);
}

- (void)testThatItNotifiesOfARegistrationFailure
{
    // given
    NSString *phone = @"+4912345678900";
    NSString *code = self.mockTransportSession.phoneVerificationCodeForRegistration;
    
    // expect
    [[self.registrationObserver expect] phoneVerificationCodeRequestDidSucceed];
    
    __block BOOL step2;
    [[[self.registrationObserver expect] andDo:^(NSInvocation *i ZM_UNUSED) {
        step2 = YES;
    }] phoneVerificationDidSucceed];
    
    // when
    [self.userSession requestPhoneVerificationCodeForRegistration:phone];
    WaitForAllGroupsToBeEmpty(0.5);
    [self.userSession verifyPhoneNumberForRegistration:phone verificationCode:code];
    WaitForAllGroupsToBeEmpty(0.5);
    
    if(!step2) {
        XCTFail(@"Code not verified");
        return;
    }
    
    // and given
    ZMIncompleteRegistrationUser *user = [self createUserWithPhone:phone code:self.mockTransportSession.invalidPhoneVerificationCode];
    
    // expect
    [[self.registrationObserver expect] registrationDidFail:OCMOCK_ANY];
    
    // when
    [self.userSession registerSelfUser:user.completeRegistrationUser];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(self.mockTransportSession.receivedRequests.count, 3u);
}

- (void)testThatItLogsInWithAPhoneNumberIfThePhoneNumberIsAlreadyRegisteredToAnotherUser
{
    // given
    NSString *phone = @"+4912345678900";
    NSString *code = self.mockTransportSession.phoneVerificationCodeForLogin;
    
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        NOT_USED(session);
        self.selfUser.phone = phone;
    }];
    
    // expect
    [[self.authenticationObserver expect] loginCodeRequestDidSucceed];
    [[self.authenticationObserver expect] authenticationDidSucceed];
    
    // when
    [self.userSession requestPhoneVerificationCodeForRegistration:phone];
    WaitForAllGroupsToBeEmpty(0.5);
    [self.userSession verifyPhoneNumberForRegistration:phone verificationCode:code];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    ZMUser *selfUser = [ZMUser selfUserInUserSession:self.userSession];
    XCTAssertEqualObjects(selfUser.name, selfUser.name);
    XCTAssertEqualObjects(selfUser.phoneNumber, phone);
    XCTAssertEqual(selfUser.accentColorValue, selfUser.accentColorValue);
    
}

- (void)testThatItReturnsAPhoneVerificationFailureWithAlreadyRegisteredPhoneNumber
{
    // given
    NSString *phone = @"+4912345678900";
    NSString *code = self.mockTransportSession.invalidPhoneVerificationCode;
    
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        NOT_USED(session);
        self.selfUser.phone = phone;
    }];
    
    // expect
    [[self.authenticationObserver expect] loginCodeRequestDidSucceed];
    [[self.registrationObserver expect] registrationDidFail:[OCMArg checkWithBlock:^BOOL(NSError *error) {
        XCTAssertEqual(error.code, (int) ZMUserSessionPhoneNumberIsAlreadyRegistered);
        XCTAssertEqualObjects(error.domain, ZMUserSessionErrorDomain);
        return YES;
    }]];
    
    // when
    [self.userSession requestPhoneVerificationCodeForRegistration:phone];
    WaitForAllGroupsToBeEmpty(0.5);
    [self.userSession verifyPhoneNumberForRegistration:phone verificationCode:code];
    WaitForAllGroupsToBeEmpty(0.5);

}

- (void)testThatWeCanAskForThePhoneRegistrationCodeTwice
{
    // given
    NSString *phone1 = @"+4912345678900";
    NSString *phone2 = @"+4900000000000";
    
    [[self.registrationObserver stub] phoneVerificationCodeRequestDidSucceed];
    
    // when
    [self.userSession requestPhoneVerificationCodeForRegistration:phone1];
    WaitForAllGroupsToBeEmpty(0.5);
    [self.userSession requestPhoneVerificationCodeForRegistration:phone2];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(self.mockTransportSession.receivedRequests.count, 2u);
}

@end
