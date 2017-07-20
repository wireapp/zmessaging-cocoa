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

class MockLocalStoreProvider: NSObject, LocalStoreProviderProtocol {
    var appGroupIdentifier: String
    var storeURL: URL?
    var keyStoreURL: URL?
    var cachesURL: URL?
    var sharedContainerDirectory: URL?

    override init() {
        appGroupIdentifier = "group." + Bundle.main.bundleIdentifier!
        sharedContainerDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        keyStoreURL = sharedContainerDirectory
        cachesURL = sharedContainerDirectory
        storeURL = sharedContainerDirectory?.appendingPathComponent("wire.db")
    }
    
    var storeExists = true
    var isStoreReady = true
    var needsToPrepareLocalStore = false
    
    var prepareLocalStoreCalled = false
    func prepareLocalStore(completion completionHandler: @escaping (() -> ())) {
        prepareLocalStoreCalled = true
        completionHandler()
    }
}

class SessionManagerTestDelegate: SessionManagerDelegate {
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

class SessionManagerTests: IntegrationTest {
    
    var storeProvider: MockLocalStoreProvider!
    var delegate: SessionManagerTestDelegate!
    
    override func setUp() {
        super.setUp()
        storeProvider = MockLocalStoreProvider()
        delegate = SessionManagerTestDelegate()
    }
    
    func createManager() -> SessionManager {
        return SessionManager(storeProvider: storeProvider,
                              appVersion: "0.0.0",
                              transportSession: transportSession!,
                              mediaManager: mediaManager!,
                              analytics: nil,
                              delegate: delegate,
                              application: application!,
                              launchOptions: [:])
    }
    
    override func tearDown() {
        storeProvider = nil
        delegate = nil
        super.tearDown()
    }
    
    func testThatItCreatesUnauthenticatedSessionAndNotifiesDelegateIfStoreIsNotAvailable() {
        // given
        storeProvider.storeExists = false
        
        // when
        _ = createManager()
        
        // then
        XCTAssertNil(delegate.userSession)
        XCTAssertNotNil(delegate.unauthenticatedSession)
    }
    
    func testThatItCreatesUserSessionAndNotifiesDelegateIfStoreIsAvailable() {
        // given
        storeProvider.storeExists = true
        
        // when
        _ = createManager()
        
        // then
        XCTAssertNotNil(delegate.userSession)
        XCTAssertNil(delegate.unauthenticatedSession)
    }
}
