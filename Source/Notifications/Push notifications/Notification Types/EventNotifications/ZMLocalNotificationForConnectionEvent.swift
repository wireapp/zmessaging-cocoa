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

class ZMLocalNotificationForConverstionCreateEvent : ZMLocalNotificationForEvent {
    
    override var eventType : ZMUpdateEventType {
        return .conversationCreate
    }
    
    override func textToDisplay(_ conversation: ZMConversation?) -> String {
        return ZMPushStringConversationCreate.localizedString(with: sender, count:nil)
    }
    
    override var category : String {
        return ZMConnectCategory
    }
}

class ZMLocalNotificationForUserConnectionEvent : ZMLocalNotificationForEvent {
    
    override var eventType : ZMUpdateEventType {
        return .userConnection
    }
    
    enum ConnectionType {
        case accepted, requested
    }
    
    var connectionType : ConnectionType!
    
    override func canCreateNotification(_ conversation: ZMConversation?) -> Bool {
        if !super.canCreateNotification(conversation) { return false }
        let lastEvent = self.lastEvent! // last event is sure to exist here, checked in canCreateNotificaion
        if let status = (lastEvent.payload["connection"] as? [String: AnyObject] )?["status"] as? String {
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
    
    override func textToDisplay(_ conversation: ZMConversation?) -> String {
        let name = sender?.name ?? (lastEvent!.payload["user"] as? [String : Any])?["name"] as? String
        if connectionType == .requested {
            return ZMPushStringConnectionRequest.localizedString(withUserName: name)
        }
        return ZMPushStringConnectionAccepted.localizedString(withUserName: name)
    }
    
    override var category : String {
        return (connectionType == .requested) ? ZMConnectCategory : ZMConversationCategory
    }
}

class ZMLocalNotificationForNewUserEvent : ZMLocalNotificationForEvent {
    
    override var eventType : ZMUpdateEventType {
        return .userContactJoin
    }
    
    override func textToDisplay(_ conversation: ZMConversation?) -> String {
        let name = (lastEvent!.payload["user"] as? [String : Any])?["name"] as? String
        return ZMPushStringNewConnection.localizedString(withUserName: name)
    }
}


