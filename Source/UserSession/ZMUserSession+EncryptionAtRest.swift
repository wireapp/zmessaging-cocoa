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
import LocalAuthentication
import WireDataModel

extension ZMUserSession {
    
    public var encryptMessagesAtRest: Bool {
        
        set {
            do {
                
                let account = Account(userName: "", userIdentifier: storeProvider.userIdentifier)

                try EncryptionKeys.deleteKeys(for: account)
                storeProvider.contextDirectory.clearEncryptionKeysInAllContexts()

                if newValue {
                    let keys = try EncryptionKeys.createKeys(for: account)
                    storeProvider.contextDirectory.storeEncryptionKeysInAllContexts(encryptionKeys: keys)
                }
                
                managedObjectContext.encryptMessagesAtRest = newValue
                managedObjectContext.saveOrRollback()
            } catch {
                Logging.EAR.error("Failed to enabling/disabling database encryption")
            }
        }
        
        get {
            return managedObjectContext.encryptMessagesAtRest
        }
    }
    
    public var isDatabaseLocked: Bool {
        managedObjectContext.encryptMessagesAtRest && managedObjectContext.encryptionKeys == nil
    }
        
    public func registerDatabaseLockedHandler(_ handler: @escaping (_ isDatabaseLocked: Bool) -> Void) -> Any {
        return NotificationInContext.addObserver(name: DatabaseEncryptionLockNotification.notificationName,
                                                 context: managedObjectContext.notificationContext,
                                                 queue: .main)
        { note in
            guard let note = note.userInfo[DatabaseEncryptionLockNotification.userInfoKey] as? DatabaseEncryptionLockNotification else { return }
            
            handler(note.databaseIsEncrypted)
        }
    }
    
    func lockDatabase() {
        guard managedObjectContext.encryptMessagesAtRest else { return }
        
        BackgroundActivityFactory.shared.notifyWhenAllBackgroundActivitiesEnd { [weak self] in
            self?.storeProvider.contextDirectory.clearEncryptionKeysInAllContexts()
        
            if let notificationContext = self?.managedObjectContext.notificationContext {
                DatabaseEncryptionLockNotification(databaseIsEncrypted: true).post(in: notificationContext)
            }
        }
    }
    
    public func unlockDatabase(with context: LAContext) throws {
        let account = Account(userName: "", userIdentifier: storeProvider.userIdentifier)
        let keys = try EncryptionKeys.init(account: account, context: context)

        storeProvider.contextDirectory.storeEncryptionKeysInAllContexts(encryptionKeys: keys)
        
        DatabaseEncryptionLockNotification(databaseIsEncrypted: false).post(in: managedObjectContext.notificationContext)
        
        syncManagedObjectContext.performGroupedBlock {
            guard let syncStrategy = self.syncStrategy else { return }
            
            let hasMoreEventsToProcess = syncStrategy.processEventsAfterUnlockingDatabase()
            
            self.managedObjectContext.performGroupedBlock { [weak self] in
                self?.isPerformingSync = hasMoreEventsToProcess
                self?.updateNetworkState()
            }
        }
    }
    
}
