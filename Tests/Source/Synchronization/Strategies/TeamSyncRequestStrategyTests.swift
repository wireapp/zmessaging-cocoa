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


@testable import WireSyncEngine


final class TeamSyncRequestStrategyTests: MessagingTest {
    
    var sut: TeamSyncRequestStrategy!
    var mockSyncStatus: MockSyncStatus!
    var mockSyncStateDelegate: MockSyncStateDelegate!
    var mockApplicationStatus: MockApplicationStatus!
    
    override func setUp() {
        super.setUp()
        mockSyncStateDelegate = MockSyncStateDelegate()
        mockSyncStatus = MockSyncStatus(managedObjectContext: syncMOC, syncStateDelegate: mockSyncStateDelegate)
        mockApplicationStatus = MockApplicationStatus()
        sut = TeamSyncRequestStrategy(withManagedObjectContext: syncMOC, applicationStatus: mockApplicationStatus, syncStatus: mockSyncStatus)
    }
    
    override func tearDown() {
        sut = nil
        mockSyncStatus = nil
        mockApplicationStatus = nil
        mockSyncStateDelegate = nil
        super.tearDown()
    }
    
    func testThatItDoesNotGenerateARequestWhenInTheWrongSyncPhase() {
        // given
        var index = 0
        mockApplicationStatus.mockSynchronizationState = .synchronizing
        
        while let phase = SyncPhase(rawValue: index) {
            defer { index += 1 }
            guard phase != .fetchingTeams else { continue }
            
            // when
            mockSyncStatus.mockPhase = phase
            
            // then
            XCTAssertNil(sut.nextRequest(), "Should'nt generate a request in sync phase: \(phase)")
        }
    }
    
    func testThatItDoesntCreateRequestsInUnauthenticatedState() {
        // given
        mockSyncStatus.mockPhase = .fetchingTeams
        
        // when
        mockApplicationStatus.mockSynchronizationState = .unauthenticated
        
        // then
        XCTAssertNil(sut.nextRequest())
    }
    
    func testThatItDoesntCreateRequestsInEventProcessingState() {
        // given
        mockSyncStatus.mockPhase = .fetchingTeams
        
        // when
        mockApplicationStatus.mockSynchronizationState = .eventProcessing
        
        // then
        XCTAssertNil(sut.nextRequest())
    }
    
    func testThatItDownloadsAllTeams() {
        // given
        mockSyncStatus.mockPhase = .fetchingTeams
        mockApplicationStatus.mockSynchronizationState = .synchronizing
        
        // when
        guard let request = sut.nextRequest() else { return XCTFail("No request generated") }
        
        // then
        XCTAssertEqual(request.path, "/teams?size=50")
        XCTAssertEqual(request.method, .methodGET)
    }
    
    func testThatItResetsTheSlowSyncWhenThereIsAPermanentError() {
        // given
        mockSyncStatus.mockPhase = .fetchingTeams
        mockApplicationStatus.mockSynchronizationState = .synchronizing
        guard let request = sut.nextRequest() else { return XCTFail("No request generated") }
        
        // when
        let response = ZMTransportResponse(payload: nil, httpStatus: 400, transportSessionError: nil)
        request.complete(with: response)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.1))
        
        // then
        XCTAssertTrue(mockSyncStatus.didCallFailCurrentSyncPhase)
    }
    
    func testThatItCreatesLocalTeamForBoundTeamFromTheResponsePayload() {
        // given
        mockSyncStatus.mockPhase = .fetchingTeams
        mockApplicationStatus.mockSynchronizationState = .synchronizing
        guard let request = sut.nextRequest() else { return XCTFail("No request generated") }
        
        let team1Id = UUID.create(), team2Id = UUID.create()
        let team1CreatorId = UUID.create(), team2CreatorId = UUID.create()
        
        // when
        let payload: [String: Any] = [
            "has_more": false,
            "teams": [
                teamPayload(id: team1Id, creator: team1CreatorId, name: "Wire GmbH", isBound: true),
                teamPayload(id: team2Id, creator: team2CreatorId, name: "Private", isBound: false),
            ]
        ]
        
        request.complete(with: .init(payload: payload as ZMTransportData, httpStatus: 200, transportSessionError: nil))
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.1))
        
        // then
        let team1 = Team.fetch(withRemoteIdentifier: team1Id, in: syncMOC)
        XCTAssertNotNil(team1)
        XCTAssertEqual(team1?.name, "Wire GmbH")
        let creator1 = ZMUser.fetch(withRemoteIdentifier: team1CreatorId, in: syncMOC)
        XCTAssertNotNil(creator1)
        XCTAssertEqual(team1?.creator, creator1)
        
        let team2 = Team.fetch(withRemoteIdentifier: team2Id, in: syncMOC)
        XCTAssertNil(team2)
    }
    
    func testThatItDownloadsATeamsMembersOnceAllTeamsHaveBeenDownloaded() {
        // given
        mockSyncStatus.mockPhase = .fetchingTeams
        mockApplicationStatus.mockSynchronizationState = .synchronizing
        let teamId = UUID.create()
        
        // when fetching the teams
        do {
            guard let request = sut.nextRequest() else { return XCTFail("No request generated") }
            
            // when
            let payload: [String: Any] = [
                "has_more": false,
                "teams": [teamPayload(id: teamId, name: "Wire GmbH", isBound: true)]
            ]
            
            let response = ZMTransportResponse(payload: payload as ZMTransportData, httpStatus: 200, transportSessionError: nil)
            request.complete(with: response)
            XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.1))
        }
        
        // then whe should fetch the teams members
        do {
            guard let request = sut.nextRequest() else { return XCTFail("No request generated") }
            XCTAssertEqual(request.path, "/teams/\(teamId.transportString())/members")
            XCTAssertEqual(request.method, .methodGET)
        }
    }
    
    func testThatItResetsTheSyncWhenItReceivesAPermanentErrorDownloadingMembers() {
        // given
        mockSyncStatus.mockPhase = .fetchingTeams
        mockApplicationStatus.mockSynchronizationState = .synchronizing
        let team1Id = UUID.create()
        
        // when fetching the teams
        do {
            guard let request = sut.nextRequest() else { return XCTFail("No request generated") }
            
            // when
            let payload: [String: Any] = [
                "has_more": false,
                "teams": [
                    teamPayload(id: team1Id, name: "Wire GmbH", isBound: true),
                ]
            ]
            
            let response = ZMTransportResponse(payload: payload as ZMTransportData, httpStatus: 200, transportSessionError: nil)
            request.complete(with: response)
            XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.1))
        }
        
        // then whe should fetch the team members of the first team
        do {
            guard let request = sut.nextRequest() else { return XCTFail("No request generated") }
            XCTAssertEqual(request.path, "/teams/\(team1Id.transportString())/members")
            XCTAssertEqual(request.method, .methodGET)
            
            // when
            request.complete(with: .init(payload: nil, httpStatus: 404, transportSessionError: nil))
            XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.1))
            
            // then
            let team = Team.fetchOrCreate(with: team1Id, create: false, in: syncMOC, created: nil)
            guard let aTeam = team else { return XCTFail("no team")}
            XCTAssertTrue(aTeam.needsToBeUpdatedFromBackend) // refetching the team from the BE should also result in a permanent error which should then delete the team

            XCTAssertNil(sut.nextRequest())
            XCTAssertTrue(mockSyncStatus.didCallFailCurrentSyncPhase)
        }
    }
    
    func testThatItCompletesTheSyncStateAfterDownloadingAllMembers() {
        // given
        mockSyncStatus.mockPhase = .fetchingTeams
        mockApplicationStatus.mockSynchronizationState = .synchronizing
        
        // fetch /teams
        do {
            guard let request = sut.nextRequest() else { return XCTFail("No request generated") }
            let payload: [String: Any] = ["has_more": false, "teams": [teamPayload(name: "Wire GmbH", isBound: true)]]
            request.complete(with: .init(payload: payload as ZMTransportData, httpStatus: 200, transportSessionError: nil))
            XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.1))
        }
        
        XCTAssertFalse(mockSyncStatus.didCallFinishCurrentSyncPhase)
        
        // fetch /teams/{id}/members
        do {
            guard let request = sut.nextRequest() else { return XCTFail("No request generated") }
            let payload: [String: Any] = [
                "members": [
                    ["user": UUID.create().transportString(), "permissions": NSNumber(value: Permissions.addRemoveConversationMember.rawValue)]
                ]
            ]
            
            request.complete(with: .init(payload: payload as ZMTransportData, httpStatus: 200, transportSessionError: nil))
            XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.1))
        }
        
        // then
        XCTAssertNil(sut.nextRequest())
        XCTAssertTrue(mockSyncStatus.didCallFinishCurrentSyncPhase)
    }
    
    func testThatItRequestAccountDeletionAfterDiscoveringDeletedTeamOnlyAfterPerformingASlowSync() {
        // given
        let selfUser = ZMUser.selfUser(in: uiMOC)
        selfUser.remoteIdentifier = userIdentifier
        uiMOC.saveOrRollback()
        mockSyncStatus.mockPhase = .fetchingTeams
        mockApplicationStatus.mockSynchronizationState = .synchronizing
        let remotelyDeletedTeamId = UUID.create()
        
        syncMOC.performGroupedBlockAndWait {
            let remotelyDeletedTeam = Team.insertNewObject(in: self.syncMOC)
            remotelyDeletedTeam.remoteIdentifier = remotelyDeletedTeamId
        }
        
        // expect
        let accountDeletedExpectation = expectation(description: "Account was deleted")
        var token : Any? = PostLoginAuthenticationObserverToken(managedObjectContext: uiMOC) { (event, _) in
            if case WireSyncEngine.PostLoginAuthenticationEvent.accountDeleted = event {
                accountDeletedExpectation.fulfill()
            }
        }
        XCTAssertNotNil(token)
        
        // when
        guard let request = sut.nextRequest() else { return XCTFail("No request generated") }
        let payload: [String: Any] = [
            "has_more": false,
            "teams": []
        ]
        request.complete(with: .init(payload: payload as ZMTransportData, httpStatus: 200, transportSessionError: nil))
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.1))
        
        
        // then
        XCTAssertTrue(waitForCustomExpectations(withTimeout: 0.5))
        token = nil
    }
    
    // MARK: - Helper
    
    private func teamPayload(id: UUID = .create(), creator creatorId: UUID = .create(), name: String, isBound: Bool) -> ZMTransportData {
        return [
            "id": id.transportString(),
            "creator": creatorId.transportString(),
            "name": name,
            "icon": "",
            "icon_key": NSNull(),
            "binding" : (isBound ? true: false)
            ] as ZMTransportData
    }
    
}
