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

class OperationLoopNewRequestObserver {
    
    var notifications = [Notification]()
    fileprivate var notificationCenter = NotificationCenter.default
    fileprivate var newRequestNotification = "ZMOperationLoopNewRequestAvailable"
    
    init() {
        notificationCenter.addObserver(forName: Notification.Name(rawValue: newRequestNotification), object: nil, queue: .main) { [weak self] note in
         self?.notifications.append(note)
        }
    }
    
    deinit {
        notificationCenter.removeObserver(self)
    }
}


@objc class MockAuthenticationProvider: NSObject, AuthenticationStatusProvider {
    var mockAuthenticationPhase: ZMAuthenticationPhase = .authenticated
    
    var currentPhase: ZMAuthenticationPhase {
        return mockAuthenticationPhase
    }
}

@objc class FakeGroupQueue : NSObject, ZMSGroupQueue {
    
    var dispatchGroup : ZMSDispatchGroup! {
        return nil
    }
    
    func performGroupedBlock(_ block : @escaping () -> Void) {
        block()
    }
    
}


// MARK: - Tests

class EventsWithIdentifierTests: ZMTBaseTest {
    
    var sut: EventsWithIdentifier!
    var identifier: UUID!
    var events: [ZMUpdateEvent]!
    
    func messageAddPayload() -> [String : Any] {
        return [
            "conversation": UUID.create().transportString(),
            "time": Date(),
            "data": [
                "content": "saf",
                "nonce": UUID.create().transportString(),
            ],
            "from": UUID.create().transportString(),
            "type": "conversation.message-add"
        ];
    }
    
    override func setUp() {
        super.setUp()
        identifier = UUID.create()
        let pushChannelData :  [String : Any] = [
            "id": identifier.transportString(),
            "payload": [messageAddPayload(), messageAddPayload()]
        ]
        
        events = ZMUpdateEvent.eventsArray(fromPushChannelData: pushChannelData as ZMTransportData)
        sut = EventsWithIdentifier(events: events, identifier: identifier, isNotice:true)
    }
    
    func testThatItCreatesTheEventsWithIdentifierCorrectly() {
        // then
        XCTAssertEqual(identifier, sut.identifier)
        XCTAssertEqual(events, sut.events!)
        XCTAssertTrue(sut.isNotice)
    }
    
    func testThatItFiltersThePreexistingEvent() {
        // given
        guard let preexistingNonce = events.first?.messageNonce() else { return XCTFail() }
        
        // when
        let filteredEventsWithID = sut.filteredWithoutPreexistingNonces([preexistingNonce])
        
        // then
        guard let event = filteredEventsWithID.events?.first else { return XCTFail() }
        XCTAssertEqual(filteredEventsWithID.events?.count, 1)
        XCTAssertNotEqual(event.messageNonce(), preexistingNonce)
        XCTAssertEqual(filteredEventsWithID.identifier, sut.identifier)
        XCTAssertEqual(filteredEventsWithID.isNotice, sut.isNotice)
        XCTAssertEqual(event, events.last)
    }
    
}

class BackgroundAPNSPingBackStatusTests: MessagingTest {

    var sut: BackgroundAPNSPingBackStatus!
    var observer: OperationLoopNewRequestObserver!
    var authenticationProvider: MockAuthenticationProvider!
    
    override func setUp() {
        super.setUp()
        
        BackgroundActivityFactory.sharedInstance().mainGroupQueue = FakeGroupQueue()
        authenticationProvider = MockAuthenticationProvider()

        sut = BackgroundAPNSPingBackStatus(
            syncManagedObjectContext: syncMOC,
            authenticationProvider: authenticationProvider
        )
        observer = OperationLoopNewRequestObserver()
    }
    
    override func tearDown() {
        BackgroundActivityFactory.tearDownInstance()
        super.tearDown()
    }

    func testThatItSetsTheNotificationID() {
        // given
        XCTAssertFalse(sut.hasNotificationIDs)
        let notificationID = UUID.create()
        
        // when
        sut.didReceiveVoIPNotification(createEventsWithID(notificationID))
        
        // then
        XCTAssertTrue(sut.hasNotificationIDs)
        XCTAssertEqual(sut.status, PingBackStatus.pinging)
        
        // when
        let notificationIDToPing = sut.nextNotificationEventsWithID()?.identifier
        
        // then
        XCTAssertEqual(notificationID, notificationIDToPing)
        XCTAssertNil(sut.nextNotificationEventsWithID())
        XCTAssertFalse(sut.hasNotificationIDs)
    }
    
    func testThatItReAddsTheNotificationIDWhenReceiving_TryAgainLater() {
        // given
        XCTAssertFalse(sut.hasNotificationIDs)
        let notificationID = UUID.create()
        let eventsWithID = createEventsWithID(notificationID)
        
        // when
        var callcount = 0
        let handler: (ZMPushPayloadResult, [ZMUpdateEvent]) -> Void = { _ in callcount += 1 }
        sut.didReceiveVoIPNotification(eventsWithID, handler: handler)
        
        // then
        XCTAssertTrue(sut.hasNotificationIDs)
        XCTAssertEqual(sut.status, PingBackStatus.pinging)
        
        // when
        guard let notificationEventsWithIDToPing = sut.nextNotificationEventsWithID() else { return XCTFail("No events with identifier") }
        
        // then
        XCTAssertEqual(notificationID, notificationEventsWithIDToPing.identifier)
        XCTAssertNil(sut.nextNotificationEventsWithID())
        XCTAssertFalse(sut.hasNotificationIDs)
        
        // when
        sut.didPerfomPingBackRequest(notificationEventsWithIDToPing, responseStatus: .tryAgainLater)
        
        // then
        XCTAssertTrue(sut.hasNotificationIDs)
        XCTAssertEqual(sut.status, PingBackStatus.pinging)
        
        let nextEventsWithID = sut.nextNotificationEventsWithID()
        
        // then
        XCTAssertEqual(notificationID, nextEventsWithID?.identifier)
        
        // when
        sut.didPerfomPingBackRequest(notificationEventsWithIDToPing, responseStatus: .success)
        XCTAssertEqual(callcount, 1)
        XCTAssertNil(sut.nextNotificationEventsWithID())
    }
    
    func testThatItRemovesTheIDWhenThePingBackFailed() {
        // given
        XCTAssertFalse(sut.hasNotificationIDs)
        let notificationID = UUID.create()
        let eventsWithID = createEventsWithID(notificationID)
        
        // when
        sut.didReceiveVoIPNotification(eventsWithID)
        
        // then
        XCTAssertTrue(sut.hasNotificationIDs)
        XCTAssertEqual(sut.status, PingBackStatus.pinging)
        
        // when
        guard let notificationEventsWithIDToPing = sut.nextNotificationEventsWithID() else { return XCTFail("No events with identifier") }
        
        // then
        XCTAssertEqual(notificationID, notificationEventsWithIDToPing.identifier)
        XCTAssertNil(sut.nextNotificationEventsWithID())
        XCTAssertFalse(sut.hasNotificationIDs)
        
        // when
        sut.didPerfomPingBackRequest(notificationEventsWithIDToPing, responseStatus: .permanentError)
        
        // then
        XCTAssertFalse(sut.hasNotificationIDs)
        XCTAssertEqual(sut.status, PingBackStatus.done)
    }
    
    func testThatItPostsNewRequestsAvailableNotificationWhenAddingANotificationID() {
        // when
        sut.didReceiveVoIPNotification(createEventsWithID())
        
        // then
        XCTAssertEqual(observer.notifications.count, 1)
    }
    
    func testThatItDoesNotCallTheHandlerAfterPingBackRequestCompletedUnsuccessfully_TryAgain_Until_Sucess() {
        // given
        let eventsWithID = createEventsWithID()
        let expectation = self.expectation(description: "It doesn't call the completion handler")
        
        // expect
        var callcount = 0
        sut.didReceiveVoIPNotification(eventsWithID) {
            callcount += 1
            XCTAssertEqual($0.0, ZMPushPayloadResult.success)
            expectation.fulfill()
        }
        
        // when
        sut.didPerfomPingBackRequest(eventsWithID, responseStatus: .tryAgainLater)
        
        // then
        XCTAssertEqual(callcount, 0)
        
        // when
        sut.didPerfomPingBackRequest(eventsWithID, responseStatus: .success)
        XCTAssertTrue(waitForCustomExpectations(withTimeout: 0.5))
        
        // then
        XCTAssertEqual(callcount, 1)
    }
    
    func testThatItCallsTheHandlerAfterPingBackRequestCompletedSuccessfully() {
        checkThatItCallsTheHandlerAfterPingBackRequestCompleted(.success)
    }
    
    func testThatItCallsTheHandlerAfterPingBackRequestCompletedUnsuccessfully_Permanent() {
        checkThatItCallsTheHandlerAfterPingBackRequestCompleted(.permanentError)
    }
    
    func checkThatItCallsTheHandlerAfterPingBackRequestCompleted(_ status: ZMTransportResponseStatus) {
        // given
        let eventsWithID = createEventsWithID()
        let expectation = self.expectation(description: "It calls the completion handler")
        
        // expect
        sut.didReceiveVoIPNotification(eventsWithID) { result in
            let expectedResult : ZMPushPayloadResult = (status == .success) ? .success : .failure
            XCTAssertEqual(result.0, expectedResult)
            XCTAssertEqual(result.1, eventsWithID.events!)
            expectation.fulfill()
        }
        
        // when
        sut.didPerfomPingBackRequest(eventsWithID, responseStatus: status)
        
        // then
        XCTAssertTrue(waitForCustomExpectations(withTimeout: 0.5))
    }
    
    func testThatItDoesSetTheStatusToDoneIfThereAreNoMoreNotifactionIDs() {
        
        // given
        let eventsWithID = createEventsWithID()
        XCTAssertEqual(sut.status, PingBackStatus.done)
        sut.didReceiveVoIPNotification(eventsWithID)
        XCTAssertEqual(sut.status, PingBackStatus.pinging)
        
        // when
        _ = sut.nextNotificationEventsWithID()
        XCTAssertFalse(sut.hasNotificationIDs)

        sut.didPerfomPingBackRequest(eventsWithID, responseStatus: .success)
        
        // then
        XCTAssertFalse(sut.hasNotificationIDs)
        XCTAssertEqual(sut.status, PingBackStatus.done)
    }
    
    func testThatItRemovesEventsFromIdentifierEventsMappingAfterSuccesfullyPerformingPingBack() {
        // given
        let eventsWithIDs = createEventsWithID()

        // when
        sut.didReceiveVoIPNotification(eventsWithIDs)
        guard let currentEvents = sut.eventsWithHandlerByNotificationID[eventsWithIDs.identifier]?.events else { return XCTFail() }
        
        // then
        XCTAssertTrue(sut.hasNotificationIDs)
        XCTAssertEqual(currentEvents, eventsWithIDs.events!)
        
        // when
        sut.didPerfomPingBackRequest(eventsWithIDs, responseStatus: .success)
        
        // then
        XCTAssertNil(sut.eventsWithHandlerByNotificationID[eventsWithIDs.identifier])
    }
    
    func testThatItRemovesEventsWithHandlerFromIdentifierEventsMappingAfterFailingToPerformPingBack() {
        // given
        let eventsWithIDs = createEventsWithID()
        let expectedIdentifier = eventsWithIDs.identifier
        
        // when
        sut.didReceiveVoIPNotification(eventsWithIDs)
        guard let currentEventsWithHandler = sut.eventsWithHandlerByNotificationID[expectedIdentifier] else { return XCTFail() }
        
        // then
        XCTAssertTrue(sut.hasNotificationIDs)
        XCTAssertEqual(currentEventsWithHandler.events!, eventsWithIDs.events!)
        
        // when
        sut.didPerfomPingBackRequest(eventsWithIDs, responseStatus: .temporaryError)
        
        // then
        XCTAssertNil(sut.eventsWithHandlerByNotificationID[expectedIdentifier])
    }
    
    func testThatItDoesNotRemoveTheIdentifierFromTheEventsIdentifierMappingWhenPingBackForOtherIDsFinishes() {
        // given
        let firstEventsWithIDs = createEventsWithID()
        let secondEventsWithIDs = createEventsWithID()
        let thirdEventsWithIDs = createEventsWithID()
        let expectedIdentifier = firstEventsWithIDs.identifier
        
        // when
        [firstEventsWithIDs, secondEventsWithIDs, thirdEventsWithIDs].forEach(sut.didReceiveVoIPNotification)
        guard let currentEvents = sut.eventsWithHandlerByNotificationID[expectedIdentifier]?.events else { return XCTFail() }
        
        // then
        XCTAssertEqual(sut.eventsWithHandlerByNotificationID.keys.count, 3)
        XCTAssertTrue(sut.hasNotificationIDs)
        XCTAssertEqual(currentEvents, firstEventsWithIDs.events!)
        
        // when
        sut.didPerfomPingBackRequest(secondEventsWithIDs, responseStatus: .success)
        sut.didPerfomPingBackRequest(thirdEventsWithIDs, responseStatus: .temporaryError)
        
        // then
        guard let finalEvents = sut.eventsWithHandlerByNotificationID[expectedIdentifier]?.events else { return XCTFail() }
        XCTAssertEqual(finalEvents, firstEventsWithIDs.events!)
    }
    
    func testThatItStartsABackgroundActivityWhenTheStatusIsAuthenticated() {
        // when
        sut.didReceiveVoIPNotification(createEventsWithID())
        XCTAssertTrue(sut.hasNotificationIDs)
        
        // then
        XCTAssertNotNil(sut.backgroundActivity)
    }
    
    func testThatItDoesNotStartABackgroundActivityWhenTheStatusIsNotAuthenticated() {
        // given
        authenticationProvider.mockAuthenticationPhase = .unauthenticated
        
        // when
        sut.didReceiveVoIPNotification(createEventsWithID())
        XCTAssertTrue(sut.hasNotificationIDs)
        
        // then
        XCTAssertNil(sut.backgroundActivity)
    }
    
    func testThatItEndsTheBackgroundActivityWhenRequestCompletesSuccessfully() {
        checkThatItEndsTheBackgroundActivityAfterThePingBackCompleted(true)
    }
    
    func testThatItEndsTheBackgroundActivityWhenRequestCompletesUnsuccessfully() {
        checkThatItEndsTheBackgroundActivityAfterThePingBackCompleted(false)
    }
    
    func checkThatItEndsTheBackgroundActivityAfterThePingBackCompleted(_ successfully: Bool) {
        // given
        let eventsWithID = createEventsWithID()
        sut.didReceiveVoIPNotification(eventsWithID)
        XCTAssertTrue(sut.hasNotificationIDs)
        XCTAssertNotNil(sut.backgroundActivity)
        
        // when
        let nextEventsWithID = sut.nextNotificationEventsWithID()!
        XCTAssertEqual(nextEventsWithID.identifier, eventsWithID.identifier)
        sut.didPerfomPingBackRequest(nextEventsWithID, responseStatus: successfully ? .success : .temporaryError)
        
        // then
        XCTAssertNil(sut.backgroundActivity)
    }
    
    func checkThatItEndsTheBackgroundActivityAfterTheFetchCompleted(_ fetchSuccess: Bool) {
        // given
        let eventsWithID = createEventsWithID(isNotice: true)
        sut.didReceiveVoIPNotification(eventsWithID)
        XCTAssertFalse(sut.hasNotificationIDs)
        XCTAssertTrue(sut.hasNoticeNotificationIDs)
        XCTAssertEqual(sut.status, PingBackStatus.fetchingNotice)
        
        XCTAssertNotNil(sut.backgroundActivity)
        
        // when
        let nextNoticeEventsWithID = sut.nextNoticeNotificationEventsWithID()!
        
        sut.didFetchNoticeNotification(nextNoticeEventsWithID, responseStatus: fetchSuccess ? .success : .temporaryError, events:[])
        XCTAssertEqual(sut.status, PingBackStatus.done)
        
        // and when
        let nextID = sut.nextNotificationEventsWithID()
        XCTAssertNil(nextID)
        
        // then
        XCTAssertNil(sut.backgroundActivity)
    }
    
    func testThatItEndsTheBackgroundActivityAfterTheFetchCompletedSuccessfully() {
        checkThatItEndsTheBackgroundActivityAfterTheFetchCompleted(true)
    }
    
    func testThatItEndsTheBackgroundActivityAfterTheFetchCompletedUnsuccessfully() {
        checkThatItEndsTheBackgroundActivityAfterTheFetchCompleted(false)
    }
    

    func simulateFetchNoticeAndPingback() {
        let nextNoticeEventsWithID = sut.nextNoticeNotificationEventsWithID()!
        sut.didFetchNoticeNotification(nextNoticeEventsWithID, responseStatus: .success, events:[])
        
    }
    
    func simulatePingBack() -> UUID {
        let nextEventsWithID = sut.nextNotificationEventsWithID()!
        sut.didPerfomPingBackRequest(nextEventsWithID, responseStatus: .success)
        return nextEventsWithID.identifier
    }
    
    func checkThatItUpdatesStatusToFetchingWhenFirstAndNextNotificationAreNotice(_ nextIsNotice: Bool) {
       
        // given
        let eventsWithID1 = createEventsWithID(isNotice: true)
        let eventsWithID2 = createEventsWithID(isNotice: nextIsNotice)

        sut.didReceiveVoIPNotification(eventsWithID1)
        sut.didReceiveVoIPNotification(eventsWithID2)

        XCTAssertTrue(sut.hasNoticeNotificationIDs)
        XCTAssertEqual(sut.status, PingBackStatus.fetchingNotice)
        
        XCTAssertNotNil(sut.backgroundActivity)
        
        // when
        simulateFetchNoticeAndPingback()

        // then
        if nextIsNotice {
            XCTAssertFalse(sut.hasNotificationIDs)
            XCTAssertEqual(sut.status, PingBackStatus.fetchingNotice)
        } else {
            XCTAssertTrue(sut.hasNotificationIDs)
            XCTAssertEqual(sut.status, PingBackStatus.pinging)
        }
        XCTAssertNotNil(sut.backgroundActivity)

        // and when
        if nextIsNotice {
            simulateFetchNoticeAndPingback()
        } else {
            _ = simulatePingBack()
        }
        
        // then
        XCTAssertNil(sut.backgroundActivity)
        XCTAssertEqual(sut.status, PingBackStatus.done)
    }
    
    func testThatItUpdatesStatusToFetchingWhenFirstAndNextNotificationAreNoticeNextIsNotice() {
        checkThatItUpdatesStatusToFetchingWhenFirstAndNextNotificationAreNotice(true)
    }
    
    func testThatItUpdatesStatusToFetchingWhenFirstAndNextNotificationAreNoticeNextIsNonNotice() {
        checkThatItUpdatesStatusToFetchingWhenFirstAndNextNotificationAreNotice(false)
    }
    
    func checkThatItUpdatesStatusToFetchingWhenFirstIsNonNoticeAndNextNotification(_ nextIsNotice: Bool) {
        
        // given
        let eventsWithID1 = createEventsWithID(isNotice: false)
        let eventsWithID2 = createEventsWithID(isNotice: nextIsNotice)
        
        sut.didReceiveVoIPNotification(eventsWithID1)
        sut.didReceiveVoIPNotification(eventsWithID2)
        
        XCTAssertTrue(sut.hasNotificationIDs)
        XCTAssertEqual(sut.status, PingBackStatus.pinging)
        
        XCTAssertNotNil(sut.backgroundActivity)
        
        // when
        _ = simulatePingBack()
        
        // then
        if nextIsNotice {
            XCTAssertTrue(sut.hasNoticeNotificationIDs)
            XCTAssertEqual(sut.status, PingBackStatus.fetchingNotice)
        } else {
            XCTAssertFalse(sut.hasNoticeNotificationIDs)
            XCTAssertEqual(sut.status, PingBackStatus.pinging)
        }
        XCTAssertNotNil(sut.backgroundActivity)
        
        // and when
        if nextIsNotice {
            simulateFetchNoticeAndPingback()
        } else {
            _ = simulatePingBack()
        }
        
        // then
        XCTAssertNil(sut.backgroundActivity)
        XCTAssertEqual(sut.status, PingBackStatus.done)
    }
    
    func testThatItUpdatesStatusToFetchingWhenFirstIsNonNoticeAndNextNotificationIsNotice() {
        checkThatItUpdatesStatusToFetchingWhenFirstIsNonNoticeAndNextNotification(true)
    }
    
    func testThatItUpdatesStatusToFetchingWhenFirstIsNonNoticeAndNextNotificationIsNotNotice() {
        checkThatItUpdatesStatusToFetchingWhenFirstIsNonNoticeAndNextNotification(false)
    }

    func testThatItTakesTheOrderFromTheNotificationIDsArray() {
        // given
        let eventsWithID1 = createEventsWithID(isNotice: true)
        let eventsWithID2 = createEventsWithID(isNotice: false)
        let eventsWithID3 = createEventsWithID(isNotice: true)

        sut.didReceiveVoIPNotification(eventsWithID1)
        sut.didReceiveVoIPNotification(eventsWithID2)
        sut.didReceiveVoIPNotification(eventsWithID3)

        XCTAssertEqual(sut.status, PingBackStatus.fetchingNotice)

        // when
        simulateFetchNoticeAndPingback()
        XCTAssertEqual(sut.status, PingBackStatus.pinging)

        _ = simulatePingBack()
        XCTAssertEqual(sut.status, PingBackStatus.fetchingNotice)

        simulateFetchNoticeAndPingback()
        XCTAssertEqual(sut.status, PingBackStatus.done)
    }

}



// MARK: - Helper

extension BackgroundAPNSPingBackStatus {
    func didReceiveVoIPNotification(_ eventsWithID: EventsWithIdentifier) {
        didReceiveVoIPNotification(eventsWithID, handler: { _ in })
    }
}

extension BackgroundAPNSPingBackStatusTests {
    func createEventsWithID(_ identifier: UUID = UUID.create(), events: [ZMUpdateEvent] = [ZMUpdateEvent()], isNotice: Bool = false) -> EventsWithIdentifier {
        return EventsWithIdentifier(events: events, identifier: identifier, isNotice: isNotice)
    }
}
