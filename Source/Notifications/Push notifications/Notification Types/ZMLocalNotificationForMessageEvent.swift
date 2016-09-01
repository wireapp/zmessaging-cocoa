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


import ZMUtilities
import MobileCoreServices;

public func findIndex<S: SequenceType>(sequence: S, predicate: (S.Generator.Element) -> Bool) -> Int? {
    for (index, element) in sequence.enumerate() {
        if predicate(element) {
            return index
        }
    }
    return nil
}

let MaximumNumberOfEventsBeforeBundling = 5


public class ZMLocalNotificationForPostInConversationEvent : ZMLocalNotificationForEvent {
    
    public override var eventType: ZMLocalNotificationForEventType {return .PostInConversation
    }

    override var requiresConversation : Bool {
        return true
    }
    
    var encryptedEventData : String? {
        guard let lastEvent = lastEvent,
              let payload = lastEvent.payload as? [String : AnyObject]
        else { return nil }
        
        if let data = payload["data"] {
            if let data = data["text"] as? String {
                return data
            }
            if let data = data["info"] as? String {
                return data
            }
        }
        return nil
    }
}


enum ZMLocalNotificationContentType  {
    case Undefined, Text(String), Image, Video, Audio, Location, FileUpload
    
    static func typeForMessage(message: ZMGenericMessage) -> ZMLocalNotificationContentType {
        if message.hasText() && message.text.content.characters.count > 0 {
            return .Text(message.text.content)
        }
        if message.hasImage() {
            return .Image
        }
        let mimeType = message.asset.original.mimeType
        if mimeType.zm_conformsToUTI(kUTTypeMovie) {
            return .Video
        }
        if mimeType.zm_conformsToUTI(kUTTypeAudio) {
            return .Audio
        }
        if message.hasAsset() {
            return .FileUpload
        }
        if message.hasLocation() {
            return .Location
        }
        return .Undefined
    }
}
extension ZMLocalNotificationContentType : Equatable {
}

func ==(lhs: ZMLocalNotificationContentType, rhs: ZMLocalNotificationContentType) -> Bool {
    switch (lhs, rhs) {
    case (let .Text(content1), let .Text(content2)):
        return content1 == content2
    case (.Image, .Image), (.Audio, .Audio), (.Video, .Video), (.Location, .Location), (.FileUpload, .FileUpload), (.Undefined, .Undefined):
        return true
    default:
        return false
    }
}

public class ZMLocalNotificationForMessage: ZMLocalNotificationForPostInConversationEvent {
    var contentType : ZMLocalNotificationContentType = .Undefined
    
    override func canCreateNotification() -> Bool {
        guard super.canCreateNotification()
            else { return false }
        
        switch lastEvent!.type {
        case .ConversationOtrAssetAdd, .ConversationOtrMessageAdd:
            guard let encryptedEventData = encryptedEventData else { return false }
            
            var genericMessage : ZMGenericMessage?
            let exception = zm_tryBlock {
                genericMessage = ZMGenericMessage(base64String: encryptedEventData)
            }
            guard exception == nil, let message = genericMessage else { return false }
            
            let aType = ZMLocalNotificationContentType.typeForMessage(message)
            guard aType != .Undefined else { return false }
            self.contentType = aType
            return true
        case .ConversationMessageAdd:
            guard let text = eventData["content"] as? String where text.characters.count > 0
                else { return false }
            contentType = .Text(text)
            return true
        case .ConversationAssetAdd:
            guard let tag = eventData["info"]?["tag"] as? String where tag == "medium"
                else { return false }
            contentType = .Image
            return true
        default:
            return false
        }
    }
    
    // MARK : Notification content
    override func configureAlertBody() -> String {
        switch contentType {
        case .Text(let content):
            return ZMPushStringMessageAdd.localizedStringWithUser(sender, conversation: conversation, text:content)
        case .Image:
            return ZMPushStringImageAdd.localizedStringWithUser(sender, conversation: conversation)
        case .Video:
            return ZMPushStringVideoAdd.localizedStringWithUser(sender, conversation: conversation)
        case .Audio:
            return ZMPushStringAudioAdd.localizedStringWithUser(sender, conversation: conversation)
        case .FileUpload:
            return ZMPushStringFileAdd.localizedStringWithUser(sender, conversation: conversation)
        case .Location:
            return ZMPushStringLocationAdd.localizedStringWithUser(sender, conversation: conversation)
        default:
            return alertBodyForMultipleMessageAddEvents
        }
    }
    
    var alertBodyForMultipleMessageAddEvents : String {
        let count = conversation!.estimatedUnreadCount + 1
        
        if conversation?.conversationType != .OneOnOne {
            return (ZMPushStringMessageAddMany + ".group").localizedStringWithConversation(conversation, count: count)
        } else {
            return (ZMPushStringMessageAddMany + ".oneonone").localizedStringWithUser(sender, count: count)
        }
    }
}


public class ZMLocalNotificationForKnockMessage : ZMLocalNotificationForPostInConversationEvent {
    
    public override var eventType: ZMLocalNotificationForEventType {return .Knock
    }
    
    override var copiedEventTypes : [ZMUpdateEventType] {
        return [.ConversationKnock, .ConversationOtrMessageAdd]
    }
    
    override func canCreateNotification() -> Bool {
        guard super.canCreateNotification()
            else { return false }
        
        switch lastEvent!.type {
        case .ConversationOtrMessageAdd:
            guard let encryptedEventData = encryptedEventData else { return false }
            
            var genericMessage : ZMGenericMessage?
            let exception = zm_tryBlock{
                genericMessage = ZMGenericMessage(base64String: encryptedEventData)
            }
            
            guard exception == nil,
                let message = genericMessage where message.hasKnock()
            else { return false }
            
            return true
        case .ConversationKnock:
            return true
        default:
            return false
        }
    }
    
    // MARK : Notification content
    override func configureAlertBody() -> String {
        let knockCount = NSNumber(integer: events.count)
        return ZMPushStringKnock.localizedStringWithUser(self.sender, conversation:self.conversation, count:knockCount)
    }

    override var soundName : String {
        return ZMLocalNotificationPingSoundName()
    }
    
    override var shouldCopyEventsOfSameSender : Bool {
        return true
    }

}

public class ZMLocalNotificationForReaction : ZMLocalNotificationForPostInConversationEvent {
    
    private var emoji : String?
    
    public override var eventType: ZMLocalNotificationForEventType {
        return .Reaction
    }
    
    override var copiedEventTypes: [ZMUpdateEventType] {
        return [.ConversationOtrMessageAdd]
    }
    
    // We create notification only if self users message was reacted to
    override func canCreateNotification() -> Bool {
        guard super.canCreateNotification() else { return false }

        guard let encryptedEventData = encryptedEventData else { return false }
        var genericMessage : ZMGenericMessage?
        let exception = zm_tryBlock{
            genericMessage = ZMGenericMessage(base64String: encryptedEventData)
        }
        
        guard exception == nil else { return false }
    
        guard let receivedMessage = genericMessage
            where receivedMessage.hasReaction()
            else { return false }
    
        // fetch message that was reacted to and make sure the sender
        guard let conversation = self.conversation,
              let message = ZMMessage.fetchMessageWithNonce(NSUUID(UUIDString: receivedMessage.reaction.messageId), forConversation: conversation, inManagedObjectContext: self.managedObjectContext)
            where message.sender == ZMUser.selfUserInContext(self.managedObjectContext)
            else { return false }

        emoji = receivedMessage.reaction.emoji
        
        return true

    }
    
    override func configureAlertBody() -> String {
        // TODO: use correct string
        return ZMPushStringReaction.localizedStringWithUser(self.sender, conversation: conversation, emoji: self.emoji!)
    }
}


