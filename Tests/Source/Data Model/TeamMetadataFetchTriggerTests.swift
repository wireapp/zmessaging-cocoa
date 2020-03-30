//
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

@testable import WireSyncEngine

class TeamMetadataFetchTriggerTests: DatabaseTest {

    func testItTriggersUserFetch() {
        // Given
        let sut = TeamMetadataFetchTrigger()
        let user = ZMUser.insertNewObject(in: uiMOC)
        user.needsToBeUpdatedFromBackend = false

        // When
        sut.triggerUserFetch(for: user)

        // Then
        XCTAssertTrue(user.needsToBeUpdatedFromBackend)
    }

    func testItTriggersUserRichProfileFetch() {
        // Given
        let sut = TeamMetadataFetchTrigger()
        let user = ZMUser.insertNewObject(in: uiMOC)
        user.needsRichProfileUpdate = false

        // When
        sut.triggerUserRichprofileFetch(for: user)

        // Then
        XCTAssertTrue(user.needsRichProfileUpdate)
    }

    func testItTriggersMembershipFetch() {
        // Given
        let sut = TeamMetadataFetchTrigger()
        let user = ZMUser.insertNewObject(in: uiMOC)
        let team = Team.insertNewObject(in: uiMOC)

        let membership = Member.insertNewObject(in: uiMOC)
        membership.user = user
        membership.team = team
        membership.needsToBeUpdatedFromBackend = false

        // When
        sut.triggerMembershipFetch(for: user)

        // Then
        XCTAssertTrue(membership.needsToBeUpdatedFromBackend)
    }

    func testItTriggersTeamFetch() {
        // Given
        let sut = TeamMetadataFetchTrigger()

        let team = Team.insertNewObject(in: uiMOC)
        team.needsToBeUpdatedFromBackend = false

        // When
        sut.triggerTeamFetch(for: team)

        // Then
        XCTAssertTrue(team.needsToBeUpdatedFromBackend)
    }

}
