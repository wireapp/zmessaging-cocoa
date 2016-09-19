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
        eventMOC.add(dispatchGroup)
    }
    
    override func tearDown() {
        eventMOC.tearDown()
        super.tearDown()
    }
    
    func dummyEvent() -> ZMUpdateEvent {
        let conversation = ZMConversation.insertNewObject(in: syncMOC)
        conversation.remoteIdentifier = UUID.create()
        let payload = payloadForMessage(in: conversation, type: EventConversationAdd, data: ["foo": "bar"])!
        return ZMUpdateEvent(fromEventStreamPayload: payload, uuid: UUID.create())!
    }
    
    func insert(_ events: [ZMUpdateEvent], startIndex: Int64 = 0) {
        eventMOC.performGroupedBlockAndWait {
            events.enumerated().forEach { index, event  in
                let _ = StoredUpdateEvent.create(event, managedObjectContext: self.eventMOC, index: startIndex + index)
            }
            
            XCTAssert(self.eventMOC.saveOrRollback())
        }
    }
    
    func testThatItProcessesEvents() {
        
        var didCallBlock = false
        
        syncMOC.performGroupedBlock {
            // given
            let event = self.dummyEvent()
            
            // when
            self.sut.processEvents([event]) { (events) in
                XCTAssertTrue(events.contains(event))
                didCallBlock = true
            }
        }
        
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertTrue(didCallBlock)
    }
    
    func testThatItProcessesPreviouslyStoredEventsFirst() {
        
        EventDecoder.testingBatchSize = 1
        var callCount = 0
        
        syncMOC.performGroupedBlock {
            // given
            let event1 = self.dummyEvent()
            let event2 = self.dummyEvent()
            self.insert([event1])
            
            // when
            
            self.sut.processEvents([event2]) { (events) in
                if callCount == 0 {
                    XCTAssertTrue(events.contains(event1))
                } else if callCount == 1 {
                    XCTAssertTrue(events.contains(event2))
                } else {
                    XCTFail("called too often")
                }
                callCount += 1
            }
        }
        
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertEqual(callCount, 2)
    }
    
    func testThatItProcessesInBatches() {
        
        EventDecoder.testingBatchSize = 2
        var callCount = 0
        
        syncMOC.performGroupedBlock {
            
            // given
            let event1 = self.dummyEvent()
            let event2 = self.dummyEvent()
            let event3 = self.dummyEvent()
            let event4 = self.dummyEvent()
            
            self.insert([event1, event2, event3])
            
            // when
            self.sut.processEvents([event4]) { (events) in
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
        }
        
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertEqual(callCount, 2)
    }
    
    func testThatItDoesNotProcessTheSameEventsTwiceWhenCalledSuccessively() {
        
        EventDecoder.testingBatchSize = 2
        
        syncMOC.performGroupedBlock {
            
            // given
            let event1 = self.dummyEvent()
            let event2 = self.dummyEvent()
            let event3 = self.dummyEvent()
            let event4 = self.dummyEvent()
            
            self.insert([event1])
            
            self.sut.processEvents([event2]) { (events) in
                XCTAssert(events.contains(event1))
                XCTAssert(events.contains(event2))
            }
            
            self.insert([event3], startIndex: 1)
            
            // when
            self.sut.processEvents([event4]) { (events) in
                XCTAssertFalse(events.contains(event1))
                XCTAssertFalse(events.contains(event2))
                XCTAssertTrue(events.contains(event3))
                XCTAssertTrue(events.contains(event4))
            }
        }
        
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
    }
    
}
