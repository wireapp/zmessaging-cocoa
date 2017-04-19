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


@testable import WireSyncEngine
import WireTesting
import WireMockTransport


// MARK: - Mocks

class OperationLoopNewRequestObserver {
    
    var token : NSObjectProtocol?
    var notifications = [Notification]()
    fileprivate var notificationCenter = NotificationCenter.default
    fileprivate var newRequestNotification = "RequestAvailableNotification"
    
    init() {
        token = notificationCenter.addObserver(forName: Notification.Name(rawValue: newRequestNotification), object: nil, queue: .main) { [weak self] note in
            self?.notifications.append(note)
        }
    }
    
    deinit {
        notifications.removeAll()
        if let token = token {
            notificationCenter.removeObserver(token)
        }
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
        BackgroundActivityFactory.sharedInstance().application = UIApplication.shared
        authenticationProvider = MockAuthenticationProvider()

        sut = BackgroundAPNSPingBackStatus(
            syncManagedObjectContext: syncMOC,
            authenticationProvider: authenticationProvider
        )
        observer = OperationLoopNewRequestObserver()
    }
    
    override func tearDown() {
        observer = nil
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
        XCTAssertEqual(sut.status, PingBackStatus.inProgress)
        
        // when
        let notificationIDToPing = sut.nextNotificationEventsWithID()?.identifier
        XCTAssertEqual(notificationID, notificationIDToPing)
        XCTAssertNotNil(sut.nextNotificationEventsWithID())
        XCTAssertTrue(sut.hasNotificationIDs)
    }

    func testThatItRemovesTheNotificationIdWhenTheFetchCompleted_NoHasMore() {
        checkThatItRemovesTheNotificationIdWhenItReceivesAResponse(hasMore: false)
    }

    func testThatItRemovesTheNotificationIdWhenTheFetchCompleted_HasMore() {
        checkThatItRemovesTheNotificationIdWhenItReceivesAResponse(hasMore: true)
    }

    func checkThatItRemovesTheNotificationIdWhenItReceivesAResponse(hasMore: Bool) {
        // given
        XCTAssertFalse(sut.hasNotificationIDs)
        let eventsWithId = createEventsWithID(.create())

        // when
        sut.didReceiveVoIPNotification(eventsWithId)

        // then
        XCTAssertTrue(sut.hasNotificationIDs)
        XCTAssertEqual(sut.status, PingBackStatus.inProgress)

        // when
        sut.didReceive(encryptedEvents: [], originalEvents: eventsWithId, hasMore: hasMore)

        // then
        XCTAssertNil(sut.nextNotificationEventsWithID())
        XCTAssertFalse(sut.hasNotificationIDs)
    }
    
    func testThatItRemovesTheNotificationIdWhenItFails() {
        // given
        XCTAssertFalse(sut.hasNotificationIDs)
        let notificationID = UUID.create()
        let eventsWithID = createEventsWithID(notificationID)
        
        // when
        var callcount = 0
        let handler: (ZMPushPayloadResult, [ZMUpdateEvent]) -> Void = { result in
            XCTAssertEqual(result.0, .failure)
            XCTAssertEqual(result.1, [])
            callcount += 1
        }
        sut.didReceiveVoIPNotification(eventsWithID, handler: handler)
        
        // then
        XCTAssertTrue(sut.hasNotificationIDs)
        XCTAssertEqual(sut.status, PingBackStatus.inProgress)
        
        // when
        guard let notificationEventsWithIDToPing = sut.nextNotificationEventsWithID() else { return XCTFail("No events with identifier") }
        
        // then
        XCTAssertEqual(notificationID, notificationEventsWithIDToPing.identifier)
        XCTAssertNotNil(sut.nextNotificationEventsWithID())
        XCTAssertTrue(sut.hasNotificationIDs)
        
        // when
        sut.didFailDownloading(originalEvents: notificationEventsWithIDToPing)
        
        // then
        XCTAssertFalse(sut.hasNotificationIDs)
        XCTAssertEqual(sut.status, PingBackStatus.done)
        XCTAssertEqual(callcount, 1)
        XCTAssertNil(sut.nextNotificationEventsWithID())
    }

    func testThatItDoesNotChangeTheStatusOrRemoveTheHandlerWhenTheItHasMoreEventsToFetch() {
        // given
        let eventsWithID = createEventsWithID()

        // when
        var receivedEvents = [(ZMPushPayloadResult, [ZMUpdateEvent])]()
        sut.didReceiveVoIPNotification(eventsWithID) {
            receivedEvents.append($0)
        }

        guard let currentEvents = sut.eventsWithHandlerByNotificationID[eventsWithID.identifier]?.events else { return XCTFail() }

        // then
        XCTAssertEqual(currentEvents, eventsWithID.events!)

        // when
        sut.didReceive(encryptedEvents: eventsWithID.events!, originalEvents: eventsWithID, hasMore: true)

        // then
        XCTAssertNotNil(sut.eventsWithHandlerByNotificationID[eventsWithID.identifier])
        XCTAssertNotNil(sut.backgroundActivity)
        guard let firstResult = receivedEvents.first else { return XCTFail("Did not receive first batch of events") }
        XCTAssertEqual(firstResult.0, ZMPushPayloadResult.success)
        XCTAssertEqual(firstResult.1, eventsWithID.events!)
        XCTAssertEqual(sut.status, PingBackStatus.inProgress)

        // when
        let otherEvents = [ZMUpdateEvent(), ZMUpdateEvent()]
        sut.didReceive(encryptedEvents: otherEvents, originalEvents: eventsWithID, hasMore: false)

        // then
        guard let secondResult = receivedEvents.last else { return XCTFail("Did not receive first batch of events") }
        XCTAssertEqual(secondResult.0, ZMPushPayloadResult.success)
        XCTAssertEqual(secondResult.1, otherEvents)
        XCTAssertNil(sut.eventsWithHandlerByNotificationID[eventsWithID.identifier])
        XCTAssertNil(sut.backgroundActivity)
        XCTAssertEqual(sut.status, PingBackStatus.done)
    }

    func testThatItRemovesTheIDWhenTheFetchFailed() {
        // given
        XCTAssertFalse(sut.hasNotificationIDs)
        let notificationID = UUID.create()
        let eventsWithID = createEventsWithID(notificationID)
        
        // when
        sut.didReceiveVoIPNotification(eventsWithID)
        
        // then
        XCTAssertTrue(sut.hasNotificationIDs)
        XCTAssertEqual(sut.status, PingBackStatus.inProgress)
        
        // when
        guard let notificationEventsWithIDToPing = sut.nextNotificationEventsWithID() else { return XCTFail("No events with identifier") }
        
        // then
        XCTAssertEqual(notificationID, notificationEventsWithIDToPing.identifier)
        XCTAssertTrue(sut.hasNotificationIDs)
        
        // when
        sut.didFailDownloading(originalEvents: notificationEventsWithIDToPing)

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
            let expectedResult: ZMPushPayloadResult = (status == .success) ? .success : .failure
            let expectedEvents = (status == .success) ? eventsWithID.events! : []
            XCTAssertEqual(result.0, expectedResult)
            XCTAssertEqual(result.1, expectedEvents)
            expectation.fulfill()
        }

        // when
        if status == .success {
            sut.didReceive(encryptedEvents: eventsWithID.events!, originalEvents: eventsWithID, hasMore: false)
        } else {
            sut.didFailDownloading(originalEvents: eventsWithID)
        }
        
        // then
        XCTAssertTrue(waitForCustomExpectations(withTimeout: 0.5))
    }
    
    func testThatItDoesSetTheStatusToDoneIfThereAreNoMoreNotificationIDsAndItReceivedEvents() {
        // given
        let eventsWithID = createEventsWithID()
        XCTAssertEqual(sut.status, PingBackStatus.done)
        sut.didReceiveVoIPNotification(eventsWithID)
        XCTAssertEqual(sut.status, PingBackStatus.inProgress)
        
        // when
        _ = sut.nextNotificationEventsWithID()
        XCTAssertTrue(sut.hasNotificationIDs)

        sut.didReceive(encryptedEvents: eventsWithID.events!, originalEvents: eventsWithID, hasMore: false)
        
        // then
        XCTAssertFalse(sut.hasNotificationIDs)
        XCTAssertEqual(sut.status, PingBackStatus.done)
    }
    
    func testThatItRemovesEventsFromIdentifierEventsMappingAfterSuccesfullyPerformingPingBack() {
        // given
        let eventsWithID = createEventsWithID()

        // when
        sut.didReceiveVoIPNotification(eventsWithID)
        guard let currentEvents = sut.eventsWithHandlerByNotificationID[eventsWithID.identifier]?.events else { return XCTFail() }
        
        // then
        XCTAssertTrue(sut.hasNotificationIDs)
        XCTAssertEqual(currentEvents, eventsWithID.events!)
        
        // when
        sut.didReceive(encryptedEvents: eventsWithID.events!, originalEvents: eventsWithID, hasMore: false)
        
        // then
        XCTAssertNil(sut.eventsWithHandlerByNotificationID[eventsWithID.identifier])
    }
    
    func testThatItRemovesEventsWithHandlerFromIdentifierEventsMappingAfterFailingToPerformPingBack() {
        // given
        let eventsWithID = createEventsWithID()
        let expectedIdentifier = eventsWithID.identifier
        
        // when
        sut.didReceiveVoIPNotification(eventsWithID)
        guard let currentEventsWithHandler = sut.eventsWithHandlerByNotificationID[expectedIdentifier] else { return XCTFail() }
        
        // then
        XCTAssertTrue(sut.hasNotificationIDs)
        XCTAssertEqual(currentEventsWithHandler.events!, eventsWithID.events!)
        
        // when
        sut.didFailDownloading(originalEvents: eventsWithID)
        
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
        sut.didReceive(encryptedEvents:[], originalEvents: secondEventsWithIDs, hasMore: false)
        sut.didFailDownloading(originalEvents: thirdEventsWithIDs)
        
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

        if successfully {
            sut.didReceive(encryptedEvents: [], originalEvents: nextEventsWithID, hasMore: false)
        } else {
            sut.didFailDownloading(originalEvents: nextEventsWithID)
        }

        // then
        XCTAssertNil(sut.backgroundActivity)
    }
    
    func simulatePingBack() -> UUID {
        let nextEventsWithID = sut.nextNotificationEventsWithID()!
        sut.didReceive(encryptedEvents:[], originalEvents: nextEventsWithID, hasMore: false)
        return nextEventsWithID.identifier
    }

    func testThatItTakesTheOrderFromTheNotificationIDsArray() {
        // given
        let eventsWithID1 = createEventsWithID(isNotice: true)
        let eventsWithID2 = createEventsWithID(isNotice: false)
        let eventsWithID3 = createEventsWithID(isNotice: true)

        sut.didReceiveVoIPNotification(eventsWithID1)
        sut.didReceiveVoIPNotification(eventsWithID2)
        sut.didReceiveVoIPNotification(eventsWithID3)

        XCTAssertEqual(sut.status, PingBackStatus.inProgress)

        // when & then
        XCTAssertNotNil(sut.notificationIDs.index(of: eventsWithID1))
        XCTAssertNotNil(sut.notificationIDs.index(of: eventsWithID2))
        XCTAssertNotNil(sut.notificationIDs.index(of: eventsWithID3))

        sut.didReceive(encryptedEvents: [], originalEvents: eventsWithID1, hasMore: false)
        XCTAssertEqual(sut.status, PingBackStatus.inProgress)
        XCTAssertNil(sut.notificationIDs.index(of: eventsWithID1))

        sut.didReceive(encryptedEvents: [], originalEvents: eventsWithID2, hasMore: false)
        XCTAssertEqual(sut.status, PingBackStatus.inProgress)
        XCTAssertNil(sut.notificationIDs.index(of: eventsWithID2))

        sut.didReceive(encryptedEvents: [], originalEvents: eventsWithID3, hasMore: false)
        XCTAssertEqual(sut.status, PingBackStatus.done)
        XCTAssertNil(sut.notificationIDs.index(of: eventsWithID3))
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
