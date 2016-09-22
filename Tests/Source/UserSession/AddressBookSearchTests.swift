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
@testable import zmessaging

class AddressBookSearchTests : MessagingTest {
    
    var sut : zmessaging.AddressBookSearch!
    var addressBook : AddressBookContactsFake!
    
    override func setUp() {
        super.setUp()
        self.addressBook = AddressBookContactsFake()
        self.sut = zmessaging.AddressBookSearch(addressBook: self.addressBook.addressBook())
    }
    
    override func tearDown() {
        self.sut = nil
        self.addressBook = nil
        super.tearDown()
    }
}

// MARK: - Contact for user
extension AddressBookSearchTests {

    func testThatContactForUserMatchesOnPhoneNumber() {
        
        // given
        let user = ZMUser.insertNewObject(in: self.uiMOC)
        user.phoneNumber = "+155505144"
        addressBook.contacts = [
            AddressBookContactsFake.Contact(firstName: "Olivia", emailAddresses: ["oli@example.com"], phoneNumbers: [user.phoneNumber])
        ]
        
        // when
        let contact = sut.contactForUser(user)
        
        // then
        XCTAssertNotNil(contact)
        if let contact = contact {
            XCTAssertEqual(contact.emailAddresses, addressBook.contacts[0].emailAddresses)
            XCTAssertEqual(contact.firstName, addressBook.contacts[0].firstName)
            XCTAssertEqual(contact.phoneNumbers, addressBook.contacts[0].phoneNumbers)
        } else {
            XCTFail()
        }
    }
    
    func testThatContactForUserMatchesOnEmail() {
        
        // given
        let user = ZMUser.insertNewObject(in: self.uiMOC)
        user.emailAddress = "oli@example.com"
        addressBook.contacts = [
            AddressBookContactsFake.Contact(firstName: "Olivia", emailAddresses: [user.emailAddress], phoneNumbers: [])
        ]
        
        // when
        let contact = sut.contactForUser(user)
        
        // then
        XCTAssertNotNil(contact)
        if let contact = contact {
            XCTAssertEqual(contact.emailAddresses, addressBook.contacts[0].emailAddresses)
            XCTAssertEqual(contact.firstName, addressBook.contacts[0].firstName)
            XCTAssertEqual(contact.phoneNumbers, addressBook.contacts[0].phoneNumbers)
        } else {
            XCTFail()
        }
    }
    
    func testThatContactForUserDoesNotMatchIfThereIsNoAddressBookAccess() {
        // given
        let user = ZMUser.insertNewObject(in: self.uiMOC)
        user.phoneNumber = "+155505144"
        user.emailAddress = "oli@example.com"
        addressBook.contacts = [
            AddressBookContactsFake.Contact(firstName: "Olivia", emailAddresses: [user.emailAddress], phoneNumbers: [user.phoneNumber])
        ]
        self.sut = zmessaging.AddressBookSearch(addressBook: nil)
        
        // when
        let contact = sut.contactForUser(user)
        
        // then
        XCTAssertNil(contact)
    }
}

// MARK: - Search query
extension AddressBookSearchTests {
    
    func testThatItSearchesByNameWithMatch() {
        
        // given
        addressBook.contacts = [
            AddressBookContactsFake.Contact(firstName: "Olivia", emailAddresses: ["oli@example.com"], phoneNumbers: []),
            AddressBookContactsFake.Contact(firstName: "Ada", emailAddresses: [], phoneNumbers: ["+155505012"])
        ]
        
        // when
        let result = Array(sut.contactsMatchingQuery("ivi"))
        
        // then
        XCTAssertEqual(result.count, 1)
        guard result.count == 1 else { return }
        XCTAssertEqual(result[0].emailAddresses, ["oli@example.com"])
    }
    
    func testThatItSearchesByNameWithNoMatch() {
        
        // given
        addressBook.contacts = [
            AddressBookContactsFake.Contact(firstName: "Olivia", emailAddresses: ["oli@example.com"], phoneNumbers: []),
            AddressBookContactsFake.Contact(firstName: "Ada", emailAddresses: [], phoneNumbers: ["+155505012"])
        ]
        
        // when
        let result = Array(sut.contactsMatchingQuery("Nadia"))
        
        // then
        XCTAssertEqual(result.count, 0)
    }
    
    func testThatItSearchesByNameWithMatchCaseInsensitive() {
        
        // given
        addressBook.contacts = [
            AddressBookContactsFake.Contact(firstName: "Olivia", emailAddresses: ["oli@example.com"], phoneNumbers: []),
            AddressBookContactsFake.Contact(firstName: "Ada", emailAddresses: [], phoneNumbers: ["+155505012"])
        ]
        
        // when
        let result = Array(sut.contactsMatchingQuery("oL"))
        
        // then
        XCTAssertEqual(result.count, 1)
        guard result.count == 1 else { return }
        XCTAssertEqual(result[0].emailAddresses, ["oli@example.com"])
    }
    
    func testThatItSearchesByNameWithMatchDiacritics() {
        
        // given
        addressBook.contacts = [
            AddressBookContactsFake.Contact(firstName: "Françoise", emailAddresses: [], phoneNumbers: ["+155505012"]),
            AddressBookContactsFake.Contact(firstName: "Håkon", emailAddresses: ["oli@example.com"], phoneNumbers: [])
        ]
        
        // when
        let result = Array(sut.contactsMatchingQuery("ak"))
        
        // then
        XCTAssertEqual(result.count, 1)
        guard result.count == 1 else { return }
        XCTAssertEqual(result[0].emailAddresses, ["oli@example.com"])
    }
    
    func testThatItSearchesByNameWithInfiniteMatches() {
        
        // given
        addressBook.createInfiniteContacts = true // "Johnny Infinite"
        
        // when
        let result = Array(sut.contactsMatchingQuery("finite"))
        
        // then
        XCTAssertEqual(result.count, 3000)
    }
}

// MARK: - Matching contacts
extension AddressBookSearchTests {
    
    func testThatItMatchesUserWithContacts() {
        // given
        addressBook.contacts = [
            AddressBookContactsFake.Contact(firstName: "Olivia", emailAddresses: ["oli@example.com"], phoneNumbers: []),
            AddressBookContactsFake.Contact(firstName: "Ada", emailAddresses: [], phoneNumbers: ["+155505012"]),
            AddressBookContactsFake.Contact(firstName: "Håkon", emailAddresses: ["hak@example.com"], phoneNumbers: []),
            AddressBookContactsFake.Contact(firstName: "Françoise", emailAddresses: [], phoneNumbers: ["+155505011"])
        ]
       
        let user1 = ZMUser.insertNewObject(in: self.uiMOC)
        user1.emailAddress = "oli@example.com"
        let user2 = ZMUser.insertNewObject(in: self.uiMOC)
        user2.phoneNumber = "+155505012"
        
        // when
        let result = sut.matchInAddressBook([user1, user2])
        
        // then
        XCTAssertEqual(result.count, 4)
        guard result.count == 4 else { return }
        XCTAssertEqual(result[0].user, user1)
        if let contact = result[0].contact {
            XCTAssertEqual(contact.emailAddresses, [user1.emailAddress])
        }
        XCTAssertEqual(result[1].user, user2)
        if let contact = result[1].contact {
            XCTAssertEqual(contact.phoneNumbers, [user2.phoneNumber])
        }
        XCTAssertNil(result[2].user)
        if let contact = result[2].contact {
            XCTAssertEqual(contact.emailAddresses, addressBook.contacts[2].emailAddresses)
        }
        XCTAssertNil(result[3].user)
        if let contact = result[3].contact {
            XCTAssertEqual(contact.phoneNumbers, addressBook.contacts[3].phoneNumbers)
        }
    }
    
    func testThatItReturnsNoContactIfUserDidNotMatch() {
        
        // given
        let user1 = ZMUser.insertNewObject(in: self.uiMOC)
        user1.emailAddress = "oli@example.com"
        let user2 = ZMUser.insertNewObject(in: self.uiMOC)
        user2.phoneNumber = "+155505012"

        // when
        let result = sut.matchInAddressBook([user1, user2])
        
        // then
        XCTAssertEqual(result.count, 2)
        guard result.count == 2 else { return }
        
        let users = Set(result.flatMap { $0.user })
        XCTAssertEqual(users, Set([user1, user2]))
        XCTAssertTrue(result.flatMap { $0.contact }.isEmpty)
    }
    
    func testThatItMatchesUserWithInfiniteContacts() {
        // given
        addressBook.createInfiniteContacts = true
        
        let user1 = ZMUser.insertNewObject(in: self.uiMOC)
        user1.emailAddress = "oli@example.com"
        let user2 = ZMUser.insertNewObject(in: self.uiMOC)
        user2.phoneNumber = "+155505012"
        
        // when
        let result = sut.matchInAddressBook([user1, user2])
        
        // then
        XCTAssertEqual(result.count, 3002) // the fact that it gets here without endless loop is a success
    }
    
}
