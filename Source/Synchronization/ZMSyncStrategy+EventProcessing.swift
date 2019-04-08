//
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
import WireUtilities

extension ZMSyncStrategy: ZMUpdateEventConsumer {

    @objc(processUpdateEvents:ignoreBuffer:)
    public func process(updateEvents: [ZMUpdateEvent], ignoreBuffer: Bool) {
        if ignoreBuffer || isReadyToProcessEvents {
            consume(updateEvents: updateEvents)
        } else {
            Logging.eventProcessing.info("Buffering \(updateEvents.count) event(s)")
            updateEvents.forEach(eventsBuffer.addUpdateEvent)
        }
    }
    
    @objc(consumeUpdateEvents:)
    public func consume(updateEvents: [ZMUpdateEvent]) {
        eventDecoder.processEvents(updateEvents) { [weak self] (decryptedUpdateEvents) in
            guard let `self` = self else { return }
            
            let date = Date()
            let fetchRequest = prefetchRequest(updateEvents: decryptedUpdateEvents)
            let prefetchResult = syncMOC.executeFetchRequestBatchOrAssert(fetchRequest)
            
            Logging.eventProcessing.info("Consuming: [\n\(decryptedUpdateEvents.map({ "\tevent: \(ZMUpdateEvent.eventTypeString(for: $0.type) ?? "Unknown")" }).joined(separator: "\n"))\n]")
        
            for event in decryptedUpdateEvents {
                for eventConsumer in self.eventConsumers {
                    eventConsumer.processEvents([event], liveEvents: true, prefetchResult: prefetchResult)
                }
                self.eventProcessingTracker?.registerEventProcessed()
            }
            localNotificationDispatcher?.processEvents(decryptedUpdateEvents, liveEvents: true, prefetchResult: nil)
            
            if let messages = fetchRequest.noncesToFetch as? Set<UUID>,
                let conversations = fetchRequest.remoteIdentifiersToFetch as? Set<UUID> {
                let confirmationMessages = ZMConversation.confirmDeliveredMessages(messages, in: conversations, with: syncMOC)
                for message in confirmationMessages {
                    self.applicationStatusDirectory?.deliveryConfirmation.needsToConfirmMessage(message.nonce!)
                }
            }
            
            syncMOC.saveOrRollback()
            
            Logging.eventProcessing.debug("Events processed in \(-date.timeIntervalSinceNow): \(self.eventProcessingTracker?.debugDescription ?? "")")
            
        }
        
    }
    
    @objc(prefetchRequestForUpdateEvents:)
    public func prefetchRequest(updateEvents: [ZMUpdateEvent]) -> ZMFetchRequestBatch {
        var messageNounces: Set<UUID> = Set()
        var conversationNounces: Set<UUID> = Set()
        
     
        for eventConsumer in eventConsumers {
            if let messageNoncesToPrefetch = eventConsumer.messageNoncesToPrefetch?(toProcessEvents: updateEvents)  {
                messageNounces.formUnion(messageNoncesToPrefetch)
            }
            
            if let conversationRemoteIdentifiersToPrefetch = eventConsumer.conversationRemoteIdentifiersToPrefetch?(toProcessEvents: updateEvents) {
                conversationNounces.formUnion(conversationRemoteIdentifiersToPrefetch)
            }
        }
        
        let fetchRequest = ZMFetchRequestBatch()
        fetchRequest.addNonces(toPrefetchMessages: messageNounces)
        fetchRequest.addConversationRemoteIdentifiers(toPrefetchConversations: conversationNounces)
        
        return fetchRequest
    }
    

}

