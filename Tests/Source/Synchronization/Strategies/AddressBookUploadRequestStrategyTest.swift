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

// TODO MARCO: test that it uploads entire address book by remembering where it stopped

// MARK: - Helpers

class AddressBookFake : zmessaging.AddressBookAccessor {
    
    var numberOfContacts : UInt {
        return UInt(contactHashes.count)
    }
    var contactHashes : [[String]] = []
    
    func iterate() -> AnyGenerator<ZMAddressBookContact> {
        return AnyGenerator([].generate())
    }
    
    func encodeWithCompletionHandler(groupQueue: ZMSGroupQueue, startingContactIndex: UInt, maxNumberOfContacts: UInt, completion: (zmessaging.EncodedAddressBookChunk?) -> ()) {
        guard self.contactHashes.count > 0 else {
            groupQueue.performGroupedBlock({ 
                completion(nil)
            })
            return
        }
        let range = startingContactIndex..<(min(numberOfContacts, startingContactIndex+maxNumberOfContacts))
        let chunk = zmessaging.EncodedAddressBookChunk(numberOfTotalContacts: self.numberOfContacts,
                                                       otherContactsHashes: self.contactHashes,
                                                       includedContacts: range)
        groupQueue.performGroupedBlock { 
            completion(chunk)
        }
    }
    
    func fillWithContacts(number: UInt) {
        contactHashes = (0..<number).map {
            ["hash-\($0)_0", "hash-\($0)_1"]
        }
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

/// Extracts a list of cards from a payload
extension ZMTransportData {

    /// Parse addressbook upload payload as contact cards
    private var parsedCards : [ContactCard]? {

        guard let dict = self as? [String:AnyObject],
            let cards = dict["cards"] as? [[String:AnyObject]]
        else {
            return nil
        }

        print(cards)
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
