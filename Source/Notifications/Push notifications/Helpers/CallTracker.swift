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


enum CallStateType {
    case Undefined, Incoming, IncomingVideo, Ongoing, SelfUserJoined, Ended
}
extension ZMUpdateEvent {
    
    func callStateType(context: NSManagedObjectContext) -> CallStateType {
        guard type == .CallState,
            let participantInfo = payload["participants"] as? [String : [String : AnyObject]]
            else { return .Undefined}
        
        let selfUser = ZMUser.selfUserInContext(context)
        
        var isSelfUserJoined = false
        var isVideo = false
        var otherCount = 0
        
        participantInfo.forEach{ (remoteID, info) in
            if let videod = info["videod"]?.boolValue  where videod == true {
                isVideo = true
            }
            if let state = info["state"] as? String where state == "joined" {
                if remoteID == selfUser.remoteIdentifier!.transportString() {
                    isSelfUserJoined = true
                } else {
                    otherCount = otherCount+1
                }
            }
        }
        
        switch (isSelfUserJoined, otherCount) {
        case (false, 0):
            return .Ended
        case (false, let count):
            if count == 1 {
                return isVideo ? .IncomingVideo : .Incoming
            }
            return .Ongoing
        case (true, _):
            return .SelfUserJoined
        }
    }
    
    public var callingSessionID : String? {
        guard type == .CallState else {return nil}
        return payload["session"] as? String
    }
    
    public var callingSequence : Int? {
        guard type == .CallState else {return nil}
        return payload["sequence"] as? Int
    }
}

struct Session {
    let sessionID : String
    let initiatorID : NSUUID
    let conversationID : NSUUID
    
    var lastSequence : Int = 0
    var isVideo : Bool = false
    
    init(sessionID: String, conversationID: NSUUID, initiatorID: NSUUID) {
        self.sessionID = sessionID
        self.conversationID = conversationID
        self.initiatorID = initiatorID
    }
    
    var callStarted : Bool = false
    var othersJoined : Bool = false
    var selfUserJoined : Bool = false
    var callEnded : Bool = false
    
    enum State : Int {
        case Incoming, Ongoing, SelfUserJoined, SessionEndedSelfJoined, SessionEnded
    }
    
    var currentState : State {
        switch (callEnded, selfUserJoined) {
        case (true, true):
            return .SessionEndedSelfJoined
        case (true, false):
            return .SessionEnded
        case (false, true):
            return .SelfUserJoined
        case (false, false):
            return othersJoined ? .Ongoing : .Incoming
        }
    }
    
    mutating func changeState(event: ZMUpdateEvent, managedObjectContext: NSManagedObjectContext) -> State {
        guard let sequence = event.callingSequence where sequence >= lastSequence else { return currentState }
        lastSequence = sequence
        let callStateType = event.callStateType(managedObjectContext)
        switch callStateType {
        case .Incoming, .IncomingVideo:
            if callStarted {
                othersJoined = true
            } else {
                callStarted = true
                if callStateType == .IncomingVideo {
                    isVideo = true
                }
            }
        case .Ongoing:
            if callStarted {
                othersJoined = true
            }
            callStarted = true
        case .SelfUserJoined:
            selfUserJoined = true
        case .Ended:
            callEnded = true
        case .Undefined:
            break
        }
        return currentState
    }
}

@objc public class SessionTracker : NSObject {
    
    var sessions : [Session] = []
    
    var joinedSessions : [String] {
        return sessions.filter{$0.selfUserJoined}.map{$0.sessionID}
    }
    
    public func clearSessions(conversation: ZMConversation){
        sessions = sessions.filter{$0.conversationID != conversation.remoteIdentifier}
    }
    
    public func addEvent(event: ZMUpdateEvent, managedObjectContext: NSManagedObjectContext)  {
        guard event.type == .CallState, let sessionID = event.callingSessionID
        else { return }
        
        // If we have an existing session with that ID, we update it
        let sessionsCopy = sessions
        for (index, session) in sessionsCopy.enumerate() {
            guard session.conversationID == event.conversationUUID() else { continue }
            
            var updatedSession = session
            if session.sessionID == sessionID {
                if session.callEnded {
                    return
                }
                updatedSession.changeState(event, managedObjectContext: managedObjectContext)
                sessions.removeAtIndex(index)
                sessions.insert(updatedSession, atIndex: index)
                return
            }
            else if let sequence = event.callingSequence where session.lastSequence < sequence {
                // We have a new sessionID, so the previous call must have ended and we didn't notice
                updatedSession.callEnded = true
                sessions.removeAtIndex(index)
                sessions.insert(updatedSession, atIndex: index)
                // We don't return but break and insert a new session
                break
            }
        }
        
        // If we don't have an existing session with that ID, we insert a new one
        insertNewSession(event, sessionID: sessionID, managedObjectContext:managedObjectContext)
    }
    
    func insertNewSession(event: ZMUpdateEvent, sessionID: String, managedObjectContext: NSManagedObjectContext) {
        var call = Session(sessionID: sessionID, conversationID: event.conversationUUID()!, initiatorID: event.senderUUID()!)
        call.changeState(event, managedObjectContext: managedObjectContext)
        sessions.append(call)
    }
    
    func sessionForEvent(event: ZMUpdateEvent) -> Session? {
        guard let sessionID = event.callingSessionID, let conversationID = event.conversationUUID()  else {return nil}
        return sessions.filter{$0.sessionID == sessionID && $0.conversationID == conversationID}.first
    }
    
    func missedSessionsFor(conversationID: NSUUID) -> [Session] {
        return sessions.filter{$0.currentState == .SessionEnded && $0.conversationID == conversationID}
    }
}


