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

public class Session : NSObject, NSCoding, NSCopying {
    let sessionID : String
    let initiatorID : NSUUID
    let conversationID : NSUUID
    
    var lastSequence : Int = 0
    var isVideo : Bool = false
    var callStarted : Bool = false
    var othersJoined : Bool = false
    var selfUserJoined : Bool = false
    var callEnded : Bool = false
    
    public init(sessionID: String, conversationID: NSUUID, initiatorID: NSUUID) {
        self.sessionID = sessionID
        self.conversationID = conversationID
        self.initiatorID = initiatorID
    }
    
    public enum State : Int {
        case Incoming, Ongoing, SelfUserJoined, SessionEndedSelfJoined, SessionEnded
    }
    public var currentState : State {
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
    
    public func changeState(event: ZMUpdateEvent, managedObjectContext: NSManagedObjectContext) -> State {
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
    
    public func encodeWithCoder(aCoder: NSCoder) {
        aCoder.encodeBool(callStarted, forKey: "callStarted")
        aCoder.encodeBool(othersJoined, forKey: "othersJoined")
        aCoder.encodeBool(selfUserJoined, forKey: "selfUserJoined")
        aCoder.encodeBool(callEnded, forKey: "callEnded")
        aCoder.encodeBool(isVideo, forKey: "isVideo")
        aCoder.encodeInteger(lastSequence, forKey: "lastSequence")
        aCoder.encodeObject(sessionID, forKey: "sessionID")
        aCoder.encodeObject(initiatorID, forKey: "iniatorID")
        aCoder.encodeObject(conversationID, forKey: "conversationID")
    }
    
    convenience required public init?(coder aDecoder: NSCoder) {
        guard let sessionID = aDecoder.decodeObjectForKey("sessionID") as? String,
        let initiatorID = aDecoder.decodeObjectForKey("initiatorID") as? NSUUID,
        let conversationID = aDecoder.decodeObjectForKey("conversationID") as? NSUUID else {return nil}
        
        self.init(sessionID: sessionID, conversationID: conversationID, initiatorID: initiatorID)
        self.callStarted = aDecoder.decodeBoolForKey("callStarted")
        self.othersJoined = aDecoder.decodeBoolForKey("othersJoined")
        self.selfUserJoined = aDecoder.decodeBoolForKey("selfUserJoined")
        self.callEnded = aDecoder.decodeBoolForKey("callEnded")
        self.isVideo = aDecoder.decodeBoolForKey("isVideo")
        self.lastSequence = aDecoder.decodeIntegerForKey("lastSequence")
    }
    
    public func copyWithZone(zone: NSZone) -> AnyObject {
        let copy = Session(sessionID: sessionID, conversationID: conversationID, initiatorID: initiatorID)
        copy.callStarted = callStarted
        copy.othersJoined = othersJoined
        copy.selfUserJoined = selfUserJoined
        copy.callEnded = callEnded
        copy.isVideo = isVideo
        copy.lastSequence = lastSequence
        return copy
    }
}

@objc public class SessionTracker : NSObject {
    static let ArchivingKey = "SessionTracker"
    let managedObjectContext: NSManagedObjectContext

    var sessions : [Session] = [] {
        didSet {
            updateArchive()
        }
    }
    
    var joinedSessions : [String] {
        return sessions.filter{$0.selfUserJoined}.map{$0.sessionID}
    }
    
    public init(managedObjectContext: NSManagedObjectContext) {
        self.managedObjectContext = managedObjectContext
        super.init()
        unarchiveOldSessions()
    }
    
    public func tearDown(){
        sessions = []
        managedObjectContext.saveOrRollback()
    }
    
    public func clearSessions(conversation: ZMConversation){
        sessions = sessions.filter{$0.conversationID != conversation.remoteIdentifier}
    }
    
    /// unarchives previous calls that haven't been cancelled yet
    func unarchiveOldSessions(){
        guard let archive = managedObjectContext.valueForKey(SessionTracker.ArchivingKey) as? NSData,
            let archivedSessions =  NSKeyedUnarchiver.unarchiveObjectWithData(archive) as? [Session]
            else { return }
        self.sessions = archivedSessions
    }
    
    /// Archives sessions
    func updateArchive(){
        let data = NSKeyedArchiver.archivedDataWithRootObject(sessions)
        managedObjectContext.setValue(data, forKey: SessionTracker.ArchivingKey)
        managedObjectContext.saveOrRollback() // we need to save otherwiese changes might not be stored
    }
    
    public func addEvent(event: ZMUpdateEvent)  {
        guard event.type == .CallState, let sessionID = event.callingSessionID
        else { return }
        
        // If we have an existing session with that ID, we update it
        for session in sessions {
            guard session.conversationID == event.conversationUUID() else { continue }
            if session.sessionID == sessionID {
                if session.callEnded {
                    return
                }
                session.changeState(event, managedObjectContext: managedObjectContext)
                return
            }
            else if let sequence = event.callingSequence where session.lastSequence < sequence {
                // We have a new sessionID, so the previous call must have ended and we didn't notice
                session.callEnded = true
                // We don't return but break and insert a new session
                break
            }
        }
        
        // If we don't have an existing session with that ID, we insert a new one
        insertNewSession(event, sessionID: sessionID, managedObjectContext:managedObjectContext)
    }
    
    func insertNewSession(event: ZMUpdateEvent, sessionID: String, managedObjectContext: NSManagedObjectContext) {
        let call = Session(sessionID: sessionID, conversationID: event.conversationUUID()!, initiatorID: event.senderUUID()!)
        call.changeState(event, managedObjectContext: managedObjectContext)
        sessions.append(call)
    }
    
    func sessionForEvent(event: ZMUpdateEvent) -> Session? {
        guard let sessionID = event.callingSessionID, let conversationID = event.conversationUUID()  else {return nil}
        return (sessions.filter{$0.sessionID == sessionID && $0.conversationID == conversationID}.first)?.copy() as? Session
    }
    
    func missedSessionsFor(conversationID: NSUUID) -> [Session] {
        return sessions.filter{$0.currentState == .SessionEnded && $0.conversationID == conversationID}
    }
}


