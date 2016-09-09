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
import ZMCDataModel


public protocol CopyableEventNotification : EventNotification {
    func copyByAddingEvent(event: ZMUpdateEvent, conversation: ZMConversation) -> Self?
    func canAddEvent(event: ZMUpdateEvent, conversation: ZMConversation) -> Bool
}

extension CopyableEventNotification {
    
    public func canAddEvent(event: ZMUpdateEvent, conversation: ZMConversation) -> Bool {
        guard eventType == event.type &&
            conversationID == conversation.remoteIdentifier && (!conversation.isSilenced || ignoresSilencedState)
            else {
                return false
        }
        return true
    }
}


final public class ZMLocalNotificationForCallEvent : ZMLocalNotificationForEvent, CopyableEventNotification {
    
    public override var eventType : ZMUpdateEventType {
        return .CallState
    }
    override public var ignoresSilencedState : Bool { return true }
    override var requiresConversation : Bool { return true }
    
    unowned var sessionTracker : SessionTracker
    var session : Session?
    var completedSessions : [SessionTracker] = []
    
    override public func containsIdenticalEvent(event: ZMUpdateEvent) -> Bool {
        guard super.containsIdenticalEvent(event) else { return false }
        
        guard let lastSequence = lastEvent?.callingSequence,
              let currentSequence = event.callingSequence
            where lastSequence == currentSequence else {
                return false
        }
        
        return true
    }
    
    public init?(events: [ZMUpdateEvent], conversation: ZMConversation?, managedObjectContext: NSManagedObjectContext, application: Application?, sessionTracker: SessionTracker) {
        self.sessionTracker = sessionTracker
        super.init(events: events, conversation: conversation, managedObjectContext: managedObjectContext, application: application)
    }
    
    required public init?(events: [ZMUpdateEvent], conversation: ZMConversation?, managedObjectContext: NSManagedObjectContext, application: Application?) {
        fatalError("init(events:conversation:managedObjectContext:application:) has not been implemented")
    }
    
    override func canCreateNotification(conversation: ZMConversation?) -> Bool {
        if (!super.canCreateNotification(conversation)) { return false }
        let lastEvent = self.lastEvent!
        session = sessionTracker.sessionForEvent(lastEvent)
        if let session = session {
            return shouldCreateNotificationForSession(session)
        }
        return false
    }
    
    func shouldCreateNotificationForSession(session: Session) -> Bool {
        switch session.currentState {
        case .Incoming, .SessionEnded:
            return true
        case .Ongoing, .SessionEndedSelfJoined, .SelfUserJoined:
            return false
        }
    }
    
    public func copyByAddingEvent(event: ZMUpdateEvent, conversation: ZMConversation) -> ZMLocalNotificationForCallEvent? {
        guard canAddEvent(event, conversation: conversation) &&
              super.canCreateNotification(conversation),
              let newSession = sessionTracker.sessionForEvent(event)
        else {return nil}
        
        if shouldCreateNotificationForSession(newSession) {
            // make sure we are not creating two notifications for the same event
            if session!.currentState == newSession.currentState && session!.sessionID == newSession.sessionID {
                return nil
            }
            // cancel previous notifications
            cancelNotifications()
            notifications.removeAll()
            
            // create new notification for session
            events.append(event)
            session = newSession
            let uiNote = configureNotification(conversation)
            notifications.append(uiNote)
            return self
        } else if newSession.currentState == .SelfUserJoined {
            // cancel previous notifications because self user joined
            cancelNotifications()
            notifications.removeAll()
            shouldBeDiscarded = true
        }
        return nil
    }
    
    
    override func configureAlertBody(conversation: ZMConversation?) -> String {
        guard let session = session else {return ""}
        switch (session.currentState) {
        case .Incoming:
            let baseString = session.isVideo ? ZMPushStringVideoCallStarts : ZMPushStringCallStarts
            return baseString.localizedStringWithUser(sender, conversation: conversation, count: nil)
        case .SessionEnded:
            let sessions = sessionTracker.missedSessionsFor(conversation!.remoteIdentifier)
            let missedSessionsInConversation = sessions.count
            
            var sender = ZMUser(remoteID: session.initiatorID, createIfNeeded: false, inContext: managedObjectContext)
            if conversation!.conversationType == .Group {
                let missedSessionsFromSender = sessions.filter{$0.initiatorID == session.initiatorID}.count
                if missedSessionsInConversation != missedSessionsFromSender {
                    sender = nil
                }
            }
            return ZMPushStringCallMissed.localizedStringWithUser(sender, conversation: conversation, count: missedSessionsInConversation)
        default :
            return ""
        }
    }
    
    override var soundName : String {
        if let session = session where session.currentState == .Incoming {
            return ZMLocalNotificationRingingSoundName()
        }
        return super.soundName
    }
    
    override var category : String {
        switch session?.currentState {
        case .Some(let state) where state == .Incoming:
            return ZMIncomingCallCategory
        case .Some(let state) where state == .SessionEnded:
            return ZMMissedCallCategory
        default:
            return ZMConversationCategory
        }
    }
}





