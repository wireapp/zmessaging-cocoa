//
// Wire
// Copyright (C) 2019 Wire Swiss GmbH
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

@testable import WireSyncEngine

final class RoleDownstreamRequestStrategyTests: MessagingTest {
    var sut: RoleDownstreamRequestStrategy!
    var mockSyncStatus: MockSyncStatus!
    var mockSyncStateDelegate: MockSyncStateDelegate!
    var mockApplicationStatus: MockApplicationStatus!

    override func setUp() {
        super.setUp()
        mockSyncStateDelegate = MockSyncStateDelegate()
        mockSyncStatus = MockSyncStatus(managedObjectContext: syncMOC, syncStateDelegate: mockSyncStateDelegate)
        mockApplicationStatus = MockApplicationStatus()
        mockApplicationStatus.mockSynchronizationState = .synchronizing
        sut = RoleDownstreamRequestStrategy(with: syncMOC, applicationStatus: mockApplicationStatus, syncStatus: mockSyncStatus)
        
        syncMOC.performGroupedBlockAndWait {
            ///TODO:
//            self.conversation1 = ZMConversation.insertNewObject(in: self.syncMOC)
//            self.conversation1.remoteIdentifier = UUID()
//
//            self.conversation2 = ZMConversation.insertNewObject(in: self.syncMOC)
//            self.conversation2.remoteIdentifier = UUID()
        }
    }
    
    override func tearDown() {
        sut = nil
        mockSyncStatus = nil
        mockApplicationStatus = nil
        mockSyncStateDelegate = nil
//        conversation1 = nil
//        conversation2 = nil
        super.tearDown()
    }

    // MARK: - Slow Sync
    
    func testThatItRequestsRoles_DuringSlowSync() {
        syncMOC.performGroupedBlockAndWait {
            // GIVEN
            self.mockSyncStatus.mockPhase = .fetchingRoles
            
            // WHEN
            guard let request = self.sut.nextRequest() else { return XCTFail() }
            
            // THEN
            XCTAssertEqual(request.path, "TODO")///TODO:
        }
    }

}
