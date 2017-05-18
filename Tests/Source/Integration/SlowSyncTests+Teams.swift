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


class SlowSyncTestsTeams: IntegrationTestBase {

    func testThatItFetchesTeamsAndMembersDuringSlowSync() {
        // Given
        var team: MockTeam!
        var otherMember: MockMember!

        // We remotely create a team on the server before logging in
        mockTransportSession.performRemoteChanges { session in
            team = session.insertTeam(withName: "Wire GmbH")
            let member = session.insertMember(with: self.selfUser, in: team)
            member.permissions = .member
            otherMember = session.insertMember(with: self.user5, in: team)
            otherMember.permissions = .admin
        }

        XCTAssert(waitForEverythingToBeDone())

        // When
        XCTAssert(logInAndWaitForSyncToBeComplete())

        // Then
        var fetchedTeams = false, fetchedMembers = false

        mockTransportSession.receivedRequests().forEach { request in
            switch request.path {
            case "/teams?size=250": fetchedTeams = true
            case "/teams/\(team.identifier)/members": fetchedMembers = true
            default: break
            }
        }

        XCTAssert(fetchedTeams)
        XCTAssert(fetchedMembers)

        do {
            let teams = ZMUser.selfUser(in: syncMOC).teams
            guard let team = teams?.first else { return XCTFail("Team missing") }
            XCTAssertEqual(team.name, "Wire GmbH")
            XCTAssertEqual(team.members.count, 2)
        }
    }

}
