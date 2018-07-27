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

class SearchDirectoryTests : MessagingTest {

    func testThatItEmptiesTheSearchUserCacheOnTeardown() {
        // given
        uiMOC.zm_searchUserCache = NSCache()
        let uuid = UUID.create()
        let sut = SearchDirectory(userSession: mockUserSession)
        _ = ZMSearchUser(contextProvider: mockUserSession, name: "John Doe", handle: "john", accentColor: .brightOrange, remoteIdentifier: uuid)
        XCTAssertNotNil(uiMOC.zm_searchUserCache?.object(forKey: uuid as NSUUID))
    
        // when
        sut.tearDown()
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))

        // then
        XCTAssertNil(uiMOC.zm_searchUserCache?.object(forKey: uuid as NSUUID))
    }
    
}
