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
import XCTest
import WireTesting

public class DiskDatabaseTest: ZMTBaseTest {
    let storeURL = PersistentStoreRelocator.storeURL(in: .cachesDirectory)!
    var moc: NSManagedObjectContext!
    
    public override func setUp() {
        super.setUp()
        NSManagedObjectContext.setUseInMemoryStore(false)
        
        cleanUp()
        
        createDatabase()
        NSManagedObjectContext.prepareLocalStore(at: storeURL, backupCorruptedDatabase: false, synchronous: true) {
            self.moc = NSManagedObjectContext.createUserInterfaceContextWithStore(at: self.storeURL)
        }
        
        assert(self.waitForAllGroupsToBeEmpty(withTimeout: 1))
    }
    
    public override func tearDown() {
        super.tearDown()
        moc = nil
    }
    
    private func createDatabase() {
        NSManagedObjectContext.prepareLocalStore(at: storeURL, backupCorruptedDatabase: false, synchronous: true, completionHandler:nil)
        
        NSManagedObjectContext.resetSharedPersistentStoreCoordinator()
    }
    
    private func cleanUp() {
        let supportCachesPath = (storeURL as NSURL).deletingLastPathComponent!.path
        
        let fileManager = FileManager.default
        
        if fileManager.fileExists(atPath: supportCachesPath) {
            try? fileManager.removeItem(atPath: supportCachesPath)
        }
        
        NSManagedObjectContext.resetSharedPersistentStoreCoordinator()
        NSManagedObjectContext.resetUserInterfaceContext()
    }
}

