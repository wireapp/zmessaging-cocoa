////
// Wire
// Copyright (C) 2018 Wire Swiss GmbH
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

extension ZMConversationTranscoder {

    @objc (processAccessModeUpdateEvent:inConversation:)
    public func processAccessModeUpdate(event: ZMUpdateEvent, in conversation: ZMConversation) {
        precondition(event.type == .conversationAccessModeUpdate, "invalid update event type")
        guard let payload = event.payload["data"] as? [String : AnyHashable] else { return }
        guard let access = payload["access"] as? [String] else { return }
        guard let accessRole = payload["access_role"] as? String else { return }

        conversation.accessMode = ConversationAccessMode(values: access)
        conversation.accessRole = ConversationAccessRole(rawValue: accessRole)
    }
    
    @objc (processDestructionTimerUpdateEvent:inConversation:)
    public func processDestructionTimerUpdate(event: ZMUpdateEvent, in conversation: ZMConversation) {
        precondition(event.type == .conversationMessageTimerUpdate, "invalid update event type")
        guard let payload = event.payload["data"] as? [String : AnyHashable],
            let senderUUID = event.senderUUID() else { return }
        if let timeoutIntegerValue = payload["message_timer"] as? Int64 {
            // Backend is sending the miliseconds, we need to convert to seconds.
            let timeoutValue = MessageDestructionTimeoutValue(rawValue: TimeInterval(timeoutIntegerValue / 1000))
            conversation.messageDestructionTimeout = .synced(timeoutValue)
        } else {
            conversation.messageDestructionTimeout = nil
        }
        
        if let user = ZMUser(remoteID: senderUUID, createIfNeeded: false, in: managedObjectContext),
            let timestamp = event.timeStamp() {
            
            let timer: TimeInterval
            
            // system message timer should reflect the synced value, not local
            if let timeout = conversation.messageDestructionTimeout,
             case let .synced(value) = timeout {
                timer = value.rawValue
            } else {
                timer = 0
            }
            
            let message = conversation.appendMessageTimerUpdateMessage(fromUser: user, timer: timer, timestamp: timestamp)
            localNotificationDispatcher.process(message)
        }
    }

}

extension ZMConversation {
    @objc public var accessPayload: [String]? {
        return accessMode?.stringValue
    }
    
    @objc public var accessRolePayload: String? {
        return accessRole?.rawValue
    }
}
