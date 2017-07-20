//
// Wire
// Copyright (C) 2017 Wire Swiss GmbH
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
import UIKit

private let zmLog = ZMSLog(tag: "LocalStoreProvider")

@objc public protocol LocalStoreProviderProtocol: NSObjectProtocol {
    var appGroupIdentifier: String { get }
    var storeExists: Bool { get }
    var storeURL: URL? { get }
    var keyStoreURL: URL? { get }
    var cachesURL: URL? { get }
    var sharedContainerDirectory: URL? { get }
    
    /// Whether the local store is ready to be opened. If it returns false, the user session can't be started yet
    var isStoreReady: Bool { get }

    /// Returns true if data store needs to be migrated.
    var needsToPrepareLocalStore: Bool { get }
    
    /// Should be called <b>before</b> using ZMUserSession when applications is started if needsToPrepareLocalStore returns true
    /// It will intialize persistent store and perform migration (if needed) on background thread.
    /// - Parameter completionHandler: called when local store is ready to be used (and the ZMUserSession is ready to be initialized). Called on an arbitrary thread, it is the responsability of the caller to switch to the desired thread.
    func prepareLocalStore(completion completionHandler: @escaping (() -> ()))
}

protocol FileManagerProtocol: class {
    func containerURL(forSecurityApplicationGroupIdentifier groupIdentifier: String) -> URL?
    func urls(for directory: FileManager.SearchPathDirectory, in domainMask: FileManager.SearchPathDomainMask) -> [URL]
}

extension FileManager: FileManagerProtocol {}


/// Encapsulates all storage related data and methods. LocalStoreProviderProtocol protocol
/// is used instead of concrete class to let us inject a custom implementation in tests
@objc public class LocalStoreProvider: NSObject {
    
    public let appGroupIdentifier: String
    let bundleIdentifier: String

    let fileManager: FileManagerProtocol
    init(bundleIdentifier: String, appGroupIdentifier: String, fileManager: FileManagerProtocol) {
        self.bundleIdentifier = bundleIdentifier
        self.appGroupIdentifier = appGroupIdentifier
        self.fileManager = fileManager
    }
    
    public override convenience init() {
        let bundle = Bundle.main
        let bundleIdentifier = bundle.bundleIdentifier!
        let groupIdentifier = "group." + bundleIdentifier
        self.init(bundleIdentifier: bundleIdentifier, appGroupIdentifier: groupIdentifier, fileManager: FileManager.default)
    }
}

extension LocalStoreProvider: LocalStoreProviderProtocol {
    
    public var sharedContainerDirectory: URL? {
        let directoryInContainer = fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
        
        guard let directory = directoryInContainer else {
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
                zmLog.error(String(format: "ERROR: self.databaseDirectoryURL == nil and deploymentEnvironment = %d", deploymentEnvironment.rawValue))
                zmLog.error("================================WARNING================================")
                zmLog.error("Wire is going to use APPLICATION SUPPORT directory to host the database")
                zmLog.error("================================WARNING================================")
            }
            return fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
        }
        return directory
    }
    
    public var cachesURL: URL? {
        return fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)?.appendingPathComponent("Library", isDirectory: true).appendingPathComponent("Caches", isDirectory: true)
    }
    
    public var isStoreReady: Bool {
        return NSManagedObjectContext.storeIsReady()
    }
    
    public var storeURL: URL? {
        return sharedContainerDirectory?.appendingPathComponent(bundleIdentifier, isDirectory: true).appendingPathComponent("store.wiredatabase")
    }
    
    public var keyStoreURL: URL? {
        return sharedContainerDirectory
    }
    
    public var storeExists: Bool {
        guard let storeURL = self.storeURL else { return false }
        return NSManagedObjectContext.storeExists(at: storeURL)
    }
    
    public var needsToPrepareLocalStore: Bool {
        guard let storeURL = self.storeURL else { return false }
        return NSManagedObjectContext.needsToPrepareLocalStore(at: storeURL)
    }
    
    public func prepareLocalStore(completion completionHandler: @escaping (() -> ())) {
        let environment = ZMDeploymentEnvironment().environmentType()
        let shouldBackupCorruptedDatabase = environment == .internal // TODO: on debug build as well
        
        NSManagedObjectContext.prepareLocalStore(at: self.storeURL, backupCorruptedDatabase: shouldBackupCorruptedDatabase, synchronous: false, completionHandler: completionHandler)
    }
    
}
