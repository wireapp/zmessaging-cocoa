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
    static let supportedMessageTypes : [ZMSystemMessageType] = [.participantsRemoved, .participantsAdded, .connectionRequest]

    let senderUUID : UUID
    public var notifications : [UILocalNotification] = []
    var userCount: Int = 0
    
    public override var uiNotifications: [UILocalNotification] {
        return notifications
    }
    
    unowned public var application : ZMApplication
    
    public required init?(message: ZMSystemMessage, application: ZMApplication?) {
        self.contentType = ZMLocalNotificationContentType.typeForMessage(message)
        guard type(of: self).canCreateNotification(message), let sender = message.sender else { return nil }

        // We don't want to create notifications when a user leaves the conversation
        if message.systemMessageType == .participantsRemoved,
            let removedUser = message.users.first,
            removedUser != ZMUser.selfUser(in: message.managedObjectContext!)  {
            return nil
        }

        self.senderUUID = sender.remoteIdentifier!
        self.application = application ?? UIApplication.shared
        super.init(conversationID: message.conversation?.remoteIdentifier)
        
        let notification = configureNotification(message)
        notifications.append(notification)
    }
    
    public func textToDisplay(_ message: ZMSystemMessage) -> String {
        switch message.systemMessageType {
        case .participantsRemoved, .participantsAdded:
            return alertBodyForParticipantEvents(message)
        case .connectionRequest:
            return ZMPushStringConnectionRequest.localizedString(withUserName: message.text)
        default:
            return ""
        }
    }
    
    func alertBodyForParticipantEvents(_ message: ZMSystemMessage) -> String {
        let isLeaveEvent = (message.systemMessageType == .participantsRemoved)
        let isCopy = (userCount != 0)
        
        userCount = userCount + message.users.count
        if isCopy {
            let key = isLeaveEvent ? ZMPushStringMemberLeaveMany : ZMPushStringMemberJoinMany
            return key.localizedString(with: nil, conversation: message.conversation, otherUser: nil)
        }
        
        var user: ZMUser?
        var key : NSString = (isLeaveEvent ? ZMPushStringMemberLeaveMany : ZMPushStringMemberJoinMany) as NSString
        if userCount == 1 {
            user = message.users.first
            key = (isLeaveEvent ? ZMPushStringMemberLeave : ZMPushStringMemberJoin) as NSString
        }
        return key.localizedString(with: message.sender, conversation: message.conversation, otherUser: user)
    }
    
    class func canCreateNotification(_ message : ZMSystemMessage) -> Bool {
        guard supportedMessageTypes.contains(message.systemMessageType) else { return false }
        return shouldCreateNotification(message)
    }
    
    public func copyByAddingMessage(_ message: ZMSystemMessage) -> ZMLocalNotificationForSystemMessage? {
        let otherContentType = ZMLocalNotificationContentType.typeForMessage(message)
        
        guard otherContentType == contentType,
              let conversation = message.conversation , conversation.remoteIdentifier == conversationID,
              let sender = message.sender , !sender.isSelfUser
        else { return nil }
        
        switch (contentType, otherContentType){
        case (.system(let type), .system) where type == .participantsAdded || type == .participantsRemoved:
            cancelNotifications()
            let note = configureNotification(message)
            notifications.append(note)
            return self
        default:
            return nil
        }
    }
}
