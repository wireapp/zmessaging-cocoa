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


/// An object that can generate requests and parse responses related to downloading
/// missing events in conversations
@objc public protocol ConversationEventsRequestEncoder : NSObjectProtocol {

    /// Called when it needs to generate a request to download the conversation events in the given range
    /// - parameter range: the range of events to fetch. It can return a request to fetch a smaller range
    /// if fetching the full range is not possible
    /// - parameter conversation: the conversation
    func requestForFetchingRange(_ range : ZMEventIDRange, conversation: ZMConversation) -> ZMTransportRequest;
}

@objc public protocol DownloadedConversationEventsParser {
    
    /// Called when some events were downloaded
    /// - parameter range: the range of events that were downloaded
    /// - parameter conversation: the conversation to which the events belong
    /// - parameter response: the transport response to parse
    func updateRange(_ range: ZMEventIDRange, conversation: ZMConversation, response: ZMTransportResponse);
}

/// A generator of requests to download missing events in conversations.
@objc public final class IncompleteConversationsDownstreamSync: NSObject, ZMRequestGenerator {
    
    /// Whether it should download the entire history
    public static let DownloadEntireHistory = true
    
    fileprivate weak var requestEncoder : ConversationEventsRequestEncoder?
    
    fileprivate weak var responseParser : DownloadedConversationEventsParser?
    
    fileprivate let conversationsCache : ZMIncompleteConversationsCache
    
    fileprivate let historySynchronizationStatus : HistorySynchronizationStatus
    
    /// Conversations for which we are currently retrieving events from the BE
    fileprivate var conversationsBeingFetched = Set<ZMConversation>()
    
    /// How long to wait between requests to download conversation events that are needed just to have the full history
    fileprivate let lowPriorityRequestsCooldownInterval : TimeInterval
    
    fileprivate let managedObjectContext : NSManagedObjectContext
    
    /// Last time a low priority request was generated
    fileprivate var lastLowPriorityDownloadDate : Date = Date(timeIntervalSince1970: 0) // long, long time ago
    
    /// Returns an IncompleteConversationDownstreamSync that relies on two incomplete conversations caches: one to be synchronized
    /// with high priority, and one to be synchronized slowly, not to interfere with other requests
    /// - parameter lowPriorityRequestsCooldownInterval: How long to wait between requests to download the low priority conversations
    /// - parameter historySynchronizationStatus: will be used
    /// download conversation events that are needed just to have the full history
    public init(requestEncoder: ConversationEventsRequestEncoder,
        responseParser: DownloadedConversationEventsParser,
        conversationsCache: ZMIncompleteConversationsCache,
        historySynchronizationStatus: HistorySynchronizationStatus,
        lowPriorityRequestsCooldownInterval: TimeInterval,
        managedObjectContext:NSManagedObjectContext)
    {
            
        self.requestEncoder = requestEncoder
        self.responseParser = responseParser
        self.conversationsCache = conversationsCache
        self.historySynchronizationStatus = historySynchronizationStatus
        self.lowPriorityRequestsCooldownInterval = lowPriorityRequestsCooldownInterval
        self.managedObjectContext = managedObjectContext
    }
    
    public func nextRequest() -> ZMTransportRequest? {

        guard
            let conversationAndGap = self.nextConversationWithGap(),
            let encoder = self.requestEncoder
        else { return nil }
        
        let request = encoder.requestForFetchingRange(conversationAndGap.gapRange, conversation: conversationAndGap.conversation)
        request.setDebugInformationTranscoder(encoder as! NSObject)
        
        request.add(ZMCompletionHandler(on: self.managedObjectContext, block: { [weak self] in
            guard let strongSelf = self, let parser = strongSelf.responseParser else { return }
            if $0.result != ZMTransportResponseStatus.tryAgainLater {
                parser.updateRange(conversationAndGap.gapRange, conversation: conversationAndGap.conversation, response: $0)
            }
            strongSelf.conversationsBeingFetched.remove(conversationAndGap.conversation)
        }))
        
        self.conversationsBeingFetched.insert(conversationAndGap.conversation)
        return request
    }
    
    /// Finds the next conversation to download and the gap to download
    fileprivate func nextConversationWithGap() -> (conversation: ZMConversation, gapRange: ZMEventIDRange)? {
        
        if let highPriorityGap = self.highPriorityConversationAndGap() {
            return highPriorityGap
        }
        
        if(IncompleteConversationsDownstreamSync.DownloadEntireHistory) {
            let readyToDownloadHistory = self.historySynchronizationStatus.shouldDownloadFullHistory
            let enoughTimeHasPassedForLowPriority = Date().timeIntervalSince(self.lastLowPriorityDownloadDate) > self.lowPriorityRequestsCooldownInterval
            
            if readyToDownloadHistory && enoughTimeHasPassedForLowPriority {
                if let lowPriorityGap = self.lowPriorityConversationAndGap() {
                    self.resetCooldown()
                    return lowPriorityGap
                }
            }
        }
        return nil
    }
    
    fileprivate func resetCooldown() {
        self.lastLowPriorityDownloadDate = Date()
        // This timer is needed to make sure that once the cooldown has passed, a new request is triggered
        DispatchQueue.global(qos: .background).asyncAfter(deadline: DispatchTime.now() + Double(Int64(UInt64(lowPriorityRequestsCooldownInterval) * NSEC_PER_SEC)) / Double(NSEC_PER_SEC)) {
                [weak self] in
                self?.managedObjectContext.performGroupedBlock {
                    ZMOperationLoop.notifyNewRequestsAvailable(self)
                }
            }
    }
    
    /// Finds a conversation in the given cache that is not currently being downloaded and gets the first gap in that conversation
    fileprivate func highPriorityConversationAndGap() -> (conversation: ZMConversation, gapRange: ZMEventIDRange)? {
        if  let firstObject = conversationsCache.incompleteWhitelistedConversations.firstObjectNot(in: self.conversationsBeingFetched),
            let conversation = firstObject as? ZMConversation,
            let gap = conversationsCache.gap(for: conversation) {
            return (conversation, gap)
        }
        return nil
    }
        
     fileprivate func lowPriorityConversationAndGap() -> (conversation: ZMConversation, gapRange: ZMEventIDRange)? {
        if let firstObject = conversationsCache.incompleteNonWhitelistedConversations.firstObjectNot(in: self.conversationsBeingFetched),
            let conversation = firstObject as? ZMConversation,
            let gap = conversationsCache.gap(for: conversation) {
                return (conversation, gap)
        }
        return nil
    }
}
