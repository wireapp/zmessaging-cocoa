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
    
    override func tearDown() {
        sut.encryptMessagesAtRest = false
        
        super.tearDown()
    }
    
    // MARK: - Database locking/unlocking
    
    func testThatDatabaseIsUnlocked_WhenEncryptionAtRestIsDisabled() {
        // given
        simulateLoggedInUser()
        syncMOC.saveOrRollback()
        
        // when
        sut.encryptMessagesAtRest = false
        
        // then
        XCTAssertFalse(sut.isDatabaseLocked)
    }

    func testThatDatabaseIsUnlocked_AfterActivatingEncryptionAtRest() {
        // given
        simulateLoggedInUser()
        syncMOC.saveOrRollback()
        
        // when
        sut.encryptMessagesAtRest = true
        
        // then
        XCTAssertFalse(sut.isDatabaseLocked)
    }
    
    func testThatDatabaseIsUnlocked_AfterDeactivatingEncryptionAtRest() {
        // given
        simulateLoggedInUser()
        syncMOC.saveOrRollback()
        sut.encryptMessagesAtRest = true
        
        // when
        sut.encryptMessagesAtRest = false
        
        // then
        XCTAssertFalse(sut.isDatabaseLocked)
    }
        
    func testThatDatabaseIsUnlocked_AfterUnlockingDatabase() throws {
        // given
        simulateLoggedInUser()
        syncMOC.saveOrRollback()
        sut.encryptMessagesAtRest = true
        sut.applicationDidEnterBackground(nil)
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // when
        let context = LAContext()
        try sut.unlockDatabase(with: context)
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertFalse(sut.isDatabaseLocked)
    }
    
    func testThatDatabaseIsLocked_AfterEnteringBackground() {
        // given
        simulateLoggedInUser()
        syncMOC.saveOrRollback()
        sut.encryptMessagesAtRest = true
        
        // when
        sut.applicationDidEnterBackground(nil)
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertTrue(sut.isDatabaseLocked)
    }

    // MARK: - Database lock handler/observer
    
    func testThatDatabaseLockedHandlerIsCalled_AfterDatabaseIsLocked() {
        // given
        simulateLoggedInUser()
        syncMOC.saveOrRollback()
        sut.encryptMessagesAtRest = true
        
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
    }
    
    func testThatDatabaseLockedHandlerIsCalled_AfterUnlockingDatabase() throws {
        // given
        simulateLoggedInUser()
        syncMOC.saveOrRollback()
        sut.encryptMessagesAtRest = true
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

        let account = Account(userName: "", userIdentifier: ZMUser.selfUser(in: syncMOC).remoteIdentifier)
        let oldKeys = try EncryptionKeys.createKeys(for: account)

        // when
        sut.encryptMessagesAtRest = true

        // then
        let newKeys = syncMOC.encryptionKeys

        XCTAssertFalse(sut.isDatabaseLocked)
        XCTAssertNotEqual(oldKeys, newKeys)
    }
    
}
