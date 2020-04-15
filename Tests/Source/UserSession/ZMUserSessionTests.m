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
@import avs;

#include "ZMUserSessionTestsBase.h"
#import "WireSyncEngine_iOS_Tests-Swift.h"

@interface ZMUserSessionTests : ZMUserSessionTestsBase

@property (nonatomic) NSNotification *lastReceivedNotification;

- (void)didReceiveNotification:(NSNotification *)notification;

@end

@implementation ZMUserSessionTests

- (void)tearDown
{
    self.lastReceivedNotification = nil;
    [super tearDown];
}

- (void)didReceiveNotification:(NSNotification *)notification
{
    self.lastReceivedNotification = notification;
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
    ZMUserSession *session = [[ZMUserSession alloc] initWithTransportSession:transportSession
                                                                mediaManager:self.mediaManager
                                                                 flowManager:self.flowManagerMock
                                                                   analytics:nil
                                                               operationLoop:nil
                                                                 application:self.application
                                                                  appVersion:version
                                                               storeProvider:self.storeProvider
                                                         showContentDelegate:nil];
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

@end


@implementation ZMUserSessionTests (ZMClientRegistrationStatusDelegate)

- (void)testThatItNotfiesTheTransportSessionWhenSelfUserClientIsRegistered
{
    // given
    UserClient *userClient = [self createSelfClient];
    id pushChannel = [OCMockObject niceMockForProtocol:@protocol(ZMPushChannel)];
    id transportSession = [OCMockObject niceMockForClass:ZMTransportSession.class];
    id cookieStorage = [OCMockObject niceMockForClass:ZMPersistentCookieStorage.class];
    id sessionManager = [[MockSessionManager alloc] init];

    // expect
    [[pushChannel expect] setClientID:userClient.remoteIdentifier];
    [[[transportSession stub] andReturn:pushChannel] pushChannel];
    [[[transportSession stub] andReturn:cookieStorage] cookieStorage];
    
    // when
    ZMUserSession *userSession = [[ZMUserSession alloc] initWithTransportSession:transportSession
                                                                    mediaManager:self.mediaManager
                                                                     flowManager:self.flowManagerMock
                                                                       analytics:nil
                                                                   operationLoop:nil
                                                                     application:self.application
                                                                      appVersion:@"00000"
                                                                   storeProvider:self.storeProvider
                                                             showContentDelegate:nil];
    userSession.sessionManager = sessionManager;
    XCTAssertFalse([(MockSessionManager *)sessionManager updatePushTokenCalled]);
    [userSession didRegisterUserClient:userClient];
    
    // then
    [pushChannel verify];
    [transportSession verify];

    XCTAssert([self waitForAllGroupsToBeEmptyWithTimeout:0.5]);
    XCTAssertTrue([(MockSessionManager *)sessionManager updatePushTokenCalled]);

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

- (void)testThatEnqueueDelayedChangesAreDoneAsynchronouslyOnTheMainQueueWithCompletionHandler
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
    [self.sut enqueueDelayedChanges:^{
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
    [self spinMainQueueWithTimeout:0.2]; // the delayed save will wait 0.1 seconds
    
    // then
    XCTAssertTrue(executed);
    XCTAssertTrue(blockExecuted);
    XCTAssertTrue(contextSaved);
}

@end

@implementation ZMUserSessionTests (NetworkState)

- (void)testThatItSetsItselfAsADelegateOfTheTransportSessionAndForwardsUserClientID
{
    // given
    UserClient *selfClient = [self createSelfClient];;
    
    self.mockPushChannel = [[MockPushChannel alloc] init];
    self.cookieStorage = [ZMPersistentCookieStorage storageForServerName:@"usersessiontest.example.com" userIdentifier:NSUUID.createUUID];
    RecordingMockTransportSession *transportSession = [[RecordingMockTransportSession alloc] initWithCookieStorage:self.cookieStorage pushChannel:self.mockPushChannel];


    // when
    ZMUserSession *testSession = [[ZMUserSession alloc] initWithTransportSession:transportSession
                                                                    mediaManager:self.mediaManager
                                                                     flowManager:self.flowManagerMock
                                                                       analytics:nil
                                                                   operationLoop:nil
                                                                     application:self.application
                                                                      appVersion:@"00000"
                                                                   storeProvider:self.storeProvider
                                                             showContentDelegate:nil];
    WaitForAllGroupsToBeEmpty(0.5);

    // then
    XCTAssertTrue(self.transportSession.didCallSetNetworkStateDelegate);
    XCTAssertEqual(self.mockPushChannel.keepOpen, YES);
    XCTAssertEqualObjects(self.mockPushChannel.clientID, selfClient.remoteIdentifier);
    
    
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
    [self.sut didStartQuickSync];
    [self.sut didFinishQuickSync];
    
    // then
    XCTAssertTrue([self waitForStatus:ZMNetworkStateOnline]);
}

- (void)testThatItNotifiesThirdPartyServicesWhenSyncIsDone
{
    // given
    XCTAssertEqual(self.thirdPartyServices.uploadCount, 0u);
    
    // when
    [self.sut didFinishQuickSync];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(self.thirdPartyServices.uploadCount, 1u);
}

- (void)testThatItOnlyNotifiesThirdPartyServicesOnce
{
    // given
    XCTAssertEqual(self.thirdPartyServices.uploadCount, 0u);
    
    // when
    [self.sut didFinishQuickSync];
    [self.sut didStartQuickSync];
    [self.sut didFinishQuickSync];
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
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(self.thirdPartyServices.uploadCount, 2u);
}

- (void)testThatItNotifiesThirdPartyServicesAgainAfterEnteringForeground_2;
{
    // given
    XCTAssertEqual(self.thirdPartyServices.uploadCount, 0u);
    
    // when
    [self.sut didFinishQuickSync];
    [self.sut applicationDidEnterBackground:nil];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(self.thirdPartyServices.uploadCount, 1u);

    [self.sut applicationWillEnterForeground:nil];
    [self.sut didStartQuickSync];
    [self.sut didFinishQuickSync];
    [self.sut applicationDidEnterBackground:nil];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(self.thirdPartyServices.uploadCount, 2u);
}

#endif

- (void)testThatWeDoNotSetUserSessionToSyncDoneWhenSyncIsDoneIfWeWereNotSynchronizing
{
    // when
    [self.sut didGoOffline];
    [self.sut didFinishQuickSync];
    
    // then
    XCTAssertTrue([self waitForOfflineStatus]);
}

- (void)testThatWeSetUserSessionToSynchronizingWhenSyncIsStarted
{
    // when
    [self.sut didStartQuickSync];
    
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
@implementation ZMUserSessionTests (BackgroundFetch)

- (void)testThatItSetsTheMinimumBackgroundFetchInterval;
{
    XCTAssertNotEqual(self.application.minimumBackgroundFetchInverval, UIApplicationBackgroundFetchIntervalNever);
    XCTAssertGreaterThanOrEqual(self.application.minimumBackgroundFetchInverval, UIApplicationBackgroundFetchIntervalMinimum);
    XCTAssertLessThanOrEqual(self.application.minimumBackgroundFetchInverval, (NSTimeInterval) (20 * 60));
}

@end
#endif
