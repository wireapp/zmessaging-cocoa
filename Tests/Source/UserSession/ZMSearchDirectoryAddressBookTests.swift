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
import XCTest
@testable import WireSyncEngine

class ZMSearchDirectoryAddressBookTests : MessagingTest {
    
    var sut : ZMSearchDirectory!
    
    override func setUp() {
        self.sut = ZMSearchDirectory(userSession: nil, search: nil)
        super.setUp()
    }
    
    override func tearDown() {
        sut.tearDown()
        assert(self.waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        super.tearDown()
    }
    
    func testThatItAddsNonLinkedAddressBookResultsToSearch() {
        // TODO MARCO
    }
    
    func testThatItDoesNotAddAddressBookResultsToSearchWhenAlreadyLinkedToFoundUser() {
        // TODO MARCO
    }
    
    func testThatItAddsAddressBookContactsResultsToSearchWhenNotLinkedToFoundUser() {
        // TODO MARCO
    }
    
    func testThatItAddsAddressBookNonContactsResultsToSearchWhenNotLinkedToFoundUser() {
        // TODO MARCO
    }
}
