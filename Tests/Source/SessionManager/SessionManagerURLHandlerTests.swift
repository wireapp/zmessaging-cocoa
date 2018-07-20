//
// Wire
// Copyright (C) 2018 Wire Swiss GmbH
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

class UserSessionSourceDummy: UserSessionSource {
    weak var activeUserSession: ZMUserSession? = nil
}

class OpenerDelegate: SessionManagerURLHandlerDelegate {
    var calls: [(URLAction, (Bool) -> Void)] = []
    func sessionManagerShouldExecuteURLAction(_ action: URLAction, callback: @escaping (Bool) -> Void) {
        calls.append((action, callback))
    }
}

final class SessionManagerURLHandlerTests: MessagingTest {
    override func setUp() {
        super.setUp()
        delegate = OpenerDelegate()
        userSessionSource = UserSessionSourceDummy()
        opener = SessionManagerURLHandler(userSessionSource: userSessionSource)
        opener.delegate = delegate
    }
    
    override func tearDown() {
        delegate = nil
        userSessionSource = nil
        opener = nil
        super.tearDown()
    }
    
    var delegate: OpenerDelegate!
    var userSessionSource: UserSessionSourceDummy!
    var opener: SessionManagerURLHandler!
    
    func testThatItIgnoresNonWireURL() {
        // when
        let canOpen = opener.openURL(URL(string: "https://google.com")!, options: [:])
        
        // then
        XCTAssertFalse(canOpen)
        XCTAssertEqual(delegate.calls.count, 0)
    }
    
    func testThatItSavesCallWhenUserSessionNotAvailable() {
        // when
        let canOpen = opener.openURL(URL(string: "wire://connect?service=2e1863a6-4a12-11e8-842f-0ed5f89f718b&provider=3879b1ec-4a12-11e8-842f-0ed5f89f718b")!, options: [:])
        
        // then
        XCTAssertTrue(canOpen)
        XCTAssertEqual(delegate.calls.count, 0)
    }
    
    func testThatItAsksDelegateIfURLMustBeOpened() {
        // given
        userSessionSource.activeUserSession = self.mockUserSession
        
        // when
        let canOpen = opener.openURL(URL(string: "wire://connect?service=2e1863a6-4a12-11e8-842f-0ed5f89f718b&provider=3879b1ec-4a12-11e8-842f-0ed5f89f718b")!, options: [:])
        
        // then
        let expectedUserData = ServiceUserData(provider: UUID(uuidString: "3879b1ec-4a12-11e8-842f-0ed5f89f718b")!,
                                           service: UUID(uuidString: "2e1863a6-4a12-11e8-842f-0ed5f89f718b")!)

        XCTAssertTrue(canOpen)
        XCTAssertEqual(delegate.calls.count, 1)
        XCTAssertEqual(delegate.calls[0].0, .connectBot(serviceUser: expectedUserData))
    }
    
    func testThatItSavesCallWhenUserSessionNotAvailable_AndCallsItLater() {
        // when
        let canOpen = opener.openURL(URL(string: "wire://connect?service=2e1863a6-4a12-11e8-842f-0ed5f89f718b&provider=3879b1ec-4a12-11e8-842f-0ed5f89f718b")!, options: [:])
        
        // then
        XCTAssertTrue(canOpen)
        XCTAssertEqual(delegate.calls.count, 0)
        
        // and when
        opener.sessionManagerActivated(userSession: self.mockUserSession)
        
        // then
        let expectedUserData = ServiceUserData(provider: UUID(uuidString: "3879b1ec-4a12-11e8-842f-0ed5f89f718b")!,
                                               service: UUID(uuidString: "2e1863a6-4a12-11e8-842f-0ed5f89f718b")!)

        XCTAssertEqual(delegate.calls.count, 1)
        XCTAssertEqual(delegate.calls[0].0, .connectBot(serviceUser: expectedUserData))
    }
}
