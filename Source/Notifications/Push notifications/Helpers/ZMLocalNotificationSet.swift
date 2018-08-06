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


import UIKit
import WireTransport


@objc public protocol ZMSynchonizableKeyValueStore : KeyValueStore {
    func enqueueDelayedSave()
}

@objc public final class ZMLocalNotificationSet : NSObject  {
    
    private var notificationCenter: UNUserNotificationCenter {
        return UNUserNotificationCenter.current()
    }
    
    private var allNotifications: [ZMLocalNotification] {
        return notifications + oldNotifications
    }
    
    private var allIDs: [UUID] {
        return allNotifications.map { $0.id }
    }
    
    public fileprivate(set) var notifications : Set<ZMLocalNotification> = Set() {
        didSet { updateArchive() }
    }

    private var oldNotifications = [ZMLocalNotification]()
    
    weak var application: ZMApplication?
    let archivingKey : String
    let keyValueStore : ZMSynchonizableKeyValueStore
    
    public init(application: ZMApplication, archivingKey: String, keyValueStore: ZMSynchonizableKeyValueStore) {
        self.application = application
        self.archivingKey = archivingKey
        self.keyValueStore = keyValueStore
        super.init()

        unarchiveOldNotifications()
    }
    
    /// unarchives all previously created notifications that haven't been cancelled yet
    func unarchiveOldNotifications(){
        guard let archive = keyValueStore.storedValue(key: archivingKey) as? Data,
            let unarchivedNotes =  NSKeyedUnarchiver.unarchiveObject(with: archive) as? [ZMLocalNotification]
            else { return }
        self.oldNotifications = unarchivedNotes
    }
    
    /// Archives all scheduled notifications - this could be optimized
    func updateArchive(){
        let data = NSKeyedArchiver.archivedData(withRootObject: allNotifications)
        keyValueStore.store(value: data as NSData, key: archivingKey)
        keyValueStore.enqueueDelayedSave() // we need to save otherwise changes might not be stored
    }
    
    @discardableResult public func remove(_ notification: ZMLocalNotification) -> ZMLocalNotification? {
        return notifications.remove(notification)
    }
    
    public func addObject(_ notification: ZMLocalNotification) {
        notifications.insert(notification)
    }
    
    public func replaceObject(_ toReplace: ZMLocalNotification, newObject: ZMLocalNotification) {
        notifications.remove(toReplace)
        notifications.insert(newObject)
    }
    
    /// Cancels all notifications
    public func cancelAllNotifications() {
        let ids = allIDs.map { $0.uuidString }
        notificationCenter.removeAllNotifications(with: ids)
        notifications = Set()
        oldNotifications = []
    }
    
    /// This cancels all notifications of a specific conversation
    public func cancelNotifications(_ conversation: ZMConversation) {
        cancelOldNotifications(conversation)
        cancelCurrentNotifications(conversation)
    }
    
    /// Cancel all notifications created in this run
    internal func cancelCurrentNotifications(_ conversation: ZMConversation) {
        guard notifications.count > 0 else { return }
        let toRemove = notifications.filter { $0.conversationID == conversation.remoteIdentifier }
        notificationCenter.removeAllNotifications(with: toRemove.map { $0.id.uuidString })
        notifications.subtract(toRemove)
    }
    
    /// Cancels all notifications created in previous runs
    internal func cancelOldNotifications(_ conversation: ZMConversation) {
        guard oldNotifications.count > 0 else { return }

        oldNotifications = oldNotifications.filter {
            guard $0.conversationID == conversation.remoteIdentifier else { return true }
            notificationCenter.removeAllNotifications(with: [$0.id.uuidString])
            return false
        }
    }
    
    /// Cancal all notifications with the given message nonce
    internal func cancelCurrentNotifications(messageNonce: UUID) {
        guard notifications.count > 0 else { return }
        let toRemove = notifications.filter { $0.messageNonce == messageNonce }
        notificationCenter.removeAllNotifications(with: toRemove.map { $0.id.uuidString })
        notifications.subtract(toRemove)
    }
}


// Event Notifications
public extension ZMLocalNotificationSet {

    public func cancelNotificationForIncomingCall(_ conversation: ZMConversation) {
        let toRemove = notifications.filter {
            $0.conversationID == conversation.remoteIdentifier && $0.isCallingNotification
        }
        notificationCenter.removeAllNotifications(with: toRemove.map { $0.id.uuidString })
        notifications.subtract(toRemove)
    }
}

// TODO: put this somewhere else?
extension UNUserNotificationCenter {
    
    func removeAllNotifications(with requestIdentifiers: [String]) {
        removePendingNotificationRequests(withIdentifiers: requestIdentifiers)
        removeDeliveredNotifications(withIdentifiers: requestIdentifiers)
    }
}
