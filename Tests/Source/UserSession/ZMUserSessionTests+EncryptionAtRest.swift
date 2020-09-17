////
// Wire
// Copyright (C) 2020 Wire Swiss GmbH
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

import Foundation
import LocalAuthentication
@testable import WireSyncEngine

class ZMUserSessionTests_EncryptionAtRest: ZMUserSessionTestsBase {

    private var account: Account {
        Account(userName: "", userIdentifier: ZMUser.selfUser(in: syncMOC).remoteIdentifier)
    }

    override func tearDown() {
        try! EncryptionKeys.deleteKeys(for: account)

        super.tearDown()
    }

    private func setEncryptionAtRest(enabled: Bool, file: StaticString = #file, line: UInt = #line) {
        sut.setEncryptionAtRest(enabled: enabled) { result in
            if case let .failure(error) = result {
                XCTFail("Failed to update EAR. Reason: \(error.localizedDescription)", file: file, line: line)
            }
        }

        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5), file: file, line: line)
    }
    
    // MARK: - Database locking/unlocking
    
    func testThatDatabaseIsUnlocked_WhenEncryptionAtRestIsDisabled() {
        // given
        simulateLoggedInUser()
        syncMOC.saveOrRollback()
        
        // when
        setEncryptionAtRest(enabled: false)
        
        // then
        XCTAssertFalse(sut.isDatabaseLocked)
    }

    func testThatDatabaseIsUnlocked_AfterActivatingEncryptionAtRest() {
        // given
        simulateLoggedInUser()
        syncMOC.saveOrRollback()
        
        // when
        setEncryptionAtRest(enabled: true)
        
        // then
        XCTAssertFalse(sut.isDatabaseLocked)
    }
    
    func testThatDatabaseIsUnlocked_AfterDeactivatingEncryptionAtRest() {
        // given
        simulateLoggedInUser()
        syncMOC.saveOrRollback()
        setEncryptionAtRest(enabled: true)
        
        // when
        setEncryptionAtRest(enabled: false)
        
        // then
        XCTAssertFalse(sut.isDatabaseLocked)
    }
        
    func testThatDatabaseIsUnlocked_AfterUnlockingDatabase() throws {
        // given
        simulateLoggedInUser()
        syncMOC.saveOrRollback()
        setEncryptionAtRest(enabled: true)
        sut.applicationDidEnterBackground(nil)
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // when
        let context = LAContext()
        try sut.unlockDatabase(with: context)
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertFalse(sut.isDatabaseLocked)
    }
    
    func testThatDatabaseIsLocked_AfterEnteringBackground() throws {
        // given
        simulateLoggedInUser()
        syncMOC.saveOrRollback()
        setEncryptionAtRest(enabled: true)
        
        // when
        sut.applicationDidEnterBackground(nil)
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertTrue(sut.isDatabaseLocked)

        // cleanup
        let context = LAContext()
        try sut.unlockDatabase(with: context)
        XCTAssertTrue(waitForCustomExpectations(withTimeout: 0.5))
    }

    // MARK: - Database lock handler/observer
    
    func testThatDatabaseLockedHandlerIsCalled_AfterDatabaseIsLocked() throws {
        // given
        simulateLoggedInUser()
        syncMOC.saveOrRollback()
        setEncryptionAtRest(enabled: true)
        
        // expect
        let databaseIsLocked = expectation(description: "database is locked")
        var token: Any? = sut.registerDatabaseLockedHandler { (isDatabaseLocked) in
            if isDatabaseLocked {
                databaseIsLocked.fulfill()
            }
        }
        XCTAssertNotNil(token)
        
        // when
        sut.applicationDidEnterBackground(nil)
        XCTAssertTrue(waitForCustomExpectations(withTimeout: 0.5))
        
        // cleanup
        token = nil

        let context = LAContext()
        try sut.unlockDatabase(with: context)
        XCTAssertTrue(waitForCustomExpectations(withTimeout: 0.5))
    }
    
    func testThatDatabaseLockedHandlerIsCalled_AfterUnlockingDatabase() throws {
        // given
        simulateLoggedInUser()
        syncMOC.saveOrRollback()
        setEncryptionAtRest(enabled: true)
        sut.applicationDidEnterBackground(nil)
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // expect
        let databaseIsUnlocked = expectation(description: "database is unlocked")
        var token: Any? = sut.registerDatabaseLockedHandler { (isDatabaseLocked) in
            if !isDatabaseLocked {
                databaseIsUnlocked.fulfill()
            }
        }
        XCTAssertNotNil(token)
        
        // when
        let context = LAContext()
        try sut.unlockDatabase(with: context)
        XCTAssertTrue(waitForCustomExpectations(withTimeout: 0.5))
        
        // cleanup
        token = nil
    }

    // MARK: - Misc

    func testThatOldEncryptionKeysAreReplaced_AfterActivatingEncryptionAtRest() throws {
        // given
        simulateLoggedInUser()
        syncMOC.saveOrRollback()

        let oldKeys = try EncryptionKeys.createKeys(for: account)

        // when
        setEncryptionAtRest(enabled: true)

        // then
        let newKeys = syncMOC.encryptionKeys

        XCTAssertFalse(sut.isDatabaseLocked)
        XCTAssertNotEqual(oldKeys, newKeys)
    }
    
}
