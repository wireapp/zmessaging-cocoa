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

import UIKit
import MobileCoreServices;


public protocol NotificationForMessage : LocalNotification {
    associatedtype MessageType : ZMMessage
    
    var contentType : ZMLocalNotificationContentType { get }
    init?(message: MessageType, application: Application?)
    func copyByAddingMessage(message: MessageType) -> Self?
    func configureAlertBody(message: MessageType) -> String
    static func shouldCreateNotification(message: MessageType) -> Bool
}

extension NotificationForMessage {
    
    public var soundName : String {
        switch contentType {
        case .Knock:
            return ZMLocalNotificationPingSoundName()
        default:
            return ZMLocalNotificationNewMessageSoundName()
        }
    }
    
    public func configureNotification(message: MessageType) -> UILocalNotification {
        let notification = UILocalNotification()
        let shouldHideContent = message.managedObjectContext!.valueForKey(ZMShouldHideNotificationContentKey)
        if let shouldHideContent = shouldHideContent as? NSNumber where shouldHideContent.boolValue == true {
            notification.alertBody = ZMPushStringDefault.localizedString()
            notification.soundName = ZMLocalNotificationNewMessageSoundName()
        } else {
            notification.alertBody = configureAlertBody(message).stringByEscapingPercentageSymbols()
            notification.soundName = soundName
            notification.category = ZMConversationCategory
        }
        notification.setupUserInfo(message)
        return notification
    }
    
    static public func shouldCreateNotification(message: MessageType) -> Bool {
        guard let sender = message.sender where !sender.isSelfUser
            else { return false }
        if let conversation = message.conversation {
            if conversation.isSilenced {
                return false
            }
            if let timeStamp = message.serverTimestamp, let lastRead = conversation.lastReadServerTimeStamp
                where lastRead.compare(timeStamp) != .OrderedAscending
            {
                return false
            }
        }
        return true
    }
}


final public class ZMLocalNotificationForMessage : ZMLocalNotification, NotificationForMessage {
    public typealias MessageType = ZMOTRMessage
    public let contentType : ZMLocalNotificationContentType

    public var notifications : [UILocalNotification] = []

    let senderUUID : NSUUID
    let messageNonce : NSUUID

    public override var uiNotifications: [UILocalNotification] {
        return notifications
    }
    
    var eventCount : Int = 1
    unowned public var application : Application
    
    public required init?(message: ZMOTRMessage, application: Application?) {
        self.contentType = ZMLocalNotificationContentType.typeForMessage(message)
        guard self.dynamicType.canCreateNotification(message, contentType: contentType),
              let conversation = message.conversation,
              let sender = message.sender
        else {return nil}
        
        self.messageNonce = message.nonce
        self.senderUUID = sender.remoteIdentifier!
        self.application = application ?? UIApplication.sharedApplication()
        super.init(conversationID: conversation.remoteIdentifier)
        
        let notification = configureNotification(message)
        notifications.append(notification)
    }

    public func configureAlertBody(message: ZMOTRMessage) -> String {
        let sender = message.sender
        let conversation = message.conversation
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
        case .Knock:
            let knockCount = NSNumber(integer: eventCount)
            return ZMPushStringKnock.localizedStringWithUser(sender, conversation:conversation, count:knockCount)
        default:
            return ""
        }
    }
    
    class func canCreateNotification(message : ZMOTRMessage, contentType: ZMLocalNotificationContentType) -> Bool {
        switch contentType {
        case .Undefined, .System:
            return false
        default:
           return shouldCreateNotification(message)
        }
    }
    
    public func copyByAddingMessage(message: ZMOTRMessage) -> ZMLocalNotificationForMessage? {
        let otherContentType = ZMLocalNotificationContentType.typeForMessage(message)
        guard otherContentType == contentType &&
              self.dynamicType.canCreateNotification(message, contentType: otherContentType),
              let conversation = message.conversation where conversation.remoteIdentifier == conversationID
        else { return nil }

        switch (otherContentType) {
        case (.Knock):
            eventCount = eventCount+1
            cancelNotifications()
            let note = configureNotification(message)
            notifications.append(note)
            return self
        default:
            return nil
        }
    }
    
    public func isNotificationFor(messageID: NSUUID) -> Bool {
        return (messageID == messageNonce)
    }
}



