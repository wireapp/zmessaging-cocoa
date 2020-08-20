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
import WireDataModel

public enum LocalNotificationEventType {
    case connectionRequestAccepted, connectionRequestPending, newConnection, conversationCreated, conversationDeleted
}

public enum LocalNotificationContentType : Equatable {
    
    case undefined
    case text(String, isMention: Bool, isReply: Bool)
    case image
    case video
    case audio
    case location
    case fileUpload
    case knock
    case reaction(emoji: String)
    case hidden
    case ephemeral(isMention: Bool, isReply: Bool)
    case participantsRemoved
    case participantsAdded
    case messageTimerUpdate(String?)
    
    static func typeForMessage(_ event: ZMUpdateEvent, conversation: ZMConversation?, in moc: NSManagedObjectContext) -> LocalNotificationContentType? {
        
        switch event.type {
        case .conversationMemberJoin:
            return .participantsAdded
        case .conversationMemberLeave:
            return .participantsRemoved
        case .conversationMessageTimerUpdate:
            guard let payload = event.payload["data"] as? [String : AnyHashable] else {
                return nil
            }
            let timeoutIntegerValue = (payload["message_timer"] as? Int64) ?? 0
            let value = MessageDestructionTimeoutValue(rawValue: TimeInterval(timeoutIntegerValue))
            
            return (value == .none)
                ? .messageTimerUpdate(nil)
                : .messageTimerUpdate(value.displayString)
        case.conversationOtrMessageAdd:
            guard let message = GenericMessage(from: event) else {
                return .undefined
            }
            return typeForMessage(message, conversation: conversation, in: moc)
        default:
            return nil
        }
    }
    
    static func typeForMessage(_ message: GenericMessage, conversation: ZMConversation?, in moc: NSManagedObjectContext) -> LocalNotificationContentType? {
        
        let selfUser = ZMUser.selfUser(in: moc)

        func getQuotedMessage(_ textMessageData: Text, conversation: ZMConversation?, in moc: NSManagedObjectContext) -> ZMOTRMessage? {
            guard let conversation = conversation else { return nil }
            let quotedMessageId = UUID(uuidString: textMessageData.quote.quotedMessageID)
            return ZMOTRMessage.fetch(withNonce: quotedMessageId, for: conversation, in: moc)
        }

        switch message.content {
        case .location:
            return .location

        case .knock:
            return .knock

        case .image:
            return .image

        case .ephemeral:
            if let textMessageData = message.textData {
                let quotedMessage = getQuotedMessage(textMessageData, conversation: conversation, in: moc)
                return .ephemeral(isMention: textMessageData.isMentioningSelf(selfUser), isReply: textMessageData.isQuotingSelf(quotedMessage))
            } else {
                return .ephemeral(isMention: false, isReply: false)
            }

        case .text, .edited:
            guard
                let textMessageData = message.textData,
                let text = message.textData?.content.removingExtremeCombiningCharacters, !text.isEmpty
            else {
                return nil
            }

            let quotedMessage = getQuotedMessage(textMessageData, conversation: conversation, in: moc)
            return .text(text, isMention: textMessageData.isMentioningSelf(selfUser), isReply: textMessageData.isQuotingSelf(quotedMessage))

        case .composite:
            guard let textData = message.composite.items.compactMap({ $0.text }).first else { return nil }
            return .text(textData.content, isMention: textData.isMentioningSelf(selfUser), isReply: false)

        case .asset(let assetData):
            switch assetData.original.metaData {
            case .audio?:
                return .audio
            case .video?:
                return .video
            case .image:
                return .image
            default:
                return .fileUpload
            }

        default:
           return nil
        }
    }
    
}
