//
// Wire
// Copyright (C) 2020 Wire Swiss GmbH
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

extension ManagedObjectContextDirectory: ZMManagedObjectContextProvider {
    
    public var managedObjectContext: NSManagedObjectContext! {
        return uiContext
    }
    
    public var syncManagedObjectContext: NSManagedObjectContext! {
        return syncContext
    }
    
}

class DatabaseTest: ZMTBaseTest {
    
    let accountId = UUID()
    var contextDirectory: ManagedObjectContextDirectory?
    
    var useInMemoryDatabase: Bool {
        return true
    }
    
    var uiMOC: NSManagedObjectContext {
        return self.contextDirectory!.uiContext
    }
    
    var syncMOC: NSManagedObjectContext {
        return self.contextDirectory!.syncContext
    }
    
    var searchMOC: NSManagedObjectContext {
        return self.contextDirectory!.searchContext
    }
    
    var sharedContainerURL: URL? {
        let bundleIdentifier = Bundle.main.bundleIdentifier
        let groupIdentifier = "group." + bundleIdentifier!
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier)
    }
    
    private func cleanUp() {
        try? FileManager.default.contentsOfDirectory(at: sharedContainerURL!, includingPropertiesForKeys: nil, options: .skipsHiddenFiles).forEach {
            try? FileManager.default.removeItem(at: $0)
        }
        
        StorageStack.reset()
    }
    
    private func createDatabase() {
        StorageStack.reset()
        
        let expectation = self.expectation(description: "Created context")
        StorageStack.shared.createStorageAsInMemory = useInMemoryDatabase
        StorageStack.shared.createManagedObjectContextDirectory(accountIdentifier: accountId, applicationContainer: sharedContainerURL!, dispatchGroup: self.dispatchGroup) {
            self.contextDirectory = $0
            expectation.fulfill()
        }
        XCTAssert(waitForCustomExpectations(withTimeout: 0.5))
    }
    
    override func setUp() {
        super.setUp()
        
        createDatabase()
    }
    
    override func tearDown() {
        cleanUp()
        contextDirectory = nil
        
        super.tearDown()
    }
    
    func performPretendingUIMocIsSyncMoc(_ block: () -> Void) {
        uiMOC.resetContextType()
        uiMOC.markAsSyncContext()
        block()
        uiMOC.resetContextType()
        uiMOC.markAsUIContext()
    }
    
}
