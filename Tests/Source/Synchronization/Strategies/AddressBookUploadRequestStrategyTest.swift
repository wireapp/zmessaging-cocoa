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
import WireLinkPreview
@testable import WireSyncEngine

class AddressBookUploadRequestStrategyTest : MessagingTest {
    
    var sut : WireSyncEngine.AddressBookUploadRequestStrategy!
    var mockApplicationStatus : MockApplicationStatus!
    var addressBook : AddressBookFake!
    
    override func setUp() {
        super.setUp()
        self.addressBook = AddressBookFake()
        
        let ab = self.addressBook // I don't want to capture self in closure later
        ab?.fillWithContacts(5)
        mockApplicationStatus = MockApplicationStatus()
        mockApplicationStatus.mockSynchronizationState = .eventProcessing
        self.sut = WireSyncEngine.AddressBookUploadRequestStrategy(managedObjectContext: self.syncMOC,
                                                               applicationStatus: mockApplicationStatus,
                                                               addressBookGenerator: { return ab })
    }
    
    override func tearDown() {
        self.mockApplicationStatus = nil
        self.sut = nil
        self.addressBook = nil
        super.tearDown()
    }
}

// MARK: - Upload requests
extension AddressBookUploadRequestStrategyTest {
    
    func testThatItReturnsNoRequestWhenTheABIsNotMarkedForUpload() {
        
        // given
        
        // when
        let request = sut.nextRequest() // this will return nil and start async processing
        
        // then
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        XCTAssertNil(request)
    }
    
    func testThatItReturnsARequestWhenTheABIsMarkedForUpload() {
        
        // given
        WireSyncEngine.AddressBook.markAddressBookAsNeedingToBeUploaded(self.syncMOC)
        
        // when
        let nilRequest = sut.nextRequest() // this will return nil and start async processing
        
        // then
        XCTAssertNil(nilRequest)
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        let request = sut.nextRequest()
        XCTAssertNotNil(request)
        if let request = request {
            XCTAssertEqual(request.path, "/onboarding/v3")
            XCTAssertEqual(request.method, ZMTransportRequestMethod.methodPOST)
            let expectedCards = self.addressBook.fakeContacts
                .map { ContactCard(id: $0.localIdentifier, hashes: $0.expectedHashes) }
                .sorted { $0.id < $1.id }
            
            if let parsedCards = request.payload?.parsedCards {
                XCTAssertEqual(parsedCards, expectedCards)
            } else {
                XCTFail("No parsed cards")
            }
            XCTAssertTrue(request.shouldCompress)
        }
    }
    
    func testThatItUploadsOnlyOnceWhenNotAskedAgain() {
        
        // given
        WireSyncEngine.AddressBook.markAddressBookAsNeedingToBeUploaded(self.syncMOC)
        _ = sut.nextRequest() // this will return nil and start async processing
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        let request = sut.nextRequest()
        request?.complete(with: ZMTransportResponse(payload: [] as ZMTransportData, httpStatus: 200, transportSessionError: nil))
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // when
        XCTAssertNil(sut.nextRequest())
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertNil(sut.nextRequest())
        
    }
    
    func testThatItReturnsNoRequestWhenTheABIsMarkedForUploadAndEmpty() {
        
        // given
        self.addressBook.fakeContacts = []
        WireSyncEngine.AddressBook.markAddressBookAsNeedingToBeUploaded(self.syncMOC)
        
        // when
        let nilRequest = sut.nextRequest() // this will return nil and start async processing
        
        // then
        XCTAssertNil(nilRequest)
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        let request = sut.nextRequest()
        XCTAssertNil(request)
    }
    
    func testThatOnlyOneRequestIsReturnedWhenCalledMultipleTimes() {
        
        // this test is tricky because I don't get a nextRequest immediately, but only after a while,
        // when creating the payload is done. I will call it multiple times and then one last time after waiting
        // (to be sure that async is done) and see that I got a non-nil only once.
        
        // given
        WireSyncEngine.AddressBook.markAddressBookAsNeedingToBeUploaded(self.syncMOC)
        let nilRequest = sut.nextRequest() // this will return nil and start async processing
        XCTAssertNil(nilRequest)

        
        // when
        var requests : [ZMTransportRequest?] = []
        (0..<10).forEach { _ in
            Thread.sleep(forTimeInterval: 0.05)
            requests.append(sut.nextRequest())
        }
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        requests.append(sut.nextRequest())
        
        // then
        XCTAssertEqual(requests.compactMap { $0 }.count, 1)
    }
    
    func testThatItReturnsARequestWhenTheABIsMarkedForUploadAgain() {
        
        // given
        WireSyncEngine.AddressBook.markAddressBookAsNeedingToBeUploaded(self.syncMOC)
        _ = sut.nextRequest() // this will return nil and start async processing
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        let request1 = sut.nextRequest()
        request1?.complete(with: ZMTransportResponse(payload: nil, httpStatus: 200, transportSessionError: nil))
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // when
        WireSyncEngine.AddressBook.markAddressBookAsNeedingToBeUploaded(self.syncMOC)
        _ = sut.nextRequest() // this will return nil and start async processing
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        let request2 = sut.nextRequest()
        
        // then
        XCTAssertNotNil(request1)
        XCTAssertNotNil(request2)
        guard let cards1 = request1?.payload?.parsedCards, let cards2 = request2?.payload?.parsedCards else {
            XCTFail()
            return
        }
        XCTAssertEqual(cards1, cards2)
    }
}


// MARK: - Resume uploading from where it left off

private let maxEntriesInAddressBookChunk = 1000

extension AddressBookUploadRequestStrategyTest {
    
    func testThatItUploadsInConsecutiveBatches() {
        
        // given
        self.addressBook.fillWithContacts(UInt(maxEntriesInAddressBookChunk*3))
        let request1 = self.getNextUploadingRequest()
        
        // when
        let request2 = self.getNextUploadingRequest()
        
        // then
        XCTAssertNotNil(request1)
        XCTAssertNotNil(request2)
        if let cards1 = (request1?.payload as? [String:AnyObject])?["cards"] as? [[String:AnyObject]] {
            XCTAssertEqual(cards1.count, maxEntriesInAddressBookChunk)
            self.checkCard(cards1.first, expectedIndex: 0)
            self.checkCard(cards1.last, expectedIndex: maxEntriesInAddressBookChunk - 1)
        } else {
            XCTFail()
        }
        if let cards2 = (request2?.payload as? [String:AnyObject])?["cards"] as? [[String:AnyObject]] {
            XCTAssertEqual(cards2.count, maxEntriesInAddressBookChunk)
            self.checkCard(cards2.first, expectedIndex: maxEntriesInAddressBookChunk)
            self.checkCard(cards2.last, expectedIndex: maxEntriesInAddressBookChunk * 2 - 1)
        } else {
            XCTFail()
        }
    }
    
    func testThatItUploadsInBatchesAndRestartWhenItReachedTheEnd() {
        
        // given
        let cardsNumber = Int(Double(maxEntriesInAddressBookChunk) * 1.5)
        self.addressBook.fillWithContacts(UInt(cardsNumber))
        
        // when
        let request1 = self.getNextUploadingRequest()
        let request2 = self.getNextUploadingRequest()
        let request3 = self.getNextUploadingRequest()
        
        // then
        XCTAssertNotNil(request1)
        XCTAssertNotNil(request2)
        XCTAssertNotNil(request3)
        if let cards1 = (request1?.payload as? [String:AnyObject])?["cards"] as? [[String:AnyObject]] {
            XCTAssertEqual(cards1.count, maxEntriesInAddressBookChunk)
            self.checkCard(cards1.first, expectedIndex: 0)
            self.checkCard(cards1.last, expectedIndex: maxEntriesInAddressBookChunk - 1)
        } else {
            XCTFail()
        }
        if let cards2 = (request2?.payload as? [String:AnyObject])?["cards"] as? [[String:AnyObject]] {
            XCTAssertEqual(cards2.count, cardsNumber - maxEntriesInAddressBookChunk)
            self.checkCard(cards2.first, expectedIndex: maxEntriesInAddressBookChunk)
            self.checkCard(cards2.last, expectedIndex: cardsNumber-1)
        } else {
            XCTFail()
        }
        if let cards3 = (request3?.payload as? [String:AnyObject])?["cards"] as? [[String:AnyObject]] {
            XCTAssertEqual(cards3.count, maxEntriesInAddressBookChunk)
            self.checkCard(cards3.first, expectedIndex: 0)
            self.checkCard(cards3.last, expectedIndex: maxEntriesInAddressBookChunk - 1)
        } else {
            XCTFail()
        }
    }
    
    func testThatItUploadsInBatchesAndRestartWhenItReachedTheEnd_ExactlyOnLastContact() {
        
        // given
        let cardsNumber = Int(Double(maxEntriesInAddressBookChunk) * 2)
        self.addressBook.fillWithContacts(UInt(cardsNumber))
        let request1 = self.getNextUploadingRequest()
        let request2 = self.getNextUploadingRequest()
        let request3 = self.getNextUploadingRequest()
        
        // then
        XCTAssertNotNil(request1)
        XCTAssertNotNil(request2)
        XCTAssertNotNil(request3)
        if let cards1 = (request1?.payload as? [String:AnyObject])?["cards"] as? [[String:AnyObject]] {
            XCTAssertEqual(cards1.count, maxEntriesInAddressBookChunk)
            self.checkCard(cards1.first, expectedIndex: 0)
            self.checkCard(cards1.last, expectedIndex: maxEntriesInAddressBookChunk - 1)
        } else {
            XCTFail()
        }
        if let cards2 = (request2?.payload as? [String:AnyObject])?["cards"] as? [[String:AnyObject]] {
            XCTAssertEqual(cards2.count, cardsNumber - maxEntriesInAddressBookChunk)
            self.checkCard(cards2.first, expectedIndex: maxEntriesInAddressBookChunk)
            self.checkCard(cards2.last, expectedIndex: cardsNumber-1)
        } else {
            XCTFail()
        }
        if let cards3 = (request3?.payload as? [String:AnyObject])?["cards"] as? [[String:AnyObject]] {
            XCTAssertEqual(cards3.count, maxEntriesInAddressBookChunk)
            self.checkCard(cards3.first, expectedIndex: 0)
            self.checkCard(cards3.last, expectedIndex: maxEntriesInAddressBookChunk - 1)
        } else {
            XCTFail()
        }
    }
    
    func testThatItUploadsInBatchesAndRestartWhenItReachedTheEnd_WithDiscrepancyOnTheNumberOfContacts() {
        // It could happen that we have 2000 contacts in the AB, but only 1500 of them have valid emails
        // or phone numbers that we can upload. So we can never upload more than 1500. This test checks 
        // that we correcly detect that we reached the end of the "uploadable" contacts and restart from
        // the first, even if we did not yet upload as many "raw" contacts as we have in the AB
        
        // given
        let cardsNumber = Int(Double(maxEntriesInAddressBookChunk) * 1.5)
        self.addressBook.fillWithContacts(UInt(cardsNumber))
        self.addressBook.numberOfAdditionalContacts = UInt(maxEntriesInAddressBookChunk * 5)
        
        // when
        let request1 = self.getNextUploadingRequest()
        let request2 = self.getNextUploadingRequest()
        let request3 = self.getNextUploadingRequest()
        
        // then
        XCTAssertNotNil(request1)
        XCTAssertNotNil(request2)
        XCTAssertNotNil(request3)
        if let cards1 = (request1?.payload as? [String:AnyObject])?["cards"] as? [[String:AnyObject]] {
            XCTAssertEqual(cards1.count, maxEntriesInAddressBookChunk)
            self.checkCard(cards1.first, expectedIndex: 0)
            self.checkCard(cards1.last, expectedIndex: maxEntriesInAddressBookChunk - 1)
        } else {
            XCTFail()
        }
        if let cards2 = (request2?.payload as? [String:AnyObject])?["cards"] as? [[String:AnyObject]] {
            XCTAssertEqual(cards2.count, cardsNumber - maxEntriesInAddressBookChunk)
            self.checkCard(cards2.first, expectedIndex: maxEntriesInAddressBookChunk)
            self.checkCard(cards2.last, expectedIndex: cardsNumber-1)
        } else {
            XCTFail()
        }
        if let cards3 = (request3?.payload as? [String:AnyObject])?["cards"] as? [[String:AnyObject]] {
            XCTAssertEqual(cards3.count, maxEntriesInAddressBookChunk)
            self.checkCard(cards3.first, expectedIndex: 0)
            self.checkCard(cards3.last, expectedIndex: maxEntriesInAddressBookChunk - 1)
        } else {
            XCTFail()
        }
        
    }
}

// MARK: - Matched contacts

/*
 Expected payload for /onboarding/v3
 
 {
    "results": [
        {
            "cards": [
                ""
            ],
            "id": "",
            "cards": [""]
        }
    ]
 }

 */

extension AddressBookUploadRequestStrategyTest {
    
    func testThatItParsesMatchingUsersFromResponse() {
        
        // GIVEN
        let user1 = self.createUser(connected: true)
        let user2 = self.createUser(connected: true)
        _ = self.createUser(connected: true)

        let contacts = [
            FakeAddressBookContact(firstName: "Joanna", emailAddresses: ["j@example.com"], phoneNumbers: [], identifier: UUID.create().transportString()),
            FakeAddressBookContact(firstName: "Chihiro", emailAddresses: ["c@example.com"], phoneNumbers: [], identifier: UUID.create().transportString())
        ]
        self.addressBook.fakeContacts = contacts
        
        let payload = [
            "results" : [
                [
                    "id" : user1.remoteIdentifier!.transportString(),
                    "cards" : [contacts[0].localIdentifier]
                ],
                [
                    "id" : user2.remoteIdentifier!.transportString(),
                    "cards" : [contacts[1].localIdentifier]
                ],
            ]
        ]
        WireSyncEngine.AddressBook.markAddressBookAsNeedingToBeUploaded(self.syncMOC)
        _ = sut.nextRequest() // this will return nil and start async processing
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        let request = sut.nextRequest()
        
        // WHEN
        request?.complete(with: ZMTransportResponse(payload: payload as ZMTransportData, httpStatus: 200, transportSessionError: nil))
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // THEN
        XCTAssertEqual(user1.addressBookEntry?.localIdentifier, contacts[0].localIdentifier)
        XCTAssertEqual(user1.addressBookEntry?.cachedName, contacts[0].firstName)
        XCTAssertEqual(user2.addressBookEntry?.localIdentifier, contacts[1].localIdentifier)
        XCTAssertEqual(user2.addressBookEntry?.cachedName, contacts[1].firstName)

    }
    
    func testThatItCreatesMatchingUsersFromResponseIfTheyDoNotExist() {
        
        // GIVEN
        let user1 = self.createUser(connected: true)
        user1.needsToBeUpdatedFromBackend = false
        let user2ID = UUID.create()
        
        let contacts = [
            FakeAddressBookContact(firstName: "Joanna", emailAddresses: ["j@example.com"], phoneNumbers: [], identifier: UUID.create().transportString()),
            FakeAddressBookContact(firstName: "Chihiro", emailAddresses: ["c@example.com"], phoneNumbers: [], identifier: UUID.create().transportString())
        ]
        self.addressBook.fakeContacts = contacts
        
        let payload = [
            "results" : [
                [
                    "id" : user1.remoteIdentifier!.transportString(),
                    "cards" : [contacts[0].localIdentifier]
                ],
                [
                    "id" : user2ID.transportString(),
                    "cards" : [contacts[1].localIdentifier]
                ],
            ]
        ]
        WireSyncEngine.AddressBook.markAddressBookAsNeedingToBeUploaded(self.syncMOC)
        _ = sut.nextRequest() // this will return nil and start async processing
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        let request = sut.nextRequest()
        
        // WHEN
        request?.complete(with: ZMTransportResponse(payload: payload as ZMTransportData, httpStatus: 200, transportSessionError: nil))
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // THEN
        XCTAssertFalse(user1.needsToBeUpdatedFromBackend)
        
        guard let user2 = ZMUser(remoteID: user2ID, createIfNeeded: false, in: self.syncMOC) else {
            XCTFail("No user was created")
            return
        }
        XCTAssertEqual(user2.addressBookEntry?.localIdentifier, contacts[1].localIdentifier)
        XCTAssertEqual(user2.addressBookEntry?.cachedName, contacts[1].firstName)
        XCTAssertTrue(user2.needsToBeUpdatedFromBackend)
        XCTAssertEqual(user2.remoteIdentifier, user2ID)
    }
    
    func testThatItEmptiesMatchingUsersIfResponseIsEmpty() {
        
        // GIVEN
        let user1 = self.createUser(connected: true)
        let user2 = self.createUser(connected: true)
        user1.addressBookEntry = AddressBookEntry.insertNewObject(in: self.syncMOC)
        user2.addressBookEntry = AddressBookEntry.insertNewObject(in: self.syncMOC)
        user1.addressBookEntry?.cachedName = "JJ"
        user2.addressBookEntry?.cachedName = "Kirk"
        user1.addressBookEntry?.localIdentifier = "u1"
        user2.addressBookEntry?.localIdentifier = "u2"
        self.syncMOC.saveOrRollback()
        
        let contacts = [
            FakeAddressBookContact(firstName: "Joanna", emailAddresses: ["j@example.com"], phoneNumbers: [], identifier: "u1"),
            FakeAddressBookContact(firstName: "Chihiro", emailAddresses: ["c@example.com"], phoneNumbers: [], identifier: "u2")
        ]
        self.addressBook.fakeContacts = contacts
        let payload = [
            "results" : []
        ]

        WireSyncEngine.AddressBook.markAddressBookAsNeedingToBeUploaded(self.syncMOC)
        _ = sut.nextRequest() // this will return nil and start async processing
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        let request = sut.nextRequest()
        
        // WHEN
        request?.complete(with: ZMTransportResponse(payload: payload as ZMTransportData, httpStatus: 200, transportSessionError: nil))
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // THEN
        XCTAssertNil(user1.addressBookEntry)
        XCTAssertNil(user2.addressBookEntry)
    }
    
    func testThatItDoesNotEmptyMatchingUsersFromResponseIfNotParsed() {
        
        // GIVEN
        let user1 = self.createUser(connected: true)
        let user2 = self.createUser(connected: true)
        user1.addressBookEntry = AddressBookEntry.insertNewObject(in: self.syncMOC)
        user2.addressBookEntry = AddressBookEntry.insertNewObject(in: self.syncMOC)
        user1.addressBookEntry?.cachedName = "JJ"
        user2.addressBookEntry?.cachedName = "Kirk"
        self.syncMOC.saveOrRollback()
        
        let contacts = [
            FakeAddressBookContact(firstName: "Joanna", emailAddresses: ["j@example.com"], phoneNumbers: []),
            FakeAddressBookContact(firstName: "Chihiro", emailAddresses: ["c@example.com"], phoneNumbers: [])
        ]
        self.addressBook.fakeContacts = contacts
        let payload = [
            "apples" : "oranges"
        ]

        WireSyncEngine.AddressBook.markAddressBookAsNeedingToBeUploaded(self.syncMOC)
        _ = sut.nextRequest() // this will return nil and start async processing
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        let request = sut.nextRequest()
        XCTAssertNotNil(request)
        
        // WHEN
        request?.complete(with: ZMTransportResponse(payload: payload as ZMTransportData, httpStatus: 200, transportSessionError: nil))
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // THEN
        XCTAssertNotNil(user1.addressBookEntry)
        XCTAssertNotNil(user2.addressBookEntry)
    }
}

// MARK: - Helpers
extension AddressBookUploadRequestStrategyTest {
    
    /// Returns the next request that is supposed to contain the AB upload payload.
    /// It also completes that request so that new requests will upload the next chunk
    /// of the AB
    func getNextUploadingRequest() -> ZMTransportRequest? {
        WireSyncEngine.AddressBook.markAddressBookAsNeedingToBeUploaded(self.syncMOC)
        _ = sut.nextRequest() // this will return nil and start async processing
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        let request = sut.nextRequest()
        let payload : [String: Any] = ["results" : []]
        request?.complete(with: ZMTransportResponse(payload: payload as NSDictionary, httpStatus: 200, transportSessionError: nil))
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        return request
    }
    
    /// Verify that a card matches the expected values: card ID and contact hash
    func checkCard(_ card: [String:AnyObject]?, expectedIndex: Int, line: UInt = #line, file: StaticString = #file) {
        let cardId = card?["card_id"] as? String
        guard let cardHashes = card?["contact"] as? [String] else {
            XCTFail(file: file, line: line)
            return
        }
        let expected = self.addressBook.fakeContacts[expectedIndex]
        XCTAssertEqual(cardId, expected.localIdentifier, file: file, line: line)
        XCTAssertEqual(cardHashes, expected.expectedHashes, file: file, line: line)
    }
    
    /// Creates a new user
    func createUser(connected: Bool) -> ZMUser {
        let user = ZMUser.insertNewObject(in: self.syncMOC)
        user.remoteIdentifier = UUID.create()
        if connected {
            let connection = ZMConnection.insertNewObject(in: self.syncMOC)
            connection.to = user
            connection.status = .accepted
        }
        self.syncMOC.saveOrRollback()
        return user
    }
}

/// Fake to supply predefined AB hashes
class AddressBookFake : WireSyncEngine.AddressBook, WireSyncEngine.AddressBookAccessor {
    
    /// Find contact by Id
    func contact(identifier: String) -> WireSyncEngine.ContactRecord? {
        return fakeContacts.first { $0.localIdentifier == identifier }
    }
    
    /// List of contacts in this address book
    var fakeContacts = [FakeAddressBookContact]()
    
    /// Reported number of contacts (it might be higher than `fakeContacts`
    /// because some contacts are filtered for not having valid email/phone)
    var numberOfAdditionalContacts : UInt = 0
    
    var numberOfContacts : UInt {
        return UInt(self.fakeContacts.count) + numberOfAdditionalContacts
    }

    /// Enumerates the contacts, invoking the block for each contact.
    /// If the block returns false, it will stop enumerating them.
    func enumerateRawContacts(block: @escaping (WireSyncEngine.ContactRecord)->(Bool)) {
        for contact in self.fakeContacts {
            if !block(contact) {
                return
            }
        }
        let infiniteContact = FakeAddressBookContact(firstName: "johnny infinite",
                                                   emailAddresses: ["johnny.infinite@example.com"],
                                                   phoneNumbers: [])
        while createInfiniteContacts {
            if !block(infiniteContact) {
                return
            }
        }
    }
    
    func rawContacts(matchingQuery: String) -> [WireSyncEngine.ContactRecord] {
        guard matchingQuery != "" else {
            return fakeContacts
        }
        return fakeContacts.filter { $0.firstName.lowercased().contains(matchingQuery.lowercased()) || $0.lastName.lowercased().contains(matchingQuery.lowercased()) }
    }
    
    /// Replace the content with a given number of random hashes
    func fillWithContacts(_ number: UInt) {
        self.fakeContacts = (0..<number).map {
            self.createContact(card: $0)
        }
    }
    
    /// Create a fake contact
    func createContact(card: UInt) -> FakeAddressBookContact {
        return FakeAddressBookContact(firstName: "tester \(card)", emailAddresses: ["tester_\(card)@example.com"], phoneNumbers: ["+155512300\(card.hashValue % 10)"], identifier: "\(card)")
    }
    
    /// Generate an infinite number of contacts
    var createInfiniteContacts = false
}

struct FakeAddressBookContact : WireSyncEngine.ContactRecord {
    
    static var incrementalLocalIdentifier = 0
    
    var firstName = ""
    var lastName = ""
    var middleName = ""
    var rawEmails : [String]
    var rawPhoneNumbers : [String]
    var nickname = ""
    var organization = ""
    var localIdentifier = ""
    
    init(firstName: String, emailAddresses: [String], phoneNumbers: [String], identifier: String? = nil) {
        self.firstName = firstName
        self.rawEmails = emailAddresses
        self.rawPhoneNumbers = phoneNumbers
        self.localIdentifier = identifier ?? {
            FakeAddressBookContact.incrementalLocalIdentifier += 1
            return "\(FakeAddressBookContact.incrementalLocalIdentifier)"
        }()
    }
    
    var expectedHashes : [String] {
        return self.rawEmails.map { $0.base64EncodedSHADigest } + self.rawPhoneNumbers.map { $0.base64EncodedSHADigest }
    }
}

private enum TestErrors : Error {
    case failedToParse
}

private struct ContactCard: Equatable {
    let id: String
    let hashes: [String]
}

private func ==(lhs: ContactCard, rhs: ContactCard) -> Bool {
    return lhs.id == rhs.id && lhs.hashes == rhs.hashes
}

extension ZMTransportData {

    /// Parse addressbook upload payload as contact cards
    fileprivate var parsedCards : [ContactCard]? {

        guard let dict = self as? [String:AnyObject],
            let cards = dict["cards"] as? [[String:AnyObject]]
        else {
            return nil
        }

        do {
            return try cards.map { card in
                guard let id = card["card_id"] as? String, let hashes = card["contact"] as? [String] else {
                    throw TestErrors.failedToParse
                }
                return ContactCard(id: id, hashes: hashes)
            }.sorted {
                $0.id < $1.id
            }
        } catch {
            return nil
        }
    }
}
