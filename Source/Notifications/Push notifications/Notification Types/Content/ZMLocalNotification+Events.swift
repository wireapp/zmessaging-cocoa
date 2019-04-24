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


extension ZMLocalNotification {
    
    // for each supported event type, use the corresponding notification builder.
    //
    convenience init?(event: ZMUpdateEvent, conversation: ZMConversation?, managedObjectContext moc: NSManagedObjectContext) {
        var builder: NotificationBuilder?
        
        switch event.type {
        case .conversationOtrMessageAdd:
            builder = ReactionEventNotificationBuilder(
                event: event, conversation: conversation, managedObjectContext: moc)
            
        case .conversationCreate:
            builder = ConversationCreateEventNotificationBuilder(
                event: event, conversation: conversation, managedObjectContext: moc)
            
        case .userConnection:
            
            builder = UserConnectionEventNotificationBuilder(
                event: event, conversation: conversation, managedObjectContext: moc)
            
        case .userContactJoin:
            builder = NewUserEventNotificationBuilder(
                event: event, conversation: conversation, managedObjectContext: moc)
            
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
        
        if let senderID = event.senderUUID() {
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
            
            if let timeStamp = event.timeStamp(),
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
        userInfo.senderID = event.senderUUID()
        userInfo.conversationID = conversation?.remoteIdentifier
        userInfo.messageNonce = event.messageNonce()
        userInfo.eventTime = event.timeStamp()
        userInfo.conversationName = conversation?.meaningfulDisplayName
        userInfo.teamName = selfUser.team?.name

        return userInfo
    }
}


// MARK: - Reaction Event

private class ReactionEventNotificationBuilder: EventNotificationBuilder {
    
    private let emoji: String
    private let nonce: UUID
    private let message: ZMGenericMessage
    
    override var notificationType: LocalNotificationType {
        if LocalNotificationDispatcher.shouldHideNotificationContent(moc: self.moc) {
            return LocalNotificationType.message(.hidden)
        } else {
            return LocalNotificationType.message(.reaction(emoji: emoji))
        }
    }
    
    override init?(event: ZMUpdateEvent, conversation: ZMConversation?, managedObjectContext: NSManagedObjectContext) {
        guard let message = ZMGenericMessage(from: event), message.hasReaction() else {
            return nil
        }

        guard let nonce = UUID(uuidString: message.reaction.messageId) else {
            return nil
        }
        
        self.message = message
        self.emoji = message.reaction.emoji
        self.nonce = nonce
        
        super.init(event: event, conversation: conversation, managedObjectContext: managedObjectContext)
    }
    
    override func shouldCreateNotification() -> Bool {
        guard super.shouldCreateNotification() else { return false }
        
        guard let receivedMessage = ZMGenericMessage(from: event), receivedMessage.hasReaction() else {
            return false
        }
        
        // If the message is an "unlike", we don't want to display a notification
        guard message.reaction.emoji != "" else { return false }
        
        // fetch message that was reacted to and make sure the sender of the original message is the selfUser
        guard let conversation = conversation,
              let reactionMessage = ZMMessage.fetch(withNonce: UUID(uuidString: message.reaction.messageId), for: conversation, in: moc),
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

