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

public typealias ResultHandler<T> = (Result<T>) -> Void

extension ZMUserSession {

    /// Enable or disable encryption at rest.
    ///
    /// When toggling encryption at rest the existing database needs to be migrated. The migration happens
    /// asynchronously on the sync context and only after a successful migration is the feature toggled. In
    /// the case that the migration fails, the sync context is reset to a clean state.
    ///
    /// - Parameters:
    ///     - enabled: When `true`, messages will be encrypted at rest.
    ///     - completion: Invoked on the main thread when the update succeeds or fails.

    public func setEncryptionAtRest(enabled: Bool, completion: ResultHandler<Void>? = nil) {
        guard enabled != encryptMessagesAtRest else { return }

        let account = Account(userName: "", userIdentifier: ZMUser.selfUser(in: managedObjectContext).remoteIdentifier)

        // Avoid unneccessary and expensive change tracking triggered when saving the sync context.
        self.notificationDispatcher.isDisabled = true

        syncManagedObjectContext.performGroupedBlock {
            do {
                if enabled {
                    try self.deleteKeys(for: account)
                    try self.createKeys(for: account)
                    try self.syncManagedObjectContext.enableEncryptionAtRest()
                } else {
                    try self.syncManagedObjectContext.disableEncryptionAtRest()
                    try self.deleteKeys(for: account)
                }

                self.syncManagedObjectContext.saveOrRollback()

                DispatchQueue.main.async {
                    self.notificationDispatcher.isDisabled = false
                    completion?(.success(()))
                }

            } catch {
                Logging.EAR.error(
                    "Failed to enabling/disabling database encryption. Reason: \(error.localizedDescription)"
                )

                self.syncManagedObjectContext.reset()

                DispatchQueue.main.async {
                    self.notificationDispatcher.isDisabled = false
                    completion?(.failure(error))
                }
            }
        }
    }
    
    public var encryptMessagesAtRest: Bool {
        return managedObjectContext.encryptMessagesAtRest
    }

    private func deleteKeys(for account: Account) throws {
        try EncryptionKeys.deleteKeys(for: account)
        storeProvider.contextDirectory.clearEncryptionKeysInAllContexts()
    }

    private func createKeys(for account: Account) throws {
        let keys = try EncryptionKeys.createKeys(for: account)
        storeProvider.contextDirectory.storeEncryptionKeysInAllContexts(encryptionKeys: keys)
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
        let account = Account(userName: "", userIdentifier: ZMUser.selfUser(in: managedObjectContext).remoteIdentifier)
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
