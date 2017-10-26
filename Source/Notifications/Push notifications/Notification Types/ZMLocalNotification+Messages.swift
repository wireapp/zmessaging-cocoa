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
        guard message.conversation?.remoteIdentifier  != nil else { return nil }
        let contentType = ZMLocalNotificationContentType.typeForMessage(message)
        let builder = MessageNotificationBuilder(message: message, contentType: contentType)
        self.init(conversation: message.conversation, type: .message(contentType), builder: builder)
        self.isEphemeral = message.isEphemeral
    }
    
    fileprivate class MessageNotificationBuilder: NotificationBuilder {
        
        fileprivate let message: ZMMessage
        fileprivate let contentType: ZMLocalNotificationContentType
        fileprivate var teamName: String?
        
        private var sender: ZMUser!
        var conversation: ZMConversation?
        
        /// Determines if the notification content should be hidden for the given message.
        ///
        private lazy var shouldHideContent: Bool = {
            let shouldHideKey = LocalNotificationDispatcher.ZMShouldHideNotificationContentKey
            if let hide = self.message.managedObjectContext!.persistentStoreMetadata(forKey: shouldHideKey) as? NSNumber,
                hide.boolValue == true {
                return true
            }
            else {
                return self.message.isEphemeral
            }
        }()
        
        init(message: ZMMessage, contentType: ZMLocalNotificationContentType) {
            self.message = message
            self.contentType = contentType
        }
        
        func shouldCreateNotification() -> Bool {
            guard let sender = message.sender, let conversation = message.conversation else { return false }
            
            self.sender = sender
            self.conversation = conversation
            
            if sender.isSelfUser || conversation.isSilenced { return false }
            
            if
                let timeStamp = message.serverTimestamp,
                let lastRead = conversation.lastReadServerTimeStamp,
                lastRead.compare(timeStamp) != .orderedAscending
            {
                return false
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
            if shouldHideContent {
                return (message.isEphemeral ? ZMPushStringEphemeral : ZMPushStringDefault).localizedStringForPushNotification()
            } else {
                
                var text: String?
                
                switch contentType {
                case .text(let content):
                    text = ZMPushStringMessageAdd.localizedString(with: sender, conversation: conversation, text: content)
                case .knock:
                    text = ZMPushStringKnock.localizedString(with: sender, conversation: conversation, count: 1)
                default:
                    text = contentType.localizationString?.localizedString(with: sender, conversation: conversation)
                }
                                
                return text?.trimmingCharacters(in: .whitespaces) ?? ""
            }
        }
        
        func category() -> String {
            guard !message.isEphemeral else { return ZMConversationCategory }
            switch contentType {
            case .knock, .system(_), .undefined: return ZMConversationCategory
            default: return ZMConversationCategoryIncludingLike
            }
        }
        
        func soundName() -> String {
            if shouldHideContent {
                return ZMCustomSound.notificationNewMessageSoundName()
            }
            else {
                return contentType == .knock ? ZMCustomSound.notificationPingSoundName() : ZMCustomSound.notificationNewMessageSoundName()
            }
        }
        
        func userInfo() -> [AnyHashable: Any]? {
            
            guard
                let moc = message.managedObjectContext,
                let selfUserID = ZMUser.selfUser(in: moc).remoteIdentifier,
                let senderID = sender.remoteIdentifier,
                let conversationID = conversation?.remoteIdentifier,
                let eventTime = message.serverTimestamp
                else { return nil }
            
            var userInfo = [AnyHashable: Any]()
            userInfo[SelfUserIDStringKey] = selfUserID.transportString()
            userInfo[SenderIDStringKey] = senderID.transportString()
            userInfo[MessageNonceIDStringKey] = message.nonce.transportString()
            userInfo[ConversationIDStringKey] = conversationID.transportString()
            userInfo[EventTimeKey] = eventTime
            userInfo[ConversationNameStringKey] = conversation?.meaningfulDisplayName
            userInfo[TeamNameStringKey] = teamName
            return userInfo
        }
    }
    
}


// MARK: - System Message

extension ZMLocalNotification {
    
    convenience init?(systemMessage: ZMSystemMessage) {
        guard systemMessage.conversation?.remoteIdentifier != nil else { return nil }
        let contentType = ZMLocalNotificationContentType.typeForMessage(systemMessage)
        let builder = SystemMessageNotificationBuilder(message: systemMessage)
        self.init(conversation: systemMessage.conversation, type: .message(contentType), builder: builder)
    }
    
    private class SystemMessageNotificationBuilder : MessageNotificationBuilder {
        
        let systemMessageType: ZMSystemMessageType
        
        private var supportedMessageTypes: [ZMSystemMessageType] {
            return [.participantsRemoved, .participantsAdded]
        }
        
        init(message: ZMSystemMessage) {
            self.systemMessageType = message.systemMessageType
            super.init(message: message as ZMSystemMessage, contentType: .system(message.systemMessageType))
        }
        
        override func shouldCreateNotification() -> Bool {
            guard supportedMessageTypes.contains(systemMessageType) else { return false }
            
            let message = self.message as! ZMSystemMessage
            
            // we don't want to create notifications when other people join or leave conversation
            let forSelf = message.users.count == 1 && message.users.first!.isSelfUser
            if !forSelf { return false }
                        
            return super.shouldCreateNotification()
        }
        
        override func bodyText() -> String {
            switch systemMessageType {
            case .participantsAdded, .participantsRemoved:
                return alertBodyForParticipantEvents()
            default:
                // this will never be returned
                return ""
            }
        }
        
        private func alertBodyForParticipantEvents() -> String {
            let isLeaveEvent = systemMessageType == .participantsRemoved
            let message = self.message as! ZMSystemMessage
            
            // we already checked there is only one user and it is the self user
            let selfUser = message.users.first!
            let key = isLeaveEvent ? ZMPushStringMemberLeave : ZMPushStringMemberJoin
            return key.localizedString(with: message.sender, conversation: message.conversation, otherUser: selfUser)
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
        let builder = FailedMessageNotificationBuilder(conversation: conversation)
        self.init(conversation: conversation, type: .failedMessage, builder: builder)
    }
    
    private func configureforExpiredMessage(in conversation: ZMConversation!) {
        
        switch conversation.conversationType {
        case .group:
            body = FailedMessageInGroupConversationText.localizedString(with: conversation, count: nil)
        default:
            body = FailedMessageInOneOnOneConversationText.localizedString(with: conversation.connectedUser, count: nil)
        }
    }
    
    private class FailedMessageNotificationBuilder: NotificationBuilder {
        
        var conversation: ZMConversation?
        private var teamName: String?
        
        init(conversation: ZMConversation?) {
            self.conversation = conversation
        }
        
        func shouldCreateNotification() -> Bool {
            return conversation != nil
        }
        
        func titleText() -> String? {
            if let moc = conversation?.managedObjectContext {
                teamName = ZMUser.selfUser(in: moc).team?.name
            }
            
            return ZMPushStringTitle.localizedString(withConversationName: conversation?.meaningfulDisplayName, teamName: teamName)
        }
        
        func bodyText() -> String {
            switch conversation!.conversationType {
            case .group:
                return FailedMessageInGroupConversationText.localizedString(with: conversation, count: nil)
            default:
                return FailedMessageInOneOnOneConversationText.localizedString(with: conversation?.connectedUser, count: nil)
            }
        }
        
        func soundName() -> String {
            return ZMCustomSound.notificationNewMessageSoundName()
        }
        
        func category() -> String {
            return ZMConversationCategory
        }
        
        func userInfo() -> [AnyHashable : Any]? {
            
            guard
                let moc = conversation?.managedObjectContext,
                let selfUserID = ZMUser.selfUser(in: moc).remoteIdentifier,
                let conversationID = conversation?.remoteIdentifier
                else { return nil }
            
            var userInfo = [AnyHashable: Any]()
            userInfo[SelfUserIDStringKey] = selfUserID.transportString()
            userInfo[ConversationIDStringKey] = conversationID.transportString()
            userInfo[ConversationNameStringKey] = conversation?.meaningfulDisplayName
            userInfo[TeamNameStringKey] = teamName
            return userInfo
        }
    }
}
