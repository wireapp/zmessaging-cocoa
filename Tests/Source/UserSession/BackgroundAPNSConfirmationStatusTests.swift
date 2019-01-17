//
// Wire
// Copyright (C) 2016 Wire Swiss GmbH
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
import WireTesting
import WireMockTransport

class BackgroundAPNSConfirmationStatusTests : MessagingTest {

    var sut : BackgroundAPNSConfirmationStatus!
    var activityManager : MockBackgroundActivityManager!

    override func setUp() {
        super.setUp()
        application.setBackground()
        activityManager = MockBackgroundActivityManager()
        BackgroundActivityFactory.shared.activityManager = activityManager
        sut = BackgroundAPNSConfirmationStatus(application: application, managedObjectContext: syncMOC)
    }
    
    override func tearDown() {
        activityManager.reset()
        activityManager = nil
        BackgroundActivityFactory.shared.activityManager = nil
        sut.tearDown()
        sut = nil
        super.tearDown()
    }
    
    func testThat_CanSendMessage_IsSetToTrue_NewMessage() {
        // given
        let uuid = UUID.create()
        
        // when
        sut.needsToConfirmMessage(uuid)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertTrue(sut.needsToSyncMessages)
    }
    
    func testThat_CanSendMessage_IsSetToFalse_MessageConfirmed() {
        // given
        let uuid = UUID.create()
        sut.needsToConfirmMessage(uuid)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))

        // when
        sut.didConfirmMessage(uuid)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))

        // then
        XCTAssertFalse(sut.needsToSyncMessages)
    }
    
    func testThat_CanSendMessage_IsSetToTrue_OneMessageConfirmed_OneMessageNew() {
        // given
        let uuid1 = UUID.create()
        let uuid2 = UUID.create()

        sut.needsToConfirmMessage(uuid1)
        sut.needsToConfirmMessage(uuid2)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))

        // when
        sut.didConfirmMessage(uuid1)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))

        // then
        XCTAssertTrue(sut.needsToSyncMessages)
    }
    
    func testThat_CanSendMessage_IsSetToFalse_MessageTimedOut() {
        // given
        let uuid1 = UUID.create()
        
        sut.needsToConfirmMessage(uuid1)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))

        // when
        activityManager.triggerExpiration()
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertFalse(sut.needsToSyncMessages)
    }
    
    func testThatItExpiresMultipleMessages() {
        // given
        let uuid1 = UUID.create()
        let uuid2 = UUID.create()
        
        sut.needsToConfirmMessage(uuid1)
        sut.needsToConfirmMessage(uuid2)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))

        // when
        activityManager.triggerExpiration()
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertFalse(sut.needsToSyncMessages)
    }
}

