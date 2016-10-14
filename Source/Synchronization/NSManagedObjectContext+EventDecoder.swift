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
import ZMCSystem

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
