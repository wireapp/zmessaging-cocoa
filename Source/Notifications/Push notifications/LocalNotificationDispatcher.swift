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

import Foundation
import UserNotifications

extension LocalNotificationDispatcher: ZMEventConsumer {

    public func processEvents(_ events: [ZMUpdateEvent], liveEvents: Bool, prefetchResult: ZMFetchRequestBatchResult?) {
        // nop
    }
    
    public func processEventsWhileInBackground(_ events: [ZMUpdateEvent]) {
        let eventsToForward = events.filter { $0.source.isOne(of: .pushNotification, .webSocket) }
        self.didReceive(events: eventsToForward, conversationMap: [:])
    }

    func didReceive(events: [ZMUpdateEvent], conversationMap: [UUID: ZMConversation]) {
        events.forEach { event in

            var conversation: ZMConversation?
            if let conversationID = event.conversationUUID {
                // Fetch the conversation here to avoid refetching every time we try to create a notification
                conversation = conversationMap[conversationID] ?? ZMConversation.fetch(withRemoteIdentifier: conversationID, in: self.syncMOC)
            }
            
            if let messageNonce = event.messageNonce {
                if eventNotifications.notifications.contains(where: { $0.messageNonce == messageNonce }) {
                    // ignore events which we already scheduled a notification for
                    return
                }
            }

            if let receivedMessage = GenericMessage(from: event) {
                
                if receivedMessage.hasReaction,
                   receivedMessage.reaction.emoji.isEmpty,
                   let messageID = UUID(uuidString: receivedMessage.reaction.messageID) {
                    // if it's an "unlike" reaction event, cancel the previous "like" notification for this message
                    eventNotifications.cancelCurrentNotifications(messageNonce: messageID)
                }
                
                if receivedMessage.hasEdited || receivedMessage.hasHidden || receivedMessage.hasDeleted {
                    // Cancel notification for message that was edited, deleted or hidden
                    cancelMessageForEditingMessage(receivedMessage)
                }
            }

            let note = ZMLocalNotification(event: event, conversation: conversation, managedObjectContext: self.syncMOC)
            note.apply(eventNotifications.addObject)
            note.apply(scheduleLocalNotification)
        }
    }
}

// MARK: - Availability behaviour change

extension LocalNotificationDispatcher {
    
    public func notifyAvailabilityBehaviourChangedIfNeeded() {
        let selfUser = ZMUser.selfUser(in: syncMOC)
        var notify = selfUser.needsToNotifyAvailabilityBehaviourChange
        
        guard notify.contains(.notification) else { return }
        
        let note = ZMLocalNotification(availability: selfUser.availability, managedObjectContext: syncMOC)
        note.apply(scheduleLocalNotification)
        notify.remove(.notification)
        selfUser.needsToNotifyAvailabilityBehaviourChange = notify
        syncMOC.enqueueDelayedSave()
    }
    
}

// MARK: - Failed messages

extension LocalNotificationDispatcher {

    /// Informs the user that the message failed to send
    public func didFailToSend(_ message: ZMMessage) {
        if message.visibleInConversation == nil || message.conversation?.conversationType == .self {
            return
        }
        let note = ZMLocalNotification(expiredMessage: message)
        note.apply(scheduleLocalNotification)
        note.apply(failedMessageNotifications.addObject)
    }

    /// Informs the user that a message in a conversation failed to send
    public func didFailToSendMessage(in conversation: ZMConversation) {
        let note = ZMLocalNotification(expiredMessageIn: conversation)
        note.apply(scheduleLocalNotification)
        note.apply(failedMessageNotifications.addObject)
    }
}
