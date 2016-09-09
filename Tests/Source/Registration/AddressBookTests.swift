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
import AddressBook
@testable import zmessaging

class AddressBookTests : XCTestCase {
    
    private var addressBookFake : AddressBookContactsFake!
    
    override func setUp() {
        self.addressBookFake = AddressBookContactsFake()
        super.setUp()
    }
    
    override func tearDown() {
        self.addressBookFake = nil
    }
}

// MARK: - Access to AB
extension AddressBookTests {
    
    func testThatItInitializesIfItHasAccessToAB() {
        
        // given
        let sut = self.addressBookFake.addressBook()

        // then
        XCTAssertNotNil(sut)
    }

    func testThatItDoesNotInitializeIfItHasNoAccessToAB() {
        
        // given
        let sut = zmessaging.AddressBook(allPeopleClosure: { _ in return self.addressBookFake.peopleGenerator },
                                         addressBookAccessCheck: { return false },
                                         numberOfPeopleClosure: { _ in return self.addressBookFake.peopleCount })
        
        // then
        XCTAssertNil(sut)
    }
    
    func testThatItReturnsNumberOfContactsEvenIfTheyHaveNoEmailNorPhone() {
        
        // given
        self.addressBookFake.contacts = [
            AddressBookContactsFake.Contact(firstName: "Olaf", emailAddresses: ["olaf@example.com"], phoneNumbers: ["+15550100"]),
            AddressBookContactsFake.Contact(firstName: "สยาม", emailAddresses: [], phoneNumbers: []),
        ]
        let sut = self.addressBookFake.addressBook()
        
        // when
        let number = sut.numberOfContacts
        
        // then
        XCTAssertEqual(number, 2)
    }
    
    func testThatItReturnsAllContactsWhenTheyHaveValidEmailAndPhoneNumbers() {
        
        // given
        self.addressBookFake.contacts = [
            AddressBookContactsFake.Contact(firstName: "Olaf", emailAddresses: ["olaf@example.com", "janet@example.com"], phoneNumbers: ["+15550100"]),
            AddressBookContactsFake.Contact(firstName: "สยาม", emailAddresses: ["siam@example.com"], phoneNumbers: ["+15550101", "+15550102"]),
        ]
        let sut = self.addressBookFake.addressBook()
        
        // when
        let contacts = Array(sut.iterate())
        
        // then
        XCTAssertEqual(contacts.count, 2)
        for i in 0..<self.addressBookFake.contacts.count {
            XCTAssertEqual(contacts[i].emailAddresses, self.addressBookFake.contacts[i].emailAddresses)
            XCTAssertEqual(contacts[i].phoneNumbers, self.addressBookFake.contacts[i].phoneNumbers)
        }
    }
    
    func testThatItReturnsAllContactsWhenTheyHaveValidEmailOrPhoneNumbers() {
        
        // given
        self.addressBookFake.contacts = [
            AddressBookContactsFake.Contact(firstName: "Olaf", emailAddresses: ["olaf@example.com"], phoneNumbers: []),
            AddressBookContactsFake.Contact(firstName: "สยาม", emailAddresses: [], phoneNumbers: ["+15550101"]),
        ]
        let sut = self.addressBookFake.addressBook()
        
        // when
        let contacts = Array(sut.iterate())
        
        // then
        XCTAssertEqual(contacts.count, 2)
        for i in 0..<self.addressBookFake.contacts.count {
            XCTAssertEqual(contacts[i].emailAddresses, self.addressBookFake.contacts[i].emailAddresses)
            XCTAssertEqual(contacts[i].phoneNumbers, self.addressBookFake.contacts[i].phoneNumbers)
        }
    }
    
    func testThatItFilterlContactsThatHaveNoEmailNorPhone() {
        
        // given
        self.addressBookFake.contacts = [
            AddressBookContactsFake.Contact(firstName: "Olaf", emailAddresses: ["olaf@example.com"], phoneNumbers: ["+15550100"]),
            AddressBookContactsFake.Contact(firstName: "สยาม", emailAddresses: [], phoneNumbers: []),
        ]
        let sut = self.addressBookFake.addressBook()
        
        // when
        let contacts = Array(sut.iterate())
        
        // then
        XCTAssertEqual(contacts.count, 1)
        XCTAssertEqual(contacts[0].emailAddresses, self.addressBookFake.contacts[0].emailAddresses)
    }
}

// MARK: - Validation/normalization
extension AddressBookTests {

    func testThatItFilterlContactsThatHaveAnInvalidPhoneAndNoEmail() {
        
        // given
        self.addressBookFake.contacts = [
            AddressBookContactsFake.Contact(firstName: "Olaf", emailAddresses: [], phoneNumbers: ["aabbccdd"]),
        ]
        let sut = self.addressBookFake.addressBook()
        
        // when
        let contacts = Array(sut.iterate())
        
        // then
        XCTAssertEqual(contacts.count, 0)
    }
    
    func testThatIgnoresInvalidPhones() {
        
        // given
        self.addressBookFake.contacts = [
            AddressBookContactsFake.Contact(firstName: "Olaf", emailAddresses: ["janet@example.com"], phoneNumbers: ["aabbccdd"]),
        ]
        let sut = self.addressBookFake.addressBook()
        
        // when
        let contacts = Array(sut.iterate())
        
        // then
        XCTAssertEqual(contacts.count, 1)
        XCTAssertEqual(contacts[0].emailAddresses, self.addressBookFake.contacts[0].emailAddresses)
        XCTAssertEqual(contacts[0].phoneNumbers, [])
    }
    
    func testThatItFilterlContactsThatHaveNoPhoneAndInvalidEmail() {
        
        // given
        self.addressBookFake.contacts = [
            AddressBookContactsFake.Contact(firstName: "Olaf", emailAddresses: ["janet"], phoneNumbers: []),
        ]
        let sut = self.addressBookFake.addressBook()
        
        // when
        let contacts = Array(sut.iterate())
        
        // then
        XCTAssertEqual(contacts.count, 0)
    }
    
    func testThatIgnoresInvalidEmails() {
        
        // given
        self.addressBookFake.contacts = [
            AddressBookContactsFake.Contact(firstName: "Olaf", emailAddresses: ["janet"], phoneNumbers: ["+15550103"]),
        ]
        let sut = self.addressBookFake.addressBook()
        
        // when
        let contacts = Array(sut.iterate())
        
        // then
        XCTAssertEqual(contacts.count, 1)
        XCTAssertEqual(contacts[0].emailAddresses, [])
        XCTAssertEqual(contacts[0].phoneNumbers, self.addressBookFake.contacts[0].phoneNumbers)
    }
    
    func testThatItNormalizesPhoneNumbers() {
        
        // given
        self.addressBookFake.contacts = [
            AddressBookContactsFake.Contact(firstName: "Olaf", emailAddresses: [], phoneNumbers: ["+1 (555) 0103"]),
        ]
        let sut = self.addressBookFake.addressBook()
        
        // when
        let contacts = Array(sut.iterate())
        
        // then
        XCTAssertEqual(contacts.count, 1)
        XCTAssertEqual(contacts[0].phoneNumbers, ["+15550103"])
    }
    
    func testThatItNormalizesEmails() {
        
        // given
        self.addressBookFake.contacts = [
            AddressBookContactsFake.Contact(firstName: "Olaf", emailAddresses: ["Olaf Karlsson <janet+1@example.com>"], phoneNumbers: []),
        ]
        let sut = self.addressBookFake.addressBook()
        
        // when
        let contacts = Array(sut.iterate())
        
        // then
        XCTAssertEqual(contacts.count, 1)
        XCTAssertEqual(contacts[0].emailAddresses, ["janet+1@example.com"])
    }
    
    func testThatItDoesNotIgnoresPhonesWithPlusZero() {
        
        // given
        self.addressBookFake.contacts = [
            AddressBookContactsFake.Contact(firstName: "Olaf", emailAddresses: [], phoneNumbers: ["+012345678"]),
        ]
        let sut = self.addressBookFake.addressBook()
        
        // when
        let contacts = Array(sut.iterate())
        
        // then
        XCTAssertEqual(contacts.count, 1)
        XCTAssertEqual(contacts[0].phoneNumbers, ["+012345678"])
    }
}

// MARK: - Encoding
extension AddressBookTests {
    
    func testThatItEncodesUsers() {
        
        // given
        self.addressBookFake.contacts = [
            AddressBookContactsFake.Contact(firstName: "Olaf", emailAddresses: ["olaf@example.com"], phoneNumbers: ["+15550101"]),
            AddressBookContactsFake.Contact(firstName: "สยาม", emailAddresses: [], phoneNumbers: ["+15550100"]),
            AddressBookContactsFake.Contact(firstName: "Hadiya", emailAddresses: [], phoneNumbers: ["+15550102"])
            
        ]
        let queue = NSManagedObjectContext(concurrencyType: .PrivateQueueConcurrencyType)
        queue.createDispatchGroups()
        let sut = self.addressBookFake.addressBook()
        let expectation = self.expectationWithDescription("Callback invoked")
        
        // when
        sut.encodeWithCompletionHandler(queue, startingContactIndex: 0, maxNumberOfContacts: 100) { chunk in
            
            // then
            if let chunk = chunk {
                XCTAssertEqual(chunk.numberOfTotalContacts, 3)
                XCTAssertEqual(chunk.includedContacts, UInt(0)..<UInt(3))
                XCTAssertEqual(chunk.otherContactsHashes, [
                        ["BSdmiT9F5EtQrsfcGm+VC7Ofb0ZRREtCGCFw4TCimqk=",
                            "f9KRVqKI/n1886fb6FnP4oIORkG5S2HO0BoCYOxLFaA="],
                        ["YCzX+75BaI4tkCJLysNi2y8f8uK6dIfYWFyc4ibLbQA="],
                        ["iJXG3rJ3vc8rrh7EgHzbWPZsWOHFJ7mYv/MD6DlY154="]
                    ])
            } else {
                XCTFail()
            }
            expectation.fulfill()
        }
        
        self.waitForExpectationsWithTimeout(0.5) { error in
            XCTAssertNil(error)
        }
    }
    
    func testThatItCallsCompletionHandlerWithNilIfNoContacts() {
        
        // given
        self.addressBookFake.contacts = []
        let queue = NSManagedObjectContext(concurrencyType: .PrivateQueueConcurrencyType)
        queue.createDispatchGroups()
        let sut = self.addressBookFake.addressBook()
        let expectation = self.expectationWithDescription("Callback invoked")
        
        // when
        sut.encodeWithCompletionHandler(queue, startingContactIndex: 0, maxNumberOfContacts: 100) { chunk in
            
            // then
            XCTAssertNil(chunk)
            expectation.fulfill()
        }
        
        self.waitForExpectationsWithTimeout(0.5) { error in
            XCTAssertNil(error)
        }
    }
    
    func testThatItEncodesOnlyAMaximumNumberOfUsers() {
        
        // given
        self.addressBookFake.contacts = [
            AddressBookContactsFake.Contact(firstName: "Olaf", emailAddresses: ["olaf@example.com"], phoneNumbers: ["+15550101"]),
            AddressBookContactsFake.Contact(firstName: "สยาม", emailAddresses: [], phoneNumbers: ["+15550100"]),
            AddressBookContactsFake.Contact(firstName: "Hadiya", emailAddresses: [], phoneNumbers: ["+15550102"])
            
        ]
        let queue = NSManagedObjectContext(concurrencyType: .PrivateQueueConcurrencyType)
        queue.createDispatchGroups()
        let sut = self.addressBookFake.addressBook()
        let expectation = self.expectationWithDescription("Callback invoked")
        
        // when
        sut.encodeWithCompletionHandler(queue, startingContactIndex: 0, maxNumberOfContacts: 2) { chunk in
            
            // then
            if let chunk = chunk {
                XCTAssertEqual(chunk.numberOfTotalContacts, 3)
                XCTAssertEqual(chunk.includedContacts, UInt(0)..<UInt(2))
                XCTAssertEqual(chunk.otherContactsHashes, [
                    ["BSdmiT9F5EtQrsfcGm+VC7Ofb0ZRREtCGCFw4TCimqk=",
                        "f9KRVqKI/n1886fb6FnP4oIORkG5S2HO0BoCYOxLFaA="],
                    ["YCzX+75BaI4tkCJLysNi2y8f8uK6dIfYWFyc4ibLbQA="]
                    ])
            } else {
                XCTFail()
            }
            expectation.fulfill()
        }
        
        self.waitForExpectationsWithTimeout(0.5) { error in
            XCTAssertNil(error)
        }
    }
    
    func testThatItEncodesOnlyTheRequestedUsers() {
        
        // given
        self.addressBookFake.contacts = [
            AddressBookContactsFake.Contact(firstName: "Olaf", emailAddresses: ["olaf@example.com"], phoneNumbers: ["+15550101"]),
            AddressBookContactsFake.Contact(firstName: "สยาม", emailAddresses: [], phoneNumbers: ["+15550100"]),
            AddressBookContactsFake.Contact(firstName: "Hadiya", emailAddresses: [], phoneNumbers: ["+15550102"]),
            AddressBookContactsFake.Contact(firstName: " أميرة", emailAddresses: ["a@example.com"], phoneNumbers: [])
        ]
        
        let queue = NSManagedObjectContext(concurrencyType: .PrivateQueueConcurrencyType)
        queue.createDispatchGroups()
        let sut = self.addressBookFake.addressBook()
        let expectation = self.expectationWithDescription("Callback invoked")
        
        // when
        sut.encodeWithCompletionHandler(queue, startingContactIndex: 1, maxNumberOfContacts: 2) { chunk in
            
            // then
            if let chunk = chunk {
                XCTAssertEqual(chunk.numberOfTotalContacts, 4)
                XCTAssertEqual(chunk.includedContacts, UInt(1)..<UInt(3))
                XCTAssertEqual(chunk.otherContactsHashes, [
                    ["YCzX+75BaI4tkCJLysNi2y8f8uK6dIfYWFyc4ibLbQA="],
                    ["iJXG3rJ3vc8rrh7EgHzbWPZsWOHFJ7mYv/MD6DlY154="]
                    ])
            } else {
                XCTFail()
            }
            expectation.fulfill()
        }
        
        self.waitForExpectationsWithTimeout(0.5) { error in
            XCTAssertNil(error)
        }
    }
    
    func testThatItEncodesAsManyContactsAsItCanIfAskedToEncodeTooMany() {
        
        // given
        self.addressBookFake.contacts = [
            AddressBookContactsFake.Contact(firstName: "Olaf", emailAddresses: ["olaf@example.com"], phoneNumbers: ["+15550101"]),
            AddressBookContactsFake.Contact(firstName: " أميرة", emailAddresses: ["a@example.com"], phoneNumbers: []),
            AddressBookContactsFake.Contact(firstName: "สยาม", emailAddresses: [], phoneNumbers: ["+15550100"]),
            AddressBookContactsFake.Contact(firstName: "Hadiya", emailAddresses: [], phoneNumbers: ["+15550102"])
        ]
        
        let queue = NSManagedObjectContext(concurrencyType: .PrivateQueueConcurrencyType)
        queue.createDispatchGroups()
        let sut = self.addressBookFake.addressBook()
        let expectation = self.expectationWithDescription("Callback invoked")
        
        // when
        sut.encodeWithCompletionHandler(queue, startingContactIndex: 2, maxNumberOfContacts: 20) { chunk in
            
            // then
            if let chunk = chunk {
                XCTAssertEqual(chunk.numberOfTotalContacts, 4)
                XCTAssertEqual(chunk.includedContacts, UInt(2)..<UInt(4))
                XCTAssertEqual(chunk.otherContactsHashes, [
                    ["YCzX+75BaI4tkCJLysNi2y8f8uK6dIfYWFyc4ibLbQA="],
                    ["iJXG3rJ3vc8rrh7EgHzbWPZsWOHFJ7mYv/MD6DlY154="]
                    ])
            } else {
                XCTFail()
            }
            expectation.fulfill()
        }
        
        self.waitForExpectationsWithTimeout(0.5) { error in
            XCTAssertNil(error)
        }
    }
    
    func testThatItEncodesNoContactIfAskedToEncodePastTheLastContact() {
        
        // given
        self.addressBookFake.contacts = [
            AddressBookContactsFake.Contact(firstName: "Olaf", emailAddresses: ["olaf@example.com"], phoneNumbers: ["+15550101"]),
            AddressBookContactsFake.Contact(firstName: " أميرة", emailAddresses: ["a@example.com"], phoneNumbers: []),
            AddressBookContactsFake.Contact(firstName: "สยาม", emailAddresses: [], phoneNumbers: ["+15550100"]),
        ]
        
        let queue = NSManagedObjectContext(concurrencyType: .PrivateQueueConcurrencyType)
        queue.createDispatchGroups()
        let sut = self.addressBookFake.addressBook()
        let expectation = self.expectationWithDescription("Callback invoked")
        
        // when
        sut.encodeWithCompletionHandler(queue, startingContactIndex: 20, maxNumberOfContacts: 20) { chunk in
            
            // then
            if let chunk = chunk {
                XCTAssertEqual(chunk.numberOfTotalContacts, 3)
                XCTAssertEqual(chunk.includedContacts, UInt(20)..<UInt(20))
                XCTAssertEqual(chunk.otherContactsHashes, [])
            } else {
                XCTFail()
            }
            expectation.fulfill()
        }
        
        self.waitForExpectationsWithTimeout(0.5) { error in
            XCTAssertNil(error)
        }
    }
    
    func testThatItEncodesTheSameAddressBookInTheSameWay() {
        
        // given
        self.addressBookFake.contacts = [
            AddressBookContactsFake.Contact(firstName: "Olaf", emailAddresses: ["olaf@example.com"], phoneNumbers: ["+15550101"]),
            AddressBookContactsFake.Contact(firstName: "สยาม", emailAddresses: [], phoneNumbers: ["+15550100"]),
            AddressBookContactsFake.Contact(firstName: "Hadiya", emailAddresses: [], phoneNumbers: ["+15550102"])
            
        ]
        let queue = NSManagedObjectContext(concurrencyType: .PrivateQueueConcurrencyType)
        queue.createDispatchGroups()
        let sut = self.addressBookFake.addressBook()
        let expectation1 = self.expectationWithDescription("Callback invoked once")
        
        var chunk1 : [[String]]? = nil
        var chunk2 : [[String]]? = nil
        
        // when
        sut.encodeWithCompletionHandler(queue, startingContactIndex: 0, maxNumberOfContacts: 100) { chunk in
            
            chunk1 = chunk?.otherContactsHashes
            expectation1.fulfill()
        }
        
        self.waitForExpectationsWithTimeout(0.5) { error in
            XCTAssertNil(error)
        }
        
        let expectation2 = self.expectationWithDescription("Callback invoked twice")
        sut.encodeWithCompletionHandler(queue, startingContactIndex: 0, maxNumberOfContacts: 100) { chunk in
            
            chunk2 = chunk?.otherContactsHashes
            expectation2.fulfill()
        }
        
        self.waitForExpectationsWithTimeout(0.5) { error in
            XCTAssertNil(error)
        }
        
        // then
        XCTAssertNotNil(chunk1)
        XCTAssertNotNil(chunk2)
        XCTAssertEqual(chunk1!, chunk2!)
    }
}
