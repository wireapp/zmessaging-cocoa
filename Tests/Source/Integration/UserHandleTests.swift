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


import Foundation
import zmessaging
import ZMCMockTransport

class UserHandleTests : IntegrationTestBase {
    
    var userProfileStatusObserver : TestUserProfileUpdateObserver!
    
    var observerToken : AnyObject!
    
    override func setUp() {
        super.setUp()
        self.userProfileStatusObserver = TestUserProfileUpdateObserver()
        self.observerToken = self.userSession.userProfileUpdateStatus.add(observer: self.userProfileStatusObserver)
    }
    
    override func tearDown() {
        self.userSession.userProfileUpdateStatus.removeObserver(token: self.observerToken)
        self.observerToken = nil
        self.userProfileStatusObserver = nil
        super.tearDown()
    }
    
    func testThatItCanCheckThatAHandleIsAvailable() {
        
        // GIVEN
        let handle = "Oscar"
        XCTAssertTrue(logInAndWaitForSyncToBeComplete())
        
        // WHEN
        self.userSession.userProfileUpdateStatus.requestCheckHandleAvailability(handle: handle)
        
        // THEN
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        XCTAssertEqual(self.userProfileStatusObserver.invokedCallbacks.count, 1)
        guard let first = self.userProfileStatusObserver.invokedCallbacks.first else { return }
        switch first {
        case .didCheckAvailabilityOfHandle(let _handle, let available):
            XCTAssertEqual(handle, _handle)
            XCTAssertTrue(available)
        default:
            XCTFail()
        }
    }
    
    func testThatItCanCheckThatAHandleIsNotAvailable() {
        
        // GIVEN
        let handle = "Oscar"
        XCTAssertTrue(logInAndWaitForSyncToBeComplete())
        self.mockTransportSession.performRemoteChanges { (session) in
            self.user1.handle = handle
        }
        
        // WHEN
        self.userSession.userProfileUpdateStatus.requestCheckHandleAvailability(handle: handle)
        
        // THEN
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        XCTAssertEqual(self.userProfileStatusObserver.invokedCallbacks.count, 1)
        guard let first = self.userProfileStatusObserver.invokedCallbacks.first else { return }
        switch first {
        case .didCheckAvailabilityOfHandle(let _handle, let available):
            XCTAssertEqual(handle, _handle)
            XCTAssertFalse(available)
        default:
            XCTFail()
        }
    }
}
