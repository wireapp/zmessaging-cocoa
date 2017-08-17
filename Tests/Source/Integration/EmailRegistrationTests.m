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

#import "ZMUserSession.h"
#import "NSError+ZMUserSession.h"
#import "ZMCredentials.h"
#import <WireSyncEngine/WireSyncEngine-Swift.h>
#import "WireSyncEngine_iOS_Tests-Swift.h"

extern NSTimeInterval DefaultPendingValidationLoginAttemptInterval;


@interface EmailRegistrationTests : IntegrationTest

@property (nonatomic) NSTimeInterval originalLoginTimerInterval;

@end

@implementation EmailRegistrationTests

- (void)setUp {
    self.originalLoginTimerInterval = DefaultPendingValidationLoginAttemptInterval;
    [super setUp];
    XCTAssert([self waitWithTimeout:0.5 verificationBlock:^BOOL{
        return nil != self.unauthenticatedSession;
    }]);
}

- (void)tearDown {
    
    DefaultPendingValidationLoginAttemptInterval = self.originalLoginTimerInterval;
    [super tearDown];
}

- (void)testThatWeCanRegisterAndLogInImmediatelyIfTheUserIsWhiteListed
{
    // given
    ZMCompleteRegistrationUser *user = [ZMCompleteRegistrationUser registrationUserWithEmail:@"thedude@example.com" password:@"foo23342"];
    user.name = @"Hans Müller";
    user.accentColorValue = ZMAccentColorStrongBlue;
    
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        [session whiteListEmail:user.emailAddress];
    }];
    
    id authenticationObserver = [OCMockObject mockForProtocol:@protocol(ZMAuthenticationObserver)];
    id authenticationObserverToken = [ZMUserSessionAuthenticationNotification addObserver:authenticationObserver];
    
    // expect
    [[authenticationObserver expect] authenticationDidSucceed];
    [[authenticationObserver expect] clientRegistrationDidSucceed]; // client registration
    
    // when
    XCTAssertNotNil(self.unauthenticatedSession);
    [self.unauthenticatedSession registerUser:user];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertTrue(self.userSession.registeredOnThisDevice);
    [authenticationObserver verify];
    [ZMUserSessionAuthenticationNotification removeObserverForToken:authenticationObserverToken];
}

- (void)testThatWhenRegisterAndRestartingTheAppItRemembersItWasRegisteredOnThisDevice
{
    // given
    ZMCompleteRegistrationUser *user = [ZMCompleteRegistrationUser registrationUserWithEmail:@"thedude@example.com" password:@"foo23342"];
    user.name = @"Hans Müller";
    user.accentColorValue = ZMAccentColorStrongBlue;
    
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        [session whiteListEmail:user.emailAddress];
    }];
    
    // when
    [self.unauthenticatedSession registerUser:user];
    WaitForAllGroupsToBeEmpty(0.5);
    [self recreateSessionManager];
    WaitForAllGroupsToBeEmpty(0.5);

    // then
    XCTAssertNotNil(self.userSession);
    XCTAssertTrue(self.userSession.registeredOnThisDevice);
}

- (void)testThatWeCanRegisterAndWaitForTheUserToVerifyTheEmail
{
    // given
    DefaultPendingValidationLoginAttemptInterval = 0.2;
    NSString *password = @"thePa$$w0rd";
    
    ZMCompleteRegistrationUser *user = [ZMCompleteRegistrationUser registrationUserWithEmail:@"thedude@example.com" password:password];
    user.name = @"Hans Müller";
    user.accentColorValue = ZMAccentColorStrongBlue;
    
    id authenticationObserver = [OCMockObject mockForProtocol:@protocol(ZMAuthenticationObserver)];
    id authenticationObserverToken = [ZMUserSessionAuthenticationNotification addObserver:authenticationObserver];
    
    id registrationObserver = [OCMockObject mockForProtocol:@protocol(ZMRegistrationObserver)];
    id registrationObserverToken = [self.unauthenticatedSession addRegistrationObserver:registrationObserver];
    
    // expect
    __block NSUInteger numFailedLogins = 0;
    XCTestExpectation *loginFailExpectation = [self expectationWithDescription:@"Login fail (need to validate)"];
    [[[authenticationObserver stub] andDo:^(NSInvocation * ZM_UNUSED i) {
        [loginFailExpectation fulfill];
    }] authenticationDidFail:[OCMArg checkWithBlock:^BOOL(NSError *error) {
        ++numFailedLogins;
        return error.code == ZMUserSessionAccountIsPendingActivation;
    }]];
    [[registrationObserver expect] emailVerificationDidSucceed];
    
    // when
    [self.unauthenticatedSession registerUser:user];
    XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0.5]);
    [NSThread sleepForTimeInterval:2];
    
    // expect
    [[authenticationObserver expect] authenticationDidSucceed];
    [[authenticationObserver expect] clientRegistrationDidSucceed]; // client registration
    
    // when
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        [session whiteListEmail:user.emailAddress];
    }];

    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertTrue(self.userSession.registeredOnThisDevice);
    [authenticationObserver verify];
    [ZMUserSessionAuthenticationNotification removeObserverForToken:authenticationObserverToken];
    [self.unauthenticatedSession removeRegistrationObserver:registrationObserverToken];
    [registrationObserver verify];
}

- (void)testThatIfRegisteringWithADuplicateEmailWeLogInIfWeHaveTheRightPassword
{
    // given
    NSString *password = @"thePa$$w0rd";
    ZMCompleteRegistrationUser *user = [ZMCompleteRegistrationUser registrationUserWithEmail:@"thedude@example.com" password:password];
    user.name = @"Hans Müller";
    user.accentColorValue = ZMAccentColorStrongBlue;
    
    
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        MockUser *previousUser = [session insertUserWithName:@"Fabio"];
        previousUser.email = user.emailAddress;
        previousUser.password = password;
    }];
    
    id authenticationObserver = [OCMockObject mockForProtocol:@protocol(ZMAuthenticationObserver)];
    id authenticationObserverToken = [ZMUserSessionAuthenticationNotification addObserver:authenticationObserver];
    
    // expect
    [[authenticationObserver expect] authenticationDidSucceed];
    [[authenticationObserver expect] clientRegistrationDidSucceed]; // client registration
    
    // when
    [self.unauthenticatedSession registerUser:user];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    [authenticationObserver verify];
    [ZMUserSessionAuthenticationNotification removeObserverForToken:authenticationObserverToken];
}

- (void)testThatIfRegisteringWithADuplicateEmailWeDoNotLogInIfWeHaveTheWrongPassword
{
    // given
    NSString *password = @"thePa$$w0rd";
    ZMCompleteRegistrationUser *user = [ZMCompleteRegistrationUser registrationUserWithEmail:@"thedude@example.com" password:password];
    user.name = @"Hans Müller";
    user.accentColorValue = ZMAccentColorStrongBlue;
    
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        MockUser *previousUser = [session insertUserWithName:@"Fabio"];
        previousUser.email = user.emailAddress;
        previousUser.password = @"nope!";
    }];
    
    id registrationObserver = [OCMockObject mockForProtocol:@protocol(ZMRegistrationObserver)];
    id registrationObserverToken = [self.unauthenticatedSession addRegistrationObserver:registrationObserver];
    
    // expect
    [[registrationObserver expect] registrationDidFail:[OCMArg checkWithBlock:^BOOL(NSError*error) {
        return error.code == ZMUserSessionEmailIsAlreadyRegistered;
    }]];
    
    // when
    [self.unauthenticatedSession registerUser:user];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    [registrationObserver verify];
    [self.unauthenticatedSession removeRegistrationObserver:registrationObserverToken];
    
}

- (void)testThatWeNotifyTheUIIfTheRegistrationFails
{
    // given
    NSString *password = @"";
    ZMCompleteRegistrationUser *user = [ZMCompleteRegistrationUser registrationUserWithEmail:@"thedude@example.com" password:password];
    user.name = @"Hans Müller";
    user.accentColorValue = ZMAccentColorStrongBlue;
    
    id registrationObserver = [OCMockObject mockForProtocol:@protocol(ZMRegistrationObserver)];
    id registrationObserverToken = [self.unauthenticatedSession addRegistrationObserver:registrationObserver];
    
    // expect
    [[registrationObserver expect] registrationDidFail:[OCMArg checkWithBlock:^BOOL(NSError*error) {
        return error.code == ZMUserSessionNeedsCredentials;
    }]];
    
    // when
    [self.unauthenticatedSession registerUser:user];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    [registrationObserver verify];
    [self.unauthenticatedSession removeRegistrationObserver:registrationObserverToken];
    
    
}

- (void)testThatWhenRegisteringAndNeedToWaitForEmailValidationWeKeepTryingToLogInUntilWeSucceed
{
    
    DefaultPendingValidationLoginAttemptInterval = 0.2;
    NSString *password = @"No one will ever guess this";
    
    // given
    ZMCompleteRegistrationUser *user = [ZMCompleteRegistrationUser registrationUserWithEmail:@"thedude@example.com" password:password];
    user.name = @"Hans Müller";
    user.accentColorValue = ZMAccentColorStrongBlue;
    
    id authenticationObserver = [OCMockObject mockForProtocol:@protocol(ZMAuthenticationObserver)];
    id authenticationObserverToken = [ZMUserSessionAuthenticationNotification addObserver:authenticationObserver];
    
    // expect
    XCTestExpectation *loginFailExpectation = [self expectationWithDescription:@"Login fail (need to validate)"];
    [[[authenticationObserver stub] andDo:^(NSInvocation * ZM_UNUSED i) {
        [loginFailExpectation fulfill];
    }] authenticationDidFail:[OCMArg checkWithBlock:^BOOL(NSError *error) {
        return error.code == ZMUserSessionAccountIsPendingActivation;
    }]];
    
    // when
    [self.unauthenticatedSession registerUser:user];
    
    // wait for more attempts
    [self spinMainQueueWithTimeout:1];
    
    // then
    NSString *expectedPath = @"/login?persist=true";
    NSUInteger count = 0;
    for(ZMTransportRequest *request in self.mockTransportSession.receivedRequests) {
        if([request.path isEqualToString:expectedPath]) {
            ++count;
        }
    }
    XCTAssertGreaterThan(count, 3u);
    
    [authenticationObserver verify];

    [ZMUserSessionAuthenticationNotification removeObserverForToken:authenticationObserverToken];
    [self.unauthenticatedSession cancelWaitForEmailVerification]; // this cancels the requests
    XCTAssert([self waitForAllGroupsToBeEmptyWithTimeout:0.1]);
}


- (void)testThatWhenRegisteringAndNeedToWaitForEmailValidationWeCanCancelTheWait
{
    // given
    DefaultPendingValidationLoginAttemptInterval = 0.2;
    NSString *password = @"thePa$$w0rd";
    ZMCompleteRegistrationUser *user = [ZMCompleteRegistrationUser registrationUserWithEmail:@"thedude@example.com" password:password];
    user.name = @"Hans Müller";
    user.accentColorValue = ZMAccentColorStrongBlue;
    
    id authenticationObserver = [OCMockObject mockForProtocol:@protocol(ZMAuthenticationObserver)];
    id authenticationObserverToken = [ZMUserSessionAuthenticationNotification addObserver:authenticationObserver];
    
    // expect
    [[authenticationObserver stub] authenticationDidFail:OCMOCK_ANY];
    
    // when
    [self.unauthenticatedSession registerUser:user];

    // wait for more attempts
    XCTAssert([self waitWithTimeout:0.5 verificationBlock:^BOOL{
        return self.mockTransportSession.receivedRequests.count > 1;
    }]);
    
    // and when

    [self.unauthenticatedSession cancelWaitForEmailVerification];
    [self.mockTransportSession resetReceivedRequests];
    
    // wait for more
    [NSThread sleepForTimeInterval:0.8];
    
    // then
    XCTAssertLessThanOrEqual(self.mockTransportSession.receivedRequests.count, 1u);
    XCTAssert([self waitForAllGroupsToBeEmptyWithTimeout:0.5]);

    [authenticationObserver verify];
    [ZMUserSessionAuthenticationNotification removeObserverForToken:authenticationObserverToken];
}

- (void)testThatAVerificationResendRequestIsAddedWhenCallingResendVerificationEmail
{
    // given
    DefaultPendingValidationLoginAttemptInterval = 0.2;
    NSString *password = @"thePa$$w0rd";
    ZMCompleteRegistrationUser *user = [ZMCompleteRegistrationUser registrationUserWithEmail:@"thedude@example.com" password:password];
    user.name = @"Hans Müller";
    user.accentColorValue = ZMAccentColorStrongBlue;
    
    id authenticationObserver = [OCMockObject mockForProtocol:@protocol(ZMAuthenticationObserver)];
    id authenticationObserverToken = [ZMUserSessionAuthenticationNotification addObserver:authenticationObserver];
    
    // expect
    [[authenticationObserver stub] authenticationDidFail:[OCMArg checkWithBlock:^BOOL(NSError *error) {
        XCTAssertEqual(error.code, (NSInteger) ZMUserSessionAccountIsPendingActivation);
        return YES;
    }]];
    
    // then
    [self.unauthenticatedSession registerUser:user];
    
    [self spinMainQueueWithTimeout:0.5]; // Wait for registration request to complete
    
    [self.mockTransportSession resetReceivedRequests];
    
    // when
    [self.unauthenticatedSession resendRegistrationVerificationEmail];
    
    [self spinMainQueueWithTimeout:0.5]; // Let verification email resend request complete
    
    [self.unauthenticatedSession cancelWaitForEmailVerification];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    NSString *expectedPath = @"/activate/send";
    
    XCTAssertGreaterThanOrEqual(self.mockTransportSession.receivedRequests.count, 1u);
    ZMTransportRequest *request = self.mockTransportSession.receivedRequests.firstObject;
    XCTAssertEqualObjects(request.path, expectedPath);
    
    [authenticationObserver verify];
    [ZMUserSessionAuthenticationNotification removeObserverForToken:authenticationObserverToken];
}

@end
