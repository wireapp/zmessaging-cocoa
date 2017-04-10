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
    case undefined, incoming, incomingVideo, ongoing, selfUserJoined, ended
}
extension ZMUpdateEvent {
    
    func callStateType(_ context: NSManagedObjectContext) -> CallStateType {
        guard type == .callState,
            let participantInfo = payload["participants"] as? [String : [String : AnyObject]]
            else { return .undefined}
        
        let selfUser = ZMUser.selfUser(in: context)
        
        var isSelfUserJoined = false
        var isVideo = false
        var otherCount = 0
        
        participantInfo.forEach{ (remoteID, info) in
            if let videod = info["videod"]?.boolValue  , videod == true {
                isVideo = true
            }
            if let state = info["state"] as? String , state == "joined" {
                if remoteID == selfUser.remoteIdentifier!.transportString() {
                    isSelfUserJoined = true
                } else {
                    otherCount = otherCount+1
                }
            }
        }
        
        switch (isSelfUserJoined, otherCount) {
        case (false, 0):
            return .ended
        case (false, let count):
            if count == 1 {
                return isVideo ? .incomingVideo : .incoming
            }
            return .ongoing
        case (true, _):
            return .selfUserJoined
        }
    }
    
    public var callingSessionID : String? {
        guard type == .callState else {return nil}
        return payload["session"] as? String
    }
    
    public var callingSequence : Int? {
        guard type == .callState else {return nil}
        return payload["sequence"] as? Int
    }
}

public final class Session : NSObject, NSCoding, NSCopying {
    let sessionID : String
    let initiatorID : UUID
    let conversationID : UUID
    
    var lastSequence : Int = 0
    var isVideo : Bool = false
    var callStarted : Bool = false
    var othersJoined : Bool = false
    var selfUserJoined : Bool = false
    var callEnded : Bool = false
    
    public init(sessionID: String, conversationID: UUID, initiatorID: UUID) {
        self.sessionID = sessionID
        self.conversationID = conversationID
        self.initiatorID = initiatorID
    }
    
    public enum State : Int {
        case incoming, ongoing, selfUserJoined, sessionEndedSelfJoined, sessionEnded
    }
    public var currentState : State {
        switch (callEnded, selfUserJoined) {
        case (true, true):
            return .sessionEndedSelfJoined
        case (true, false):
            return .sessionEnded
        case (false, true):
            return .selfUserJoined
        case (false, false):
            return othersJoined ? .ongoing : .incoming
        }
    }
    
    public func changeState(_ event: ZMUpdateEvent, managedObjectContext: NSManagedObjectContext) -> State {
        guard let sequence = event.callingSequence , sequence >= lastSequence else { return currentState }
        lastSequence = sequence
        let callStateType = event.callStateType(managedObjectContext)
        switch callStateType {
        case .incoming, .incomingVideo:
            if callStarted {
                othersJoined = true
            } else {
                callStarted = true
                if callStateType == .incomingVideo {
                    isVideo = true
                }
            }
        case .ongoing:
            if callStarted {
                othersJoined = true
            }
            callStarted = true
        case .selfUserJoined:
            selfUserJoined = true
        case .ended:
            callEnded = true
        case .undefined:
            break
        }
        return currentState
    }
    
    open func encode(with aCoder: NSCoder) {
        aCoder.encode(callStarted, forKey: #keyPath(callStarted))
        aCoder.encode(othersJoined, forKey: #keyPath(othersJoined))
        aCoder.encode(selfUserJoined, forKey: #keyPath(selfUserJoined))
        aCoder.encode(callEnded, forKey: #keyPath(callEnded))
        aCoder.encode(isVideo, forKey: #keyPath(isVideo))
        aCoder.encode(lastSequence, forKey: #keyPath(lastSequence))
        aCoder.encode(sessionID, forKey: #keyPath(sessionID))
        aCoder.encode(initiatorID, forKey: #keyPath(initiatorID))
        aCoder.encode(conversationID, forKey: #keyPath(conversationID))
    }
    
    convenience required public init?(coder aDecoder: NSCoder) {
        guard let sessionID = aDecoder.decodeObject(forKey: #keyPath(sessionID)) as? String,
            let initiatorID = aDecoder.decodeObject(forKey: #keyPath(initiatorID)) as? UUID,
            let conversationID = aDecoder.decodeObject(forKey: #keyPath(conversationID)) as? UUID else {return nil}
        
        self.init(sessionID: sessionID, conversationID: conversationID, initiatorID: initiatorID)
        self.callStarted = aDecoder.decodeBool(forKey: #keyPath(callStarted))
        self.othersJoined = aDecoder.decodeBool(forKey: #keyPath(othersJoined))
        self.selfUserJoined = aDecoder.decodeBool(forKey: #keyPath(selfUserJoined))
        self.callEnded = aDecoder.decodeBool(forKey: #keyPath(callEnded))
        self.isVideo = aDecoder.decodeBool(forKey: #keyPath(isVideo))
        self.lastSequence = aDecoder.decodeInteger(forKey: #keyPath(lastSequence))
    }
    
    open func copy(with zone: NSZone?) -> Any {
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

@objc public final class SessionTracker : NSObject {
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
    
    public func clearSessions(_ conversation: ZMConversation){
        sessions = sessions.filter{$0.conversationID != conversation.remoteIdentifier}
    }
    
    /// unarchives previous calls that haven't been cancelled yet
    func unarchiveOldSessions(){
        guard let archive = managedObjectContext.persistentStoreMetadata(forKey: SessionTracker.ArchivingKey) as? Data else { return }
        let unarchiver = NSKeyedUnarchiver(forReadingWith: archive)
        
        // NSCoding prefixes classes with module name, after project rename so to unarchive 
        // "old" data we need to explicitly specify the class through delegate method
        unarchiver.delegate = self
        if let archivedSessions = unarchiver.decodeObject(forKey: NSKeyedArchiveRootObjectKey) as? [Session] {
            self.sessions = archivedSessions
        }
    }
    
    /// Archives sessions
    func updateArchive(){
        let data = NSKeyedArchiver.archivedData(withRootObject: sessions)
        managedObjectContext.setPersistentStoreMetadata(data, key: SessionTracker.ArchivingKey)
        managedObjectContext.saveOrRollback() // we need to save otherwiese changes might not be stored
    }
    
    public func addEvent(_ event: ZMUpdateEvent)  {
        guard event.type == .callState, let sessionID = event.callingSessionID
        else { return }
        
        // If we have an existing session with that ID, we update it
        for session in sessions {
            guard session.conversationID == event.conversationUUID() else { continue }
            if session.sessionID == sessionID {
                if session.callEnded {
                    return
                }
                _ = session.changeState(event, managedObjectContext: managedObjectContext)
                return
            }
            else if let sequence = event.callingSequence , session.lastSequence < sequence {
                // We have a new sessionID, so the previous call must have ended and we didn't notice
                session.callEnded = true
                // We don't return but break and insert a new session
                break
            }
        }
        
        // If we don't have an existing session with that ID, we insert a new one
        insertNewSession(event, sessionID: sessionID, managedObjectContext:managedObjectContext)
    }
    
    func insertNewSession(_ event: ZMUpdateEvent, sessionID: String, managedObjectContext: NSManagedObjectContext) {
        let call = Session(sessionID: sessionID, conversationID: event.conversationUUID()!, initiatorID: event.senderUUID()!)
        _ = call.changeState(event, managedObjectContext: managedObjectContext)
        sessions.append(call)
    }
    
    func sessionForEvent(_ event: ZMUpdateEvent) -> Session? {
        guard let sessionID = event.callingSessionID, let conversationID = event.conversationUUID()  else {return nil}
        return (sessions.filter{$0.sessionID == sessionID && $0.conversationID == conversationID}.first)?.copy() as? Session
    }
    
    func missedSessionsFor(_ conversationID: UUID) -> [Session] {
        return sessions.filter{$0.currentState == .sessionEnded && $0.conversationID == conversationID}
    }
}

extension SessionTracker: NSKeyedUnarchiverDelegate {
    public func unarchiver(_ unarchiver: NSKeyedUnarchiver, cannotDecodeObjectOfClassName name: String, originalClasses classNames: [String]) -> Swift.AnyClass? {
        // If we encounter unknown class it was probably archived when `WireSyncEngine` was called `zmessaging` and full class name doesn't match
        return Session.self
    }
}
