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

#import "MessagingTest.h"
#import "ObjectTranscoderTests.h"
#import "ZMUserProfileUpdateTranscoder.h"
#import "ZMUserProfileUpdateStatus.h"
#import "NSError+ZMUserSessionInternal.h"

@interface ZMUserProfileUpdateTrancoderTests : ObjectTranscoderTests

@property (nonatomic) ZMUserProfileUpdateTranscoder *sut;
@property (nonatomic) ZMUserProfileUpdateStatus *userProfileStatus;

- (ZMTransportResponse *)errorResponse;
- (ZMTransportResponse *)badRequestResponse;
- (ZMTransportResponse *)invalidPhoneNumberResponse;
- (ZMTransportResponse *)successResponse;
- (ZMTransportResponse *)invalidEmailResponse;

@end



@implementation ZMUserProfileUpdateTrancoderTests

- (ZMTransportResponse *)errorResponse {
    return [ZMTransportResponse responseWithPayload:nil HTTPStatus:400 transportSessionError:nil];
}

- (ZMTransportResponse *)badRequestResponse {
    return [ZMTransportResponse responseWithPayload:@{@"label": @"bad-request"} HTTPStatus:400 transportSessionError:nil];
}

- (ZMTransportResponse *)keyExistsResponse {
    return [ZMTransportResponse responseWithPayload:@{@"label": @"key-exists"} HTTPStatus:409 transportSessionError:nil];
}

- (ZMTransportResponse *)invalidPhoneNumberResponse {
    return [ZMTransportResponse responseWithPayload:@{@"label": @"invalid-phone"} HTTPStatus:400 transportSessionError:nil];
}

- (ZMTransportResponse *)invalidEmailResponse {
    return [ZMTransportResponse responseWithPayload:@{@"label": @"invalid-email"} HTTPStatus:400 transportSessionError:nil];
}

- (ZMTransportResponse *)successResponse {
    return [ZMTransportResponse responseWithPayload:nil HTTPStatus:200 transportSessionError:nil];
}

- (void)setUp {
    [super setUp];
    self.userProfileStatus = [OCMockObject partialMockForObject:[[ZMUserProfileUpdateStatus alloc] initWithManagedObjectContext:self.uiMOC]];
    self.sut = [[ZMUserProfileUpdateTranscoder alloc] initWithManagedObjectContext:self.uiMOC userProfileUpdateStatus:self.userProfileStatus];
}

- (void)tearDown {
    
    [(id)self.userProfileStatus verify];
    self.userProfileStatus = nil;
    [self.sut tearDown];
    self.sut = nil;
    [super tearDown];
}

- (void)testThatItDoesNotCreateAnyRequestIfTheUserProfileStatusIsIdle
{
    // when
    ZMTransportRequest *request = [self.sut.requestGenerators nextRequest];
    
    // then
    XCTAssertNil(request);
}

@end


@implementation ZMUserProfileUpdateTrancoderTests (Requests)

- (void)testThatItCreatesARequestToRequestAPhoneVerificationCode
{
    // given
    NSString *phone = @"+4912345678900";
    [self.userProfileStatus prepareForRequestingPhoneVerificationCodeForRegistration:phone];
    ZMTransportRequest *expected = [ZMTransportRequest requestWithPath:@"/self/phone" method:ZMMethodPUT payload:@{@"phone":phone}];
    
    // when
    ZMTransportRequest *request = [[self.sut requestGenerators] nextRequest];
    
    // then
    XCTAssertEqualObjects(expected, request);
}


- (void)testThatItCreatesARequestToVerifyPhone
{
    // given
    NSString *phone = @"+4912345678900";
    NSString *code = @"123456";
    [self.userProfileStatus prepareForPhoneChangeWithCredentials:[ZMPhoneCredentials credentialsWithPhoneNumber:phone verificationCode:code]];
    ZMTransportRequest *expected = [ZMTransportRequest requestWithPath:@"/activate" method:ZMMethodPOST payload:@{@"phone":phone, @"code":code, @"dryrun":@(NO)}];
    
    // when
    ZMTransportRequest *request = [[self.sut requestGenerators] nextRequest];
    
    // then
    XCTAssertEqualObjects(expected, request);
}

- (void)testThatItCreatesARequestToUpdatePassword
{
    // given
    NSString *email = @"mm@foo.bar";
    NSString *password = @"12$#@$3456";
    [self.userProfileStatus prepareForEmailAndPasswordChangeWithCredentials:[ZMEmailCredentials credentialsWithEmail:email password:password]];
    ZMTransportRequest *expected = [ZMTransportRequest requestWithPath:@"/self/password" method:ZMMethodPUT payload:@{@"new_password":password}];
    
    // when
    ZMTransportRequest *request = [[self.sut requestGenerators] nextRequest];
    
    // then
    XCTAssertEqualObjects(expected, request);
}

- (void)testThatItCreatesARequestToUpdateEmail
{
    // given
    NSString *email = @"mm@foo.bar";
    NSString *password = @"12$#@$3456";
    [self.userProfileStatus prepareForEmailAndPasswordChangeWithCredentials:[ZMEmailCredentials credentialsWithEmail:email password:password]];
    [self.userProfileStatus didUpdatePasswordSuccessfully];
    ZMTransportRequest *expected = [ZMTransportRequest requestWithPath:@"/self/email" method:ZMMethodPUT payload:@{@"email":email}];
    
    // when
    ZMTransportRequest *request = [[self.sut requestGenerators] nextRequest];
    
    // then
    XCTAssertEqualObjects(expected, request);
}

@end


@implementation ZMUserProfileUpdateTrancoderTests (Responses)

- (void)testThatItCallsDidRequestPhoneVerificationCodeSuccessfully
{
    // given
    NSString *phone = @"+4912345678900";
    [self.userProfileStatus prepareForRequestingPhoneVerificationCodeForRegistration:phone];
    
    // expect
    [[(id) self.userProfileStatus expect] didRequestPhoneVerificationCodeSuccessfully];
    
    // when
    ZMTransportRequest *request = [[self.sut requestGenerators] nextRequest];
    [request completeWithResponse:self.successResponse];
    WaitForAllGroupsToBeEmpty(0.1);
}

- (void)testThatItCallsDidFailPhoneVerificationCodeRequest
{
    // given
    NSString *phone = @"+4912345678900";
    [self.userProfileStatus prepareForRequestingPhoneVerificationCodeForRegistration:phone];
    
    // expect
    [[(id) self.userProfileStatus expect] didFailPhoneVerificationCodeRequestWithError:[OCMArg isNotNil]];
    
    // when
    ZMTransportRequest *request = [[self.sut requestGenerators] nextRequest];
    [request completeWithResponse:self.errorResponse];
    WaitForAllGroupsToBeEmpty(0.1);
}

- (void)testThatItGetsInvalidPhoneNumberErrorOnInvalidPhoneResponse
{
    // given
    NSString *phone = @"+4912345678900";
    [self.userProfileStatus prepareForRequestingPhoneVerificationCodeForRegistration:phone];
    
    // expect
    [[(id) self.userProfileStatus expect] didFailPhoneVerificationCodeRequestWithError:[OCMArg checkWithBlock:^BOOL(NSError *error) {
        return error.code == ZMUserSessionInvalidPhoneNumber;
    }]];
    
    // when
    ZMTransportRequest *request = [[self.sut requestGenerators] nextRequest];
    [request completeWithResponse:self.invalidPhoneNumberResponse];
    WaitForAllGroupsToBeEmpty(0.1);
}

- (void)testThatItGetsInvalidPhoneNumberErrorOnBadRequestResponse
{
    // given
    NSString *phone = @"+4912345678900";
    [self.userProfileStatus prepareForRequestingPhoneVerificationCodeForRegistration:phone];
    
    // expect
    [[(id) self.userProfileStatus expect] didFailPhoneVerificationCodeRequestWithError:[OCMArg checkWithBlock:^BOOL(NSError *error) {
        return error.code == ZMUserSessionInvalidPhoneNumber;
    }]];
    
    // when
    ZMTransportRequest *request = [[self.sut requestGenerators] nextRequest];
    [request completeWithResponse:self.badRequestResponse];
    WaitForAllGroupsToBeEmpty(0.1);
}

- (void)testThatItGetsDuplicatePhoneNumberErrorOnDuplicatePhoneNumber
{
    // given
    NSString *phone = @"+4912345678900";
    [self.userProfileStatus prepareForRequestingPhoneVerificationCodeForRegistration:phone];
    
    // expect
    [[(id) self.userProfileStatus expect] didFailPhoneVerificationCodeRequestWithError:[OCMArg checkWithBlock:^BOOL(NSError *error) {
        return error.code == ZMUserSessionPhoneNumberIsAlreadyRegistered;
    }]];
    
    // when
    ZMTransportRequest *request = [[self.sut requestGenerators] nextRequest];
    [request completeWithResponse:self.keyExistsResponse];
    WaitForAllGroupsToBeEmpty(0.1);
}

- (void)testThatItCallsDidVerifyPhoneSuccessfully
{
    // given
    NSString *phone = @"+4912345678900";
    NSString *code = @"123456";
    [self.userProfileStatus prepareForPhoneChangeWithCredentials:[ZMPhoneCredentials credentialsWithPhoneNumber:phone verificationCode:code]];
    
    // expect
    [[(id) self.userProfileStatus expect] didVerifyPhoneSuccessfully];
    
    // when
    ZMTransportRequest *request = [[self.sut requestGenerators] nextRequest];
    [request completeWithResponse:self.successResponse];
    WaitForAllGroupsToBeEmpty(0.1);

}

- (void)testThatItCallsDidFailPhoneVerification
{
    // given
    NSString *phone = @"+4912345678900";
    NSString *code = @"123456";
    [self.userProfileStatus prepareForPhoneChangeWithCredentials:[ZMPhoneCredentials credentialsWithPhoneNumber:phone verificationCode:code]];
    
    // expect
    [[(id) self.userProfileStatus expect] didFailPhoneVerification:[NSError userSessionErrorWithErrorCode:ZMUserSessionUnkownError userInfo:nil]];
    
    // when
    ZMTransportRequest *request = [[self.sut requestGenerators] nextRequest];
    [request completeWithResponse:self.errorResponse];
    WaitForAllGroupsToBeEmpty(0.1);

}

- (void)testThatCallsDidUpdatePasswordSuccessfully
{
    // given
    NSString *email = @"mm@foo.bar";
    NSString *password = @"12$#@$3456";
    [self.userProfileStatus prepareForEmailAndPasswordChangeWithCredentials:[ZMEmailCredentials credentialsWithEmail:email password:password]];
    
    // expect
    [[(id) self.userProfileStatus expect] didUpdatePasswordSuccessfully];
    
    // when
    ZMTransportRequest *request = [[self.sut requestGenerators] nextRequest];
    [request completeWithResponse:self.successResponse];
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatCallsDidFailPasswordUpdateOn403
{
    // given
    NSString *email = @"mm@foo.bar";
    NSString *password = @"12$#@$3456";
    [self.userProfileStatus prepareForEmailAndPasswordChangeWithCredentials:[ZMEmailCredentials credentialsWithEmail:email password:password]];
    
    // expect
    [[(id) self.userProfileStatus expect] didUpdatePasswordSuccessfully];
    
    // when
    ZMTransportRequest *request = [[self.sut requestGenerators] nextRequest];
    [request completeWithResponse:[ZMTransportResponse responseWithPayload:@{@"label":@"invalid-credentials"} HTTPStatus:403 transportSessionError:nil]];
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatCallsDidFailPasswordUpdateOn400
{
    // given
    NSString *email = @"mm@foo.bar";
    NSString *password = @"12$#@$3456";
    [self.userProfileStatus prepareForEmailAndPasswordChangeWithCredentials:[ZMEmailCredentials credentialsWithEmail:email password:password]];
    
    // expect
    [[(id) self.userProfileStatus expect] didFailPasswordUpdate];
    
    // when
    ZMTransportRequest *request = [[self.sut requestGenerators] nextRequest];
    [request completeWithResponse:self.errorResponse];
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatItCallsDidUpdateEmailSuccessfully
{
    // given
    NSString *email = @"mm@foo.bar";
    NSString *password = @"12$#@$3456";
    [self.userProfileStatus prepareForEmailAndPasswordChangeWithCredentials:[ZMEmailCredentials credentialsWithEmail:email password:password]];
    [self.userProfileStatus didUpdatePasswordSuccessfully];
    
    // expect
    [[(id) self.userProfileStatus expect] didUpdateEmailSuccessfully];
    
    // when
    ZMTransportRequest *request = [[self.sut requestGenerators] nextRequest];
    [request completeWithResponse:self.successResponse];
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatItCallsDidFailEmailUpdateWithInvalidEmail
{
    // given
    NSString *email = @"mm@foo.bar";
    NSString *password = @"12$#@$3456";
    [self.userProfileStatus prepareForEmailAndPasswordChangeWithCredentials:[ZMEmailCredentials credentialsWithEmail:email password:password]];
    [self.userProfileStatus didUpdatePasswordSuccessfully];
    
    // expect
    [[(id) self.userProfileStatus expect] didFailEmailUpdate:[NSError userSessionErrorWithErrorCode:ZMUserSessionInvalidEmail userInfo:nil]];
    
    // when
    ZMTransportRequest *request = [[self.sut requestGenerators] nextRequest];
    [request completeWithResponse:self.invalidEmailResponse];
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatItCallsDidFailEmailUpdateWithDuplicatedEmail
{
    // given
    NSString *email = @"mm@foo.bar";
    NSString *password = @"12$#@$3456";
    [self.userProfileStatus prepareForEmailAndPasswordChangeWithCredentials:[ZMEmailCredentials credentialsWithEmail:email password:password]];
    [self.userProfileStatus didUpdatePasswordSuccessfully];
    
    // expect
    [[(id) self.userProfileStatus expect] didFailEmailUpdate:[NSError userSessionErrorWithErrorCode:ZMUserSessionEmailIsAlreadyRegistered userInfo:nil]];
    
    // when
    ZMTransportRequest *request = [[self.sut requestGenerators] nextRequest];
    [request completeWithResponse:self.keyExistsResponse];
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatItCallsDidFailEmailUpdateWithUnknownError
{
    // given
    NSString *email = @"mm@foo.bar";
    NSString *password = @"12$#@$3456";
    [self.userProfileStatus prepareForEmailAndPasswordChangeWithCredentials:[ZMEmailCredentials credentialsWithEmail:email password:password]];
    [self.userProfileStatus didUpdatePasswordSuccessfully];
    
    // expect
    [[(id) self.userProfileStatus expect] didFailEmailUpdate:[NSError userSessionErrorWithErrorCode:ZMUserSessionUnkownError userInfo:nil]];
    
    // when
    ZMTransportRequest *request = [[self.sut requestGenerators] nextRequest];
    [request completeWithResponse:self.errorResponse];
    WaitForAllGroupsToBeEmpty(0.5);
}

@end
