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

class StoredUpdateEventTests: MessagingTest {

    var eventMOC = NSManagedObjectContext.createEventContext(withAppGroupIdentifier: nil)

    override func tearDown() {
        eventMOC.tearDown()
        super.tearDown()
    }
    
    func testThatYouCanCreateAnEvent(){
        
        // given
        let conversation = ZMConversation.insertNewObjectInManagedObjectContext(self.uiMOC)
        conversation.remoteIdentifier = NSUUID.createUUID()
        let payload = self .payloadForMessageInConversation(conversation, type: EventConversationAdd, data: ["foo": "bar"])
        let event = ZMUpdateEvent(fromEventStreamPayload: payload, uuid: NSUUID.createUUID())
        event.appendDebugInformation("Highly informative description")
        
        // when
        if let storedEvent = StoredUpdateEvent.create(event, managedObjectContext: eventMOC, index: 0) {
            
            // then
            XCTAssertEqual(storedEvent.debugInformation, event.debugInformation)
            XCTAssertEqual(storedEvent.payload, event.payload)
            XCTAssertEqual(storedEvent.isTransient, event.isTransient)
            XCTAssertEqual(storedEvent.source, Int16(event.source.rawValue))
            XCTAssertEqual(storedEvent.sortIndex, 0)
            XCTAssertEqual(storedEvent.uuidString, event.uuid.transportString())
        } else {
            XCTFail("Did not create storedEvent")
        }
    }
    
    func testThatItOnlyFetchesEventsLowerOrEqualToStopIndex(){
        
        // given
        let conversation = ZMConversation.insertNewObjectInManagedObjectContext(self.uiMOC)
        conversation.remoteIdentifier = NSUUID.createUUID()
        let payload = self .payloadForMessageInConversation(conversation, type: EventConversationAdd, data: ["foo": "bar"])
        let event = ZMUpdateEvent(fromEventStreamPayload: payload, uuid: NSUUID.createUUID())
        
        guard let storedEvent1 = StoredUpdateEvent.create(event, managedObjectContext: eventMOC, index: 0),
            let storedEvent2 = StoredUpdateEvent.create(event, managedObjectContext: eventMOC, index: 1),
            let storedEvent3 = StoredUpdateEvent.create(event, managedObjectContext: eventMOC, index: 2)
            else {
                XCTFail("Could not create storedEvents")
                return
        }
        
        // when
        let storedEvents = StoredUpdateEvent.nextEvents(eventMOC, batchSize: 3, stopAtIndex:1)
        
        // then
        XCTAssertTrue(storedEvents.contains(storedEvent1))
        XCTAssertTrue(storedEvents.contains(storedEvent2))
        XCTAssertFalse(storedEvents.contains(storedEvent3))
    }
    
    func testThatItOrdersEventsBySortIndex(){
        
        // given
        let conversation = ZMConversation.insertNewObjectInManagedObjectContext(self.uiMOC)
        conversation.remoteIdentifier = NSUUID.createUUID()
        let payload = self .payloadForMessageInConversation(conversation, type: EventConversationAdd, data: ["foo": "bar"])
        let event = ZMUpdateEvent(fromEventStreamPayload: payload, uuid: NSUUID.createUUID())
        
        guard let storedEvent1 = StoredUpdateEvent.create(event, managedObjectContext: eventMOC, index: 0),
            let storedEvent2 = StoredUpdateEvent.create(event, managedObjectContext: eventMOC, index: 30),
            let storedEvent3 = StoredUpdateEvent.create(event, managedObjectContext: eventMOC, index: 10)
            else {
                XCTFail("Could not create storedEvents")
                return
        }
        
        // when
        let storedEvents = StoredUpdateEvent.nextEvents(eventMOC, batchSize: 3, stopAtIndex:30)
        
        // then
        XCTAssertEqual(storedEvents[0], storedEvent1)
        XCTAssertEqual(storedEvents[1], storedEvent3)
        XCTAssertEqual(storedEvents[2], storedEvent2)
    }
    
    func testThatItReturnsOnlyDefinedBatchSize(){
        
        // given
        let conversation = ZMConversation.insertNewObjectInManagedObjectContext(self.uiMOC)
        conversation.remoteIdentifier = NSUUID.createUUID()
        let payload = self .payloadForMessageInConversation(conversation, type: EventConversationAdd, data: ["foo": "bar"])
        let event = ZMUpdateEvent(fromEventStreamPayload: payload, uuid: NSUUID.createUUID())
        
        guard let storedEvent1 = StoredUpdateEvent.create(event, managedObjectContext: eventMOC, index: 0),
            let storedEvent2 = StoredUpdateEvent.create(event, managedObjectContext: eventMOC, index: 10),
            let storedEvent3 = StoredUpdateEvent.create(event, managedObjectContext: eventMOC, index: 30)
            else {
                XCTFail("Could not create storedEvents")
                return
        }
        
        // when
        let storedEvents = StoredUpdateEvent.nextEvents(eventMOC, batchSize: 2, stopAtIndex:30)
        
        // then
        XCTAssertEqual(storedEvents.count, 2)
        XCTAssertTrue(storedEvents.contains(storedEvent1))
        XCTAssertTrue(storedEvents.contains(storedEvent2))
        XCTAssertFalse(storedEvents.contains(storedEvent3))
    }
    
    func testThatItReturnsHighestIndex(){
        
        // given
        let conversation = ZMConversation.insertNewObjectInManagedObjectContext(self.uiMOC)
        conversation.remoteIdentifier = NSUUID.createUUID()
        let payload = self .payloadForMessageInConversation(conversation, type: EventConversationAdd, data: ["foo": "bar"])
        let event = ZMUpdateEvent(fromEventStreamPayload: payload, uuid: NSUUID.createUUID())
        
        guard let _ = StoredUpdateEvent.create(event, managedObjectContext: eventMOC, index: 0),
            let _ = StoredUpdateEvent.create(event, managedObjectContext: eventMOC, index: 1),
            let _ = StoredUpdateEvent.create(event, managedObjectContext: eventMOC, index: 2)
            else {
                XCTFail("Could not create storedEvents")
                return
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
                XCTFail("Could not create storedEvents")
                return
        }
        
        guard let restoredEvent = StoredUpdateEvent.eventsFromStoredEvents([storedEvent]).first
            else {
                XCTFail("Could not create original event")
                return
        }
        
        // then
        XCTAssertEqual(restoredEvent, event)
        XCTAssertEqual(restoredEvent.payload["foo"] as? String, event.payload["foo"] as? String)
        XCTAssertEqual(restoredEvent.isTransient, event.isTransient)
        XCTAssertEqual(restoredEvent.source, event.source)
        XCTAssertEqual(restoredEvent.uuid, event.uuid)
        
    }
}
