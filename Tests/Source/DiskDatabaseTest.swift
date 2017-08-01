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
        StorageStack.shared.createStorageAsInMemory = false
        
        cleanUp()
        createDatabase()

        let keyStoreURL = storeURL.deletingLastPathComponent()
        let semaphore = DispatchSemaphore(value: 0)

        StorageStack.shared.createManagedObjectContextDirectory(at: storeURL, keyStore: keyStoreURL) {
            self.moc = $0.uiContext
            semaphore.signal()
        }

        semaphore.wait()
        assert(self.waitForAllGroupsToBeEmpty(withTimeout: 1))
    }
    
    public override func tearDown() {
        super.tearDown()
        moc = nil
    }
    
    private func createDatabase() {
        let keyStoreURL = storeURL.deletingLastPathComponent()
        let semaphore = DispatchSemaphore(value: 0)

        StorageStack.shared.createManagedObjectContextDirectory(at: storeURL, keyStore: keyStoreURL) { _ in
            semaphore.signal()
        }

        semaphore.wait()
        StorageStack.reset()
    }
    
    private func cleanUp() {
        let supportCachesPath = (storeURL as NSURL).deletingLastPathComponent!.path
        
        let fileManager = FileManager.default
        
        if fileManager.fileExists(atPath: supportCachesPath) {
            try? fileManager.removeItem(atPath: supportCachesPath)
        }
        
        StorageStack.reset()
    }
}

