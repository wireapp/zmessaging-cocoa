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


@import ZMTransport;
@import zmessaging;
@import ZMCDataModel;

#import "MessagingTest.h"
#import "ZMPhoneNumberVerificationTranscoder.h"
#import "ZMAuthenticationStatus.h"
#import "ZMSingleRequestSync.h"
#import "ZMCredentials+Internal.h"
#import "ZMUserSessionRegistrationNotification.h"

@interface ZMPhoneNumberVerificationTranscoderTests : MessagingTest

@property (nonatomic) ZMPhoneNumberVerificationTranscoder *sut;
@property (nonatomic) ZMAuthenticationStatus *authenticationStatus;

@end

@implementation ZMPhoneNumberVerificationTranscoderTests

- (void)setUp {
    [super setUp];
    
    self.authenticationStatus = [[ZMAuthenticationStatus alloc] initWithManagedObjectContext:self.uiMOC cookie:nil];
    self.sut = [[ZMPhoneNumberVerificationTranscoder alloc] initWithManagedObjectContext:self.uiMOC authenticationStatus:self.authenticationStatus];
}

- (void)tearDown {
    [self.sut tearDown];
    self.sut = nil;
    [super tearDown];
}

- (void)testThatItReturnsRequestForVerificationCodeWhenThereIsPhoneNumberAndNoVerificationCode
{
    //given
    id mockLocale = [OCMockObject niceMockForClass:[NSLocale class]];
    [[[mockLocale stub] andReturn:@[@"en"]] preferredLanguages];
    
    NSString *phoneNumber = @"+712434235";
    [self.authenticationStatus prepareForRequestingPhoneVerificationCodeForRegistration:phoneNumber];
    NSDictionary *payload = @{@"phone": phoneNumber, @"locale": @"en"};
    
    ZMTransportRequest *expectedRequest = [[ZMTransportRequest alloc] initWithPath:@"/activate/send" method:ZMMethodPOST payload:payload authentication:ZMTransportRequestAuthNone];

    // when
    ZMTransportRequest *request = [self.sut.requestGenerators nextRequest];
    
    // then
    XCTAssertEqualObjects(request, expectedRequest);
}

- (void)testThatItReturnsRequestForPhoneNumberActivationWhenThereIsPhoneNumberAndVerificationCode
{
    //given
    NSString *phoneNumber = @"+712434235";
    NSString *code = @"123456";
    [self.authenticationStatus prepareForRegistrationPhoneVerificationWithCredentials:[ZMPhoneCredentials credentialsWithPhoneNumber:phoneNumber verificationCode:code]];
    
    [self.sut verifyPhoneNumber];
    
    ZMTransportRequest *expectedRequest = [[ZMTransportRequest alloc] initWithPath:@"/activate" method:ZMMethodPOST payload:@{@"phone": phoneNumber, @"code": code, @"dryrun": @(YES)} authentication:ZMTransportRequestAuthNone];
    
    //when
    ZMTransportRequest *request;
    request = [self.sut.requestGenerators nextRequest];
    
    //then
    XCTAssertEqualObjects(expectedRequest, request);
}

- (void)testThatItDoesNotReturnRequestIfThereIsNoPhoneNumberAndNoVerificationCode
{
    ZMTransportRequest *request;
    request = [self.sut.requestGenerators nextRequest];
    XCTAssertNil(request);
}

- (void)testThatItDoesNotReturnRequestIfThereIsNoPhoneNumberAndThereIsVerificationCode
{
    [self.authenticationStatus prepareForRegistrationPhoneVerificationWithCredentials:[ZMPhoneCredentials credentialsWithPhoneNumber:@"+4912345678900" verificationCode:@"123456"]];
    [self.authenticationStatus didCompletePhoneVerificationSuccessfully];
    
    ZMTransportRequest *request;
    request = [self.sut.requestGenerators nextRequest];
    XCTAssertNil(request);
}

- (void)testThatAfterResetVerificationStateItReturnsRequestForVerificationCodeIfNoVerificationCode
{
    //given
    NSString *phoneNumber = @"+712434235";
    [self.authenticationStatus prepareForRequestingPhoneVerificationCodeForRegistration:phoneNumber];

    //when
    ZMTransportRequest *request;
    request = [self.sut.requestGenerators nextRequest];
    
    //then
    XCTAssertNotNil(request);
    ZM_ALLOW_MISSING_SELECTOR(XCTAssertNil([self.sut.requestGenerators firstNonNilReturnedFromSelector:@selector(nextRequest)]));
    
    //and when
    ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:@{@"code": @0,
                                                                               @"message": @"",
                                                                               @"label": @""}
                                                                  HTTPStatus:400
                                                       transportSessionError:nil];
    [request completeWithResponse:response];
    WaitForAllGroupsToBeEmpty(0.5);

    [self.authenticationStatus prepareForRequestingPhoneVerificationCodeForRegistration:phoneNumber];
    [self.sut resetVerificationState];
    
    ZMTransportRequest *newRequest;
    ZM_ALLOW_MISSING_SELECTOR(newRequest = [self.sut.requestGenerators firstNonNilReturnedFromSelector:@selector(nextRequest)]);
    
    //then
    XCTAssertEqualObjects(request, newRequest);
    XCTAssertEqual(self.authenticationStatus.currentPhase, ZMAuthenticationPhaseRequestPhoneVerificationCodeForRegistration);
}

- (void)testThatAfterResetVerificationStateItReturnsActivationRequestIfThereIsVerificationCode
{
    //given
    NSString *phoneNumber = @"+712434235";
    NSString *code = @"123456";
    
    //when
    [self.authenticationStatus prepareForRegistrationPhoneVerificationWithCredentials:[ZMPhoneCredentials credentialsWithPhoneNumber:phoneNumber verificationCode:code]];
    [self.sut verifyPhoneNumber];
    
    ZMTransportRequest *request;
    request = [self.sut.requestGenerators nextRequest];
    
    //then
    XCTAssertNotNil(request);
    ZM_ALLOW_MISSING_SELECTOR(XCTAssertNil([self.sut.requestGenerators firstNonNilReturnedFromSelector:@selector(nextRequest)]));
    
    //and when
    ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:@{@"code": @0,
                                                                               @"message": @"",
                                                                               @"label": @""}
                                                                  HTTPStatus:400
                                                       transportSessionError:nil];
    [request completeWithResponse:response];
    WaitForAllGroupsToBeEmpty(0.5);
    
    [self.authenticationStatus prepareForRegistrationPhoneVerificationWithCredentials:[ZMPhoneCredentials credentialsWithPhoneNumber:phoneNumber verificationCode:code]];
    [self.sut resetVerificationState];
    
    ZMTransportRequest *newRequest;
    ZM_ALLOW_MISSING_SELECTOR(newRequest = [self.sut.requestGenerators firstNonNilReturnedFromSelector:@selector(nextRequest)]);
    
    //then
    XCTAssertEqualObjects(request, newRequest);
}

- (void)testThatVerifyPhoneNumberMarksVerificationRequest
{
    //given
    NSString *phoneNumber = @"+712434235";
    NSString *code = @"123456";
    [self.authenticationStatus prepareForRegistrationPhoneVerificationWithCredentials:[ZMPhoneCredentials credentialsWithPhoneNumber:phoneNumber verificationCode:code]];

    ZMTransportRequest *expectedRequest = [[ZMTransportRequest alloc] initWithPath:@"/activate" method:ZMMethodPOST payload:@{@"phone": phoneNumber, @"code": code, @"dryrun": @(YES)} authentication:ZMTransportRequestAuthNone];

    //when
    [self.sut verifyPhoneNumber];
    
    //then
    ZMTransportRequest *request;
    request = [self.sut.requestGenerators nextRequest];
    XCTAssertEqualObjects(expectedRequest, request);

    //and when
    ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:@{@"code": @0,
                                                                               @"message": @"",
                                                                               @"label": @""}
                                                                  HTTPStatus:400
                                                       transportSessionError:nil];
    [request completeWithResponse:response];
    WaitForAllGroupsToBeEmpty(0.5);

    //then
    request = [self.sut.requestGenerators nextRequest];
    XCTAssertNil(request);
    
    //and when
    [self.authenticationStatus prepareForRegistrationPhoneVerificationWithCredentials:[ZMPhoneCredentials credentialsWithPhoneNumber:phoneNumber verificationCode:code]];
    [self.sut verifyPhoneNumber];
    
    //then
    request = [self.sut.requestGenerators nextRequest];
    XCTAssertEqualObjects(expectedRequest, request);
}

- (void)testThatIfDuplicatedPhoneNumberGoesToLoginCodeRequestStatus
{
    // given
    NSString *phoneNumber = @"+712434235";
    [self.authenticationStatus prepareForRequestingPhoneVerificationCodeForRegistration:phoneNumber];
    
    ZMTransportRequest *request;
    request = [self.sut.requestGenerators nextRequest];
    ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:@{@"code": @0,
                                                                               @"message": @"",
                                                                               @"label": @"key-exists"}
                                                                  HTTPStatus:409
                                                       transportSessionError:nil];
    
    //when
    [request completeWithResponse:response];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(self.authenticationStatus.currentPhase, ZMAuthenticationPhaseRequestPhoneVerificationCodeForLogin);
    XCTAssertEqualObjects(self.authenticationStatus.loginPhoneNumberThatNeedsAValidationCode, phoneNumber);
}

- (void)testThatIfPhoneVerificationCodeRequestFailsPhoneNumberIsClearedAndCreadentialsAreNotSet
{
    // given
    NSString *phoneNumber = @"+712434235";
    [self.authenticationStatus prepareForRequestingPhoneVerificationCodeForRegistration:phoneNumber];

    ZMTransportRequest *request;
    request = [self.sut.requestGenerators nextRequest];

    ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:@{@"code": @0,
                                                                               @"message": @"",
                                                                               @"label": @""}
                                                                  HTTPStatus:400
                                                       transportSessionError:nil];
    
    //when
    [request completeWithResponse:response];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(self.authenticationStatus.currentPhase, ZMAuthenticationPhaseUnauthenticated);
    XCTAssertNil(self.authenticationStatus.loginCredentials);
    XCTAssertNil(self.authenticationStatus.registrationPhoneNumberThatNeedsAValidationCode);
    XCTAssertNil(self.authenticationStatus.registrationPhoneValidationCredentials);
}

- (void)testThatIfPhoneVerificationCodeRequestFailsItNotifies
{
    NSString *phoneNumber = @"+712434235";
    [self.authenticationStatus prepareForRequestingPhoneVerificationCodeForRegistration:phoneNumber];

    ZMTransportRequest *request;
    request = [self.sut.requestGenerators nextRequest];
    
    //given
    ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:@{@"code": @0,
                                                                               @"message": @"",
                                                                               @"label": @""}
                                                                  HTTPStatus:400
                                                       transportSessionError:nil];
    
    __block BOOL notificationCalled = NO;
    //expect
    id token = [ZMUserSessionRegistrationNotification addObserverWithBlock:^(ZMUserSessionRegistrationNotification *note) {
        XCTAssertNotNil(note.error);
        XCTAssertEqual(note.type, ZMRegistrationNotificationPhoneNumberVerificationCodeRequestDidFail);
        notificationCalled = YES;
    }];
    
    //when
    [request completeWithResponse:response];
    WaitForAllGroupsToBeEmpty(0.5);
    
    [ZMUserSessionRegistrationNotification removeObserver:token];
    XCTAssert(notificationCalled);
}

- (void)testThatIfPhoneVerificationCodeRequestSucceedItNotifies
{
    //given
    NSString *phoneNumber = @"+712434235";
    NSString *code = @"123456";
    [self.authenticationStatus prepareForRegistrationPhoneVerificationWithCredentials:[ZMPhoneCredentials credentialsWithPhoneNumber:phoneNumber verificationCode:code]];
    
    __block BOOL notificationCalled = NO;
    //expect
    id token = [ZMUserSessionRegistrationNotification addObserverWithBlock:^(ZMUserSessionRegistrationNotification *note) {
        XCTAssertNil(note.error);
        XCTAssertEqual(note.type, ZMRegistrationNotificationPhoneNumberVerificationDidSucceed);
        notificationCalled = YES;
    }];

    [self.sut verifyPhoneNumber];
    
    //when
    ZMTransportRequest *request;
    request = [self.sut.requestGenerators nextRequest];

    ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:@{}
                                                                  HTTPStatus:200
                                                       transportSessionError:nil];
    
    [request completeWithResponse:response];
    WaitForAllGroupsToBeEmpty(0.5);
    
    XCTAssert(notificationCalled);
    [ZMUserSessionRegistrationNotification removeObserver:token];
}

- (void)testThatIfPhoneActivationRequestFailsItClearsPhoneNumberAndCode
{
    ZMUser *selfUser = [ZMUser selfUserInContext:self.sut.managedObjectContext];
    XCTAssertNil(selfUser.phoneNumber);
    
    //given
    NSString *phoneNumber = @"+712434235";
    NSString *code = @"123456";
    [self.authenticationStatus prepareForRegistrationPhoneVerificationWithCredentials:[ZMPhoneCredentials credentialsWithPhoneNumber:phoneNumber verificationCode:code]];

    ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:@{}
                                                                  HTTPStatus:404
                                                       transportSessionError:nil];

    [self.sut verifyPhoneNumber];

    //when
    ZMTransportRequest *request;
    request = [self.sut.requestGenerators nextRequest];

    [request completeWithResponse:response];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(self.authenticationStatus.currentPhase, ZMAuthenticationPhaseUnauthenticated);
    XCTAssertNil(self.authenticationStatus.loginCredentials);
    XCTAssertNil(self.authenticationStatus.registrationPhoneNumberThatNeedsAValidationCode);
    XCTAssertNil(self.authenticationStatus.registrationPhoneValidationCredentials);
}

- (void)testThatItNotifiesIfPhoneActivationRequestFailsWithGenericError
{
    //given
    NSString *phoneNumber = @"+712434235";
    NSString *code = @"123456";
    [self.authenticationStatus prepareForRegistrationPhoneVerificationWithCredentials:[ZMPhoneCredentials credentialsWithPhoneNumber:phoneNumber verificationCode:code]];

    
    ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:@{}
                                                                  HTTPStatus:400
                                                       transportSessionError:nil];
    
    __block BOOL notificationCalled = NO;
    //expect
    id token = [ZMUserSessionRegistrationNotification addObserverWithBlock:^(ZMUserSessionRegistrationNotification *note) {
        XCTAssertEqualObjects(note.error.domain, ZMUserSessionErrorDomain);
        XCTAssertEqual(note.error.code, (long) ZMUserSessionUnkownError);
        XCTAssertEqual(note.type, ZMRegistrationNotificationPhoneNumberVerificationDidFail);
        notificationCalled = YES;
    }];
    
    [self.sut verifyPhoneNumber];
    
    //when
    ZMTransportRequest *request;
    request = [self.sut.requestGenerators nextRequest];
    
    [request completeWithResponse:response];
    WaitForAllGroupsToBeEmpty(0.5);

    [ZMUserSessionRegistrationNotification removeObserver:token];
    XCTAssert(notificationCalled);
}

- (void)testThatItNotifiesIfPhoneActivationRequestFailsWithInvalidCode
{
    //given
    NSString *phoneNumber = @"+712434235";
    NSString *code = @"123456";
    [self.authenticationStatus prepareForRegistrationPhoneVerificationWithCredentials:[ZMPhoneCredentials credentialsWithPhoneNumber:phoneNumber verificationCode:code]];
    
    
    ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:@{@"label":@"invalid-code"}
                                                                  HTTPStatus:404
                                                       transportSessionError:nil];
    
    __block BOOL notificationCalled = NO;
    //expect
    id token = [ZMUserSessionRegistrationNotification addObserverWithBlock:^(ZMUserSessionRegistrationNotification *note) {
        XCTAssertEqualObjects(note.error.domain, ZMUserSessionErrorDomain);
        XCTAssertEqual(note.error.code, (long) ZMUserSessionInvalidPhoneNumberVerificationCode);
        XCTAssertEqual(note.type, ZMRegistrationNotificationPhoneNumberVerificationDidFail);
        notificationCalled = YES;
    }];
    
    [self.sut verifyPhoneNumber];
    
    //when
    ZMTransportRequest *request;
    request = [self.sut.requestGenerators nextRequest];
    
    [request completeWithResponse:response];
    WaitForAllGroupsToBeEmpty(0.5);
    
    [ZMUserSessionRegistrationNotification removeObserver:token];
    XCTAssert(notificationCalled);
}


@end


