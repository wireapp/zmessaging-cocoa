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
    
    PostLoginAuthenticationNotificationRecorder *recorder = [[PostLoginAuthenticationNotificationRecorder alloc] initWithDispatchGroup:self.dispatchGroup];
    
    // when
    XCTAssertNotNil(self.unauthenticatedSession);
    [self.unauthenticatedSession registerUser:user];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertTrue(self.userSession.registeredOnThisDevice);
    XCTAssertEqual(recorder.notifications.count, 1lu);
    XCTAssertEqual(recorder.notifications.firstObject.event, PostLoginAuthenticationEventObjCClientRegistrationDidSucceed);
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
    
    // expect
    XCTestExpectation *loginFailExpectation = [self expectationWithDescription:@"Login fail (need to validate)"];
    id preLoginToken = [[PreLoginAuthenticationObserverToken alloc] initWithAuthenticationStatus:self.unauthenticatedSession.authenticationStatus handler:^(enum PreLoginAuthenticationEventObjc event, NSError *error) {
        if (event == PreLoginAuthenticationEventObjcAuthenticationDidFail && error.code == ZMUserSessionAccountIsPendingActivation) {
            [loginFailExpectation fulfill];
        }
    }];
    
    XCTestExpectation *emailVerifiedExpectation = [self expectationWithDescription:@"Email was verified"];
    id registrationObserverToken = [ZMUserSessionRegistrationNotification addObserverInSession:self.unauthenticatedSession withBlock:^(ZMUserSessionRegistrationNotificationType type, NSError *error) {
        NOT_USED(error);
        
        if (type == ZMRegistrationNotificationEmailVerificationDidSucceed) {
            [emailVerifiedExpectation fulfill];
        }
    }];
    
    // when
    [self.unauthenticatedSession registerUser:user];
    XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0.5]);
    preLoginToken = nil;
    registrationObserverToken = nil;
    
    PostLoginAuthenticationNotificationRecorder *recorder = [[PostLoginAuthenticationNotificationRecorder alloc] initWithDispatchGroup:self.dispatchGroup];
    
    // expect
    XCTestExpectation *loginSuccessful = [self expectationWithDescription:@"Login succeeded"];
    preLoginToken = [[PreLoginAuthenticationObserverToken alloc] initWithAuthenticationStatus:self.unauthenticatedSession.authenticationStatus handler:^(enum PreLoginAuthenticationEventObjc event, NSError *error) {
        NOT_USED(error);
        if (event == PreLoginAuthenticationEventObjcAuthenticationDidSucceed) {
            [loginSuccessful fulfill];
        }
    }];
    
    // when
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        [session whiteListEmail:user.emailAddress];
    }];
    
    // then
    XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0.5]);
    WaitForAllGroupsToBeEmpty(0.5);
    XCTAssertTrue(self.userSession.registeredOnThisDevice);
    XCTAssertEqual(recorder.notifications.count, 1lu);
    XCTAssertEqual(recorder.notifications.firstObject.event, PostLoginAuthenticationEventObjCClientRegistrationDidSucceed);
}

- (void)testThatIfRegisteringWithADuplicateEmailWeDoNotLogInIfWeHaveTheRightPassword
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
    
    PostLoginAuthenticationNotificationRecorder *recorder = [[PostLoginAuthenticationNotificationRecorder alloc] initWithDispatchGroup:self.dispatchGroup];
    
    // when
    [self.unauthenticatedSession registerUser:user];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(recorder.notifications.count, 0lu);
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
    registrationObserverToken = nil;
    
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
    registrationObserverToken = nil;
    
    
}

- (void)testThatWhenRegisteringAndNeedToWaitForEmailValidationWeKeepTryingToLogInUntilWeSucceed
{
    
    DefaultPendingValidationLoginAttemptInterval = 0.2;
    NSString *password = @"No one will ever guess this";
    
    // given
    ZMCompleteRegistrationUser *user = [ZMCompleteRegistrationUser registrationUserWithEmail:@"thedude@example.com" password:password];
    user.name = @"Hans Müller";
    user.accentColorValue = ZMAccentColorStrongBlue;
    
    __block BOOL loginHasFailed = NO;
    id preLoginToken = [[PreLoginAuthenticationObserverToken alloc] initWithAuthenticationStatus:self.unauthenticatedSession.authenticationStatus handler:^(enum PreLoginAuthenticationEventObjc event, NSError *error) {
        if (event == PreLoginAuthenticationEventObjcAuthenticationDidFail && error.code == ZMUserSessionAccountIsPendingActivation) {
            loginHasFailed = YES;
        }
    }];
    
    
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
    XCTAssertTrue(loginHasFailed);
    preLoginToken = nil;
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
    
    // expect
    XCTestExpectation *waitingForEmailVerification = [self expectationWithDescription:@"waiting for email to be verified"];
    id preLoginToken = [[PreLoginAuthenticationObserverToken alloc] initWithAuthenticationStatus:self.unauthenticatedSession.authenticationStatus handler:^(enum PreLoginAuthenticationEventObjc event, NSError *error) {
        NOT_USED(error);
        
        if (event == PreLoginAuthenticationEventObjcAuthenticationDidFail) {
            [waitingForEmailVerification fulfill];
        }
    }];
    
    // when
    [self.unauthenticatedSession registerUser:user];
    XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0.5]);
    [self.mockTransportSession resetReceivedRequests];
    
    [self spinMainQueueWithTimeout:0.5]; // login request complete
    
    // and when

    [self.unauthenticatedSession cancelWaitForEmailVerification];
    [self.mockTransportSession resetReceivedRequests];
    
    
    [self spinMainQueueWithTimeout:0.5]; // wait for more login attemps
    
    // then
    XCTAssertLessThanOrEqual(self.mockTransportSession.receivedRequests.count, 1u);
    XCTAssert([self waitForAllGroupsToBeEmptyWithTimeout:0.5]);
    preLoginToken = nil;
}

- (void)testThatAVerificationResendRequestIsAddedWhenCallingResendVerificationEmail
{
    // given
    DefaultPendingValidationLoginAttemptInterval = 0.2;
    NSString *password = @"thePa$$w0rd";
    ZMCompleteRegistrationUser *user = [ZMCompleteRegistrationUser registrationUserWithEmail:@"thedude@example.com" password:password];
    user.name = @"Hans Müller";
    user.accentColorValue = ZMAccentColorStrongBlue;
    
    // expect
    __block BOOL loginHasFailed = NO;
    id preLoginToken = [[PreLoginAuthenticationObserverToken alloc] initWithAuthenticationStatus:self.unauthenticatedSession.authenticationStatus handler:^(enum PreLoginAuthenticationEventObjc event, NSError *error) {
        if (event == PreLoginAuthenticationEventObjcAuthenticationDidFail && error.code == ZMUserSessionAccountIsPendingActivation) {
            loginHasFailed = YES;
        }
    }];
    
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
    
    XCTAssertTrue(loginHasFailed);
    preLoginToken = nil;
}

@end
