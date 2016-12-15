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
@testable import zmessaging

class InvitationsTests : IntegrationTestBase {
    
    var searchDirectory : ZMSearchDirectory!
    
    var addressBook : AddressBookFake!
    
    override func setUp() {
        super.setUp()
        self.addressBook = AddressBookFake()
        self.updateDisplayNameGenerator(withUsers: self.allUsers)
        self.searchDirectory = ZMSearchDirectory(userSession: self.userSession)
        zmessaging.debug_searchResultAddressBookOverride = self.addressBook
    }
    
    override func tearDown() {
        self.searchDirectory.tearDown()
        self.searchDirectory = nil
        zmessaging.debug_searchResultAddressBookOverride = nil
        super.tearDown()
    }
}

extension InvitationsTests {

    func testThatItFetchesUsersAndNotifies() {
        
        // given
        XCTAssertTrue(self.logInAndWaitForSyncToBeComplete())
        
        let expectation = self.expectation(description: "Observer called")
        let request = ZMSearchRequest()
        request.query = ""
        request.includeContacts = true
        
        let observer = SearchResultOberserverMock(callback: { result, token in
            XCTAssertNotNil(result)
            XCTAssertEqual(result?.usersInContacts.count, 2)
            XCTAssertNotNil(token)
            expectation.fulfill()
        })
        
        self.searchDirectory.add(observer)
        defer { self.searchDirectory.remove(observer) }
        
        // when
        let token = self.searchDirectory.perform(request)
        
        // then
        XCTAssertNotNil(token)
        XCTAssertTrue(self.waitForCustomExpectations(withTimeout: 0.5))
    }
}

// MARK: - Helpers
@objc class SearchResultOberserverMock : NSObject, ZMSearchResultObserver {
    
    fileprivate typealias ObserverCallback = (_ result: ZMSearchResult?, _ searchToken: ZMSearchToken?)->(Void)
    
    fileprivate let callback: ObserverCallback
    
    fileprivate init(callback: @escaping ObserverCallback) {
        self.callback = callback
    }
    
    func didReceive(_ result: ZMSearchResult!, for searchToken: ZMSearchToken!) {
        self.callback(result, searchToken)
    }
    
}
