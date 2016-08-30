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
    
    var mockNextNotificationID: NSUUID?
    var mockNextNotificationEvents: [ZMUpdateEvent] = []
    
    var mockStatus : PingBackStatus = .Done {
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

    override func didPerfomPingBackRequest(eventsWithID: EventsWithIdentifier, responseStatus: ZMTransportResponseStatus) {
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
    
    override func didFetchNoticeNotification(eventsWithID: EventsWithIdentifier, responseStatus: ZMTransportResponseStatus, events: [ZMUpdateEvent]) {
        didFetchNoticeNotification?(eventsWithID, responseStatus, events)
    }
}


// MARK: - Tests

class PingBackRequestStrategyTests: MessagingTest {

    var sut: PingBackRequestStrategy!
    var authenticationStatus: MockAuthenticationStatus!
    var pingBackStatus: MockBackgroundAPNSPingBackStatus!
    var notificationDispatcher: LocalNotificationDispatchType!
    
    override func setUp() {
        super.setUp()
        notificationDispatcher = MockNotificationDispatcher()
        authenticationStatus = MockAuthenticationStatus(phase: .Authenticated)
        
        pingBackStatus = MockBackgroundAPNSPingBackStatus(
            syncManagedObjectContext: syncMOC,
            authenticationProvider: authenticationStatus,
            localNotificationDispatcher: notificationDispatcher
        )
        
        sut = PingBackRequestStrategy(
            managedObjectContext: syncMOC,
            backgroundAPNSPingBackStatus: pingBackStatus,
            authenticationStatus: authenticationStatus
        )
    }

    func testThatItGeneratesARequestWhenThePingBackStatusReturnsANotificationIDAndTheStateIsAuthenticated() {
        // given
        let notificationID = NSUUID.createUUID()
        pingBackStatus.mockNextNotificationID = notificationID
        pingBackStatus.mockStatus = .Pinging
        XCTAssertTrue(pingBackStatus.hasNotificationIDs)
        
        // when
        let request = sut.nextRequest()
        
        // then
        XCTAssertEqual(request?.method, .MethodPOST)
        XCTAssertTrue(request!.shouldUseVoipSession)
        XCTAssertEqual(request?.path, "/push/fallback/\(notificationID.transportString())/cancel")
        XCTAssertNil(request?.payload)
    }
    
    func testThatItDoesNotGenerateARequestWhenThePingBackStatusReturnsANotificationIDButTheStatusIsNotPinging() {
        // given
        let notificationID = NSUUID.createUUID()
        pingBackStatus.mockNextNotificationID = notificationID
        pingBackStatus.mockStatus = .FetchingNotice
        XCTAssertTrue(pingBackStatus.hasNotificationIDs)
        
        // when
        let request = sut.nextRequest()
        
        // then
        XCTAssertNil(request)
    }
    
    func testThatItDoesNotGenerateARequestWhenThePingBackStatusReturnsANotificationIDButTheStateIsUnauthenticated() {
        // given
        authenticationStatus.mockPhase = .Unauthenticated
        pingBackStatus.mockNextNotificationID = NSUUID.createUUID()
        XCTAssertTrue(pingBackStatus.hasNotificationIDs)
        
        // when
        let request = sut.nextRequest()
        
        // then
        XCTAssertNil(request)
    }
    
    func testThatItDoesNotGenerateARequestWhenThePingBackStatusReturnsNoNotificationIDButTheStateIsAuthenticated() {
        // given
        authenticationStatus.mockPhase = .Authenticated
        XCTAssertFalse(pingBackStatus.hasNotificationIDs)
        
        // when
        let request = sut.nextRequest()
        
        // then
        XCTAssertNil(request)
    }

    func testThatItCallsDidPerformPingBackRequestWithSuccessOnThePingBackStatusAfterSuccessfullyPerformingThePingBack() {
        // given
        let nextUUID = NSUUID.createUUID()
        var didPerformPingBackCalled = false
        var receivedEventsWithID: EventsWithIdentifier?
        var receivedStatus: ZMTransportResponseStatus?
        
        pingBackStatus.mockNextNotificationID = nextUUID
        pingBackStatus.mockStatus = .Pinging
        pingBackStatus.didPerformPingBackVerification = { eventsWithID, status in
            didPerformPingBackCalled = true
            receivedStatus = status
            receivedEventsWithID = eventsWithID
        }
        
        XCTAssertTrue(pingBackStatus.hasNotificationIDs)
        
        // when
        let response = ZMTransportResponse(payload: nil, HTTPstatus: 200, transportSessionError: nil)
        let request = sut.nextRequest()
        request?.completeWithResponse(response)
        XCTAssertTrue(waitForAllGroupsToBeEmptyWithTimeout(0.5))
        
        // then
        XCTAssertTrue(didPerformPingBackCalled)
        XCTAssertEqual(receivedStatus, .Success)
        XCTAssertEqual(receivedEventsWithID?.identifier, nextUUID)
    }
    
    func testThatItCallsDidPerformPingBackRequestOnThePingBackStatusAfterFailingPerformingThePingBack_401_ReenqueuesTheEventsAndID() {
        // given
        let nextUUID = NSUUID.createUUID()
        var didPerformPingBackCallCount = 0
        var receivedEventsWithID: EventsWithIdentifier?
        var receivedStatus: ZMTransportResponseStatus?
        
        pingBackStatus.mockNextNotificationID = nextUUID
        pingBackStatus.mockStatus = .Pinging
        pingBackStatus.didPerformPingBackVerification = { eventsWithID, status in
            didPerformPingBackCallCount += 1
            receivedStatus = status
            receivedEventsWithID = eventsWithID
        }
        
        XCTAssertTrue(pingBackStatus.hasNotificationIDs)
        
        // when
        let request = sut.nextRequest()
        request?.completeWithResponse(ZMTransportResponse(payload: nil, HTTPstatus: 401, transportSessionError: .tryAgainLaterError()))
        XCTAssertTrue(waitForAllGroupsToBeEmptyWithTimeout(0.5))
        
        // then
        XCTAssertEqual(didPerformPingBackCallCount, 1)
        XCTAssertEqual(receivedStatus, .TryAgainLater)
        XCTAssertEqual(receivedEventsWithID?.identifier, nextUUID)
        
        XCTAssertTrue(pingBackStatus.hasNotificationIDs)
        let nextRequest = sut.nextRequest()
        XCTAssertNotNil(nextRequest)
        nextRequest?.completeWithResponse(ZMTransportResponse(payload: nil, HTTPstatus: 200, transportSessionError: nil))
        XCTAssertTrue(waitForAllGroupsToBeEmptyWithTimeout(0.5))
        
        XCTAssertEqual(didPerformPingBackCallCount, 2)
        XCTAssertEqual(receivedStatus, .Success)
        XCTAssertEqual(receivedEventsWithID?.identifier, nextUUID)
    }
    
    func testThatItCallsDidPerformPingBackRequestOnThePingBackStatusAfterFailingPerformingThePingBack_400() {
        // given
        let nextUUID = NSUUID.createUUID()
        var didPerformPingBackCalled = false
        var receivedEventsWithID: EventsWithIdentifier?
        var receivedStatus: ZMTransportResponseStatus?
        
        pingBackStatus.mockNextNotificationID = nextUUID
        pingBackStatus.mockStatus = .Pinging
        pingBackStatus.didPerformPingBackVerification = { eventsWithID, status in
            didPerformPingBackCalled = true
            receivedStatus = status
            receivedEventsWithID = eventsWithID
        }
        
        XCTAssertTrue(pingBackStatus.hasNotificationIDs)
        
        // when
        let response = ZMTransportResponse(payload: nil, HTTPstatus: 400, transportSessionError: nil)
        let request = sut.nextRequest()
        request?.completeWithResponse(response)
        XCTAssertTrue(waitForAllGroupsToBeEmptyWithTimeout(0.5))
        
        // then
        XCTAssertTrue(didPerformPingBackCalled)
        XCTAssertEqual(receivedStatus, .PermanentError)
        XCTAssertEqual(receivedEventsWithID?.identifier, nextUUID)
    }
}
