////
// Wire
// Copyright (C) 2018 Wire Swiss GmbH
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

class ZMHotFixTests_Integration: MessagingTest {

    func testThatOnlyTeamAndGroupConversationsAreUpdated() {
        // given
        let g1 = ZMConversation.insertNewObject(in: self.syncMOC)
        g1.conversationType = .group
        XCTAssertFalse(g1.needsToBeUpdatedFromBackend)
        
        let g2 = ZMConversation.insertNewObject(in: self.syncMOC)
        g2.conversationType = .group
        g2.team = Team.insertNewObject(in: self.syncMOC)
        XCTAssertFalse(g2.needsToBeUpdatedFromBackend)

        let g3 = ZMConversation.insertNewObject(in: self.syncMOC)
        g3.conversationType = .connection
        XCTAssertFalse(g3.needsToBeUpdatedFromBackend)

        self.syncMOC.setPersistentStoreMetadata("146.0", key: "lastSavedVersion")
        let sut = ZMHotFix(syncMOC: self.syncMOC)

        // when
        self.performIgnoringZMLogError {
            sut?.applyPatches(forCurrentVersion: "147.0")
            XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        }

        // then
        XCTAssertTrue(g1.needsToBeUpdatedFromBackend)
        XCTAssertTrue(g2.needsToBeUpdatedFromBackend)
        XCTAssertFalse(g3.needsToBeUpdatedFromBackend)
    }

    
    func testThatOnlyGroupConversationsAreUpdated() {
        // given
        let g1 = ZMConversation.insertNewObject(in: self.syncMOC)
        g1.conversationType = .group
        XCTAssertFalse(g1.needsToBeUpdatedFromBackend)
        
        let g2 = ZMConversation.insertNewObject(in: self.syncMOC)
        g2.conversationType = .connection
        g2.team = Team.insertNewObject(in: self.syncMOC)
        XCTAssertFalse(g2.needsToBeUpdatedFromBackend)
        
        let g3 = ZMConversation.insertNewObject(in: self.syncMOC)
        g3.conversationType = .connection
        XCTAssertFalse(g3.needsToBeUpdatedFromBackend)
        
        self.syncMOC.setPersistentStoreMetadata("147.0", key: "lastSavedVersion")
        let sut = ZMHotFix(syncMOC: self.syncMOC)
        
        // when
        self.performIgnoringZMLogError {
            sut?.applyPatches(forCurrentVersion: "155.0")
            XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        }
        
        // then
        XCTAssertTrue(g1.needsToBeUpdatedFromBackend)
        XCTAssertFalse(g2.needsToBeUpdatedFromBackend)
        XCTAssertFalse(g3.needsToBeUpdatedFromBackend)
    }
}
