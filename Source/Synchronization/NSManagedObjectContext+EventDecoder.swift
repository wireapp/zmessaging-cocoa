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
import WireSystem
import WireDataModel

private let zmLog = ZMSLog(tag: "EventDecoder")

@objc extension NSManagedObjectContext {
    
    fileprivate static var eventPersistentStoreCoordinator: NSPersistentStoreCoordinator?
    
    /// Creates and returns the `ManagedObjectContext` used for storing update events, ee `ZMEventModel`, `StorUpdateEvent` and `EventDecoder`.
    /// - parameter appGroupIdentifier: identifier for a shared container group to be used to store the database,
    /// - parameter userIdentifier: identifier for the user account which the context should be used with.
    public static func createEventContext(withSharedContainerURL sharedContainerURL: URL, userIdentifier: UUID) -> NSManagedObjectContext {
        createOrRelocateStoreIfNeeded(sharedContainerURL: sharedContainerURL, userIdentifier: userIdentifier)
        
        return createEventContext(at: storeURL(withSharedContainerURL: sharedContainerURL, userIdentifier: userIdentifier))
    }
    
    internal static func createEventContext(at location : URL) -> NSManagedObjectContext {        
        eventPersistentStoreCoordinator = createPersistentStoreCoordinator()
        
        let managedObjectContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        managedObjectContext.persistentStoreCoordinator = eventPersistentStoreCoordinator
        managedObjectContext.createDispatchGroups()
        managedObjectContext.performGroupedBlock {
            managedObjectContext.isEventMOC = true
        }
        
        addPersistentStore(eventPersistentStoreCoordinator!, at: location)
        
        return managedObjectContext
    }
    
    fileprivate static func createOrRelocateStoreIfNeeded(sharedContainerURL: URL, userIdentifier: UUID) {
        let newStoreURL = storeURL(withSharedContainerURL: sharedContainerURL, userIdentifier: userIdentifier)
        let fileManager = FileManager.default
        
        guard !fileManager.fileExists(atPath: newStoreURL.path) else { return }
        
        FileManager.default.createAndProtectDirectory(at: newStoreURL.deletingLastPathComponent())
        
        var oldStoreURL : URL?
        let previousLocations = previousEventStoreLocations(userIdentifier: userIdentifier, sharedContainerURL: sharedContainerURL)
        for previousLocation in previousLocations {
            if fileManager.fileExists(atPath: previousLocation.path) {
                oldStoreURL = previousLocation
                break
            }
        }
        
        if let oldStoreURL = oldStoreURL {
            PersistentStoreRelocator.moveStore(from: oldStoreURL, to: newStoreURL)
        }
    }
    
    fileprivate static func relocateStoreIfNeeded(previousStoreURL: URL, newStoreURL: URL) {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: previousStoreURL.path) && !fileManager.fileExists(atPath: newStoreURL.path) {
            PersistentStoreRelocator.moveStore(from: previousStoreURL, to: newStoreURL)
        }
    }

    public func tearDownEventMOC() {
        if let store = persistentStoreCoordinator?.persistentStores.first {
            try! persistentStoreCoordinator?.remove(store)
        }
        
        Swift.type(of: self).eventPersistentStoreCoordinator = nil
    }

    var isEventMOC: Bool {
        set { userInfo[IsEventContextKey] = newValue }
        get { return (userInfo.object(forKey: IsEventContextKey) as? Bool) ?? false }
    }

    fileprivate static func createPersistentStoreCoordinator() -> NSPersistentStoreCoordinator {
        guard let modelURL = Bundle(for: StoredUpdateEvent.self).url(forResource: "ZMEventModel", withExtension:"momd") else {
            fatal("Error loading model from bundle")
        }
        guard let mom = NSManagedObjectModel(contentsOf: modelURL) else {
            fatal("Error initializing mom from: \(modelURL)")
        }
        return NSPersistentStoreCoordinator(managedObjectModel: mom)
    }
    
    fileprivate static func addPersistentStore(_ psc: NSPersistentStoreCoordinator, at location: URL, isSecondTry: Bool = false) {
        do {
            let options: [String: Any] = [
                NSMigratePersistentStoresAutomaticallyOption: true,
                NSInferMappingModelAutomaticallyOption: true
            ]
            let storeType = StorageStack.shared.createStorageAsInMemory ? NSInMemoryStoreType : NSSQLiteStoreType
            try psc.addPersistentStore(ofType: storeType, configurationName: nil, at: location, options: options)
        } catch {
            if isSecondTry {
                fatal("Error adding persistent store \(error)")
            } else {
                let stores = psc.persistentStores
                stores.forEach { try! psc.remove($0) }
                addPersistentStore(eventPersistentStoreCoordinator!, at: location, isSecondTry: true)
                
            }
        }
    }
    
    
    fileprivate static func addPersistentStore(_ psc: NSPersistentStoreCoordinator, withSharedContainerURL sharedContainerURL: URL, userIdentifier: UUID, isSecondTry: Bool = false) {
        let storeURL = self.storeURL(withSharedContainerURL: sharedContainerURL, userIdentifier: userIdentifier)
        do {
            let storeType = StorageStack.shared.createStorageAsInMemory ? NSInMemoryStoreType : NSSQLiteStoreType
            try psc.addPersistentStore(ofType: storeType, configurationName: nil, at: storeURL, options: nil)
        } catch {
            if isSecondTry {
                fatal("Error adding persistent store \(error)")
            } else {
                let stores = psc.persistentStores
                stores.forEach { try! psc.remove($0) }
                addPersistentStore(eventPersistentStoreCoordinator!, withSharedContainerURL: sharedContainerURL, userIdentifier: userIdentifier, isSecondTry: true)

            }
        }
    }
    
    fileprivate static func previousEventStoreLocations(userIdentifier : UUID, sharedContainerURL: URL) -> [URL] {
        return [sharedContainerURL, sharedContainerURL.appendingPathComponent(userIdentifier.uuidString)].map({ $0.appendingPathComponent("ZMEventModel.sqlite") })
    }
    
    fileprivate static func storeURL(withSharedContainerURL sharedContainerURL: URL, userIdentifier: UUID) -> URL {
        let storeURL = sharedContainerURL.appendingPathComponent("AccountData", isDirectory: true)
                       .appendingPathComponent(userIdentifier.uuidString, isDirectory:true)
                       .appendingPathComponent("events", isDirectory:true)
        
        let storeFileName = "ZMEventModel.sqlite"
        return storeURL.appendingPathComponent(storeFileName, isDirectory: false)
    }
}
