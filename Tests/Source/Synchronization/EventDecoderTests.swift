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


import ZMTesting
@testable import zmessaging

class EventDecoderTest: MessagingTest {
    
    var eventMOC = NSManagedObjectContext.createEventContext(withAppGroupIdentifier: nil)
    var sut : EventDecoder!

    override func setUp() {
        super.setUp()
        sut = EventDecoder(eventMOC: eventMOC, syncMOC: syncMOC)
        eventMOC.addGroup(self.dispatchGroup)
    }
    
    override func tearDown() {
        eventMOC.tearDown()
        super.tearDown()
    }
    
    func dummyEvent() -> ZMUpdateEvent {
        let conversation = ZMConversation.insertNewObjectInManagedObjectContext(self.uiMOC)
        conversation.remoteIdentifier = NSUUID.createUUID()
        let payload = payloadForMessageInConversation(conversation, type: EventConversationAdd, data: ["foo": "bar"])
        let event = ZMUpdateEvent(fromEventStreamPayload: payload, uuid: NSUUID.createUUID())
        return event
    }
    
    func testThatItProcessesEvents() {
        // given
        let event = dummyEvent()
        
        // when
        var didCallBlock = false
        sut.processEvents([event]) { (events) in
            XCTAssertTrue(events.contains(event))
            didCallBlock = true
        }

        XCTAssert(waitForAllGroupsToBeEmptyWithTimeout(0.5))
        
        // then
        XCTAssertTrue(didCallBlock)
    }
    
    func testThatItProcessesPreviouslyStoredEventsFirst() {
        // given
        
        EventDecoder.testingBatchSize = 1
        
        let event1 = dummyEvent()
        let event2 = dummyEvent()
        let _ = StoredUpdateEvent.create(event1, managedObjectContext: eventMOC, index: 0)
        eventMOC.saveOrRollback()
        
        // when
        var callCount = 0
        sut.processEvents([event2]) { (events) in
            if callCount == 0 {
                XCTAssertTrue(events.contains(event1))
            } else if callCount == 1 {
                XCTAssertTrue(events.contains(event2))
            } else {
                XCTFail("called too often")
            }
            callCount += 1
        }
        XCTAssert(waitForAllGroupsToBeEmptyWithTimeout(0.5))
        
        // then
        XCTAssertEqual(callCount, 2)
    }
    
    func testThatItProcessesInBatches() {
        // given
        EventDecoder.testingBatchSize = 2
        
        let event1 = dummyEvent()
        let event2 = dummyEvent()
        let event3 = dummyEvent()
        let event4 = dummyEvent()
        
        let _ = StoredUpdateEvent.create(event1, managedObjectContext: eventMOC, index: 0)
        let _ = StoredUpdateEvent.create(event2, managedObjectContext: eventMOC, index: 1)
        let _ = StoredUpdateEvent.create(event3, managedObjectContext: eventMOC, index: 2)
        eventMOC.saveOrRollback()
        
        // when
        var callCount = 0
        sut.processEvents([event4]) { (events) in
            if callCount == 0 {
                XCTAssertTrue(events.contains(event1))
                XCTAssertTrue(events.contains(event2))
            } else if callCount == 1 {
                XCTAssertTrue(events.contains(event3))
                XCTAssertTrue(events.contains(event4))
            }
            else {
                XCTFail("called too often")
            }
            callCount += 1
        }
        XCTAssert(waitForAllGroupsToBeEmptyWithTimeout(0.5))
        
        // then
        XCTAssertEqual(callCount, 2)
    }

}
