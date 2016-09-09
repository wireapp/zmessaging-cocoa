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
import ZMTransport


@objc public protocol ZMSynchonizableKeyValueStore : ZMKeyValueStore {
    func enqueueDelayedSave()
}

@objc public class ZMLocalNotificationSet : NSObject  {
    
    public private(set) var notifications : Set<ZMLocalNotification> = Set() {
        didSet {
            updateArchive()
        }
    }
    
    var oldNotifications = [UILocalNotification]()
    
    weak var application: Application?
    let archivingKey : String
    let keyValueStore : ZMSynchonizableKeyValueStore
    
    public init(application: Application, archivingKey: String, keyValueStore: ZMSynchonizableKeyValueStore) {
        self.application = application
        self.archivingKey = archivingKey
        self.keyValueStore = keyValueStore
        super.init()
        
        unarchiveOldNotifications()
    }
    
    /// unarchives all previously created notifications that haven't been cancelled yet
    func unarchiveOldNotifications(){
        guard let archive = keyValueStore.valueForKey(archivingKey) as? NSData,
            let unarchivedNotes =  NSKeyedUnarchiver.unarchiveObjectWithData(archive) as? [UILocalNotification]
            else { return }
        self.oldNotifications = unarchivedNotes
    }
    
    /// Archives all scheduled notifications - this could be optimized
    func updateArchive(){
        var uiNotifications : [UILocalNotification] = notifications.reduce([]) { (uiNotes, localNote) in
            var newUINotes = uiNotes
            newUINotes.appendContentsOf(localNote.uiNotifications)
            return newUINotes
        }
        uiNotifications = uiNotifications + oldNotifications
        let data = NSKeyedArchiver.archivedDataWithRootObject(uiNotifications)
        keyValueStore.setValue(data, forKey: archivingKey)
        keyValueStore.enqueueDelayedSave() // we need to save otherwiese changes might not be stored
    }
    
    public func remove(notification: ZMLocalNotification) -> ZMLocalNotification? {
        return notifications.remove(notification)
    }
    
    public func addObject(notification: ZMLocalNotification) {
        notifications.insert(notification)
    }
    
    public func replaceObject(toReplace: ZMLocalNotification, newObject: ZMLocalNotification) {
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
    public func cancelNotifications(conversation: ZMConversation) {
        cancelOldNotifications(conversation)
        cancelCurrentNotifications(conversation)
    }
    
    /// Cancel all notifications created in this run
    internal func cancelCurrentNotifications(conversation: ZMConversation) {
        guard self.notifications.count > 0 else { return }
        var toRemove = Set<ZMLocalNotification>()
        notifications.forEach{
            if($0.conversationID == conversation.remoteIdentifier) {
                toRemove.insert($0)
                $0.uiNotifications.forEach{ application?.cancelLocalNotification($0) }
            }
        }
        notifications.subtractInPlace(toRemove)
    }
    
    /// Cancels all notifications created in previous runs
    internal func cancelOldNotifications(conversation: ZMConversation) {
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

    public func copyExistingEventNotification(event: ZMUpdateEvent, conversation: ZMConversation) -> ZMLocalNotificationForEvent? {        
        let notificationsCopy = notifications
        for note in notificationsCopy {
            if let note = note as? ZMLocalNotificationForEvent where note is CopyableEventNotification {
                if let copied = (note as! CopyableEventNotification).copyByAddingEvent(event, conversation: conversation) as? ZMLocalNotificationForEvent {
                    if note.shouldBeDiscarded {
                        remove(note)
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
    
    public func cancelNotificationForIncomingCall(conversation: ZMConversation) {
        var toRemove = Set<ZMLocalNotification>()
        self.notifications.forEach{
            guard ($0.conversationID == conversation.remoteIdentifier),
                  let note = $0 as? ZMLocalNotificationForCallEvent where note.eventType == .CallState
            else { return }
            toRemove.insert($0)
            $0.uiNotifications.forEach{ application?.cancelLocalNotification($0) }
        }
        self.notifications.subtractInPlace(toRemove)
    }
}

// Message Notifications

public extension ZMLocalNotificationSet {
    
    public func copyExistingMessageNotification<T : ZMLocalNotification where T : NotificationForMessage>(message: T.MessageType) -> T? {
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
