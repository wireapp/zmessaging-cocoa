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

import Foundation


public extension ZMLocalNotificationDispatcher {

    // Processes ZMOTRMessages and ZMSystemMessages
    public func processMessage(message: ZMMessage) {
        if let message = message as? ZMOTRMessage {
            if let note = localNotificationForMessage(message), let uiNote = note.uiNotifications.last {
                (sharedApplicationForSwift as! Application).scheduleLocalNotification(uiNote)
            }
        }
        if let message = message as? ZMSystemMessage {
            if let note = localNotificationForSystemMessage(message), let uiNote = note.uiNotifications.last {
                (sharedApplicationForSwift as! Application).scheduleLocalNotification(uiNote)
            }
        }
    }
    
    // Process ZMGenericMessage that have "invisible" as in they don't create a message themselves
    public func processGenericMessage(genericMessage: ZMGenericMessage) {
        // hidden, deleted and reaction do not create messages on their own
        if genericMessage.hasEdited() || genericMessage.hasHidden() || genericMessage.hasDeleted() {
            // Cancel notification for message that was edited, deleted or hidden
            cancelMessageForEditingMessage(genericMessage)
        }
    }
}

// MARK: ZMOTRMessage
extension ZMLocalNotificationDispatcher {

    private func localNotificationForMessage(message : ZMOTRMessage) -> ZMLocalNotificationForMessage? {
        // We don't want to create duplicate notifications (e.g. for images)
        for note in messageNotifications.notifications where note is ZMLocalNotificationForMessage {
            if (note as! ZMLocalNotificationForMessage).isNotificationFor(message.nonce) {
                return nil;
            }
        }
        // We might want to "bundle" notifications, e.g. Pings from the same user
        if let newNote : ZMLocalNotificationForMessage = messageNotifications.copyExistingMessageNotification(message) {
            return newNote;
        }
        
        if let newNote = ZMLocalNotificationForMessage(message: message, application:(sharedApplicationForSwift as! Application)) {
            messageNotifications.addObject(newNote)
            return newNote;
        }
        return nil
    }
    
    private func cancelMessageForEditingMessage(genericMessage: ZMGenericMessage) {
        var idToDelete : NSUUID?
        
        if genericMessage.hasEdited(), let replacingID = genericMessage.edited.replacingMessageId {
            idToDelete = NSUUID(UUIDString: replacingID)
        }
        else if genericMessage.hasDeleted(), let deleted = genericMessage.deleted.messageId {
            idToDelete = NSUUID(UUIDString: deleted)
        }
        else if genericMessage.hasHidden(), let hidden = genericMessage.hidden.messageId {
            idToDelete = NSUUID(UUIDString: hidden)
        }
        
        if let idToDelete = idToDelete {
            cancelNotificationForMessageID(idToDelete)
        }
    }
    
    private func cancelNotificationForMessageID(messageID: NSUUID) {
        for note in messageNotifications.notifications where note is ZMLocalNotificationForMessage {
            if (note as! ZMLocalNotificationForMessage).isNotificationFor(messageID) {
                note.uiNotifications.forEach{(sharedApplicationForSwift as! Application).cancelLocalNotification($0)}
                messageNotifications.remove(note);
            }
        }
    }
}


// MARK: ZMSystemMessage
extension ZMLocalNotificationDispatcher {
    
    private func localNotificationForSystemMessage(message : ZMSystemMessage) -> ZMLocalNotificationForSystemMessage? {
        
        // We might want to "bundle" notifications, e.g. member join / leave events
        if let newNote: ZMLocalNotificationForSystemMessage = messageNotifications.copyExistingMessageNotification(message) {
            return newNote;
        }
        
        if let newNote = ZMLocalNotificationForSystemMessage(message: message, application:(sharedApplicationForSwift as! Application)) {
            messageNotifications.addObject(newNote)
            return newNote;
        }
        return nil
    }
}

