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
    
    public fileprivate(set) var notifications : Set<ZMLocalNotification> = Set() {
        didSet {
            updateArchive()
        }
    }
    
    var oldNotifications = [UILocalNotification]()
    
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
            let unarchivedNotes =  NSKeyedUnarchiver.unarchiveObject(with: archive) as? [UILocalNotification]
            else { return }
        self.oldNotifications = unarchivedNotes
    }
    
    /// Archives all scheduled notifications - this could be optimized
    func updateArchive(){
        var uiNotifications : [UILocalNotification] = notifications.reduce([]) { (uiNotes, localNote) in
            var newUINotes = uiNotes
            newUINotes.append(localNote.uiLocalNotification)
            return newUINotes
        }
        uiNotifications = uiNotifications + oldNotifications
        let data = NSKeyedArchiver.archivedData(withRootObject: uiNotifications)
        keyValueStore.store(value: data as NSData, key: archivingKey)
        keyValueStore.enqueueDelayedSave() // we need to save otherwiese changes might not be stored
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
        notifications.forEach { application?.cancelLocalNotification($0.uiLocalNotification) }
        notifications = Set()
        
        oldNotifications.forEach{application?.cancelLocalNotification($0)}
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
        var toRemove = Set<ZMLocalNotification>()
        notifications.forEach {
            if ($0.conversationID == conversation.remoteIdentifier) {
                toRemove.insert($0)
                application?.cancelLocalNotification($0.uiLocalNotification)
            }
        }
        notifications.subtract(toRemove)
    }
    
    /// Cancels all notifications created in previous runs
    internal func cancelOldNotifications(_ conversation: ZMConversation) {
        guard oldNotifications.count > 0 else { return }

        oldNotifications = oldNotifications.filter {
            if ($0.zm_conversationRemoteID == conversation.remoteIdentifier) {
                application?.cancelLocalNotification($0)
                return false
            }
            return true
        }
    }
    
    /// Cancal all notifications with the given message nonce
    internal func cancelCurrentNotifications(messageNonce: UUID) {
        guard notifications.count > 0 else { return }
        var toRemove = Set<ZMLocalNotification>()
        notifications.forEach {
            if ($0.messageNonce == messageNonce) {
                toRemove.insert($0)
                application?.cancelLocalNotification($0.uiLocalNotification)
            }
        }
        notifications.subtract(toRemove)
    }
}


// Event Notifications
public extension ZMLocalNotificationSet {

    public func cancelNotificationForIncomingCall(_ conversation: ZMConversation) {
        var toRemove = Set<ZMLocalNotification>()
        notifications.forEach{ note in
            guard note.conversationID == conversation.remoteIdentifier, note.isCallingNotification else { return }
            toRemove.insert(note)
            application?.cancelLocalNotification(note.uiLocalNotification)
        }
        notifications.subtract(toRemove)
    }
}
