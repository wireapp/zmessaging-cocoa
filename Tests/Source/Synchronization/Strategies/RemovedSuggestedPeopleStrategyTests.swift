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

@testable import zmessaging

class RemovedSuggestedPeopleStrategyTests : MessagingTest {

    var sut: RemovedSuggestedPeopleStrategy!
    var clientRegistrationDelegate : ZMMockClientRegistrationStatus!
    let remoteIDA = UUID()
    let remoteIDB = UUID()
    
    override func setUp() {
        super.setUp()
        clientRegistrationDelegate = ZMMockClientRegistrationStatus()
        sut = RemovedSuggestedPeopleStrategy(managedObjectContext: syncMOC, clientRegistrationDelegate: clientRegistrationDelegate)
    }
    
    override func tearDown() {
        sut.tearDown()
        sut = nil
        clientRegistrationDelegate.tearDown()
        clientRegistrationDelegate = nil
        super.tearDown()
    }
    
    func testThatItDoesNotGenerateARequestWhenThereAreNotRemovedIDs() {
        // when
        let request = sut.nextRequest()
        
        // then
        XCTAssertNil(request);
    }
    
    func setRemovedRemoteIdentifiersAndWaitForNotification() {
        syncMOC.performGroupedBlockAndWait{
            // expect
            self.expectation(forNotification: "RequestAvailableNotification", object: self.sut, handler: nil)
            
            // when
            self.syncMOC.removedSuggestedContactRemoteIdentifiers = [self.remoteIDA, self.remoteIDB]
        }
        XCTAssert(self.waitForCustomExpectations(withTimeout:0.5))
    }
    
    
    func testThatItGeneratesRequestsForRemovedIDs() {
        // given
        setRemovedRemoteIdentifiersAndWaitForNotification()
        
        syncMOC.performGroupedBlockAndWait{
            // when
            guard let request1 = self.sut.nextRequest() else { return XCTFail() }
            guard let request2 = self.sut.nextRequest() else { return XCTFail() }
            let request3 = self.sut.nextRequest()
            
            // then
            XCTAssertNotNil(request1);
            XCTAssertEqual(request1.method, .methodPUT);
            XCTAssertNil(request1.payload);
            
            XCTAssertNotNil(request2);
            XCTAssertEqual(request2.method, .methodPUT);
            XCTAssertNil(request2.payload);
            
            let expectedPaths = ["/search/suggestions/\(self.remoteIDA.transportString())/ignore",
                                 "/search/suggestions/\(self.remoteIDB.transportString())/ignore"]
            
            XCTAssertTrue(expectedPaths.contains(request1.path))
            XCTAssertTrue(expectedPaths.contains(request1.path))
            XCTAssertNotEqual(request1.path, request2.path);
            
            XCTAssertNil(request3);
        }
    }
    
    func testThatItDoesNotGenerateRequestsClientNotReady() {
        // given
        setRemovedRemoteIdentifiersAndWaitForNotification()
        clientRegistrationDelegate.mockReadiness = false
        
        syncMOC.performGroupedBlockAndWait{
            // when
            let request = self.sut.nextRequest()
            
            // then
            XCTAssertNil(request)
        }
    }
    
    func testThatItRemovesIdentifiersOnceTheyHaveBeenSentToTheBackend_1() {
        // given
        setRemovedRemoteIdentifiersAndWaitForNotification()
        let response = ZMTransportResponse(payload:nil, httpStatus:200, transportSessionError:nil)
        
        // when
        syncMOC.performGroupedBlockAndWait{
            guard let request = self.sut.nextRequest() else { return XCTFail() }
            request.complete(with: response)
        }
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout:0.5))
        
        // then
        syncMOC.performGroupedBlockAndWait{
            XCTAssertEqual(self.syncMOC.removedSuggestedContactRemoteIdentifiers.count, 1)
        }
    }
    
    func testThatItRemovesIdentifiersOnceTheyHaveBeenSentToTheBackend_2() {
        // given
        setRemovedRemoteIdentifiersAndWaitForNotification()
        let response = ZMTransportResponse(payload:nil, httpStatus:200, transportSessionError:nil)

        // when
        syncMOC.performGroupedBlockAndWait{
            guard let request1 = self.sut.nextRequest() else { return XCTFail() }
            guard let request2 = self.sut.nextRequest() else { return XCTFail() }

            request1.complete(with: response)
            request2.complete(with: response)
        }
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout:0.5))
        
        // then
        syncMOC.performGroupedBlockAndWait{
            XCTAssertEqual(self.syncMOC.removedSuggestedContactRemoteIdentifiers.count, 0)
        }
    }

    func testThatItDoesNotRemoveAnIdentifierWhenTheResponseIs_TryAgain() {
        // given
        setRemovedRemoteIdentifiersAndWaitForNotification()
        let response = ZMTransportResponse(payload:nil, httpStatus:0, transportSessionError:NSError.tryAgainLaterError())
    
        // when
        syncMOC.performGroupedBlockAndWait{
            guard let request = self.sut.nextRequest() else { return XCTFail() }
            request.complete(with: response)
        }
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout:0.5))
        
        // then
        syncMOC.performGroupedBlockAndWait{
            XCTAssertEqual(self.syncMOC.removedSuggestedContactRemoteIdentifiers.count, 2)
        }
    }
}

