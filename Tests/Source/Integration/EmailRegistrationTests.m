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

extern NSTimeInterval DefaultPendingValidationLoginAttemptInterval;


@interface EmailRegistrationTests : IntegrationTestBase

@property (nonatomic) NSTimeInterval originalLoginTimerInterval;

@end

@implementation EmailRegistrationTests

- (void)setUp {
    self.originalLoginTimerInterval = DefaultPendingValidationLoginAttemptInterval;
    [super setUp];
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
    id authenticationObserverToken = [self.userSession addAuthenticationObserver:authenticationObserver];
    
    // expect
    [[authenticationObserver expect] authenticationDidSucceed];
    
    // when
    [self.userSession registerSelfUser:user];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertTrue(self.userSession.registeredOnThisDevice);
    [authenticationObserver verify];
    [self.userSession removeAuthenticationObserverForToken:authenticationObserverToken];
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
    [self.userSession registerSelfUser:user];
    WaitForAllGroupsToBeEmpty(0.5);
    [self recreateUserSessionAndWipeCache:NO];
    
    // then
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
    id authenticationObserverToken = [self.userSession addAuthenticationObserver:authenticationObserver];
    
    id registrationObserver = [OCMockObject mockForProtocol:@protocol(ZMRegistrationObserver)];
    id registrationObserverToken = [self.userSession addRegistrationObserver:registrationObserver];
    
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
    [self.userSession registerSelfUser:user];
    XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0.5]);
    [NSThread sleepForTimeInterval:2];
    
    // expect
    [[authenticationObserver expect] authenticationDidSucceed];
    
    // when
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        [session whiteListEmail:user.emailAddress];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertTrue(self.userSession.registeredOnThisDevice);
    [authenticationObserver verify];
    [self.userSession removeAuthenticationObserverForToken:authenticationObserverToken];
    [self.userSession removeRegistrationObserverForToken:registrationObserverToken];
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
    id authenticationObserverToken = [self.userSession addAuthenticationObserver:authenticationObserver];
    
    // expect
    [[authenticationObserver expect] authenticationDidSucceed];
    
    // when
    [self.userSession registerSelfUser:user];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    [authenticationObserver verify];
    [self.userSession removeAuthenticationObserverForToken:authenticationObserverToken];
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
    id registrationObserverToken = [self.userSession addRegistrationObserver:registrationObserver];
    
    // expect
    [[registrationObserver expect] registrationDidFail:[OCMArg checkWithBlock:^BOOL(NSError*error) {
        return error.code == ZMUserSessionEmailIsAlreadyRegistered;
    }]];
    
    // when
    [self.userSession start];
    [self.userSession registerSelfUser:user];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    [registrationObserver verify];
    [self.userSession removeRegistrationObserverForToken:registrationObserverToken];
    
}

- (void)testThatWeNotifyTheUIIfTheRegistrationFails
{
    // given
    NSString *password = @"";
    ZMCompleteRegistrationUser *user = [ZMCompleteRegistrationUser registrationUserWithEmail:@"thedude@example.com" password:password];
    user.name = @"Hans Müller";
    user.accentColorValue = ZMAccentColorStrongBlue;
    
    id registrationObserver = [OCMockObject mockForProtocol:@protocol(ZMRegistrationObserver)];
    id registrationObserverToken = [self.userSession addRegistrationObserver:registrationObserver];
    
    // expect
    [[registrationObserver expect] registrationDidFail:[OCMArg checkWithBlock:^BOOL(NSError*error) {
        return error.code == ZMUserSessionNeedsCredentials;
    }]];
    
    // when
    [self.userSession registerSelfUser:user];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    [registrationObserver verify];
    [self.userSession removeRegistrationObserverForToken:registrationObserverToken];
    
    
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
    id authenticationObserverToken = [self.userSession addAuthenticationObserver:authenticationObserver];
    
    // expect
    XCTestExpectation *loginFailExpectation = [self expectationWithDescription:@"Login fail (need to validate)"];
    [[[authenticationObserver stub] andDo:^(NSInvocation * ZM_UNUSED i) {
        [loginFailExpectation fulfill];
    }] authenticationDidFail:[OCMArg checkWithBlock:^BOOL(NSError *error) {
        return error.code == ZMUserSessionAccountIsPendingActivation;
    }]];
    
    // when
    [self.userSession registerSelfUser:user];
    WaitForAllGroupsToBeEmpty(1);
    
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

    [self.userSession removeAuthenticationObserverForToken:authenticationObserverToken];
    [self.userSession cancelWaitForEmailVerification]; // this cancels the requests
    XCTAssert([self waitForAllGroupsToBeEmptyWithTimeout:0.5]);
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
    id authenticationObserverToken = [self.userSession addAuthenticationObserver:authenticationObserver];
    
    // expect
    [[authenticationObserver stub] authenticationDidFail:OCMOCK_ANY];
    
    // when
    [self.userSession registerSelfUser:user];
    WaitForAllGroupsToBeEmpty(1);

    // wait for more attempts
    [NSThread sleepForTimeInterval:0.5];
    
    // and when
    [self.userSession cancelWaitForEmailVerification];
    [self.mockTransportSession resetReceivedRequests];
    
    // wait for more
    [NSThread sleepForTimeInterval:0.8];
    
    // then
    XCTAssertLessThanOrEqual(self.mockTransportSession.receivedRequests.count, 1u);
    XCTAssert([self waitForAllGroupsToBeEmptyWithTimeout:0.5]);

    [authenticationObserver verify];
    [self.userSession removeAuthenticationObserverForToken:authenticationObserverToken];
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
    id authenticationObserverToken = [self.userSession addAuthenticationObserver:authenticationObserver];
    
    // expect
    [[authenticationObserver stub] authenticationDidFail:[OCMArg checkWithBlock:^BOOL(NSError *error) {
        XCTAssertEqual(error.code, (NSInteger) ZMUserSessionAccountIsPendingActivation);
        return YES;
    }]];
    
    // then
    [self.userSession registerSelfUser:user];
    WaitForAllGroupsToBeEmpty(0.5);
    
    [self.mockTransportSession resetReceivedRequests];
    
    // when
    [self.userSession resendRegistrationVerificationEmail];
    [NSThread sleepForTimeInterval:0.5];
    [self.userSession cancelWaitForEmailVerification];
    WaitForAllGroupsToBeEmpty(0.1 + DefaultPendingValidationLoginAttemptInterval);
    
    
    // then
    NSString *expectedPath = @"/activate/send";
    
    XCTAssertGreaterThanOrEqual(self.mockTransportSession.receivedRequests.count, 1u);
    ZMTransportRequest *request = self.mockTransportSession.receivedRequests.firstObject;
    XCTAssertEqualObjects(request.path, expectedPath);
    
    [authenticationObserver verify];
    [self.userSession removeAuthenticationObserverForToken:authenticationObserverToken];
}



@end
