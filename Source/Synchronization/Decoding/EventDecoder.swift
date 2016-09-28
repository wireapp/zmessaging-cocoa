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
import WireMessageStrategy

private let zmLog = ZMSLog(tag: "EventDecoder")

extension NSManagedObjectContext {
    
    fileprivate static var eventPersistentStoreCoordinator: NSPersistentStoreCoordinator?
    
    /// Creates and returns the `ManagedObjectContext` used for storing update events, ee `ZMEventModel`, `StorUpdateEvent` and `EventDecoder`.
    /// - parameter appGroupIdentifier: Optional identifier for a shared container group to be used to store the database,
    /// if `nil` is passed a default of `group. + bundleIdentifier` will be used (e.g. when testing)
    public static func createEventContext(withAppGroupIdentifier appGroupIdentifier: String?) -> NSManagedObjectContext {
        eventPersistentStoreCoordinator = createPersistentStoreCoordinator()
        let managedObjectContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        managedObjectContext.persistentStoreCoordinator = eventPersistentStoreCoordinator
        managedObjectContext.createDispatchGroups()
        
        addPersistentStore(eventPersistentStoreCoordinator!, appGroupIdentifier: appGroupIdentifier)
        return managedObjectContext
    }
    
    public func tearDown() {
        if let store = persistentStoreCoordinator?.persistentStores.first {
            try! persistentStoreCoordinator?.remove(store)
        }
        
        type(of: self).eventPersistentStoreCoordinator = nil
    }
    
    fileprivate static func createPersistentStoreCoordinator() -> NSPersistentStoreCoordinator {
        guard let modelURL = Bundle(for: StoredUpdateEvent.self).url(forResource: "ZMEventModel", withExtension:"momd") else {
            fatalError("Error loading model from bundle")
        }
        guard let mom = NSManagedObjectModel(contentsOf: modelURL) else {
            fatalError("Error initializing mom from: \(modelURL)")
        }
        return NSPersistentStoreCoordinator(managedObjectModel: mom)
    }
    
    fileprivate static func addPersistentStore(_ psc: NSPersistentStoreCoordinator, appGroupIdentifier: String?, isSecondTry: Bool = false) {
        guard let storeURL = storeURL(forAppGroupIdentifier: appGroupIdentifier) else { return }
        do {
            let storeType = useInMemoryStore() ? NSInMemoryStoreType : NSSQLiteStoreType
            try psc.addPersistentStore(ofType: storeType, configurationName: nil, at: storeURL, options: nil)
        } catch {
            if isSecondTry {
                zmLog.error("Error adding persistent store \(error)")
            } else {
                let stores = psc.persistentStores
                stores.forEach { try! psc.remove($0) }
                addPersistentStore(psc, appGroupIdentifier: appGroupIdentifier, isSecondTry: true)
            }
        }
    }
    
    fileprivate static func storeURL(forAppGroupIdentifier appGroupdIdentifier: String?) -> URL? {
        let fileManager = FileManager.default
        
        guard let identifier = Bundle.main.bundleIdentifier ?? Bundle(for: ZMUser.self).bundleIdentifier else { return nil }
        let groupIdentifier = appGroupdIdentifier ?? "group.\(identifier)"
        let directoryInContainer = fileManager.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier)
        
        let directory: URL
        
        if directoryInContainer != .none {
            directory = directoryInContainer!
        }
        else {
            // Seems like the shared container is not available. This could happen for series of reasons:
            // 1. The app is compiled with with incorrect provisioning profile (for example with 3rd parties)
            // 2. App is running on simulator and there is no correct provisioning profile on the system
            // 3. Bug with signing
            //
            // The app should allow not having a shared container in cases 1 and 2; in case 3 the app should crash
            
            let deploymentEnvironment = ZMDeploymentEnvironment().environmentType()
            if TARGET_IPHONE_SIMULATOR == 0 && (deploymentEnvironment == ZMDeploymentEnvironmentType.appStore || deploymentEnvironment == ZMDeploymentEnvironmentType.internal) {
                return nil
            }
            else {
                directory = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first!
                zmLog.error(String(format: "ERROR: self.databaseDirectoryURL == nil and deploymentEnvironment = %d", deploymentEnvironment.rawValue))
                zmLog.error("================================WARNING================================")
                zmLog.error("Wire is going to use APPLICATION SUPPORT directory to host the EventDecoder database")
                zmLog.error("================================WARNING================================")
            }
        }
        
        var _storeURL = directory.appendingPathComponent(identifier)
        
        if !fileManager.fileExists(atPath: _storeURL.path) {
            do {
                try fileManager.createDirectory(at: _storeURL, withIntermediateDirectories: true, attributes: nil)
            } catch {
                assertionFailure("Failed to get or create directory \(error)")
            }
        }
        
        do {
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try _storeURL.setResourceValues(values)
        } catch {
            assertionFailure("Error excluding \(_storeURL.path) from backup: \(error)")
        }
        
        let storeFileName = "ZMEventModel.sqlite"
        return _storeURL.appendingPathComponent(storeFileName)
    }
}

@objc public final class EventDecoder: NSObject {
    
    public typealias ConsumeBlock = (([ZMUpdateEvent]) -> Void)
    
    static var BatchSize : Int {
        if let testingBatchSize = testingBatchSize {
            return testingBatchSize
        }
        return 500
    }
    
    /// Set this for testing purposes only
    static var testingBatchSize : Int?
    
    let eventMOC : NSManagedObjectContext
    let syncMOC: NSManagedObjectContext
    
    fileprivate typealias EventsWithStoredEvents = (storedEvents: [StoredUpdateEvent], updateEvents: [ZMUpdateEvent])
    
    public init(eventMOC: NSManagedObjectContext, syncMOC: NSManagedObjectContext) {
        self.eventMOC = eventMOC
        self.syncMOC = syncMOC
        super.init()
    }
    
    /// Decrypts passed in events and stores them in chronological order in a persisted database. It then saves the database and cryptobox
    /// It then calls the passed in block (multiple times if necessary), returning the decrypted events
    /// If the app crashes while processing the events, they can be recovered from the database
    /// Recovered events are processed before the passed in events to reflect event history
    public func processEvents(_ events: [ZMUpdateEvent], block: ConsumeBlock) {
        
        var lastIndex: Int64?
        
        eventMOC.performGroupedBlockAndWait {
            // Get the highest index of events in the DB
            lastIndex = StoredUpdateEvent.highestIndex(self.eventMOC)
        }
        
        guard let index = lastIndex else { return }

        storeEvents(events, startingAtIndex: index)
        process(block, firstCall: true)
    }
    
    /// Decrypts and stores the decrypted events as `StoreUpdateEvent` in the event database.
    /// The encryption context is only closed after the events have been stored, which ensures
    /// they can be decrypted again in case of a crash.
    /// - parameter events The new events that should be decrypted and stored in the database.
    /// - parameter startingAtIndex The startIndex to be used for the incrementing sortIndex of the stored events.
    fileprivate func storeEvents(_ events: [ZMUpdateEvent], startingAtIndex startIndex: Int64) {
        syncMOC.zm_cryptKeyStore.encryptionContext.perform { [weak self] (sessionsDirectory) in
            guard let `self` = self else { return }
            
            let newUpdateEvents = events.flatMap { sessionsDirectory.decryptUpdateEventAndAddClient($0, managedObjectContext: self.syncMOC) }
            
            // This call has to be synchronous to ensure that we close the
            // encryption context only if we stored all events in the database
            self.eventMOC.performGroupedBlockAndWait {
                
                // Insert the decryted events in the event database using a `storeIndex`
                // incrementing from the highest index currently stored in the database
                for (idx, event) in newUpdateEvents.enumerated() {
                    _ = StoredUpdateEvent.create(event, managedObjectContext: self.eventMOC, index: idx + startIndex + 1)
                }
                
                self.eventMOC.saveOrRollback()
            }
        }
    }
    
    // Processes the stored events in the database in batches of size EventDecoder.BatchSize` and calls the `consumeBlock` for each batch.
    // After the `consumeBlock` has been called the stored events are deleted from the database.
    // This method terminates when no more events are in the database.
    fileprivate func process(_ consumeBlock: ConsumeBlock, firstCall: Bool) {
        let events = fetchNextEventsBatch()
        guard events.storedEvents.count > 0 else {
            if firstCall {
                consumeBlock([])
            }
            return
        }

        processBatch(events.updateEvents, storedEvents: events.storedEvents, block: consumeBlock)
        process(consumeBlock, firstCall: false)
    }
    
    /// Calls the `ComsumeBlock` and deletes the respective stored events subsequently.
    fileprivate func processBatch(_ events: [ZMUpdateEvent], storedEvents: [NSManagedObject], block: ConsumeBlock) {
        block(events)
        
        eventMOC.performGroupedBlockAndWait {
            storedEvents.forEach(self.eventMOC.delete(_:))
            self.eventMOC.saveOrRollback()
        }
    }
    
    /// Fetches and returns the next batch of size `EventDecoder.BatchSize` 
    /// of `StoredEvents` and `ZMUpdateEvent`'s in a `EventsWithStoredEvents` tuple.
    fileprivate func fetchNextEventsBatch() -> EventsWithStoredEvents {
        var (storedEvents, updateEvents)  = ([StoredUpdateEvent](), [ZMUpdateEvent]())

        eventMOC.performGroupedBlockAndWait {
            storedEvents = StoredUpdateEvent.nextEvents(self.eventMOC, batchSize: EventDecoder.BatchSize)
            updateEvents = StoredUpdateEvent.eventsFromStoredEvents(storedEvents)
        }
        
        return (storedEvents: storedEvents, updateEvents: updateEvents)
    }
    
}

