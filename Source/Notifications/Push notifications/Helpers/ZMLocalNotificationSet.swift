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
    
    let archivingKey : String
    let keyValueStore : ZMSynchonizableKeyValueStore
    var notificationCenter: UserNotificationCenter = UNUserNotificationCenter.current()
    
    public fileprivate(set) var notifications = Set<ZMLocalNotification>() {
        didSet { updateArchive() }
    }

    public private(set) var oldNotifications = [NotificationUserInfo]()

    private var allNotifications: [NotificationUserInfo] {
        return notifications.compactMap { $0.userInfo } + oldNotifications
    }
    
    public init(archivingKey: String, keyValueStore: ZMSynchonizableKeyValueStore) {
        self.archivingKey = archivingKey
        self.keyValueStore = keyValueStore
        super.init()

        unarchiveOldNotifications()
    }
    
    /// Unarchives all previously created notifications that haven't been cancelled yet
    func unarchiveOldNotifications(){
        guard let archive = keyValueStore.storedValue(key: archivingKey) as? Data,
        let unarchivedNotes =  NSKeyedUnarchiver.unarchiveObject(with: archive) as? [NotificationUserInfo]
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
        let ids = allNotifications.compactMap { $0.requestID?.uuidString }
        notificationCenter.removeAllNotifications(withIdentifiers: ids)
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
        notificationCenter.removeAllNotifications(withIdentifiers: toRemove.map { $0.id.uuidString })
        notifications.subtract(toRemove)
    }
    
    /// Cancels all notifications created in previous runs
    internal func cancelOldNotifications(_ conversation: ZMConversation) {
        guard oldNotifications.count > 0 else { return }
        
        oldNotifications = oldNotifications.filter { userInfo in
            guard
                userInfo.conversationID == conversation.remoteIdentifier,
                let requestID = userInfo.requestID?.uuidString
                else { return true }
            
            notificationCenter.removeAllNotifications(withIdentifiers: [requestID])
            return false
        }
    }
    
    /// Cancal all notifications with the given message nonce
    internal func cancelCurrentNotifications(messageNonce: UUID) {
        guard notifications.count > 0 else { return }
        let toRemove = notifications.filter { $0.messageNonce == messageNonce }
        notificationCenter.removeAllNotifications(withIdentifiers: toRemove.map { $0.id.uuidString })
        notifications.subtract(toRemove)
    }
}


// Event Notifications
public extension ZMLocalNotificationSet {

    func cancelNotificationForIncomingCall(_ conversation: ZMConversation) {
        let toRemove = notifications.filter {
            $0.conversationID == conversation.remoteIdentifier && $0.isCallingNotification
        }
        notificationCenter.removeAllNotifications(withIdentifiers: toRemove.map { $0.id.uuidString })
        notifications.subtract(toRemove)
    }
}
