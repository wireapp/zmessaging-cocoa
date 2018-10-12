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
    public func processDestructionTimerUpdate(event: ZMUpdateEvent, in conversation: ZMConversation?) {
        precondition(event.type == .conversationMessageTimerUpdate, "invalid update event type")
        guard let payload = event.payload["data"] as? [String : AnyHashable],
            let senderUUID = event.senderUUID(),
            let user = ZMUser(remoteID: senderUUID, createIfNeeded: false, in: managedObjectContext) else { return }
        
        var timeout: MessageDestructionTimeout?
        let timeoutIntegerValue = (payload["message_timer"] as? Int64) ?? 0
        
        // Backend is sending the miliseconds, we need to convert to seconds.
        timeout = .synced(MessageDestructionTimeoutValue(rawValue: TimeInterval(timeoutIntegerValue / 1000)))
        
        let fromSelf = user.isSelfUser
        let fromOffToOff = !(conversation?.hasSyncedDestructionTimeout ?? false) && timeout == .synced(.none)
        
        let noChange = fromOffToOff || conversation?.messageDestructionTimeout == timeout
        
        // We seem to get duplicate update events for timeout changes, returning
        // early will avoid duplicate system messages.
        if fromSelf && noChange { return }

        conversation?.messageDestructionTimeout = timeout
        
        if let timestamp = event.timeStamp(), let conversation = conversation {
            // system message should reflect the synced timer value, not local
            let timer = conversation.hasSyncedDestructionTimeout ? conversation.messageDestructionTimeoutValue : 0
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
    
    @objc
    public func requestForUpdatingSelfInfo() -> ZMUpstreamRequest? {
        guard let remoteIdentifier = self.remoteIdentifier else {
            return nil
        }
        
        var payload: [String: Any] = [:]
        var updatedKeys: Set<String> = Set()
        
        if hasLocalModifications(forKey: ZMConversationSilencedChangedTimeStampKey) {
            if silencedChangedTimestamp == nil {
                silencedChangedTimestamp = Date()
            }
            
            payload[ZMConversationInfoOTRMutedValueKey] = mutedMessageTypes != .none
            payload[ZMConversationInfoOTRMutedStatusValueKey] = mutedMessageTypes.rawValue
            payload[ZMConversationInfoOTRMutedReferenceKey] = silencedChangedTimestamp?.transportString()
            
            updatedKeys.insert(ZMConversationSilencedChangedTimeStampKey)
        }
        
        if hasLocalModifications(forKey: ZMConversationArchivedChangedTimeStampKey) {
            if archivedChangedTimestamp == nil {
                archivedChangedTimestamp = Date()
            }
            
            payload[ZMConversationInfoOTRArchivedValueKey] = isArchived
            payload[ZMConversationInfoOTRArchivedReferenceKey] = archivedChangedTimestamp?.transportString()
            
            updatedKeys.insert(ZMConversationArchivedChangedTimeStampKey)
        }
        
        guard !updatedKeys.isEmpty else {
            return nil
        }
        
        let path = NSString.path(withComponents: [ConversationsPath, remoteIdentifier.transportString(), "self"])
        let request = ZMTransportRequest(path: path, method: .methodPUT, payload: payload as NSDictionary)
        return ZMUpstreamRequest(keys: updatedKeys, transportRequest: request)
    }
}
