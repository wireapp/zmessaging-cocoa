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
import ZMUtilities
import avs

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
    
    public var notification : Notification {
        return Notification(name: VoiceGainNotification.notificationName,
                            object: self.conversationId as NSUUID,
                            userInfo: [VoiceGainNotification.userInfoKey : self])
    }
    
    public func post() {
        NotificationCenter.default.post(notification)
    }
}

@objc
public class CallEndedNotification : NSObject {
    
    public static let notificationName = Notification.Name("CallEndedNotification")
    public static let userInfoKey = notificationName.rawValue
    
    public let reason : VoiceChannelV2CallEndReason
    public let conversationId : UUID
    
    public init(reason: VoiceChannelV2CallEndReason, conversationId: UUID) {
        self.reason = reason
        self.conversationId = conversationId
        
        super.init()
    }
    
    public func post() {
        NotificationCenter.default.post(name: CallEndedNotification.notificationName,
                                        object: nil,
                                        userInfo: [CallEndedNotification.userInfoKey : self])
    }
    
}

@objc
public protocol WireCallCenterV2CallStateObserver : class {
    
    @objc(callCenterDidChangeVoiceChannelState:conversation:)
    func callCenterDidChange(voiceChannelState: VoiceChannelV2State, conversation: ZMConversation)
}

@objc
public protocol VoiceChannelParticipantObserver : class {
    
    func voiceChannelParticipantsDidChange(_ changeInfo : SetChangeInfo)
    
}

@objc
public protocol VoiceGainObserver : class {
    
    func voiceGainDidChange(forParticipant participant: ZMUser, volume: Float)
    
}

struct VoiceChannelStateNotification {
    
    static let notificationName = Notification.Name("VoiceChannelStateNotification")
    static let userInfoKey = notificationName.rawValue
    
    let voiceChannelState : VoiceChannelV2State
    let conversationId : NSManagedObjectID
    
    func post() {
        NotificationCenter.default.post(name: VoiceChannelStateNotification.notificationName,
                                        object: nil,
                                        userInfo: [VoiceChannelStateNotification.userInfoKey : self])
    }
}

class VoiceGainObserverToken : NSObject {
    
    fileprivate let context : NSManagedObjectContext
    fileprivate weak var observer : VoiceGainObserver?
    fileprivate var token : NSObjectProtocol?
    
    deinit {
        if let token = token {
            NotificationCenter.default.removeObserver(token)
        }
    }
    
    init (context: NSManagedObjectContext, conversationId: UUID, observer: VoiceGainObserver) {
        self.context = context
        self.observer = observer
        
        super.init()
        
        token = NotificationCenter.default.addObserver(forName: VoiceGainNotification.notificationName, object: conversationId as NSUUID, queue: .main) { [weak self] (note) in
            guard let `self` = self,
                  let note = note.userInfo?[VoiceGainNotification.userInfoKey] as? VoiceGainNotification,
                  let user = ZMUser(remoteID: note.userId, createIfNeeded: false, in: context)
            else { return }
            
            self.context.performGroupedBlock {
                self.observer?.voiceGainDidChange(forParticipant: user, volume: note.volume)
            }
        }
    }
    
}


class VoiceChannelParticipantsObserverToken : NSObject {
    
    fileprivate var state : SetSnapshot
    fileprivate var activeFlowParticipantsState : NSOrderedSet
    
    fileprivate let context : NSManagedObjectContext
    fileprivate let conversation : ZMConversation
    fileprivate weak var observer : VoiceChannelParticipantObserver?
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    init(context: NSManagedObjectContext, conversation: ZMConversation, observer : VoiceChannelParticipantObserver) {
        self.context = context
        self.conversation = conversation
        self.observer = observer
        
        state = SetSnapshot(set: conversation.voiceChannelRouter!.v2.participants, moveType: .uiCollectionView)
        activeFlowParticipantsState = conversation.activeFlowParticipants.copy() as! NSOrderedSet
        
        super.init()
        
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(managedObjectContextDidChange(note:)),
                                               name: Notification.Name.NSManagedObjectContextObjectsDidChange, object: context)
        
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(callStateDidChange(note:)),
                                               name: WireCallCenterV2.CallStateDidChangeNotification, object: nil)
    }
    
    @objc
    func managedObjectContextDidChange(note: Notification) {
        let changes = ManagedObjectChanges(note: note)
        
        if changes.updated.contains(conversation) {
            let changedKeys = Set(conversation.changedValuesForCurrentEvent().keys)
            if changedKeys.contains("callParticipants") || changedKeys.isEmpty {
                recalculateSet()
            }
        }
    }
    
    @objc
    func callStateDidChange(note: Notification) {
        if let conversations = note.userInfo?["updated"] as? Set<ZMConversation>, conversations.contains(conversation), conversations.contains(conversation) {
            recalculateSet()
        }
    }
    
    func recalculateSet() {
        let newParticipants = conversation.voiceChannel!.participants
        let newFlowParticipants = conversation.activeFlowParticipants
        
        // participants who have an updated flow, but are still in the voiceChannel
        let newConnected = newFlowParticipants.subtracting(orderedSet: activeFlowParticipantsState)
        let newDisconnected = activeFlowParticipantsState.subtracting(orderedSet: newFlowParticipants)
        
        // participants who left the voiceChannel / call
        let addedUsers = newParticipants.subtracting(orderedSet: state.set)
        let removedUsers = state.set.subtracting(orderedSet: newParticipants)
        
        let updated = newConnected.adding(orderedSet: newDisconnected)
            .subtracting(orderedSet: removedUsers)
            .subtracting(orderedSet: addedUsers)
        
        // calculate inserts / deletes / moves
        if let newStateUpdate = state.updatedState(updated, observedObject: conversation, newSet: newParticipants) {
            state = newStateUpdate.newSnapshot
            activeFlowParticipantsState = (conversation.activeFlowParticipants.copy() as? NSOrderedSet) ?? NSOrderedSet()
            
            let changeInfo = newStateUpdate.changeInfo
            
            observer?.voiceChannelParticipantsDidChange(changeInfo)
        }
    }
    
}

class WireCallCenterV2ReceivedVideoObserverToken : NSObject {
    
    fileprivate let conversation : ZMConversation
    fileprivate let context: NSManagedObjectContext
    fileprivate weak var observer : ReceivedVideoObserver?
    
    /// remote side has the intent to send video
    fileprivate var isVideoEnabled = false
    // remote side does send video
    fileprivate var isVideoStarted = true
    // remote side has a bad connection
    fileprivate var isBadConnection = false
    
    fileprivate var previousState : ReceivedVideoState = .stopped
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    init(context: NSManagedObjectContext, conversation: ZMConversation, observer: ReceivedVideoObserver) {
        self.context = context
        self.conversation = conversation
        self.observer = observer
        
        super.init()
        
        NotificationCenter.default.addObserver(self, selector: #selector(callStateDidChange(note:)), name: WireCallCenterV2.CallStateDidChangeNotification, object: nil)
        
        NotificationCenter.default.addObserver(self, selector: #selector(flowManagerDidChangeReceivedVideoState(note:)), name: NSNotification.Name(rawValue: FlowManagerVideoReceiveStateNotification), object: nil)
    }
    
    func flowManagerDidChangeReceivedVideoState(note: Notification) {
        context.performGroupedBlock { [weak self] in
            guard let `self` = self else { return }
            if let changeInfo = note.object as? AVSVideoStateChangeInfo {
                self.isVideoStarted = changeInfo.state == .FLOWMANAGER_VIDEO_RECEIVE_STARTED
                self.isBadConnection = changeInfo.reason == .FLOWMANAGER_VIDEO_BAD_CONNECTION
                self.notifyObserverIfStateChanged()
            }
        }
    }
    
    func callStateDidChange(note: Notification) {
        if let conversations = note.userInfo?["updated"] as? Set<ZMConversation>, conversations.contains(conversation) {
            isVideoEnabled = !conversation.otherActiveVideoCallParticipants.isEmpty
            notifyObserverIfStateChanged()
        }
    }
    
    var state : ReceivedVideoState {
        
        if !isVideoEnabled {
            return .stopped
        }
        
        if isBadConnection {
            return .badConnection
        }
        
        return isVideoStarted ? .started : .stopped
    }
    
    func notifyObserverIfStateChanged() {
        let newState = state
        
        if newState != previousState {
            previousState = newState
            self.observer?.callCenterDidChange(receivedVideoState: newState)
        }
    }
    
}

class NotificationCenterObserverToken : NSObject {
    
    var token : AnyObject?
    
    deinit {
        if let token = token {
            NotificationCenter.default.removeObserver(token)
        }
    }
    
    init(name: NSNotification.Name, object: AnyObject?, queue: OperationQueue?, block: @escaping (_ note: Notification) -> Void) {
        token = NotificationCenter.default.addObserver(forName: name, object: object, queue: queue, using: block)
    }
    
}


@objc
public class WireCallCenterV2 : NSObject {
    
    @objc
    public static let CallStateDidChangeNotification = Notification.Name("CallStateDidChangeNotification")
    
    let context : NSManagedObjectContext
    var voiceChannelStates : [ZMConversation : VoiceChannelV2State] = [:]

    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    public init(context: NSManagedObjectContext) {
        self.context = context
        
        super.init()
        
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(managedObjectContextDidChange(note:)),
                                               name: Notification.Name.NSManagedObjectContextObjectsDidChange, object: context)
        
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(callStateDidChange(note:)),
                                               name: WireCallCenterV2.CallStateDidChangeNotification,
                                               object: nil)
        
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(applicationDidBecomeActive(note:)),
                                               name: Notification.Name.UIApplicationDidBecomeActive,
                                               object: nil)
    }
    
    /// Add observer of the state of all voice channels. Returns a token which needs to be retained as long as the observer should be active.
    public class func addVoiceChannelStateObserver(observer: WireCallCenterV2CallStateObserver, context: NSManagedObjectContext) -> WireCallCenterObserverToken {
        return NotificationCenterObserverToken(name: VoiceChannelStateNotification.notificationName, object: nil, queue: .main) { [weak observer] (note) in
            if let note = note.userInfo?[VoiceChannelStateNotification.userInfoKey] as? VoiceChannelStateNotification {
                context.performGroupedBlock {
                    guard let conv = (try? context.existingObject(with: note.conversationId)) as? ZMConversation else { return }
                    observer?.callCenterDidChange(voiceChannelState: note.voiceChannelState, conversation: conv)
                }
                
            }
        }
    }
    
    /// Add observer of particpants in a voice channel. Returns a token which needs to be retained as long as the observer should be active.
    public class func addVoiceChannelParticipantObserver(observer: VoiceChannelParticipantObserver, forConversation conversation: ZMConversation, context: NSManagedObjectContext) -> WireCallCenterObserverToken {
        return VoiceChannelParticipantsObserverToken(context: context, conversation: conversation, observer: observer)
    }
    
    /// Add observer of voice gain. Returns a token which needs to be retained as long as the observer should be active.
    public class func addVoiceGainObserver(observer: VoiceGainObserver, forConversation conversation: ZMConversation, context: NSManagedObjectContext) -> WireCallCenterObserverToken {
        return VoiceGainObserverToken(context: context, conversationId: conversation.remoteIdentifier!, observer: observer)
    }
    
    /// Add observer of received video. Returns a token which needs to be retained as long as the observer should be active.
    public class func addReceivedVideoObserver(observer: ReceivedVideoObserver, forConversation conversation: ZMConversation, context: NSManagedObjectContext) -> WireCallCenterObserverToken {
        return WireCallCenterV2ReceivedVideoObserverToken(context: context, conversation: conversation, observer: observer)
    }
    
    public class func removeObserver(token: WireCallCenterObserverToken) {
        NotificationCenter.default.removeObserver(token)
    }
    
    @objc
    func managedObjectContextDidChange(note: Notification) {
        
        let changes = ManagedObjectChanges(note: note)
        
        for object in changes.updated {
            
            let observedKeys = ["callParticipants", "voiceChannel"]
            
            if let conversation = object as? ZMConversation {
                    let changedKeys = Set(conversation.changedValuesForCurrentEvent().keys)
                    if !changedKeys.isDisjoint(with: observedKeys) || changedKeys.isEmpty {
                        updateVoiceChannelState(forConversation: conversation)
                    }
            }
        }
    }
    
    @objc
    func callStateDidChange(note: Notification) {
        if let conversations = note.userInfo?["updated"] as? Set<ZMConversation> {
            for conversation in conversations {
                updateVoiceChannelState(forConversation: conversation)
            }
        }
    }
    
    func checkCallState() {
        for (objectId, callState) in context.zm_callState {
            if callState.hasChanges {
                if let conversation = context.object(with: objectId) as? ZMConversation {
                    updateVoiceChannelState(forConversation: conversation)
                }
            }
        }
    }
    
    func updateVoiceChannelState(forConversation conversation: ZMConversation) {
        let newState = conversation.voiceChannelRouter?.v2.state ?? VoiceChannelV2State.invalid
        let previousState = voiceChannelStates[conversation] ?? VoiceChannelV2State.noActiveUsers
        
        if newState != previousState {
            voiceChannelStates[conversation] = newState
            VoiceChannelStateNotification(voiceChannelState: newState, conversationId: conversation.objectID).post()
        }
    }
    
    func conversations(withVoiceChannelStates expectedStates: [VoiceChannelV2State]) -> [ZMConversation] {
        return voiceChannelStates.flatMap { (conversation: ZMConversation, state: VoiceChannelV2State) -> ZMConversation? in
            return expectedStates.contains(state) ? conversation : nil
        }
    }
    
}

extension WireCallCenterV2 {
    
    @objc
    func applicationDidBecomeActive(note: Notification) {
        if let connectedCallConversation =  conversations(withVoiceChannelStates: [.selfConnectedToActiveChannel]).first, connectedCallConversation.isVideoCall {
            // We need to start video in conversation that accepted video call in background but did not start the recording yet
            try? connectedCallConversation.voiceChannelRouter?.v2.setVideoSendActive(true)
        }
    }
    
}
