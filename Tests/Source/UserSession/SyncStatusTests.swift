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


import XCTest
@testable import WireSyncEngine

class InitialSyncObserver : NSObject, ZMInitialSyncCompletionObserver {
    
    var didNotify : Bool = false
    
    override init() {
        super.init()
        ZMUserSession.addInitalSyncCompletionObserver(self)
    }
    
    func tearDown(){
        ZMUserSession.removeInitalSyncCompletionObserver(self)
    }
    
    func initialSyncCompleted(_ notification: Notification!) {
        didNotify = true
    }
}


class SyncStatusTests : MessagingTest {

    var sut : SyncStatus!
    var mockSyncDelegate : MockSyncStateDelegate!
    override func setUp() {
        super.setUp()
        mockSyncDelegate = MockSyncStateDelegate()
        sut = SyncStatus(managedObjectContext: uiMOC, syncStateDelegate: mockSyncDelegate)
    }
    
    override func tearDown() {
        self.uiMOC.zm_lastNotificationID = nil
        super.tearDown()
    }
    
    func testThatWhenIntializingWithoutLastEventIDItStartsInStateFetchingLastUpdateEventID(){
        // given
        uiMOC.zm_lastNotificationID = nil
        
        // when
        sut = SyncStatus(managedObjectContext: uiMOC, syncStateDelegate: mockSyncDelegate)
        
        // then
        XCTAssertEqual(sut.currentSyncPhase, .fetchingLastUpdateEventID)
    }
    
    func testThatWhenIntializingWihtLastEventIDItStartsInStateFetchingMissingEvents(){
        // given
        uiMOC.zm_lastNotificationID = UUID.timeBasedUUID() as UUID
        
        // when
        sut = SyncStatus(managedObjectContext: uiMOC, syncStateDelegate: mockSyncDelegate)
        
        // then
        XCTAssertEqual(sut.currentSyncPhase, .fetchingMissedEvents)
    }
    
    func testThatItGoesThroughTheStatesInSpecificOrder(){
        // given
        XCTAssertEqual(sut.currentSyncPhase, .fetchingLastUpdateEventID)
        // when
        sut.didFinishCurrentSyncPhase()
        // then
        XCTAssertEqual(sut.currentSyncPhase, .fetchingConnections)
        // when
        sut.didFinishCurrentSyncPhase()
        // then
        XCTAssertEqual(sut.currentSyncPhase, .fetchingConversations)
        // when
        sut.didFinishCurrentSyncPhase()
        // then
        XCTAssertEqual(sut.currentSyncPhase, .fetchingUsers)
        // when
        sut.didFinishCurrentSyncPhase()
        // then
        XCTAssertEqual(sut.currentSyncPhase, .fetchingMissedEvents)
        // when
        sut.didFinishCurrentSyncPhase()
        // then
        XCTAssertEqual(sut.currentSyncPhase, .done)
    }
    
    func testThatItSavesTheLastNotificationIDOnlyAfterFinishingUserPhase(){
        // given
        XCTAssertEqual(sut.currentSyncPhase, .fetchingLastUpdateEventID)
        sut.updateLastUpdateEventID(eventID: UUID.timeBasedUUID() as UUID)
        XCTAssertNil(uiMOC.zm_lastNotificationID)

        // when
        sut.didFinishCurrentSyncPhase()
        // then
        XCTAssertNil(uiMOC.zm_lastNotificationID)
        // when
        sut.didFinishCurrentSyncPhase()
        // then
        XCTAssertNil(uiMOC.zm_lastNotificationID)
        // when
        sut.didFinishCurrentSyncPhase()
        // then
        XCTAssertNil(uiMOC.zm_lastNotificationID)
        // when
        sut.didFinishCurrentSyncPhase()
        // then
        XCTAssertNotNil(uiMOC.zm_lastNotificationID)
    }
    
    func testThatItDoesNotSetTheLastNotificationIDIfItHasNone(){
        XCTAssertEqual(sut.currentSyncPhase, .fetchingLastUpdateEventID)
        uiMOC.zm_lastNotificationID = UUID.timeBasedUUID() as UUID
        XCTAssertNotNil(uiMOC.zm_lastNotificationID)
        
        // when
        XCTAssertEqual(sut.currentSyncPhase, .fetchingLastUpdateEventID)
        // when
        sut.didFinishCurrentSyncPhase()
        // then
        XCTAssertEqual(sut.currentSyncPhase, .fetchingConnections)
        // when
        sut.didFinishCurrentSyncPhase()
        // then
        XCTAssertEqual(sut.currentSyncPhase, .fetchingConversations)
        // when
        sut.didFinishCurrentSyncPhase()
        // then
        XCTAssertEqual(sut.currentSyncPhase, .fetchingUsers)
        // when
        sut.didFinishCurrentSyncPhase()
        
        // then
        XCTAssertNotNil(uiMOC.zm_lastNotificationID)
    }
    
    func testThatItNotifiesTheStateDelegateWhenFinishingSync(){
        // given
        XCTAssertEqual(sut.currentSyncPhase, .fetchingLastUpdateEventID)
        XCTAssertFalse(mockSyncDelegate.didCallFinishSync)
        
        // when
        sut.didFinishCurrentSyncPhase()
        // then
        XCTAssertFalse(mockSyncDelegate.didCallFinishSync)
        // when
        sut.didFinishCurrentSyncPhase()
        // then
        XCTAssertFalse(mockSyncDelegate.didCallFinishSync)
        // when
        sut.didFinishCurrentSyncPhase()
        // then
        XCTAssertFalse(mockSyncDelegate.didCallFinishSync)
        // when
        sut.didFinishCurrentSyncPhase()
        // then
        XCTAssertFalse(mockSyncDelegate.didCallFinishSync)
        // when
        sut.didFinishCurrentSyncPhase()
        
        // then
        XCTAssertTrue(mockSyncDelegate.didCallFinishSync)
    }
    
    func testThatItNotifiesTheStateDelegateWhenStartingSync(){
        // given
        uiMOC.zm_lastNotificationID = UUID.timeBasedUUID() as UUID
        sut = SyncStatus(managedObjectContext: uiMOC, syncStateDelegate: mockSyncDelegate)
        XCTAssertEqual(sut.currentSyncPhase, .fetchingMissedEvents)

        // then
        XCTAssertTrue(mockSyncDelegate.didCallStartSync)
    }
    
    func testThatItDoesNotNotifyTheStateDelegateWhenAlreadySyncing(){
        // given
        mockSyncDelegate.didCallStartSync = false
        sut.didFinishCurrentSyncPhase()
        XCTAssertEqual(sut.currentSyncPhase, .fetchingConnections)
        
        XCTAssertFalse(mockSyncDelegate.didCallStartSync)
        
        // when
        sut.didFinishCurrentSyncPhase()
        
        // then
        XCTAssertFalse(mockSyncDelegate.didCallStartSync)
    }
    

    func testThatItNotifiesTheStateDelegateWhenPushChannelClosedThatSyncStarted(){
        // given
        uiMOC.zm_lastNotificationID = UUID.timeBasedUUID() as UUID
        sut = SyncStatus(managedObjectContext: uiMOC, syncStateDelegate: mockSyncDelegate)
        sut.didFinishCurrentSyncPhase()
        XCTAssertEqual(sut.currentSyncPhase, .done)
        mockSyncDelegate.didCallStartSync = false

        // when
        sut.pushChannelDidClose()

        // then
        XCTAssertTrue(mockSyncDelegate.didCallStartSync)

    }
    
    func testThatItNotifiesObserverThatSyncCompleted(){
        // given
        uiMOC.zm_lastNotificationID = UUID.timeBasedUUID() as UUID
        sut = SyncStatus(managedObjectContext: uiMOC, syncStateDelegate: mockSyncDelegate)
        
        let observer = InitialSyncObserver()
        XCTAssertFalse(observer.didNotify)

        // when
        sut.didFinishCurrentSyncPhase()
        XCTAssert(self.waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertTrue(observer.didNotify)
        
        observer.tearDown()
    }

}


// MARK: QuickSync
extension SyncStatusTests {
    
    func testThatItStartsQuickSyncWhenPushChannelOpens_PreviousPhaseDone(){
        // given
        uiMOC.zm_lastNotificationID = UUID.timeBasedUUID() as UUID
        sut = SyncStatus(managedObjectContext: uiMOC, syncStateDelegate: mockSyncDelegate)
        sut.didFinishCurrentSyncPhase()
        XCTAssertEqual(sut.currentSyncPhase, .done)
        
        // when
        sut.pushChannelDidOpen()
        
        // then
        XCTAssertEqual(sut.currentSyncPhase, .fetchingMissedEvents)
    }
    
    func testThatItDoesNotStartsQuickSyncWhenPushChannelOpens_PreviousInSlowSync(){
        // given
        XCTAssertEqual(sut.currentSyncPhase, .fetchingLastUpdateEventID)
        
        // when
        sut.pushChannelDidOpen()
        
        // then
        XCTAssertEqual(sut.currentSyncPhase, .fetchingLastUpdateEventID)
    }
    
    func testThatItRestartsQuickSyncWhenPushChannelOpens_PreviousInQuickSync(){
        // given
        uiMOC.zm_lastNotificationID = UUID.timeBasedUUID() as UUID
        sut = SyncStatus(managedObjectContext: uiMOC, syncStateDelegate: mockSyncDelegate)
        XCTAssertEqual(sut.currentSyncPhase, .fetchingMissedEvents)
        XCTAssertFalse(sut.needsToRestartQuickSync)
        
        // when
        sut.pushChannelDidOpen()
        
        // then
        XCTAssertEqual(sut.currentSyncPhase, .fetchingMissedEvents)
        XCTAssertTrue(sut.needsToRestartQuickSync)
        
        // and when
        sut.didFinishCurrentSyncPhase()
        
        // then
        XCTAssertEqual(sut.currentSyncPhase, .fetchingMissedEvents)
    }
    
    func testThatItRestartsQuickSyncWhenPushChannelClosedDuringQuickSync(){
        // given
        uiMOC.zm_lastNotificationID = UUID.timeBasedUUID() as UUID
        sut = SyncStatus(managedObjectContext: uiMOC, syncStateDelegate: mockSyncDelegate)
        XCTAssertEqual(sut.currentSyncPhase, .fetchingMissedEvents)
        XCTAssertFalse(sut.needsToRestartQuickSync)
        
        // when
        sut.pushChannelDidOpen()
        
        // then
        XCTAssertEqual(sut.currentSyncPhase, .fetchingMissedEvents)
        XCTAssertTrue(sut.needsToRestartQuickSync)
        
        // and when
        sut.pushChannelDidClose()
        sut.pushChannelDidOpen()
        sut.didFinishCurrentSyncPhase()
        
        // then
        XCTAssertEqual(sut.currentSyncPhase, .fetchingMissedEvents)
    }
    
    func testThatItDoesNotRestartsQuickSyncWhenPushChannelIsClosed(){
        // given
        uiMOC.zm_lastNotificationID = UUID.timeBasedUUID() as UUID
        sut = SyncStatus(managedObjectContext: uiMOC, syncStateDelegate: mockSyncDelegate)
        XCTAssertEqual(sut.currentSyncPhase, .fetchingMissedEvents)
        XCTAssertFalse(sut.needsToRestartQuickSync)
        
        // when
        sut.pushChannelDidOpen()
        
        // then
        XCTAssertEqual(sut.currentSyncPhase, .fetchingMissedEvents)
        XCTAssertTrue(sut.needsToRestartQuickSync)
        
        // and when
        sut.pushChannelDidClose()
        sut.didFinishCurrentSyncPhase()
        
        // then
        XCTAssertEqual(sut.currentSyncPhase, .done)
    }
    
    func testThatItEntersSlowSyncIfQuickSyncFailed(){
        // given
        uiMOC.zm_lastNotificationID = UUID.timeBasedUUID() as UUID
        sut = SyncStatus(managedObjectContext: uiMOC, syncStateDelegate: mockSyncDelegate)
        XCTAssertEqual(sut.currentSyncPhase, .fetchingMissedEvents)
        
        // when
        sut.didFailCurrentSyncPhase()
        
        // then
        XCTAssertEqual(sut.currentSyncPhase, .fetchingConnections)
    }
    
    func testThatItDoesNotSaveLastNotificationIDWhenSlowSyncFailed(){
        // given
        let oldID = UUID.timeBasedUUID() as UUID
        let newID = UUID.timeBasedUUID() as UUID
        uiMOC.zm_lastNotificationID = oldID
        sut = SyncStatus(managedObjectContext: uiMOC, syncStateDelegate: mockSyncDelegate)
        XCTAssertEqual(sut.currentSyncPhase, .fetchingMissedEvents)
        
        // when
        sut.updateLastUpdateEventID(eventID: newID)
        sut.didFailCurrentSyncPhase()
        
        // then
        XCTAssertEqual(uiMOC.zm_lastNotificationID, oldID)
        XCTAssertNotEqual(uiMOC.zm_lastNotificationID, newID)
    }
    
    func testThatItSavesLastNotificationIDOnlyAfterSlowSyncFinishedSuccessfullyAfterFailedQuickSync(){
        // given
        let oldID = UUID.timeBasedUUID() as UUID
        let newID = UUID.timeBasedUUID() as UUID
        uiMOC.zm_lastNotificationID = oldID
        sut = SyncStatus(managedObjectContext: uiMOC, syncStateDelegate: mockSyncDelegate)
        XCTAssertEqual(sut.currentSyncPhase, .fetchingMissedEvents)
        
        // when
        sut.updateLastUpdateEventID(eventID: newID)
        sut.didFailCurrentSyncPhase()
        
        // then
        XCTAssertNotEqual(uiMOC.zm_lastNotificationID, newID)
        
        // and when
        sut.didFinishCurrentSyncPhase()
        // then
        XCTAssertNotEqual(uiMOC.zm_lastNotificationID, newID)
        // when
        sut.didFinishCurrentSyncPhase()
        // then
        XCTAssertNotEqual(uiMOC.zm_lastNotificationID, newID)
        // when
        sut.didFinishCurrentSyncPhase()
        // then
        XCTAssertEqual(uiMOC.zm_lastNotificationID, newID)
        XCTAssertNotEqual(uiMOC.zm_lastNotificationID, oldID)
    }
}
