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
@import WireSyncEngine;
@import WireUtilities;

#import "MessagingTest.h"
#import "ZMLoginCodeRequestTranscoder.h"
#import "ZMAuthenticationStatus.h"
#import "ZMCredentials.h"
#import "ZMAuthenticationStatus.h"
#import "WireSyncEngine_iOS_Tests-Swift.h"

@interface ZMLoginCodeRequestTranscoderTests : MessagingTest

@property (nonatomic) ZMLoginCodeRequestTranscoder *sut;
@property (nonatomic) ZMAuthenticationStatus *authenticationStatus;
@property (nonatomic) MockUserInfoParser *userInfoParser;

@end

@implementation ZMLoginCodeRequestTranscoderTests

- (void)setUp {
    [super setUp];

    DispatchGroupQueue *groupQueue = [[DispatchGroupQueue alloc] initWithQueue:dispatch_get_main_queue()];
    self.userInfoParser = [[MockUserInfoParser alloc] init];
    self.authenticationStatus = [[ZMAuthenticationStatus alloc] initWithGroupQueue:groupQueue userInfoParser:self.userInfoParser];
    self.sut = [[ZMLoginCodeRequestTranscoder alloc] initWithGroupQueue:groupQueue authenticationStatus:self.authenticationStatus];
}

- (void)tearDown {
    self.authenticationStatus = nil;
    self.sut = nil;
    self.userInfoParser = nil;
    [super tearDown];
}

- (void)testThatItReturnsNoRequestWhenThereAreNoCredentials
{
    ZMTransportRequest *request;
    request = [self.sut nextRequest];
    XCTAssertNil(request);
}

- (void)testThatItReturnsExpectedRequestWhenThereIsPhoneNumber
{
    NSString *phoneNumber = @"+7123456789";
    [self.authenticationStatus prepareForRequestingPhoneVerificationCodeForLogin:phoneNumber];

    ZMTransportRequest *expectedRequest = [[ZMTransportRequest alloc] initWithPath:@"/login/send" method:ZMMethodPOST payload:@{@"phone": phoneNumber} authentication:ZMTransportRequestAuthNone];
    
    ZMTransportRequest *request = [self.sut nextRequest];
    XCTAssertEqualObjects(request, expectedRequest);
}

- (void)testThatItInformTheAuthCenterThatTheCodeWasReceived
{
    // given
    NSString *phoneNumber = @"+7123456789";
    [self.authenticationStatus prepareForRequestingPhoneVerificationCodeForLogin:phoneNumber];
    ZMTransportRequest *request = [self.sut nextRequest];
    
    // when
    [request completeWithResponse:[ZMTransportResponse responseWithPayload:nil HTTPStatus:200 transportSessionError:nil]];
    WaitForAllGroupsToBeEmpty(0.2);
    
    // then
    XCTAssertEqual(self.authenticationStatus.currentPhase, ZMAuthenticationPhaseUnauthenticated);
}

- (void)testThatItInformTheAuthCenterThatTheCodeRequestFailed
{
    // given
    NSString *phoneNumber = @"+7123456789";
    [self.authenticationStatus prepareForRequestingPhoneVerificationCodeForLogin:phoneNumber];
    ZMTransportRequest *request = [self.sut nextRequest];
 
    // expect
    XCTestExpectation *expectation = [self expectationWithDescription:@"user session authentication notification"];
    
    id token = [[PreLoginAuthenticationObserverToken alloc] initWithAuthenticationStatus:self.authenticationStatus handler:^(enum PreLoginAuthenticationEventObjc event, NSError *error) {
        XCTAssertEqual(event, PreLoginAuthenticationEventObjcLoginCodeRequestDidFail);
        XCTAssertEqual(error.code, (long) ZMUserSessionUnknownError);
        XCTAssertEqualObjects(error.domain, NSError.ZMUserSessionErrorDomain);
        [expectation fulfill];
    }];
    
    // when
    [request completeWithResponse:[ZMTransportResponse responseWithPayload:nil HTTPStatus:400 transportSessionError:nil]];
    WaitForAllGroupsToBeEmpty(0.2);
    
    // then
    XCTAssertEqual(self.authenticationStatus.currentPhase, ZMAuthenticationPhaseUnauthenticated);
    XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0.5]);
    
    token = nil;
}


- (void)testThatItInformTheAuthCenterThatTheCodeRequestFailedBecauseOfInvalidPhoneNumber
{
    // given
    NSString *phoneNumber = @"+7123456789";
    [self.authenticationStatus prepareForRequestingPhoneVerificationCodeForLogin:phoneNumber];
    ZMTransportRequest *request = [self.sut nextRequest];
    
    // expect
    XCTestExpectation *expectation = [self expectationWithDescription:@"user session authentication notification"];
    
    id token = [[PreLoginAuthenticationObserverToken alloc] initWithAuthenticationStatus:self.authenticationStatus handler:^(enum PreLoginAuthenticationEventObjc event, NSError *error) {
        XCTAssertEqual(event, PreLoginAuthenticationEventObjcLoginCodeRequestDidFail);
        XCTAssertEqual(error.code, (long) ZMUserSessionInvalidPhoneNumber);
        XCTAssertEqualObjects(error.domain, NSError.ZMUserSessionErrorDomain);
        [expectation fulfill];
    }];
    
    // when
    [request completeWithResponse:[ZMTransportResponse responseWithPayload:@{@"label":@"invalid-phone"} HTTPStatus:400 transportSessionError:nil]];
    WaitForAllGroupsToBeEmpty(0.2);
    
    // then
    XCTAssertEqual(self.authenticationStatus.currentPhase, ZMAuthenticationPhaseUnauthenticated);
    XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0.5]);
    
    token = nil;
}


- (void)testThatItInformTheAuthCenterThatTheCodeRequestFailedBecauseOfPendingLogin
{
    // given
    NSString *phoneNumber = @"+7123456789";
    [self.authenticationStatus prepareForRequestingPhoneVerificationCodeForLogin:phoneNumber];
    ZMTransportRequest *request = [self.sut nextRequest];
    
    // expect
    XCTestExpectation *expectation = [self expectationWithDescription:@"user session authentication notification"];
    id token = [[PreLoginAuthenticationObserverToken alloc] initWithAuthenticationStatus:self.authenticationStatus handler:^(enum PreLoginAuthenticationEventObjc event, NSError *error) {
        XCTAssertEqual(event, PreLoginAuthenticationEventObjcLoginCodeRequestDidFail);
        XCTAssertEqual(error.code, (long) ZMUserSessionCodeRequestIsAlreadyPending);
        XCTAssertEqualObjects(error.domain, NSError.ZMUserSessionErrorDomain);
        [expectation fulfill];
    }];
    
    // when
    [request completeWithResponse:[ZMTransportResponse responseWithPayload:@{@"label":@"pending-login"} HTTPStatus:403 transportSessionError:nil]];
    WaitForAllGroupsToBeEmpty(0.2);
    
    // then
    XCTAssertEqual(self.authenticationStatus.currentPhase, ZMAuthenticationPhaseUnauthenticated);
    XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0.5]);
    
    token = nil;
}


- (void)testThatItInformTheAuthCenterThatTheCodeRequestFailedBecauseThePhoneIsUnauthorized
{
    // given
    NSString *phoneNumber = @"+7123456789";
    [self.authenticationStatus prepareForRequestingPhoneVerificationCodeForLogin:phoneNumber];
    ZMTransportRequest *request = [self.sut nextRequest];
    
    // expect
    XCTestExpectation *expectation = [self expectationWithDescription:@"user session authentication notification"];
    id token = [[PreLoginAuthenticationObserverToken alloc] initWithAuthenticationStatus:self.authenticationStatus handler:^(enum PreLoginAuthenticationEventObjc event, NSError *error) {
        XCTAssertEqual(event, PreLoginAuthenticationEventObjcLoginCodeRequestDidFail);
        XCTAssertEqual(error.code, (long) ZMUserSessionInvalidPhoneNumber);
        XCTAssertEqualObjects(error.domain, NSError.ZMUserSessionErrorDomain);
        [expectation fulfill];
    }];
    
    // when
    [request completeWithResponse:[ZMTransportResponse responseWithPayload:@{@"label":@"unauthorized"} HTTPStatus:403 transportSessionError:nil]];
    WaitForAllGroupsToBeEmpty(0.2);
    
    // then
    XCTAssertEqual(self.authenticationStatus.currentPhase, ZMAuthenticationPhaseUnauthenticated);
    XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0.5]);
    
    token = nil;
}

@end
