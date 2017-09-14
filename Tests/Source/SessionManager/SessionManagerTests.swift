//
// Wire
// Copyright (C) 2017 Wire Swiss GmbH
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


import XCTest
import WireTesting
@testable import WireSyncEngine


class SessionManagerTestDelegate: SessionManagerDelegate {

    func sessionManagerWillOpenAccount(_ account: Account) {
        // no-op
    }
    
    func sessionManagerDidLogout(error: Error?) {
        // no op
    }
    
    func sessionManagerDidBlacklistCurrentVersion() {
        // no op
    }

    var unauthenticatedSession : UnauthenticatedSession?
    func sessionManagerCreated(unauthenticatedSession : UnauthenticatedSession) {
        self.unauthenticatedSession = unauthenticatedSession
    }
    
    var userSession : ZMUserSession?
    func sessionManagerCreated(userSession : ZMUserSession) {
        self.userSession = userSession
    }
    
    var startedMigrationCalled = false
    func sessionManagerWillStartMigratingLocalStore() {
        startedMigrationCalled = true
    }

}

class TestReachability: ReachabilityProvider, ReachabilityTearDown {
    var mayBeReachable = true
    var isMobileConnection = true
    var oldMayBeReachable = true
    var oldIsMobileConnection = true
    
    var tearDownCalled = false
    func tearDown() {
        tearDownCalled = true
    }
}

class SessionManagerTests: IntegrationTest {

    var delegate: SessionManagerTestDelegate!
    var sut: SessionManager?
    
    override func setUp() {
        super.setUp()
        delegate = SessionManagerTestDelegate()
    }
    
    func createManager() -> SessionManager? {
        guard let mediaManager = mediaManager, let application = application, let transportSession = transportSession else { return nil }
        let environment = ZMBackendEnvironment(type: .staging)
        let reachability = TestReachability()
        let unauthenticatedSessionFactory = MockUnauthenticatedSessionFactory(transportSession: transportSession as! UnauthenticatedTransportSessionProtocol, environment: environment, reachability: reachability)
        let authenticatedSessionFactory = MockAuthenticatedSessionFactory(
            apnsEnvironment: apnsEnvironment,
            application: application,
            mediaManager: mediaManager,
            flowManager: FlowManagerMock(),
            transportSession: transportSession,
            environment: environment,
            reachability: reachability
        )
        
        return SessionManager(
            appVersion: "0.0.0",
            authenticatedSessionFactory: authenticatedSessionFactory,
            unauthenticatedSessionFactory: unauthenticatedSessionFactory,
            reachability: reachability,
            delegate: delegate,
            application: application,
            launchOptions: [:],
            dispatchGroup: dispatchGroup
        )
    }
    
    override func tearDown() {
        delegate = nil
        sut = nil
        super.tearDown()
    }
    
    func testThatItCreatesUnauthenticatedSessionAndNotifiesDelegateIfStoreIsNotAvailable() {
        // when
        sut = createManager()
        
        // then
        XCTAssertNil(delegate.userSession)
        XCTAssertNotNil(delegate.unauthenticatedSession)
    }
    
    func testThatItCreatesUserSessionAndNotifiesDelegateIfStoreIsAvailable() {
        // given
        guard let sharedContainer = Bundle.main.appGroupIdentifier.map(FileManager.sharedContainerDirectory) else { return XCTFail() }
        let manager = AccountManager(sharedDirectory: sharedContainer)
        let account = Account(userName: "", userIdentifier: currentUserIdentifier)
        account.cookieStorage().authenticationCookieData = NSData.secureRandomData(ofLength: 16)
        manager.addAndSelect(account)

        var completed = false
        LocalStoreProvider.createStack(
            applicationContainer: sharedContainer,
            userIdentifier: currentUserIdentifier,
            dispatchGroup: dispatchGroup,
            completion: { _ in completed = true }
        )
        
        XCTAssert(wait(withTimeout: 0.5) { completed })

        // when
        sut = createManager()
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.1))
        
        // then
        XCTAssertNotNil(delegate.userSession)
        XCTAssertNil(delegate.unauthenticatedSession)
    }
    
}

class SessionManagerTests_Teams: IntegrationTest {
    
    override func setUp() {
        super.setUp()
        createSelfUserAndConversation()
    }
    
    func testThatItUpdatesAccountAfterLoginWithTeamName() {
        // given
        let teamName = "Wire"
        self.mockTransportSession.performRemoteChanges { session in
            _ = session.insertTeam(withName: teamName, isBound: true, users: [self.selfUser])
        }
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // when
        XCTAssert(login())
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))

        let _ = MockAsset(in: mockTransportSession.managedObjectContext, forID: selfUser.previewProfileAssetIdentifier!)
        
        // then
        guard let sharedContainer = Bundle.main.appGroupIdentifier.map(FileManager.sharedContainerDirectory) else { return XCTFail() }
        let manager = AccountManager(sharedDirectory: sharedContainer)
        guard let account = manager.accounts.first, manager.accounts.count == 1 else { XCTFail("Should have one account"); return }
        XCTAssertEqual(account.userIdentifier.transportString(), self.selfUser.identifier)
        XCTAssertEqual(account.teamName, teamName)
        XCTAssertNil(account.imageData)
    }
    
    func testThatItUpdatesAccountAfterTeamNameChanges() {
        // given
        var team: MockTeam!
        self.mockTransportSession.performRemoteChanges { session in
            team = session.insertTeam(withName: "Wire", isBound: true, users: [self.selfUser])
        }
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // when
        XCTAssert(login())
        
        let newTeamName = "Not Wire"
        self.mockTransportSession.performRemoteChanges { session in
            team.name = newTeamName
        }
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        guard let sharedContainer = Bundle.main.appGroupIdentifier.map(FileManager.sharedContainerDirectory) else { return XCTFail() }
        let manager = AccountManager(sharedDirectory: sharedContainer)
        guard let account = manager.accounts.first, manager.accounts.count == 1 else { XCTFail("Should have one account"); return }
        XCTAssertEqual(account.userIdentifier.transportString(), self.selfUser.identifier)
        XCTAssertEqual(account.teamName, newTeamName)
    }
    
    func testThatItUpdatesAccountWithUserDetailsAfterLogin() {
        // when
        XCTAssert(login())
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        guard let sharedContainer = Bundle.main.appGroupIdentifier.map(FileManager.sharedContainerDirectory) else { return XCTFail() }
        let manager = AccountManager(sharedDirectory: sharedContainer)
        guard let account = manager.accounts.first, manager.accounts.count == 1 else { XCTFail("Should have one account"); return }
        XCTAssertEqual(account.userIdentifier.transportString(), self.selfUser.identifier)
        XCTAssertNil(account.teamName)
        XCTAssertEqual(account.userName, self.selfUser.name)
        let image = MockAsset(in: mockTransportSession.managedObjectContext, forID: selfUser.previewProfileAssetIdentifier!)

        XCTAssertEqual(account.imageData, image?.data)
    }
    
    func testThatItUpdatesAccountAfterUserNameChange() {
        // when
        XCTAssert(login())
        
        let newName = "BOB"
        self.mockTransportSession.performRemoteChanges { session in
            self.selfUser.name = newName
        }
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        guard let sharedContainer = Bundle.main.appGroupIdentifier.map(FileManager.sharedContainerDirectory) else { return XCTFail() }
        let manager = AccountManager(sharedDirectory: sharedContainer)
        guard let account = manager.accounts.first, manager.accounts.count == 1 else { XCTFail("Should have one account"); return }
        XCTAssertEqual(account.userIdentifier.transportString(), self.selfUser.identifier)
        XCTAssertNil(account.teamName)
        XCTAssertEqual(account.userName, selfUser.name)
    }
    
    func testThatItDeletesTheAccountFolder() throws {
        // given
        guard let sharedContainer = Bundle.main.appGroupIdentifier.map(FileManager.sharedContainerDirectory) else { return XCTFail() }
        
        let manager = AccountManager(sharedDirectory: sharedContainer)
        let account = Account(userName: "Test Account", userIdentifier: currentUserIdentifier)
        manager.add(account)
        
        let accountFolder = StorageStack.accountFolder(accountIdentifier: account.userIdentifier, applicationContainer: sharedContainer)
        
        try FileManager.default.createDirectory(at: accountFolder, withIntermediateDirectories: true, attributes: nil)
        
        // when
        self.sessionManager!.delete(account: account)
        
        // then
        XCTAssertFalse(FileManager.default.fileExists(atPath: accountFolder.path))
    }
}

class SessionManagerPayloadCheckerTests: MessagingTest {
    func testThatItDetectsTheUserFromPayload() {
        // GIVEN
        let user = ZMUser.selfUser(in: self.uiMOC)
        user.remoteIdentifier = UUID()
        
        let payload: [AnyHashable: Any] = ["data": [
                "user": user.remoteIdentifier!.transportString()
            ]
        ]
        // WHEN & THEN
        XCTAssertTrue(payload.isPayload(for: user))
    }
    
    func testThatItDiscardsThePayloadFromOtherUser() {
        // GIVEN
        let user = ZMUser.selfUser(in: self.uiMOC)
        user.remoteIdentifier = UUID()
        
        let payload: [AnyHashable: Any] = ["data": [
            "user": UUID().transportString()
            ]
        ]
        // WHEN & THEN
        XCTAssertFalse(payload.isPayload(for: user))
    }
    
    func testThatItDetectsPayloadWithUserAsCorrect() {
        // GIVEN
        let payload: [AnyHashable: Any] = ["data": [
            "user": UUID().transportString()
            ]
        ]
        // WHEN
        XCTAssertFalse(payload.isPayloadMissingUserInformation())
    }
    
    func testThatItDetectsPayloadWithoutUserAsWrong() {
        // GIVEN
        let payload: [AnyHashable: Any] = [:]
        // WHEN
        XCTAssertTrue(payload.isPayloadMissingUserInformation())
    }
}

class SessionManagerTests_MultiUserSession: IntegrationTest {
    func testThatItLoadsAndKeepsBackgroundUserSession() {
        // GIVEN
        guard let sharedContainer = Bundle.main.appGroupIdentifier.map(FileManager.sharedContainerDirectory) else { return XCTFail() }
        
        let manager = AccountManager(sharedDirectory: sharedContainer)
        let account1 = Account(userName: "Test Account 1", userIdentifier: currentUserIdentifier)
        manager.add(account1)
        
        let account2 = Account(userName: "Test Account 2", userIdentifier: UUID())
        manager.add(account2)
        // WHEN
        weak var sessionForAccount1Reference: ZMUserSession? = nil
        let session1LoadedExpectation = self.expectation(description: "Session for account 1 loaded")
        self.sessionManager!.withSession(for: account1, perform: { sessionForAccount1 in
            // THEN
            session1LoadedExpectation.fulfill()
            XCTAssertNotNil(sessionForAccount1.managedObjectContext)
            sessionForAccount1Reference = sessionForAccount1
        })
        // WHEN
        weak var sessionForAccount2Reference: ZMUserSession? = nil
        let session2LoadedExpectation = self.expectation(description: "Session for account 2 loaded")
        self.sessionManager!.withSession(for: account1, perform: { sessionForAccount2 in
            // THEN
            session2LoadedExpectation.fulfill()
            XCTAssertNotNil(sessionForAccount2.managedObjectContext)
            sessionForAccount2Reference = sessionForAccount2
        })
        
        // THEN
        XCTAssertTrue(self.waitForCustomExpectations(withTimeout: 0.5) { error in
            XCTAssertNil(error)
            XCTAssertNotNil(sessionForAccount1Reference)
            XCTAssertNotNil(sessionForAccount2Reference)
            
            self.sessionManager!.deactivateAllBackgroundSessions()
        })
    }
    
    func testThatItUnloadsUserSession() {
        // GIVEN
        guard let sharedContainer = Bundle.main.appGroupIdentifier.map(FileManager.sharedContainerDirectory) else { return XCTFail() }
        
        let manager = AccountManager(sharedDirectory: sharedContainer)
        let account = Account(userName: "Test Account", userIdentifier: currentUserIdentifier)
        manager.add(account)
        
        // WHEN
        self.sessionManager!.withSession(for: account, perform: { session in
            XCTAssertNotNil(session.managedObjectContext)
        })
        
        // THEN
        XCTAssertNotNil(self.sessionManager!.backgroundUserSessions[account])
        
        // AND WHEN
        self.sessionManager!.deactivateAllBackgroundSessions()
        
        // THEN
        XCTAssertNil(self.sessionManager!.backgroundUserSessions[account])
    }
}

class SessionManagerTests_Push: IntegrationTest {
    func testThatItStoresThePushToken() {
        XCTFail()
    }
    
    /*
     
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

 */
}

