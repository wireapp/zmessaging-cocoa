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
#import "NSError+ZMUserSession.h"
#import "NSError+ZMUserSessionInternal.h"
#import "ZMSearchDirectory.h"

#import "ZMUserSession.h"
#import "ZMUserSession+Authentication.h"
#import "ZMUserSession+Registration.h"

#import "ZMCredentials.h"
  
@interface UserProfileTests : IntegrationTestBase

@end

@implementation UserProfileTests

- (void)testThatWeCanChangeUsernameAndAccentColorForSelfUser
{

    NSString *name = @"My New Name";
    ZMAccentColor accentColor = ZMAccentColorSoftPink;
    {
        // Create a UI context
        XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
        // Change the name & save
        ZMUser<ZMEditableUser> *selfUser = [ZMUser selfUserInUserSession:self.userSession];
        
        // sanity check
        XCTAssertNotEqual(selfUser.accentColorValue, accentColor);
        
        selfUser.name = name;
        selfUser.accentColorValue = accentColor;
        
        [self.userSession saveOrRollbackChanges];
        // Wait for merge ui->sync to be done
        WaitForEverythingToBeDone();
        
        XCTAssertEqual(selfUser.accentColorValue, accentColor);
    }
    
    // Tears down context(s) &
    // Re-create contexts
    [self recreateUserSessionAndWipeCache:YES];
    
    // Wait for sync to be done
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    
    // Check that user is updated:
    {
        // Get the self user
        ZMUser<ZMEditableUser> *selfUser = [ZMUser selfUserInUserSession:self.userSession];
        XCTAssertEqualObjects(selfUser.name, name);
        XCTAssertEqual(selfUser.accentColorValue, accentColor);
    }

    
}

- (void)testThatItNotifiesObserverWhenWeChangeAccentColorForSelfUser
{
    ZMAccentColor accentColor = ZMAccentColorSoftPink;
    
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);

    ZMUser<ZMEditableUser> *selfUser = [ZMUser selfUserInUserSession:self.userSession];
    XCTAssertNotEqual(selfUser.accentColorValue, accentColor);
    
    UserChangeObserver *observer = [[UserChangeObserver alloc] initWithUser:selfUser];
    
    // when
    selfUser.accentColorValue = accentColor;
    [self.userSession saveOrRollbackChanges];
    WaitForEverythingToBeDone();
    
    // then
    NSArray *notifications = observer.notifications;
    XCTAssertEqual(notifications.count, 1u);
    
    UserChangeInfo *note = notifications.firstObject;
    XCTAssertNotNil(note);
    XCTAssertTrue(note.accentColorValueChanged);
    
    XCTAssertEqual(selfUser.accentColorValue, accentColor);
    [observer tearDown];
}

@end



@implementation UserProfileTests (Onboarding)


- (void)registerUser
{
    NSString *password = @"thePa$$w0rd";
    ZMCompleteRegistrationUser *user = [ZMCompleteRegistrationUser registrationUserWithEmail:@"thedude@example.com" password:password];
    user.name = @"Hans Müller";
    user.accentColorValue = ZMAccentColorStrongBlue;
    
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        [session whiteListEmail:user.emailAddress];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
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

@end



@implementation UserProfileTests (ChangeEmailAndPhoneAtSecondLogin)

- (void)testThatItCanSetsThePhoneAtTheSecondLogin
{
    // given
    NSString *phone = @"+9912312452";

    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    [self.mockTransportSession resetReceivedRequests];

    XCTAssertFalse(self.userSession.registeredOnThisDevice);
    
    ZMUser *selfUser = [ZMUser selfUserInUserSession:self.userSession];
    XCTAssertEqualObjects(selfUser.phoneNumber, @"");
    
    id userObserver = [OCMockObject mockForProtocol:@protocol(ZMUserObserver)];
    id userObserverToken = [ZMUser addUserObserver:userObserver forUsers:@[selfUser] inUserSession:self.userSession];
    
    id editableUserObserver = [OCMockObject mockForProtocol:@protocol(UserProfileUpdateObserver)];
    id editableUserObserverToken = [self.userSession.userProfile addObserver:editableUserObserver];
    
    [(id<ZMUserObserver>)[userObserver expect] userDidChange:OCMOCK_ANY]; // <- DONE: when receiving this, I know that the phone number was set
    
    // expect
    XCTestExpectation *phoneNumberVerificationCodeExpectation = [self expectationWithDescription:@"phoneNumberVerificationCodeExpectation"];
    [[[editableUserObserver expect] andDo:^(NSInvocation *inv) {
        NOT_USED(inv);
        [phoneNumberVerificationCodeExpectation fulfill];
    }] phoneNumberVerificationCodeRequestDidSucceed];
    
    // when
    [self.userSession.userProfile requestPhoneVerificationCodeWithPhoneNumber:phone]; // <- STEP 1
    
    if(![self waitForCustomExpectationsWithTimeout:0.5]) {
        XCTFail(@"phoneNumberVerificationCodeExpectation");
        return;
    }
    
    // and when
    [self.userSession.userProfile requestPhoneNumberChangeWithCredentials:[ZMPhoneCredentials credentialsWithPhoneNumber:phone verificationCode:self.mockTransportSession.phoneVerificationCodeForUpdatingProfile]];  // <- STEP 2
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(self.mockTransportSession.receivedRequests.count, 2u);
    XCTAssertEqualObjects(selfUser.phoneNumber, phone);
    
    // after
    [ZMUser removeUserObserverForToken:userObserverToken];
    [self.userSession.userProfile removeObserverWithToken:editableUserObserverToken];

}

- (void)testThatItIsNotifiedWhenItConfirmsWithTheWrongCode
{
    // given
    NSString *phone = @"+9912312452";
    
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    [self.mockTransportSession resetReceivedRequests];
    
    XCTAssertFalse(self.userSession.registeredOnThisDevice);
    
    ZMUser *selfUser = [ZMUser selfUserInUserSession:self.userSession];
    XCTAssertEqualObjects(selfUser.phoneNumber, @"");
    
    id userObserver = [OCMockObject mockForProtocol:@protocol(UserProfileUpdateObserver)];
    id token = [self.userSession.userProfile addObserver:userObserver];
    
    //expect
    [[userObserver expect] phoneNumberVerificationCodeRequestDidSucceed];
    [[userObserver expect] phoneNumberChangeDidFail:OCMOCK_ANY];
    
    // when
    [self.userSession.userProfile requestPhoneVerificationCodeWithPhoneNumber:phone];
    WaitForAllGroupsToBeEmpty(0.5);
    [self.userSession.userProfile requestPhoneNumberChangeWithCredentials:[ZMPhoneCredentials credentialsWithPhoneNumber:phone verificationCode:self.mockTransportSession.invalidPhoneVerificationCode]];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(self.mockTransportSession.receivedRequests.count, 2u);
    
    // after
    [self.userSession.userProfile removeObserverWithToken:token];
}

- (void)testThatItIsNotifiedWhenItFailsToRequestAVerificationCode
{
    // given
    NSString *phone = @"+9912312452";
    
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    [self.mockTransportSession resetReceivedRequests];
    
    XCTAssertFalse(self.userSession.registeredOnThisDevice);
    
    ZMUser *selfUser = [ZMUser selfUserInUserSession:self.userSession];
    XCTAssertEqualObjects(selfUser.phoneNumber, @"");
    
    id userObserver = [OCMockObject mockForProtocol:@protocol(UserProfileUpdateObserver)];
    id token = [self.userSession.userProfile addObserver:userObserver];
    
    // expect
    [[userObserver expect] phoneNumberVerificationCodeRequestDidFail:[OCMArg isNotNil]];
    
    self.mockTransportSession.responseGeneratorBlock = ^ZMTransportResponse*(ZMTransportRequest *request) {
        if([request.path isEqualToString:@"/self/phone"]) {
            return [ZMTransportResponse responseWithPayload:nil HTTPStatus:400 transportSessionError:nil];
        }
        return nil;
    };
    
    
    // when
    [self.userSession.userProfile requestPhoneVerificationCodeWithPhoneNumber:phone];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(self.mockTransportSession.receivedRequests.count, 1u);
    
    // after
    [self.userSession.userProfile removeObserverWithToken:token];
}


- (void)testThatItIsNotifiedWhenItFailsToRequestAVerificationCodeBecausePhoneNumberIsInUse
{
    // given
    NSString *phone = @"+9912312452";
    
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    [self.mockTransportSession resetReceivedRequests];
    
    XCTAssertFalse(self.userSession.registeredOnThisDevice);
    
    ZMUser *selfUser = [ZMUser selfUserInUserSession:self.userSession];
    XCTAssertEqualObjects(selfUser.phoneNumber, @"");
    
    id userObserver = [OCMockObject mockForProtocol:@protocol(UserProfileUpdateObserver)];
    id token = [self.userSession.userProfile addObserver:userObserver];
    
    // expect
    [[userObserver expect] phoneNumberVerificationCodeRequestDidFail:[OCMArg checkWithBlock:^BOOL(NSError *error) {
        return error.code == ZMUserSessionPhoneNumberIsAlreadyRegistered && [error.domain isEqualToString:ZMUserSessionErrorDomain];
    }]];
    
    self.mockTransportSession.responseGeneratorBlock = ^ZMTransportResponse*(ZMTransportRequest *request) {
        if([request.path isEqualToString:@"/self/phone"]) {
            return [ZMTransportResponse responseWithPayload:@{@"label":@"key-exists"} HTTPStatus:409 transportSessionError:nil];
        }
        return nil;
    };
    
    
    // when
    [self.userSession.userProfile requestPhoneVerificationCodeWithPhoneNumber:phone];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(self.mockTransportSession.receivedRequests.count, 1u);
    
    // after
    [self.userSession.userProfile removeObserverWithToken:token];
}


- (void)testThatItGetsInvalidPhoneNumberErrorWhenItFailsToRequestAVerificationCodeWithBadRequestResponse
{
    // given
    NSString *phone = @"+9912312452";
    
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    [self.mockTransportSession resetReceivedRequests];
    
    XCTAssertFalse(self.userSession.registeredOnThisDevice);
    
    ZMUser *selfUser = [ZMUser selfUserInUserSession:self.userSession];
    XCTAssertEqualObjects(selfUser.phoneNumber, @"");
    
    id userObserver = [OCMockObject mockForProtocol:@protocol(UserProfileUpdateObserver)];
    id token = [self.userSession.userProfile addObserver:userObserver];
    
    // expect
    [[userObserver expect] phoneNumberVerificationCodeRequestDidFail:[OCMArg isNotNil]];
    
    self.mockTransportSession.responseGeneratorBlock = ^ZMTransportResponse*(ZMTransportRequest *request) {
        if([request.path isEqualToString:@"/self/phone"]) {
            return [ZMTransportResponse responseWithPayload:@{@"label": @"bad-request"} HTTPStatus:400 transportSessionError:nil];
        }
        return nil;
    };
    
    
    // when
    [self.userSession.userProfile requestPhoneVerificationCodeWithPhoneNumber:phone];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(self.mockTransportSession.receivedRequests.count, 1u);

    // after
    [self.userSession.userProfile removeObserverWithToken:token];
}

- (void)testThatItGetsInvalidPhoneNumberErrorWhenItFailsToRequestAVerificationCodeWithInvalidPhoneResponse
{
    // given
    NSString *phone = @"+9912312452";
    
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    [self.mockTransportSession resetReceivedRequests];
    
    XCTAssertFalse(self.userSession.registeredOnThisDevice);
    
    ZMUser *selfUser = [ZMUser selfUserInUserSession:self.userSession];
    XCTAssertEqualObjects(selfUser.phoneNumber, @"");
    
    id userObserver = [OCMockObject mockForProtocol:@protocol(UserProfileUpdateObserver)];
    id token = [self.userSession.userProfile addObserver:userObserver];
    
    // expect
    [[userObserver expect] phoneNumberVerificationCodeRequestDidFail:[OCMArg isNotNil]];
    
    self.mockTransportSession.responseGeneratorBlock = ^ZMTransportResponse*(ZMTransportRequest *request) {
        if([request.path isEqualToString:@"/self/phone"]) {
            return [ZMTransportResponse responseWithPayload:@{@"label": @"invalid-phone"} HTTPStatus:400 transportSessionError:nil];
        }
        return nil;
    };
    
    
    // when
    [self.userSession.userProfile requestPhoneVerificationCodeWithPhoneNumber:phone];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(self.mockTransportSession.receivedRequests.count, 1u);
    
    // after
    [self.userSession.userProfile removeObserverWithToken:token];
}

- (BOOL)loginWithPhoneAndRemoveEmail
{
    NSString *phone = @"+99123456789";
    self.selfUser.email = nil;
    self.selfUser.phone = phone;
    self.selfUser.password = nil;
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        [session whiteListPhone:phone];
    }];
    
    return [self loginAndWaitForSyncToBeCompleteWithPhone:phone];
}

- (void)testThatItCanSetEmailAndPassword
{
    // given
    NSString *email = @"foobar@geraterwerwer.dsf";
    XCTAssertTrue([self loginWithPhoneAndRemoveEmail]);
    ZMEmailCredentials *credentials = [ZMEmailCredentials credentialsWithEmail:email password:@"ds4rgsdg"];
    [self.mockTransportSession resetReceivedRequests];
    
    XCTAssertFalse(self.userSession.registeredOnThisDevice);
    
    ZMUser *selfUser = [ZMUser selfUserInUserSession:self.userSession];
    XCTAssertEqualObjects(selfUser.emailAddress, nil);

    // expect
    id editUserObserver = [OCMockObject mockForProtocol:@protocol(UserProfileUpdateObserver)];
    id editUserObserverToken = [self.userSession.userProfile addObserver:editUserObserver];
    [[editUserObserver expect] didSentVerificationEmail];
    
    id userObserver = [OCMockObject mockForProtocol:@protocol(ZMUserObserver)];
    id userObserverToken = [ZMUser addUserObserver:userObserver forUsers:@[selfUser] inUserSession:self.userSession];
    [(id<ZMUserObserver>)[userObserver expect] userDidChange:OCMOCK_ANY]; // <- DONE: when receiving this, I know that the email was set
    
    
    // when
    [self.userSession.userProfile requestSettingEmailAndPasswordWithCredentials:credentials error:nil]; // <- STEP 1
    WaitForAllGroupsToBeEmpty(0.5);
    
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        // simulate user click on email
        NOT_USED(session);
        self.selfUser.email = email;
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(self.mockTransportSession.receivedRequests.count, 2u);
    XCTAssertEqualObjects(selfUser.emailAddress, email);
    
    // after
    [ZMUser removeUserObserverForToken:userObserverToken];
    [self.userSession.userProfile removeObserverWithToken:editUserObserverToken];
    
}

- (void)testThatItNotifiesWhenFailingToSetThePasswordForNetworkError
{
    // given
    NSString *email = @"foobar@geraterwerwer.dsf";
    XCTAssertTrue([self loginWithPhoneAndRemoveEmail]);
    ZMEmailCredentials *credentials = [ZMEmailCredentials credentialsWithEmail:email password:@"ds4rgsdg"];
    [self.mockTransportSession resetReceivedRequests];
    
    XCTAssertFalse(self.userSession.registeredOnThisDevice);
    
    ZMUser *selfUser = [ZMUser selfUserInUserSession:self.userSession];
    XCTAssertEqualObjects(selfUser.emailAddress, nil);
    
    id userObserver = [OCMockObject mockForProtocol:@protocol(UserProfileUpdateObserver)];
    id token = [self.userSession.userProfile addObserver:userObserver];
    
    // expect
    self.mockTransportSession.responseGeneratorBlock = ^ZMTransportResponse*(ZMTransportRequest *request) {
        if([request.path isEqualToString:@"/self/password"]) {
            return [ZMTransportResponse responseWithPayload:nil HTTPStatus:400 transportSessionError:nil];
        }
        return nil;
    };
    [[userObserver expect] passwordUpdateRequestDidFail];
    
    // when
    [self.userSession.userProfile requestSettingEmailAndPasswordWithCredentials:credentials error:nil];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(self.mockTransportSession.receivedRequests.count, 1u);
    
    // after
    [self.userSession.userProfile removeObserverWithToken:token];
}

- (void)testThatItSilentlyIgnoreWhenFailingToSetThePasswordBecauseThePasswordWasAlreadyThere
{
    // given
    NSString *email = @"foobar@geraterwerwer.dsf";
    XCTAssertTrue([self loginWithPhoneAndRemoveEmail]);
    ZMEmailCredentials *credentials = [ZMEmailCredentials credentialsWithEmail:email password:@"ds4rgsdg"];
    [self.mockTransportSession resetReceivedRequests];
    
    XCTAssertFalse(self.userSession.registeredOnThisDevice);
    
    ZMUser *selfUser = [ZMUser selfUserInUserSession:self.userSession];
    XCTAssertEqualObjects(selfUser.emailAddress, nil);
    
    id editingObserver = [OCMockObject mockForProtocol:@protocol(UserProfileUpdateObserver)];
    id editingToken = [self.userSession.userProfile addObserver:editingObserver];
    id userObserver = [OCMockObject mockForProtocol:@protocol(ZMUserObserver)];
    id userToken = [ZMUser addUserObserver:userObserver forUsers:@[selfUser] inUserSession:self.userSession];
    [(id<ZMUserObserver>)[userObserver expect] userDidChange:OCMOCK_ANY]; // when receiving this, I know that the email was set
    
    // expect
    self.mockTransportSession.responseGeneratorBlock = ^ZMTransportResponse*(ZMTransportRequest *request) {
        if([request.path isEqualToString:@"/self/password"]) {
            return [ZMTransportResponse responseWithPayload:@{@"label":@"invalid-credentials"} HTTPStatus:403 transportSessionError:nil];
        }
        return nil;
    };
    [[editingObserver expect] didSentVerificationEmail];
    [[editingObserver expect] passwordUpdateRequestDidFail];
    
    // when
    [self.userSession.userProfile requestSettingEmailAndPasswordWithCredentials:credentials error:nil];
    WaitForAllGroupsToBeEmpty(0.5);
    
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        // simulate user click on email
        NOT_USED(session);
        self.selfUser.email = email;
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(self.mockTransportSession.receivedRequests.count, 2u);
    XCTAssertEqualObjects(selfUser.emailAddress, email);
    
    // after
    [ZMUser removeUserObserverForToken:userToken];
    [self.userSession.userProfile removeObserverWithToken:editingToken];
    
}

- (void)testThatItNotifiesWhenFailingToSetTheEmailBecauseOfGenericError
{
    // given
    NSString *email = @"foobar@geraterwerwer.dsf";
    XCTAssertTrue([self loginWithPhoneAndRemoveEmail]);
    ZMEmailCredentials *credentials = [ZMEmailCredentials credentialsWithEmail:email password:@"ds4rgsdg"];
    [self.mockTransportSession resetReceivedRequests];
    
    XCTAssertFalse(self.userSession.registeredOnThisDevice);
    
    ZMUser *selfUser = [ZMUser selfUserInUserSession:self.userSession];
    XCTAssertEqualObjects(selfUser.emailAddress, nil);
    
    id editiongObserver = [OCMockObject mockForProtocol:@protocol(UserProfileUpdateObserver)];
    id token = [self.userSession.userProfile addObserver:editiongObserver];
    
    // expect
    self.mockTransportSession.responseGeneratorBlock = ^ZMTransportResponse*(ZMTransportRequest *request) {
        if([request.path isEqualToString:@"/self/email"]) {
            return [ZMTransportResponse responseWithPayload:nil HTTPStatus:400 transportSessionError:nil];
        }
        return nil;
    };
    [[editiongObserver expect] emailUpdateDidFail:[NSError userSessionErrorWithErrorCode:ZMUserSessionUnkownError userInfo:nil]];
    
    // when
    [self.userSession.userProfile requestSettingEmailAndPasswordWithCredentials:credentials error:nil];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(self.mockTransportSession.receivedRequests.count, 2u);
    
    // after
    [self.userSession.userProfile removeObserverWithToken:token];
    
}

- (void)testThatItNotifiesWhenFailingToSetTheEmailBecauseOfInvalidEmail
{
    // given
    NSString *email = @"foobar@geraterwerwer.dsf";
    XCTAssertTrue([self loginWithPhoneAndRemoveEmail]);
    ZMEmailCredentials *credentials = [ZMEmailCredentials credentialsWithEmail:email password:@"ds4rgsdg"];
    [self.mockTransportSession resetReceivedRequests];
    
    XCTAssertFalse(self.userSession.registeredOnThisDevice);
    
    ZMUser *selfUser = [ZMUser selfUserInUserSession:self.userSession];
    XCTAssertEqualObjects(selfUser.emailAddress, nil);
    
    id editiongObserver = [OCMockObject mockForProtocol:@protocol(UserProfileUpdateObserver)];
    id token = [self.userSession.userProfile addObserver:editiongObserver];
    
    // expect
    self.mockTransportSession.responseGeneratorBlock = ^ZMTransportResponse*(ZMTransportRequest *request) {
        if([request.path isEqualToString:@"/self/email"]) {
            return [ZMTransportResponse responseWithPayload:@{@"label":@"invalid-email"} HTTPStatus:400 transportSessionError:nil];
        }
        return nil;
    };
    [[editiongObserver expect] emailUpdateDidFail:[NSError userSessionErrorWithErrorCode:ZMUserSessionInvalidEmail userInfo:nil]];
    
    // when
    [self.userSession.userProfile requestSettingEmailAndPasswordWithCredentials:credentials error:nil];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(self.mockTransportSession.receivedRequests.count, 2u);
    
    // after
    [self.userSession.userProfile removeObserverWithToken:token];
    
}

- (void)testThatItNotifiesWhenFailingToSetTheEmailBecauseOfEmailAlreadyInUse
{
    // given
    NSString *email = @"foobar@geraterwerwer.dsf";
    XCTAssertTrue([self loginWithPhoneAndRemoveEmail]);
    ZMEmailCredentials *credentials = [ZMEmailCredentials credentialsWithEmail:email password:@"ds4rgsdg"];
    [self.mockTransportSession resetReceivedRequests];
    
    XCTAssertFalse(self.userSession.registeredOnThisDevice);
    
    ZMUser *selfUser = [ZMUser selfUserInUserSession:self.userSession];
    XCTAssertEqualObjects(selfUser.emailAddress, nil);
    
    id editiongObserver = [OCMockObject mockForProtocol:@protocol(UserProfileUpdateObserver)];
    id token = [self.userSession.userProfile addObserver:editiongObserver];
    
    // expect
    self.mockTransportSession.responseGeneratorBlock = ^ZMTransportResponse*(ZMTransportRequest *request) {
        if([request.path isEqualToString:@"/self/email"]) {
            return [ZMTransportResponse responseWithPayload:@{@"label":@"key-exists"} HTTPStatus:409 transportSessionError:nil];
        }
        return nil;
    };
    [[editiongObserver expect] emailUpdateDidFail:[NSError userSessionErrorWithErrorCode:ZMUserSessionEmailIsAlreadyRegistered userInfo:nil]];
    
    // when
    [self.userSession.userProfile requestSettingEmailAndPasswordWithCredentials:credentials error:nil];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(self.mockTransportSession.receivedRequests.count, 2u);
    
    // after
    [self.userSession.userProfile removeObserverWithToken:token];
    
}

@end

