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

    override func setUp() {
        super.setUp()
        self.mockApplicationStatus = MockApplicationStatus()

        self.mockApplicationStatus.mockSynchronizationState = .eventProcessing

        sut = TeamImageAssetUpdateStrategy(withManagedObjectContext: syncMOC,
                                           applicationStatus: mockApplicationStatus)

        ///TODO: cache for team image?
//        self.syncMOC.zm_userImageCache = UserImageLocalCache()
//        self.uiMOC.zm_userImageCache = self.syncMOC.zm_userImageCache
    }

    override func tearDown() {
        mockApplicationStatus = nil
        sut = nil
//        self.syncMOC.zm_userImageCache = nil
        super.tearDown()
    }

    func testThatItCreatesDownstreamRequestSyncs() {
        XCTAssertNotNil(sut.downstreamRequestSync)
    }

    func testThatItWhitelistsUserOnPreviewSyncForImageNotification() {
    }

    func testThatItCreatesRequestForCorrectAssetIdentifierForImage() {
    }

    func testThatItUpdatesCorrectUserImageDataForImage() {
    }

    func testThatItDeletesPreviewProfileAssetIdentifierWhenReceivingAPermanentErrorForImage() {
    }
}
