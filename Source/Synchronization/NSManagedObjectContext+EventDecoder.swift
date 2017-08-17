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

extension NSManagedObjectContext {
    
    fileprivate static var eventPersistentStoreCoordinator: NSPersistentStoreCoordinator?
    
    /// Creates and returns the `ManagedObjectContext` used for storing update events, ee `ZMEventModel`, `StorUpdateEvent` and `EventDecoder`.
    /// - parameter appGroupIdentifier: Optional identifier for a shared container group to be used to store the database,
    /// if `nil` is passed a default of `group. + bundleIdentifier` will be used (e.g. when testing)
    public static func createEventContext(withSharedContainerURL sharedContainerURL: URL, userIdentifier: UUID?) -> NSManagedObjectContext {
        let previousStoreURL = storeURL(withSharedContainerURL: sharedContainerURL, userIdentifier: nil) // Passing no user identifier resolves to the old location before multiple accounts
        let newStoreURL = storeURL(withSharedContainerURL: sharedContainerURL, userIdentifier: userIdentifier)
        FileManager.default.createAndProtectDirectory(at: newStoreURL.deletingLastPathComponent())
        relocateStoreIfNeeded(previousStoreURL: previousStoreURL, newStoreURL: newStoreURL)
        eventPersistentStoreCoordinator = createPersistentStoreCoordinator()
        let managedObjectContext = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        managedObjectContext.persistentStoreCoordinator = eventPersistentStoreCoordinator
        managedObjectContext.createDispatchGroups()
        managedObjectContext.performGroupedBlock {
            managedObjectContext.isEventMOC = true
        }
        addPersistentStore(eventPersistentStoreCoordinator!, withSharedContainerURL: sharedContainerURL, userIdentifier: userIdentifier)
        return managedObjectContext
    }
    
    fileprivate static func relocateStoreIfNeeded(previousStoreURL: URL, newStoreURL: URL) {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: previousStoreURL.path) && !fileManager.fileExists(atPath: newStoreURL.path) {
            PersistentStoreRelocator.moveStore(from: previousStoreURL, to: newStoreURL)
        }
    }

    public func tearDownEventMOC() {
        precondition(isEventMOC, "Invalid operation: tearDownEventMOC called on context not marked as event MOC")
        if let store = persistentStoreCoordinator?.persistentStores.first {
            try! persistentStoreCoordinator?.remove(store)
        }
        
        type(of: self).eventPersistentStoreCoordinator = nil
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
    
    fileprivate static func addPersistentStore(_ psc: NSPersistentStoreCoordinator, withSharedContainerURL sharedContainerURL: URL, userIdentifier: UUID?, isSecondTry: Bool = false) {
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
    
    fileprivate static func storeURL(withSharedContainerURL sharedContainerURL: URL, userIdentifier: UUID?) -> URL {
        let storeURL: URL
        if let userIdentifier = userIdentifier {
            storeURL = sharedContainerURL.appendingPathComponent(userIdentifier.uuidString, isDirectory:true)
        } else {
            storeURL = sharedContainerURL
        }
        
        let storeFileName = "ZMEventModel.sqlite"
        return storeURL.appendingPathComponent(storeFileName, isDirectory: false)
    }
}
