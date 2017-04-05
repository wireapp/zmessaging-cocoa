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
import WireDataModel


public protocol CopyableEventNotification : EventNotification {
    func copyByAddingEvent(_ event: ZMUpdateEvent, conversation: ZMConversation) -> Self?
    func canAddEvent(_ event: ZMUpdateEvent, conversation: ZMConversation) -> Bool
}

extension CopyableEventNotification {
    
    public func canAddEvent(_ event: ZMUpdateEvent, conversation: ZMConversation) -> Bool {
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
        return .callState
    }
    override public var ignoresSilencedState : Bool { return true }
    override var requiresConversation : Bool { return true }
    
    unowned var sessionTracker : SessionTracker
    var session : Session?
    var completedSessions : [SessionTracker] = []
    
    override public func containsIdenticalEvent(_ event: ZMUpdateEvent) -> Bool {
        guard super.containsIdenticalEvent(event) else { return false }
        
        guard let lastSequence = lastEvent?.callingSequence,
              let currentSequence = event.callingSequence,
              lastSequence == currentSequence else {
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
    
    override func canCreateNotification(_ conversation: ZMConversation?) -> Bool {
        if (!super.canCreateNotification(conversation)) { return false }
        let lastEvent = self.lastEvent!
        session = sessionTracker.sessionForEvent(lastEvent)
        if let session = session {
            return shouldCreateNotificationForSession(session)
        }
        return false
    }
    
    func shouldCreateNotificationForSession(_ session: Session) -> Bool {
        switch session.currentState {
        case .incoming, .sessionEnded:
            return true
        case .ongoing, .sessionEndedSelfJoined, .selfUserJoined:
            return false
        }
    }
    
    public func copyByAddingEvent(_ event: ZMUpdateEvent, conversation: ZMConversation) -> ZMLocalNotificationForCallEvent? {
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
        } else if newSession.currentState == .selfUserJoined {
            // cancel previous notifications because self user joined
            cancelNotifications()
            notifications.removeAll()
            shouldBeDiscarded = true
        }
        return nil
    }
    
    
    override func configureAlertBody(_ conversation: ZMConversation?) -> String {
        guard let session = session else {return ""}
        switch (session.currentState) {
        case .incoming:
            let baseString = session.isVideo ? ZMPushStringVideoCallStarts : ZMPushStringCallStarts
            return baseString.localizedString(with: sender, conversation: conversation, count: nil)
        case .sessionEnded:
            let sessions = sessionTracker.missedSessionsFor(conversation!.remoteIdentifier!)
            let missedSessionsInConversation = sessions.count
            
            var sender = ZMUser(remoteID: session.initiatorID, createIfNeeded: false, in: managedObjectContext)
            if conversation!.conversationType == .group {
                let missedSessionsFromSender = sessions.filter{$0.initiatorID == session.initiatorID}.count
                if missedSessionsInConversation != missedSessionsFromSender {
                    sender = nil
                }
            }
            return ZMPushStringCallMissed.localizedString(with: sender, conversation: conversation, count: NSNumber(value: missedSessionsInConversation))
        default :
            return ""
        }
    }
    
    override var soundName : String {
        if let session = session , session.currentState == .incoming {
            return ZMCustomSound.notificationRingingSoundName()
        }
        return super.soundName
    }
    
    override var category : String {
        switch session?.currentState {
        case .some(let state) where state == .incoming:
            return ZMIncomingCallCategory
        case .some(let state) where state == .sessionEnded:
            return ZMMissedCallCategory
        default:
            return ZMConversationCategory
        }
    }
}





