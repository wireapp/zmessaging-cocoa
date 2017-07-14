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

import XCTest
import WireTesting

@testable import WireSyncEngine

class ZMUserSessionAuthenticationNotificationTests: ZMTBaseTest {
    
    
    func testThatRegistrationDidFailNotifiesTheAuthenticationObserver() {
        // given
        let error = NSError(domain: "foo", code: 201, userInfo: nil)
        let observer =  AuthenticationObserver()
        let expectation = self.expectation(description: "Observer notified")
        
        observer.onFailure = {
            expectation.fulfill()
        }
        
        // expect
        let token = ZMUserSessionAuthenticationNotification.addObserver(observer)
        XCTAssertNotNil(token)
        
        // when
        ZMUserSessionAuthenticationNotification.notifyAuthenticationDidFail(error)
        XCTAssert(waitForCustomExpectations(withTimeout: 0.5))
    }
    
    func testThatAuthenticationDidSucceedNotifiesTheAuthenticationObserver() {
        // given
        let observer =  AuthenticationObserver()
        let expectation = self.expectation(description: "Observer notified")
        
        observer.onSuccess = {
            expectation.fulfill()
        }
        
        // expect
        let token = ZMUserSessionAuthenticationNotification.addObserver(observer)
        XCTAssertNotNil(token)
        
        // when
        ZMUserSessionAuthenticationNotification.notifyAuthenticationDidSucceed()
        XCTAssert(waitForCustomExpectations(withTimeout: 0.5))
    }
    
}
