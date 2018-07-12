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

    func testThatPushTokenIsMigrated() {
        // given
        createSelfClient()
        let token = Data(bytes: [0x01, 0x02, 0x03])
        let identifier = "com.identifier"
        let transport = "APNS"
        let registered = true
        let toDelete = false
        let legacyToken = ZMPushToken(deviceToken: token, identifier: identifier, transportType: transport, isRegistered: registered, isMarkedForDeletion: toDelete)
        self.syncMOC.pushKitToken = legacyToken


        self.syncMOC.setPersistentStoreMetadata("175.0", key: "lastSavedVersion")
        let sut = ZMHotFix(syncMOC: self.syncMOC)

        self.performIgnoringZMLogError {
            sut?.applyPatches(forCurrentVersion: "178.0")
            XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        }

        guard let client = ZMUser.selfUser(in: self.syncMOC).selfClient() else { XCTFail(); return }
        guard let pushToken = client.pushToken else { XCTFail(); return }
        XCTAssertNil(self.syncMOC.pushKitToken)

        XCTAssertEqual(pushToken.deviceToken, token)
        XCTAssertEqual(pushToken.appIdentifier, identifier)
        XCTAssertEqual(pushToken.transportType, transport)
        XCTAssertEqual(pushToken.isRegistered, registered)
        XCTAssertEqual(pushToken.isMarkedForDeletion, toDelete)

        // We need to re-download it to make sure it is still valid
        XCTAssertTrue(pushToken.isMarkedForDownload)
    }
}
