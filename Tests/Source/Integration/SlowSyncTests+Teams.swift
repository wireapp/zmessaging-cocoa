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

    func DISABLED_testThatItFetchesTeamsAndMembersDuringSlowSync() {
        // Given
        var team: MockTeam!
        var otherMember: MockMember!

        // We remotely create a team on the server before logging in
        mockTransportSession.performRemoteChanges { session in
            team = session.insertTeam(withName: "Wire GmbH", isBound: true)
            let member = session.insertMember(with: self.selfUser, in: team)
            member.permissions = .member
            otherMember = session.insertMember(with: self.user5, in: team) // User 5 is unconnected
            otherMember.permissions = .admin
        }

        XCTAssert(waitForEverythingToBeDone())

        // When
        XCTAssert(logInAndWaitForSyncToBeComplete())

        // Then
        var fetchedTeams = false, fetchedMembers = false

        mockTransportSession.receivedRequests().forEach { request in
            switch request.path {
            case "/teams?size=50": fetchedTeams = true
            case "/teams/\(team.identifier)/members": fetchedMembers = true
            default: break
            }
        }

        XCTAssert(fetchedTeams)
        XCTAssert(fetchedMembers)

        do {
            let selfUser = ZMUser.selfUser(in: syncMOC)
            XCTAssert(selfUser.hasTeam)
            guard let team = selfUser.team else { return XCTFail("Team missing") }

            let selfMember = selfUser.membership
            XCTAssertNotNil(selfMember)
            XCTAssertEqual(selfMember?.permissions, .member)
            XCTAssertEqual(team.name, "Wire GmbH")
            XCTAssertEqual(team.members.count, 2)

            let member = team.members.first { mockMember(otherMember, isEqualTo: $0) }
            XCTAssertNotNil(member)
            XCTAssertEqual(member?.permissions, .admin)
            XCTAssertEqual(member?.user?.remoteIdentifier, user(for: user5).remoteIdentifier)
        }
    }

    func DISABLED_testThatItFetchesTeamConversationsDuringSlowSync() {
        // Given
        var team: MockTeam!
        var otherMember: MockMember!

        // We remotely create a team on the server before logging in
        mockTransportSession.performRemoteChanges { session in
            team = session.insertTeam(withName: "Wire GmbH", isBound: true)
            let member = session.insertMember(with: self.selfUser, in: team)
            member.permissions = .member
            otherMember = session.insertMember(with: self.user5, in: team) // User 5 is unconnected
            otherMember.permissions = .admin

            let conversation = session.insertGroupConversation(withSelfUser: self.selfUser, otherUsers: [self.user5, self.user3])
            conversation.team = team
        }

        XCTAssert(waitForEverythingToBeDone())

        // When
        XCTAssert(logInAndWaitForSyncToBeComplete())

        // Then
        var fetchedTeams = false, fetchedMembers = false

        mockTransportSession.receivedRequests().forEach { request in
            switch request.path {
            case "/teams?size=50": fetchedTeams = true
            case "/teams/\(team.identifier)/members": fetchedMembers = true
            default: break
            }
        }

        XCTAssert(fetchedTeams)
        XCTAssert(fetchedMembers)

        do {
            let realSelfUser = user(for: selfUser)!
            XCTAssert(realSelfUser.hasTeam)
            guard let team = realSelfUser.team else { return XCTFail("Team missing") }

            XCTAssertEqual(team.conversations.count, 1)
            guard let conversation = team.conversations.first else { return XCTFail("Conversation missing") }
            XCTAssertEqual(conversation.conversationType, .group)

            XCTAssertTrue(conversation.otherActiveParticipants.contains(user(for: user3)!))
            XCTAssertTrue(user(for: user3).isGuest(in: conversation))
            XCTAssertTrue(user(for: user5).isTeamMember)
            XCTAssertTrue(realSelfUser.isTeamMember)

            let selfMember = realSelfUser.membership
            XCTAssertNotNil(selfMember)
            XCTAssertEqual(selfMember?.permissions, .member)
            let user5Member = user(for: user5).membership
            XCTAssertEqual(user5Member?.permissions, .admin)
            XCTAssertEqual(team.name, "Wire GmbH")
            XCTAssertEqual(team.members.count, 2)
        }
    }

}
