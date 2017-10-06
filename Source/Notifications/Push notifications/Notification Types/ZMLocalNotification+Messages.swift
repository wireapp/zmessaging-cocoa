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


// MARK: - Failed Messages

extension ZMLocalNotification {
    
    convenience init?(expiredMessage: ZMMessage) {
        guard let conversationID = expiredMessage.conversation?.remoteIdentifier else { return nil }
        self.init(conversationID: conversationID, type: .failedMessage)
        configureforExpiredMessage(in: expiredMessage.conversation)
    }
    
    private func configureforExpiredMessage(in conversation: ZMConversation!) {
        
        switch conversation.conversationType {
        case .group:
            body = FailedMessageInGroupConversationText.localizedString(with: conversation, count: nil)
        default:
            body = FailedMessageInOneOnOneConversationText.localizedString(with: conversation.connectedUser, count: nil)
        }
        
        configureTitle(for: conversation)

        // TODO: sound? category?
    }
}


// MARK: - Message

extension ZMLocalNotification {
    
    convenience init?(message: ZMMessage) {
        guard let conversationID = message.conversation?.remoteIdentifier else { return nil }
        let contentType = ZMLocalNotificationContentType.typeForMessage(message)
        // system messages are processed separately
        if case .system(_) = contentType { return nil }
        guard type(of: self).shouldCreateNotification(for: message) else { return nil }
        self.init(conversationID: conversationID, type: .message(contentType))
        configure(for: message, in: message.conversation, type: contentType)
    }
    
    /// Determines if the notification should be created for the given message.
    /// If true is returned, then this guarantees that the message has a conversation
    /// and sender.
    ///
    fileprivate static func shouldCreateNotification(for message: ZMMessage) -> Bool {
        
        guard let sender = message.sender, !sender.isSelfUser else { return false }
        guard let conversation = message.conversation else { return false }
        
        if conversation.isSilenced { return false }
        
        if
            let timeStamp = message.serverTimestamp,
            let lastRead = conversation.lastReadServerTimeStamp,
            lastRead.compare(timeStamp) != .orderedAscending
        {
            return false
        }
        
        return true
    }
    
    fileprivate func configure(for message: ZMMessage, in conversation: ZMConversation!, type: ZMLocalNotificationContentType) {
        
        if shouldHideContent(for: message) {
            body = (message.isEphemeral ? ZMPushStringEphemeral : ZMPushStringDefault).localizedStringForPushNotification()
            soundName = ZMCustomSound.notificationNewMessageSoundName()
        }
        else {
            configureBody(for: message, type: type)
            soundName = type == .knock ? ZMCustomSound.notificationPingSoundName() : ZMCustomSound.notificationNewMessageSoundName()
        }
        
        configureTitle(for: conversation)
        configureCategory(for: message)
    }
    
    /// Determines the notification body text for the given message and content type.
    ///
    private func configureBody(for message: ZMMessage, type: ZMLocalNotificationContentType) {
        let sender = message.sender
        let conversation = message.conversation
        let text: NSString?
        
        switch type {
        case .text(let content):
            text = ZMPushStringMessageAdd.localizedString(with: sender, conversation: conversation, text:content)
            
        case .system(let systemMessageType):
            text = bodyText(for: systemMessageType)
            
        default:
            text = type.localizationString?.localizedString(with: sender, conversation: conversation)
        }
        
        if let text = text {
            body = text.escapingPercentageSymbols()
        }
    }
    
    /// Determines the notification category for the given message.
    ///
    private func configureCategory(for message: ZMMessage) {
        guard !message.isEphemeral else { category = ZMConversationCategory }
        switch self.type {
        case .message(let contentType):
            switch contentType {
            case .knock, .system(_), .undefined: category = ZMConversationCategory
            default: category = ZMConversationCategoryIncludingLike
            }
        default: category = nil
        }
    }
    
    /// Determines if the notification content should be hidden for the given message.
    ///
    private func shouldHideContent(for message: ZMMessage) -> Bool {
        let shouldHideKey = LocalNotificationDispatcher.ZMShouldHideNotificationContentKey
        if let hide = message.managedObjectContext!.persistentStoreMetadata(forKey: shouldHideKey) as? NSNumber,
            hide.boolValue == true {
            return true
        }
        else {
            return message.isEphemeral
        }
    }
}


// MARK: - System Message

extension ZMLocalNotification {
    
    private static var supportedMessageTypes: [ZMSystemMessageType] {
        return [.participantsRemoved, .participantsAdded, .connectionRequest]
    }
    
    convenience init?(systemMessage: ZMSystemMessage) {
        guard
            let conversationID = systemMessage.conversation?.remoteIdentifier,
            type(of: self).shouldCreateNotification(for: systemMessage)
            else { return nil }
        
        let contentType = ZMLocalNotificationContentType.typeForMessage(systemMessage)
        self.init(conversationID: conversationID, type: .message(contentType))
        configure(for: systemMessage as ZMMessage, in: systemMessage.conversation, type: contentType)
    }
    
    private static func shouldCreateNotification(for message: ZMSystemMessage) -> Bool {
        guard supportedMessageTypes.contains(message.systemMessageType) else { return false }
        
        // we don't want to create notifications when another user leaves the conversation
        if message.systemMessageType == .participantsRemoved,
            let removedUser = message.users.first,
            removedUser != ZMUser.selfUser(in: message.managedObjectContext!)
        {
            return false
        }
        
        return shouldCreateNotification(for: message as ZMMessage)
    }
    
    fileprivate func bodyText(for systemMessageType: ZMSystemMessageType) -> NSString? {
        switch systemMessageType {
        case .participantsAdded, .participantsRemoved:
            // TODO: single & many participation
            return nil
        case .connectionRequest:
            return ZMPushStringConnectionRequest.localizedString(withUserName: message.text)
        default:
            return nil
        }
    }
}
