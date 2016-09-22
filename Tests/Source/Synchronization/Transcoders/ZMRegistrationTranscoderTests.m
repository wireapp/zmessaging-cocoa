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
@import ZMCDataModel;

#import "ObjectTranscoderTests.h"
#import "ZMRegistrationTranscoder.h"
#import "ZMAuthenticationStatus.h"
#import "ZMCredentials.h"
#import "ZMUserSessionRegistrationNotification.h"
#import "NSError+ZMUserSessionInternal.h"

@interface ZMRegistrationTranscoderTests : ObjectTranscoderTests

@property (nonatomic) ZMRegistrationTranscoder<ZMSingleRequestTranscoder> *sut;
@property (nonatomic) id registrationDownstreamSync;
@property (nonatomic) id verificationResendRequestSync;
@property (nonatomic) ZMAuthenticationStatus *authenticationStatus;
@property (nonatomic) ZMPersistentCookieStorage *cookieStorage;
@property (nonatomic) id mockLocale;

@end



@implementation ZMRegistrationTranscoderTests

- (void)setUp
{
    [super setUp];
    
    // Request to /register
    id classMock = [OCMockObject mockForClass:ZMSingleRequestSync.class];
    self.mockLocale = [OCMockObject niceMockForClass:[NSLocale class]];
    [[[self.mockLocale stub] andReturn:@[@"en"]] preferredLanguages];
    
    [self verifyMockLater:self.mockLocale];
    
    self.registrationDownstreamSync = [OCMockObject mockForClass:ZMSingleRequestSync.class];
    (void) [[[self.registrationDownstreamSync expect] andReturn:self.registrationDownstreamSync] syncWithSingleRequestTranscoder:OCMOCK_ANY managedObjectContext:self.uiMOC];
    [self verifyMockLater:self.registrationDownstreamSync];
    
    self.cookieStorage = [ZMPersistentCookieStorage storageForServerName:@"com.wearezeta.test-zmessaging"];
    ZMCookie *cookie = [[ZMCookie alloc] initWithManagedObjectContext:self.uiMOC cookieStorage:self.cookieStorage];
    self.authenticationStatus = [[ZMAuthenticationStatus alloc] initWithManagedObjectContext:self.uiMOC cookie:cookie];
    
    self.sut = (id) [[ZMRegistrationTranscoder alloc] initWithManagedObjectContext:self.uiMOC authenticationStatus:self.authenticationStatus];
    [classMock stopMocking];
}

- (void)tearDown
{
    [self.sut tearDown];
    self.sut = nil;
    self.registrationDownstreamSync = nil;
    self.cookieStorage = nil;
    self.authenticationStatus = nil;
    self.mockLocale = nil;
    [super tearDown];
}

- (void)testThatItOnlyProcessesRegistrationRequests;
{
    // when
    NSArray *generators = self.sut.requestGenerators;
    
    // then
    XCTAssertEqual(generators.count, 1u);
    XCTAssertTrue([generators.firstObject isKindOfClass:ZMSingleRequestSync.class]);
}

- (void)testThatItDoesNotReturnAContextChangeTracker;
{
    // when
    NSArray *trackers = self.sut.contextChangeTrackers;
    
    // then
    XCTAssertEqual(trackers.count, 0u);
}

- (void)testThatItCallsNextRequestOnRegistrationRequestSyncs
{
    // expect
    [[[self.registrationDownstreamSync expect] andReturn:nil] nextRequest];
    
    // when
    [self.sut.requestGenerators nextRequest];
    
    // then
    [self.registrationDownstreamSync verify];
}

- (NSDictionary *)expectedPayloadWithLocale:(NSString *)locale email:(NSString *)email password:(NSString *)password
{
    NSString *cookieLabel = self.authenticationStatus.cookieLabel;
    NSDictionary *expectedPayload = @{
                                      @"name" : @"foo",
                                      @"password" : password,
                                      @"accent_id" : @(ZMAccentColorBrightYellow),
                                      @"email" : email,
                                      @"locale": locale,
                                      @"label": cookieLabel
                                      };
    return expectedPayload;
}

- (void)testThatItSendsARegistrationRequestWithEnglishLaguage;
{
    // given
    NSString *email = @"class@example.com";
    NSString *password = @"classified";
    NSDictionary *expectedPayload = [self expectedPayloadWithLocale:@"en" email:email password:password];
    
    // when
    ZMCompleteRegistrationUser *regUser = [ZMCompleteRegistrationUser registrationUserWithEmail:email password:password];
    regUser.name = expectedPayload[@"name"];
    regUser.accentColorValue = ZMAccentColorBrightYellow;
    [self.authenticationStatus prepareForRegistrationOfUser:regUser];
    ZMTransportRequest *request = [(id)self.sut requestForSingleRequestSync:self.registrationDownstreamSync];
    
    // then
    XCTAssertNotNil(request);
    XCTAssertFalse(request.needsAuthentication);
    XCTAssertEqualObjects(request.path, @"/register");
    XCTAssertEqual(request.method, ZMMethodPOST);
    AssertEqualDictionaries(expectedPayload, (id) request.payload);
}

- (void)testThatItSendsARegistrationRequestWithGermanLaguage;
{
    self.mockLocale = [OCMockObject niceMockForClass:[NSLocale class]];
    [[[self.mockLocale stub] andReturn:@[@"de"]] preferredLanguages];

    // given
    NSString *email = @"class@example.com";
    NSString *password = @"classified";
    NSDictionary *expectedPayload = [self expectedPayloadWithLocale:@"de" email:email password:password];
    
    // when
    ZMCompleteRegistrationUser *regUser = [ZMCompleteRegistrationUser registrationUserWithEmail:email password:password];
    regUser.name = expectedPayload[@"name"];
    regUser.accentColorValue = ZMAccentColorBrightYellow;
    [self.authenticationStatus prepareForRegistrationOfUser:regUser];
    ZMTransportRequest *request = [(id)self.sut requestForSingleRequestSync:self.registrationDownstreamSync];
    
    // then
    XCTAssertNotNil(request);
    XCTAssertFalse(request.needsAuthentication);
    XCTAssertEqualObjects(request.path, @"/register");
    XCTAssertEqual(request.method, ZMMethodPOST);
    AssertEqualDictionaries(expectedPayload, (id) request.payload);
}

- (void)testThatItSendsARegistrationRequestWithGermanLaguageIfThereIsNoSupportedLanguageBefore;
{
    self.mockLocale = [OCMockObject niceMockForClass:[NSLocale class]];
    [[[self.mockLocale stub] andReturn:@[@"it-IT", @"jp", @"de", @"fr-CA", @"en"]] preferredLanguages];
    
    // given
    NSString *email = @"class@example.com";
    NSString *password = @"classified";
    NSDictionary *expectedPayload = [self expectedPayloadWithLocale:@"de" email:email password:password];
    
    // when
    ZMCompleteRegistrationUser *regUser = [ZMCompleteRegistrationUser registrationUserWithEmail:email password:password];
    regUser.name = expectedPayload[@"name"];
    regUser.accentColorValue = ZMAccentColorBrightYellow;
    [self.authenticationStatus prepareForRegistrationOfUser:regUser];
    ZMTransportRequest *request = [(id)self.sut requestForSingleRequestSync:self.registrationDownstreamSync];
    
    // then
    XCTAssertNotNil(request);
    XCTAssertFalse(request.needsAuthentication);
    XCTAssertEqualObjects(request.path, @"/register");
    XCTAssertEqual(request.method, ZMMethodPOST);
    AssertEqualDictionaries(expectedPayload, (id) request.payload);
}

- (void)testThatItSendsARegistrationRequestWithEnglishAmericanLaguageIfThereIsNoSupportedLanguageBefore;
{
    self.mockLocale = [OCMockObject niceMockForClass:[NSLocale class]];
    [[[self.mockLocale stub] andReturn:@[@"it-IT", @"jp", @"en-US", @"fr-CA", @"de"]] preferredLanguages];
    
    // given
    NSString *email = @"class@example.com";
    NSString *password = @"classified";
    NSDictionary *expectedPayload = [self expectedPayloadWithLocale:@"en-US" email:email password:password];

    // when
    ZMCompleteRegistrationUser *regUser = [ZMCompleteRegistrationUser registrationUserWithEmail:email password:password];
    regUser.name = expectedPayload[@"name"];
    regUser.accentColorValue = ZMAccentColorBrightYellow;
    [self.authenticationStatus prepareForRegistrationOfUser:regUser];
    ZMTransportRequest *request = [(id)self.sut requestForSingleRequestSync:self.registrationDownstreamSync];
    
    // then
    XCTAssertNotNil(request);
    XCTAssertFalse(request.needsAuthentication);
    XCTAssertEqualObjects(request.path, @"/register");
    XCTAssertEqual(request.method, ZMMethodPOST);
    AssertEqualDictionaries(expectedPayload, (id) request.payload);
}

- (void)testThatItSendsARegistrationRequestWithEnglishLaguageIfThereIsNoSupportedLanguageInTheList;
{
    self.mockLocale = [OCMockObject niceMockForClass:[NSLocale class]];
    [[[self.mockLocale stub] andReturn:@[@"it-IT", @"jp", @"fr-CA"]] preferredLanguages];
    
    // given
    NSString *email = @"class@example.com";
    NSString *password = @"classified";
    NSDictionary *expectedPayload = [self expectedPayloadWithLocale:@"en" email:email password:password];

    
    // when
    ZMCompleteRegistrationUser *regUser = [ZMCompleteRegistrationUser registrationUserWithEmail:email password:password];
    regUser.name = expectedPayload[@"name"];
    regUser.accentColorValue = ZMAccentColorBrightYellow;
    [self.authenticationStatus prepareForRegistrationOfUser:regUser];
    ZMTransportRequest *request = [(id)self.sut requestForSingleRequestSync:self.registrationDownstreamSync];
    
    // then
    XCTAssertNotNil(request);
    XCTAssertFalse(request.needsAuthentication);
    XCTAssertEqualObjects(request.path, @"/register");
    XCTAssertEqual(request.method, ZMMethodPOST);
    AssertEqualDictionaries(expectedPayload, (id) request.payload);
}


- (void)testThatItSetsEnglishAsDefaultLanguage
{
    self.mockLocale = [OCMockObject niceMockForClass:[NSLocale class]];
    [[[self.mockLocale stub] andReturn:@[@"fr"]] preferredLanguages];

    // given
    NSString *email = @"class@example.com";
    NSString *password = @"classified";
    NSDictionary *expectedPayload = [self expectedPayloadWithLocale:@"en" email:email password:password];
    
    // when
    ZMCompleteRegistrationUser *regUser = [ZMCompleteRegistrationUser registrationUserWithEmail:email password:password];
    regUser.name = expectedPayload[@"name"];
    regUser.accentColorValue = ZMAccentColorBrightYellow;
    [self.authenticationStatus prepareForRegistrationOfUser:regUser];
    ZMTransportRequest *request = [(id)self.sut requestForSingleRequestSync:self.registrationDownstreamSync];
    
    // then
    AssertEqualDictionaries(expectedPayload, (id) request.payload);
}

- (void)testThatItSetsEnglishAsDefaultLanguageWithNoUnderscores
{
    self.mockLocale = [OCMockObject niceMockForClass:[NSLocale class]];
    [[[self.mockLocale stub] andReturn:@[@"en_IN"]] preferredLanguages];
    
    // given
    NSString *email = @"class@example.com";
    NSString *password = @"classified";
    NSDictionary *expectedPayload = [self expectedPayloadWithLocale:@"en-IN" email:email password:password];
    
    // when
    ZMCompleteRegistrationUser *regUser = [ZMCompleteRegistrationUser registrationUserWithEmail:email password:password];
    regUser.name = expectedPayload[@"name"];
    regUser.accentColorValue = ZMAccentColorBrightYellow;
    [self.authenticationStatus prepareForRegistrationOfUser:regUser];
    ZMTransportRequest *request = [(id)self.sut requestForSingleRequestSync:self.registrationDownstreamSync];
    
    // then
    AssertEqualDictionaries(expectedPayload, (id) request.payload);
}


- (void)testThatResetRegistrationStateResetsAndMarkForDownloadTheSingleRequest
{
    // expect
    [[self.registrationDownstreamSync expect] readyForNextRequest];
    [[self.registrationDownstreamSync expect] resetCompletionState];
    
    // when
    [self.sut resetRegistrationState];
    
    // then
    [self.registrationDownstreamSync verify];
}


- (void)testThatItSetsTheCredentialAndResetsRegistrationPasswordOnSuccessfulRegistration
{
    // given
    NSString *password = @"foo$$$$";
    NSString *email = @"email@example.com";
    ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:@{@"name": @"Clara", @"email":email} HTTPStatus:200 transportSessionError:nil];
    [self.authenticationStatus prepareForRegistrationOfUser:[ZMCompleteRegistrationUser registrationUserWithEmail:email password:password]];
    
    // when
    [self.sut didReceiveResponse:response forSingleRequest:self.registrationDownstreamSync];
    
    // then
    XCTAssertEqualObjects(self.authenticationStatus.loginCredentials.password, password);
    XCTAssertEqualObjects(self.authenticationStatus.loginCredentials.email, email);
}

- (void)testThatItSetsRegisteredOnThisDeviceOnSuccessfulRegistration
{
    // given
    NSString *password = @"foo$$$$";
    NSString *email = @"email@example.com";
    ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:@{@"name": @"Clara", @"email":email} HTTPStatus:200 transportSessionError:nil];
    [self.authenticationStatus prepareForRegistrationOfUser:[ZMCompleteRegistrationUser registrationUserWithEmail:email password:password]];
    
    // when
    [self.sut didReceiveResponse:response forSingleRequest:self.registrationDownstreamSync];
    
    // then
    XCTAssertTrue(self.authenticationStatus.registeredOnThisDevice);
}

- (void)testThatItUpdatesTheSelfUserAfterSuccessfullRegistration
{
    // given
    NSString *name = @"Name";
    NSString *emailAddress = @"user@example.com";
    NSUUID *remoteID = [NSUUID createUUID];
    
    ZMCompleteRegistrationUser *user = [ZMCompleteRegistrationUser registrationUserWithEmail:emailAddress password:@"foobar$$"];
    user.name = name;
    [self.authenticationStatus prepareForRegistrationOfUser:user];
    
    ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:@{@"name": name,
                                                                               @"email": emailAddress,
                                                                               @"id": remoteID.transportString}
                                                                  HTTPStatus:200
                                                       transportSessionError:nil];
    
    // when
    [self.sut didReceiveResponse:response forSingleRequest:self.registrationDownstreamSync];

    // then
    ZMUser *selfUser = [ZMUser selfUserInContext:self.uiMOC];
    XCTAssertEqualObjects(selfUser.name, name);
    XCTAssertEqualObjects(selfUser.emailAddress, emailAddress);
}

- (void)testThatItDoesNotSetTheSelfUserIDAfterRegistration
{
    // given
    NSString *name = @"Name";
    NSString *emailAddress = @"user@example.com";
    NSUUID *remoteID = [NSUUID createUUID];
    ZMCompleteRegistrationUser *user = [ZMCompleteRegistrationUser registrationUserWithEmail:emailAddress password:@"foobar$$"];
    user.name = name;
    [self.authenticationStatus prepareForRegistrationOfUser:user];
    

    
    ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:@{@"name": name,
                                                                               @"email": emailAddress,
                                                                               @"id": remoteID.transportString}
                                                                  HTTPStatus:200
                                                       transportSessionError:nil];
    
    [self.sut didReceiveResponse:response forSingleRequest:self.registrationDownstreamSync];
    
    // then
    ZMUser *selfUser = [ZMUser selfUserInContext:self.uiMOC];
    XCTAssertNil(selfUser.remoteIdentifier);
}

- (void)testThatItDoesNotUpdateTheSelfUserAfterUnSuccessfullRegistration
{
    // given
    NSString *name = @"Name";
    NSString *emailAddress = @"user@example.com";
    ZMCompleteRegistrationUser *user = [ZMCompleteRegistrationUser registrationUserWithEmail:emailAddress password:@"foobar$$"];
    user.name = name;
    [self.authenticationStatus prepareForRegistrationOfUser:user];
    
    ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:nil HTTPStatus:400 transportSessionError:nil];
    
    // when
    [self.sut didReceiveResponse:response forSingleRequest:self.registrationDownstreamSync];
    
    // then
    ZMUser *selfUser = [ZMUser selfUserInContext:self.uiMOC];
    XCTAssertNil(selfUser.name);
    XCTAssertNil(selfUser.emailAddress);
    XCTAssertNil(selfUser.remoteIdentifier);
}

- (void)testThatItNotifiesOfAnUnsuccessfullRegistration
{
    // given
    NSString *name = @"Name";
    NSString *emailAddress = @"user@example.com";
    ZMCompleteRegistrationUser *user = [ZMCompleteRegistrationUser registrationUserWithEmail:emailAddress password:@"foobar$$"];
    user.name = name;
    [self.authenticationStatus prepareForRegistrationOfUser:user];
    
    // expect
    XCTestExpectation *expectation = [self expectationWithDescription:@"error notification"];
    id token = [ZMUserSessionRegistrationNotification addObserverWithBlock:^(ZMUserSessionRegistrationNotification *note) {
        XCTAssertEqual(note.error.code, (long) ZMUserSessionUnkownError);
        XCTAssertEqual(note.error.domain, ZMUserSessionErrorDomain);
        [expectation fulfill];
    } ];

    ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:nil HTTPStatus:400 transportSessionError:nil];
    
    // when
    [self.sut didReceiveResponse:response forSingleRequest:self.registrationDownstreamSync];
    
    // then
    XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0.5]);
    [ZMUserSessionRegistrationNotification removeObserver:token];
}

- (void)testThatItNotifiesOfAnUnsuccessfullRegistrationBecauseOfInvalidEmail
{
    // given
    NSString *name = @"Name";
    NSString *emailAddress = @"user@example.com";
    ZMCompleteRegistrationUser *user = [ZMCompleteRegistrationUser registrationUserWithEmail:emailAddress password:@"foobar$$"];
    user.name = name;
    [self.authenticationStatus prepareForRegistrationOfUser:user];
    
    // expect
    XCTestExpectation *expectation = [self expectationWithDescription:@"error notification"];
    id token = [ZMUserSessionRegistrationNotification addObserverWithBlock:^(ZMUserSessionRegistrationNotification *note) {
        XCTAssertEqual(note.error.code, (long) ZMUserSessionInvalidEmail);
        XCTAssertEqual(note.error.domain, ZMUserSessionErrorDomain);
        [expectation fulfill];
    } ];
    
    ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:@{@"label":@"invalid-email"} HTTPStatus:400 transportSessionError:nil];
    
    // when
    [self.sut didReceiveResponse:response forSingleRequest:self.registrationDownstreamSync];
    
    // then
    XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0.5]);
    [ZMUserSessionRegistrationNotification removeObserver:token];
}

- (void)testThatItNotifiesOfAnUnsuccessfullRegistrationBecauseOfInvalidPhone
{
    // given
    ZMCompleteRegistrationUser *user = [ZMCompleteRegistrationUser registrationUserWithPhoneNumber:@"+4912345678" phoneVerificationCode:@"123456"];
    user.name = @"foo";
    [self.authenticationStatus prepareForRegistrationOfUser:user];
    
    // expect
    XCTestExpectation *expectation = [self expectationWithDescription:@"error notification"];
    id token = [ZMUserSessionRegistrationNotification addObserverWithBlock:^(ZMUserSessionRegistrationNotification *note) {
        XCTAssertEqual(note.error.code, (long) ZMUserSessionInvalidPhoneNumber);
        XCTAssertEqual(note.error.domain, ZMUserSessionErrorDomain);
        [expectation fulfill];
    } ];
    
    ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:@{@"label":@"invalid-phone"} HTTPStatus:400 transportSessionError:nil];
    
    // when
    [self.sut didReceiveResponse:response forSingleRequest:self.registrationDownstreamSync];
    
    // then
    XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0.5]);
    [ZMUserSessionRegistrationNotification removeObserver:token];
}

- (void)testThatItDoesNotUpdateTheRegisterOnThisDeviceAfterUnSuccessfullRegistration
{
    // given
    NSString *name = @"Name";
    NSString *emailAddress = @"user@example.com";
    NSUUID *remoteID = [NSUUID createUUID];
    ZMCompleteRegistrationUser *user = [ZMCompleteRegistrationUser registrationUserWithEmail:emailAddress password:@"foobar$$"];
    user.name = name;
    [self.authenticationStatus prepareForRegistrationOfUser:user];
    
    ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:@{@"name": name,
                                                                               @"email": emailAddress,
                                                                               @"id": remoteID.transportString}
                                                                  HTTPStatus:400
                                                       transportSessionError:nil];
    
    // when
    [self.sut didReceiveResponse:response forSingleRequest:self.registrationDownstreamSync];
    
    // then
    XCTAssertFalse(self.authenticationStatus.registeredOnThisDevice);

}

@end
