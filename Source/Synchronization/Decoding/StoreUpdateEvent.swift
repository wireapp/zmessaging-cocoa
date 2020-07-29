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
public final class StoredUpdateEvent: NSManagedObject {
    
    static let entityName =  "StoredUpdateEvent"
    static let SortIndexKey = "sortIndex"
    @NSManaged var uuidString: String?
    @NSManaged var debugInformation: String?
    @NSManaged var isTransient: Bool
    @NSManaged var payload: NSDictionary?
    @NSManaged var encryptedPayload: NSData?
    @NSManaged var source: Int16
    @NSManaged var sortIndex: Int64
    
    static func insertNewObject(_ context: NSManagedObjectContext) -> StoredUpdateEvent? {
        return NSEntityDescription.insertNewObject(forEntityName: self.entityName, into: context) as? StoredUpdateEvent
    }
    
    /// Maps a passed in `ZMUpdateEvent` to a `StoredUpdateEvent` which is persisted in a database
    /// The passed in `index` is used to enumerate events to be able to fetch and sort them later on in the order they were received
    public static func create(_ event: ZMUpdateEvent, managedObjectContext: NSManagedObjectContext, index: Int64) -> StoredUpdateEvent? {
        guard let storedEvent = StoredUpdateEvent.insertNewObject(managedObjectContext) else { return nil }
        storedEvent.debugInformation = event.debugInformation
        storedEvent.isTransient = event.isTransient
        storedEvent.payload = event.payload as NSDictionary
        storedEvent.source = Int16(event.source.rawValue)
        storedEvent.sortIndex = index
        storedEvent.uuidString = event.uuid?.transportString()
        return storedEvent
    }
    
    /// Maps a passed in `ZMUpdateEvent` to a `StoredUpdateEvent` which is persisted in a database
    /// - Parameters:
    ///   - event: received events
    ///   - managedObjectContext: current managedObjectContext
    ///   - index: the passed in `index` is used to enumerate events to be able to fetch and sort them later on in the order they were received
    ///   - publicKey: the publicKey which will be used to encrypt update events
    /// - Returns: storedEvent which will be persisted in a database
    public static func encryptAndCreate(_ event: ZMUpdateEvent, managedObjectContext: NSManagedObjectContext, index: Int64, publicKey: SecKey?) -> StoredUpdateEvent? {
        guard let storedEvent = StoredUpdateEvent.insertNewObject(managedObjectContext) else { return nil }
        storedEvent.debugInformation = event.debugInformation
        storedEvent.isTransient = event.isTransient
        storedEvent.source = Int16(event.source.rawValue)
        storedEvent.sortIndex = index
        storedEvent.uuidString = event.uuid?.transportString()
        guard let publicKey = publicKey,
            let data = try? JSONSerialization.data(withJSONObject: event.payload, options: []) else {
                storedEvent.payload = event.payload as NSDictionary
                return storedEvent
        }
        storedEvent.encryptedPayload = SecKeyCreateEncryptedData(publicKey,
                                                                 .eciesEncryptionCofactorX963SHA256AESGCM,
                                                                 data as CFData,
                                                                 nil)
        return storedEvent
    }
    
    /// Returns stored events sorted by and up until (including) the defined `stopIndex`
    /// Returns a maximum of `batchSize` events at a time
    public static func nextEvents(_ context: NSManagedObjectContext, batchSize: Int) -> [StoredUpdateEvent] {
        let fetchRequest = NSFetchRequest<StoredUpdateEvent>(entityName: self.entityName)
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: StoredUpdateEvent.SortIndexKey, ascending: true)]
        fetchRequest.fetchLimit = batchSize
        fetchRequest.returnsObjectsAsFaults = false
        let result = context.fetchOrAssert(request: fetchRequest)
        return result
    }
    
    /// Returns the highest index of all stored events
    public static func highestIndex(_ context: NSManagedObjectContext) -> Int64 {
        let fetchRequest = NSFetchRequest<StoredUpdateEvent>(entityName: self.entityName)
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: StoredUpdateEvent.SortIndexKey, ascending: false)]
        fetchRequest.fetchBatchSize = 1
        let result = context.fetchOrAssert(request: fetchRequest)
        return result.first?.sortIndex ?? 0
    }
    
    /// Maps passed in objects of type `StoredUpdateEvent` to `ZMUpdateEvent`
    public static func eventsFromStoredEvents(_ storedEvents: [StoredUpdateEvent], encryptionKeys: EncryptionKeys? = nil) -> [ZMUpdateEvent] {
        let events : [ZMUpdateEvent] = storedEvents.compactMap {
            var eventUUID : UUID?
            var payload : NSDictionary?
            if let uuid = $0.uuidString {
                eventUUID = UUID(uuidString: uuid)
            }
            if let encryptionKeys = encryptionKeys,
                let encryptedPayload = $0.encryptedPayload {
                let test = SecKeyCreateDecryptedData(encryptionKeys.privateKey,
                                                     .eciesEncryptionCofactorX963SHA256AESGCM,
                                                     encryptedPayload,
                                                     nil)
                payload = try? JSONSerialization.jsonObject(with: test! as Data, options: []) as? NSDictionary
            } else {
                payload = $0.payload
            }
            
            guard let _ = payload else {
                return nil
            }
            let decryptedEvent = ZMUpdateEvent.decryptedUpdateEvent(fromEventStreamPayload: payload!, uuid:eventUUID, transient: $0.isTransient, source: ZMUpdateEventSource(rawValue:Int($0.source))!)
            if let debugInfo = $0.debugInformation {
                decryptedEvent?.appendDebugInformation(debugInfo)
            }
            return decryptedEvent
        }
        return events
    }
}
