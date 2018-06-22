//
// Wire
// Copyright (C) 2017 Wire Swiss GmbH
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


// MARK: - Message

extension ZMLocalNotification {
    
    convenience init?(message: ZMMessage) {
        guard message.conversation?.remoteIdentifier != nil, let builder = MessageNotificationBuilder(message: message) else { return nil }
        
        self.init(conversation: message.conversation, builder: builder)
    }
    
    fileprivate class MessageNotificationBuilder: NotificationBuilder {
        
        fileprivate let message: ZMMessage
        fileprivate let contentType: LocalNotificationContentType
        fileprivate let managedObjectContext : NSManagedObjectContext
        
        let sender: ZMUser
        let conversation: ZMConversation
        
        init?(message: ZMMessage) {
            guard let sender = message.sender,
                  let conversation = message.conversation,
                  let managedObjectContext = message.managedObjectContext,
                  let contentType = LocalNotificationContentType.typeForMessage(message) else { return nil }
            
            self.sender = sender
            self.conversation = conversation
            self.message = message
            self.contentType = contentType
            self.managedObjectContext = managedObjectContext
        }
        
        var notificationType: LocalNotificationType {
            if LocalNotificationDispatcher.shouldHideNotificationContent(moc: managedObjectContext), !message.isEphemeral {
                return LocalNotificationType.message(.hidden)
            } else {
                return LocalNotificationType.message(contentType)
            }
        }
        
        func shouldCreateNotification() -> Bool {
            
            if sender.isSelfUser || conversation.isSilenced { return false }
            
            if let timeStamp = message.serverTimestamp,
               let lastRead = conversation.lastReadServerTimeStamp,
               lastRead.compare(timeStamp) != .orderedAscending
            {
                return false
            }
            
            return true
        }
        
        func titleText() -> String? {
            return notificationType.titleText(selfUser: ZMUser.selfUser(in: managedObjectContext), conversation: conversation)
        }
        
        func bodyText() -> String {
            return notificationType.messageBodyText(sender: sender, conversation: conversation).trimmingCharacters(in: .whitespaces)
        }
        
        func userInfo() -> [AnyHashable: Any]? {
            
            guard
                let moc = message.managedObjectContext,
                let selfUserID = ZMUser.selfUser(in: moc).remoteIdentifier,
                let senderID = sender.remoteIdentifier,
                let conversationID = conversation.remoteIdentifier,
                let eventTime = message.serverTimestamp
                else { return nil }
            
            var userInfo = [AnyHashable: Any]()
            userInfo[SelfUserIDStringKey] = selfUserID.transportString()
            userInfo[SenderIDStringKey] = senderID.transportString()
            userInfo[MessageNonceIDStringKey] = message.nonce!.transportString()
            userInfo[ConversationIDStringKey] = conversationID.transportString()
            userInfo[EventTimeKey] = eventTime
            userInfo[ConversationNameStringKey] = conversation.meaningfulDisplayName
            userInfo[TeamNameStringKey] = ZMUser.selfUser(in: managedObjectContext).team?.name
            return userInfo
        }
    }
    
}


// MARK: - System Message

extension ZMLocalNotification {
    
    convenience init?(systemMessage: ZMSystemMessage) {
        guard systemMessage.conversation?.remoteIdentifier != nil, let builder = SystemMessageNotificationBuilder(message: systemMessage) else { return nil }
        
        self.init(conversation: systemMessage.conversation, builder: builder)
    }
    
    private class SystemMessageNotificationBuilder : MessageNotificationBuilder {
        
        override var notificationType: LocalNotificationType {
            return LocalNotificationType.message(contentType)
        }
        
        override func shouldCreateNotification() -> Bool {
            guard let systemMessage = message as? ZMSystemMessage else { return false }
            
            // we don't want to create notifications when other people join or leave conversation
            let forSelf = systemMessage.users.count == 1 && systemMessage.users.first!.isSelfUser
            if !forSelf && systemMessage.systemMessageType != .messageTimerUpdate {
                return false
            }
                        
            return super.shouldCreateNotification()
        }
        
    }

}


// MARK: - Failed Messages

extension ZMLocalNotification {
    
    convenience init?(expiredMessage: ZMMessage) {
        guard let conversation = expiredMessage.conversation else { return nil }
        self.init(expiredMessageIn: conversation)
    }
    
    convenience init?(expiredMessageIn conversation: ZMConversation) {
        guard let builder = FailedMessageNotificationBuilder(conversation: conversation) else { return nil }
        
        self.init(conversation: conversation, builder: builder)
    }
    
    private class FailedMessageNotificationBuilder: NotificationBuilder {
        
        fileprivate let conversation: ZMConversation
        fileprivate let managedObjectContext: NSManagedObjectContext
        
        var notificationType: LocalNotificationType {
            return LocalNotificationType.failedMessage
        }
        
        init?(conversation: ZMConversation?) {
            guard let conversation = conversation, let managedObjectContext = conversation.managedObjectContext else { return nil }
        
            self.conversation = conversation
            self.managedObjectContext = managedObjectContext
        }
        
        func shouldCreateNotification() -> Bool {
            return true
        }
        
        func titleText() -> String? {
            return notificationType.titleText(selfUser: ZMUser.selfUser(in: managedObjectContext), conversation: conversation)
        }
        
        func bodyText() -> String {
            return notificationType.messageBodyText(sender: ZMUser.selfUser(in: managedObjectContext), conversation: conversation)
        }
        
        func userInfo() -> [AnyHashable : Any]? {
            
            guard let selfUserID = ZMUser.selfUser(in: managedObjectContext).remoteIdentifier,
                  let conversationID = conversation.remoteIdentifier else { return nil }
            
            var userInfo = [AnyHashable: Any]()
            userInfo[SelfUserIDStringKey] = selfUserID.transportString()
            userInfo[ConversationIDStringKey] = conversationID.transportString()
            userInfo[ConversationNameStringKey] = conversation.meaningfulDisplayName
            userInfo[TeamNameStringKey] = ZMUser.selfUser(in: managedObjectContext).team?.name
            
            return userInfo
        }
    }
}
