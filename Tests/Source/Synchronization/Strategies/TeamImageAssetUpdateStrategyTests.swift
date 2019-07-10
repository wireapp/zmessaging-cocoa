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

import Foundation
import XCTest
@testable import WireSyncEngine

final class TeamImageAssetUpdateStrategyTests : MessagingTest {

    var sut: TeamImageAssetUpdateStrategy!
    var mockApplicationStatus : MockApplicationStatus!
    let pictureAssetId = "blah"

    override func setUp() {
        super.setUp()
        self.mockApplicationStatus = MockApplicationStatus()

        self.mockApplicationStatus.mockSynchronizationState = .eventProcessing

        sut = TeamImageAssetUpdateStrategy(withManagedObjectContext: syncMOC,
                                           applicationStatus: mockApplicationStatus)
    }

    override func tearDown() {
        mockApplicationStatus = nil
        sut = nil
        super.tearDown()
    }

    func testThatItCreatesDownstreamRequestSyncs() {
        XCTAssertNotNil(sut.downstreamRequestSync)
    }

    private func createMockTeam() -> Team {
        let team = Team(context: syncMOC)
        team.pictureAssetId = pictureAssetId
        team.remoteIdentifier = UUID()

        return team
    }

    func testThatItWhitelistsUserOnPreviewSyncForImageNotification() {
        // GIVEN
        let team = createMockTeam()
        let sync = sut.downstreamRequestSync!
        XCTAssertFalse(sync.hasOutstandingItems)
        syncMOC.saveOrRollback()

        // WHEN
        uiMOC.performGroupedBlock {
            (self.uiMOC.object(with: team.objectID) as? Team)?.requestImage()
        }
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))

        // THEN
        XCTAssert(sync.hasOutstandingItems)
    }

    func testThatItCreatesRequestForCorrectAssetIdentifierForImage() {
        // GIVEN
        let team = createMockTeam()
        syncMOC.saveOrRollback()

        // WHEN
        uiMOC.performGroupedBlock {
            (self.uiMOC.object(with: team.objectID) as? Team)?.requestImage()
        }
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))

        // THEN
        let request = sut.downstreamRequestSync.nextRequest()
        XCTAssertNotNil(request)
        XCTAssertEqual(request?.path, "/assets/v3/\(pictureAssetId)")
        XCTAssertEqual(request?.method, .methodGET)
    }

    func testThatItUpdatesCorrectUserImageDataForImage() {
        // GIVEN
        let team = createMockTeam()

        let imageData = "image".data(using: .utf8)!
        let sync = sut.downstreamRequestSync!
        let response = ZMTransportResponse(imageData: imageData, httpStatus: 200, transportSessionError: nil, headers: nil)

        // WHEN
        self.sut.update(team, with: response, downstreamSync: sync)

        // THEN
        XCTAssertEqual(team.imageData, imageData)
    }

    func testThatItDeletesPreviewProfileAssetIdentifierWhenReceivingAPermanentErrorForImage() {
        // Given
        let team = createMockTeam()
        syncMOC.saveOrRollback()

        // When
        uiMOC.performGroupedBlock {
            (self.uiMOC.object(with: team.objectID) as? Team)?.requestImage()
        }
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        guard let request = sut.nextRequestIfAllowed() else { return XCTFail("nil request generated") }
        XCTAssertEqual(request.path, "/assets/v3/\(pictureAssetId)")
        XCTAssertEqual(request.method, .methodGET)

        // Given
        let response = ZMTransportResponse(payload: nil, httpStatus: 404, transportSessionError: nil)
        request.complete(with: response)

        // THEN
        team.requestImage()
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        XCTAssertNil(team.pictureAssetId)
        XCTAssertNil(sut.nextRequestIfAllowed())
    }
}
