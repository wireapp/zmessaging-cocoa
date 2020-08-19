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


import WireTesting
@testable import WireSyncEngine

class UpdateEventsStoreMigrationTests: MessagingTest {

    var applicationContainer: URL {
        return FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("StorageStackTests")
    }

    var previousEventStoreLocations : [URL] {
        return [
            sharedContainerURL,
            sharedContainerURL.appendingPathComponent(userIdentifier.uuidString)
            ].map({ $0.appendingPathComponent("ZMEventModel.sqlite")})
    }

    func testThatItMigratesTheStoreFromOldLocation() throws {

        for oldEventStoreLocation in previousEventStoreLocations {

            // given
            StorageStack.shared.createStorageAsInMemory = false
            try FileManager.default.createDirectory(at: oldEventStoreLocation.deletingLastPathComponent(), withIntermediateDirectories: true)
            let eventMOC_oldLocation = NSManagedObjectContext.createEventContext(at: oldEventStoreLocation)
            eventMOC_oldLocation.add(self.dispatchGroup)

            // given
            let conversation = ZMConversation.insertNewObject(in: self.uiMOC)
            conversation.remoteIdentifier = UUID.create()
            let payload = self.payloadForMessage(in: conversation, type: EventConversationAdd, data: ["foo": "bar"])!
            let event = ZMUpdateEvent(fromEventStreamPayload: payload, uuid: UUID.create())!

            guard let storedEvent1 = StoredUpdateEvent.encryptAndCreate(event, managedObjectContext: eventMOC_oldLocation, index: 0),
                let storedEvent2 = StoredUpdateEvent.encryptAndCreate(event, managedObjectContext: eventMOC_oldLocation, index: 1),
                let storedEvent3 = StoredUpdateEvent.encryptAndCreate(event, managedObjectContext: eventMOC_oldLocation, index: 2)
                else {
                    return XCTFail("Could not create storedEvents")
            }
            try eventMOC_oldLocation.save()
            let objectIDs = Set([storedEvent1, storedEvent2, storedEvent3].map { $0.objectID.uriRepresentation() })
            eventMOC_oldLocation.tearDownEventMOC()
            XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))

            // when
            let eventMOC = NSManagedObjectContext.createEventContext(withSharedContainerURL: sharedContainerURL, userIdentifier: userIdentifier)
            let batch = StoredUpdateEvent.nextEvents(eventMOC, batchSize: 4)

            // then
            XCTAssertEqual(batch.count, 3)
            let loadedObjectIDs = Set(batch.map { $0.objectID.uriRepresentation() })

            XCTAssertEqual(objectIDs, loadedObjectIDs)
            batch.forEach{ XCTAssertFalse($0.isFault) }

            // cleanup
            removeFilesInSharedContainer()

        }
    }

    func testThatItReopensTheExistingStoreInNewLocation() throws {
        // given
        StorageStack.shared.createStorageAsInMemory = false
        let eventMOC_sameLocation = NSManagedObjectContext.createEventContext(withSharedContainerURL: sharedContainerURL, userIdentifier: userIdentifier)
        eventMOC_sameLocation.add(self.dispatchGroup)

        // given
        let conversation = ZMConversation.insertNewObject(in: self.uiMOC)
        conversation.remoteIdentifier = UUID.create()
        let payload = self.payloadForMessage(in: conversation, type: EventConversationAdd, data: ["foo": "bar"])!
        let event = ZMUpdateEvent(fromEventStreamPayload: payload, uuid: UUID.create())!
        
        guard let storedEvent1 = StoredUpdateEvent.encryptAndCreate(event, managedObjectContext: eventMOC_sameLocation, index: 0),
            let storedEvent2 = StoredUpdateEvent.encryptAndCreate(event, managedObjectContext: eventMOC_sameLocation, index: 1),
            let storedEvent3 = StoredUpdateEvent.encryptAndCreate(event, managedObjectContext: eventMOC_sameLocation, index: 2)
            else {
                return XCTFail("Could not create storedEvents")
        }
        
        try eventMOC_sameLocation.save()
        let objectIDs = Set([storedEvent1, storedEvent2, storedEvent3].map { $0.objectID.uriRepresentation() })
        eventMOC_sameLocation.tearDownEventMOC()
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))

        // when
        let eventMOC = NSManagedObjectContext.createEventContext(withSharedContainerURL: sharedContainerURL, userIdentifier: userIdentifier)
        let batch = StoredUpdateEvent.nextEvents(eventMOC, batchSize: 4)

        // then
        XCTAssertEqual(batch.count, 3)
        let loadedObjectIDs = Set(batch.map { $0.objectID.uriRepresentation() })

        XCTAssertEqual(objectIDs, loadedObjectIDs)
        batch.forEach{ XCTAssertFalse($0.isFault) }
    }
}
