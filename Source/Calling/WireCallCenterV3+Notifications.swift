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

@objc
public enum ReceivedVideoState : UInt {
    /// Sender is not sending video
    case stopped
    /// Sender is sending video
    case started
    /// Sender is sending video but currently has a bad connection
    case badConnection
}

@objc
public protocol ReceivedVideoObserver : class {
    
    @objc(callCenterDidChangeReceivedVideoState:user:)
    func callCenterDidChange(receivedVideoState: ReceivedVideoState, user: ZMUser)
    
}

protocol SelfPostingNotification {
    static var notificationName : Notification.Name { get }
}

extension SelfPostingNotification {
    static var userInfoKey : String { return notificationName.rawValue }
    
    func post(in context: NotificationContext) {
        NotificationInContext(name: type(of:self).notificationName, context: context, userInfo: [type(of:self).userInfoKey : self]).post()
    }
}

/// MARK - CBR observer

public protocol ConstantBitRateAudioObserver : class {
    func callCenterDidChange(constantAudioBitRateAudioEnabled: Bool)
}

struct WireCallCenterCBRNotification : SelfPostingNotification {
    static let notificationName = Notification.Name("WireCallCenterCBRNotification")
    
    public let enabled: Bool
}

/// MARK - Call state observer

public protocol WireCallCenterCallStateObserver : class {
    
    /**
     Called when the callState changes in a conversation
 
     - parameter callState: updated state
     - parameter conversation: where the call is ongoing
     - parameter caller: user which initiated the call
     - parameter timestamp: when the call state change occured
     */
    func callCenterDidChange(callState: CallState, conversation: ZMConversation, caller: ZMUser, timestamp: Date?)
}

public struct WireCallCenterCallStateNotification : SelfPostingNotification {
    static let notificationName = Notification.Name("WireCallCenterNotification")
    
    weak var context : NSManagedObjectContext?
    let callState : CallState
    let conversationId : UUID
    let callerId : UUID
    let messageTime : Date?
}

/// MARK - Missed call observer

public protocol WireCallCenterMissedCallObserver : class {
    func callCenterMissedCall(conversation: ZMConversation, caller: ZMUser, timestamp: Date, video: Bool)
}

public struct WireCallCenterMissedCallNotification : SelfPostingNotification {
    static let notificationName = Notification.Name("WireCallCenterMissedCallNotification")
    
    weak var context : NSManagedObjectContext?
    let conversationId : UUID
    let callerId : UUID
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
    public typealias ChangeInfoContent = AVSCallMember
    
    static let notificationName = Notification.Name("VoiceChannelParticipantNotification")
    static let userInfoKey = notificationName.rawValue
    public let setChangeInfo : SetChangeInfo<AVSCallMember>
    let conversationId : UUID
    unowned var callCenter : WireCallCenterV3
    
    init(setChangeInfo: SetChangeInfo<AVSCallMember>, conversationId: UUID, callCenter: WireCallCenterV3) {
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

extension WireCallCenterV3 {
    
    // MARK - Observer
    
    
    /// Register observer of the call center call state. This will inform you when there's an incoming call etc.
    /// Returns a token which needs to be retained as long as the observer should be active.
    public class func addCallStateObserver(observer: WireCallCenterCallStateObserver, userSession: ZMUserSession) -> Any  {
        return addCallStateObserver(observer: observer, context: userSession.managedObjectContext)
    }
    
    /// Register observer of the call center call state in all user sessions.
    /// Returns a token which needs to be retained as long as the observer should be active.
    class func addGlobalCallStateObserver(observer: WireCallCenterCallStateObserver) -> Any  {
        return NotificationInContext.addUnboundedObserver(name: WireCallCenterCallStateNotification.notificationName, context: nil) { [weak observer] (note) in
            if let note = note.userInfo[WireCallCenterCallStateNotification.userInfoKey] as? WireCallCenterCallStateNotification,
               let context = note.context,
               let caller = ZMUser(remoteID: note.callerId, createIfNeeded: false, in: context),
               let conversation = ZMConversation(remoteID: note.conversationId, createIfNeeded: false, in: context) {
                
                observer?.callCenterDidChange(callState: note.callState, conversation: conversation, caller: caller, timestamp: note.messageTime)
            }
        }
    }
    
    /// Register observer of the call center call state. This will inform you when there's an incoming call etc.
    /// Returns a token which needs to be retained as long as the observer should be active.
    internal class func addCallStateObserver(observer: WireCallCenterCallStateObserver, context: NSManagedObjectContext) -> Any  {
        return NotificationInContext.addObserver(name: WireCallCenterCallStateNotification.notificationName, context: context.notificationContext, queue: .main) { [weak observer] note in
            if let note = note.userInfo[WireCallCenterCallStateNotification.userInfoKey] as? WireCallCenterCallStateNotification,
               let caller = ZMUser(remoteID: note.callerId, createIfNeeded: false, in: context),
               let conversation = ZMConversation(remoteID: note.conversationId, createIfNeeded: false, in: context) {
                
                observer?.callCenterDidChange(callState: note.callState, conversation: conversation, caller: caller, timestamp: note.messageTime)
            }
        }
    }
    
    /// Register observer of the call center call state. This will inform you when there's an incoming call etc.
    /// Returns a token which needs to be retained as long as the observer should be active.
    public class func addCallStateObserver(observer: WireCallCenterCallStateObserver, for conversation: ZMConversation, userSession: ZMUserSession) -> Any  {
        return addCallStateObserver(observer: observer, for: conversation, context: userSession.managedObjectContext)
    }
    
    /// Register observer of the call center call state. This will inform you when there's an incoming call etc.
    /// Returns a token which needs to be retained as long as the observer should be active.
    internal class func addCallStateObserver(observer: WireCallCenterCallStateObserver, for conversation: ZMConversation, context: NSManagedObjectContext) -> Any  {
        return NotificationInContext.addObserver(name: WireCallCenterCallStateNotification.notificationName, context: context.notificationContext, queue: .main) { [weak observer] note in
            if let note = note.userInfo[WireCallCenterCallStateNotification.userInfoKey] as? WireCallCenterCallStateNotification,
               let caller = ZMUser(remoteID: note.callerId, createIfNeeded: false, in: context),
                   note.conversationId == conversation.remoteIdentifier {
                
                observer?.callCenterDidChange(callState: note.callState, conversation: conversation, caller: caller, timestamp: note.messageTime)
            }
        }
    }
    
    /// Register observer of missed calls.
    /// Returns a token which needs to be retained as long as the observer should be active.
    public class func addMissedCallObserver(observer: WireCallCenterMissedCallObserver, userSession: ZMUserSession) -> Any  {
        return addMissedCallObserver(observer: observer, context: userSession.managedObjectContext)
    }
    
    /// Register observer of missed calls.
    /// Returns a token which needs to be retained as long as the observer should be active.
    internal class func addMissedCallObserver(observer: WireCallCenterMissedCallObserver, context: NSManagedObjectContext) -> Any  {
        return NotificationInContext.addObserver(name: WireCallCenterMissedCallNotification.notificationName, context: context.notificationContext, queue: .main) { [weak observer] note in
            if let note = note.userInfo[WireCallCenterMissedCallNotification.userInfoKey] as? WireCallCenterMissedCallNotification,
               let caller = ZMUser(remoteID: note.callerId, createIfNeeded: false, in: context),
               let conversation = ZMConversation(remoteID: note.conversationId, createIfNeeded: false, in: context) {
                    
                observer?.callCenterMissedCall(conversation: conversation, caller: caller, timestamp: note.timestamp, video: note.video)
            }
        }
    }
    
    /// Register observer of missed calls for in all user sessions
    /// Returns a token which needs to be retained as long as the observer should be active.
    class func addGlobalMissedCallObserver(observer: WireCallCenterMissedCallObserver) -> Any  {
        return NotificationInContext.addUnboundedObserver(name: WireCallCenterMissedCallNotification.notificationName, context: nil) { [weak observer] note in
            if let note = note.userInfo[WireCallCenterMissedCallNotification.userInfoKey] as? WireCallCenterMissedCallNotification,
               let context = note.context,
               let caller = ZMUser(remoteID: note.callerId, createIfNeeded: false, in: context),
               let conversation = ZMConversation(remoteID: note.conversationId, createIfNeeded: false, in: context) {
                
                observer?.callCenterMissedCall(conversation: conversation, caller: caller, timestamp: note.timestamp, video: note.video)
            }
        }
    }
    
    /// Register observer when constant audio bit rate is enabled/disabled
    /// Returns a token which needs to be retained as long as the observer should be active.
    public class func addConstantBitRateObserver(observer: ConstantBitRateAudioObserver, userSession: ZMUserSession) -> Any {
        return addConstantBitRateObserver(observer: observer, context: userSession.managedObjectContext)
    }
    
    /// Register observer when constant audio bit rate is enabled/disabled
    /// Returns a token which needs to be retained as long as the observer should be active.
    internal class func addConstantBitRateObserver(observer: ConstantBitRateAudioObserver, context: NSManagedObjectContext) -> Any {
        return NotificationInContext.addObserver(name: WireCallCenterCBRNotification.notificationName, context: context.notificationContext, queue: .main) { [weak observer] note in
            if let note = note.userInfo[WireCallCenterCBRNotification.userInfoKey] as? WireCallCenterCBRNotification {
                observer?.callCenterDidChange(constantAudioBitRateAudioEnabled: note.enabled)
            }
        }
    }
    
    /// Add observer of particpants in a voice channel. Returns a token which needs to be retained as long as the observer should be active.
    /// Returns a token which needs to be retained as long as the observer should be active.
    public class func addVoiceChannelParticipantObserver(observer: VoiceChannelParticipantObserver, for conversation: ZMConversation, userSession: ZMUserSession) -> Any {
        return addVoiceChannelParticipantObserver(observer: observer, for: conversation, context: userSession.managedObjectContext)
    }
    
    /// Add observer of particpants in a voice channel. Returns a token which needs to be retained as long as the observer should be active.
    /// Returns a token which needs to be retained as long as the observer should be active.
    internal class func addVoiceChannelParticipantObserver(observer: VoiceChannelParticipantObserver, for conversation: ZMConversation, context: NSManagedObjectContext) -> Any {
        let remoteID = conversation.remoteIdentifier!
        
        return NotificationInContext.addObserver(name: VoiceChannelParticipantNotification.notificationName, context: context.notificationContext, queue: .main) { [weak observer] note in
            guard let note = note.userInfo[VoiceChannelParticipantNotification.userInfoKey] as? VoiceChannelParticipantNotification,
                let strongObserver = observer
            else { return }
            
            if note.conversationId == remoteID {
                strongObserver.voiceChannelParticipantsDidChange(note)
            }
        }
    }
    
    /// Add observer of voice gain. Returns a token which needs to be retained as long as the observer should be active.
    /// Returns a token which needs to be retained as long as the observer should be active.
    public class func addVoiceGainObserver(observer: VoiceGainObserver, for conversation: ZMConversation, userSession: ZMUserSession) -> Any {
        return addVoiceGainObserver(observer: observer, for: conversation, context: userSession.managedObjectContext)
    }
    
    /// Add observer of voice gain. Returns a token which needs to be retained as long as the observer should be active.
    /// Returns a token which needs to be retained as long as the observer should be active.
    internal class func addVoiceGainObserver(observer: VoiceGainObserver, for conversation: ZMConversation, context: NSManagedObjectContext) -> Any {
        return NotificationInContext.addObserver(name: VoiceGainNotification.notificationName, context: context.notificationContext, object: conversation.remoteIdentifier! as NSUUID, queue: .main) { [weak observer] note in
            guard let note = note.userInfo[VoiceGainNotification.userInfoKey] as? VoiceGainNotification,
                let observer = observer,
                let user = ZMUser(remoteID: note.userId, createIfNeeded: false, in: context)
                else { return }
            
            observer.voiceGainDidChange(forParticipant: user, volume: note.volume)
        }
    }
    
}


class VoiceChannelParticipantV3Snapshot {
    
    fileprivate var state : SetSnapshot<AVSCallMember>
    public private(set) var members : OrderedSetState<AVSCallMember>
    
    fileprivate unowned var callCenter : WireCallCenterV3
    fileprivate let conversationId : UUID
    fileprivate let selfUserID : UUID
    
    init(conversationId: UUID, selfUserID: UUID, members: [AVSCallMember]?, callCenter: WireCallCenterV3) {
        self.callCenter = callCenter
        self.conversationId = conversationId
        self.selfUserID = selfUserID
        
        if let unfilteredMembers = members {
            self.members = type(of: self).filteredMembers(unfilteredMembers)
        } else {
            let unfilteredMembers = callCenter.avsWrapper.members(in: conversationId)
            self.members = type(of: self).filteredMembers(unfilteredMembers)
        }
        state = SetSnapshot(set: self.members, moveType: .uiCollectionView)
    }
    
    static func filteredMembers(_ members: [AVSCallMember]) -> OrderedSetState<AVSCallMember> {
        // remove duplicates see: https://wearezeta.atlassian.net/browse/ZIOS-8610
        // When a user joins with two devices, we would have a duplicate entry for this user in the member array returned from AVS
        // For now, we will keep the one with "the highest state", meaning if one entry has `audioEstablished == false` and the other one `audioEstablished == true`, we keep the one with `audioEstablished == true`
        let callMembers = members.reduce([AVSCallMember]()){ (filtered, member) in
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
    
    func callParticipantsChanged(newParticipants: [AVSCallMember]) {
        var updated : Set<AVSCallMember> = Set()
        var newMembers = [AVSCallMember]()
        
        for m in newParticipants {
            if let idx = members.order[m], (members.array[idx].audioEstablished != m.audioEstablished || members.array[idx].videoState != m.videoState) {
                updated.insert(m)
            }
            newMembers.append(m)
        }
        guard newMembers != members.array || updated.count > 0 else { return }
        
        members = type(of:self).filteredMembers(newMembers)
        recalculateSet(updated: updated)
    }
    
    func callParticpantVideoStateChanged(userId: UUID, videoState: VideoState) {
        guard let callMember = members.array.first(where: { $0.remoteId == userId }) else { return }
        
        let updatedCallMember = AVSCallMember(userId: userId, audioEstablished: callMember.audioEstablished, videoState: videoState)
        let updatedCallMembers: [AVSCallMember] = members.array.map({ member in
            if member.remoteId == userId {
                return updatedCallMember
            } else {
                return member
            }
        })
        
        callParticipantsChanged(newParticipants: updatedCallMembers)
    }
    
    func callParticpantAudioEstablished(userId: UUID) {
        guard let callMember = members.array.first(where: { $0.remoteId == userId }) else { return }
        
        let updatedCallMember = AVSCallMember(userId: userId, audioEstablished: true, videoState: callMember.videoState)
        let updatedCallMembers: [AVSCallMember] = members.array.map({ member in
            if member.remoteId == userId {
                return updatedCallMember
            } else {
                return member
            }
        })
        
        callParticipantsChanged(newParticipants: updatedCallMembers)
    }
    
    /// calculate inserts / deletes / moves
    func recalculateSet(updated: Set<AVSCallMember>) {
        guard let newStateUpdate = state.updatedState(updated,
                                                      observedObject: conversationId as NSUUID,
                                                      newSet: members)
        else { return}
        
        state = newStateUpdate.newSnapshot
        VoiceChannelParticipantNotification(setChangeInfo: newStateUpdate.changeInfo, conversationId: self.conversationId, callCenter: callCenter).post()
    }
    
    public func callParticipantState(forUserWith userId: UUID) -> CallParticipantState {
        guard let callMember = members.array.first(where: { $0.remoteId == userId }) else { return .unconnected }
        
        if callMember.audioEstablished {
            return .connected(videoState: callMember.videoState)
        } else {
            return .connecting
        }
    }
}
