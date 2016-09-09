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


final public class ZMLocalNotificationForSystemMessage : ZMLocalNotification, NotificationForMessage {

    public typealias MessageType = ZMSystemMessage
    public let contentType : ZMLocalNotificationContentType
    static let supportedMessageTypes : [ZMSystemMessageType] = [.ParticipantsRemoved, .ParticipantsAdded, .ConversationNameChanged, .ConnectionRequest]

    let senderUUID : NSUUID
    public var notifications : [UILocalNotification] = []
    var userCount: Int = 0
    
    public override var uiNotifications: [UILocalNotification] {
        return notifications
    }
    
    unowned public var application : Application
    
    public required init?(message: ZMSystemMessage, application: Application?) {
        self.contentType = ZMLocalNotificationContentType.typeForMessage(message)
        guard self.dynamicType.canCreateNotification(message),
              let sender = message.sender
        else {return nil}
        
        self.senderUUID = sender.remoteIdentifier!
        self.application = application ?? UIApplication.sharedApplication()
        super.init(conversationID: message.conversation?.remoteIdentifier)
        
        let notification = configureNotification(message)
        notifications.append(notification)
    }
    
    public func configureAlertBody(message: ZMSystemMessage) -> String {
        switch message.systemMessageType {
        case .ParticipantsRemoved, .ParticipantsAdded:
            return alertBodyForParticipantEvents(message)
        case .ConversationNameChanged:
            return ZMPushStringConversationRename.localizedStringWithUser(message.sender, count:nil, text:message.text)
        case .ConnectionRequest:
            return ZMPushStringConnectionRequest.localizedStringWithUserName(message.text)
        default:
            return ""
        }
    }
    
    func alertBodyForParticipantEvents(message: ZMSystemMessage) -> String {
        let isLeaveEvent = (message.systemMessageType == .ParticipantsRemoved)
        let isCopy = (userCount != 0)
        let users = isLeaveEvent ? message.removedUsers : message.addedUsers
        
        userCount = userCount + users.count
        if isCopy {
            let key = isLeaveEvent ? ZMPushStringMemberLeaveMany : ZMPushStringMemberJoinMany
            return key.localizedStringWithUser(nil, conversation: message.conversation, otherUser: nil)
        }
        
        var user: ZMUser?
        var key : NSString = isLeaveEvent ? ZMPushStringMemberLeaveMany : ZMPushStringMemberJoinMany
        if userCount == 1 {
            if (users.first == message.sender) {
                key = ZMPushStringMemberLeaveSender
            } else {
                user = users.first
                key = isLeaveEvent ? ZMPushStringMemberLeave : ZMPushStringMemberJoin
            }
        }
        return key.localizedStringWithUser(message.sender, conversation: message.conversation, otherUser: user)
    }
    
    class func canCreateNotification(message : ZMSystemMessage) -> Bool {
        guard supportedMessageTypes.contains(message.systemMessageType) else { return false }
        return shouldCreateNotification(message)
    }
    
    public func copyByAddingMessage(message: ZMSystemMessage) -> ZMLocalNotificationForSystemMessage? {
        let otherContentType = ZMLocalNotificationContentType.typeForMessage(message)
        
        guard otherContentType == contentType,
              let conversation = message.conversation where conversation.remoteIdentifier == conversationID,
              let sender = message.sender where !sender.isSelfUser
        else { return nil }
        
        switch (contentType, otherContentType){
        case (.System(let type), .System) where type == .ParticipantsAdded || type == .ParticipantsRemoved:
            cancelNotifications()
            let note = configureNotification(message)
            notifications.append(note)
            return self
        default:
            return nil
        }
    }
}
