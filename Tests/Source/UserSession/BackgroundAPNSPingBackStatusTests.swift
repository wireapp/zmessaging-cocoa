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
import ZMTesting
import ZMCMockTransport


// MARK: - Mocks

class OperationLoopNewRequestObserver {
    
    var notifications = [NSNotification]()
    private var notificationCenter = NSNotificationCenter.defaultCenter()
    private var newRequestNotification = "ZMOperationLoopNewRequestAvailable"
    
    init() {
        notificationCenter.addObserverForName(newRequestNotification, object: nil, queue: .mainQueue()) { [weak self] note in
         self?.notifications.append(note)
        }
    }
    
    deinit {
        notificationCenter.removeObserver(self)
    }
}


@objc class MockAuthenticationProvider: NSObject, AuthenticationStatusProvider {
    var mockAuthenticationPhase: ZMAuthenticationPhase = .Authenticated
    
    var currentPhase: ZMAuthenticationPhase {
        return mockAuthenticationPhase
    }
}


@objc class MockNotificationDispatcher: NSObject, LocalNotificationDispatchType {
    var didReceiveUpdateEventsBlock: ([ZMUpdateEvent]? -> Void)?
    var callCount = 0
    
    func didReceiveUpdateEvents(events: [ZMUpdateEvent]?, notificationID: NSUUID) {
        callCount += 1
        didReceiveUpdateEventsBlock?(events)
    }
}

@objc class FakeGroupQueue : NSObject, ZMSGroupQueue {
    
    var dispatchGroup : ZMSDispatchGroup! {
        return nil
    }
    
    func performGroupedBlock(block : dispatch_block_t)
    {
        block()
    }
    
}


// MARK: - Tests

class EventsWithIdentifierTests: ZMTBaseTest {
    
    var sut: EventsWithIdentifier!
    var identifier: NSUUID!
    var events: [ZMUpdateEvent]!
    
    func messageAddPayload() -> [String : AnyObject] {
        return [
            "conversation": NSUUID.createUUID().transportString(),
            "time": NSDate(),
            "data": [
                "content": "saf",
                "nonce": NSUUID.createUUID().transportString(),
            ],
            "from": NSUUID.createUUID().transportString(),
            "type": "conversation.message-add"
        ];
    }
    
    override func setUp() {
        super.setUp()
        identifier = NSUUID.createUUID()
        let pushChannelData = [
            "id": identifier.transportString(),
            "payload": [messageAddPayload(), messageAddPayload()]
        ]
        
        
        events = ZMUpdateEvent.eventsArrayFromPushChannelData(pushChannelData)
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
    var notificationDispatcher: MockNotificationDispatcher!
    
    override func setUp() {
        super.setUp()
        
        BackgroundActivityFactory.sharedInstance().mainGroupQueue = FakeGroupQueue()
        
        authenticationProvider = MockAuthenticationProvider()
        notificationDispatcher = MockNotificationDispatcher()
        sut = BackgroundAPNSPingBackStatus(
            syncManagedObjectContext: syncMOC,
            authenticationProvider: authenticationProvider,
            localNotificationDispatcher: notificationDispatcher
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
        let notificationID = NSUUID.createUUID()
        
        // when
        sut.didReceiveVoIPNotification(createEventsWithID(notificationID))
        
        // then
        XCTAssertTrue(sut.hasNotificationIDs)
        XCTAssertEqual(sut.status, PingBackStatus.Pinging)
        
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
        let notificationID = NSUUID.createUUID()
        let eventsWithID = createEventsWithID(notificationID)
        
        // when
        var callcount = 0
        let handler: (ZMPushPayloadResult, [ZMUpdateEvent]) -> Void = { _ in callcount += 1 }
        sut.didReceiveVoIPNotification(eventsWithID, handler: handler)
        
        // then
        XCTAssertTrue(sut.hasNotificationIDs)
        XCTAssertEqual(sut.status, PingBackStatus.Pinging)
        
        // when
        guard let notificationEventsWithIDToPing = sut.nextNotificationEventsWithID() else { return XCTFail("No events with identifier") }
        
        // then
        XCTAssertEqual(notificationID, notificationEventsWithIDToPing.identifier)
        XCTAssertNil(sut.nextNotificationEventsWithID())
        XCTAssertFalse(sut.hasNotificationIDs)
        
        // when
        sut.didPerfomPingBackRequest(notificationEventsWithIDToPing, responseStatus: .TryAgainLater)
        
        // then
        XCTAssertTrue(sut.hasNotificationIDs)
        XCTAssertEqual(sut.status, PingBackStatus.Pinging)
        
        let nextEventsWithID = sut.nextNotificationEventsWithID()
        
        // then
        XCTAssertEqual(notificationID, nextEventsWithID?.identifier)
        
        // when
        sut.didPerfomPingBackRequest(notificationEventsWithIDToPing, responseStatus: .Success)
        XCTAssertEqual(callcount, 1)
        XCTAssertNil(sut.nextNotificationEventsWithID())
    }
    
    func testThatItRemovesTheIDWhenThePingBackFailed() {
        // given
        XCTAssertFalse(sut.hasNotificationIDs)
        let notificationID = NSUUID.createUUID()
        let eventsWithID = createEventsWithID(notificationID)
        
        // when
        sut.didReceiveVoIPNotification(eventsWithID)
        
        // then
        XCTAssertTrue(sut.hasNotificationIDs)
        XCTAssertEqual(sut.status, PingBackStatus.Pinging)
        
        // when
        guard let notificationEventsWithIDToPing = sut.nextNotificationEventsWithID() else { return XCTFail("No events with identifier") }
        
        // then
        XCTAssertEqual(notificationID, notificationEventsWithIDToPing.identifier)
        XCTAssertNil(sut.nextNotificationEventsWithID())
        XCTAssertFalse(sut.hasNotificationIDs)
        
        // when
        sut.didPerfomPingBackRequest(notificationEventsWithIDToPing, responseStatus: .PermanentError)
        
        // then
        XCTAssertFalse(sut.hasNotificationIDs)
        XCTAssertEqual(sut.status, PingBackStatus.Done)
    }
    
    func testThatItPostsNewRequestsAvailableNotificationWhenAddingANotificationID() {
        // when
        sut.didReceiveVoIPNotification(createEventsWithID())
        XCTAssert(self.waitForAllGroupsToBeEmptyWithTimeout(0.5))
        
        // then
        XCTAssertEqual(observer.notifications.count, 1)
    }
    
    func testThatItNotifiesTheLocalNotificationDispatcherIfThePingBackSucceded() {
        
        // given
        let eventsWithID = createEventsWithID()
        sut.didReceiveVoIPNotification(eventsWithID)
        notificationDispatcher.didReceiveUpdateEventsBlock = { events in
            guard let unwrappedEvents = events else { return XCTFail() }
            XCTAssertEqual(unwrappedEvents, eventsWithID.events!)
        }
        
        // when
        _ = sut.nextNotificationEventsWithID()
        sut.didPerfomPingBackRequest(eventsWithID, responseStatus: .Success)
        
        // then
        XCTAssertEqual(notificationDispatcher.callCount, 1)
    }
    
    func testThatItDoesNotNotifyTheLocalNotificationDispatcherIfThePingBackFailed_TemporaryError() {
        
        // given
        let eventsWithID = createEventsWithID()
        sut.didReceiveVoIPNotification(eventsWithID)
        
        // when
        _ = sut.nextNotificationEventsWithID()
        sut.didPerfomPingBackRequest(eventsWithID, responseStatus: .TemporaryError)
        
        // then
        XCTAssertEqual(notificationDispatcher.callCount, 0)
    }
    
    func testThatItDoesNotNotifyTheLocalNotificationDispatcherIfThePingBackFailed_TryAgainLater() {
        
        // given
        let eventsWithID = createEventsWithID()
        sut.didReceiveVoIPNotification(eventsWithID)
        
        // when
        _ = sut.nextNotificationEventsWithID()
        sut.didPerfomPingBackRequest(eventsWithID, responseStatus: .TryAgainLater)
        
        // then
        XCTAssertEqual(notificationDispatcher.callCount, 0)
    }
    
    func testThatItDoesNotCallTheHandlerAfterPingBackRequestCompletedUnsuccessfully_TryAgain_Until_Sucess() {
        // given
        let eventsWithID = createEventsWithID()
        let expectation = expectationWithDescription("It doesn't call the completion handler")
        
        // expect
        var callcount = 0
        sut.didReceiveVoIPNotification(eventsWithID) {
            callcount += 1
            XCTAssertEqual($0.0, ZMPushPayloadResult.Success)
            expectation.fulfill()
        }
        
        // when
        sut.didPerfomPingBackRequest(eventsWithID, responseStatus: .TryAgainLater)
        
        // then
        XCTAssertEqual(callcount, 0)
        
        // when
        sut.didPerfomPingBackRequest(eventsWithID, responseStatus: .Success)
        XCTAssertTrue(waitForCustomExpectationsWithTimeout(0.5))
        
        // then
        XCTAssertEqual(callcount, 1)
    }
    
    func testThatItCallsTheHandlerAfterPingBackRequestCompletedSuccessfully() {
        checkThatItCallsTheHandlerAfterPingBackRequestCompleted(.Success)
    }
    
    func testThatItCallsTheHandlerAfterPingBackRequestCompletedUnsuccessfully_Permanent() {
        checkThatItCallsTheHandlerAfterPingBackRequestCompleted(.PermanentError)
    }
    
    func checkThatItCallsTheHandlerAfterPingBackRequestCompleted(status: ZMTransportResponseStatus) {
        // given
        let eventsWithID = createEventsWithID()
        let expectation = expectationWithDescription("It calls the completion handler")
        
        // expect
        sut.didReceiveVoIPNotification(eventsWithID) { result in
            XCTAssertEqual(result.0, (status == .Success) ? ZMPushPayloadResult.Success : ZMPushPayloadResult.Failure)
            expectation.fulfill()
        }
        
        // when
        sut.didPerfomPingBackRequest(eventsWithID, responseStatus: status)
        
        // then
        XCTAssertTrue(waitForCustomExpectationsWithTimeout(0.5))
    }
    
    func testThatItDoesSetTheStatusToDoneIfThereAreNoMoreNotifactionIDs() {
        
        // given
        let eventsWithID = createEventsWithID()
        XCTAssertEqual(sut.status, PingBackStatus.Done)
        sut.didReceiveVoIPNotification(eventsWithID)
        XCTAssertEqual(sut.status, PingBackStatus.Pinging)
        
        // when
        _ = sut.nextNotificationEventsWithID()
        XCTAssertFalse(sut.hasNotificationIDs)

        sut.didPerfomPingBackRequest(eventsWithID, responseStatus: .Success)
        
        // then
        XCTAssertFalse(sut.hasNotificationIDs)
        XCTAssertEqual(sut.status, PingBackStatus.Done)
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
        sut.didPerfomPingBackRequest(eventsWithIDs, responseStatus: .Success)
        
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
        sut.didPerfomPingBackRequest(eventsWithIDs, responseStatus: .TemporaryError)
        
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
        sut.didPerfomPingBackRequest(secondEventsWithIDs, responseStatus: .Success)
        sut.didPerfomPingBackRequest(thirdEventsWithIDs, responseStatus: .TemporaryError)
        
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
        authenticationProvider.mockAuthenticationPhase = .Unauthenticated
        
        // when
        sut.didReceiveVoIPNotification(createEventsWithID())
        XCTAssertFalse(sut.hasNotificationIDs)
        
        // then
        XCTAssertNil(sut.backgroundActivity)
    }
    
    func testThatItEndsTheBackgroundActivityWhenRequestCompletesSuccessfully() {
        checkThatItEndsTheBackgroundActivityAfterThePingBackCompleted(true)
    }
    
    func testThatItEndsTheBackgroundActivityWhenRequestCompletesUnsuccessfully() {
        checkThatItEndsTheBackgroundActivityAfterThePingBackCompleted(false)
    }
    
    func checkThatItEndsTheBackgroundActivityAfterThePingBackCompleted(successfully: Bool) {
        // given
        let eventsWithID = createEventsWithID()
        sut.didReceiveVoIPNotification(eventsWithID)
        XCTAssertTrue(sut.hasNotificationIDs)
        XCTAssertNotNil(sut.backgroundActivity)
        
        // when
        let nextEventsWithID = sut.nextNotificationEventsWithID()!
        XCTAssertEqual(nextEventsWithID.identifier, eventsWithID.identifier)
        sut.didPerfomPingBackRequest(nextEventsWithID, responseStatus: successfully ? .Success : .TemporaryError)
        
        // then
        XCTAssertNil(sut.backgroundActivity)
    }
    
    func checkThatItEndsTheBackgroundActivityAfterTheFetchCompleted(fetchSuccess: Bool) {
        // given
        let eventsWithID = createEventsWithID(isNotice: true)
        sut.didReceiveVoIPNotification(eventsWithID)
        XCTAssertFalse(sut.hasNotificationIDs)
        XCTAssertTrue(sut.hasNoticeNotificationIDs)
        XCTAssertEqual(sut.status, PingBackStatus.FetchingNotificationStream)
        
        XCTAssertNotNil(sut.backgroundActivity)
        
        // when
        let nextNoticeEventsWithID = sut.nextNoticeNotificationEventsWithID()!
        
        sut.didFetchNoticeNotification(nextNoticeEventsWithID, responseStatus: fetchSuccess ? .Success : .TemporaryError, events:[])
        XCTAssertEqual(sut.status, PingBackStatus.Done)
        
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
    

    func simulateFetchNoticeAndPingback() -> Bool {
        if let nextNoticeEventsWithID = sut.nextNoticeNotificationEventsWithID() {
            sut.missingUpdateEventTranscoder(didReceiveEvents: [], originalEvents: nextNoticeEventsWithID, hasMore: false)
            return true
        }
        return false
    }
    
    func simulatePingBack() -> NSUUID {
        let nextEventsWithID = sut.nextNotificationEventsWithID()!
        sut.didPerfomPingBackRequest(nextEventsWithID, responseStatus: .Success)
        return nextEventsWithID.identifier
    }
    
    func checkThatItUpdatesStatusToFetchingStreamWhenFirstAndNextNotificationAreNotice(nextIsNotice: Bool) {
       
        // given
        let eventsWithID1 = createEventsWithID(isNotice: true)
        let eventsWithID2 = createEventsWithID(isNotice: nextIsNotice)

        sut.didReceiveVoIPNotification(eventsWithID1)
        sut.didReceiveVoIPNotification(eventsWithID2)

        XCTAssertTrue(sut.hasNoticeNotificationIDs)
        XCTAssertEqual(sut.status, PingBackStatus.FetchingNotificationStream)
        
        XCTAssertNotNil(sut.backgroundActivity)
        
        // when
        XCTAssertTrue(simulateFetchNoticeAndPingback())

        // then
        if nextIsNotice {
            XCTAssertTrue(sut.hasNoticeNotificationIDs)
            XCTAssertFalse(sut.hasNotificationIDs)
            XCTAssertEqual(sut.status, PingBackStatus.FetchingNotificationStream)
        } else {
            XCTAssertTrue(sut.hasNotificationIDs)
            XCTAssertEqual(sut.status, PingBackStatus.Pinging)
        }
        XCTAssertNotNil(sut.backgroundActivity)

        // and when
        if nextIsNotice {
            XCTAssertTrue(simulateFetchNoticeAndPingback())
        } else {
            simulatePingBack()
        }
        
        // then
        XCTAssertNil(sut.backgroundActivity)
        XCTAssertEqual(sut.status, PingBackStatus.Done)
    }
    
    func testThatItUpdatesStatusToFetchingStreamWhenFirstAndNextNotificationAreNoticeNextIsNotice() {
        checkThatItUpdatesStatusToFetchingStreamWhenFirstAndNextNotificationAreNotice(true)
    }
    
    func testThatItUpdatesStatusToFetchingStreamWhenFirstAndNextNotificationAreNoticeNextIsNonNotice() {
        checkThatItUpdatesStatusToFetchingStreamWhenFirstAndNextNotificationAreNotice(false)
    }
    
    func checkThatItUpdatesStatusToFetchingStreamWhenFirstIsNonNoticeAndNextNotification(nextIsNotice: Bool) {
        
        // given
        let eventsWithID1 = createEventsWithID(isNotice: false)
        let eventsWithID2 = createEventsWithID(isNotice: nextIsNotice)
        
        sut.didReceiveVoIPNotification(eventsWithID1)
        sut.didReceiveVoIPNotification(eventsWithID2)
        
        XCTAssertTrue(sut.hasNotificationIDs)
        XCTAssertEqual(sut.status, PingBackStatus.Pinging)
        
        XCTAssertNotNil(sut.backgroundActivity)
        
        // when
        simulatePingBack()
        
        // then
        if nextIsNotice {
            XCTAssertTrue(sut.hasNoticeNotificationIDs)
            XCTAssertEqual(sut.status, PingBackStatus.FetchingNotificationStream)
        } else {
            XCTAssertFalse(sut.hasNoticeNotificationIDs)
            XCTAssertEqual(sut.status, PingBackStatus.Pinging)
        }
        XCTAssertNotNil(sut.backgroundActivity)
        
        // and when
        if nextIsNotice {
            simulateFetchNoticeAndPingback()
        } else {
            simulatePingBack()
        }
        
        // then
        XCTAssertNil(sut.backgroundActivity)
        XCTAssertEqual(sut.status, PingBackStatus.Done)
    }
    
    func testThatItUpdatesStatusToFetchingStreamWhenFirstIsNonNoticeAndNextNotificationIsNotice() {
        checkThatItUpdatesStatusToFetchingStreamWhenFirstIsNonNoticeAndNextNotification(true)
    }
    
    func testThatItUpdatesStatusToFetchingStreamWhenFirstIsNonNoticeAndNextNotificationIsNotNotice() {
        checkThatItUpdatesStatusToFetchingStreamWhenFirstIsNonNoticeAndNextNotification(false)
    }

    func testThatItTakesTheOrderFromTheNotificationIDsArray() {
        // given
        let eventsWithID1 = createEventsWithID(isNotice: true)
        let eventsWithID2 = createEventsWithID(isNotice: false)
        let eventsWithID3 = createEventsWithID(isNotice: true)

        sut.didReceiveVoIPNotification(eventsWithID1)
        sut.didReceiveVoIPNotification(eventsWithID2)
        sut.didReceiveVoIPNotification(eventsWithID3)

        XCTAssertEqual(sut.status, PingBackStatus.FetchingNotificationStream)

        // when
        simulateFetchNoticeAndPingback()
        XCTAssertEqual(sut.status, PingBackStatus.Pinging)

        simulatePingBack()
        XCTAssertEqual(sut.status, PingBackStatus.FetchingNotificationStream)

        simulateFetchNoticeAndPingback()
        XCTAssertEqual(sut.status, PingBackStatus.Done)
    }
}


// MARK: MissingUpdateEventTranscoder
extension BackgroundAPNSPingBackStatusTests {
    
    func testThatItReturnsHasNoticeNotification_TRUE_IfNoNotificationInProgress(){
        
        // given
        let eventsWithID1 = createEventsWithID(isNotice: true)
        let eventsWithID2 = createEventsWithID(isNotice: true)
        
        sut.didReceiveVoIPNotification(eventsWithID1)
        sut.didReceiveVoIPNotification(eventsWithID2)
        
        // then
        XCTAssertTrue(sut.hasNoticeNotificationIDs)
        XCTAssertFalse(sut.notificationInProgress)
    }
    
    func testThatItReturnsHasNoticeNotification_FALSE_IFNotificationInProgress(){
    
        // given
        let eventsWithID1 = createEventsWithID(isNotice: true)
        let eventsWithID2 = createEventsWithID(isNotice: true)

        sut.didReceiveVoIPNotification(eventsWithID1)
        sut.didReceiveVoIPNotification(eventsWithID2)

        // when
        XCTAssertNotNil(sut.nextNoticeNotificationEventsWithID())
        
        // then
        XCTAssertFalse(sut.hasNoticeNotificationIDs)
        XCTAssertTrue(sut.notificationInProgress)
        
        // and when
        sut.missingUpdateEventTranscoder(didReceiveEvents: [ZMUpdateEvent()], originalEvents: eventsWithID1, hasMore: false)
        
        // then
        XCTAssertTrue(sut.hasNoticeNotificationIDs)
        XCTAssertFalse(sut.notificationInProgress)
    }
    
    func testThatWhenFetchingNotificationStreamFailsItSwitchesTo_FetchNotice(){
        // given
        let eventsWithID1 = createEventsWithID(isNotice: true)
        sut.didReceiveVoIPNotification(eventsWithID1)
        XCTAssertEqual(sut.status, PingBackStatus.FetchingNotificationStream)
        XCTAssertTrue(sut.hasNoticeNotificationIDs)

        // when
        XCTAssertNotNil(sut.nextNoticeNotificationEventsWithID())
        XCTAssertFalse(sut.notificationIDs.contains(eventsWithID1))
        sut.missingUpdateEventTranscoderFailedDownloadingEvents(eventsWithID1)

        // then
        XCTAssertTrue(sut.hasNoticeNotificationIDs)
        XCTAssertTrue(sut.notificationIDs.contains(eventsWithID1))
        XCTAssertEqual(sut.status, PingBackStatus.FetchingNotice)
    }
    
    func testThatItFinishesWithFailureWhenNoEventsReturned(){
        // given
        let eventsWithID1 = createEventsWithID(isNotice: true)
        
        var  didFinish = false
        let handler: (ZMPushPayloadResult, [ZMUpdateEvent]) -> Void = { (result, events) in
            XCTAssertEqual(result, ZMPushPayloadResult.Failure)
            XCTAssertEqual(events.count, 0)
            didFinish = true
        }
        
        sut.didReceiveVoIPNotification(eventsWithID1, handler: handler)
        XCTAssertNotNil(sut.nextNoticeNotificationEventsWithID())

        // when
        sut.missingUpdateEventTranscoder(didReceiveEvents: [], originalEvents: eventsWithID1, hasMore: false)
        
        // then
        XCTAssertTrue(didFinish)
        XCTAssertFalse(sut.notificationInProgress)
        XCTAssertEqual(sut.status, PingBackStatus.Done)
    }
    
    func testThatItFinishesWithSuccessWhenEventsReturned(){
        // given
        let realEventWithID = self.createRealNoticeEventWithID()
        
        var  didFinish = false
        let handler: (ZMPushPayloadResult, [ZMUpdateEvent]) -> Void = { (result, events) in
            XCTAssertEqual(result, ZMPushPayloadResult.Success)
            XCTAssertEqual(events.count, 0)
            didFinish = true
        }
        
        notificationDispatcher.didReceiveUpdateEventsBlock = { events in
            guard let events = events, let givenEvents = realEventWithID.events else {
                XCTFail("did not forward send events")
                return
            }
            XCTAssertEqual(events, givenEvents)
        }
        
        sut.didReceiveVoIPNotification(realEventWithID, handler: handler)
        XCTAssertNotNil(sut.nextNoticeNotificationEventsWithID())
        
        // when
        sut.missingUpdateEventTranscoder(didReceiveEvents: realEventWithID.events!, originalEvents: realEventWithID, hasMore: false)
        
        // then
        XCTAssertTrue(didFinish)
        XCTAssertFalse(sut.notificationInProgress)
        XCTAssertEqual(sut.status, PingBackStatus.Done)
        XCTAssertEqual(notificationDispatcher.callCount, 1)
    }
    
    func testThatItDoesNotFinishWhenEventsNotReturnedButHasMore(){
        // given
        let eventsWithID1 = createEventsWithID(isNotice: true)
        let unrelatedEvent = createEvent(NSUUID.timeBasedUUID())
        
        var didFinish = false
        let handler: (ZMPushPayloadResult, [ZMUpdateEvent]) -> Void = { (result, events) in
            didFinish = true
        }
        
        notificationDispatcher.didReceiveUpdateEventsBlock = { events in
            guard let events = events else {
                XCTFail("did not forward send events")
                return
            }
            XCTAssertEqual(events, [unrelatedEvent])
        }
        
        sut.didReceiveVoIPNotification(eventsWithID1, handler: handler)
        XCTAssertNotNil(sut.nextNoticeNotificationEventsWithID())

        // when
        sut.missingUpdateEventTranscoder(didReceiveEvents: [unrelatedEvent], originalEvents: eventsWithID1, hasMore: true)
        
        // then
        XCTAssertFalse(didFinish)
        XCTAssertTrue(sut.notificationInProgress)
        XCTAssertEqual(sut.status, PingBackStatus.FetchingNotificationStream)
        XCTAssertEqual(notificationDispatcher.callCount, 1)
    }
}


// MARK: - Helper

extension BackgroundAPNSPingBackStatus {
    func didReceiveVoIPNotification(eventsWithID: EventsWithIdentifier) {
        didReceiveVoIPNotification(eventsWithID, handler: { _ in })
    }
}

extension BackgroundAPNSPingBackStatusTests {
    func createEventsWithID(identifier: NSUUID = NSUUID.createUUID(), events: [ZMUpdateEvent] = [ZMUpdateEvent()], isNotice: Bool = false) -> EventsWithIdentifier {
        return EventsWithIdentifier(events: events, identifier: identifier, isNotice: isNotice)
    }
    
    func createRealNoticeEventWithID(identifier : NSUUID = NSUUID.timeBasedUUID()) -> EventsWithIdentifier {
        let event = createEvent(identifier)
        let eventWithID = EventsWithIdentifier(events: [event], identifier: event.uuid, isNotice: true)
        return eventWithID
    }
    
    func createEvent(timeBasedIdentifier: NSUUID) -> ZMUpdateEvent {
        let conversation = ZMConversation.insertNewObjectInManagedObjectContext(self.uiMOC)
        conversation.remoteIdentifier = NSUUID.createUUID()
        
        let payload = self.payloadForMessageInConversation(conversation, type: EventConversationAdd, data: [:])
        let event = ZMUpdateEvent(fromEventStreamPayload: payload, uuid: timeBasedIdentifier)
        return event
    }
}
