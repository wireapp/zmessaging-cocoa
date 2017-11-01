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
        
        self.init(conversation: conversation, type: .event(event.type), builder: builder!)
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
    fileprivate var teamName: String?
    
    /// set to true if notification depends / refers to a specific conversation
    var requiresConversation : Bool { return false }
    
    fileprivate lazy var shouldHideContent: Bool = {
        let shouldHideKey = LocalNotificationDispatcher.ZMShouldHideNotificationContentKey
        let shouldHide = self.moc.persistentStoreMetadata(forKey: shouldHideKey) as? NSNumber
        return shouldHide?.boolValue ?? false
    }()
    
    init(event: ZMUpdateEvent, conversation: ZMConversation?, managedObjectContext: NSManagedObjectContext) {
        self.event = event
        self.conversation = conversation
        self.moc = managedObjectContext
        if let senderID = event.senderUUID() {
            self.sender = ZMUser(remoteID: senderID, createIfNeeded: false, in: self.moc)
        }
    }
    
    func shouldCreateNotification() -> Bool {
        // The notification either has a conversation or does not require one
        guard conversation != nil || !requiresConversation else { return false }
        // if there is a sender, it's not the selfUser
        if let sender = self.sender, sender.isSelfUser { return false }
        
        if let conversation = conversation {
            if conversation.isSilenced {
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
        if let moc = conversation?.managedObjectContext {
            teamName = ZMUser.selfUser(in: moc).team?.name
        }
        
        return ZMPushStringTitle.localizedString(withConversationName: conversation?.meaningfulDisplayName, teamName: teamName)
    }
    
    func bodyText() -> String {
        return ZMPushStringDefault.localizedStringForPushNotification()
    }
    
    func category() -> String {
        return ZMConversationCategory
    }

    func soundName() -> String {
        return ZMCustomSound.notificationNewMessageSoundName()
    }
    
    func userInfo() -> [AnyHashable : Any]? {
        
        guard let selfUserID = ZMUser.selfUser(in: moc).remoteIdentifier else { return nil }
        
        var userInfo = [AnyHashable: Any]()
        userInfo[SelfUserIDStringKey] = selfUserID.transportString()
        
        if let senderID = event.senderUUID() {
            userInfo[SenderIDStringKey] = senderID.transportString()
        }
        
        if let conversationID = conversation?.remoteIdentifier {
            userInfo[ConversationIDStringKey] = conversationID.transportString()
        }
        
        if let messageNonce = event.messageNonce() {
            userInfo[MessageNonceIDStringKey] = messageNonce.transportString()
        }
        
        if let eventTime = event.timeStamp() {
            userInfo[EventTimeKey] = eventTime
        }
        
        if requiresConversation {
            userInfo[ConversationNameStringKey] = conversation?.meaningfulDisplayName
        }
        
        userInfo[TeamNameStringKey] = teamName
        
        return userInfo
    }
}


// MARK: - Reaction Event

private class ReactionEventNotificationBuilder: EventNotificationBuilder {
    
    override var requiresConversation: Bool { return true }
    
    private var emoji : String!
    private var nonce : String!
    
    override func shouldCreateNotification() -> Bool {
        guard super.shouldCreateNotification() else { return false }
        
        guard let receivedMessage = ZMGenericMessage(from: event), receivedMessage.hasReaction() else {
            return false
        }
        
        // If the message is an "unlike", we don't want to display a notification
        guard receivedMessage.reaction.emoji != "" else { return false }
        
        // fetch message that was reacted to and make sure the sender of the original message is the selfUser
        guard let conversation = conversation,
            let message = ZMMessage.fetch(withNonce: UUID(uuidString: receivedMessage.reaction.messageId), for: conversation, in: moc),
            message.sender == ZMUser.selfUser(in: moc)
            else { return false }
        
        emoji = receivedMessage.reaction.emoji
        nonce = receivedMessage.reaction.messageId
        return true
    }
    
    override func bodyText() -> String {
        if shouldHideContent {
            return super.bodyText()
        }
        else {
            return ZMPushStringReaction.localizedString(with: sender, conversation: conversation, emoji: emoji!)
        }
    }
    
    override func userInfo() -> [AnyHashable : Any]? {
        // we want to store the nonce of the message being reacted to, not the event nonce
        var info = super.userInfo()
        info?[MessageNonceIDStringKey] = nonce
        return info
    }
}


// MARK: - Conversation Create Event

private class ConversationCreateEventNotificationBuilder: EventNotificationBuilder {
    
    override func titleText() -> String? {
        teamName = ZMUser.selfUser(in: moc).team?.name
        return ZMPushStringTitle.localizedString(withConversationName: nil, teamName: teamName)
    }
    
    override func bodyText() -> String {
        return ZMPushStringConversationCreate.localizedString(with: sender, count: nil)
    }
    
    override func category() -> String {
        return ZMConnectCategory
    }
}


// MARK: - User Connection Event

private class UserConnectionEventNotificationBuilder: EventNotificationBuilder {
    
    enum ConnectionType { case accepted, requested }
    
    var connectionType : ConnectionType!
    
    override func shouldCreateNotification() -> Bool {
        guard super.shouldCreateNotification() else { return false }
        
        if let status = (event.payload["connection"] as? [String: AnyObject] )?["status"] as? String {
            if status == "accepted" {
                connectionType = .accepted
                return true
            } else if status == "pending" {
                connectionType = .requested
                return true
            }
        }
        
        return false
    }
    
    override func titleText() -> String? {
        return nil
    }
    
    override func bodyText() -> String {
        let name = sender?.name ?? (event.payload["user"] as? [String : Any])?["name"] as? String
        if connectionType == .requested {
            return ZMPushStringConnectionRequest.localizedString(withUserName: name)
        }
        
        return ZMPushStringConnectionAccepted.localizedString(withUserName: name)
    }
    
    override func category() -> String {
        return (connectionType == .requested) ? ZMConnectCategory : ZMConversationCategory
    }
}


// MARK: - New User Event

private class NewUserEventNotificationBuilder: EventNotificationBuilder {
    
    override func titleText() -> String? {
        return nil
    }
    
    override func bodyText() -> String {
        let name = (event.payload["user"] as? [String : Any])?["name"] as? String
        return ZMPushStringNewConnection.localizedString(withUserName: name)
    }
}
