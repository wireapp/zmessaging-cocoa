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
@import WireMockTransport;
@import WireSyncEngine;

#include "ZMUserSessionTestsBase.h"
#import "ZMPushToken.h"
#import "UILocalNotification+UserInfo.h"
#import "ZMUserSession+UserNotificationCategories.h"
#import "WireSyncEngine_iOS_Tests-Swift.h"

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
    self.lastReceivedNotification = nil;
    [super tearDown];
}

- (void)didReceiveNotification:(NSNotification *)notification
{
    self.lastReceivedNotification = notification;
}

- (void)testThatItInitializesTheBackendEnvironments
{
    // given
    ZMBackendEnvironment *prod = [ZMBackendEnvironment environmentWithType:ZMBackendEnvironmentTypeProduction];
    ZMBackendEnvironment *staging = [ZMBackendEnvironment environmentWithType:ZMBackendEnvironmentTypeStaging];
    
    // then
    XCTAssertEqualObjects(prod.backendURL, [NSURL URLWithString:@"https://prod-nginz-https.wire.com"]);
    XCTAssertEqualObjects(staging.backendURL, [NSURL URLWithString:@"https://staging-nginz-https.zinfra.io"]);
    
    XCTAssertEqualObjects(prod.backendWSURL, [NSURL URLWithString:@"https://prod-nginz-ssl.wire.com"]);
    XCTAssertEqualObjects(staging.backendWSURL, [NSURL URLWithString:@"https://staging-nginz-ssl.zinfra.io"]);
    
    XCTAssertEqualObjects(prod.blackListURL, [NSURL URLWithString:@"https://clientblacklist.wire.com/prod/ios"]);
    XCTAssertEqualObjects(staging.blackListURL, [NSURL URLWithString:@"https://clientblacklist.wire.com/staging/ios"]);
}

- (void)testThatItSetsTheUserAgentOnStart;
{
    // given
    NSString *version = @"The-version-123";
    id transportSession = [OCMockObject niceMockForClass:ZMTransportSession.class];
    [[[transportSession stub] andReturn:[OCMockObject niceMockForClass:[ZMPersistentCookieStorage class]]] cookieStorage];
    
    // expect
    id userAgent = [OCMockObject mockForClass:ZMUserAgent.class];
    [[[userAgent expect] classMethod] setWireAppVersion:version];

    // when

    ZMUserSession *session = [[ZMUserSession alloc] initWithMediaManager:nil
                                                             flowManager:self.flowManagerMock
                                                               analytics:nil
                                                        transportSession:transportSession
                                                         apnsEnvironment:nil
                                                             application:self.application
                                                              appVersion:version
                                                           storeProvider:self.storeProvider];
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
        NSManagedObjectContext *mocUI = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];

        mocSync = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
        
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
        mocUI = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
        
        NSManagedObjectContext *mocSync = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSPrivateQueueConcurrencyType];
        
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
    id pushChannel = [OCMockObject niceMockForProtocol:@protocol(ZMPushChannel)];
    id transportSession = [OCMockObject niceMockForClass:ZMTransportSession.class];
    id cookieStorage = [OCMockObject niceMockForClass:ZMPersistentCookieStorage.class];
    
    // expect
    [[pushChannel expect] setClientID:userClient.remoteIdentifier];
    [[[transportSession stub] andReturn:pushChannel] pushChannel];
    [[[transportSession stub] andReturn:cookieStorage] cookieStorage];
    
    // when
    ZMUserSession *userSession = [[ZMUserSession alloc] initWithTransportSession:transportSession
                                                                    mediaManager:self.mediaManager
                                                                     flowManager:self.flowManagerMock
                                                                       analytics:nil
                                                                 apnsEnvironment:self.apnsEnvironment
                                                                   operationLoop:nil
                                                                     application:self.application
                                                                      appVersion:@"00000"
                                                                   storeProvider:self.storeProvider];
    [userSession didRegisterUserClient:userClient];
    
    // then
    [pushChannel verify];
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
    NOT_USED([selfUser establishSessionWithClient:user1Client1 usingPreKey:@"pQABAQICoQBYIGnflzMYd4OvMaHKfcIJzlb1fvEIhBx4qN545db7ZDBrA6EAoQBYIH7q8TQbCCuaMLYW6yW7NzLsU/OA7ea7Xs/hAyXK1jETBPY="]);
    
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


@implementation ZMUserSessionTests (PushToken)

- (void)testThatItSetsThePushToken;
{
    // given
    uint8_t const tokenData[] = {
        0xc5, 0xe2, 0x4e, 0x41, 0xe4, 0xd4, 0x32, 0x90, 0x37, 0x92, 0x84, 0x49, 0x34, 0x94, 0x87, 0x54, 0x7e, 0xf1, 0x4f, 0x16, 0x2c, 0x77, 0xae, 0xe3, 0xaa, 0x8e, 0x12, 0xa3, 0x9c, 0x8d, 0xb1, 0xd5,
    };
    NSData * const deviceToken = [NSData dataWithBytes:tokenData length:sizeof(tokenData)];
    XCTAssertNil(self.sut.managedObjectContext.pushKitToken);
    [[self.transportSession stub] attemptToEnqueueSyncRequestWithGenerator:OCMOCK_ANY];
    
    // when
    [self.sut setPushKitToken:deviceToken];
    ZMPushToken *pushToken = self.sut.managedObjectContext.pushKitToken;
    
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
    id pushChannel = [OCMockObject mockForProtocol:@protocol(ZMPushChannel)];
    
    [[[transportSession stub] andReturn:pushChannel] pushChannel];

    [[transportSession stub] configurePushChannelWithConsumer:OCMOCK_ANY groupQueue:OCMOCK_ANY];
    self.cookieStorage = [ZMPersistentCookieStorage storageForServerName:@"usersessiontest.example.com" userIdentifier:NSUUID.createUUID];

    [[[transportSession stub] andReturn:self.cookieStorage] cookieStorage];
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
    [[pushChannel expect] setKeepOpen:YES];
    [[pushChannel expect] setClientID:OCMOCK_ANY];
    

    // when
    ZMUserSession *testSession = [[ZMUserSession alloc] initWithTransportSession:transportSession
                                                                    mediaManager:self.mediaManager
                                                                     flowManager:self.flowManagerMock
                                                                       analytics:nil
                                                                 apnsEnvironment:self.apnsEnvironment
                                                                   operationLoop:nil
                                                                     application:self.application
                                                                      appVersion:@"00000"
                                                                   storeProvider:self.storeProvider];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    [pushChannel verify];
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

- (BOOL)waitForOnlineSynchronizingStatus
{
    return [self waitForStatus:ZMNetworkStateOnlineSynchronizing];
}

- (void)testThatWeSetUserSessionToOnlineWhenWeDidReceiveData
{
    // when
    [self.sut didGoOffline];
    [self.sut didReceiveData];

    // then
    XCTAssertTrue([self waitForOnlineSynchronizingStatus]);

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
    XCTAssertTrue([self waitForOnlineSynchronizingStatus]);

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
    XCTAssertTrue([self waitForOnlineSynchronizingStatus]);

    // when
    [self.sut didGoOffline];
    
    // then
    XCTAssertTrue([self waitForOfflineStatus]);

}


- (void)testThatItNotifiesObserversWhenTheNetworkStatusBecomesOnline
{
    // given
    NetworkStateRecorder *stateRecorder = [[NetworkStateRecorder alloc] init];
    [self.sut didGoOffline];
    XCTAssertTrue([self waitForOfflineStatus]);
    XCTAssertEqual(self.sut.networkState, ZMNetworkStateOffline);
    
    // when
    id token = [ZMNetworkAvailabilityChangeNotification addNetworkAvailabilityObserver:stateRecorder userSession:self.sut];
    [self.sut didReceiveData];
    
    // then
    WaitForAllGroupsToBeEmpty(0.5);
    XCTAssertEqual(stateRecorder.stateChanges.count, 1u);
    XCTAssertEqual((ZMNetworkState)[stateRecorder.stateChanges.firstObject intValue], ZMNetworkStateOnlineSynchronizing);
    
    // after
    token = nil;
}

- (void)testThatItDoesNotNotifiesObserversWhenTheNetworkStatusWasAlreadyOnline
{
    // given
    NetworkStateRecorder *stateRecorder = [[NetworkStateRecorder alloc] init];
    
    // when
    id token = [ZMNetworkAvailabilityChangeNotification addNetworkAvailabilityObserver:stateRecorder userSession:self.sut];
    [self.sut didReceiveData];
    
    // then
    WaitForAllGroupsToBeEmpty(0.5);
    XCTAssertEqual(stateRecorder.stateChanges.count, 0u);
    
    // after
    token = nil;
    
}

- (void)testThatItNotifiesObserversWhenTheNetworkStatusBecomesOffline
{
    // given
    NetworkStateRecorder *stateRecorder = [[NetworkStateRecorder alloc] init];
    
    // when
    id token = [ZMNetworkAvailabilityChangeNotification addNetworkAvailabilityObserver:stateRecorder userSession:self.sut];
    [self.sut didGoOffline];
    
    // then
    WaitForAllGroupsToBeEmpty(0.5);
    XCTAssertEqual(stateRecorder.stateChanges.count, 1u);
    XCTAssertEqual((ZMNetworkState)[stateRecorder.stateChanges.firstObject intValue], ZMNetworkStateOffline);
    
    // after
    token = nil;
}

- (void)testThatItDoesNotNotifiesObserversWhenTheNetworkStatusWasAlreadyOffline
{
    // given
    NetworkStateRecorder *stateRecorder = [[NetworkStateRecorder alloc] init];
    [self.sut didGoOffline];
    XCTAssertTrue([self waitForOfflineStatus]);
    
    // when
    id token = [ZMNetworkAvailabilityChangeNotification addNetworkAvailabilityObserver:stateRecorder userSession:self.sut];
    [self.sut didGoOffline];
    
    // then
    WaitForAllGroupsToBeEmpty(0.5);
    XCTAssertEqual(stateRecorder.stateChanges.count, 0u);
    
    // after
    token = nil;
    
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
        
        ZMUser *sender = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        sender.remoteIdentifier = [NSUUID UUID];
        
        ZMConnection *connection = [ZMConnection insertNewObjectInManagedObjectContext:self.syncMOC];
        connection.conversation = conversation;
        connection.to = sender;
        connection.status = ZMConnectionStatusAccepted;
        
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

- (UILocalNotification *)notificationMessageConversationForCategory:(NSString *)category
{
    __block ZMConversation *conversation;
    __block ZMMessage *message;
    [self.syncMOC performGroupedBlockAndWait:^{
        conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        conversation.conversationType = ZMConversationTypeOneOnOne;
        conversation.remoteIdentifier = [NSUUID UUID];
        
        ZMUser *sender = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        sender.remoteIdentifier = [NSUUID UUID];
        
        ZMConnection *connection = [ZMConnection insertNewObjectInManagedObjectContext:self.syncMOC];
        connection.conversation = conversation;
        connection.to = sender;
        connection.status = ZMConnectionStatusAccepted;
        
        message = (ZMMessage *)[conversation appendMessageWithText:@"Test message"];
        [message markAsSent];
        
        [self.syncMOC saveOrRollback];
    }];
    
    UILocalNotification *note = [[UILocalNotification alloc] init];
    note.category = category;
    note.userInfo = @{@"conversationIDString": conversation.remoteIdentifier.transportString,
                      @"messageNonceString": message.nonce.transportString};
    
    return note;
}

- (void)testThatItMarksThePushTokenAsNotRegisteredAfterResettingPushTokens
{
    // given
    NSData *deviceToken = [NSData dataWithBytes:@"bla" length:3];
    ZMPushToken *pushToken = [[ZMPushToken alloc] initWithDeviceToken:deviceToken
                                                           identifier:@"com.wire.ent"
                                                        transportType:@"APNS_VOIP"
                                                         isRegistered:YES];
    self.uiMOC.pushKitToken = pushToken;
    
    // when
    [self performIgnoringZMLogError:^{
        [self.sut resetPushTokens];
        WaitForAllGroupsToBeEmpty(0.5);
    }];
    
    // then
    XCTAssertFalse(self.uiMOC.pushKitToken.isRegistered);
}

- (void)testThatItDoesNotForcePushKitTokenUploadIfNotChangedTheData
{
    // given
    NSData *deviceToken = [NSData dataWithBytes:@"bla" length:3];
    ZMPushToken *pushToken = [[ZMPushToken alloc] initWithDeviceToken:deviceToken
                                                           identifier:@"com.wire.ent"
                                                        transportType:@"APNS_VOIP"
                                                         isRegistered:YES];
    self.uiMOC.pushKitToken = pushToken;
    
    // when
    [self.sut setPushKitToken:deviceToken];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertTrue(self.uiMOC.pushKitToken.isRegistered);
}

- (void)testThatItStoresThePushKitToken
{
    // given
    NSData *deviceToken = [NSData dataWithBytes:@"bla" length:3];
    ZMPushToken *pushToken = [[ZMPushToken alloc] initWithDeviceToken:deviceToken
                                                           identifier:@"com.wire.ent"
                                                        transportType:@"APNS_VOIP"
                                                         isRegistered:YES];
    self.uiMOC.pushKitToken = pushToken;
    
    // when
    [self performIgnoringZMLogError:^{
        [self.sut resetPushTokens];
        WaitForAllGroupsToBeEmpty(0.5);
    }];
    
    // then
    XCTAssertFalse(self.uiMOC.pushKitToken.isRegistered);
}

//- (void)testThatIt_DoesNot_ForwardsRemoteNotificationsWhileRunning_WhenNotLoggedIn;
//{
//    // expect
//    NSDictionary *remoteNotification = @{@"a": @"b"};
//    [[self.operationLoop reject] fetchEventsFromPushChannelPayload:remoteNotification completionHandler:OCMOCK_ANY source:ZMPushNotficationTypeAlert];
//    
//    // when
//    [self.sut application:OCMOCK_ANY didReceiveRemoteNotification:remoteNotification fetchCompletionHandler:^(UIBackgroundFetchResult result) {
//        XCTAssertNotEqual(result, UIBackgroundFetchResultFailed);
//    }];
//    
//    [self.operationLoop verify];
//}

- (void)checkThatItCallsTheDelegateForNotification:(UILocalNotification *)notification responseInfo:(NSDictionary *)responseInfo actionIdentifier:(NSString *)actionIdentifier withBlock:(void (^)(id mockDelegate))block
{
    id mockDelegate = [OCMockObject mockForProtocol:@protocol(ZMRequestsToOpenViewsDelegate)];
    
    // expect
    block(mockDelegate);
    
    // when
    __block BOOL didCallCompletionHandler = NO;
    self.sut.requestToOpenViewDelegate = mockDelegate;
    [self.sut handleActionWithApplication:self.application with:actionIdentifier for:notification with:responseInfo completionHandler:^{
        didCallCompletionHandler = YES;
    }];
    
    WaitForAllGroupsToBeEmpty(0.5);
    [self.sut didFinishSync];
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
    [self.sut didFinishSync];
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
        [[mockDelegate expect] showConversationListForUserSession:self.sut];
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
        [[mockDelegate expect] showConversationListForUserSession:self.sut];
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
        [[mockDelegate expect] userSession:self.sut showConversation:OCMOCK_ANY];
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
        [[mockDelegate reject] userSession:self.sut showConversation:OCMOCK_ANY];
    }];
    
    //then
    XCTAssertTrue(conversation.isSilenced);
}

- (void)testThatItAddsLike_ForZMConversationCategory_ZMMessageLikeAction
{
    //given
    [self simulateLoggedInUser];
    self.sut.operationStatus.isInBackground = YES;
    
    [[[self.transportSession stub] andReturn:nil] attemptToEnqueueSyncRequestWithGenerator:OCMOCK_ANY];
    UILocalNotification *note = [self notificationMessageConversationForCategory:ZMConversationCategory];
    NSString *conversationIDString = note.userInfo[@"conversationIDString"];
    ZMConversation *conversation = [ZMConversation conversationWithRemoteID:[NSUUID uuidWithTransportString:conversationIDString]
                                                             createIfNeeded:NO
                                                                  inContext:self.uiMOC];
    
    // expect
    [self.sut handleActionWithApplication:self.application
                                     with:ZMMessageLikeAction
                                      for:note
                                     with:[NSDictionary dictionary]
                        completionHandler:^{}];
    
    WaitForAllGroupsToBeEmpty(0.5);
    //then
    ZMMessage *lastMessage = conversation.messages.lastObject;
    XCTAssertNotNil(lastMessage.reactions);
    XCTAssertEqual((int)lastMessage.reactions.count, 1);
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
        [[mockDelegate expect] userSession:self.sut showConversation:OCMOCK_ANY];
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
        [[mockDelegate expect] userSession:self.sut showConversation:conversation];
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
        [[mockDelegate expect] userSession:self.sut showConversation:conversation];
    }];

    // then
    XCTAssertTrue(sender.isConnected);
}

- (void)testThatItCalls_DelegateShowConversationAndAcceptsCall_ZMConnectCategory
{
    // given
    [self simulateLoggedInUser];
    [self createSelfClient];
    
    WireCallCenterV3Mock *callCenter = [self createCallCenter];
    
    [[[self.transportSession stub] andReturn:nil] attemptToEnqueueSyncRequestWithGenerator:OCMOCK_ANY];

    UILocalNotification *note = [self notificationWithConversationForCategory:ZMIncomingCallCategory];
    ZMConversation *conversation = [note conversationInManagedObjectContext:self.uiMOC];
    
    [self.uiMOC saveOrRollback];
    
    [self simulateIncomingCallFromUser:conversation.connectedUser conversation:conversation];
    
    
    // expect
    [self.application setInactive];

    [self checkThatItCallsTheDelegateForNotification:note responseInfo:nil actionIdentifier:ZMCallAcceptAction withBlock:^(id mockDelegate) {
        [[mockDelegate expect] userSession:self.sut showConversation:conversation];

    }];
    
    // then
    XCTAssertTrue(callCenter.didCallAnswerCall);
}

- (void)testThatIt_DoesNotCall_DelegateShowConversationAndIgnoresCall_ZMIncomingCallCategory_IgnoreAction
{
    // given
    [self simulateLoggedInUser];
    [self createSelfClient];
    
    WireCallCenterV3Mock *callCenter = [self createCallCenter];
    
    [[[self.transportSession stub] andReturn:nil] attemptToEnqueueSyncRequestWithGenerator:OCMOCK_ANY];

    UILocalNotification *note = [self notificationWithConversationForCategory:ZMIncomingCallCategory];
    ZMConversation *conversation = [note conversationInManagedObjectContext:self.uiMOC];
    
    [self simulateIncomingCallFromUser: conversation.connectedUser conversation:conversation];
    
    // expect
    [self.application setInactive];
    
    [self checkThatItCallsTheDelegateForNotification:note responseInfo:nil actionIdentifier:ZMCallIgnoreAction withBlock:^(id mockDelegate) {
        [[mockDelegate reject] userSession:self.sut showConversation:OCMOCK_ANY];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertTrue(callCenter.didCallRejectCall);
}

- (void)testThatItCalls_DelegateShowConversationButDoesNotCallBack_ZMMissedCallCategory_CallBackAction
{
    // given
    [self simulateLoggedInUser];
    [self createSelfClient];
    
    WireCallCenterV3Mock *callCenter = [self createCallCenter];
    
    [[[self.transportSession stub] andReturn:nil] attemptToEnqueueSyncRequestWithGenerator:OCMOCK_ANY];
    
    UILocalNotification *note = [self notificationWithConversationForCategory:ZMMissedCallCategory];
    ZMConversation *conversation = [note conversationInManagedObjectContext:self.uiMOC];
    
    // expect
    [self.application setInactive];

    [self checkThatItCallsTheDelegateForNotification:note responseInfo:nil actionIdentifier:ZMCallAcceptAction withBlock:^(id mockDelegate) {
        [[mockDelegate expect] userSession:self.sut showConversation:conversation];
    }];
    
    // then
    XCTAssertFalse(callCenter.didCallStartCall);

}

- (void)testThatItDoesNotCall_DelegateShowConversationAndAppendsAMessage_ZMConversationCategory_DirectReplyAction
{
    // given
    [self simulateLoggedInUser];
    self.sut.operationStatus.isInBackground = YES;
    
    [[[self.transportSession stub] andReturn:nil] attemptToEnqueueSyncRequestWithGenerator:OCMOCK_ANY];
    
    UILocalNotification *note = [self notificationWithConversationForCategory:ZMConversationCategory];
    ZMConversation *conversation = [note conversationInManagedObjectContext:self.uiMOC];
    NSDictionary *responseInfo = @{UIUserNotificationActionResponseTypedTextKey: @"Hello hello"};
    XCTAssertEqual(conversation.messages.count, 0u);
    __block BOOL didCallCompletionHandler = NO;
    
    [self.sut handleActionWithApplication:self.application with:ZMConversationDirectReplyAction for:note with:responseInfo completionHandler:^{
        didCallCompletionHandler = YES;
    }];
    
    // Fake message was sent
    [self.sut.operationStatus finishBackgroundTaskWithTaskResult:ZMBackgroundTaskResultFinished];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertTrue(didCallCompletionHandler);
    XCTAssertEqual(conversation.messages.count, 1u);
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
    [[mockDelegate expect] userSession:self.sut showConversation:ZM_ARG_SAVE(requestedConversation)];
    
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

@interface ZMCallFlowRequestStrategy (FlowManagerDelegate) <AVSFlowManagerDelegate>
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
