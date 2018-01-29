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

import Foundation
@testable import WireSyncEngine

class TeamInviteTests: IntegrationTest {
    
    var team: MockTeam?
    
    override func setUp() {
        super.setUp()
        createSelfUserAndConversation()
        createExtraUsersAndConversations()
        team = remotelyInsertTeam(members: [selfUser])
    }
    
    override func tearDown() {
        team = nil
        super.tearDown()
    }
    
    @discardableResult func remotelyInsertTeam(members: Set<MockUser>, isBound: Bool = true) -> MockTeam? {
        var mockTeam: MockTeam?
        mockTransportSession.performRemoteChanges { session in
            mockTeam = session.insertTeam(withName: "Team", isBound: true, users: members)
        }
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        return mockTeam
    }

    func testThatItSendsATeamMemberInvitation_Successful() {
        // Given
        XCTAssert(login())
        guard let localSelfUser = user(for: selfUser) else { return XCTFail() }
        XCTAssertTrue(localSelfUser.hasTeam)

        // Ensure we have the right permissions to invite team members
        selfUser.memberships?.first?.permissions = .admin
        
        // When
        var result: InviteResult?
        localSelfUser.team?.invite(email: "test@example.com", in: userSession!) {
            result = $0
        }
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // Then
        guard let inviteResult = result else { return XCTFail("failed to get invite result") }
        XCTAssertEqual(inviteResult, InviteResult.success(email: "test@example.com"))
    }
    
    func testThatItReturnsAnErrorIncaseSelfUserDoesNotHaveAddTeamMemberPermissions() {
        // Given
        XCTAssert(login())
        guard let localSelfUser = user(for: selfUser) else { return XCTFail() }
        XCTAssert(localSelfUser.hasTeam)
        guard let member = localSelfUser.membership else { return XCTFail("no membership") }
        XCTAssertFalse(member.permissions.contains(.addTeamMember))
        
        // When
        var result: InviteResult?
        localSelfUser.team?.invite(email: "test@example.com", in: userSession!) {
            result = $0
        }
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // Then
        guard let inviteResult = result else { return XCTFail("failed to get invite result") }
        XCTAssertEqual(inviteResult, InviteResult.failure(email: "test@example.com", error: .unknown))
    }
    
}
