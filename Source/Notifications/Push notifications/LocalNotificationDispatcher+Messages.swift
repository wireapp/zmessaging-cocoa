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
    
    // Process ZMGenericMessage that have "invisible" as in they don't create a message themselves
    @objc(processEvent:) public func process(_ event: ZMUpdateEvent) {
        Logging.push.safePublic("Process message with nonce=\(event.messageNonce)")
        
        var note: ZMLocalNotification?
        var conversation: ZMConversation?
        if let conversationID = event.conversationUUID {
            conversation = ZMConversation.fetch(withRemoteIdentifier: conversationID, in: self.syncMOC)
        }
        
        // hidden, deleted and reaction do not create messages on their own
        if let genericMessage = GenericMessage(from: event) {
            // we don't want to create duplicate notifications
            guard let nonce = event.messageNonce,
                !messageNotifications.hasNotification(for: nonce) else {
                    return Logging.push.safePublic("Ignore duplicate message with nonce = \(event.messageNonce)")
            }
            
            if genericMessage.hasEdited || genericMessage.hasHidden || genericMessage.hasDeleted {
                // Cancel notification for message that was edited, deleted or hidden
                cancelMessageForEditingMessage(genericMessage)
            }
        }
        
        note = ZMLocalNotification(event: event, conversation: conversation, managedObjectContext: self.syncMOC)
        note.apply(scheduleLocalNotification)
        note.apply(messageNotifications.addObject)
    }
}

// MARK: ZMOTRMessage
extension LocalNotificationDispatcher {
    
    fileprivate func cancelMessageForEditingMessage(_ genericMessage: GenericMessage) {
        var idToDelete : UUID?
        
        if genericMessage.hasEdited {
            let replacingID = genericMessage.edited.replacingMessageID
            idToDelete = UUID(uuidString: replacingID)
        }
        else if genericMessage.hasDeleted {
            let deleted = genericMessage.deleted.messageID
            idToDelete = UUID(uuidString: deleted)
        }
        else if genericMessage.hasHidden {
            let hidden = genericMessage.hidden.messageID
            idToDelete = UUID(uuidString: hidden)
        }
        
        if let idToDelete = idToDelete {
            cancelNotificationForMessageID(idToDelete)
        }
    }
    
    fileprivate func cancelNotificationForMessageID(_ messageID: UUID) {
        Logging.push.safePublic("Canceling local notification with id = \(messageID)")
        
        notificationCenter.removePendingNotificationRequests(withIdentifiers: [messageID.uuidString])
        notificationCenter.removeDeliveredNotifications(withIdentifiers: [messageID.uuidString])
        messageNotifications.removeAllNotifications(for: messageID)
    }
}

private extension ZMLocalNotificationSet {
    
    func hasNotification(for messageNonce: UUID) -> Bool {
        return !notifications(for: messageNonce).isEmpty
    }
    
    func notifications(for messageNonce: UUID) -> [ZMLocalNotification] {
        return notifications.filter { $0.messageNonce == messageNonce }
    }
    
    func removeAllNotifications(for messageNonce: UUID) {
        notifications(for: messageNonce).forEach { self.remove($0) }
    }
}
