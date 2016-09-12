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

class StoreUpdateEventTests: MessagingTest {

    var eventMOC: NSManagedObjectContext!

    override func setUp() {
        super.setUp()
        eventMOC = NSManagedObjectContext.createEventContext(withAppGroupIdentifier: nil)
        eventMOC.addGroup(self.dispatchGroup)
    }
    
    override func tearDown() {
        XCTAssertTrue(waitForAllGroupsToBeEmptyWithTimeout(0.5))
        eventMOC.tearDown()
        super.tearDown()
    }
    
    func testThatYouCanCreateAnEvent() {
        
        // given
        let conversation = ZMConversation.insertNewObjectInManagedObjectContext(self.uiMOC)
        conversation.remoteIdentifier = NSUUID.createUUID()
        let payload = self .payloadForMessageInConversation(conversation, type: EventConversationAdd, data: ["foo": "bar"])
        let event = ZMUpdateEvent(fromEventStreamPayload: payload, uuid: NSUUID.createUUID())
        event.appendDebugInformation("Highly informative description")
        
        // when
        if let storedEvent = StoredUpdateEvent.create(event, managedObjectContext: eventMOC, index: 2) {
            
            // then
            XCTAssertEqual(storedEvent.debugInformation, event.debugInformation)
            XCTAssertEqual(storedEvent.payload, event.payload)
            XCTAssertEqual(storedEvent.isTransient, event.isTransient)
            XCTAssertEqual(storedEvent.source, Int16(event.source.rawValue))
            XCTAssertEqual(storedEvent.sortIndex, 2)
            XCTAssertEqual(storedEvent.uuidString, event.uuid.transportString())
        } else {
            XCTFail("Did not create storedEvent")
        }
    }
    
    func testThatItFetchesAllStoredEvents() {
        
        // given
        let conversation = ZMConversation.insertNewObjectInManagedObjectContext(self.uiMOC)
        conversation.remoteIdentifier = NSUUID.createUUID()
        let payload = self .payloadForMessageInConversation(conversation, type: EventConversationAdd, data: ["foo": "bar"])
        let event = ZMUpdateEvent(fromEventStreamPayload: payload, uuid: NSUUID.createUUID())
        
        guard let storedEvent1 = StoredUpdateEvent.create(event, managedObjectContext: eventMOC, index: 0),
            let storedEvent2 = StoredUpdateEvent.create(event, managedObjectContext: eventMOC, index: 1),
            let storedEvent3 = StoredUpdateEvent.create(event, managedObjectContext: eventMOC, index: 2)
            else {
                return XCTFail("Could not create storedEvents")
        }
        
        // when
        let batch = StoredUpdateEvent.nextEvents(eventMOC, batchSize: 4)
        
        // then
        XCTAssertEqual(batch.count, 3)
        XCTAssertTrue(batch.contains(storedEvent1))
        XCTAssertTrue(batch.contains(storedEvent2))
        XCTAssertTrue(batch.contains(storedEvent3))
        batch.forEach{ XCTAssertFalse($0.fault) }
    }
    
    func testThatItOrdersEventsBySortIndex() {
        
        // given
        let conversation = ZMConversation.insertNewObjectInManagedObjectContext(self.uiMOC)
        conversation.remoteIdentifier = NSUUID.createUUID()
        let payload = self .payloadForMessageInConversation(conversation, type: EventConversationAdd, data: ["foo": "bar"])
        let event = ZMUpdateEvent(fromEventStreamPayload: payload, uuid: NSUUID.createUUID())
        
        guard let storedEvent1 = StoredUpdateEvent.create(event, managedObjectContext: eventMOC, index: 0),
            let storedEvent2 = StoredUpdateEvent.create(event, managedObjectContext: eventMOC, index: 30),
            let storedEvent3 = StoredUpdateEvent.create(event, managedObjectContext: eventMOC, index: 10)
            else {
                return XCTFail("Could not create storedEvents")
        }
        
        // when
        let storedEvents = StoredUpdateEvent.nextEvents(eventMOC, batchSize: 3)
        
        // then
        XCTAssertEqual(storedEvents[0], storedEvent1)
        XCTAssertEqual(storedEvents[1], storedEvent3)
        XCTAssertEqual(storedEvents[2], storedEvent2)
    }
    
    func testThatItReturnsOnlyDefinedBatchSize() {
        
        // given
        let conversation = ZMConversation.insertNewObjectInManagedObjectContext(self.uiMOC)
        conversation.remoteIdentifier = NSUUID.createUUID()
        let payload = self .payloadForMessageInConversation(conversation, type: EventConversationAdd, data: ["foo": "bar"])
        let event = ZMUpdateEvent(fromEventStreamPayload: payload, uuid: NSUUID.createUUID())
        
        guard let storedEvent1 = StoredUpdateEvent.create(event, managedObjectContext: eventMOC, index: 0),
            let storedEvent2 = StoredUpdateEvent.create(event, managedObjectContext: eventMOC, index: 10),
            let storedEvent3 = StoredUpdateEvent.create(event, managedObjectContext: eventMOC, index: 30)
            else {
                return XCTFail("Could not create storedEvents")
        }
        
        // when
        let firstBatch = StoredUpdateEvent.nextEvents(eventMOC, batchSize: 2)
        
        // then
        XCTAssertEqual(firstBatch.count, 2)
        XCTAssertTrue(firstBatch.contains(storedEvent1))
        XCTAssertTrue(firstBatch.contains(storedEvent2))
        XCTAssertFalse(firstBatch.contains(storedEvent3))
        
        // when
        firstBatch.forEach(eventMOC.deleteObject)
        let secondBatch = StoredUpdateEvent.nextEvents(eventMOC, batchSize: 2)
        
        // then
        XCTAssertEqual(secondBatch.count, 1)
        XCTAssertTrue(secondBatch.contains(storedEvent3))
    }
    
    func testThatItReturnsHighestIndex() {
        
        // given
        let conversation = ZMConversation.insertNewObjectInManagedObjectContext(self.uiMOC)
        conversation.remoteIdentifier = NSUUID.createUUID()
        let payload = self .payloadForMessageInConversation(conversation, type: EventConversationAdd, data: ["foo": "bar"])
        let event = ZMUpdateEvent(fromEventStreamPayload: payload, uuid: NSUUID.createUUID())
        
        guard let _ = StoredUpdateEvent.create(event, managedObjectContext: eventMOC, index: 0),
            let _ = StoredUpdateEvent.create(event, managedObjectContext: eventMOC, index: 1),
            let _ = StoredUpdateEvent.create(event, managedObjectContext: eventMOC, index: 2)
            else {
                return XCTFail("Could not create storedEvents")
        }
        
        // when
        let highestIndex = StoredUpdateEvent.highestIndex(eventMOC)
        
        // then
        XCTAssertEqual(highestIndex, 2)
    }
    
    func testThatItCanConvertAnEventToStoredEventAndBack() {
        
        // given
        let conversation = ZMConversation.insertNewObjectInManagedObjectContext(self.uiMOC)
        conversation.remoteIdentifier = NSUUID.createUUID()
        let payload = self .payloadForMessageInConversation(conversation, type: EventConversationAdd, data: ["foo": "bar"])
        let event = ZMUpdateEvent(fromEventStreamPayload: payload, uuid: NSUUID.createUUID())
        
        // when
        guard let storedEvent = StoredUpdateEvent.create(event, managedObjectContext: eventMOC, index: 0)
            else {
                return XCTFail("Could not create storedEvents")
                
        }
        
        guard let restoredEvent = StoredUpdateEvent.eventsFromStoredEvents([storedEvent]).first
            else {
                return XCTFail("Could not create original event")
        }
        
        // then
        XCTAssertEqual(restoredEvent, event)
        XCTAssertEqual(restoredEvent.payload["foo"] as? String, event.payload["foo"] as? String)
        XCTAssertEqual(restoredEvent.isTransient, event.isTransient)
        XCTAssertEqual(restoredEvent.source, event.source)
        XCTAssertEqual(restoredEvent.uuid, event.uuid)
        
    }
}
