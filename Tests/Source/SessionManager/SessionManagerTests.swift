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
    
    func sessionManagerWillSuspendSession() {
        // no-op
    }
    
    func sessionManagerDidLogout() {
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
