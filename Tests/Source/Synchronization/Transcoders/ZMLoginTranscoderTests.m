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

@import ZMCDataModel;

#import "MessagingTest.h"
#import "ZMLoginTranscoder+Internal.h"
#import "ZMUserSession+Internal.h"
#import "ZMCredentials.h"
#import "ZMAuthenticationStatus.h"
#import "NSError+ZMUserSession.h"
#import "ZMUserSessionAuthenticationNotification.h"
#import "ZMUserSessionRegistrationNotification.h"
#import "ZMClientRegistrationStatus.h"
#import "ZMAuthenticationStatus.h"

@import ZMUtilities;

static NSString * const TestEmail = @"bar@example.com";
static NSString * const TestPassword = @"super-secure-password-sijovhjs987y";

static NSString * const TestPhoneNumber = @"+7123456789";
static NSString * const TestPhoneCode = @"123456";

extern NSTimeInterval DefaultPendingValidationLoginAttemptInterval;

@interface TestTimedSingleRequest : NSObject

@property (nonatomic) NSTimeInterval timeInterval;
- (ZMTransportRequest *)nextRequest;

@end



@implementation TestTimedSingleRequest

- (ZMTransportRequest *)nextRequest {
    return nil;
}

@end




@interface ZMLoginTranscoderTests : MessagingTest

@property (nonatomic) ZMLoginTranscoder *sut;
@property (nonatomic) ZMAuthenticationStatus *authenticationStatus;
@property (nonatomic) id mockClientRegistrationStatus;

@property (nonatomic) ZMCredentials *testEmailCredentials;
@property (nonatomic) ZMCredentials *testPhoneNumberCredentials;
@property (nonatomic) NSTimeInterval originalLoginTimerInterval;
@property (nonatomic) id mockLocale;

@end

@implementation ZMLoginTranscoderTests


- (void)setUp {
    [super setUp];
    
    self.originalLoginTimerInterval = DefaultPendingValidationLoginAttemptInterval;
    ZMCookie *cookie = [[ZMCookie alloc] initWithManagedObjectContext:self.uiMOC cookieStorage:[ZMPersistentCookieStorage storageForServerName:@"test"]];
    self.authenticationStatus = [[ZMAuthenticationStatus alloc] initWithManagedObjectContext:self.uiMOC cookie:cookie];
    self.mockClientRegistrationStatus = [OCMockObject niceMockForClass:[ZMClientRegistrationStatus class]];
    
    self.mockLocale = [OCMockObject niceMockForClass:[NSLocale class]];
    [[[self.mockLocale stub] andReturn:[NSLocale localeWithLocaleIdentifier:@"fr_FR"]] currentLocale];
    
    self.sut = [[ZMLoginTranscoder alloc] initWithManagedObjectContext:self.uiMOC authenticationStatus:self.authenticationStatus clientRegistrationStatus:self.mockClientRegistrationStatus];
    
    self.testEmailCredentials = [ZMEmailCredentials credentialsWithEmail:TestEmail password:TestPassword];
    self.testPhoneNumberCredentials = [ZMPhoneCredentials credentialsWithPhoneNumber:TestPhoneNumber verificationCode:TestPhoneCode];
}

- (void)tearDown {
    [self.sut tearDown];
    self.sut = nil;
    self.authenticationStatus = nil;
    self.mockClientRegistrationStatus = nil;
    self.mockLocale = nil;
    DefaultPendingValidationLoginAttemptInterval = self.originalLoginTimerInterval;
    [super tearDown];
}


- (void)testThatItGeneratesRequestsItSelf
{
    // when
    NSArray *generators = self.sut.requestGenerators;
    
    // then
    XCTAssertEqual(generators.count, 1u);
    XCTAssertEqual(generators.firstObject, self.sut);
}

- (void)testThatItReturnsTheContextChangeTrackers;
{
    // when
    NSArray *trackers = self.sut.contextChangeTrackers;
    
    // then
    XCTAssertEqual(trackers.count, 0u);
}

- (void)testThatItCreatesTheTimedRequestSyncWithZeroDelayInDefaultConstructor
{
    // given
    ZMLoginTranscoder *sut = [[ZMLoginTranscoder alloc] initWithManagedObjectContext:self.uiMOC authenticationStatus:self.authenticationStatus clientRegistrationStatus:self.mockClientRegistrationStatus];
    
    // then
    XCTAssertNotNil(sut.timedDownstreamSync);
    XCTAssertEqualObjects(sut.timedDownstreamSync.moc, self.uiMOC);
    XCTAssertEqualObjects(sut.timedDownstreamSync.transcoder, sut);
    XCTAssertEqual(sut.timedDownstreamSync.timeInterval, 0);
    
    // after
    [sut tearDown];
}

- (void)expectAuthenticationSucceedAfter:(void(^)())block;
{
    id mockAuthStatus = [OCMockObject partialMockForObject:self.authenticationStatus];
    [[[mockAuthStatus expect] andForwardToRealObject] loginSucceed];
    
    // when
    block();
    
    //then
    [mockAuthStatus verify];
}

- (void)expectAuthenticationFailedWithError:(ZMUserSessionErrorCode)code after:(void(^)())block;
{
    //expect
    __block BOOL notified = NO;
    id<ZMAuthenticationObserverToken> token = [ZMUserSessionAuthenticationNotification addObserverWithBlock:^(ZMUserSessionAuthenticationNotification *note) {
        XCTAssertNotNil(note.error);
        XCTAssertEqual((ZMUserSessionErrorCode)note.error.code, code);
        notified = YES;
    }];
    
    // when
    block();
    
    //then
    XCTAssert(notified);
    [ZMUserSessionAuthenticationNotification removeObserver:token];
}

- (void)expectRegistrationSucceedAfter:(void(^)())block;
{
    //expect
    __block BOOL notified = NO;
    id<ZMRegistrationObserverToken> token = [ZMUserSessionRegistrationNotification addObserverWithBlock:^(ZMUserSessionRegistrationNotification *note) {
        XCTAssertNil(note.error);
        notified = YES;
    }];
    
    // when
    block();
    
    //then
    XCTAssert(notified);
    [ZMUserSessionRegistrationNotification removeObserver:token];
}

- (void)expectRegistrationFailedWithError:(ZMUserSessionErrorCode)code after:(void(^)())block;
{
    //expect
    __block BOOL notified = NO;
    id<ZMRegistrationObserverToken> token = [ZMUserSessionRegistrationNotification addObserverWithBlock:^(ZMUserSessionRegistrationNotification *note) {
        XCTAssertNotNil(note.error);
        XCTAssertEqual((ZMUserSessionErrorCode)note.error.code, code);
        notified = YES;
    }];
    
    // when
    block();
    
    //then
    XCTAssert(notified);
    [ZMUserSessionRegistrationNotification removeObserver:token];
}

@end

@implementation ZMLoginTranscoderTests (Login)

- (void)testThatItReturnsNoLoginRequestWhenTheUserSessionHasNoCredentials
{
    // when
    ZMTransportRequest *request = [self.sut.requestGenerators nextRequest];
    
    // then
    XCTAssertNil(request);
}


- (void)testThatItGeneratesALoginRequestWhenTheUserSessionHasCredentialsWithEmailAndWeAreNotLoggedIn
{
    // given
    NSDictionary *payload = @{@"email": self.testEmailCredentials.email,
                              @"password": self.testEmailCredentials.password,
                              @"label": self.authenticationStatus.cookieLabel};
    ZMTransportRequest *expectedRequest = [[ZMTransportRequest alloc] initWithPath:ZMLoginURL method:ZMMethodPOST payload:payload authentication:ZMTransportRequestAuthCreatesCookieAndAccessToken];
    
    [self.authenticationStatus prepareForLoginWithCredentials:self.testEmailCredentials];

    // when
    ZMTransportRequest *request = [[self.sut requestGenerators] nextRequest];
    
    // then
    XCTAssertEqualObjects(request, expectedRequest);
}

- (void)testThatItGeneratesALoginRequestWhenTheUserSessionHasCredentialsWithPhoneNumberAndWeAreNotLoggedIn
{
    // given
    NSDictionary *payload = @{@"phone": self.testPhoneNumberCredentials.phoneNumber,
                              @"code": self.testPhoneNumberCredentials.phoneNumberVerificationCode,
                              @"label": self.authenticationStatus.cookieLabel};
    ZMTransportRequest *expectedRequest = [[ZMTransportRequest alloc] initWithPath:ZMLoginURL method:ZMMethodPOST payload:payload authentication:ZMTransportRequestAuthCreatesCookieAndAccessToken];
    [self.authenticationStatus prepareForLoginWithCredentials:self.testPhoneNumberCredentials];
    
    // when
    ZMTransportRequest *request = [[self.sut requestGenerators] nextRequest];
    
    // then
    XCTAssertEqualObjects(request, expectedRequest);
}

- (void)testThatItDoesNotGenerateALoginRequestWhenTheUserSessionHasNoCredentials
{
    // when
    ZMTransportRequest *request = [[self.sut requestGenerators] nextRequest];
    
    // then
    XCTAssertNil(request);
}

- (void)testThatItDoesNotGenerateALoginRequestWhenTheUserSessionIsLoggedIn
{
    // given
    [self.authenticationStatus setAuthenticationCookieData:[@"foo" dataUsingEncoding:NSUTF8StringEncoding]];
    
    // when
    ZMTransportRequest *request = [[self.sut requestGenerators] nextRequest];
    
    // then
    XCTAssertNil(request);
}


- (void)testThatItUsesCredentialsForVerificationResendRequests
{
    // given
    NSDictionary *payload = @{@"email": self.testEmailCredentials.email,
                              @"locale" : [NSLocale formattedLocaleIdentifier]};
    ZMTransportRequest *expectedRequest = [[ZMTransportRequest alloc] initWithPath:ZMResendVerificationURL method:ZMMethodPOST payload:payload authentication:ZMTransportRequestAuthNone];
    [self.authenticationStatus prepareForLoginWithCredentials:self.testEmailCredentials];
    [self.authenticationStatus didFailLoginWithEmailBecausePendingValidation];
    [ZMUserSessionRegistrationNotification resendValidationForRegistrationEmail];
    
    WaitForAllGroupsToBeEmpty(0.5);
    
    // when
    ZMTransportRequest *request = [[self.sut requestGenerators] nextRequest];
    
    // then
    XCTAssertEqualObjects(request, expectedRequest);
}

- (void)testThatItDoesNotUseSelfuserForVerificationResendRequests
{
    // given
    ZMUser *user = [ZMUser selfUserInContext:self.uiMOC];
    user.emailAddress = @"User@example.com";
    XCTAssertNotEqual(user.emailAddress, self.testEmailCredentials.email);
    [self.authenticationStatus prepareForLoginWithCredentials:self.testEmailCredentials];
    
    NSDictionary *payload = @{@"email": user.emailAddress};
    ZMTransportRequest *rejectedRequest = [[ZMTransportRequest alloc] initWithPath:ZMResendVerificationURL method:ZMMethodPOST payload:payload authentication:ZMTransportRequestAuthNone];
    
    // when
    ZMTransportRequest *request = [[self.sut requestGenerators] nextRequest];
    
    // then
    XCTAssertNotEqualObjects(request, rejectedRequest);
}


@end


@implementation  ZMLoginTranscoderTests (AuthenticationDelegate)

-(void)testThatItCallsAuthenticationSucceededOnLoginSucceedsWithEmail
{
    // given
    NSDictionary *content = @{@"access_token": @"61184561417968870ce708ed0c319206914bc56db444d01227a63f9b9849045f.1.1401213378.a.3bc5750a-b965-40f8-aff2-831e9b5ac2e9.846754296078244309",
                              @"expires_in": @604800,
                              @"token_type": @"Bearer"
                              };
    [self.authenticationStatus prepareForLoginWithCredentials:[ZMEmailCredentials credentialsWithEmail:@"foo@example.com" password:@"12345678"]];
    ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:content HTTPStatus:200 transportSessionError:nil];
    
    // when
    
    [self expectAuthenticationSucceedAfter:^{
        [[[self.sut requestGenerators] nextRequest] completeWithResponse:response];
        WaitForAllGroupsToBeEmpty(0.5);
    }];
}

-(void)testThatItCallsAuthenticationSucceededOnLoginSucceedsWithPhoneNumber
{
    // given
    NSDictionary *content = @{@"access_token": @"61184561417968870ce708ed0c319206914bc56db444d01227a63f9b9849045f.1.1401213378.a.3bc5750a-b965-40f8-aff2-831e9b5ac2e9.846754296078244309",
                              @"expires_in": @604800,
                              @"token_type": @"Bearer"
                              };
    [self.authenticationStatus prepareForLoginWithCredentials:[ZMPhoneCredentials credentialsWithPhoneNumber:@"+49123456789" verificationCode:@"123456"]];
    ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:content HTTPStatus:200 transportSessionError:nil];

    // when
    [self expectAuthenticationSucceedAfter:^{
        [[[self.sut requestGenerators] nextRequest] completeWithResponse:response];
        WaitForAllGroupsToBeEmpty(0.5);
    }];
}

-(void)testThatItCallsAuthenticationFailOnInvalidEmailCredentialsIfNotDuplicatedEmailRegistered
{
    // given
    NSDictionary *content = @{@"code":@403,
                              @"message":@"Invalid login credentials",
                              @"label":@"invalid-credentials"};
    [self.authenticationStatus prepareForLoginWithCredentials:[ZMEmailCredentials credentialsWithEmail:@"foo@example.com" password:@"12345678"]];
    ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:content HTTPStatus:403 transportSessionError:nil];
    
    // when
    [self expectAuthenticationFailedWithError:ZMUserSessionInvalidCredentials after:^{
        [[[self.sut requestGenerators] nextRequest] completeWithResponse:response];
        WaitForAllGroupsToBeEmpty(0.5);
    }];
}

-(void)testThatItCallsRegistrationFailOnInvalidEmailCredentialsIfDuplicatedEmailRegistered
{
    // given
    NSDictionary *content = @{@"code":@403,
                              @"message":@"Invalid login credentials",
                              @"label":@"invalid-credentials"};
    ZMCompleteRegistrationUser *user = [ZMCompleteRegistrationUser registrationUserWithEmail:@"foo@example.com" password:@"12345678"];
    user.name = @"foo";
    [self.authenticationStatus prepareForRegistrationOfUser:user];
    [self.authenticationStatus didFailRegistrationWithDuplicatedEmail];
    
    ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:content HTTPStatus:403 transportSessionError:nil];

    // when
    [self expectRegistrationFailedWithError:ZMUserSessionEmailIsAlreadyRegistered after:^{
        [[[self.sut requestGenerators] nextRequest] completeWithResponse:response];
        WaitForAllGroupsToBeEmpty(0.5);
    }];
}

-(void)testThatItCallsRegistrationFailOnInvalidPhoneNumberCredentialsIfNotDuplicatedPhoneNumberRegistered
{
    // given
    NSDictionary *content = @{@"code":@403,
                              @"message":@"Invalid login credentials",
                              @"label":@"invalid-credentials"};
    
    ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:content HTTPStatus:403 transportSessionError:nil];
    [self.authenticationStatus prepareForLoginWithCredentials:[ZMPhoneCredentials credentialsWithPhoneNumber:@"+4912345678" verificationCode:@"123456"]];
    
    // when
    [self expectAuthenticationFailedWithError:ZMUserSessionInvalidCredentials after:^{
        [[[self.sut requestGenerators] nextRequest] completeWithResponse:response];
        WaitForAllGroupsToBeEmpty(0.5);
    }];
}

-(void)testThatItCallsAuthenticationFailOnErrorResponseWithoutPayload
{
    // given
    [self.authenticationStatus prepareForLoginWithCredentials:[ZMPhoneCredentials credentialsWithPhoneNumber:@"+4912345678" verificationCode:@"123456"]];
    ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:nil HTTPStatus:403 transportSessionError:nil];

    // when
    [self expectAuthenticationFailedWithError:ZMUserSessionUnkownError after:^{
        [[[self.sut requestGenerators] nextRequest] completeWithResponse:response];
        WaitForAllGroupsToBeEmpty(0.5);
    }];
}

-(void)testThatItCallsAuthenticationFailOnPendingActivation
{
    // given
    NSDictionary *content = @{@"code":@403,
                              @"message":@"Account pending activation",
                              @"label":@"pending-activation"};
    [self.authenticationStatus prepareForLoginWithCredentials:[ZMEmailCredentials credentialsWithEmail:@"foo@example.com" password:@"12345678"]];
    ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:content HTTPStatus:403 transportSessionError:nil];
    
    // when
    [self expectAuthenticationFailedWithError:ZMUserSessionAccountIsPendingActivation after:^{
        [[[self.sut requestGenerators] nextRequest] completeWithResponse:response];
        WaitForAllGroupsToBeEmpty(0.5);
    }];
}

-(void)testThatItInvalidatesTheCredentialsOnLoginErrorWhenLoggingWithEmail
{
    // given
    NSDictionary *content = @{@"code":@403,
                              @"message":@"Invalid login credentials",
                              @"label":@"invalid-credentials"};
    
    ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:content HTTPStatus:403 transportSessionError:nil];
    [self.authenticationStatus prepareForLoginWithCredentials:[ZMEmailCredentials credentialsWithEmail:@"foo@example.com" password:@"12345678"]];
    
    // when
    [self expectAuthenticationFailedWithError:ZMUserSessionInvalidCredentials after:^{
        [[[self.sut requestGenerators] nextRequest] completeWithResponse:response];
        WaitForAllGroupsToBeEmpty(0.5);
    }];
    
    // then
    XCTAssertEqual(self.authenticationStatus.currentPhase, ZMAuthenticationPhaseUnauthenticated);
    XCTAssertNil(self.authenticationStatus.loginCredentials);

}

-(void)testThatItInvalidatesTheCredentialsOnLoginErrorWhenLoggingWithPhoneNumber
{
    // given
    NSDictionary *content = @{@"code":@403,
                              @"message":@"Invalid login credentials",
                              @"label":@"invalid-credentials"};
    [self.authenticationStatus prepareForLoginWithCredentials:[ZMPhoneCredentials credentialsWithPhoneNumber:@"+49123456789" verificationCode:@"12345678"]];
    ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:content HTTPStatus:403 transportSessionError:nil];
    
    // when
    [self expectAuthenticationFailedWithError:ZMUserSessionInvalidCredentials after:^{
        [[[self.sut requestGenerators] nextRequest] completeWithResponse:response];
        WaitForAllGroupsToBeEmpty(0.5);
    }];
    
    // then
    XCTAssertEqual(self.authenticationStatus.currentPhase, ZMAuthenticationPhaseUnauthenticated);
    XCTAssertNil(self.authenticationStatus.loginCredentials);
}

- (void)testThatItDoesNotDeleteCredentialsButSwitchesToStateAuthenticatedOnLoginSucceedsWithPhone
{
    // given
    NSDictionary *content = @{@"access_token": @"61184561417968870ce708ed0c319206914bc56db444d01227a63f9b9849045f.1.1401213378.a.3bc5750a-b965-40f8-aff2-831e9b5ac2e9.846754296078244309",
                              @"expires_in": @604800,
                              @"token_type": @"Bearer"
                              };
    [self.authenticationStatus prepareForLoginWithCredentials:[ZMPhoneCredentials credentialsWithPhoneNumber:@"+49123456789" verificationCode:@"12345678"]];
    ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:content HTTPStatus:200 transportSessionError:nil];
    
    // when
    [self expectAuthenticationSucceedAfter:^{
        [[[self.sut requestGenerators] nextRequest] completeWithResponse:response];
        [self.authenticationStatus setAuthenticationCookieData:[@"foo" dataUsingEncoding:NSUTF8StringEncoding]];
        WaitForAllGroupsToBeEmpty(0.5);
    }];
    
    // then
    XCTAssertEqual(self.authenticationStatus.currentPhase, ZMAuthenticationPhaseAuthenticated);
    XCTAssertNotNil(self.authenticationStatus.loginCredentials);

}

- (void)testThatItDoesNotDeleteCredentialsButSwitchesToStateAuthenticatedOnLoginSucceedsWithEmail
{
    // given
    NSDictionary *content = @{@"access_token": @"61184561417968870ce708ed0c319206914bc56db444d01227a63f9b9849045f.1.1401213378.a.3bc5750a-b965-40f8-aff2-831e9b5ac2e9.846754296078244309",
                              @"expires_in": @604800,
                              @"token_type": @"Bearer"
                              };
    [self.authenticationStatus prepareForLoginWithCredentials:[ZMEmailCredentials credentialsWithEmail:@"foo@example.com" password:@"12345678"]];
    ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:content HTTPStatus:200 transportSessionError:nil];
    
    // when
    [self expectAuthenticationSucceedAfter:^{
        [[[self.sut requestGenerators] nextRequest] completeWithResponse:response];
        [self.authenticationStatus setAuthenticationCookieData:[@"foo" dataUsingEncoding:NSUTF8StringEncoding]];
        WaitForAllGroupsToBeEmpty(0.5);
    }];
    
    // then
    XCTAssertEqual(self.authenticationStatus.currentPhase, ZMAuthenticationPhaseAuthenticated);
    XCTAssertNotNil(self.authenticationStatus.loginCredentials);

}

@end




@implementation ZMLoginTranscoderTests (EmailVerification)

- (void)testThatItResetsDidRegisterDuplicatedEmailAfterASuccessfulLoginRequest
{
    // given
    NSDictionary *content = @{@"access_token": @"61184561417968870ce708ed0c319206914bc56db444d01227a63f9b9849045f.1.1401213378.a.3bc5750a-b965-40f8-aff2-831e9b5ac2e9.846754296078244309",
                              @"expires_in": @604800,
                              @"token_type": @"Bearer"
                              };
    ZMCompleteRegistrationUser *user = [ZMCompleteRegistrationUser registrationUserWithEmail:@"foo@example.com" password:@"12345678"];
    user.name = @"foo";
    [self.authenticationStatus prepareForRegistrationOfUser:user];
    [self.authenticationStatus didFailRegistrationWithDuplicatedEmail];
    ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:content HTTPStatus:200 transportSessionError:nil];
    
    // when
    [self expectAuthenticationSucceedAfter:^{
        [[[self.sut requestGenerators] nextRequest] completeWithResponse:response];
        WaitForAllGroupsToBeEmpty(0.5);
    }];
    
    // then
    XCTAssertNotEqual(self.authenticationStatus.currentPhase, ZMAuthenticationPhaseWaitingForEmailVerification);
}

-(void)testThatOnPendingActivationItStartsTheTimedRequestWith5SecondsAndDoesNotResetCredentials
{
    // given
    NSDictionary *content = @{@"code":@403,
                              @"message":@"Account pending activation",
                              @"label":@"pending-activation"};
    
    ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:content HTTPStatus:403 transportSessionError:nil];
    ZMCompleteRegistrationUser *user = [ZMCompleteRegistrationUser registrationUserWithEmail:@"foo@example.com" password:@"12345678"];
    user.name = @"foo";
    [self.authenticationStatus prepareForRegistrationOfUser:user];
    [self.authenticationStatus didFailRegistrationWithDuplicatedEmail];
    
    // when
    [self expectAuthenticationFailedWithError:ZMUserSessionAccountIsPendingActivation after:^{
        [[[self.sut requestGenerators] nextRequest] completeWithResponse:response];
        WaitForAllGroupsToBeEmpty(0.5);
    }];
}

-(void)testThatOnPendingActivationItResetTheTimerToZeroWhenTheFollowingRequestIsCompleted
{
    // given
    DefaultPendingValidationLoginAttemptInterval = 0.2;
    NSDictionary *payloadPending = @{@"code":@403,
                              @"message":@"Account pending activation",
                              @"label":@"pending-activation"};
    
    NSDictionary *payloadValid = @{@"access_token": @"61184561417968870ce708ed0c319206914bc56db444d01227a63f9b9849045f.1.1401213378.a.3bc5750a-b965-40f8-aff2-831e9b5ac2e9.846754296078244309",
                              @"expires_in": @604800,
                              @"token_type": @"Bearer"
                              };
    
    ZMCompleteRegistrationUser *user = [ZMCompleteRegistrationUser registrationUserWithEmail:@"foo@example.com" password:@"12345678"];
    user.name = @"foo";
    [self.authenticationStatus prepareForRegistrationOfUser:user];
    [self.authenticationStatus didFailRegistrationWithDuplicatedEmail];
    ZMTransportResponse *responsePending = [ZMTransportResponse responseWithPayload:payloadPending HTTPStatus:403 transportSessionError:nil];
    ZMTransportResponse *responseValid = [ZMTransportResponse responseWithPayload:payloadValid HTTPStatus:200 transportSessionError:nil];
    
    // when
    [self expectAuthenticationFailedWithError:ZMUserSessionAccountIsPendingActivation after:^{
        [[[self.sut requestGenerators] nextRequest] completeWithResponse:responsePending];
        WaitForAllGroupsToBeEmpty(0.5);
    }];
    
    // when
    [self expectAuthenticationSucceedAfter:^{
        [[[self.sut requestGenerators] nextRequest] completeWithResponse:responseValid];
        WaitForAllGroupsToBeEmpty(0.5);
    }];
}

- (void)testThatItSendsAVerificationResendRequest_AuthenticationStatus;
{
    // given
    NSDictionary *expectedPayload = @{@"email" : self.testEmailCredentials.email,
                                      @"locale" : [NSLocale formattedLocaleIdentifier]};
    [self.authenticationStatus prepareForLoginWithCredentials:[ZMEmailCredentials credentialsWithEmail:self.testEmailCredentials.email password:@"12345678"]];
    [self.authenticationStatus didFailLoginWithEmailBecausePendingValidation];
    [ZMUserSessionRegistrationNotification resendValidationForRegistrationEmail];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // when
    ZMTransportRequest *request = [[self.sut requestGenerators] nextRequest];
    
    // then
    XCTAssertNotNil(request);
    XCTAssertFalse(request.needsAuthentication);
    XCTAssertEqualObjects(request.path, @"/activate/send");
    XCTAssertEqual(request.method, ZMMethodPOST);
    AssertEqualDictionaries(expectedPayload, (id) request.payload);
}


- (void)testThatItSendsAVerificationResendRequest_ClientRegistrationStatus;
{
    // given
    NSDictionary *expectedPayload = @{@"email" : self.testEmailCredentials.email,
                                      @"locale" : [NSLocale formattedLocaleIdentifier]};
    ZMEmailCredentials *credentials = [ZMEmailCredentials credentialsWithEmail:self.testEmailCredentials.email password:@"12345678"];

    [(ZMClientRegistrationStatus *)[[self.mockClientRegistrationStatus expect] andReturnValue:OCMOCK_VALUE(ZMClientRegistrationPhaseWaitingForEmailVerfication)] currentPhase];
    [[[self.mockClientRegistrationStatus expect] andReturn:credentials] emailCredentials];
    
    [ZMUserSessionRegistrationNotification resendValidationForRegistrationEmail];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // when
    ZMTransportRequest *request = [[self.sut requestGenerators] nextRequest];
    
    // then
    XCTAssertNotNil(request);
    XCTAssertFalse(request.needsAuthentication);
    XCTAssertEqualObjects(request.path, @"/activate/send");
    XCTAssertEqual(request.method, ZMMethodPOST);
    AssertEqualDictionaries(expectedPayload, (id) request.payload);
    [self.mockClientRegistrationStatus verify];
}

@end

