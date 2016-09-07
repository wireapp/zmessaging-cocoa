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
    
    var addressBook : AddressBookContactsFake!
    
    override func setUp() {
        super.setUp()
        self.addressBook = AddressBookContactsFake()
        self.updateDisplayNameGeneratorWithUsers(self.allUsers)
        self.searchDirectory = ZMSearchDirectory(userSession: self.userSession)
        self.addressBook = AddressBookContactsFake()
        zmessaging.debug_searchResultAddressBookOverride = self.addressBook.addressBook()
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
        
        let expectation = self.expectationWithDescription("Observer called")
        let request = ZMSearchRequest()
        request.query = ""
        request.includeContacts = true
        
        let observer = SearchResultOberserverMock(callback: { result, token in
            XCTAssertNotNil(result)
            XCTAssertEqual(result?.usersInContacts.count, 2)
            XCTAssertNotNil(token)
            expectation.fulfill()
        })
        
        self.searchDirectory.addSearchResultObserver(observer)
        defer { self.searchDirectory.removeSearchResultObserver(observer) }
        
        // when
        let token = self.searchDirectory.performRequest(request)
        
        // then
        XCTAssertNotNil(token)
        XCTAssertTrue(self.waitForCustomExpectationsWithTimeout(0.5))
    }
    
    func testThatWeAreFetchingUsersContactAndAddressBook() {
        
        // given
        XCTAssertTrue(self.logInAndWaitForSyncToBeComplete())
        self.addressBook.contacts = [
            AddressBookContactsFake.Contact(firstName: "Mario", emailAddresses: ["mm@example.com"], phoneNumbers: [])
        ]
        let expectation = self.expectationWithDescription("Observer called")
        let request = ZMSearchRequest()
        request.query = ""
        request.includeContacts = true
        request.includeAddressBookContacts = true
        
        let observer = SearchResultOberserverMock(callback: { result, token in
            XCTAssertNotNil(result)
            XCTAssertEqual(result?.usersInContacts.count, self.connectedUsers.count + self.addressBook.contacts.count)
            XCTAssertNotNil(token)
            expectation.fulfill()
        })
        
        self.searchDirectory.addSearchResultObserver(observer)
        defer { self.searchDirectory.removeSearchResultObserver(observer) }
        
        // when
        let token = self.searchDirectory.performRequest(request)
        
        // then
        XCTAssertNotNil(token)
        XCTAssertTrue(self.waitForCustomExpectationsWithTimeout(0.5))
    }
    
    func testThatFetchingContactDoesntDuplicateWireAndAddressBookContact() {
        
        //given
        XCTAssertTrue(self.logInAndWaitForSyncToBeComplete())
        self.addressBook.contacts = [
            AddressBookContactsFake.Contact(firstName: self.user1.name, emailAddresses: [self.user1.email], phoneNumbers: []),
            AddressBookContactsFake.Contact(firstName: "Mario", emailAddresses: ["mm@example.com"], phoneNumbers: [])
        ]
        
        let expectation = self.expectationWithDescription("Observer called")
        let request = ZMSearchRequest()
        request.query = ""
        request.includeContacts = true
        request.includeAddressBookContacts = true
        
        let observer = SearchResultOberserverMock(callback: { result, token in
            XCTAssertNotNil(result)
            XCTAssertEqual(result?.usersInContacts.count, self.connectedUsers.count + self.addressBook.contacts.count - 1)
            XCTAssertNotNil(token)
            expectation.fulfill()
        })
        
        self.searchDirectory.addSearchResultObserver(observer)
        defer { self.searchDirectory.removeSearchResultObserver(observer) }
        
        // when
        let token = self.searchDirectory.performRequest(request)
        
        // then
        XCTAssertNotNil(token)
        XCTAssertTrue(self.waitForCustomExpectationsWithTimeout(0.5))
    }
}

// MARK: - Helpers
@objc class SearchResultOberserverMock : NSObject, ZMSearchResultObserver {
    
    private typealias ObserverCallback = (result: ZMSearchResult?, searchToken: ZMSearchToken?)->(Void)
    
    private let callback: ObserverCallback
    
    private init(callback: ObserverCallback) {
        self.callback = callback
    }
    
    func didReceiveSearchResult(result: ZMSearchResult!, forToken searchToken: ZMSearchToken!) {
        self.callback(result: result, searchToken: searchToken)
    }
    
}