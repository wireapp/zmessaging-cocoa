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
            newUINotes.append(contentsOf: localNote.uiNotifications)
            return newUINotes
        }
        uiNotifications = uiNotifications + oldNotifications
        let data = NSKeyedArchiver.archivedData(withRootObject: uiNotifications)
        keyValueStore.store(value: data as NSData, key: archivingKey)
        keyValueStore.enqueueDelayedSave() // we need to save otherwiese changes might not be stored
    }
    
    public func remove(_ notification: ZMLocalNotification) -> ZMLocalNotification? {
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
        notifications.forEach{ $0.uiNotifications.forEach{ application?.cancelLocalNotification($0) } }
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
        guard self.notifications.count > 0 else { return }
        var toRemove = Set<ZMLocalNotification>()
        notifications.forEach{
            if($0.conversationID == conversation.remoteIdentifier) {
                toRemove.insert($0)
                $0.uiNotifications.forEach{ application?.cancelLocalNotification($0) }
            }
        }
        notifications.subtract(toRemove)
    }
    
    /// Cancels all notifications created in previous runs
    internal func cancelOldNotifications(_ conversation: ZMConversation) {
        guard oldNotifications.count > 0 else { return }

        oldNotifications = oldNotifications.filter{
            if($0.zm_conversationRemoteID == conversation.remoteIdentifier) {
                application?.cancelLocalNotification($0)
                return false
            }
            return true
        }
    }
}


// Event Notifications
public extension ZMLocalNotificationSet {

    public func copyExistingEventNotification(_ event: ZMUpdateEvent, conversation: ZMConversation) -> ZMLocalNotificationForEvent? {        
        let notificationsCopy = notifications
        for note in notificationsCopy {
            if let note = note as? ZMLocalNotificationForEvent , note is CopyableEventNotification {
                if let copied = (note as! CopyableEventNotification).copyByAddingEvent(event, conversation: conversation) as? ZMLocalNotificationForEvent {
                    if note.shouldBeDiscarded {
                        _ = remove(note)
                    }
                    else {
                        replaceObject(note, newObject: copied)
                    }
                    return copied
                }
            }
        }
        return nil
    }
    
}

// Message Notifications

public extension ZMLocalNotificationSet {
    
    public func copyExistingMessageNotification<T : ZMLocalNotification>(_ message: T.MessageType) -> T? where T : NotificationForMessage {
        let notificationsCopy = notifications
        for note in notificationsCopy {
            if let note = note as? T {
                if let copied = note.copyByAddingMessage(message) {
                    replaceObject(note, newObject: copied)
                    return copied
                }
            }
        }
        return nil
    }
}
