//
// Wire
// Copyright (C) 2017 Wire Swiss GmbH
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
import WireRequestStrategy

class CallingRequestStrategyTests : MessagingTest {

    var sut: CallingRequestStrategy!
    var mockRegistrationDelegate : ClientRegistrationDelegate!
    
    override func setUp() {
        super.setUp()
        mockRegistrationDelegate = MockClientRegistrationDelegate()
        sut = CallingRequestStrategy(managedObjectContext: uiMOC, clientRegistrationDelegate: mockRegistrationDelegate, flowManager: FlowManagerMock(), callEventStatus: CallEventStatus(), configuration: .init())
    }
    
    override func tearDown() {
        sut = nil
        mockRegistrationDelegate = nil
        super.tearDown()
    }

    // MARK: - Misc
    
    func testThatItReturnsItselfAndTheGenericMessageStrategyAsContextChangeTracker(){
        // when
        let trackers = sut.contextChangeTrackers
        
        // then
        XCTAssertTrue(trackers.first is CallingRequestStrategy)
        XCTAssertTrue(trackers.last is GenericMessageRequestStrategy)
    }

    // MARK: - Call Config
    
    func testThatItGenerateCallConfigRequestAndCallsTheCompletionHandler() {
        
        // given
        let expectedCallConfig = "{\"config\":true}"
        let receivedCallConfigExpectation = expectation(description: "Received CallConfig")
        
        sut.requestCallConfig { (callConfig, httpStatusCode) in
            if callConfig == expectedCallConfig, httpStatusCode == 200 {
                receivedCallConfigExpectation.fulfill()
            }
        }
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        let request = sut.nextRequest()
        XCTAssertEqual(request?.path, "/calls/config/v2")
        
        // when
        let payload = [ "config" : true ]
        request?.complete(with: ZMTransportResponse(payload: payload as ZMTransportData, httpStatus: 200, transportSessionError: nil))
        
        // then
        XCTAssertTrue(waitForCustomExpectations(withTimeout: 0.5))
    }
    
    func testThatItGeneratesOnlyOneCallConfigRequest() {
        
        // given
        sut.requestCallConfig { (_, _) in}
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // when
        let request = sut.nextRequest()
        XCTAssertNotNil(request)
        
        // then
        let secondRequest = sut.nextRequest()
        XCTAssertNil(secondRequest)
    }
    
    func testThatItGeneratesCompressedCallConfigRequest() {
        
        // given
        sut.requestCallConfig { (_, _) in}
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // when
        guard let request = sut.nextRequest() else { return XCTFail() }
        
        // then
        XCTAssertTrue(request.shouldCompress)
    }
    
    func testThatItDoesNotForwardUnsuccessfulResponses() {
        // given
        let expectedCallConfig = "{\"config\":true}"
        let receivedCallConfigExpectation = expectation(description: "Received CallConfig")
        
        sut.requestCallConfig { (callConfig, httpStatusCode) in
            if callConfig == expectedCallConfig, httpStatusCode == 200 {
                receivedCallConfigExpectation.fulfill()
            } else {
                XCTFail()
            }
        }
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        let request = sut.nextRequest()
        XCTAssertEqual(request?.path, "/calls/config/v2")
        
        // when
        let badPayload = [ "error" : "not found" ]
        request?.complete(with: ZMTransportResponse(payload: badPayload as ZMTransportData, httpStatus: 412, transportSessionError: nil))
        
        // when
        let payload = [ "config" : true ]
        request?.complete(with: ZMTransportResponse(payload: payload as ZMTransportData, httpStatus: 200, transportSessionError: nil))

        // then
        XCTAssertTrue(waitForCustomExpectations(withTimeout: 0.5))

    }

    // MARK: - Client List

    func testThatItGenerateClientListRequestAndCallsTheCompletionHandler() {
        // Given
        createSelfClient()

        let conversationId = UUID.create()
        let userId1 = UUID.create()
        let userId2 = UUID.create()
        let clientId1 = "client1"
        let clientId2 = "client2"

        let payload = """
        {
            "missing": {
                "\(userId1.transportString())": ["\(clientId1)", "\(clientId2)"],
                "\(userId2.transportString())": ["\(clientId1)"]
            }
        }
        """

        let receivedClientList = expectation(description: "Received client list")

        // When
        sut.requestClientsList(conversationId: conversationId) { clients in
            // Then
            XCTAssertEqual(clients.count, 3)
            XCTAssertTrue(clients.contains(AVSClient(userId: userId1, clientId: clientId1)))
            XCTAssertTrue(clients.contains(AVSClient(userId: userId1, clientId: clientId2)))
            XCTAssertTrue(clients.contains(AVSClient(userId: userId2, clientId: clientId1)))
            receivedClientList.fulfill()
        }

        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))

        let request = sut.nextRequest()
        XCTAssertNotNil(request)
        XCTAssertEqual(request?.path, "/conversations/\(conversationId.transportString())/otr/messages")

        // When
        request?.complete(with: ZMTransportResponse(payload: payload as ZMTransportData, httpStatus: 412, transportSessionError: nil))

        // Then
        XCTAssertTrue(waitForCustomExpectations(withTimeout: 0.5))
    }

    func testThatItGeneratesOnlyOneClientListRequest() {
        // Given
        createSelfClient()

        // When
        sut.requestClientsList(conversationId: .create()) { _ in }
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))

        // Then
        let request = sut.nextRequest()
        XCTAssertNotNil(request)

        let secondRequest = sut.nextRequest()
        XCTAssertNil(secondRequest)
    }

}
