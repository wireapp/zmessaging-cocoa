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


@import PushKit;
@import ZMCMockTransport;

#include "ZMUserSessionTestsBase.h"
#import "ZMPushToken.h"
#import "UILocalNotification+UserInfo.h"
#import "ZMUserSession+UserNotificationCategories.h"
#import "zmessaging_iOS_Tests-Swift.h"

@interface ZMUserSessionTests : ZMUserSessionTestsBase

@property (nonatomic) NSNotification *lastReceivedNotification;

- (void)didReceiveNotification:(NSNotification *)notification;
- (void)simulateLoggedInUser;

@end



@implementation ZMUserSessionTests

- (void)simulateLoggedInUser
{
    [self.syncMOC setPersistentStoreMetadata:@"foooooo" forKey:ZMPersistedClientIdKey];
    [ZMUser selfUserInContext:self.syncMOC].remoteIdentifier = [NSUUID createUUID];
    [self.cookieStorage setAuthenticationCookieData:self.validCookie];
}

- (void)tearDown
{
    [super tearDown];
    self.lastReceivedNotification = nil;
}

- (void)didReceiveNotification:(NSNotification *)notification
{
    self.lastReceivedNotification = notification;
}

- (void)testThatItInitializesTheBackendEnvironments
{
    // given
    ZMBackendEnvironment *edge = [ZMBackendEnvironment environmentWithType:ZMBackendEnvironmentTypeEdge];
    ZMBackendEnvironment *prod = [ZMBackendEnvironment environmentWithType:ZMBackendEnvironmentTypeProduction];
    ZMBackendEnvironment *staging = [ZMBackendEnvironment environmentWithType:ZMBackendEnvironmentTypeStaging];
    
    // then
    XCTAssertEqualObjects(edge.backendURL, [NSURL URLWithString:@"https://edge-nginz-https.zinfra.io"]);
    XCTAssertEqualObjects(prod.backendURL, [NSURL URLWithString:@"https://prod-nginz-https.wire.com"]);
    XCTAssertEqualObjects(staging.backendURL, [NSURL URLWithString:@"https://staging-nginz-https.zinfra.io"]);
    
    XCTAssertEqualObjects(edge.backendWSURL, [NSURL URLWithString:@"https://edge-nginz-ssl.zinfra.io"]);
    XCTAssertEqualObjects(prod.backendWSURL, [NSURL URLWithString:@"https://prod-nginz-ssl.wire.com"]);
    XCTAssertEqualObjects(staging.backendWSURL, [NSURL URLWithString:@"https://staging-nginz-ssl.zinfra.io"]);
    
    XCTAssertEqualObjects(edge.blackListURL, [NSURL URLWithString:@"https://clientblacklist.wire.com/edge/ios"]);
    XCTAssertEqualObjects(prod.blackListURL, [NSURL URLWithString:@"https://clientblacklist.wire.com/prod/ios"]);
    XCTAssertEqualObjects(staging.blackListURL, [NSURL URLWithString:@"https://clientblacklist.wire.com/staging/ios"]);
}

- (void)testThatItSetsTheUserAgentOnStart;
{
    // given
    NSString *version = @"The-version-123";
    id transportSession = [OCMockObject niceMockForClass:ZMTransportSession.class];
    [[[[transportSession stub] classMethod] andReturn:transportSession] alloc];
    (void) [[[transportSession expect] andReturn:transportSession] initWithBaseURL:OCMOCK_ANY websocketURL:OCMOCK_ANY mainGroupQueue:OCMOCK_ANY initialAccessToken:OCMOCK_ANY application:OCMOCK_ANY sharedContainerIdentifier:OCMOCK_ANY];
    [[[transportSession stub] andReturn:[OCMockObject niceMockForClass:[ZMPersistentCookieStorage class]]] cookieStorage];
    
    // expect
    id userAgent = [OCMockObject mockForClass:ZMUserAgent.class];
    [[[userAgent expect] classMethod] setWireAppVersion:version];
    
    // when
    ZMUserSession *session = [[ZMUserSession alloc] initWithMediaManager:nil
                                                               analytics:nil
                                                              appVersion:version
                                                      appGroupIdentifier:self.groupIdentifier];
    XCTAssertNotNil(session);
    
    // then
    [userAgent verify];
    [userAgent stopMocking];
    [session tearDown];
    [transportSession stopMocking];
}

- (void)testThatWeCanGetAManagedObjectContext
{

    // when
    NSManagedObjectContext *moc = [self.sut managedObjectContext];
    NSManagedObjectContext *moc2 = [self.sut managedObjectContext];

    // then
    XCTAssertNotNil(moc);
    XCTAssertNotNil(moc2);
    XCTAssertEqual(moc, moc2);
}

- (void)testThatSyncContextReturnsSelfForLinkedSyncContext
{
    // given
    XCTAssertNotNil(self.sut.syncManagedObjectContext);
    // when & then
    XCTAssertEqual(self.sut.syncManagedObjectContext, self.sut.syncManagedObjectContext.zm_syncContext);
}

- (void)testThatUIContextReturnsSelfForLinkedUIContext
{
    // given
    XCTAssertNotNil(self.sut.managedObjectContext);
    // when & then
    XCTAssertEqual(self.sut.managedObjectContext, self.sut.managedObjectContext.zm_userInterfaceContext);
}

- (void)testThatSyncContextReturnsLinkedUIContext
{
    // given
    XCTAssertNotNil(self.sut.syncManagedObjectContext);
    // when & then
    XCTAssertEqual(self.sut.syncManagedObjectContext.zm_userInterfaceContext, self.sut.managedObjectContext);
}

- (void)testThatUIContextReturnsLinkedSyncContext
{
    // given
    XCTAssertNotNil(self.sut.managedObjectContext);
    // when & then
    XCTAssertEqual(self.sut.managedObjectContext.zm_syncContext, self.sut.syncManagedObjectContext);
}

- (void)testThatLinkedUIContextIsNotStrongReferenced
{
    NSManagedObjectContext *mocSync = nil;
    @autoreleasepool {
        // given
        NSManagedObjectContext *mocUI = [[NSManagedObjectContext alloc] init];

        mocSync = [[NSManagedObjectContext alloc] init];
        
        mocUI.zm_syncContext = mocSync;
        mocSync.zm_userInterfaceContext = mocUI;
        
        XCTAssertNotNil(mocUI.zm_syncContext);
        XCTAssertNotNil(mocSync.zm_userInterfaceContext);
        
        // when
        mocUI = nil;
    }
    
    // then
    XCTAssertNotNil(mocSync);
    XCTAssertNil(mocSync.zm_userInterfaceContext);
}

- (void)testThatLinkedSyncContextIsNotStrongReferenced
{
    NSManagedObjectContext *mocUI = nil;
    @autoreleasepool {
        // given
        mocUI = [[NSManagedObjectContext alloc] init];
        
        NSManagedObjectContext *mocSync = [[NSManagedObjectContext alloc] init];
        
        mocUI.zm_syncContext = mocSync;
        mocSync.zm_userInterfaceContext = mocUI;
        
        XCTAssertNotNil(mocUI.zm_syncContext);
        XCTAssertNotNil(mocSync.zm_userInterfaceContext);
        
        // when
        mocSync = nil;
    }
    
    // then
    XCTAssertNotNil(mocUI);
    XCTAssertNil(mocUI.zm_syncContext);
}

- (void)testThatIsLoggedInIsFalseAtStartup
{
    // then
    XCTAssertFalse([self.sut isLoggedIn]);
}


- (void)testThatIsLoggedInIsTrueIfItHasACookieAndSelfUserRemoteIdAndRegisteredClientID
{
    // when
    [self simulateLoggedInUser];
    
    // then
    XCTAssertTrue([self.sut isLoggedIn]);
}

@end


@implementation ZMUserSessionTests (ZMClientRegistrationStatusDelegate)

- (void)testThatItNotfiesTheTransportSessionWhenSelfUserClientIsRegistered
{
    // given
    UserClient *userClient = [self createSelfClient];
    id transportSession = [OCMockObject niceMockForClass:ZMTransportSession.class];
    id cookieStorage = [OCMockObject niceMockForClass:ZMPersistentCookieStorage.class];
    
    // expect
    [[transportSession expect] setClientID:userClient.remoteIdentifier];
    [[transportSession expect] restartPushChannel];
    [[[transportSession stub] andReturn:cookieStorage] cookieStorage];
    
    // when
    ZMUserSession *userSession = [[ZMUserSession alloc] initWithTransportSession:transportSession
                                                            userInterfaceContext:self.uiMOC
                                                        syncManagedObjectContext:self.syncMOC
                                                                    mediaManager:self.mediaManager
                                                                 apnsEnvironment:self.apnsEnvironment
                                                                   operationLoop:nil
                                                                     application:self.application
                                                                      appVersion:@"00000"
                                                              appGroupIdentifier:self.groupIdentifier];
    [userSession didRegisterUserClient:userClient];
    
    // then
    [transportSession verify];
    [userSession tearDown];
}

- (void)testThatItReturnsTheFingerprintForSelfUserClient
{
    // given
    UserClient *userClient = [self createSelfClient];
    
    // when & then
    XCTAssertNotNil(userClient.fingerprint);
}

- (void)testThatItReturnsTheFingerprintForUserClient
{
    // given
    UserClient *selfUser = [self createSelfClient];
    
    ZMUser *user1 = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
    user1.remoteIdentifier = [NSUUID createUUID];
    UserClient *user1Client1 = [UserClient insertNewObjectInManagedObjectContext:self.syncMOC];
    user1Client1.user = user1;
    user1Client1.remoteIdentifier = @"aabbccdd11";
    [self.syncMOC saveOrRollback];
    
    // when
    [selfUser establishSessionWithClient:user1Client1 usingPreKey:@"pQABAQICoQBYIGnflzMYd4OvMaHKfcIJzlb1fvEIhBx4qN545db7ZDBrA6EAoQBYIH7q8TQbCCuaMLYW6yW7NzLsU/OA7ea7Xs/hAyXK1jETBPY="];
    
    // then
    XCTAssertNotNil(user1Client1.fingerprint);
}

- (void)testThatFingerprintIsMissingForUnknownClient
{
    // given
    [self createSelfClient];
    ZMUser *user1 = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
    UserClient *user1Client1 = [UserClient insertNewObjectInManagedObjectContext:self.syncMOC];
    user1Client1.user = user1;
    user1Client1.remoteIdentifier = @"aabbccdd11";
    
    // when & then
    XCTAssertNil(user1Client1.fingerprint);
}

@end


@implementation ZMUserSessionTests (PerformChanges)

- (void)testThatPerformChangesAreDoneSynchronouslyOnTheMainQueue
{
    // given
    __block BOOL executed = NO;
    __block BOOL contextSaved = NO;
    
    // expect
    [[NSNotificationCenter defaultCenter] addObserverForName:NSManagedObjectContextDidSaveNotification object:self.uiMOC queue:nil usingBlock:^(NSNotification *note) {
        NOT_USED(note);
        contextSaved = YES;
    }];
    
    // when
    [self.sut performChanges:^{
        XCTAssertEqual([NSOperationQueue currentQueue], [NSOperationQueue mainQueue]);
        XCTAssertFalse(executed);
        XCTAssertFalse(contextSaved);
        executed = YES;
        [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC]; // force a save
    }];
    
    // then
    XCTAssertTrue(contextSaved);
    XCTAssertTrue(executed);
}

- (void)testThatEnqueueChangesAreDoneAsynchronouslyOnTheMainQueue
{
    // given
    __block BOOL executed = NO;
    __block BOOL contextSaved = NO;
    
    // expect
    [[NSNotificationCenter defaultCenter] addObserverForName:NSManagedObjectContextDidSaveNotification object:self.uiMOC queue:nil usingBlock:^(NSNotification *note) {
        NOT_USED(note);
        contextSaved = YES;
    }];
    
    // when
    [self.sut enqueueChanges:^{
        XCTAssertEqual([NSOperationQueue currentQueue], [NSOperationQueue mainQueue]);
        XCTAssertFalse(executed);
        XCTAssertFalse(contextSaved);
        executed = YES;
        [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC]; // force a save
    }];
    
    // then
    XCTAssertFalse(executed);
    XCTAssertFalse(contextSaved);

    // and when
    [self spinMainQueueWithTimeout:0.05];
    
    // then
    XCTAssertTrue(contextSaved);
    XCTAssertTrue(executed);
}


- (void)testThatEnqueueChangesAreDoneAsynchronouslyOnTheMainQueueWithCompletionHandler
{
    // given
    __block BOOL executed = NO;
    __block BOOL blockExecuted = NO;
    __block BOOL contextSaved = NO;
    
    // expect
    [[NSNotificationCenter defaultCenter] addObserverForName:NSManagedObjectContextDidSaveNotification object:self.uiMOC queue:nil usingBlock:^(NSNotification *note) {
        NOT_USED(note);
        contextSaved = YES;
    }];
    
    // when
    [self.sut enqueueChanges:^{
        XCTAssertEqual([NSOperationQueue currentQueue], [NSOperationQueue mainQueue]);
        XCTAssertFalse(executed);
        XCTAssertFalse(contextSaved);
        executed = YES;
        [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC]; // force a save
    } completionHandler:^{
        XCTAssertTrue(executed);
        XCTAssertEqual([NSOperationQueue currentQueue], [NSOperationQueue mainQueue]);
        XCTAssertFalse(blockExecuted);
        XCTAssertTrue(contextSaved);
        blockExecuted = YES;
    }];
    
    // then
    XCTAssertFalse(executed);
    XCTAssertFalse(blockExecuted);
    XCTAssertFalse(contextSaved);

    // and when
    [self spinMainQueueWithTimeout:0.05];
    
    // then
    XCTAssertTrue(executed);
    XCTAssertTrue(blockExecuted);
    XCTAssertTrue(contextSaved);
}

@end



@implementation ZMUserSessionTests (AuthenticationCenter)

- (void)testThatRegistrationDidFailNotifiesTheAuthenticationObserver
{
    // given
    NSError *error = [NSError errorWithDomain:@"foo" code:201 userInfo:@{}];
    
    // expect
    [[(id) self.registrationObserver expect] registrationDidFail:[OCMArg checkWithBlock:^BOOL(NSError *receivedError) {
        XCTAssertEqual([NSOperationQueue currentQueue], [NSOperationQueue mainQueue]);
        XCTAssertEqualObjects(error, receivedError);
        return YES;
    }]];
    
    // when
    [ZMUserSessionRegistrationNotification notifyRegistrationDidFail:error];
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatAuthenticationDidSucceedNotifiesTheAuthenticationObserver
{
    // expect
    [[[(id) self.authenticationObserver expect] andDo:^(NSInvocation *i ZM_UNUSED){
        XCTAssertEqual([NSOperationQueue currentQueue], [NSOperationQueue mainQueue]);
    }] authenticationDidSucceed];
    
    // when
    [ZMUserSessionAuthenticationNotification notifyAuthenticationDidSucceed];
    WaitForAllGroupsToBeEmpty(0.5);
}


- (void)testThatAuthenticationDidFailNotifiesTheAuthenticationObserver
{
    // given
    NSError *error = [NSError errorWithDomain:@"foo" code:201 userInfo:@{}];
    
    // expect
    [[(id) self.authenticationObserver expect] authenticationDidFail:[OCMArg checkWithBlock:^BOOL(NSError *receivedError) {
        XCTAssertEqual([NSOperationQueue currentQueue], [NSOperationQueue mainQueue]);
        XCTAssertEqualObjects(error, receivedError);
        return YES;
    }]];
    
    // when
    [ZMUserSessionAuthenticationNotification notifyAuthenticationDidFail:error];
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatItNotifiesAuthenticationCenterObserversWhenTheCredentialsChange
{
    // given
    self.dataChangeNotificationsCount = 0;
    
    // when
    [self.sut.authenticationStatus prepareForLoginWithCredentials:[ZMEmailCredentials credentialsWithEmail:@"bar@bar.bar" password:@"boo"]];
    
    // then
    XCTAssertEqual(self.dataChangeNotificationsCount, 1u);
}

@end



@implementation ZMUserSessionTests (PushToken)

- (void)testThatItSetsThePushToken;
{
    // given
    uint8_t const tokenData[] = {
        0xc5, 0xe2, 0x4e, 0x41, 0xe4, 0xd4, 0x32, 0x90, 0x37, 0x92, 0x84, 0x49, 0x34, 0x94, 0x87, 0x54, 0x7e, 0xf1, 0x4f, 0x16, 0x2c, 0x77, 0xae, 0xe3, 0xaa, 0x8e, 0x12, 0xa3, 0x9c, 0x8d, 0xb1, 0xd5,
    };
    NSData * const deviceToken = [NSData dataWithBytes:tokenData length:sizeof(tokenData)];
    XCTAssertNil(self.sut.managedObjectContext.pushToken);
    [[self.transportSession stub] attemptToEnqueueSyncRequestWithGenerator:OCMOCK_ANY];
    
    // when
    [self.sut setPushToken:deviceToken];
    ZMPushToken *pushToken = self.sut.managedObjectContext.pushToken;
    
    // then
    XCTAssertNotNil(pushToken);
    XCTAssertEqualObjects(pushToken.deviceToken, deviceToken);
    XCTAssertNotNil(pushToken.appIdentifier);
    XCTAssertTrue([pushToken.appIdentifier hasPrefix:@"com.wire."]);
    XCTAssertFalse(pushToken.isRegistered);
}

- (void)testThatItResetsThePushTokensWhenNotificationIsFired
{
    // given
    id partialSessionMock = [OCMockObject partialMockForObject:self.sut];
    
    // expect
    [[partialSessionMock expect] resetPushTokens];
    
    // when
    [[NSNotificationCenter defaultCenter] postNotificationName:ZMUserSessionResetPushTokensNotificationName object:nil];
    
    // then
    [partialSessionMock verify];
    [partialSessionMock stopMocking];
}

@end


@implementation ZMUserSessionTests (NetworkState)

- (void)testThatItSetsItselfAsADelegateOfTheTransportSessionAndForwardsUserClientID
{
    // given
    id transportSession = [OCMockObject mockForClass:ZMTransportSession.class];

    [[transportSession stub] openPushChannelWithConsumer:OCMOCK_ANY groupQueue:OCMOCK_ANY];
    [[transportSession stub] closePushChannelAndRemoveConsumer];
    self.cookieStorage = [ZMPersistentCookieStorage storageForServerName:@"usersessiontest.example.com"];
    [[[transportSession stub] andReturn:self.cookieStorage] cookieStorage];
    self.authenticationObserver = [OCMockObject mockForProtocol:@protocol(ZMAuthenticationObserver)];
    [[transportSession stub] setAccessTokenRenewalFailureHandler:[OCMArg checkWithBlock:^BOOL(ZMCompletionHandlerBlock obj) {
        self.authFailHandler = obj;
        return YES;
    }]];
    [[transportSession stub] setAccessTokenRenewalSuccessHandler:[OCMArg checkWithBlock:^BOOL(ZMAccessTokenHandlerBlock obj) {
        self.tokenSuccessHandler = obj;
        return YES;
    }]];
    
    [[transportSession stub] attemptToEnqueueSyncRequestWithGenerator:OCMOCK_ANY];

    // expect
    [[transportSession expect] setNetworkStateDelegate:OCMOCK_ANY];
    [[transportSession expect] setClientID:OCMOCK_ANY];

    // when
    ZMUserSession *testSession = [[ZMUserSession alloc] initWithTransportSession:transportSession
                                                            userInterfaceContext:self.uiMOC
                                                        syncManagedObjectContext:self.syncMOC
                                                                    mediaManager:self.mediaManager
                                                                 apnsEnvironment:self.apnsEnvironment
                                                                   operationLoop:nil
                                                                     application:self.application
                                                                      appVersion:@"00000"
                                                              appGroupIdentifier:self.groupIdentifier];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    [transportSession verify];
    [testSession tearDown];
}

- (BOOL)waitForStatus:(ZMNetworkState)state
{
    return ([self waitOnMainLoopUntilBlock:^BOOL{
        return self.sut.networkState == state;
    } timeout:0.5]);
}

- (BOOL)waitForOfflineStatus
{
    return [self waitForStatus:ZMNetworkStateOffline];
}

- (BOOL)waitForOnlineStatus
{
    return [self waitForStatus:ZMNetworkStateOnline];
}

- (void)testThatWeSetUserSessionToOnlineWhenWeDidReceiveData
{
    // when
    [self.sut didGoOffline];
    [self.sut didReceiveData];

    // then
    XCTAssertTrue([self waitForOnlineStatus]);

}

- (void)testThatWeSetUserSessionToOfflineWhenARequestFails
{
    // when
    [self.sut didGoOffline];
    
    // then
    XCTAssertTrue([self waitForOfflineStatus]);
}

- (void)testThatWeSetUserSessionToSyncDoneWhenSyncIsDone
{
    // when
    [self.sut didStartSync];
    [self.sut didFinishSync];
    
    // then
    XCTAssertTrue([self waitForStatus:ZMNetworkStateOnline]);
}

- (void)testThatItNotifiesThirdPartyServicesWhenSyncIsDone
{
    // given
    XCTAssertEqual(self.thirdPartyServices.uploadCount, 0u);
    
    // when
    [self.sut didFinishSync];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(self.thirdPartyServices.uploadCount, 1u);
}

- (void)testThatItOnlyNotifiesThirdPartyServicesOne
{
    // given
    XCTAssertEqual(self.thirdPartyServices.uploadCount, 0u);
    
    // when
    [self.sut didFinishSync];
    [self.sut didStartSync];
    [self.sut didFinishSync];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(self.thirdPartyServices.uploadCount, 1u);
}

#if TARGET_OS_IPHONE
- (void)testThatItNotifiesThirdPartyServicesWhenEnteringBackground;
{
    // given
    XCTAssertEqual(self.thirdPartyServices.uploadCount, 0u);
    
    // when
    [self.sut applicationDidEnterBackground:nil];
    
    // then
    XCTAssertEqual(self.thirdPartyServices.uploadCount, 1u);
}

- (void)testThatItNotifiesThirdPartyServicesAgainAfterEnteringForeground_1;
{
    // given
    XCTAssertEqual(self.thirdPartyServices.uploadCount, 0u);
    
    // when
    [self.sut applicationDidEnterBackground:nil];
    [self.sut applicationWillEnterForeground:nil];
    [self.sut applicationDidEnterBackground:nil];
    
    // then
    XCTAssertEqual(self.thirdPartyServices.uploadCount, 2u);
}

- (void)testThatItNotifiesThirdPartyServicesAgainAfterEnteringForeground_2;
{
    // given
    XCTAssertEqual(self.thirdPartyServices.uploadCount, 0u);
    
    // when
    [self.sut didFinishSync];
    [self.sut applicationDidEnterBackground:nil];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(self.thirdPartyServices.uploadCount, 1u);

    [self.sut applicationWillEnterForeground:nil];
    [self.sut didStartSync];
    [self.sut didFinishSync];
    [self.sut applicationDidEnterBackground:nil];
    
    // then
    XCTAssertEqual(self.thirdPartyServices.uploadCount, 2u);
}

#endif

- (void)testThatWeDoNotSetUserSessionToSyncDoneWhenSyncIsDoneIfWeWereNotSynchronizing
{
    // when
    [self.sut didGoOffline];
    [self.sut didFinishSync];
    
    // then
    XCTAssertTrue([self waitForOfflineStatus]);
}


- (void)testThatWeSetUserSessionToSynchronizingWhenSyncIsStarted
{
    // when
    [self.sut didStartSync];
    
    // then
    XCTAssertTrue([self waitForStatus:ZMNetworkStateOnlineSynchronizing]);
}

- (void)testThatWeCanGoBackOnlineAfterGoingOffline
{
    // when
    [self.sut didGoOffline];
    
    // then
    XCTAssertTrue([self waitForOfflineStatus]);
    
    // when
    [self.sut didReceiveData];
    
    // then
    XCTAssertTrue([self waitForOnlineStatus]);

}

- (void)testThatWeCanGoBackOfflineAfterGoingOnline
{
    // when
    [self.sut didGoOffline];
    
    // then
    XCTAssertTrue([self waitForOfflineStatus]);
    
    // when
    [self.sut didReceiveData];
    
    // then
    XCTAssertTrue([self waitForOnlineStatus]);

    // when
    [self.sut didGoOffline];
    
    // then
    XCTAssertTrue([self waitForOfflineStatus]);

}


- (void)testThatItNotifiesObserversWhenTheNetworkStatusBecomesOnline
{
    // given
    id observer = [OCMockObject mockForProtocol:@protocol(ZMNetworkAvailabilityObserver)];
    [self.sut didGoOffline];
    XCTAssertTrue([self waitForOfflineStatus]);
    XCTAssertEqual(self.sut.networkState, ZMNetworkStateOffline);
    
    // expect
    [[observer expect] didChangeAvailability:[OCMArg checkWithBlock:^BOOL(ZMNetworkAvailabilityChangeNotification *note) {
        return note.networkState == ZMNetworkStateOnline;
    }]];
    
    // when
    [ZMNetworkAvailabilityChangeNotification addNetworkAvailabilityObserver:observer userSession:self.sut];
    [self.sut didReceiveData];
    
    // then
    XCTAssertTrue([self waitForOnlineStatus]);
    [observer verify];
    
    // after
    [ZMNetworkAvailabilityChangeNotification removeNetworkAvailabilityObserver:observer];
}

- (void)testThatItDoesNotNotifiesObserversWhenTheNetworkStatusWasAlreadyOnline
{
    // given
    id observer = [OCMockObject mockForProtocol:@protocol(ZMNetworkAvailabilityObserver)];
    
    // expect
    [[observer reject] didChangeAvailability:OCMOCK_ANY];
    
    // when
    [ZMNetworkAvailabilityChangeNotification addNetworkAvailabilityObserver:observer userSession:self.sut];
    [self.sut didReceiveData];
    
    // then
    WaitForAllGroupsToBeEmpty(0.5);
    [observer verify];
    
    // after
    [ZMNetworkAvailabilityChangeNotification removeNetworkAvailabilityObserver:observer];
    
}

- (void)testThatItNotifiesObserversWhenTheNetworkStatusBecomesOffline
{
    // given
    id observer = [OCMockObject mockForProtocol:@protocol(ZMNetworkAvailabilityObserver)];
    
    // expect
    [[observer expect] didChangeAvailability:[OCMArg checkWithBlock:^BOOL(ZMNetworkAvailabilityChangeNotification *note) {
        return note.networkState == ZMNetworkStateOffline;
    }]];
    
    // when
    [ZMNetworkAvailabilityChangeNotification addNetworkAvailabilityObserver:observer userSession:self.sut];
    [self.sut didGoOffline];
    
    // then
    XCTAssertTrue([self waitForOfflineStatus]);
    [observer verify];
    
    // after
    [ZMNetworkAvailabilityChangeNotification removeNetworkAvailabilityObserver:observer];
}

- (void)testThatItDoesNotNotifiesObserversWhenTheNetworkStatusWasAlreadyOffline
{
    // given
    id observer = [OCMockObject mockForProtocol:@protocol(ZMNetworkAvailabilityObserver)];
    [self.sut didGoOffline];
    XCTAssertTrue([self waitForOfflineStatus]);
    
    // expect
    [[observer reject] didChangeAvailability:OCMOCK_ANY];
    
    // when
    [ZMNetworkAvailabilityChangeNotification addNetworkAvailabilityObserver:observer userSession:self.sut];
    [self.sut didGoOffline];
    
    // then
    WaitForAllGroupsToBeEmpty(0.5);
    [observer verify];
    
    // after
    [ZMNetworkAvailabilityChangeNotification removeNetworkAvailabilityObserver:observer];
    
}

@end



@implementation ZMUserSessionTests (CommonContacts)

- (void)testThatSearchingForDifferentUsersReturnsDifferentTokens
{
    // when
    id<ZMCommonContactsSearchToken> token1 = [self.sut searchCommonContactsWithUserID:[NSUUID createUUID] searchDelegate:nil];
    id<ZMCommonContactsSearchToken> token2 = [self.sut searchCommonContactsWithUserID:[NSUUID createUUID] searchDelegate:nil];

    // then
    XCTAssertNotEqualObjects(token1, token2);
}

- (void)testThatSearchingForTheSameUserTwiceReturnsDifferentTokens
{
    // given
    NSUUID *search = [NSUUID createUUID];
    
    // when
    id<ZMCommonContactsSearchToken> token1 = [self.sut searchCommonContactsWithUserID:search searchDelegate:nil];
    id<ZMCommonContactsSearchToken> token2 = [self.sut searchCommonContactsWithUserID:search searchDelegate:nil];
    
    // then
    XCTAssertNotEqualObjects(token1, token2);
}

- (void)testThatItForwardsASearchToZMCommonContactsSearch
{
    // given
    NSUUID *expectedUI = [NSUUID createUUID];
    __block id<ZMCommonContactsSearchToken> receivedToken;
    
    id mockDelegate = [OCMockObject mockForProtocol:@protocol(ZMCommonContactsSearchDelegate)];
    
    // expect
    id mockCommonContactsSearch = [OCMockObject mockForClass:ZMCommonContactsSearch.class];
    [[[mockCommonContactsSearch expect] classMethod] startSearchWithTransportSession:self.transportSession userID:expectedUI token:[OCMArg checkWithBlock:^BOOL(id obj) {
        receivedToken = obj;
        return YES;
    }] syncMOC:self.syncMOC uiMOC:self.uiMOC searchDelegate:mockDelegate resultsCache:OCMOCK_ANY];
    
    // when
    id<ZMCommonContactsSearchToken> token = [self.sut searchCommonContactsWithUserID:expectedUI searchDelegate:mockDelegate];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    [mockDelegate verify];
    [mockCommonContactsSearch verify];
    XCTAssertNotNil(token);
    XCTAssertEqual(token, receivedToken);
    
    // after
    [mockCommonContactsSearch stopMocking];
}

- (void)testThatItForwardsASearchToZMCommonContactsSearchUsingTheSameCache
{
    // given
    __block id passedCache;
    
    id mockDelegate = [OCMockObject mockForProtocol:@protocol(ZMCommonContactsSearchDelegate)];
    
    // expect
    id mockCommonContactsSearch = [OCMockObject mockForClass:ZMCommonContactsSearch.class];
    [[[mockCommonContactsSearch expect] classMethod] startSearchWithTransportSession:self.transportSession userID:OCMOCK_ANY token:OCMOCK_ANY syncMOC:self.syncMOC uiMOC:self.uiMOC searchDelegate:mockDelegate resultsCache:[OCMArg checkWithBlock:^BOOL(id obj) {
        passedCache = obj;
        return YES;
    }]];
    
    [[[mockCommonContactsSearch expect] classMethod] startSearchWithTransportSession:self.transportSession userID:OCMOCK_ANY token:OCMOCK_ANY syncMOC:self.syncMOC uiMOC:self.uiMOC searchDelegate:mockDelegate resultsCache:[OCMArg checkWithBlock:^BOOL(id obj) {
        return obj == passedCache;
    }]];
    
    
    // when
    [self.sut searchCommonContactsWithUserID:[NSUUID createUUID] searchDelegate:mockDelegate];
    [self.sut searchCommonContactsWithUserID:[NSUUID createUUID] searchDelegate:mockDelegate];
    WaitForAllGroupsToBeEmpty(0.5);
    
    
    // then
    [mockDelegate verify];
    [mockCommonContactsSearch verify];
    XCTAssertNotNil(passedCache);
    
    // after
    [mockCommonContactsSearch stopMocking];
}

@end



#if TARGET_OS_IPHONE

@implementation ZMUserSessionTests (RemoteNotifications)

- (UILocalNotification *)notificationWithConversationForCategory:(NSString *)category
{
    __block ZMConversation *conversation;
    [self.syncMOC performGroupedBlockAndWait:^{
        conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        conversation.conversationType = ZMConversationTypeOneOnOne;
        conversation.remoteIdentifier = [NSUUID UUID];
        [self.syncMOC saveOrRollback];
    }];
    
    UILocalNotification *note = [[UILocalNotification alloc] init];
    note.category = category;
    note.userInfo = @{@"conversationIDString": conversation.remoteIdentifier.transportString};
    
    return note;
}

- (UILocalNotification *)notificationWithConnectionRequestFromSender:(ZMUser *)sender
{
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    conversation.conversationType = ZMConversationTypeConnection;
    conversation.remoteIdentifier = [NSUUID createUUID];
    ZMConnection *connection = [ZMConnection insertNewObjectInManagedObjectContext:self.uiMOC];
    connection.conversation = conversation;
    connection.to = sender;
    connection.status = ZMConnectionStatusPending;
    
    [self.uiMOC saveOrRollback];
    
    UILocalNotification *note = [[UILocalNotification alloc] init];
    note.category = ZMConnectCategory;
    note.userInfo = @{@"conversationIDString": conversation.remoteIdentifier.transportString,
                      @"senderIDString" : sender.remoteIdentifier.transportString};
    
    return note;
}

- (void)testThatItStoresThePushToken
{
    // given
    NSData *deviceToken = [NSData dataWithBytes:@"bla" length:3];
    ZMPushToken *pushToken = [[ZMPushToken alloc] initWithDeviceToken:deviceToken
                                                           identifier:@"com.wire.ent"
                                                        transportType:@"APNS"
                                                             fallback:nil
                                                         isRegistered:YES];
    // expect
    id mockRemoteRegistrant = [OCMockObject partialMockForObject:self.sut.applicationRemoteNotification];
    [(ZMApplicationRemoteNotification *)[[mockRemoteRegistrant expect] andForwardToRealObject] application:OCMOCK_ANY didRegisterForRemoteNotificationsWithDeviceToken:deviceToken];
    
    // when
    [self.sut application:OCMOCK_ANY didRegisterForRemoteNotificationsWithDeviceToken:deviceToken];
    
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqualObjects(self.uiMOC.pushToken, pushToken);
    [mockRemoteRegistrant verify];
}

- (void)testThatItMarksThePushTokenAsNotRegisteredAfterResetting
{
    // given
    NSData *deviceToken = [NSData dataWithBytes:@"bla" length:3];
    ZMPushToken *pushToken = [[ZMPushToken alloc] initWithDeviceToken:deviceToken
                                                           identifier:@"com.wire.ent"
                                                        transportType:@"APNS"
                                                             fallback:@"APNS"
                                                         isRegistered:YES];
    self.uiMOC.pushToken = pushToken;
    
    // when
    [self performIgnoringZMLogError:^{
        [self.sut resetPushTokens];
        WaitForAllGroupsToBeEmpty(0.5);
    }];
    
    // then
    XCTAssertFalse(self.uiMOC.pushToken.isRegistered);
}

- (void)testThatItCallsRegisterForPushNotificationsIfNoPushTokenIsSet
{
    // given
    XCTAssertNil(self.uiMOC.pushToken);
    id mockPushRegistrant = [OCMockObject partialMockForObject:self.sut.pushRegistrant];
    [(ZMPushRegistrant *)[[mockPushRegistrant stub] andReturn:[NSData data]] pushToken];
    
    // when
    [self performIgnoringZMLogError:^{
        [self.sut resetPushTokens];
        WaitForAllGroupsToBeEmpty(0.5);
    }];

    // then
    XCTAssertEqual(self.application.registerForRemoteNotificationCount, 1u);
}

- (void)testThatItCallsRegisterForPushNotificationsAgainIfNoPushTokenIsSet
{
    // given
    XCTAssertNil(self.uiMOC.pushToken);
    id mockPushRegistrant = [OCMockObject partialMockForObject:self.sut.pushRegistrant];
    [(ZMPushRegistrant *)[[mockPushRegistrant stub] andReturn:[NSData data]] pushToken];
    
    // when
    [self performIgnoringZMLogError:^{
        [self.sut resetPushTokens];
        [self.sut resetPushTokens];
        WaitForAllGroupsToBeEmpty(0.5);
    }];
    
    // then
    XCTAssertEqual(self.application.registerForRemoteNotificationCount, 2u);
}

- (void)testThatItMarksPushTokenAsNotRegisteredWhenResettingEvenIfItHasSameData
{
    // given
    NSData *deviceToken = [NSData dataWithBytes:@"bla" length:3];
    ZMPushToken *pushToken = [[ZMPushToken alloc] initWithDeviceToken:deviceToken
                                                           identifier:@"com.wire.ent"
                                                        transportType:@"APNS_VOIP"
                                                             fallback:@"APNS"
                                                         isRegistered:YES];
    id mockPushRegistrant = [OCMockObject partialMockForObject:self.sut.pushRegistrant];
    [(ZMPushRegistrant *)[[mockPushRegistrant stub] andReturn:deviceToken] pushToken];
    self.uiMOC.pushKitToken = pushToken;
    
    // when
    [self performIgnoringZMLogError:^{
        [self.sut resetPushTokens];
        WaitForAllGroupsToBeEmpty(0.5);
    }];
    
    // then
    XCTAssertEqual(self.application.registerForRemoteNotificationCount, 1u);
    XCTAssertFalse(self.uiMOC.pushKitToken.isRegistered);
}

- (void)testThatItStoresThePushKitToken
{
    // given
    NSData *deviceToken = [NSData dataWithBytes:@"bla" length:3];
    ZMPushToken *pushToken = [[ZMPushToken alloc] initWithDeviceToken:deviceToken
                                                           identifier:@"com.wire.ent"
                                                        transportType:@"APNS_VOIP"
                                                             fallback:@"APNS"
                                                         isRegistered:NO];
    // expect
    id mockPushRegistrant = [OCMockObject partialMockForObject:self.sut.pushRegistrant];
    [(ZMPushRegistrant *)[[mockPushRegistrant expect] andReturn:deviceToken] pushToken];
    [[[self.apnsEnvironment expect] andReturn:@"APNS"] fallbackForTransportType:ZMAPNSTypeVoIP];
    
    // when
    [self performIgnoringZMLogError:^{
        [self.sut resetPushTokens];
        WaitForAllGroupsToBeEmpty(0.5);
    }];
    
    // then
    [mockPushRegistrant verify];
    [self.apnsEnvironment verify];
    XCTAssertEqualObjects(self.uiMOC.pushKitToken, pushToken);
    XCTAssertFalse(self.uiMOC.pushKitToken.isRegistered);
}


- (void)testThatIt_DoesNot_ForwardsRemoteNotificationsWhileRunning_WhenNotLoggedIn;
{
    // expect
    NSDictionary *remoteNotification = @{@"a": @"b"};
    [[self.operationLoop reject] saveEventsAndSendNotificationForPayload:remoteNotification fetchCompletionHandler:OCMOCK_ANY source:ZMPushNotficationTypeAlert];
    
    // when
    [self.sut application:OCMOCK_ANY didReceiveRemoteNotification:remoteNotification fetchCompletionHandler:^(UIBackgroundFetchResult result) {
        XCTAssertNotEqual(result, UIBackgroundFetchResultFailed);
    }];
    
    [self.operationLoop verify];
}

- (void)checkThatItCallsTheDelegateForNotification:(UILocalNotification *)notification responseInfo:(NSDictionary *)responseInfo actionIdentifier:(NSString *)actionIdentifier withBlock:(void (^)(id mockDelegate))block
{
    id mockDelegate = [OCMockObject mockForProtocol:@protocol(ZMRequestsToOpenViewsDelegate)];
    
    // expect
    block(mockDelegate);
    
    // when
    __block BOOL didCallCompletionHandler = NO;
    self.sut.requestToOpenViewDelegate = mockDelegate;
    [self.sut application:self.application handleActionWithIdentifier:actionIdentifier forLocalNotification:notification responseInfo:responseInfo completionHandler:^{
        didCallCompletionHandler = YES;
    }];
    
    WaitForAllGroupsToBeEmpty(0.5);
    [[NSNotificationCenter defaultCenter] postNotificationName:@"ZMApplicationDidEnterEventProcessingStateNotification" object:nil];
    WaitForAllGroupsToBeEmpty(0.5);
    
    [mockDelegate verify];
    XCTAssertTrue(didCallCompletionHandler);
}

- (void)checkThatItCallsOnLaunchTheDelegateForNotification:(UILocalNotification *)notification withBlock:(void (^)(id mockDelegate))block
{
    id mockDelegate = [OCMockObject mockForProtocol:@protocol(ZMRequestsToOpenViewsDelegate)];
    
    NSDictionary *launchOptions = @{UIApplicationLaunchOptionsLocalNotificationKey: notification};
    
    // expect
    block(mockDelegate);
    
    // when
    self.sut.requestToOpenViewDelegate = mockDelegate;
    [self.sut application:self.application didFinishLaunchingWithOptions:launchOptions];
    
    WaitForAllGroupsToBeEmpty(0.5);
    [[NSNotificationCenter defaultCenter] postNotificationName:@"ZMApplicationDidEnterEventProcessingStateNotification" object:nil];
    WaitForAllGroupsToBeEmpty(0.5);
    
    [mockDelegate verify];
}


- (void)testThatItCalls_DelegateShowConversationList_ForZMConversationCategory_NoConversation
{
    // given
    UILocalNotification *note = [[UILocalNotification alloc] init];
    note.category = ZMConversationCategory;
    
    // expect
    [self.application setInactive];

    [self checkThatItCallsTheDelegateForNotification:note responseInfo:nil actionIdentifier:nil withBlock:^(id mockDelegate) {
        [[mockDelegate expect] showConversationList];
    }];
}

- (void)testThat_OnLaunch_ItCalls_DelegateShowConversationList_ForZMConversationCategory_NoConversation_LoggedIn
{
    // given
    [self simulateLoggedInUser];
    
    UILocalNotification *note = [[UILocalNotification alloc] init];
    note.category = ZMConversationCategory;
    
    // expect
    [self.application setInactive];
    
    [self checkThatItCallsOnLaunchTheDelegateForNotification:note withBlock:^(id mockDelegate) {
        [[mockDelegate expect] showConversationList];
    }];
}

- (void)testThat_OnLaunch_ItDoesNotCall_DelegateShowConversationList_WhenNotLoggedIn
{
    // given
    UILocalNotification *note = [[UILocalNotification alloc] init];
    note.category = ZMConversationCategory;
    
    // expect
    [self checkThatItCallsOnLaunchTheDelegateForNotification:note withBlock:^(id mockDelegate) {
        [[mockDelegate reject] showConversationList];
        [[mockDelegate reject] showMessage:OCMOCK_ANY inConversation:OCMOCK_ANY];
        [[mockDelegate reject] showConversation:OCMOCK_ANY];
    }];
}


- (void)testThatItCalls_DelegateShowConversation_ForZMConversationCategory
{
    //given
    [[[self.transportSession stub] andReturn:nil] attemptToEnqueueSyncRequestWithGenerator:OCMOCK_ANY];
    UILocalNotification *note = [self notificationWithConversationForCategory:ZMConversationCategory];
    
    // expect
    [self.application setInactive];

    [self checkThatItCallsTheDelegateForNotification:note responseInfo:nil actionIdentifier:nil withBlock:^(id mockDelegate) {
        [[mockDelegate expect] showConversation:OCMOCK_ANY];
    }];
}


- (void)testThatItMutesAndDoesNotCall_DelegateShowConversation_ForZMConversationCategory_ZMConversationMuteAction
{
    //given
    [self simulateLoggedInUser];

    [[[self.transportSession stub] andReturn:nil] attemptToEnqueueSyncRequestWithGenerator:OCMOCK_ANY];
    UILocalNotification *note = [self notificationWithConversationForCategory:ZMConversationCategory];
    ZMConversation *conversation = [note conversationInManagedObjectContext:self.uiMOC];
    
    // expect
    [self.application setInactive];
    
    [self checkThatItCallsTheDelegateForNotification:note responseInfo:nil actionIdentifier:ZMConversationMuteAction withBlock:^(id mockDelegate) {
        [[mockDelegate reject] showConversation:OCMOCK_ANY];
    }];
    
    //then
    XCTAssertTrue(conversation.isSilenced);
}

- (void)testThat_OnLaunch_ItCalls_DelegateShowConversation_ForZMConversationCategory
{
    // given
    [self simulateLoggedInUser];

    [[[self.transportSession stub] andReturn:nil] attemptToEnqueueSyncRequestWithGenerator:OCMOCK_ANY];
    
    UILocalNotification *note = [self notificationWithConversationForCategory:ZMConversationCategory];
    
    // expect
    [self.application setInactive];

    [self checkThatItCallsOnLaunchTheDelegateForNotification:note withBlock:^(id mockDelegate) {
        [[mockDelegate expect] showConversation:OCMOCK_ANY];
    }];
}


- (void)testThatItCalls_DelegateShowConversation_ZMConnectCategory
{
    // given
    [self simulateLoggedInUser];
    
    [[[self.transportSession stub] andReturn:nil] attemptToEnqueueSyncRequestWithGenerator:OCMOCK_ANY];
    
    ZMUser *sender = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    sender.remoteIdentifier = NSUUID.createUUID;
    
    UILocalNotification *note = [self notificationWithConnectionRequestFromSender:sender];
    ZMConversation *conversation = [note conversationInManagedObjectContext:self.uiMOC];

    // expect
    [self.application setInactive];

    [self checkThatItCallsTheDelegateForNotification:note responseInfo:nil actionIdentifier:nil withBlock:^(id mockDelegate) {
        [[mockDelegate expect] showConversation:conversation];
    }];
    
    // then
    XCTAssertFalse(sender.isConnected);
}


- (void)testThatItCalls_DelegateShowConversation_AndConnectsTheUser_ZMConnectCategory_AcceptAction
{
    // given
    [self simulateLoggedInUser];
    
    [[[self.transportSession stub] andReturn:nil] attemptToEnqueueSyncRequestWithGenerator:OCMOCK_ANY];
    
    ZMUser *sender = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    sender.remoteIdentifier = NSUUID.createUUID;
    XCTAssertFalse(sender.isConnected);

    UILocalNotification *note = [self notificationWithConnectionRequestFromSender:sender];
    ZMConversation *conversation = [note conversationInManagedObjectContext:self.uiMOC];
    
    // expect
    [self.application setInactive];

    [self checkThatItCallsTheDelegateForNotification:note responseInfo:nil actionIdentifier:ZMConnectAcceptAction withBlock:^(id mockDelegate) {
        [[mockDelegate expect] showConversation:conversation];
    }];
    
    // then
    XCTAssertTrue(sender.isConnected);
}


- (void)testThatItCalls_DelegateShowConversationAndAcceptsCall_ZMConnectCategory
{
    // given
    [self simulateLoggedInUser];
    
    [[[self.transportSession stub] andReturn:nil] attemptToEnqueueSyncRequestWithGenerator:OCMOCK_ANY];

    UILocalNotification *note = [self notificationWithConversationForCategory:ZMIncomingCallCategory];
    ZMConversation *conversation = [note conversationInManagedObjectContext:self.uiMOC];

    [[conversation mutableOrderedSetValueForKey:@"callParticipants"] addObject:[ZMUser insertNewObjectInManagedObjectContext:self.uiMOC]];
    [self.uiMOC saveOrRollback];
    
    // expect
    [self.application setInactive];

    [self checkThatItCallsTheDelegateForNotification:note responseInfo:nil actionIdentifier:nil withBlock:^(id mockDelegate) {
        [[mockDelegate expect] showConversation:conversation];
    }];
    
    // then
    XCTAssertTrue(conversation.callDeviceIsActive);
}

- (void)testThatIt_DoesNotAcceptsCall_ButCallsDelegateShowConversation_ZMIncomingCallCategory_NoCallParticipants
{
    // given
    [self simulateLoggedInUser];
    
    [[[self.transportSession stub] andReturn:nil] attemptToEnqueueSyncRequestWithGenerator:OCMOCK_ANY];
    
    UILocalNotification *note = [self notificationWithConversationForCategory:ZMIncomingCallCategory];
    ZMConversation *conversation = [note conversationInManagedObjectContext:self.uiMOC];
    
    // expect
    [self.application setInactive];
    
    [self checkThatItCallsTheDelegateForNotification:note responseInfo:nil actionIdentifier:nil withBlock:^(id mockDelegate) {
        [[mockDelegate expect] showConversation:conversation];
    }];
    
    // then
    XCTAssertFalse(conversation.callDeviceIsActive);
}

- (void)testThatIt_DoesNotCall_DelegateShowConversationAndIgnoresCall_ZMIncomingCallCategory_IgnoreAction
{
    // given
    [self simulateLoggedInUser];
    
    [[[self.transportSession stub] andReturn:nil] attemptToEnqueueSyncRequestWithGenerator:OCMOCK_ANY];

    UILocalNotification *note = [self notificationWithConversationForCategory:ZMIncomingCallCategory];
    ZMConversation *conversation = [note conversationInManagedObjectContext:self.uiMOC];
    
    // expect
    [self.application setInactive];
    
    [self checkThatItCallsTheDelegateForNotification:note responseInfo:nil actionIdentifier:ZMCallIgnoreAction withBlock:^(id mockDelegate) {
        [[mockDelegate reject] showConversation:conversation];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertFalse(conversation.callDeviceIsActive);
    XCTAssertTrue(conversation.isIgnoringCall);
}


- (void)testThatItCalls_DelegateShowConversationAndCallsBack_ZMMissedCallCategory_CallBackAction
{
    // given
    [self simulateLoggedInUser];
    
    [[[self.transportSession stub] andReturn:nil] attemptToEnqueueSyncRequestWithGenerator:OCMOCK_ANY];
    
    UILocalNotification *note = [self notificationWithConversationForCategory:ZMMissedCallCategory];
    ZMConversation *conversation = [note conversationInManagedObjectContext:self.uiMOC];
    
    // expect
    [self.application setInactive];

    [self checkThatItCallsTheDelegateForNotification:note responseInfo:nil actionIdentifier:ZMCallAcceptAction withBlock:^(id mockDelegate) {
        [[mockDelegate expect] showConversation:conversation];
    }];
    
    // then
    XCTAssertTrue(conversation.callDeviceIsActive);

}

- (void)testThatItDoesNotCall_DelegateShowConversationAndAppendsAMessage_ZMConversationCategory_DirectReplyAction
{
    // given
    [self simulateLoggedInUser];
    
    [[[self.transportSession stub] andReturn:nil] attemptToEnqueueSyncRequestWithGenerator:OCMOCK_ANY];
    
    UILocalNotification *note = [self notificationWithConversationForCategory:ZMConversationCategory];
    ZMConversation *conversation = [note conversationInManagedObjectContext:self.uiMOC];
    NSDictionary *responseInfo = @{UIUserNotificationActionResponseTypedTextKey: @"Hello hello"};
    XCTAssertEqual(conversation.messages.count, 0u);

    // expect
    [self checkThatItCallsTheDelegateForNotification:note responseInfo:responseInfo actionIdentifier:ZMConversationDirectReplyAction withBlock:^(id mockDelegate) {
        [[self.operationLoop expect] startBackgroundTaskWithCompletionHandler:[OCMArg checkWithBlock:^BOOL((void(^completionHandler)())) {
            if (completionHandler != nil) {
                completionHandler();
                return YES;
            }
            return NO;
        }]];
        [[mockDelegate reject] showConversation:conversation];
        [[mockDelegate reject] showConversation:conversation];

    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertFalse(conversation.callDeviceIsActive);
    XCTAssertEqual(conversation.messages.count, 1u);
}


- (void)testThatItMarksTheTokenToDeleteWhenReceivingDidInvalidateToken
{
    // given
    [self.uiMOC setPushKitToken:[[ZMPushToken alloc] initWithDeviceToken:[NSData data] identifier:@"foo.bar" transportType:@"APNS" fallback:@"APNS" isRegistered:YES]];
    XCTAssertNotNil(self.uiMOC.pushKitToken);
    XCTAssertFalse(self.uiMOC.pushKitToken.isMarkedForDeletion);
    id mockPushRegistry = [OCMockObject niceMockForClass:[PKPushRegistry class]];
    
    // when
    [self.sut.pushRegistrant pushRegistry:mockPushRegistry didInvalidatePushTokenForType:PKPushTypeVoIP];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertTrue(self.uiMOC.pushKitToken.isMarkedForDeletion);
}

- (void)testThatItSetsThePushTokenWhenReceivingUpdateCredentials
{
    // given
    NSData *token = [NSData data];
    id mockCredentials =[OCMockObject niceMockForClass:[PKPushCredentials class]];
    [(PKPushCredentials *)[[mockCredentials expect] andReturn:token] token];
    id mockPushRegistry = [OCMockObject niceMockForClass:[PKPushRegistry class]];

    XCTAssertNil(self.uiMOC.pushKitToken);

    // when
    [self.sut.pushRegistrant pushRegistry:mockPushRegistry didUpdatePushCredentials:mockCredentials forType:PKPushTypeVoIP];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertNotNil(self.uiMOC.pushKitToken);
    XCTAssertEqualObjects(self.uiMOC.pushKitToken.deviceToken, token);
}

@end
#endif



#if TARGET_OS_IPHONE
@implementation ZMUserSessionTests (BackgroundFetch)

- (void)testThatItSetsTheMinimumBackgroundFetchInterval;
{
    XCTAssertNotEqual(self.application.minimumBackgroundFetchInverval, UIApplicationBackgroundFetchIntervalNever);
    XCTAssertGreaterThanOrEqual(self.application.minimumBackgroundFetchInverval, UIApplicationBackgroundFetchIntervalMinimum);
    XCTAssertLessThanOrEqual(self.application.minimumBackgroundFetchInverval, (NSTimeInterval) (20 * 60));
}

- (void)testThatItForwardsTheBackgroundFetchRequestToTheOperationLoop
{
    // given
    XCTestExpectation *expectation = [self expectationWithDescription:@"Background fetch completed"];
    void (^handler)(UIBackgroundFetchResult) = ^(UIBackgroundFetchResult result) {
        XCTAssertEqual(result, UIBackgroundFetchResultNewData);
        [expectation fulfill];
    };
    
    // expect
    [(ZMOperationLoop *)[[(id) self.operationLoop expect] andCall:@selector(forward_startBackgroundFetchWithCompletionHandler:) onObject:self] startBackgroundFetchWithCompletionHandler:OCMOCK_ANY];
    
    // when
    [self.sut application:self.application performFetchWithCompletionHandler:handler];
    
    // then
    XCTAssert([self waitForCustomExpectationsWithTimeout:0.5]);
    [(id) self.operationLoop verify];
}

- (void)forward_startBackgroundFetchWithCompletionHandler:(ZMBackgroundFetchHandler)handler;
{
    handler(ZMBackgroundFetchResultNewData);
}

@end
#endif



@implementation ZMUserSessionTests (LaunchOptions)

- (void)testThatItSendsNotificationIfLaunchedWithPhoneVerficationURL
{
    // given
    NSURL *verificationURL = [NSURL URLWithString:@"wire://verify-phone/123456"];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didReceiveNotification:) name:ZMLaunchedWithPhoneVerificationCodeNotificationName object:nil];
    
    // when
    [self.sut didLaunchWithURL:verificationURL];
    
    // then
    XCTAssertEqualObjects(self.lastReceivedNotification.name, ZMLaunchedWithPhoneVerificationCodeNotificationName);
    XCTAssertEqualObjects([self.lastReceivedNotification.userInfo objectForKey:ZMPhoneVerificationCodeKey], @"123456");
    [[NSNotificationCenter defaultCenter] removeObserver:self name:ZMLaunchedWithPhoneVerificationCodeNotificationName object:nil];
}

@end




@implementation ZMUserSessionTests (RequestToOpenConversation)

- (void)testThatItCallsTheDelegateWhenRequestedToOpenAConversation
{
    // given
    [[[self.transportSession stub] andReturn:nil] attemptToEnqueueSyncRequestWithGenerator:OCMOCK_ANY];
    id mockDelegate = [OCMockObject mockForProtocol:@protocol(ZMRequestsToOpenViewsDelegate)];
    self.sut.requestToOpenViewDelegate = mockDelegate;
    __block NSManagedObjectID *conversationID;
    __block ZMConversation *requestedConversation;
    
    // expect
    [[mockDelegate expect] showConversation:ZM_ARG_SAVE(requestedConversation)];
    
    // when
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        [self.syncMOC saveOrRollback];
        
        conversationID = conversation.objectID;
        [ZMUserSession requestToOpenSyncConversationOnUI:conversation];
    }];
    
    // then
    [self spinMainQueueWithTimeout:0.1];
    [mockDelegate verify];
    XCTAssertEqualObjects(requestedConversation.objectID, conversationID);
    XCTAssertEqual(requestedConversation.managedObjectContext, self.uiMOC);
    
}

@end

@interface ZMFlowSync (FlowManagerDelegate) <AVSFlowManagerDelegate>
@end

@implementation ZMUserSessionTests (AVSLogObserver)

- (void)testThatSubscriberIsNotRetained
{
    // given
    id token = nil;
    id __weak weakLogObserver = nil;
    @autoreleasepool {
        id logObserver = [OCMockObject mockForProtocol:@protocol(ZMAVSLogObserver)];
        
        token = [ZMUserSession addAVSLogObserver:logObserver];
        
        // when
        weakLogObserver = logObserver;
        XCTAssertNotNil(weakLogObserver);
        logObserver = nil;
    }
    // then
    XCTAssertNil(weakLogObserver);
    [ZMUserSession removeAVSLogObserver:token];
}

- (void)testThatLogCallbackIsNotTriggeredAfterUnsubscribe
{
    // given
    NSString *testMessage = @"Sample AVS Log";
    id logObserver = [OCMockObject mockForProtocol:@protocol(ZMAVSLogObserver)];
    [[logObserver reject] logMessage:nil];
    
    id token = [ZMUserSession addAVSLogObserver:logObserver];
    [ZMUserSession removeAVSLogObserver:token];
    
    // when
    [ZMFlowSync logMessage:testMessage];
    
    // then
    [logObserver verify];
}

@end

@implementation ZMUserSessionTests (Transport)

- (void)testThatItCallsTheTransportSessionWithTheIdentifierAndHandlerIf_AddCompletionHandlerForBackgroundSessionWithIdentifier_IsCalled
{
    // given
    dispatch_block_t handler = ^{};
    NSString * const identifier = @"com.wearezeta.background_session";
    
    // expect
    [[self.transportSession expect] addCompletionHandlerForBackgroundSessionWithIdentifier:identifier handler:handler];
    
    // when
    [self.sut addCompletionHandlerForBackgroundURLSessionWithIdentifier:identifier handler:handler];
}

@end
