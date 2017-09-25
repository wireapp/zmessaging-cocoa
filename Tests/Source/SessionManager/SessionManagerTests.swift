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
import PushKit
@testable import WireSyncEngine

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
        
        // given
        let observer = SessionManagerObserverMock()
        let token = sut?.addSessionManagerObserver(observer)
        
        // when
        sut = createManager()
        
        // then
        XCTAssertNil(delegate.userSession)
        XCTAssertNotNil(delegate.unauthenticatedSession)
        withExtendedLifetime(token) {
            XCTAssertEqual([], observer.createdUserSession)
        }
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
        let observer = SessionManagerObserverMock()
        let token = sut?.addSessionManagerObserver(observer)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.1))
        
        // then
        XCTAssertNotNil(delegate.userSession)
        XCTAssertNil(delegate.unauthenticatedSession)
        withExtendedLifetime(token) {
            XCTAssertEqual([delegate.userSession].flatMap { $0 }, observer.createdUserSession)
        }
    }
    
    func testThatItNotifiesDelegateAndObserverWhenCreatingSession() {
        
        // GIVEN
        let account = self.createAccount()
        account.cookieStorage().authenticationCookieData = NSData.secureRandomData(ofLength: 16)
        
        guard let mediaManager = mediaManager, let application = application else { return XCTFail() }
        
        let sessionManagerExpectation = self.expectation(description: "Session manager and session is loaded")

        var realSessionManager: SessionManager! = nil
        let observer = SessionManagerObserverMock()
        var observerToken: Any? = nil
        SessionManager.create(appVersion: "0.0.0",
                              mediaManager: mediaManager,
                              analytics: nil,
                              delegate: nil,
                              application: application,
                              launchOptions: [:],
                              blacklistDownloadInterval : 60) { sessionManager in
                                
                                let environment = ZMBackendEnvironment(type: .staging)
                                let reachability = TestReachability()
                                let authenticatedSessionFactory = MockAuthenticatedSessionFactory(
                                    apnsEnvironment: self.apnsEnvironment!,
                                    application: application,
                                    mediaManager: mediaManager,
                                    flowManager: FlowManagerMock(),
                                    transportSession: self.transportSession!,
                                    environment: environment,
                                    reachability: reachability
                                )
                                
                                sessionManager.authenticatedSessionFactory = authenticatedSessionFactory
                                
                                // WHEN
                                observerToken = sessionManager.addSessionManagerObserver(observer)
                                sessionManager.loadSession(for: account) { userSession in
                                    realSessionManager = sessionManager
                                    XCTAssertNotNil(userSession)
                                    sessionManagerExpectation.fulfill()
                                }
        }
        
        // THEN
        XCTAssertTrue(self.waitForCustomExpectations(withTimeout: 0.5))
        XCTAssertEqual([realSessionManager.activeUserSession!], observer.createdUserSession)
        
        // AFTER
        withExtendedLifetime(observerToken) {
            realSessionManager.tearDownAllBackgroundSessions()
        }
    }
    
}

extension IntegrationTest {
    func createAccount() -> Account {
        guard let sharedContainer = Bundle.main.appGroupIdentifier.map(FileManager.sharedContainerDirectory) else {
            XCTFail()
            fatalError()
        }
        
        let manager = AccountManager(sharedDirectory: sharedContainer)
        let account = Account(userName: "Test Account", userIdentifier: currentUserIdentifier)
        manager.addOrUpdate(account)
        
        return account
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
        guard let sharedContainer = Bundle.main.appGroupIdentifier.map(FileManager.sharedContainerDirectory) else {
            XCTFail()
            return
        }
        let account = self.createAccount()
        
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
        manager.addOrUpdate(account1)
        
        let account2 = Account(userName: "Test Account 2", userIdentifier: UUID())
        manager.addOrUpdate(account2)
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
            
            self.sessionManager!.tearDownAllBackgroundSessions()
        })
    }
    
    func testThatItUnloadsUserSession() {
        // GIVEN
        let account = self.createAccount()
        
        // WHEN
        self.sessionManager!.withSession(for: account, perform: { session in
            XCTAssertNotNil(session.managedObjectContext)
        })
        
        // THEN
        XCTAssertNotNil(self.sessionManager!.backgroundUserSessions[account.userIdentifier])
        
        // AND WHEN
        self.sessionManager!.tearDownAllBackgroundSessions()
        
        // THEN
        XCTAssertNil(self.sessionManager!.backgroundUserSessions[account.userIdentifier])
    }
    
    func testThatItDoesNotUnloadActiveUserSessionFromMemoryWarning() {
        // GIVEN
        let account = self.createAccount()
        account.cookieStorage().authenticationCookieData = NSData.secureRandomData(ofLength: 16)
        
        guard let mediaManager = mediaManager, let application = application else { return XCTFail() }
        
        let sessionManagerExpectation = self.expectation(description: "Session manager and session is loaded")
        
        // WHEN
        var realSessionManager: SessionManager! = nil
        SessionManager.create(appVersion: "0.0.0",
                              mediaManager: mediaManager,
                              analytics: nil,
                              delegate: nil,
                              application: application,
                              launchOptions: [:],
                              blacklistDownloadInterval : 60) { sessionManager in
                                
                                let environment = ZMBackendEnvironment(type: .staging)
                                let reachability = TestReachability()
                                let authenticatedSessionFactory = MockAuthenticatedSessionFactory(
                                    apnsEnvironment: self.apnsEnvironment!,
                                    application: application,
                                    mediaManager: mediaManager,
                                    flowManager: FlowManagerMock(),
                                    transportSession: self.transportSession!,
                                    environment: environment,
                                    reachability: reachability
                                )
                                
                                sessionManager.authenticatedSessionFactory = authenticatedSessionFactory
                                
                                sessionManager.loadSession(for: account) { userSession in
                                    realSessionManager = sessionManager
                                    XCTAssertNotNil(userSession)
                                    sessionManagerExpectation.fulfill()
                                }
        }
        
        // THEN
        XCTAssertTrue(self.waitForCustomExpectations(withTimeout: 0.5))
        
        XCTAssertNotNil(realSessionManager.backgroundUserSessions[account.userIdentifier])
        
        // WHEN
        NotificationCenter.default.post(name: NSNotification.Name.UIApplicationDidReceiveMemoryWarning, object: nil)
        
        // THEN
        XCTAssertNotNil(realSessionManager.backgroundUserSessions[account.userIdentifier])
        
        // CLEANUP
        realSessionManager.tearDownAllBackgroundSessions()
    }
    
    func testThatItUnloadBackgroundUserSessionFromMemoryWarning() {
        // GIVEN
        let account = self.createAccount()
        account.cookieStorage().authenticationCookieData = NSData.secureRandomData(ofLength: 16)
        
        guard let mediaManager = mediaManager, let application = application else { return XCTFail() }
        
        let sessionManagerExpectation = self.expectation(description: "Session manager and session is loaded")

        // WHEN
        var realSessionManager: SessionManager! = nil
        SessionManager.create(appVersion: "0.0.0",
                       mediaManager: mediaManager,
                       analytics: nil,
                       delegate: nil,
                       application: application,
                       launchOptions: [:],
                       blacklistDownloadInterval : 60) { sessionManager in
                        
                        let environment = ZMBackendEnvironment(type: .staging)
                        let reachability = TestReachability()
                        let authenticatedSessionFactory = MockAuthenticatedSessionFactory(
                            apnsEnvironment: self.apnsEnvironment!,
                            application: application,
                            mediaManager: mediaManager,
                            flowManager: FlowManagerMock(),
                            transportSession: self.transportSession!,
                            environment: environment,
                            reachability: reachability
                        )
                        
                        sessionManager.authenticatedSessionFactory = authenticatedSessionFactory

            sessionManager.withSession(for: account) { userSession in
                realSessionManager = sessionManager
                XCTAssertNotNil(userSession)
                sessionManagerExpectation.fulfill()
            }
        }
        
        // THEN
        XCTAssertTrue(self.waitForCustomExpectations(withTimeout: 0.5))
        
        XCTAssertNotNil(realSessionManager.backgroundUserSessions[account.userIdentifier])
        
        // WHEN
        NotificationCenter.default.post(name: NSNotification.Name.UIApplicationDidReceiveMemoryWarning, object: nil)
        
        // THEN
        XCTAssertNil(realSessionManager.backgroundUserSessions[account.userIdentifier])
        
        // CLEANUP
        realSessionManager.tearDownAllBackgroundSessions()
    }
    
    func testThatItLoadsAccountForPush() {
        // GIVEN
        let account = Account(userName: "Test Account", userIdentifier: currentUserIdentifier)
        self.sessionManager?.accountManager.addOrUpdate(account)

        weak var weakSession: ZMUserSession? = nil
        var payload: [AnyHashable: Any] = [:]
        autoreleasepool {
            var session: ZMUserSession! = nil
            self.sessionManager?.withSession(for: account, perform: { createdSession in
                session = createdSession
                weakSession = createdSession
            })
            
            XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.5))
            
            let selfUser = ZMUser.selfUser(inUserSession: session)!
            selfUser.remoteIdentifier = currentUserIdentifier
            
            payload = ["data": [
                "user": selfUser.remoteIdentifier?.transportString()
                ]
            ]
            
            self.sessionManager!.tearDownAllBackgroundSessions()
            XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.5))
            session = nil
            XCTAssertNil(self.sessionManager!.backgroundUserSessions[account.userIdentifier])
        }
        self.userSession = nil
        XCTAssertNil(weakSession)
        
        // WHEN
        let pushCompleted = self.expectation(description: "Push completed")
        self.sessionManager?.pushDispatcher.didReceiveRemoteNotification(payload, fetchCompletionHandler: { _ in
            DispatchQueue.main.async {
                // THEN
                XCTAssertNotNil(self.sessionManager!.backgroundUserSessions[account.userIdentifier])
                
                // CLEANUP
                self.sessionManager!.tearDownAllBackgroundSessions()
                pushCompleted.fulfill()
            }
        })
        
        XCTAssertTrue(self.waitForCustomExpectations(withTimeout: 10))
    }
    
    func setupSession() -> ZMUserSession {
        let manager = self.sessionManager!.accountManager
        let account = Account(userName: "Test Account", userIdentifier: currentUserIdentifier)
        manager.addOrUpdate(account)
        account.cookieStorage().authenticationCookieData = NSData.secureRandomData(ofLength: 16)
        manager.addAndSelect(account)
        
        var session: ZMUserSession! = nil
        self.sessionManager?.withSession(for: account, perform: { createdSession in
            session = createdSession
        })
        
        let selfUser = ZMUser.selfUser(in: session.managedObjectContext)
        selfUser.remoteIdentifier = currentUserIdentifier
        
        session.managedObjectContext.saveOrRollback()
        
        session.syncManagedObjectContext.performGroupedBlock {
            let _ = ZMConversation(remoteID: self.currentUserIdentifier, createIfNeeded: true, in: session.syncManagedObjectContext)
            session.syncManagedObjectContext.saveOrRollback()
        }
        
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        return session
    }
    
    func testThatItActivatesTheAccountForPushReaction() {
        // GIVEN
        let session = self.setupSession()
        session.isPerformingSync = false
        session.pushChannelIsOpen = true
        application?.applicationState = .background
        
        let selfConversation = ZMConversation(remoteID: currentUserIdentifier, createIfNeeded: false, in: session.managedObjectContext)
        
        let localNotification = UILocalNotification()
        localNotification.setupUserInfo(selfConversation, for: nil)
        
        XCTAssertEqual(localNotification.zm_selfUserUUID, currentUserIdentifier)
        XCTAssertNil(self.sessionManager!.activeUserSession)
        
        // WHEN
        self.sessionManager?.didReceiveLocal(notification: localNotification, application: self.application!)
        
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.5))

        // THEN
        XCTAssertEqual(self.sessionManager!.activeUserSession, session)
        
        // CLEANUP
        self.sessionManager!.tearDownAllBackgroundSessions()
    }
    
    func testThatItActivatesTheAccountForPushAction() {
        // GIVEN
        let session = self.setupSession()
        session.isPerformingSync = false
        session.pushChannelIsOpen = true
        application?.applicationState = .inactive
        
        let selfConversation = ZMConversation(remoteID: currentUserIdentifier, createIfNeeded: false, in: session.managedObjectContext)
        
        let localNotification = UILocalNotification()
        localNotification.setupUserInfo(selfConversation, for: nil)
        
        XCTAssertEqual(localNotification.zm_selfUserUUID, currentUserIdentifier)
        XCTAssertNil(self.sessionManager!.activeUserSession)
        
        // WHEN
        self.sessionManager?.handleAction(with: nil, for: localNotification, with: [:], completionHandler: {_ in}, application: self.application!)
       
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.5))

        // THEN
        XCTAssertEqual(self.sessionManager!.activeUserSession, session)
        
        // CLEANUP
        self.sessionManager!.tearDownAllBackgroundSessions()
    }
    
}

class SessionManagerTests_Push: IntegrationTest {
    func testThatItStoresThePushToken() {
        // GIVEN
        let token = Data(bytes: [0xba, 0xdf, 0x00, 0xd0])
        let fakePushClient = TestPushDispatcherClient()
        // WHEN
        self.sessionManager!.pushDispatcher.add(client: fakePushClient)
        self.sessionManager!.didRegisteredForRemoteNotifications(with: token)
        
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // THEN
        XCTAssertEqual(fakePushClient.pushTokens.count, 1)
        XCTAssertEqual(fakePushClient.pushTokens[0].type, .regular)
        XCTAssertEqual(fakePushClient.pushTokens[0].data, token)
    }
    
    func testThatItForwardsThePush() {
        // GIVEN
        let fakePushClient = TestPushDispatcherClient()
        let payload: [AnyHashable: Any] = ["data": [
            "user": UUID().transportString(),
            "type": "notice"
            ]]
        
        // WHEN
        self.sessionManager!.pushDispatcher.add(client: fakePushClient)
        self.sessionManager!.didReceiveRemote(notification: payload, fetchCompletionHandler: {_ in })

        XCTAssert(self.waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // THEN
        XCTAssertEqual(fakePushClient.canHandlePayloads.count, 1)
        XCTAssertEqual(fakePushClient.receivedPayloads.count, 1)
        XCTAssert(NSDictionary(dictionary: fakePushClient.receivedPayloads[0]).isEqual(to: fakePushClient.canHandlePayloads[0]))
        XCTAssert(NSDictionary(dictionary: fakePushClient.receivedPayloads[0]).isEqual(to: payload))
    }
    
    func testThatItMarksTheTokenToDeleteWhenReceivingDidInvalidateToken() {
        // GIVEN
        let account = self.createAccount()
        
        // WHEN
        
        var session: ZMUserSession! = nil
        self.sessionManager?.withSession(for: account, perform: { createdSession in
            session = createdSession
        })
        
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        session.managedObjectContext.pushKitToken = ZMPushToken(deviceToken: Data(), identifier: "foo.bar", transportType: "APNS", fallback: "APNS", isRegistered: true)
        
        // THEN
        XCTAssertNotNil(session.managedObjectContext.pushKitToken)
        XCTAssertFalse(session.managedObjectContext.pushKitToken.isMarkedForDeletion)
        
        // AND WHEN
        self.sessionManager?.pushDispatcher.pushRegistrant.pushRegistry(PKPushRegistry.init(queue: nil), didInvalidatePushTokenForType:.voIP)
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // THEN
        XCTAssertTrue(session.managedObjectContext.pushKitToken.isMarkedForDeletion)
        
        // CLEANUP
        self.sessionManager!.tearDownAllBackgroundSessions()
    }
    
    class MockPushCredentials: PKPushCredentials {
        override var token: Data {
            return Data()
        }
    }
    
    func testThatItSetsThePushTokenWhenReceivingUpdateCredentials() {
        // GIVEN
        let account = self.createAccount()
        
        var session: ZMUserSession! = nil
        self.sessionManager?.withSession(for: account, perform: { createdSession in
            session = createdSession
        })
        
        let credentials = MockPushCredentials()
        // WHEN
        self.sessionManager?.pushDispatcher.pushRegistrant.pushRegistry(PKPushRegistry.init(queue: nil), didUpdate: credentials, forType: .voIP)
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // THEN
        XCTAssertNotNil(session.managedObjectContext.pushKitToken)
        XCTAssertEqual(session.managedObjectContext.pushKitToken.deviceToken, credentials.token)
        XCTAssertFalse(session.managedObjectContext.pushKitToken.isMarkedForDeletion)
        
        // CLEANUP
        self.sessionManager!.tearDownAllBackgroundSessions()
    }
}

// MARK: - Mocks
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

class SessionManagerObserverMock: SessionManagerObserver {
    
    var createdUserSession: [ZMUserSession] = []
    
    func sessionManagerCreated(userSession: ZMUserSession) {
        createdUserSession.append(userSession)
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
