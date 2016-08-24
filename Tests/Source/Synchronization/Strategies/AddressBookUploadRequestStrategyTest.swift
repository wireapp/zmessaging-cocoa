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
import ZMCLinkPreview
@testable import zmessaging

class AddressBookUploadRequestStrategyTest : MessagingTest {
    
    var sut : zmessaging.AddressBookUploadRequestStrategy!
    var authenticationStatus : MockAuthenticationStatus!
    var clientRegistrationStatus : ZMMockClientRegistrationStatus!
    var addressBook : AddressBookFake!
    
    override func setUp() {
        super.setUp()
        self.authenticationStatus = MockAuthenticationStatus(phase: .Authenticated)
        self.clientRegistrationStatus = ZMMockClientRegistrationStatus()
        self.clientRegistrationStatus.mockPhase = .Registered
        self.addressBook = AddressBookFake()
        let ab = self.addressBook // I don't want to capture self in closure later
        ab.contactHashes = [
            ["1"], ["2a", "2b"], ["3"], ["4"]
        ]
        self.sut = zmessaging.AddressBookUploadRequestStrategy(authenticationStatus: self.authenticationStatus,
                                                    clientRegistrationStatus: self.clientRegistrationStatus,
                                                    managedObjectContext: self.syncMOC,
                                                    addressBookGenerator: { return ab } )
    }
    
    override func tearDown() {
        self.authenticationStatus = nil
        self.clientRegistrationStatus.tearDown()
        self.clientRegistrationStatus = nil
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
        XCTAssertTrue(self.waitForAllGroupsToBeEmptyWithTimeout(0.5))
        XCTAssertNil(request)
    }
    
    func testThatItReturnsARequestWhenTheABIsMarkedForUpload() {
        
        // given
        zmessaging.AddressBook.markAddressBookAsNeedingToBeUploaded(self.syncMOC)
        
        // when
        let nilRequest = sut.nextRequest() // this will return nil and start async processing
        
        // then
        XCTAssertNil(nilRequest)
        XCTAssertTrue(self.waitForAllGroupsToBeEmptyWithTimeout(0.5))
        let request = sut.nextRequest()
        XCTAssertNotNil(request)
        if let request = request {
            XCTAssertEqual(request.path, "/onboarding/v3")
            XCTAssertEqual(request.method, ZMTransportRequestMethod.MethodPOST)
            let expectedCards = self.addressBook.contactHashes.enumerate().map { (index, hashes) in ContactCard(id: "\(index)", hashes: hashes)}
            
            if let parsedCards = request.payload.parsedCards {
                XCTAssertEqual(parsedCards, expectedCards)
            } else {
                XCTFail("No parsed cards")
            }
            XCTAssertTrue(request.shouldCompress)
        }
    }
    
    func testThatItUploadsOnlyOnceWhenNotAskedAgain() {
        
        // given
        zmessaging.AddressBook.markAddressBookAsNeedingToBeUploaded(self.syncMOC)
        _ = sut.nextRequest() // this will return nil and start async processing
        XCTAssertTrue(self.waitForAllGroupsToBeEmptyWithTimeout(0.5))
        let request = sut.nextRequest()
        request?.completeWithResponse(ZMTransportResponse(payload: [], HTTPstatus: 200, transportSessionError: nil))
        XCTAssertTrue(self.waitForAllGroupsToBeEmptyWithTimeout(0.5))
        
        // when
        XCTAssertNil(sut.nextRequest())
        XCTAssertTrue(self.waitForAllGroupsToBeEmptyWithTimeout(0.5))
        
        // then
        XCTAssertNil(sut.nextRequest())
        
    }
    
    func testThatItReturnsNoRequestWhenTheABIsMarkedForUploadAndEmpty() {
        
        // given
        self.addressBook.contactHashes = []
        zmessaging.AddressBook.markAddressBookAsNeedingToBeUploaded(self.syncMOC)
        
        // when
        let nilRequest = sut.nextRequest() // this will return nil and start async processing
        
        // then
        XCTAssertNil(nilRequest)
        XCTAssertTrue(self.waitForAllGroupsToBeEmptyWithTimeout(0.5))
        let request = sut.nextRequest()
        XCTAssertNil(request)
    }
    
    func testThatOnlyOneRequestIsReturnedWhenCalledMultipleTimes() {
        
        // this test is tricky because I don't get a nextRequest immediately, but only after a while,
        // when creating the payload is done. I will call it multiple times and then one last time after waiting
        // (to be sure that async is done) and see that I got a non-nil only once.
        
        // given
        zmessaging.AddressBook.markAddressBookAsNeedingToBeUploaded(self.syncMOC)
        let nilRequest = sut.nextRequest() // this will return nil and start async processing
        XCTAssertNil(nilRequest)

        
        // when
        var requests : [ZMTransportRequest?] = []
        (0..<10).forEach { _ in
            NSThread.sleepForTimeInterval(0.05)
            requests.append(sut.nextRequest())
        }
        XCTAssertTrue(self.waitForAllGroupsToBeEmptyWithTimeout(0.5))
        requests.append(sut.nextRequest())
        
        // then
        XCTAssertEqual(requests.flatMap { $0 }.count, 1)
    }
    
    func testThatItReturnsARequestWhenTheABIsMarkedForUploadAgain() {
        
        // given
        zmessaging.AddressBook.markAddressBookAsNeedingToBeUploaded(self.syncMOC)
        _ = sut.nextRequest() // this will return nil and start async processing
        XCTAssertTrue(self.waitForAllGroupsToBeEmptyWithTimeout(0.5))
        let request1 = sut.nextRequest()
        request1?.completeWithResponse(ZMTransportResponse(payload: nil, HTTPstatus: 200, transportSessionError: nil))
        XCTAssertTrue(self.waitForAllGroupsToBeEmptyWithTimeout(0.5))
        
        // when
        zmessaging.AddressBook.markAddressBookAsNeedingToBeUploaded(self.syncMOC)
        _ = sut.nextRequest() // this will return nil and start async processing
        XCTAssertTrue(self.waitForAllGroupsToBeEmptyWithTimeout(0.5))
        let request2 = sut.nextRequest()
        
        // then
        XCTAssertNotNil(request1)
        XCTAssertNotNil(request2)
        guard let cards1 = request1?.payload.parsedCards, let cards2 = request2?.payload.parsedCards else {
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
            XCTAssertTrue(self.checkCard(cards1.first, expectedIndex: 0))
            XCTAssertTrue(self.checkCard(cards1.last, expectedIndex: maxEntriesInAddressBookChunk - 1))
        } else {
            XCTFail()
        }
        if let cards2 = (request2?.payload as? [String:AnyObject])?["cards"] as? [[String:AnyObject]] {
            XCTAssertEqual(cards2.count, maxEntriesInAddressBookChunk)
            XCTAssertTrue(self.checkCard(cards2.first, expectedIndex: maxEntriesInAddressBookChunk))
            XCTAssertTrue(self.checkCard(cards2.last, expectedIndex: maxEntriesInAddressBookChunk * 2 - 1))
        } else {
            XCTFail()
        }
    }
    
    func testThatItUploadsInBatchesAndRestartWhenItReachedTheEnd() {
        
        // given
        let cardsNumber = Int(Double(maxEntriesInAddressBookChunk) * 1.5)
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
            XCTAssertTrue(self.checkCard(cards1.first, expectedIndex: 0))
            XCTAssertTrue(self.checkCard(cards1.last, expectedIndex: maxEntriesInAddressBookChunk - 1))
        } else {
            XCTFail()
        }
        if let cards2 = (request2?.payload as? [String:AnyObject])?["cards"] as? [[String:AnyObject]] {
            XCTAssertEqual(cards2.count, cardsNumber - maxEntriesInAddressBookChunk)
            XCTAssertTrue(self.checkCard(cards2.first, expectedIndex: maxEntriesInAddressBookChunk))
            XCTAssertTrue(self.checkCard(cards2.last, expectedIndex: cardsNumber-1))
        } else {
            XCTFail()
        }
        if let cards3 = (request3?.payload as? [String:AnyObject])?["cards"] as? [[String:AnyObject]] {
            XCTAssertEqual(cards3.count, maxEntriesInAddressBookChunk)
            XCTAssertTrue(self.checkCard(cards3.first, expectedIndex: 0))
            XCTAssertTrue(self.checkCard(cards3.last, expectedIndex: maxEntriesInAddressBookChunk - 1))
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
            XCTAssertTrue(self.checkCard(cards1.first, expectedIndex: 0))
            XCTAssertTrue(self.checkCard(cards1.last, expectedIndex: maxEntriesInAddressBookChunk - 1))
        } else {
            XCTFail()
        }
        if let cards2 = (request2?.payload as? [String:AnyObject])?["cards"] as? [[String:AnyObject]] {
            XCTAssertEqual(cards2.count, cardsNumber - maxEntriesInAddressBookChunk)
            XCTAssertTrue(self.checkCard(cards2.first, expectedIndex: maxEntriesInAddressBookChunk))
            XCTAssertTrue(self.checkCard(cards2.last, expectedIndex: cardsNumber-1))
        } else {
            XCTFail()
        }
        if let cards3 = (request3?.payload as? [String:AnyObject])?["cards"] as? [[String:AnyObject]] {
            XCTAssertEqual(cards3.count, maxEntriesInAddressBookChunk)
            XCTAssertTrue(self.checkCard(cards3.first, expectedIndex: 0))
            XCTAssertTrue(self.checkCard(cards3.last, expectedIndex: maxEntriesInAddressBookChunk - 1))
        } else {
            XCTFail()
        }
    }
}

// MARK: - Helpers
extension AddressBookUploadRequestStrategyTest {
    
    /// Returns the next request that is supposed to contain the AB upload payload.
    /// It also completes that request so that new requests will upload the next chunk
    /// of the AB
    func getNextUploadingRequest() -> ZMTransportRequest? {
        zmessaging.AddressBook.markAddressBookAsNeedingToBeUploaded(self.syncMOC)
        _ = sut.nextRequest() // this will return nil and start async processing
        XCTAssertTrue(self.waitForAllGroupsToBeEmptyWithTimeout(0.5))
        let request = sut.nextRequest()
        request?.completeWithResponse(ZMTransportResponse(payload: nil, HTTPstatus: 200, transportSessionError: nil))
        XCTAssertTrue(self.waitForAllGroupsToBeEmptyWithTimeout(0.5))
        return request
    }
    
    /// Verify that a card matches the expected values: card ID and contact hash
    func checkCard(card: [String:AnyObject]?, expectedIndex: Int) -> Bool {
        let cardId = card?["card_id"] as? String
        let expectedId = "\(expectedIndex)"
        guard let cardHashes = card?["contact"] as? [String] else {
            XCTFail()
            return false
        }
        let expectedHashes = self.addressBook.hashesForCard(UInt(expectedIndex))
        XCTAssertEqual(cardId, expectedId)
        XCTAssertEqual(cardHashes, expectedHashes)
        return cardId == expectedId && cardHashes == expectedHashes
    }
}

/// Fake to supply predefined AB hashes
class AddressBookFake : zmessaging.AddressBookAccessor {
    
    var numberOfContacts : UInt {
        return UInt(contactHashes.count)
    }
    var contactHashes : [[String]] = []
    
    func iterate() -> LazySequence<AnyGenerator<ZMAddressBookContact>> {
        return AnyGenerator([].generate()).lazy
    }
    
    func encodeWithCompletionHandler(groupQueue: ZMSGroupQueue, startingContactIndex: UInt, maxNumberOfContacts: UInt, completion: (zmessaging.EncodedAddressBookChunk?) -> ()) {
        guard self.contactHashes.count > 0 else {
            groupQueue.performGroupedBlock({ 
                completion(nil)
            })
            return
        }
        let range = startingContactIndex..<(min(numberOfContacts, startingContactIndex+maxNumberOfContacts))
        let contactsInRange = Array(self.contactHashes[Int(range.startIndex)..<Int(range.endIndex)])
        let chunk = zmessaging.EncodedAddressBookChunk(numberOfTotalContacts: self.numberOfContacts,
                                                       otherContactsHashes: contactsInRange,
                                                       includedContacts: range)
        groupQueue.performGroupedBlock { 
            completion(chunk)
        }
    }
    
    func fillWithContacts(number: UInt) {
        contactHashes = (0..<number).map {
            self.hashesForCard($0)
        }
    }
    
    func hashesForCard(number: UInt) -> [String] {
        return ["hash-\(number)_0", "hash-\(number)_1"]
    }
}

extension ZMAddressBookContact {
    
    convenience init(emailAddresses: [String], phoneNumbers: [String]) {
        self.init()
        self.emailAddresses = emailAddresses
        self.phoneNumbers = phoneNumbers
    }
}

private enum TestErrors : ErrorType {
    case FailedToParse
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
    private var parsedCards : [ContactCard]? {

        guard let dict = self as? [String:AnyObject],
            let cards = dict["cards"] as? [[String:AnyObject]]
        else {
            return nil
        }

        do {
            return try cards.map { card in
                guard let id = card["card_id"] as? String, hashes = card["contact"] as? [String] else {
                    throw TestErrors.FailedToParse
                }
                return ContactCard(id: id, hashes: hashes)
            }
        } catch {
            return nil
        }
    }
}
