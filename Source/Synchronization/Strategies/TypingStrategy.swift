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

import WireDataModel

public let ZMTypingNotificationName = "ZMTypingNotification"
let IsTypingKey = "isTyping"
let ClearIsTypingKey = "clearIsTyping"

let StatusKey = "status"
let StoppedKey = "stopped"
let StartedKey = "started"

public struct TypingEvent {
    
    let date : Date
    let objectID : NSManagedObjectID
    let isTyping : Bool
    
    static func typingEvent(with objectID: NSManagedObjectID,
                            isTyping:Bool,
                            ifDifferentFrom other: TypingEvent?) -> TypingEvent?
    {
        let date = Date()
        if let other = other, other.isTyping == isTyping && other.objectID.isEqual(objectID) &&
           (fabs(date.timeIntervalSince(other.date)) < (ZMTypingDefaultTimeout / ZMTypingRelativeSendTimeout))
        {
            return nil
        }
        return TypingEvent(date: date, objectID: objectID, isTyping: isTyping)
    }
}


public class TypingStrategy : AbstractRequestStrategy {
    
    fileprivate var typing : ZMTyping!
    fileprivate var conversations : [NSManagedObjectID : Bool] = [:]
    fileprivate var lastSentTypingEvent : TypingEvent?
    fileprivate var tornDown : Bool = false

    @available (*, unavailable)
    override init(withManagedObjectContext moc: NSManagedObjectContext, applicationStatus: ApplicationStatus) {
        fatalError()
    }
    
    public convenience init(applicationStatus: ApplicationStatus, managedObjectContext: NSManagedObjectContext) {
        self.init(applicationStatus: applicationStatus, syncContext: managedObjectContext, uiContext: managedObjectContext.zm_userInterface, typing: nil)
    }
    
    init(applicationStatus: ApplicationStatus, syncContext: NSManagedObjectContext, uiContext: NSManagedObjectContext, typing: ZMTyping?) {
        self.typing = typing ?? ZMTyping(userInterfaceManagedObjectContext: uiContext, syncManagedObjectContext: syncContext)
        super.init(withManagedObjectContext: syncContext, applicationStatus: applicationStatus)
        NotificationCenter.default.addObserver(self, selector: #selector(addConversationForNextRequest), name: Notification.Name(rawValue: ZMTypingNotificationName), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(shouldClearTypingForConversation), name: Notification.Name(rawValue: ZMConversationClearTypingNotificationName), object: nil)
    }
    
    public func tearDown() {
        NotificationCenter.default.removeObserver(self)
        typing.tearDown()
        typing = nil
        tornDown = true
    }
    
    deinit {
        assert(tornDown, "Need to tearDown TypingStrategy")
    }
    
    fileprivate dynamic func addConversationForNextRequest(note : Notification) {
        guard let conversation = note.object as? ZMConversation, conversation.remoteIdentifier != nil
        else { return }
        
        let isTyping = (note.userInfo?[IsTypingKey] as? NSNumber)?.boolValue ?? false
        let clearIsTyping = (note.userInfo?[ClearIsTypingKey] as? NSNumber)?.boolValue ?? false
        
        add(conversation:conversation, isTyping:isTyping, clearIsTyping:clearIsTyping)
    }
    
    fileprivate dynamic func shouldClearTypingForConversation(note: Notification) {
        guard let conversation = note.object as? ZMConversation, conversation.remoteIdentifier != nil
        else { return }
        
        add(conversation:conversation, isTyping: false, clearIsTyping: true)
    }
    
    fileprivate func add(conversation: ZMConversation, isTyping: Bool, clearIsTyping: Bool) {
        guard conversation.remoteIdentifier != nil
        else { return }
        
        managedObjectContext.performGroupedBlock {
            if (clearIsTyping) {
                self.conversations.removeValue(forKey: conversation.objectID)
                self.lastSentTypingEvent = nil
            } else {
                self.conversations[conversation.objectID] = isTyping
                RequestAvailableNotification.notifyNewRequestsAvailable(self)
            }
        }
    }
    
    public override func nextRequestIfAllowed() -> ZMTransportRequest? {
        guard let (convObjectID, isTyping) = conversations.popFirst(),
              let newTypingEvent = TypingEvent.typingEvent(with: convObjectID, isTyping: isTyping, ifDifferentFrom: lastSentTypingEvent),
              let conversation = managedObjectContext.object(with: convObjectID) as? ZMConversation,
              let remoteIdentifier = conversation.remoteIdentifier
        else { return nil }
        
        let path = "/conversations/\(remoteIdentifier.transportString())/typing"
        let payload = [StatusKey: isTyping ? StartedKey : StoppedKey]
        let request = ZMTransportRequest(path: path, method: .methodPOST, payload: payload as ZMTransportData)
        request.setDebugInformationTranscoder(self)
        
        lastSentTypingEvent = newTypingEvent;
        return request
    }
}

extension TypingStrategy : ZMEventConsumer {
    
    public func processEvents(_ events: [ZMUpdateEvent], liveEvents: Bool, prefetchResult: ZMFetchRequestBatchResult?) {
        guard liveEvents else { return }
        
        events.forEach{process(event: $0, conversationsByID: prefetchResult?.conversationsByRemoteIdentifier)}
    }
    
    func process(event: ZMUpdateEvent, conversationsByID: [UUID: ZMConversation]?)  {
        guard event.type == .conversationTyping || event.type == .conversationOtrMessageAdd,
              let userID = event.senderUUID(),
              let conversationID = event.conversationUUID(),
              let user = ZMUser(remoteID: userID, createIfNeeded: true, in: managedObjectContext),
              let conversation = conversationsByID?[conversationID] ?? ZMConversation(remoteID: conversationID, createIfNeeded: true, in: managedObjectContext)
        else { return }
        
        if event.type == .conversationTyping {
            guard let payloadData = event.payload["data"] as? [String: String],
                  let status = payloadData[StatusKey]
            else { return }
            processIsTypingUpdateEvent(for: user, in: conversation, with: status)
        } else if event.type == .conversationOtrMessageAdd {
            processMessageAddEvent(for: user, in: conversation)
        }
    }
    
    func processIsTypingUpdateEvent(for user: ZMUser, in conversation: ZMConversation, with status: String) {
        let startedTyping = (status == StartedKey)
        let stoppedTyping = (status == StoppedKey)
        if (startedTyping || stoppedTyping) {
            typing.setIs(startedTyping, for: user, in: conversation)
        }
    }
    
    func processMessageAddEvent(for user: ZMUser, in conversation: ZMConversation) {
        typing.setIs(false, for: user, in: conversation)
    }
    
}


extension TypingStrategy {
    
    public static func notifyTranscoderThatUser(isTyping: Bool, in conversation: ZMConversation) {
        let userInfo = [IsTypingKey : NSNumber(value:isTyping)]
        NotificationCenter.default.post(name: NSNotification.Name(rawValue:ZMTypingNotificationName), object: conversation, userInfo: userInfo)
    }
    
    public static func clearTranscoderStateForTyping(in conversation: ZMConversation) {
        let userInfo = [ClearIsTypingKey : NSNumber(value: 1)]
        NotificationCenter.default.post(name: NSNotification.Name(rawValue:ZMTypingNotificationName), object: conversation, userInfo: userInfo)
    }
}


