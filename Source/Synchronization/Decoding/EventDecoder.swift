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
import Cryptobox
import ZMCDataModel

private let zmLog = ZMSLog(tag: "EventDecoder")

extension NSManagedObjectContext {

    private static var eventPersistentStoreCoordinator: NSPersistentStoreCoordinator?

    /// Creates and returns the `ManagedObjectContext` used for storing update events, ee `ZMEventModel`, `StorUpdateEvent` and `EventDecoder`.
    /// - parameter appGroupIdentifier: Optional identifier for a shared container group to be used to store the database,
    /// if `nil` is passed a default of `group. + bundleIdentifier` will be used (e.g. when testing)
    public static func createEventContext(withAppGroupIdentifier appGroupIdentifier: String?) -> NSManagedObjectContext {
        eventPersistentStoreCoordinator = createPersistentStoreCoordinator()
        let managedObjectContext = NSManagedObjectContext(concurrencyType: .PrivateQueueConcurrencyType)
        managedObjectContext.persistentStoreCoordinator = eventPersistentStoreCoordinator
        managedObjectContext.createDispatchGroups()
        
        addPersistentStore(eventPersistentStoreCoordinator!, appGroupIdentifier: appGroupIdentifier)
        return managedObjectContext
    }

    public func tearDown() {
        if let store = persistentStoreCoordinator?.persistentStores.first {
            try! persistentStoreCoordinator?.removePersistentStore(store)
        }
        
        self.dynamicType.eventPersistentStoreCoordinator = nil
    }

    private static func createPersistentStoreCoordinator() -> NSPersistentStoreCoordinator {
        guard let modelURL = NSBundle(forClass: StoredUpdateEvent.self).URLForResource("ZMEventModel", withExtension:"momd") else {
            fatalError("Error loading model from bundle")
        }
        guard let mom = NSManagedObjectModel(contentsOfURL: modelURL) else {
            fatalError("Error initializing mom from: \(modelURL)")
        }
        return NSPersistentStoreCoordinator(managedObjectModel: mom)
    }

    private static func addPersistentStore(psc: NSPersistentStoreCoordinator, appGroupIdentifier: String?, isSecondTry: Bool = false) {
        guard let storeURL = storeURL(forAppGroupIdentifier: appGroupIdentifier) else { return }
        do {
            let storeType = useInMemoryStore() ? NSInMemoryStoreType : NSSQLiteStoreType
            try psc.addPersistentStoreWithType(storeType, configuration: nil, URL: storeURL, options: nil)
        } catch {
            if isSecondTry {
                zmLog.error("Error adding persistent store \(error)")
            } else {
                let stores = psc.persistentStores
                stores.forEach { try! psc.removePersistentStore($0) }
                addPersistentStore(psc, appGroupIdentifier: appGroupIdentifier, isSecondTry: true)
            }
        }
    }

    private static func storeURL(forAppGroupIdentifier appGroupdIdentifier: String?) -> NSURL? {
        let fileManager = NSFileManager.defaultManager()
        
        guard let identifier = NSBundle.mainBundle().bundleIdentifier ?? NSBundle(forClass: ZMUser.self).bundleIdentifier else { return nil }
        let groupIdentifier = appGroupdIdentifier ?? "group.\(identifier)"
        guard let directory = fileManager.containerURLForSecurityApplicationGroupIdentifier(groupIdentifier) else { return nil }
        
        let _storeURL = directory.URLByAppendingPathComponent(identifier)
        
        if !fileManager.fileExistsAtPath(_storeURL.path!) {
            do {
                try fileManager.createDirectoryAtURL(_storeURL, withIntermediateDirectories: true, attributes: nil)
            } catch {
                assertionFailure("Failed to get or create directory \(error)")
            }
        }
        
        do {
            try _storeURL.setResourceValue(1, forKey: NSURLIsExcludedFromBackupKey)
        } catch {
            assertionFailure("Error excluding \(_storeURL.path!) from backup: \(error)")
        }
        
        let storeFileName = "ZMEventModel.sqlite"
        return _storeURL.URLByAppendingPathComponent(storeFileName)
    }
}

@objc public class EventDecoder: NSObject {
    
    public typealias ConsumeBlock = ([ZMUpdateEvent] -> Void)
    
    static var BatchSize : Int {
        if let testingBatchSize = testingBatchSize {
            return testingBatchSize
        }
        return 500
    }
    
    /// set this for testing purposes only
    static var testingBatchSize : Int?
    
    let eventMOC : NSManagedObjectContext
    let syncMOC: NSManagedObjectContext
    weak var encryptionContext : EncryptionContext?
    
    private typealias EventsWithStoredEvents = (storedEvents: [StoredUpdateEvent], updateEvents: [ZMUpdateEvent])
    
    public init(eventMOC: NSManagedObjectContext, syncMOC: NSManagedObjectContext) {
        self.eventMOC = eventMOC
        self.syncMOC = syncMOC
        self.encryptionContext = syncMOC.zm_cryptKeyStore.encryptionContext
        super.init()
    }
    
    /// Decrypts passed in events and stores them in chronological order in a persisted database. It then saves the database and cryptobox
    /// It then calls the passed in block (multiple times if necessary), returning the decrypted events
    /// If the app crashes while processing the events, they can be recovered from the database
    /// Recovered events are processed before the passed in events to reflect event history
    public func processEvents(events: [ZMUpdateEvent], block: ConsumeBlock) {
        
        eventMOC.performGroupedBlock {
            // Get the highest index of events in the DB
            let lastIndex = StoredUpdateEvent.highestIndex(self.eventMOC)
            
            // Store the new events
            self.storeEvents(events, startingAtIndex: lastIndex) {
                // Process all events in the database in batches
                self.process(block)
            }
        }

    }
    
    /// Decrypts and stores the decrypted events as `StoreUpdateEvent` in the event database.
    /// The encryption context is only closed after the events have been stored, which ensures 
    /// they can be decrypted again in case of a crash.
    /// - parameter events The new events that should be decrypted and stored in the database.
    /// - parameter completion The startIndex to be used for the incrementing sortIndex of the stored events.
    /// - parameter completion The completion closure to be called after the events have been stored and decrypted, called on the eventMOC queue.
    private func storeEvents(events: [ZMUpdateEvent], startingAtIndex startIndex: Int64, completion: () -> Void) {
        syncMOC.performGroupedBlock {
            self.encryptionContext?.perform { [weak self] (sessionsDirectory) in
                guard let strongSelf = self else { return }
                
                let newUpdateEvents = events.flatMap { sessionsDirectory.decryptUpdateEventAndAddClient($0, managedObjectContext: strongSelf.syncMOC) }
                
                // This call has to be synchronous to ensure that we close the
                // encryption context only if we stored all events in the database
                strongSelf.eventMOC.performGroupedBlockAndWait {
                    
                    // Decrypt the events and insert them counting upwards from the highest index in the DB
                    for (idx, event) in newUpdateEvents.enumerate() {
                        _ = StoredUpdateEvent.create(event, managedObjectContext: strongSelf.eventMOC, index: idx + startIndex + 1)
                    }
                    
                    strongSelf.eventMOC.saveOrRollback()
                }
            }
            
            self.eventMOC.performGroupedBlock {
                completion()
            }
        }
    }

    // Processes the stored events in the database in batches of size EventDecoder.BatchSize` and calls the `consumeBlock` for each batch.
    // After the `consumeBlock` has been called the stored events are deleted from the database.
    // This method terminates when no more events are in the database.
    private func process(consumeBlock: ConsumeBlock) {
        fetchNextEventsBatch { events in
            guard events.storedEvents.count > 0 else { return }

            self.processBatch(events.updateEvents, storedEvents: events.storedEvents, block: consumeBlock) {
                self.process(consumeBlock)
            }
        }
    }
    
    /// Calls the `ComsumeBlock` and deletes the respective stored events subsequently,
    /// The consume block is guaranteed to be called on the syncMOC's queue.
    /// The completion closure is invoked after the `StoredEvent`'s have been deleted on the eventMOC.
    private func processBatch(events: [ZMUpdateEvent], storedEvents: [NSManagedObject], block: ConsumeBlock, completion: () -> Void) {
        let strongEventMOC = eventMOC

        // switch to the sync queue to call the passed in block with the update events
        syncMOC.performGroupedBlock { 
            block(events)

            strongEventMOC.performGroupedBlock {
                storedEvents.forEach(strongEventMOC.deleteObject)
                strongEventMOC.saveOrRollback()
                completion()
            }
        }
    }
    
    /// Fetches the next batch of of size `EventDecoder.BatchSize` and calls the completion handler
    /// with the `StoredEvents` and `ZMUpdateEvent`'s in a `EventsWithStoredEvents` tuple.
    private func fetchNextEventsBatch(completion: (EventsWithStoredEvents) -> Void) {
        self.eventMOC.performGroupedBlock {
            let storedEvents = StoredUpdateEvent.nextEvents(self.eventMOC, batchSize: EventDecoder.BatchSize)
            let updateEvents = StoredUpdateEvent.eventsFromStoredEvents(storedEvents)
            return completion((storedEvents: storedEvents, updateEvents: updateEvents))
        }
    }
    
}

