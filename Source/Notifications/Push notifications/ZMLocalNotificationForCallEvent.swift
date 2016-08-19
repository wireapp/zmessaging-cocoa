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


public class ZMLocalNotificationForCallEvent : ZMLocalNotificationForEvent {
    
    public override var eventType: ZMLocalNotificationForEventType {return .Call }
    override var ignoresSilencedState : Bool { return true }
    override var requiresConversation : Bool { return true }
    override var copiedEventTypes : [ZMUpdateEventType] { return [.CallState] }
    let accedptedCallTypes : [ZMCallEventType] = [.IncomingCall, .IncomingVideoCall, .CallEnded, .SelfUserJoined]
    let callStartedTypes : [ZMCallEventType] = [.IncomingCall, .IncomingVideoCall]

    var currentCallType : ZMCallEventType?
    var callStartedEventsByUser : [NSUUID : Int] = [:]
    var lastSessionIDToSenderID : [String : NSUUID] = [:]
    var lastJoinedSessionID : String?
    let unknownUUID = NSUUID(UUIDString: "cc6515c4-6d3e-48c2-b09d-43a6130c9333")!
    
    override public func containsIdenticalEvent(event: ZMUpdateEvent) -> Bool {
        guard super.containsIdenticalEvent(event) else { return false }
        
        guard let lastSequence = lastEvent?.payload["sequence"] as? Int,
              let currentSequence = event.payload["sequence"] as? Int
            where lastSequence == currentSequence else {
                return false
        }
        
        return true
    }
    
    override func canCreateNotification() -> Bool {
        if (!super.canCreateNotification()) { return false }
        let lastEvent = self.lastEvent!
        let callType = lastEvent.callEventTypeOnManagedObjectContext(managedObjectContext)
        guard accedptedCallTypes.contains(callType) else { return false }
        
        let senderID = sender?.remoteIdentifier ?? unknownUUID
        let sessionID = lastEvent.payload["session"] as? String ?? "unspecified"
        guard shouldAcceptEvent(sessionID, eventType: callType) else { return false }
        
        return configure(callType, sessionID: sessionID, senderID: senderID)
    }
    
    func configure(callType: ZMCallEventType, sessionID: String, senderID: NSUUID) -> Bool {
        switch callType {
            
        case .IncomingCall, .IncomingVideoCall:
            currentCallType = callType
            lastSessionIDToSenderID = [sessionID : senderID]
            callStartedEventsByUser[senderID] = (callStartedEventsByUser[senderID] ?? 0) + 1
            return true
        case .CallEnded:
            if lastJoinedSessionID != nil && lastJoinedSessionID == sessionID {
                return false
            }
            if lastSessionIDToSenderID.count == 0 {
                return false
            }
            if let lastSessionID = lastSessionIDToSenderID.keys.first where lastSessionID != sessionID {
                lastSessionIDToSenderID = [:]
            }
            currentCallType = callType
            return true
        case .SelfUserJoined:
            lastJoinedSessionID = sessionID ?? lastJoinedSessionID
            cancelCallNotifications()
            currentCallType = callType
            return true
            
        default:
            return false
        }

    }
    
    override var shouldCreateNoficiationForLastEvent : Bool {
        if currentCallType == .SelfUserJoined {
            return false
        }
        return true
    }
    
    override func prepareForCopy(note: ZMLocalNotificationForEvent) {
        super.prepareForCopy(note)
        if let note = note as? ZMLocalNotificationForCallEvent {
            lastSessionIDToSenderID = note.lastSessionIDToSenderID
            lastJoinedSessionID     = note.lastJoinedSessionID
            callStartedEventsByUser = note.callStartedEventsByUser
            currentCallType         = note.currentCallType
        }
    }
    
    func shouldAcceptEvent(session: String?, eventType: ZMCallEventType) -> Bool {
        let lastSessionID = lastSessionIDToSenderID.keys.first
        let isSameSession = (lastSessionID != nil) && (lastSessionID == session)
        if isSameSession {
            let isSameEventType = (currentCallType != nil) && (currentCallType == eventType || callStartedTypes.contains(eventType))
            return !isSameEventType
        }
        return true
    }
    
    override func configureAlertBody() -> String {
        switch (currentCallType!) {
        case .IncomingCall:
            return ZMPushStringCallStarts.localizedStringWithUser(sender, conversation: conversation, count: nil)
        case .IncomingVideoCall:
            return ZMPushStringVideoCallStarts.localizedStringWithUser(sender, conversation: conversation, count: nil)
        case .CallEnded:
            var sender : ZMUser?
            if let lastSenderID = lastSessionIDToSenderID.values.first where lastSenderID != unknownUUID {
                sender = ZMUser(remoteID: callStartedEventsByUser.keys.first!, createIfNeeded: false, inContext: managedObjectContext)
            }
            if conversation!.conversationType == .Group {
                if callStartedEventsByUser.count == 1 {
                    let count = callStartedEventsByUser.values.first ?? 1
                    return ZMPushStringCallMissed.localizedStringWithUser(sender, conversation: conversation, count: count)
                }
                let aCount = callStartedEventsByUser.values.reduce(0){$0 + $1}
                return ZMPushStringCallMissed.localizedStringWithUser(nil, conversation:conversation, count: (aCount > 0) ? aCount : 1)
            }
            return ZMPushStringCallMissed.localizedStringWithUser(sender, conversation: conversation, count: callStartedEventsByUser.values.first ?? 1)
        default :
            return ""
        }
    }
    
    override var soundName : String {
        if currentCallType == .IncomingCall || currentCallType == .IncomingVideoCall {
            return ZMLocalNotificationRingingSoundName()
        }
        return super.soundName
    }
    
    override var category : String {
        switch currentCallType! {
        case .IncomingCall, .IncomingVideoCall:
            return ZMIncomingCallCategory
        case .CallEnded:
            return ZMMissedCallCategory
        default:
            return ZMConversationCategory
        }
    }
    
    func cancelCallNotifications() {
        super.cancelNotifications()
        notifications = []
        events = []
        callStartedEventsByUser = [:]
    }
}





