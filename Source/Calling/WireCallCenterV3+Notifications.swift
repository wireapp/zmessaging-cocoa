//
// Wire
// Copyright (C) 2017 Wire Swiss GmbH
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


protocol SelfPostingNotification {
    static var notificationName : Notification.Name { get }
}

extension SelfPostingNotification {
    static var userInfoKey : String { return notificationName.rawValue }
    
    func post(in context: NotificationContext) {
        NotificationInContext(name: type(of:self).notificationName, context: context, userInfo: [type(of:self).userInfoKey : self]).post()
    }
}



/// MARK - Video call observer

struct WireCallCenterV3VideoNotification : SelfPostingNotification {
    static let notificationName = Notification.Name("WireCallCenterVideoNotification")
    
    let receivedVideoState : ReceivedVideoState
    
    init(receivedVideoState: ReceivedVideoState) {
        self.receivedVideoState = receivedVideoState
    }

}



/// MARK - Call state observer

public protocol WireCallCenterCallStateObserver : class {
    func callCenterDidChange(callState: CallState, conversationId: UUID, userId: UUID?, timeStamp: Date?)
}

public struct WireCallCenterCallStateNotification : SelfPostingNotification {
    static let notificationName = Notification.Name("WireCallCenterNotification")
    
    let callState : CallState
    let conversationId : UUID
    let userId : UUID?
    let messageTime : Date?
}



/// MARK - Missed call observer

public protocol WireCallCenterMissedCallObserver : class {
    func callCenterMissedCall(conversationId: UUID, userId: UUID, timestamp: Date, video: Bool)
}

public struct WireCallCenterMissedCallNotification : SelfPostingNotification {
    static let notificationName = Notification.Name("WireCallCenterMissedCallNotification")
    
    let conversationId : UUID
    let userId : UUID
    let timestamp: Date
    let video: Bool
}



/// MARK - ConferenceParticipantsObserver
protocol WireCallCenterConferenceParticipantsObserver : class {
    func callCenterConferenceParticipantsChanged(conversationId: UUID, userIds: [UUID])
}

struct WireCallCenterConferenceParticipantsChangedNotification : SelfPostingNotification {
    static let notificationName = Notification.Name("WireCallCenterNotification")
    
    let conversationId : UUID
    let userId : UUID
    let timestamp: Date
    let video: Bool
}


/// MARK - VoiceChannelParticipantObserver

@objc
public protocol VoiceChannelParticipantObserver : class {
    func voiceChannelParticipantsDidChange(_ changeInfo : VoiceChannelParticipantNotification)
}


@objc public class VoiceChannelParticipantNotification : NSObject, SetChangeInfoOwner {
    public typealias ChangeInfoContent = CallMember
    
    static let notificationName = Notification.Name("VoiceChannelParticipantNotification")
    static let userInfoKey = notificationName.rawValue
    public let setChangeInfo : SetChangeInfo<CallMember>
    let conversationId : UUID
    unowned var callCenter : WireCallCenterV3
    
    init(setChangeInfo: SetChangeInfo<CallMember>, conversationId: UUID, callCenter: WireCallCenterV3) {
        self.setChangeInfo = setChangeInfo
        self.conversationId = conversationId
        self.callCenter = callCenter
    }
    
    func post() {
        guard let context = callCenter.uiMOC else { return }
        
        NotificationInContext(name: VoiceChannelParticipantNotification.notificationName,
                              context: context.notificationContext,
                              object: nil,
                              userInfo: [VoiceChannelParticipantNotification.userInfoKey : self]).post()
    }
    
    public var orderedSetState : OrderedSetState<ChangeInfoContent> { return setChangeInfo.orderedSetState }
    public var insertedIndexes : IndexSet { return setChangeInfo.insertedIndexes }
    public var deletedIndexes : IndexSet { return setChangeInfo.deletedIndexes }
    public var deletedObjects: Set<AnyHashable> { return setChangeInfo.deletedObjects }
    public var updatedIndexes : IndexSet { return setChangeInfo.updatedIndexes }
    public var movedIndexPairs : [MovedIndex] { return setChangeInfo.movedIndexPairs }
    public var zm_movedIndexPairs : [ZMMovedIndex] { return setChangeInfo.zm_movedIndexPairs }
    public func enumerateMovedIndexes(_ block:@escaping (_ from: Int, _ to : Int) -> Void) {
        setChangeInfo.enumerateMovedIndexes(block)
    }
}

/// MARK - VoiceGainObserver

@objc
public protocol VoiceGainObserver : class {
    func voiceGainDidChange(forParticipant participant: ZMUser, volume: Float)
}

@objc
public class VoiceGainNotification : NSObject  {
    
    public static let notificationName = Notification.Name("VoiceGainNotification")
    public static let userInfoKey = notificationName.rawValue
    
    public let volume : Float
    public let userId : UUID
    public let conversationId : UUID
    
    public init(volume: Float, conversationId: UUID, userId: UUID) {
        self.volume = volume
        self.conversationId = conversationId
        self.userId = userId
        
        super.init()
    }
    
    public func post(in context: NotificationContext, queue: NotificationQueue) {
        NotificationInContext(name: VoiceGainNotification.notificationName, context: context, object: conversationId as NSUUID, userInfo: [VoiceGainNotification.userInfoKey : self]).post(on: queue)
    }
}

/// MARK - CBR observer

public protocol WireCallCenterCBRCallObserver : class {
    func callCenterCallIsCBR()
}

struct WireCallCenterCBRCallNotification : SelfPostingNotification {
    static let notificationName = Notification.Name("WireCallCenterCBRCallNotification")
}


extension WireCallCenterV3 {
    
    // MARK - Observer
    
    /// Register observer of the call center call state. This will inform you when there's an incoming call etc.
    /// Returns a token which needs to be retained as long as the observer should be active.
    public class func addCallStateObserver(observer: WireCallCenterCallStateObserver, context: NSManagedObjectContext) -> Any  {
        return NotificationInContext.addObserver(name: WireCallCenterCallStateNotification.notificationName, context: context.notificationContext, queue: .main) { [weak observer] note in
            if let note = note.userInfo[WireCallCenterCallStateNotification.userInfoKey] as? WireCallCenterCallStateNotification {
                observer?.callCenterDidChange(callState: note.callState, conversationId: note.conversationId, userId: note.userId, timeStamp: note.messageTime)
            }
        }
    }
    
    /// Register observer of missed calls.
    /// Returns a token which needs to be retained as long as the observer should be active.
    public class func addMissedCallObserver(observer: WireCallCenterMissedCallObserver, context: NSManagedObjectContext) -> Any  {
        return NotificationInContext.addObserver(name: WireCallCenterMissedCallNotification.notificationName, context: context.notificationContext, queue: .main) { [weak observer] note in
            if let note = note.userInfo[WireCallCenterMissedCallNotification.userInfoKey] as? WireCallCenterMissedCallNotification {
                observer?.callCenterMissedCall(conversationId: note.conversationId, userId: note.userId, timestamp: note.timestamp, video: note.video)
            }
        }
    }
    
    /// Register observer of the video state. This will inform you when the remote caller starts, stops sending video.
    /// Returns a token which needs to be retained as long as the observer should be active.
    public class func addReceivedVideoObserver(observer: ReceivedVideoObserver, context: NSManagedObjectContext) -> Any {
        return NotificationInContext.addObserver(name: WireCallCenterV3VideoNotification.notificationName, context: context.notificationContext, queue: .main) { [weak observer] note in
            if let note = note.userInfo[WireCallCenterV3VideoNotification.userInfoKey] as? WireCallCenterV3VideoNotification {
                observer?.callCenterDidChange(receivedVideoState: note.receivedVideoState)
            }
        }
    }
    
}


class VoiceChannelParticipantV3Snapshot {
    
    fileprivate var state : SetSnapshot<CallMember>
    public private(set) var members : OrderedSetState<CallMember>
    
    fileprivate unowned var callCenter : WireCallCenterV3
    fileprivate let conversationId : UUID
    fileprivate let selfUserID : UUID
    let initiator : UUID
    
    init(conversationId: UUID, selfUserID: UUID, members: [CallMember]?, initiator: UUID? = nil, callCenter: WireCallCenterV3) {
        self.callCenter = callCenter
        self.conversationId = conversationId
        self.selfUserID = selfUserID
        self.initiator = initiator ?? selfUserID
        
        if let unfilteredMembers = members {
            self.members = type(of: self).filteredMembers(unfilteredMembers)
        } else {
            let unfilteredMembers = callCenter.avsWrapper.members(in: conversationId)
            self.members = type(of: self).filteredMembers(unfilteredMembers)
        }
        state = SetSnapshot(set: self.members, moveType: .uiCollectionView)
    }
    
    static func filteredMembers(_ members: [CallMember]) -> OrderedSetState<CallMember> {
        // remove duplicates see: https://wearezeta.atlassian.net/browse/ZIOS-8610
        // When a user joins with two devices, we would have a duplicate entry for this user in the member array returned from AVS
        // For now, we will keep the one with "the highest state", meaning if one entry has `audioEstablished == false` and the other one `audioEstablished == true`, we keep the one with `audioEstablished == true`
        let callMembers = members.reduce([CallMember]()){ (filtered, member) in
            var newFiltered = filtered
            if let idx = newFiltered.index(of: member) {
                if !newFiltered[idx].audioEstablished && member.audioEstablished {
                    newFiltered[idx] = member
                }
            } else {
                newFiltered.append(member)
            }
            return newFiltered
        }
        
        return callMembers.toOrderedSetState()
    }
    
    func callParticipantsChanged(newParticipants: [CallMember]) {
        var updated : Set<CallMember> = Set()
        var newMembers = [CallMember]()
        
        for m in newParticipants {
            if let idx = members.order[m], members.array[idx].audioEstablished != m.audioEstablished {
                updated.insert(m)
            }
            newMembers.append(m)
        }
        guard newMembers != members.array || updated.count > 0 else { return }
        
        members = type(of:self).filteredMembers(newMembers)
        recalculateSet(updated: updated)
    }
    
    /// calculate inserts / deletes / moves
    func recalculateSet(updated: Set<CallMember>) {
        guard let newStateUpdate = state.updatedState(updated,
                                                      observedObject: conversationId as NSUUID,
                                                      newSet: members)
        else { return}
        
        state = newStateUpdate.newSnapshot
        VoiceChannelParticipantNotification(setChangeInfo: newStateUpdate.changeInfo, conversationId: self.conversationId, callCenter: callCenter).post()
    }
    
    public func connectionState(forUserWith userId: UUID) -> VoiceChannelV2ConnectionState {
        let tempMember = CallMember(userId: userId, audioEstablished: false)
        guard let idx = members.order[tempMember] else {
            return .notConnected
        }
        let member = members.array[idx]
        return member.audioEstablished ? .connected : .connecting
    }
}
