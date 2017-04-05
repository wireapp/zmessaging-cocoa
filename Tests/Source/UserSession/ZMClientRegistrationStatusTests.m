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
@import WireDataModel;

#import "MessagingTest.h"
#import "ZMClientRegistrationStatus.h"
#import "ZMCredentials.h"
#import <WireSyncEngine/WireSyncEngine-Swift.h>
#import "ZMClientRegistrationStatus+Internal.h"
#import "NSError+ZMUserSession.h"
#import "ZMUserSessionAuthenticationNotification.h"
#import "ZMCookie.h"

@interface FakeCredentialProfider : NSObject <ZMCredentialProvider>
@property (nonatomic) NSUInteger  clearCallCount;
@property (nonatomic) NSString *email;
@property (nonatomic) NSString *password;
@property (nonatomic) BOOL shouldReturnNilCredentials;
@end

@implementation FakeCredentialProfider

- (ZMEmailCredentials *)emailCredentials
{
    if (self.shouldReturnNilCredentials) {
        return nil;
    }
    NSString *email = self.email ?: @"knockknock@example.com";
    NSString *password = self.password ?: @"guessmeifyoucan";
    return [ZMEmailCredentials credentialsWithEmail:email password:password];
}

- (void)credentialsMayBeCleared
{
    self.clearCallCount++;
}

@end


@interface ZMClientRegistrationStatusTests : MessagingTest

@property (nonatomic) ZMClientRegistrationStatus *sut;
@property (nonatomic) FakeCredentialProfider *loginProvider;
@property (nonatomic) FakeCredentialProfider *updateProvider;
@property (nonatomic) id mockCookieStorage;
@property (nonatomic) id mockClientRegistrationDelegate;
@property (nonatomic) id sessionToken;
@property (nonatomic) NSMutableArray *sessionNotifications;
@end



@implementation ZMClientRegistrationStatusTests

- (void)setUp {
    [super setUp];
    [self.uiMOC setPersistentStoreMetadata:nil forKey:ZMPersistedClientIdKey]; // make sure to call this before initializing sut
    self.loginProvider = [[FakeCredentialProfider alloc] init];
    self.updateProvider = [[FakeCredentialProfider alloc] init];
    self.sessionNotifications = [NSMutableArray array];
    self.mockCookieStorage = [OCMockObject niceMockForClass:[ZMPersistentCookieStorage class]];
    self.mockClientRegistrationDelegate = [OCMockObject niceMockForProtocol:@protocol(ZMClientRegistrationStatusDelegate)];
    [[[self.mockCookieStorage stub] andReturn:[NSData data]] authenticationCookieData];
    
    ZMCookie *cookie = [[ZMCookie alloc] initWithManagedObjectContext:self.syncMOC cookieStorage:self.mockCookieStorage];
    self.sut = [[ZMClientRegistrationStatus alloc] initWithManagedObjectContext:self.uiMOC
                                                        loginCredentialProvider:self.loginProvider
                                                       updateCredentialProvider:self.updateProvider
                                                                         cookie:cookie
                                                     registrationStatusDelegate:self.mockClientRegistrationDelegate];
    self.sessionToken = [ZMUserSessionAuthenticationNotification addObserverWithBlock:^(ZMUserSessionAuthenticationNotification *note) {
        [self.sessionNotifications addObject:note];
    }];
}

- (void)tearDown {
    [ZMUserSessionAuthenticationNotification removeObserver:self.sessionToken];
    [self.sessionNotifications removeAllObjects];
    self.loginProvider = nil;
    self.updateProvider = nil;
    [self.sut tearDown];
    self.sut = nil;
    [super tearDown];
}

- (NSError *)tooManyClientsError
{
    return [NSError errorWithDomain:@"ZMUserSession" code:ZMUserSessionCanNotRegisterMoreClients userInfo:nil];
}

- (NSError *)needToRegisterEmailError
{
    return [NSError errorWithDomain:@"ZMUserSession" code:ZMUserSessionNeedsToRegisterEmailToRegisterClient userInfo:nil];
}

- (void)testThatItInsertsANewClientIfThereIsNoneWaitingToBeSynced
{
    // given
    ZMUser *selfUser = [ZMUser selfUserInContext:self.uiMOC];
    selfUser.remoteIdentifier = [NSUUID UUID];
    UserClient *client = [UserClient insertNewObjectInManagedObjectContext:self.uiMOC];
    client.user = selfUser;
    client.remoteIdentifier = @"identifier";
    
    XCTAssertEqual(selfUser.clients.count, 1u);
    
    // when
    [self.sut prepareForClientRegistration];
    
    // then
    XCTAssertEqual(selfUser.clients.count, 2u);
}


- (void)testThatItDoesNotInsertANewClientIfThereIsAlreadyOneWaitingToBeSynced
{
    // given
    ZMUser *selfUser = [ZMUser selfUserInContext:self.uiMOC];
    selfUser.remoteIdentifier = [NSUUID UUID];
    UserClient *client = [UserClient insertNewObjectInManagedObjectContext:self.uiMOC];
    client.user = selfUser;
    
    XCTAssertEqual(selfUser.clients.count, 1u);
    
    // when
    [self.sut prepareForClientRegistration];
    
    // then
    XCTAssertEqual(selfUser.clients.count, 1u);
}

- (void)testThatItUsesUpdateCredentialsIfItHasSome
{
    // given
    self.updateProvider.email = @"iam@example.com";
    self.updateProvider.password = @"thisIsDifferent";
    
    // when
    ZMEmailCredentials *credentials = [self.sut emailCredentials];
    
    // then
    XCTAssertEqual(credentials.email, self.updateProvider.email);
    XCTAssertEqual(credentials.password, self.updateProvider.password);
}

- (void)testThatItReturns_WaitingForSelfUser_IFSelfUserDoesNotHaveRemoteID
{
    // given
    ZMUser *selfUser = [ZMUser selfUserInContext:self.uiMOC];
    selfUser.remoteIdentifier = nil;
    
    // then
    XCTAssertEqual(self.sut.currentPhase, ZMClientRegistrationPhaseWaitingForSelfUser);
}


- (void)testThatItReturns_Registered_IfSelfClientIsSet
{
    // given
    ZMUser *selfUser = [ZMUser selfUserInContext:self.uiMOC];
    selfUser.remoteIdentifier = [NSUUID UUID];
    [self.uiMOC setPersistentStoreMetadata:@"lala" forKey:ZMPersistedClientIdKey];
    
    // then
    XCTAssertEqual(self.sut.currentPhase, ZMClientRegistrationPhaseRegistered);
}

- (void)testThatItReturns_FetchingClients_WhenReceivingAnErrorWithTooManyClients
{
    // given
    ZMUser *selfUser = [ZMUser selfUserInContext:self.uiMOC];
    selfUser.remoteIdentifier = [NSUUID UUID];
    
    // when
    [self.sut didFailToRegisterClient:[self tooManyClientsError]];
    
    // then
    XCTAssertEqual(self.sut.currentPhase, ZMClientRegistrationPhaseFetchingClients);
}

- (void)testThatItReturns_WaitingForDeletion_AfterUserSelectedClientToDelete
{
    // given
    __block BOOL notificationReceived = NO;
    id <ZMAuthenticationObserverToken> token = [ZMUserSessionAuthenticationNotification addObserverWithBlock:^(ZMUserSessionAuthenticationNotification *note) {
        notificationReceived = YES;
        XCTAssertEqual(note.type, ZMAuthenticationNotificationAuthenticationDidFail);
    }];
    
    [self performPretendingUiMocIsSyncMoc:^{
        ZMUser *selfUser = [ZMUser selfUserInContext:self.uiMOC];
        selfUser.remoteIdentifier = NSUUID.createUUID;
        
        UserClient *client = [UserClient insertNewObjectInManagedObjectContext:self.uiMOC];
        client.remoteIdentifier = @"identifier";
        client.user = selfUser;
        
        [self.uiMOC setPersistentStoreMetadata:client.remoteIdentifier forKey:ZMPersistedClientIdKey];
        [self.uiMOC saveOrRollback];
        
        // when
        [self.sut didDetectCurrentClientDeletion];
    }];
    
    WaitForAllGroupsToBeEmpty(0.5);

    // then
    XCTAssertTrue(notificationReceived);
    XCTAssertEqual(self.sut.currentPhase, ZMClientRegistrationPhaseUnregistered);
    
    [ZMUserSessionAuthenticationNotification removeObserver:token];
}

- (void)testThatItResets_LocallyModifiedKeys_AfterUserSelectedClientToDelete
{
    // given
    [self performPretendingUiMocIsSyncMoc:^{
        ZMUser *selfUser = [ZMUser selfUserInContext:self.uiMOC];
        selfUser.remoteIdentifier = NSUUID.createUUID;
        
        UserClient *client = [UserClient insertNewObjectInManagedObjectContext:self.uiMOC];
        client.remoteIdentifier = @"identifier";
        client.user = selfUser;
        [client setLocallyModifiedKeys:[NSSet setWithObject:@"numberOfKeysRemaining"]];
        
        [self.uiMOC setPersistentStoreMetadata:client.remoteIdentifier forKey:ZMPersistedClientIdKey];
        
        // when
        [self.sut didDetectCurrentClientDeletion];
        
        // then
        XCTAssertFalse([client hasLocalModificationsForKey:@"numberOfKeysRemaining"]);
    }];
}

- (void)testThatItInvalidatesSelfClientAndDeletesAndRecreatesCryptoBoxOnDidDetectCurrentClientDeletion
{
    // given
    ZMUser *selfUser = [ZMUser selfUserInContext:self.uiMOC];
    selfUser.remoteIdentifier = [NSUUID UUID];
    
    UserClient *client = [UserClient insertNewObjectInManagedObjectContext:self.uiMOC];
    client.user = selfUser;
    [self.uiMOC saveOrRollback];
    
    // when
    [self.sut didFailToRegisterClient:[self tooManyClientsError]];
    [ZMClientUpdateNotification notifyFetchingClientsCompletedWithUserClients:@[client]];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(self.sut.currentPhase, ZMClientRegistrationPhaseWaitingForDeletion);
}

- (void)testThatItReturns_WaitingForEmailVerfication_IFError_UserNeedsToRegisterEmail
{
    // given
    ZMUser *selfUser = [ZMUser selfUserInContext:self.uiMOC];
    selfUser.remoteIdentifier = [NSUUID UUID];
    
    // when
    NSError *error = [NSError errorWithDomain:@"ZMUserSession" code:ZMUserSessionNeedsToRegisterEmailToRegisterClient userInfo:nil];
    [self.sut didFailToRegisterClient:error];
    
    // then
    XCTAssertEqual(self.sut.currentPhase, ZMClientRegistrationPhaseWaitingForEmailVerfication);
}


- (void)testThatItReturnsYESForNeedsToRegisterClientIfNoClientIdInMetadata
{
    [self.uiMOC setPersistentStoreMetadata:nil forKey:ZMPersistedClientIdKey];
    XCTAssertTrue([ZMClientRegistrationStatus needsToRegisterClientInContext:self.uiMOC]);
}

- (void)testThatItReturnsNOForNeedsToRegisterClientIfThereIsClientIdInMetadata
{
    [self.uiMOC setPersistentStoreMetadata:@"lala" forKey:ZMPersistedClientIdKey];
    XCTAssertFalse([ZMClientRegistrationStatus needsToRegisterClientInContext:self.uiMOC]);
}

- (void)testThatItNotfiesCredentialProviderWhenClientIsRegistered
{
    //given
    ZMUser *selfUser = [ZMUser selfUserInContext:self.uiMOC];
    selfUser.remoteIdentifier = [NSUUID new];

    //when
    [self.sut prepareForClientRegistration];

    UserClient *client = [UserClient insertNewObjectInManagedObjectContext:self.uiMOC];
    client.remoteIdentifier = [NSUUID createUUID].transportString;

    [self.sut didRegisterClient:client];

    // then
    XCTAssertEqual(self.sut.currentPhase, ZMClientRegistrationPhaseRegistered);
    XCTAssertEqual(self.loginProvider.clearCallCount, 1u);
    XCTAssertEqual(self.updateProvider.clearCallCount, 1u);
}

- (void)testThatItNotfiesDelegateWhenClientIsRegistered
{
    // given
    ZMUser *selfUser = [ZMUser selfUserInContext:self.uiMOC];
    selfUser.remoteIdentifier = [NSUUID new];
    
    [self.sut prepareForClientRegistration];
    
    UserClient *client = [UserClient insertNewObjectInManagedObjectContext:self.uiMOC];
    client.remoteIdentifier = [NSUUID createUUID].transportString;
    [[self.mockClientRegistrationDelegate expect] didRegisterUserClient:client];
    
    // when
    [self.sut didRegisterClient:client];
    
    // then
    [self.mockClientRegistrationDelegate verify];
}

- (void)testThatItTransitionsFrom_WaitingForEmail_To_Unregistered_WhenSelfUserChangesWithEmailAddress
{
    // given
    
    ZMUser *selfUser = [ZMUser selfUserInContext:self.uiMOC];
    selfUser.remoteIdentifier = [NSUUID UUID];
    
    [self.sut didFailToRegisterClient:[self needToRegisterEmailError]];
    XCTAssertEqual(self.sut.currentPhase, ZMClientRegistrationPhaseWaitingForEmailVerfication);
    
    // when
    selfUser.emailAddress = @"me@example.com";
    [self.sut didFetchSelfUser];
    
    // then
    XCTAssertEqual(self.sut.currentPhase, ZMClientRegistrationPhaseUnregistered);
}


- (void)testThatItDoesNotTransitionsFrom_WaitingForEmail_To_Unregistered_WhenSelfUserChangesWithoutEmailAddress
{
    // given
    
    ZMUser *selfUser = [ZMUser selfUserInContext:self.uiMOC];
    selfUser.remoteIdentifier = [NSUUID UUID];
    
    [self.sut didFailToRegisterClient:[self needToRegisterEmailError]];
    XCTAssertEqual(self.sut.currentPhase, ZMClientRegistrationPhaseWaitingForEmailVerfication);
    
    // when
    selfUser.emailAddress = nil;
    [self.sut didFetchSelfUser];
    
    // then
    XCTAssertEqual(self.sut.currentPhase, ZMClientRegistrationPhaseWaitingForEmailVerfication);
}

- (void)testThatItResetsThePhaseToWaitingForLoginIfItNeedsPasswordToRegisterClient
{
    // given
    ZMUser *selfUser = [ZMUser selfUserInContext:self.uiMOC];
    selfUser.remoteIdentifier = [NSUUID UUID];
    [[[self.mockCookieStorage stub] andReturn:[NSData data]] authenticationCookieData];
    self.loginProvider.shouldReturnNilCredentials = YES;
    self.updateProvider.shouldReturnNilCredentials = YES;
    
    XCTAssertEqual(self.sut.currentPhase, ZMClientRegistrationPhaseUnregistered);

    NSError *error = [NSError errorWithDomain:@"ZMUserSession" code:ZMUserSessionNeedsPasswordToRegisterClient userInfo:nil];

    // when
    [self.sut didFailToRegisterClient:error];
    
    // then
    XCTAssertEqual(self.sut.currentPhase, ZMClientRegistrationPhaseWaitingForLogin);
    
    // and when
    // the user entered the password, we can proceed trying to register the client
    self.loginProvider.shouldReturnNilCredentials = NO;
    
    // then
    XCTAssertEqual(self.sut.currentPhase, ZMClientRegistrationPhaseUnregistered);
}


@end



@implementation ZMClientRegistrationStatusTests (AuthenticationNotifications)

- (void)testThatItNotifiesTheUIAboutSuccessfulRegistration
{
    // givne
    UserClient *client = [UserClient insertNewObjectInManagedObjectContext:self.uiMOC];
    client.remoteIdentifier = @"yay";
    
    // when
    [self.sut didRegisterClient:client];
    
    // then
    XCTAssertEqual(self.sessionNotifications.count, 1u);
    ZMUserSessionAuthenticationNotification *note = self.sessionNotifications.firstObject;
    XCTAssertEqual(note.type, ZMAuthenticationNotificationAuthenticationDidSuceeded);
}

- (void)testThatItNotifiesTheUIIfTheClientWasAlreadyRegisteredBeforeFetchingTheSelfUser
{
    // given
    [self.uiMOC setPersistentStoreMetadata:@"brrrrr" forKey:ZMPersistedClientIdKey];
    
    // when
    [self.sut didFetchSelfUser];
    
    // then
    XCTAssertEqual(self.sessionNotifications.count, 1u);
    ZMUserSessionAuthenticationNotification *note = self.sessionNotifications.firstObject;
    XCTAssertEqual(note.type, ZMAuthenticationNotificationAuthenticationDidSuceeded);
}

- (void)testThatItNotifiesTheUIIfTheRegistrationFailsWithMissingEmailVerification
{
    // given
    NSError *error = [self needToRegisterEmailError];
    
    // when
    [self.sut didFailToRegisterClient:error];
    
    // then
    XCTAssertEqual(self.sessionNotifications.count, 1u);
    ZMUserSessionAuthenticationNotification *note = self.sessionNotifications.firstObject;
    XCTAssertEqual(note.type, ZMAuthenticationNotificationAuthenticationDidFail);
    XCTAssertEqual(note.error, error);
}

- (void)testThatItNotifiesTheUIIfTheRegistrationFailsWithMissingPasswordError
{
    // given
    NSError *error = [NSError errorWithDomain:@"ZMUserSession" code:ZMUserSessionNeedsPasswordToRegisterClient userInfo:nil];
    
    // when
    [self.sut didFailToRegisterClient:error];
    
    // then
    XCTAssertEqual(self.sessionNotifications.count, 1u);
    ZMUserSessionAuthenticationNotification *note = self.sessionNotifications.firstObject;
    XCTAssertEqual(note.type, ZMAuthenticationNotificationAuthenticationDidFail);
    XCTAssertEqual(note.error, error);
}

- (void)testThatItNotifiesTheUIIfTheRegistrationFailsWithWrongCredentialsError
{
    // given
    NSError *error = [NSError errorWithDomain:@"ZMUserSession" code:ZMUserSessionInvalidCredentials userInfo:nil];
    
    // when
    [self.sut didFailToRegisterClient:error];
    
    // then
    XCTAssertEqual(self.sessionNotifications.count, 1u);
    ZMUserSessionAuthenticationNotification *note = self.sessionNotifications.firstObject;
    XCTAssertEqual(note.type, ZMAuthenticationNotificationAuthenticationDidFail);
    XCTAssertEqual(note.error, error);
}

- (void)testThatItDoesNotNotifiesTheUIIfTheRegistrationFailsWithTooManyClientsError
{
    // given
    NSError *error = [self tooManyClientsError];
    
    // when
    [self.sut didFailToRegisterClient:error];
    
    // then
    XCTAssertEqual(self.sessionNotifications.count, 0u);
}

- (void)testThatItDeletesTheCookieIfFetchingClientsFailedWithError_SelfClientIsInvalid
{
    // given
    ZMUser *selfUser = [ZMUser selfUserInContext:self.uiMOC];
    selfUser.remoteIdentifier = [NSUUID UUID];
    
    UserClient *client = [UserClient insertNewObjectInManagedObjectContext:self.uiMOC];
    client.user = selfUser;
    client.remoteIdentifier = @"identifer";
    [self.uiMOC saveOrRollback];
    [self.uiMOC setPersistentStoreMetadata:client.remoteIdentifier forKey:ZMPersistedClientIdKey];

    XCTAssertNotNil(selfUser.selfClient);
    
    NSError *error = [NSError errorWithDomain:@"ClientManagement" code:ClientUpdateErrorSelfClientIsInvalid userInfo:nil];

    // expect
    [[self.mockCookieStorage expect] setAuthenticationCookieData:nil];
    
    // when
    [ZMClientUpdateNotification notifyFetchingClientsDidFail:error];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertNil([self.uiMOC persistentStoreMetadataForKey:ZMPersistedClientIdKey]);
    [self.mockCookieStorage verify];
}


@end

