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

extension NSNotification.Name {
    static let calculateBadgeCount = NSNotification.Name(rawValue: "calculateBadgeCountNotication")
}

@objc
public protocol UpdateEventProcessor: class {
            
    @objc(storeUpdateEvents:ignoreBuffer:)
    func storeUpdateEvents(_ updateEvents: [ZMUpdateEvent], ignoreBuffer: Bool)
    
    @objc(storeAndProcessUpdateEvents:ignoreBuffer:)
    func storeAndProcessUpdateEvents(_ updateEvents: [ZMUpdateEvent], ignoreBuffer: Bool)
}

extension ZMSyncStrategy: UpdateEventProcessor {
         
    /// Process previously received events after finishing the quick sync.
    ///
    /// - Returns: **True** if there are still more events to process
    @objc
    public func processEventsAfterFinishingQuickSync() -> Bool { // TODO jacob shouldn't be public
        processAllEventsInBuffer()
        return processEventsIfReady()
    }
    
    /// Process previously received events after unlocking the database.
    ///
    /// - Returns: **True** if there are still more events to process
    @objc
    public func processEventsAfterUnlockingDatabase() -> Bool { // TODO jacob shouldn't be public
        return processEventsIfReady()
    }
        
    /// Process previously received events if we are ready to process events.
    ///
    /// /// - Returns: **True** if there are still more events to process
    func processEventsIfReady() -> Bool {
        guard isReadyToProcessEvents else {
            return  true
        }
        
        if syncMOC.encryptMessagesAtRest {
            guard let encryptionKeys = syncMOC.encryptionKeys else {
                return true
            }
            
            processStoredUpdateEvents(with: encryptionKeys)
        } else {
            processStoredUpdateEvents()
        }
        
        applyHotFixes()
        
        return false
    }
    
    public func storeUpdateEvents(_ updateEvents: [ZMUpdateEvent], ignoreBuffer: Bool) {
        if ignoreBuffer || isReadyToProcessEvents {
            eventDecoder.decryptAndStoreEvents(updateEvents) { [weak self] (decryptedEvents) in
                guard let `self` = self else { return }
                
                Logging.eventProcessing.info("Consuming events while in background")
                for eventConsumer in self.eventConsumers {
                    eventConsumer.processEventsWhileInBackground?(decryptedEvents)
                }
                self.syncMOC.saveOrRollback()
                NotificationInContext(name: .calculateBadgeCount, context: self.syncMOC.notificationContext).post()
            }
        } else {
            Logging.eventProcessing.info("Buffering \(updateEvents.count) event(s)")
            updateEvents.forEach(eventsBuffer.addUpdateEvent)
        }
    }
    
    public func storeAndProcessUpdateEvents(_ updateEvents: [ZMUpdateEvent], ignoreBuffer: Bool) {
        storeUpdateEvents(updateEvents, ignoreBuffer: ignoreBuffer)
        _ = processEventsIfReady()
    }
        
    private func processStoredUpdateEvents(with encryptionKeys: EncryptionKeys? = nil) {
        eventDecoder.processStoredEvents(with: encryptionKeys) { [weak self] (decryptedUpdateEvents) in
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
            ZMConversation.calculateLastUnreadMessages(in: syncMOC)
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
