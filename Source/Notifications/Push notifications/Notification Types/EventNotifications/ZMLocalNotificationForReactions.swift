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

public protocol CopyableEventNotification : EventNotification {

    ///
    ///
    /// - Parameters:
    ///   - event:
    ///   - conversation: 
    ///   - userSession: userSession for cancelLocalNotification (in main thread)
    /// - Returns: 
    func copyByAddingEvent(_ event: ZMUpdateEvent, conversation: ZMConversation, userSession: ZMUserSession) -> Self?
    func canAddEvent(_ event: ZMUpdateEvent, conversation: ZMConversation) -> Bool
}

extension CopyableEventNotification {
    
    public func canAddEvent(_ event: ZMUpdateEvent, conversation: ZMConversation) -> Bool {
        guard eventType == event.type &&
            conversationID == conversation.remoteIdentifier && (!conversation.isSilenced || ignoresSilencedState)
            else {
                return false
        }
        return true
    }
}

final public class ZMLocalNotificationForReaction : ZMLocalNotificationForEvent, CopyableEventNotification {
    
    fileprivate var emoji : String!
    fileprivate var nonce : String!
    
    public override var eventType: ZMUpdateEventType {
        return .conversationOtrMessageAdd
    }
    
    override var requiresConversation : Bool {
        return true
    }
    
    // We create notification only if self users message was reacted to
    override func canCreateNotification(_ conversation: ZMConversation?) -> Bool {
        guard super.canCreateNotification(conversation) else { return false }
        guard let lastEvent = lastEvent,
              let receivedMessage = ZMGenericMessage(from:lastEvent) , receivedMessage.hasReaction()
        else { return false }
        
        // If the message is an "unlike", we don't want to display a notification
        guard receivedMessage.reaction.emoji != "" else { return false }
        
        // fetch message that was reacted to and make sure the sender of the original message is the selfUser
        guard let conversation = conversation,
            let message = ZMMessage.fetch(withNonce: UUID(uuidString: receivedMessage.reaction.messageId), for: conversation, in: self.managedObjectContext),
            message.sender == ZMUser.selfUser(in: self.managedObjectContext)
            else { return false }
        
        emoji = receivedMessage.reaction.emoji
        nonce = receivedMessage.reaction.messageId
        return true
    }
    
    override func configureNotification(_ conversation: ZMConversation?) -> UILocalNotification {
        let notification = super.configureNotification(conversation)
        notification.userInfo!["messageNonceString"] = nonce
        return notification
    }
    
    public func copyByAddingEvent(_ event: ZMUpdateEvent, conversation: ZMConversation, userSession: ZMUserSession) -> ZMLocalNotificationForReaction? {
        guard canAddEvent(event, conversation: conversation),
              let otherMessage = ZMGenericMessage(from:event) , otherMessage.hasReaction()
        else { return nil }
        
        // If new event is an "unlike" from the same sender we want to cancel the previous notification
        if otherMessage.reaction.messageId == nonce &&
            otherMessage.reaction.emoji == "" &&
            event.senderUUID() == sender?.remoteIdentifier
        {
            self.managedObjectContext.zm_userInterface.performGroupedBlock {
                self.cancelNotifications(userSession: userSession)
            }
            
            shouldBeDiscarded = true
            return nil
        }
        return nil
    }
    
    override func textToDisplay(_ conversation: ZMConversation?) -> String {
        return ZMPushStringReaction.localizedString(with: self.sender, conversation: conversation, emoji: self.emoji!)
    }
}

