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

final class ConversationRoleDownstreamRequestStrategyTests: MessagingTest {
    var sut: ConversationRoleDownstreamRequestStrategy!
    var mockSyncStatus: MockSyncStatus!
    var mockSyncStateDelegate: MockSyncStateDelegate!
    var mockApplicationStatus: MockApplicationStatus!

    override func setUp() {
        super.setUp()
        mockSyncStateDelegate = MockSyncStateDelegate()
        mockSyncStatus = MockSyncStatus(managedObjectContext: syncMOC, syncStateDelegate: mockSyncStateDelegate)
        mockApplicationStatus = MockApplicationStatus()
        mockApplicationStatus.mockSynchronizationState = .synchronizing
        sut = ConversationRoleDownstreamRequestStrategy(withManagedObjectContext: syncMOC, applicationStatus: mockApplicationStatus)
    }
    
    override func tearDown() {
        sut = nil
        mockSyncStatus = nil
        mockApplicationStatus = nil
        mockSyncStateDelegate = nil
        super.tearDown()
    }

    func testThatPredicateIsCorrect(){
        // given
        let convo1: ZMConversation = ZMConversation.insertNewObject(in: self.syncMOC)
        convo1.conversationType = .group
        convo1.remoteIdentifier = .create()
        convo1.needsToDownloadRoles = true

        let convo2: ZMConversation = ZMConversation.insertNewObject(in: self.syncMOC)
        convo2.conversationType = .group
        convo2.remoteIdentifier = .create()
        convo2.needsToDownloadRoles = false
        
        // then
        XCTAssert(sut.downstreamSync.predicateForObjectsToDownload.evaluate(with:convo1))
        XCTAssertFalse(sut.downstreamSync.predicateForObjectsToDownload.evaluate(with:convo2))
    }

    func testThatItCreatesAReuqestForATeamThatNeedsToBeRedownloadItsMembersFromTheBackend() {
        syncMOC.performGroupedBlockAndWait {
            // given
            let convo1: ZMConversation = ZMConversation.insertNewObject(in: self.syncMOC)
            convo1.conversationType = .group
            convo1.remoteIdentifier = .create()
            convo1.addParticipantAndUpdateConversationState(user: ZMUser.selfUser(in: self.syncMOC), role: nil)

            self.mockApplicationStatus.mockSynchronizationState = .eventProcessing
            
            // when
            convo1.needsToDownloadRoles = true
            self.boostrapChangeTrackers(with: convo1)
            
            // then
            guard let request = self.sut.nextRequest() else { return XCTFail("No request generated") }
            XCTAssertEqual(request.method, .methodGET)
            XCTAssertEqual(request.path, "/conversations/\(convo1.remoteIdentifier!.transportString())/roles")
        }
    }

    func testThatItFetch() {
        syncMOC.performGroupedBlockAndWait {
            // given
            let convo1: ZMConversation = ZMConversation.insertNewObject(in: self.syncMOC)
            convo1.conversationType = .group
            convo1.remoteIdentifier = .create()
            convo1.addParticipantAndUpdateConversationState(user: ZMUser.selfUser(in: self.syncMOC), role: nil)
            
            self.mockApplicationStatus.mockSynchronizationState = .eventProcessing
            
            // when
            convo1.needsToDownloadRoles = true
            let objs:[ZMConversation] = self.sut.contextChangeTrackers.compactMap({$0.fetchRequestForTrackedObjects()}).flatMap({self.syncMOC.executeFetchRequestOrAssert($0) as! [ZMConversation] })
                

            // then            
            XCTAssertEqual(objs, [convo1])
        }
    }
    
    ///TODO: more tests for error cases.

    // MARK: - Helper
    ///TODO: move to utility
    private func boostrapChangeTrackers(with objects: ZMManagedObject...) {
        sut.contextChangeTrackers.forEach {
            $0.objectsDidChange(Set(objects))
        }
        
    }
}
