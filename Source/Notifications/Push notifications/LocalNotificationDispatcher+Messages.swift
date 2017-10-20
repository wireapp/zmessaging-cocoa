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
import WireMessageStrategy

extension LocalNotificationDispatcher: PushMessageHandler {
    
    @objc
    public func processBuffer() {
        
        guard !localNotificationBuffer.isEmpty else { return }
        
        // we want to process the notifications only after saving the sync context, so that
        // the UI will have the objects availble to display.
        syncMOC.saveOrRollback()
        
        // for now we just display the latest notification in the buffer to avoid
        // an unreadable stream of notifications (since one note replaces the other)
        if let lastNote = localNotificationBuffer.last {
            self.foregroundNotificationDelegate?.didReceieveLocalMessage(notification: lastNote, application: application)
        }
        
        localNotificationBuffer.removeAll()
    }
    
    /// Dispatches the given message notification depending on the current application
    /// state. If the app is active, then the notification is directed to the user
    /// session, otherwise it is directed to the system via UIApplication.
    ///
    /// - Parameter note: notification to dispatch
    func scheduleUILocalNotification(_ note: UILocalNotification) {
        if userSession.operationStatus.operationState == .foreground {
            localNotificationBuffer.append(note)
        } else {
            userSession.scheduleLocalNotificationInMainThread(notification: note, application: application)
        }
    }
    
    // Processes ZMOTRMessages and ZMSystemMessages
    @objc(processMessage:) public func process(_ message: ZMMessage) {
        if let message = message as? ZMOTRMessage {
            if let note = localNotificationForMessage(message), let uiNote = note.uiNotifications.last {
                scheduleUILocalNotification(uiNote)
            }
        }
        if let message = message as? ZMSystemMessage {
            if let note = localNotificationForSystemMessage(message), let uiNote = note.uiNotifications.last {
                scheduleUILocalNotification(uiNote)
            }
        }
    }
    
    // Process ZMGenericMessage that have "invisible" as in they don't create a message themselves
    @objc(processGenericMessage:) public func process(_ genericMessage: ZMGenericMessage) {
        // hidden, deleted and reaction do not create messages on their own
        if genericMessage.hasEdited() || genericMessage.hasHidden() || genericMessage.hasDeleted() {
            // Cancel notification for message that was edited, deleted or hidden
            cancelMessageForEditingMessage(genericMessage)
        }
    }
}

// MARK: ZMOTRMessage
extension LocalNotificationDispatcher {
    
    fileprivate func localNotificationForMessage(_ message : ZMOTRMessage) -> ZMLocalNotificationForMessage? {
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
        
        if let newNote = ZMLocalNotificationForMessage(message: message, application: self.application, userSession: userSession) {
            messageNotifications.addObject(newNote)
            return newNote;
        }
        return nil
    }
    
    fileprivate func cancelMessageForEditingMessage(_ genericMessage: ZMGenericMessage) {
        var idToDelete : UUID?
        
        if genericMessage.hasEdited(), let replacingID = genericMessage.edited.replacingMessageId {
            idToDelete = UUID(uuidString: replacingID)
        }
        else if genericMessage.hasDeleted(), let deleted = genericMessage.deleted.messageId {
            idToDelete = UUID(uuidString: deleted)
        }
        else if genericMessage.hasHidden(), let hidden = genericMessage.hidden.messageId {
            idToDelete = UUID(uuidString: hidden)
        }
        
        if let idToDelete = idToDelete {
            cancelNotificationForMessageID(idToDelete)
        }
    }
    
    fileprivate func cancelNotificationForMessageID(_ messageID: UUID) {
        for note in messageNotifications.notifications where note is ZMLocalNotificationForMessage {
            if (note as! ZMLocalNotificationForMessage).isNotificationFor(messageID) {
                note.uiNotifications.forEach{ notification in
                    userSession.cancelLocalNotificationInMainThread(notification:notification, application: application)
                    }
                _ = messageNotifications.remove(note);
            }
        }
    }
}


// MARK: ZMSystemMessage
extension LocalNotificationDispatcher {
    
    fileprivate func localNotificationForSystemMessage(_ message : ZMSystemMessage) -> ZMLocalNotificationForSystemMessage? {
        
        // we only want participation messages concerning only the self user
        if message.isGroupParticipationMessageNotForSelf {
            return nil
        }
        
        if let newNote = ZMLocalNotificationForSystemMessage(message: message, application:self.application, userSession: userSession) {
            messageNotifications.addObject(newNote)
            return newNote;
        }
        return nil
    }
}

private extension ZMSystemMessage {
    
    /// Returns true if the system message notifies that a user(s) that is not the self user
    /// was added or removed from a conversation.
    ///
    var isGroupParticipationMessageNotForSelf: Bool {
        let addOrRemove = systemMessageType == .participantsAdded || systemMessageType == .participantsRemoved
        let forSelf = users.count == 1 && users.first!.isSelfUser
        return addOrRemove && !forSelf
    }
}

