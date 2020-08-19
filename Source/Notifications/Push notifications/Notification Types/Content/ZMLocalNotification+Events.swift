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

import WireDataModel

extension ZMLocalNotification {
    
    // for each supported event type, use the corresponding notification builder.
    //
    convenience init?(event: ZMUpdateEvent, conversation: ZMConversation?, managedObjectContext moc: NSManagedObjectContext) {
        var builder: NotificationBuilder?
        
        switch event.type {
        case .conversationOtrMessageAdd:
            let message = GenericMessage(from: event)
            builder = (message?.hasReaction ?? false)
            ? ReactionEventNotificationBuilder(event: event, conversation: conversation, managedObjectContext: moc)
            : NewMessageNotificationBuilder(event: event, conversation: conversation, managedObjectContext: moc)
            
        case .conversationCreate:
            builder = ConversationCreateEventNotificationBuilder(event: event, conversation: conversation, managedObjectContext: moc)
            
        case .conversationDelete:
            builder = ConversationDeleteEventNotificationBuilder(event: event, conversation: conversation, managedObjectContext: moc)
            
        case .userConnection:
            builder = UserConnectionEventNotificationBuilder(event: event, conversation: conversation, managedObjectContext: moc)
            
        case .userContactJoin:
            builder = NewUserEventNotificationBuilder(event: event, conversation: conversation, managedObjectContext: moc)
        case .conversationMemberJoin, .conversationMemberLeave, .conversationMessageTimerUpdate:
            guard conversation?.remoteIdentifier != nil else {
                return nil
            }
            builder = NewSystemMessageNotificationBuilder(event: event, conversation: conversation, managedObjectContext: moc)
        default:
            return nil
        }
        
        if let builder = builder {
            self.init(conversation: conversation, builder: builder)
        } else {
            return nil
        }
    }
    
}

// Base class for event notification builders. Subclass this for each
// event type, and override the components specific for that type.
///
fileprivate class EventNotificationBuilder: NotificationBuilder {
    
    let event: ZMUpdateEvent
    let moc: NSManagedObjectContext
    var sender: ZMUser?
    var conversation: ZMConversation?
    
    var notificationType: LocalNotificationType {
        fatal("You must override this property in a subclass")
    }
    
    init?(event: ZMUpdateEvent, conversation: ZMConversation?, managedObjectContext: NSManagedObjectContext) {
        self.event = event
        self.conversation = conversation
        self.moc = managedObjectContext
        
        if let senderID = event.senderUUID {
            self.sender = ZMUser(remoteID: senderID, createIfNeeded: false, in: self.moc)
        }
    }
    
    func shouldCreateNotification() -> Bool {
        // if there is a sender, it's not the selfUser
        if let sender = self.sender, sender.isSelfUser { return false }
        
        if let conversation = conversation {
            if conversation.mutedMessageTypesIncludingAvailability != .none {
                return false
            }
            
            if let timeStamp = event.timestamp,
                let lastRead = conversation.lastReadServerTimeStamp , lastRead.compare(timeStamp) != .orderedAscending {
                // don't show notifications that have already been read
                return false
            }
        }
        
        return true
    }
    
    func titleText() -> String? {
        return notificationType.titleText(selfUser: ZMUser.selfUser(in: moc), conversation: conversation)
    }
    
    func bodyText() -> String {
        return notificationType.messageBodyText(sender: sender, conversation: conversation)
    }
        
    func userInfo() -> NotificationUserInfo? {
        let selfUser = ZMUser.selfUser(in: moc)
        guard let selfUserRemoteID = selfUser.remoteIdentifier else { return nil }
        
        let userInfo = NotificationUserInfo()
        userInfo.selfUserID = selfUserRemoteID
        userInfo.senderID = event.senderUUID
        userInfo.conversationID = conversation?.remoteIdentifier
        userInfo.messageNonce = event.messageNonce
        userInfo.eventTime = event.timestamp
        userInfo.conversationName = conversation?.meaningfulDisplayName
        userInfo.teamName = selfUser.team?.name

        return userInfo
    }
}


// MARK: - Reaction Event

private class ReactionEventNotificationBuilder: EventNotificationBuilder {
    
    private let emoji: String
    private let nonce: UUID
    private let message: GenericMessage
    
    override var notificationType: LocalNotificationType {
        if LocalNotificationDispatcher.shouldHideNotificationContent(moc: self.moc) {
            return LocalNotificationType.message(.hidden)
        } else {
            return LocalNotificationType.message(.reaction(emoji: emoji))
        }
    }
    
    override init?(event: ZMUpdateEvent, conversation: ZMConversation?, managedObjectContext: NSManagedObjectContext) {
        guard let message = GenericMessage(from: event), message.hasReaction else {
            return nil
        }

        guard let nonce = UUID(uuidString: message.reaction.messageID) else {
            return nil
        }
        
        self.message = message
        self.emoji = message.reaction.emoji
        self.nonce = nonce
        
        super.init(event: event, conversation: conversation, managedObjectContext: managedObjectContext)
    }
    
    override func shouldCreateNotification() -> Bool {
        guard super.shouldCreateNotification() else { return false }
        
        guard let receivedMessage = GenericMessage(from: event), receivedMessage.hasReaction else {
            return false
        }
        
        // If the message is an "unlike", we don't want to display a notification
        guard message.reaction.emoji != "" else { return false }
        
        // fetch message that was reacted to and make sure the sender of the original message is the selfUser
        guard let conversation = conversation,
              let reactionMessage = ZMMessage.fetch(withNonce: UUID(uuidString: message.reaction.messageID), for: conversation, in: moc),
            reactionMessage.sender == ZMUser.selfUser(in: moc) else { return false }
        
        return true
    }
    
    override func userInfo() -> NotificationUserInfo? {
        // we want to store the nonce of the message being reacted to, not the event nonce
        let info = super.userInfo()
        info?.messageNonce = nonce
        return info
    }
}


// MARK: - Conversation Create Event

private class ConversationCreateEventNotificationBuilder: EventNotificationBuilder {
    
    override var notificationType: LocalNotificationType {
        return LocalNotificationType.event(.conversationCreated)
    }
    
    override func shouldCreateNotification() -> Bool {
        return super.shouldCreateNotification() && conversation?.conversationType == .group
    }
    
}

// MARK: - Conversation Delete Event

private class ConversationDeleteEventNotificationBuilder: EventNotificationBuilder {
    
    override var notificationType: LocalNotificationType {
        return LocalNotificationType.event(.conversationDeleted)
    }
    
    override func shouldCreateNotification() -> Bool {
        return super.shouldCreateNotification() && conversation?.conversationType == .group
    }
    
}


// MARK: - User Connection Event

private class UserConnectionEventNotificationBuilder: EventNotificationBuilder {
    
    var eventType : LocalNotificationEventType
    var senderName: String?
    
    override var notificationType: LocalNotificationType {
        return LocalNotificationType.event(eventType)
    }
    
    override init?(event: ZMUpdateEvent, conversation: ZMConversation?, managedObjectContext: NSManagedObjectContext) {
        
        if let status = (event.payload["connection"] as? [String: AnyObject] )?["status"] as? String {
            if status == "accepted" {
                self.eventType = .connectionRequestAccepted
            } else if status == "pending" {
                self.eventType = .connectionRequestPending
            } else {
                return nil
            }
        } else {
            return nil
        }
        
        super.init(event: event, conversation: conversation, managedObjectContext: managedObjectContext)
        
        senderName = sender?.name ?? (event.payload["user"] as? [String : Any])?["name"] as? String
    }
    
    override func titleText() -> String? {
        return nil
    }
    
    override func bodyText() -> String {
        return notificationType.messageBodyText(senderName: senderName)
    }
    
}


// MARK: - New User Event

private class NewUserEventNotificationBuilder: EventNotificationBuilder {
    
    override var notificationType: LocalNotificationType {
        return LocalNotificationType.event(.newConnection)
    }
    
    override func titleText() -> String? {
        return nil
    }
    
    override func bodyText() -> String {
        let name = (event.payload["user"] as? [String : Any])?["name"] as? String
        return notificationType.messageBodyText(senderName: name)
    }
}

// MARK: - Message

private class NewMessageNotificationBuilder: EventNotificationBuilder {
    private let message: GenericMessage?
    let contentType: LocalNotificationContentType

    override init?(event: ZMUpdateEvent, conversation: ZMConversation?, managedObjectContext: NSManagedObjectContext) {
        guard let contentType = LocalNotificationContentType.typeForMessage(event, conversation: conversation, in: managedObjectContext)
            else {
                return nil
        }

        self.message = GenericMessage(from: event)
        self.contentType = contentType
        super.init(event: event, conversation: conversation, managedObjectContext: managedObjectContext)
    }

    override func titleText() -> String? {
        return notificationType.titleText(selfUser: ZMUser.selfUser(in: moc), conversation: conversation)
    }
    
    override func bodyText() -> String {
        return notificationType.messageBodyText(sender: sender, conversation: conversation).trimmingCharacters(in: .whitespaces)
    }
    
    override var notificationType: LocalNotificationType {
        if case .ephemeral? = message?.content {
            return LocalNotificationType.message(contentType)
        }
        return LocalNotificationDispatcher.shouldHideNotificationContent(moc: self.moc)
        ? LocalNotificationType.message(.hidden)
        : LocalNotificationType.message(contentType)
    }

    override func shouldCreateNotification() -> Bool {
        guard let message = message else {
            // This is the case when we have an undefined message and we can't deserialize it.
            return true
        }
        guard let conversation = conversation,
            let senderUUID = event.senderUUID,
            !conversation.isMessageSilenced(message, senderID: senderUUID) else {
                Logging.push.safePublic("Not creating local notification for message with nonce = \(event.messageNonce) because conversation is silenced")
                return false
        }
        
        if let timeStamp = event.timestamp,
            let lastRead = conversation.lastReadServerTimeStamp,
            lastRead.compare(timeStamp) != .orderedAscending
        {
            return false
        }
        return true
    }
}

// MARK: - System Message

private class NewSystemMessageNotificationBuilder : EventNotificationBuilder {
    let contentType: LocalNotificationContentType
    
    override init?(event: ZMUpdateEvent, conversation: ZMConversation?, managedObjectContext: NSManagedObjectContext) {
        guard let contentType = LocalNotificationContentType.typeForMessage(event, conversation: conversation, in: managedObjectContext)
            else {
                return nil
        }
        
        self.contentType = contentType
        super.init(event: event, conversation: conversation, managedObjectContext: managedObjectContext)
    }
    
    override func titleText() -> String? {
        return notificationType.titleText(selfUser: ZMUser.selfUser(in: moc), conversation: conversation)
    }
    
    override func bodyText() -> String {
        return notificationType.messageBodyText(sender: sender, conversation: conversation).trimmingCharacters(in: .whitespaces)
    }
    
    override var notificationType: LocalNotificationType {
        return LocalNotificationType.message(contentType)
    }
    
    override func shouldCreateNotification() -> Bool {
        // we don't want to create notifications when other people join or leave conversation
        let concernsSelfUser = event.userIDs.contains(ZMUser.selfUser(in: moc).remoteIdentifier)

        switch contentType {
        case .participantsAdded where concernsSelfUser == false, .participantsRemoved where concernsSelfUser == false:
            return false
        default:
            break
        }
         return super.shouldCreateNotification()
    }
}
