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


import zmessaging
import ZMTesting
import ZMCMockTransport


// MARK: - Mocks

class MockBackgroundAPNSPingBackStatus: BackgroundAPNSPingBackStatus {
    
    var mockNextNotificationID: UUID?
    var mockNextNotificationEvents: [ZMUpdateEvent] = []
    
    var mockStatus : PingBackStatus = .done {
        didSet {
            status = mockStatus
        }
    }
    var didPerformPingBackVerification: ((EventsWithIdentifier, ZMTransportResponseStatus) -> Void)?
    
    override var hasNotificationIDs: Bool {
        return nil != mockNextNotificationID
    }
    

    override func nextNotificationEventsWithID() -> EventsWithIdentifier? {
        return mockNextNotificationID.map {
            EventsWithIdentifier(events: mockNextNotificationEvents, identifier: $0, isNotice: false)
        }
    }

    override func didPerfomPingBackRequest(_ eventsWithID: EventsWithIdentifier, responseStatus: ZMTransportResponseStatus) {
        didPerformPingBackVerification?(eventsWithID, responseStatus)
    }
    
    var didFetchNoticeNotification: ((EventsWithIdentifier, ZMTransportResponseStatus, [ZMUpdateEvent]) -> Void)?
    
    override var hasNoticeNotificationIDs : Bool {
        return nil != mockNextNotificationID
    }
    
    override func nextNoticeNotificationEventsWithID() -> EventsWithIdentifier? {
        return mockNextNotificationID.map {
            EventsWithIdentifier(events: mockNextNotificationEvents, identifier: $0, isNotice: true)
        }
    }
    
    override func didFetchNoticeNotification(_ eventsWithID: EventsWithIdentifier, responseStatus: ZMTransportResponseStatus, events: [ZMUpdateEvent]) {
        didFetchNoticeNotification?(eventsWithID, responseStatus, events)
    }
}


// MARK: - Tests

class PingBackRequestStrategyTests: MessagingTest {

    var sut: PingBackRequestStrategy!
    var authenticationStatus: MockAuthenticationStatus!
    var pingBackStatus: MockBackgroundAPNSPingBackStatus!
    
    override func setUp() {
        super.setUp()
        authenticationStatus = MockAuthenticationStatus(phase: .authenticated)
        
        pingBackStatus = MockBackgroundAPNSPingBackStatus(
            syncManagedObjectContext: syncMOC,
            authenticationProvider: authenticationStatus
        )
        
        sut = PingBackRequestStrategy(
            managedObjectContext: syncMOC,
            backgroundAPNSPingBackStatus: pingBackStatus,
            authenticationStatus: authenticationStatus
        )
    }

    func testThatItGeneratesARequestWhenThePingBackStatusReturnsANotificationIDAndTheStateIsAuthenticated() {
        // given
        let notificationID = UUID.create()
        pingBackStatus.mockNextNotificationID = notificationID
        pingBackStatus.mockStatus = .pinging
        XCTAssertTrue(pingBackStatus.hasNotificationIDs)
        
        // when
        let request = sut.nextRequest()
        
        // then
        XCTAssertEqual(request?.method, .methodPOST)
        XCTAssertTrue(request!.shouldUseVoipSession)
        XCTAssertEqual(request?.path, "/push/fallback/\(notificationID.transportString())/cancel")
        XCTAssertNil(request?.payload)
    }
    
    func testThatItDoesNotGenerateARequestWhenThePingBackStatusReturnsANotificationIDButTheStatusIsNotPinging() {
        // given
        let notificationID = UUID.create()
        pingBackStatus.mockNextNotificationID = notificationID
        pingBackStatus.mockStatus = .fetchingNotice
        XCTAssertTrue(pingBackStatus.hasNotificationIDs)
        
        // when
        let request = sut.nextRequest()
        
        // then
        XCTAssertNil(request)
    }
    
    func testThatItDoesNotGenerateARequestWhenThePingBackStatusReturnsANotificationIDButTheStateIsUnauthenticated() {
        // given
        authenticationStatus.mockPhase = .unauthenticated
        pingBackStatus.mockNextNotificationID = UUID.create()
        XCTAssertTrue(pingBackStatus.hasNotificationIDs)
        
        // when
        let request = sut.nextRequest()
        
        // then
        XCTAssertNil(request)
    }
    
    func testThatItDoesNotGenerateARequestWhenThePingBackStatusReturnsNoNotificationIDButTheStateIsAuthenticated() {
        // given
        authenticationStatus.mockPhase = .authenticated
        XCTAssertFalse(pingBackStatus.hasNotificationIDs)
        
        // when
        let request = sut.nextRequest()
        
        // then
        XCTAssertNil(request)
    }

    func testThatItCallsDidPerformPingBackRequestWithSuccessOnThePingBackStatusAfterSuccessfullyPerformingThePingBack() {
        // given
        let nextUUID = UUID.create()
        var didPerformPingBackCalled = false
        var receivedEventsWithID: EventsWithIdentifier?
        var receivedStatus: ZMTransportResponseStatus?
        
        pingBackStatus.mockNextNotificationID = nextUUID
        pingBackStatus.mockStatus = .pinging
        pingBackStatus.didPerformPingBackVerification = { eventsWithID, status in
            didPerformPingBackCalled = true
            receivedStatus = status
            receivedEventsWithID = eventsWithID
        }
        
        XCTAssertTrue(pingBackStatus.hasNotificationIDs)
        
        // when
        let response = ZMTransportResponse(payload: nil, httpStatus: 200, transportSessionError: nil)
        let request = sut.nextRequest()
        request?.complete(with: response)
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertTrue(didPerformPingBackCalled)
        XCTAssertEqual(receivedStatus, .success)
        XCTAssertEqual(receivedEventsWithID?.identifier, nextUUID)
    }
    
    func testThatItCallsDidPerformPingBackRequestOnThePingBackStatusAfterFailingPerformingThePingBack_401_ReenqueuesTheEventsAndID() {
        // given
        let nextUUID = UUID.create()
        var didPerformPingBackCallCount = 0
        var receivedEventsWithID: EventsWithIdentifier?
        var receivedStatus: ZMTransportResponseStatus?
        
        pingBackStatus.mockNextNotificationID = nextUUID
        pingBackStatus.mockStatus = .pinging
        pingBackStatus.didPerformPingBackVerification = { eventsWithID, status in
            didPerformPingBackCallCount += 1
            receivedStatus = status
            receivedEventsWithID = eventsWithID
        }
        
        XCTAssertTrue(pingBackStatus.hasNotificationIDs)
        
        // when
        let request = sut.nextRequest()
        request?.complete(with: ZMTransportResponse(payload: nil, httpStatus: 401, transportSessionError: NSError.tryAgainLaterError() as Error))
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertEqual(didPerformPingBackCallCount, 1)
        XCTAssertEqual(receivedStatus, .tryAgainLater)
        XCTAssertEqual(receivedEventsWithID?.identifier, nextUUID)
        
        XCTAssertTrue(pingBackStatus.hasNotificationIDs)
        let nextRequest = sut.nextRequest()
        XCTAssertNotNil(nextRequest)
        nextRequest?.complete(with: ZMTransportResponse(payload: nil, httpStatus: 200, transportSessionError: nil))
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        XCTAssertEqual(didPerformPingBackCallCount, 2)
        XCTAssertEqual(receivedStatus, .success)
        XCTAssertEqual(receivedEventsWithID?.identifier, nextUUID)
    }
    
    func testThatItCallsDidPerformPingBackRequestOnThePingBackStatusAfterFailingPerformingThePingBack_400() {
        // given
        let nextUUID = UUID.create()
        var didPerformPingBackCalled = false
        var receivedEventsWithID: EventsWithIdentifier?
        var receivedStatus: ZMTransportResponseStatus?
        
        pingBackStatus.mockNextNotificationID = nextUUID
        pingBackStatus.mockStatus = .pinging
        pingBackStatus.didPerformPingBackVerification = { eventsWithID, status in
            didPerformPingBackCalled = true
            receivedStatus = status
            receivedEventsWithID = eventsWithID
        }
        
        XCTAssertTrue(pingBackStatus.hasNotificationIDs)
        
        // when
        let response = ZMTransportResponse(payload: nil, httpStatus: 400, transportSessionError: nil)
        let request = sut.nextRequest()
        request?.complete(with: response)
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertTrue(didPerformPingBackCalled)
        XCTAssertEqual(receivedStatus, .permanentError)
        XCTAssertEqual(receivedEventsWithID?.identifier, nextUUID)
    }
}
