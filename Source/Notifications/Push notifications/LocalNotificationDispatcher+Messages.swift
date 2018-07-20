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
import WireRequestStrategy

extension LocalNotificationDispatcher: PushMessageHandler {

    // Processes ZMOTRMessages and ZMSystemMessages
    @objc(processMessage:) public func process(_ message: ZMMessage) {
        // we don't want to create duplicate notifications
        if messageNotifications.notifications.contains(where: { note in
            return (note.userInfo?[MessageNonceIDStringKey] as? String) ==  message.nonce!.transportString()
        }) { return }
        
        var note: ZMLocalNotification?
        
        if let message = message as? ZMOTRMessage {
            note = ZMLocalNotification(message: message)
        }
        else if let message = message as? ZMSystemMessage {
            note = ZMLocalNotification(systemMessage: message)
        }
        
        note.apply(scheduleLocalNotification)
        note.apply(messageNotifications.addObject)
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
        for note in messageNotifications.notifications {
            if note.messageNonce == messageID {
                application.cancelLocalNotification(note.uiLocalNotification)
                messageNotifications.remove(note)
            }
        }
    }
}
