//
//  AddressBookTests.swift
//  zmessaging-cocoa
//
//  Created by Marco Conti on 17/08/16.
//  Copyright © 2016 Zeta Project Gmbh. All rights reserved.
//

import Foundation
import AddressBook
@testable import zmessaging

class AddressBookTests : XCTestCase {
    
    private var iteratorFake : AddressBookContactsFake!
    
    override func setUp() {
        self.iteratorFake = AddressBookContactsFake()
        super.setUp()
    }
    
    override func tearDown() {
        self.iteratorFake = nil
    }
}

// MARK: - Access to AB
extension AddressBookTests {
    
    func testThatItInitializesIfItHasAccessToAB() {
        
        // given
        let sut = zmessaging.AddressBook(addressBookAccessCheck: { return true })

        // then
        XCTAssertNotNil(sut)
    }

    func testThatItDoesNotInitializeIfItHasNoAccessToAB() {
        
        // given
        let sut = zmessaging.AddressBook(addressBookAccessCheck: { return false })
        
        // then
        XCTAssertNil(sut)
    }
    
    func testThatItReturnsNumberOfContactsEvenIfTheyHaveNoEmailNorPhone() {
        
        // given
        self.iteratorFake.contacts = [
            Contact(firstName: "Olaf", emailAddresses: ["olaf@example.com"], phoneNumbers: ["+15550100"]),
            Contact(firstName: "สยาม", emailAddresses: [], phoneNumbers: []),
        ]
        let sut = zmessaging.AddressBook(allPeopleClosure: { _ in self.iteratorFake.allPeople },
                                         addressBookAccessCheck: { return true })!
        
        // when
        let number = sut.numberOfContacts
        
        // then
        XCTAssertEqual(number, 2)
    }
    
    func testThatItReturnsAllContactsWhenTheyHaveValidEmailAndPhoneNumbers() {
        
        // given
        self.iteratorFake.contacts = [
            Contact(firstName: "Olaf", emailAddresses: ["olaf@example.com", "janet@example.com"], phoneNumbers: ["+15550100"]),
            Contact(firstName: "สยาม", emailAddresses: ["siam@example.com"], phoneNumbers: ["+15550101", "+15550102"]),
        ]
        let sut = zmessaging.AddressBook(allPeopleClosure: { _ in self.iteratorFake.allPeople },
                                         addressBookAccessCheck: { return true })!
        
        // when
        let contacts = Array(sut.iterate())
        
        // then
        XCTAssertEqual(contacts.count, 2)
        for i in 0..<self.iteratorFake.contacts.count {
            XCTAssertEqual(contacts[i].emailAddresses, self.iteratorFake.contacts[i].emailAddresses)
            XCTAssertEqual(contacts[i].phoneNumbers, self.iteratorFake.contacts[i].phoneNumbers)
        }
    }
    
    func testThatItReturnsAllContactsWhenTheyHaveValidEmailOrPhoneNumbers() {
        
        // given
        self.iteratorFake.contacts = [
            Contact(firstName: "Olaf", emailAddresses: ["olaf@example.com"], phoneNumbers: []),
            Contact(firstName: "สยาม", emailAddresses: [], phoneNumbers: ["+15550101"]),
        ]
        let sut = zmessaging.AddressBook(allPeopleClosure: { _ in self.iteratorFake.allPeople },
                                         addressBookAccessCheck: { return true })!
        
        // when
        let contacts = Array(sut.iterate())
        
        // then
        XCTAssertEqual(contacts.count, 2)
        for i in 0..<self.iteratorFake.contacts.count {
            XCTAssertEqual(contacts[i].emailAddresses, self.iteratorFake.contacts[i].emailAddresses)
            XCTAssertEqual(contacts[i].phoneNumbers, self.iteratorFake.contacts[i].phoneNumbers)
        }
    }
    
    func testThatItFilterlContactsThatHaveNoEmailNorPhone() {
        
        // given
        self.iteratorFake.contacts = [
            Contact(firstName: "Olaf", emailAddresses: ["olaf@example.com"], phoneNumbers: ["+15550100"]),
            Contact(firstName: "สยาม", emailAddresses: [], phoneNumbers: []),
        ]
        let sut = zmessaging.AddressBook(allPeopleClosure: { _ in self.iteratorFake.allPeople },
                                         addressBookAccessCheck: { return true })!
        
        // when
        let contacts = Array(sut.iterate())
        
        // then
        XCTAssertEqual(contacts.count, 1)
        XCTAssertEqual(contacts[0].emailAddresses, self.iteratorFake.contacts[0].emailAddresses)
    }
}

// MARK: - Validation/normalization
extension AddressBookTests {

    func testThatItFilterlContactsThatHaveAnInvalidPhoneAndNoEmail() {
        
        // given
        self.iteratorFake.contacts = [
            Contact(firstName: "Olaf", emailAddresses: [], phoneNumbers: ["aabbccdd"]),
        ]
        let sut = zmessaging.AddressBook(allPeopleClosure: { _ in self.iteratorFake.allPeople },
                                         addressBookAccessCheck: { return true })!
        
        // when
        let contacts = Array(sut.iterate())
        
        // then
        XCTAssertEqual(contacts.count, 0)
    }
    
    func testThatIgnoresInvalidPhones() {
        
        // given
        self.iteratorFake.contacts = [
            Contact(firstName: "Olaf", emailAddresses: ["janet@example.com"], phoneNumbers: ["aabbccdd"]),
        ]
        let sut = zmessaging.AddressBook(allPeopleClosure: { _ in self.iteratorFake.allPeople },
                                         addressBookAccessCheck: { return true })!
        
        // when
        let contacts = Array(sut.iterate())
        
        // then
        XCTAssertEqual(contacts.count, 1)
        XCTAssertEqual(contacts[0].emailAddresses, self.iteratorFake.contacts[0].emailAddresses)
        XCTAssertEqual(contacts[0].phoneNumbers, [])
    }
    
    func testThatItFilterlContactsThatHaveNoPhoneAndInvalidEmail() {
        
        // given
        self.iteratorFake.contacts = [
            Contact(firstName: "Olaf", emailAddresses: ["janet"], phoneNumbers: []),
        ]
        let sut = zmessaging.AddressBook(allPeopleClosure: { _ in self.iteratorFake.allPeople },
                                         addressBookAccessCheck: { return true })!
        
        // when
        let contacts = Array(sut.iterate())
        
        // then
        XCTAssertEqual(contacts.count, 0)
    }
    
    func testThatIgnoresInvalidEmails() {
        
        // given
        self.iteratorFake.contacts = [
            Contact(firstName: "Olaf", emailAddresses: ["janet"], phoneNumbers: ["+15550103"]),
        ]
        let sut = zmessaging.AddressBook(allPeopleClosure: { _ in self.iteratorFake.allPeople },
                                         addressBookAccessCheck: { return true })!
        
        // when
        let contacts = Array(sut.iterate())
        
        // then
        XCTAssertEqual(contacts.count, 1)
        XCTAssertEqual(contacts[0].emailAddresses, [])
        XCTAssertEqual(contacts[0].phoneNumbers, self.iteratorFake.contacts[0].phoneNumbers)
    }
    
    func testThatItNormalizesPhoneNumbers() {
        
        // given
        self.iteratorFake.contacts = [
            Contact(firstName: "Olaf", emailAddresses: [], phoneNumbers: ["+1 (555) 0103"]),
        ]
        let sut = zmessaging.AddressBook(allPeopleClosure: { _ in self.iteratorFake.allPeople },
                                         addressBookAccessCheck: { return true })!
        
        // when
        let contacts = Array(sut.iterate())
        
        // then
        XCTAssertEqual(contacts.count, 1)
        XCTAssertEqual(contacts[0].phoneNumbers, ["+15550103"])
    }
    
    func testThatItNormalizesEmails() {
        
        // given
        self.iteratorFake.contacts = [
            Contact(firstName: "Olaf", emailAddresses: ["Olaf Karlsson <janet+1@example.com>"], phoneNumbers: []),
        ]
        let sut = zmessaging.AddressBook(allPeopleClosure: { _ in self.iteratorFake.allPeople },
                                         addressBookAccessCheck: { return true })!
        
        // when
        let contacts = Array(sut.iterate())
        
        // then
        XCTAssertEqual(contacts.count, 1)
        XCTAssertEqual(contacts[0].emailAddresses, ["janet+1@example.com"])
    }
    
    func testThatItDoesNotIgnoresPhonesWithPlusZero() {
        
        // given
        self.iteratorFake.contacts = [
            Contact(firstName: "Olaf", emailAddresses: [], phoneNumbers: ["+012345678"]),
        ]
        let sut = zmessaging.AddressBook(allPeopleClosure: { _ in self.iteratorFake.allPeople },
                                         addressBookAccessCheck: { return true })!
        
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
        self.iteratorFake.contacts = [
            Contact(firstName: "Olaf", emailAddresses: ["olaf@example.com"], phoneNumbers: ["+15550101"]),
            Contact(firstName: "สยาม", emailAddresses: [], phoneNumbers: ["+15550100"]),
            Contact(firstName: "Hadiya", emailAddresses: [], phoneNumbers: ["+15550102"])
            
        ]
        let queue = NSManagedObjectContext(concurrencyType: .PrivateQueueConcurrencyType)
        queue.createDispatchGroups()
        let sut = zmessaging.AddressBook(allPeopleClosure: { _ in self.iteratorFake.allPeople },
                                         addressBookAccessCheck: { return true })!
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
        self.iteratorFake.contacts = []
        let queue = NSManagedObjectContext(concurrencyType: .PrivateQueueConcurrencyType)
        queue.createDispatchGroups()
        let sut = zmessaging.AddressBook(allPeopleClosure: { _ in self.iteratorFake.allPeople },
                                         addressBookAccessCheck: { return true })!
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
        self.iteratorFake.contacts = [
            Contact(firstName: "Olaf", emailAddresses: ["olaf@example.com"], phoneNumbers: ["+15550101"]),
            Contact(firstName: "สยาม", emailAddresses: [], phoneNumbers: ["+15550100"]),
            Contact(firstName: "Hadiya", emailAddresses: [], phoneNumbers: ["+15550102"])
            
        ]
        let queue = NSManagedObjectContext(concurrencyType: .PrivateQueueConcurrencyType)
        queue.createDispatchGroups()
        let sut = zmessaging.AddressBook(allPeopleClosure: { _ in self.iteratorFake.allPeople },
                                         addressBookAccessCheck: { return true })!
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
        self.iteratorFake.contacts = [
            Contact(firstName: "Olaf", emailAddresses: ["olaf@example.com"], phoneNumbers: ["+15550101"]),
            Contact(firstName: "สยาม", emailAddresses: [], phoneNumbers: ["+15550100"]),
            Contact(firstName: "Hadiya", emailAddresses: [], phoneNumbers: ["+15550102"]),
            Contact(firstName: " أميرة", emailAddresses: ["a@example.com"], phoneNumbers: [])
        ]
        
        let queue = NSManagedObjectContext(concurrencyType: .PrivateQueueConcurrencyType)
        queue.createDispatchGroups()
        let sut = zmessaging.AddressBook(allPeopleClosure: { _ in self.iteratorFake.allPeople },
                                         addressBookAccessCheck: { return true })!
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
        self.iteratorFake.contacts = [
            Contact(firstName: "Olaf", emailAddresses: ["olaf@example.com"], phoneNumbers: ["+15550101"]),
            Contact(firstName: " أميرة", emailAddresses: ["a@example.com"], phoneNumbers: []),
            Contact(firstName: "สยาม", emailAddresses: [], phoneNumbers: ["+15550100"]),
            Contact(firstName: "Hadiya", emailAddresses: [], phoneNumbers: ["+15550102"])
        ]
        
        let queue = NSManagedObjectContext(concurrencyType: .PrivateQueueConcurrencyType)
        queue.createDispatchGroups()
        let sut = zmessaging.AddressBook(allPeopleClosure: { _ in self.iteratorFake.allPeople },
                                         addressBookAccessCheck: { return true })!
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
        self.iteratorFake.contacts = [
            Contact(firstName: "Olaf", emailAddresses: ["olaf@example.com"], phoneNumbers: ["+15550101"]),
            Contact(firstName: " أميرة", emailAddresses: ["a@example.com"], phoneNumbers: []),
            Contact(firstName: "สยาม", emailAddresses: [], phoneNumbers: ["+15550100"]),
        ]
        
        let queue = NSManagedObjectContext(concurrencyType: .PrivateQueueConcurrencyType)
        queue.createDispatchGroups()
        let sut = zmessaging.AddressBook(allPeopleClosure: { _ in self.iteratorFake.allPeople },
                                         addressBookAccessCheck: { return true })!
        let expectation = self.expectationWithDescription("Callback invoked")
        
        // when
        sut.encodeWithCompletionHandler(queue, startingContactIndex: 20, maxNumberOfContacts: 20) { chunk in
            
            // then
            XCTAssertNil(chunk)
            expectation.fulfill()
        }
        
        self.waitForExpectationsWithTimeout(0.5) { error in
            XCTAssertNil(error)
        }
    }
    
    func testThatItEncodesTheSameAddressBookInTheSameWay() {
        
        // given
        self.iteratorFake.contacts = [
            Contact(firstName: "Olaf", emailAddresses: ["olaf@example.com"], phoneNumbers: ["+15550101"]),
            Contact(firstName: "สยาม", emailAddresses: [], phoneNumbers: ["+15550100"]),
            Contact(firstName: "Hadiya", emailAddresses: [], phoneNumbers: ["+15550102"])
            
        ]
        let queue = NSManagedObjectContext(concurrencyType: .PrivateQueueConcurrencyType)
        queue.createDispatchGroups()
        let sut = zmessaging.AddressBook(allPeopleClosure: { _ in self.iteratorFake.allPeople },
                                         addressBookAccessCheck: { return true })!
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


// MARK: - Utility - faking contacts

struct Contact {
    
    let firstName : String
    let emailAddresses : [String]
    let phoneNumbers : [String]
}

private class AddressBookContactsFake {
    
    var contacts : [Contact] = []
    
    var allPeople : [ABRecordRef] {
        
        return self.contacts.map { contact in
            let record: ABRecordRef = ABPersonCreate().takeRetainedValue()
            ABRecordSetValue(record, kABPersonFirstNameProperty, contact.firstName, nil)
            if !contact.emailAddresses.isEmpty {
                let values: ABMutableMultiValue =
                    ABMultiValueCreateMutable(ABPropertyType(kABMultiStringPropertyType)).takeRetainedValue()
                contact.emailAddresses.forEach {
                    ABMultiValueAddValueAndLabel(values, $0, kABHomeLabel, nil)
                }
                ABRecordSetValue(record, kABPersonEmailProperty, values, nil)
            }
            if !contact.phoneNumbers.isEmpty {
                let values: ABMutableMultiValue =
                    ABMultiValueCreateMutable(ABPropertyType(kABMultiStringPropertyType)).takeRetainedValue()
                contact.phoneNumbers.forEach {
                    ABMultiValueAddValueAndLabel(values, $0, kABPersonPhoneMainLabel, nil)
                }
                ABRecordSetValue(record, kABPersonPhoneProperty, values, nil)
            }
            return record
        }
    }
}
