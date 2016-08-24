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


@objc public class EventDataController: NSObject {
    
    public static var useInMemoryStore: Bool = false
    
    public let managedObjectContext: NSManagedObjectContext = {
        let psc = EventDataController.createPersistentStoreCoordinator()
        
        let managedObjectContext = NSManagedObjectContext(concurrencyType: .PrivateQueueConcurrencyType)
        managedObjectContext.persistentStoreCoordinator = psc
        managedObjectContext.createDispatchGroups()
        
        EventDataController.addPersistentStore(psc)
        return managedObjectContext
    }()
    
    private static func createPersistentStoreCoordinator() -> NSPersistentStoreCoordinator {
        guard let modelURL = NSBundle(forClass: StoredUpdateEvent.self).URLForResource("ZMEventModel", withExtension:"momd") else {
            fatalError("Error loading model from bundle")
        }
        guard let mom = NSManagedObjectModel(contentsOfURL: modelURL) else {
            fatalError("Error initializing mom from: \(modelURL)")
        }
        return NSPersistentStoreCoordinator(managedObjectModel: mom)
    }
    
    private static func addPersistentStore(psc: NSPersistentStoreCoordinator, isSecondTry: Bool = false){
        guard let storeURL = EventDataController.storeURL else {return }
        do {
            let storeType = EventDataController.useInMemoryStore ? NSInMemoryStoreType : NSSQLiteStoreType
            try psc.addPersistentStoreWithType(storeType, configuration: nil, URL: storeURL, options: nil)
        } catch {
            if isSecondTry {
                zmLog.error("Error adding persistent store \(error)")
            } else {
                let stores = psc.persistentStores
                stores.forEach { try! psc.removePersistentStore($0) }
                addPersistentStore(psc, isSecondTry: true)
            }
        }
    }
    
    public func tearDown(){
        if let store = managedObjectContext.persistentStoreCoordinator?.persistentStores.first {
            try! managedObjectContext.persistentStoreCoordinator?.removePersistentStore(store)
        }
    }
    
    private static var storeURL : NSURL? {
        let fileManager = NSFileManager.defaultManager()
        guard let directory = fileManager.URLsForDirectory(.ApplicationSupportDirectory, inDomains: .UserDomainMask).last,
            let identifier = NSBundle.mainBundle().bundleIdentifier ?? NSBundle(forClass: ZMUser.self).bundleIdentifier
            else { return nil }
        let _storeURL =  directory.URLByAppendingPathComponent(identifier)
        
        if !fileManager.fileExistsAtPath(_storeURL.path!) {
            do {
                try fileManager.createDirectoryAtURL(_storeURL, withIntermediateDirectories: true, attributes: nil)
            }
            catch let error as NSError {
                assertionFailure("Failed to get or create directory \(error)")
            }
        }
        
        do {
            try _storeURL.setResourceValue(1, forKey:NSURLIsExcludedFromBackupKey)
        }
        catch let error as NSError {
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
    
    public init(eventMOC: NSManagedObjectContext, syncMOC: NSManagedObjectContext){
        self.eventMOC = eventMOC
        self.syncMOC = syncMOC
        self.encryptionContext = syncMOC.zm_cryptKeyStore.encryptionContext
        super.init()
    }
    
    /// Decrypts passed in events and stores them in chronological order in a persisted database. It then saves the database and cryptobox
    /// It then calls the passed in block (multiple times if necessary), returning the decrypted events
    /// If the app crashes while processing the events, they can be recovered from the database
    /// Recovered events are processed before the passed in events to reflect event history
    public func processEvents(events: [ZMUpdateEvent], block: ConsumeBlock){
        
        // fetch first batch of old events
        let batchSize = EventDecoder.BatchSize
        let oldStoredEvents = StoredUpdateEvent.nextEvents(eventMOC, batchSize: batchSize, stopAtIndex: nil)
        let oldEvents = StoredUpdateEvent.eventsFromStoredEvents(oldStoredEvents)
        
        // get highest index of events in DB
        var lastIndex = oldStoredEvents.last?.sortIndex ?? 0
        if oldStoredEvents.count == batchSize {
            lastIndex = StoredUpdateEvent.highestIndex(eventMOC)
        }

        // decryptEvents and insert counting upwards from highest index in DB
        var newStoredEvents = [StoredUpdateEvent]()
        var newEvents = [ZMUpdateEvent]()
        
        encryptionContext?.perform({ [weak self] (sessionsDirectory) in
            guard let strongSelf = self else { return }
            
            newEvents = events.flatMap { sessionsDirectory.decryptUpdateEventAndAddClient($0, managedObjectContext: strongSelf.syncMOC) }
            
            strongSelf.eventMOC.performGroupedBlockAndWait {
                // decryptEvents and insert counting upwards from highest index in DB
                for (idx, event) in newEvents.enumerate() {
                    if let storedEvent = StoredUpdateEvent.create(event, managedObjectContext: strongSelf.eventMOC, index: idx + lastIndex + 1) {
                        newStoredEvents.append(storedEvent)
                    }
                }
                
                strongSelf.eventMOC.saveOrRollback()
            }
        })
        
        // process old events
        consumeStoredEvents(oldStoredEvents, someEvents: oldEvents, lastIndexToFetch: lastIndex, consumeBlock: block)
        
        // process new events
        if newEvents.count > 0 {
            processBatch(newEvents, storedEvents: newStoredEvents, block: block)
        } else {
            block([])
        }
    }
    
    /// calls the consuming block and deletes the respective stored events subsequently
    private func processBatch(events:[ZMUpdateEvent], storedEvents:[StoredUpdateEvent], block: ConsumeBlock) {
        block(events)
        let strongEventMOC = eventMOC

        eventMOC.performGroupedBlockAndWait {
            storedEvents.forEach(strongEventMOC.deleteObject)
            strongEventMOC.saveOrRollback()
        }
    }
    
    
    /// consumes passed in stored events and fetches more events if the last passed in event is not the last event to fetch
    private func consumeStoredEvents(someStoredEvents: [StoredUpdateEvent], someEvents: [ZMUpdateEvent], lastIndexToFetch: Int64, consumeBlock: ConsumeBlock) {
        var storedEvents = someStoredEvents
        var events = someEvents
        
        var hasMoreEvents = true
        while hasMoreEvents {
            // if the index of the last fetched object is not the lastIndexToFetch, we have more objects to fetch
            hasMoreEvents = storedEvents.last?.sortIndex != lastIndexToFetch
            
            if events.count > 0 {
                processBatch(events, storedEvents: storedEvents, block: consumeBlock)
                events = []
                storedEvents = []
            }
            else {
                hasMoreEvents = false
            }
            
            if hasMoreEvents {
                storedEvents = StoredUpdateEvent.nextEvents(eventMOC, batchSize: EventDecoder.BatchSize, stopAtIndex: lastIndexToFetch)
                if storedEvents.count > 0 {
                    events = StoredUpdateEvent.eventsFromStoredEvents(storedEvents)
                } else {
                    hasMoreEvents = false
                }
            }
        }
    }
    
}

