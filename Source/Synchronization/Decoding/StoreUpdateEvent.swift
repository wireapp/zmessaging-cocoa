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

import Foundation
import CoreData

@objc(StoredUpdateEvent)
public class StoredUpdateEvent: NSManagedObject {
    
    static let entityName =  "StoredUpdateEvent"
    static let SortIndexKey = "sortIndex"
    @NSManaged var uuidString: String?
    @NSManaged var debugInformation: String?
    @NSManaged var isTransient: Bool
    @NSManaged var payload: NSDictionary
    @NSManaged var source: Int16
    @NSManaged var sortIndex: Int64
    
    static func insertNewObject(context: NSManagedObjectContext) -> StoredUpdateEvent? {
        return NSEntityDescription.insertNewObjectForEntityForName(self.entityName, inManagedObjectContext: context) as? StoredUpdateEvent
    }
    
    /// Maps a passed in `ZMUpdateEvent` to a `StoredUpdateEvent` which is persisted in a database
    /// The passed in `index` is used to enumerate events to be able to fetch and sort them later on in the order they were received
    public static func create(event: ZMUpdateEvent, managedObjectContext: NSManagedObjectContext, index: Int64) -> StoredUpdateEvent? {
        guard let storedEvent = StoredUpdateEvent.insertNewObject(managedObjectContext) else { return nil }
        storedEvent.debugInformation = event.debugInformation
        storedEvent.isTransient = event.isTransient
        storedEvent.payload = event.payload
        storedEvent.source = Int16(event.source.rawValue)
        storedEvent.sortIndex = index
        storedEvent.uuidString = event.uuid.transportString()
        return storedEvent
    }
    
    /// Returns stored events sorted by and up until (including) the defined `stopIndex`
    /// Returns a maximum of `batchSize` events at a time
    public static func nextEvents(context: NSManagedObjectContext, batchSize: Int) -> [StoredUpdateEvent] {
        let fetchRequest = NSFetchRequest(entityName: self.entityName)
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: StoredUpdateEvent.SortIndexKey, ascending: true)]
        fetchRequest.fetchLimit = batchSize
        fetchRequest.returnsObjectsAsFaults = false
        let result = context.executeFetchRequestOrAssert(fetchRequest)
        return result as? [StoredUpdateEvent] ?? []
    }
    
    /// Returns the highest index of all stored events
    public static func highestIndex(context: NSManagedObjectContext) -> Int64 {
        let fetchRequest = NSFetchRequest(entityName: self.entityName)
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: StoredUpdateEvent.SortIndexKey, ascending: false)]
        fetchRequest.fetchBatchSize = 1
        let result = context.executeFetchRequestOrAssert(fetchRequest)
        return result.first?.sortIndex ?? 0
    }
    
    /// Maps passed in objects of type `StoredUpdateEvent` to `ZMUpdateEvent`
    public static func eventsFromStoredEvents(storedEvents: [StoredUpdateEvent]) -> [ZMUpdateEvent] {
        let events : [ZMUpdateEvent] = storedEvents.flatMap{
            var eventUUID : NSUUID?
            if let uuid = $0.uuidString {
                eventUUID = NSUUID(UUIDString: uuid)
            }
            let decryptedEvent = ZMUpdateEvent.decryptedUpdateEventFromEventStreamPayload($0.payload, uuid:eventUUID, source: ZMUpdateEventSource(rawValue:Int($0.source))!)
            if let debugInfo = $0.debugInformation {
                decryptedEvent?.appendDebugInformation(debugInfo)
            }
            return decryptedEvent
        }
        return events
    }
}
