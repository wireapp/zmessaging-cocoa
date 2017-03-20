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


class VoiceChannelParticipantSnapshot: NSObject {
    
    fileprivate var state : SetSnapshot
    fileprivate var activeFlowParticipantsState : NSOrderedSet
    fileprivate var callParticipantState : NSOrderedSet

    fileprivate weak var conversation : ZMConversation?

    init(conversation: ZMConversation) {
        self.conversation = conversation
        state = SetSnapshot(set: conversation.voiceChannelRouter!.v2.participants, moveType: .uiCollectionView)
        activeFlowParticipantsState = conversation.activeFlowParticipants.copy() as! NSOrderedSet
        callParticipantState = conversation.callParticipants.copy() as! NSOrderedSet
    }
    
    func callStateDidChange(for conversations: Set<ZMConversation>) {
        guard let conversation = conversation, conversations.contains(conversation) else { return }
        recalculateSet()
    }
    
    func recalculateSet() {
        guard let conversation = conversation,
              let voiceChannel = conversation.voiceChannel
        else { return }
        
        let newParticipants = voiceChannel.participants
        let newFlowParticipants = conversation.activeFlowParticipants
        guard newParticipants != callParticipantState || newFlowParticipants != activeFlowParticipantsState else { return }
        
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
            VoiceChannelParticipantNotification(setChangeInfo: newStateUpdate.changeInfo, conversation: conversation).post()
        }
        activeFlowParticipantsState = (newFlowParticipants.copy() as? NSOrderedSet) ?? NSOrderedSet()
        callParticipantState = (newParticipants.copy() as? NSOrderedSet) ?? NSOrderedSet()
    }
}

public class VoiceChannelStateSnapshot {
    fileprivate weak var conversation : ZMConversation?
    fileprivate var currentVoiceChannelState : VoiceChannelV2State
    
    init?(conversation: ZMConversation) {
        let state = conversation.voiceChannelRouter?.v2.state ?? VoiceChannelV2State.invalid
        guard state != .invalid && state != .noActiveUsers else { return nil }
        self.conversation = conversation
        currentVoiceChannelState = state
        // Initial change notification
        VoiceChannelStateNotification(voiceChannelState: currentVoiceChannelState, conversationId: conversation.objectID).post()
    }
    
    func recalculateState(){
        guard let conversation = self.conversation else { return }
        _ = updateVoiceChannelState(for: conversation)
    }
    
    func updateVoiceChannelState(for conversation: ZMConversation) -> Bool {
        guard conversation == self.conversation else { return false }
        let newState = conversation.voiceChannelRouter?.v2.state ?? VoiceChannelV2State.invalid
        
        if newState != currentVoiceChannelState {
            currentVoiceChannelState = newState
            VoiceChannelStateNotification(voiceChannelState: newState, conversationId: conversation.objectID).post()
            return true
        }
        return false
    }
}

fileprivate class ReceivedVideoStateSnapshot {
    
    fileprivate weak var conversation : ZMConversation?
    
    /// remote side has the intent to send video
    fileprivate var isVideoEnabled = false
    // remote side does send video
    fileprivate var isVideoStarted = true
    // remote side has a bad connection
    fileprivate var isBadConnection = false
    
    fileprivate var previousState : ReceivedVideoState = .stopped
    
    init(conversation: ZMConversation) {
        self.conversation = conversation
    }
    
    func callStateDidChange(for conversations: Set<ZMConversation>) {
        guard let conversation = conversation,
              conversations.contains(conversation)
        else { return }
        
        isVideoEnabled = !conversation.otherActiveVideoCallParticipants.isEmpty
        notifyObserverIfStateChanged()
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
    
    func updateState(changeInfo: AVSVideoStateChangeInfo) {
        isVideoStarted = changeInfo.state == .FLOWMANAGER_VIDEO_RECEIVE_STARTED
        isBadConnection = changeInfo.reason == .FLOWMANAGER_VIDEO_BAD_CONNECTION
        notifyObserverIfStateChanged()
    }
    
    func notifyObserverIfStateChanged() {
        guard let conversation = conversation else { return }
        
        let newState = state
        if newState != previousState {
            previousState = newState
            VoiceChannelVideoChangedNotification(receivedVideoState: newState, conversation: conversation).post()
        }
    }
}


extension NSManagedObjectContext {
    public static let WireCallCenterV2Key = "WireCallCenter2"
    
    public var wireCallCenterV2 : WireCallCenterV2 {
        assert(zm_isUserInterfaceContext, "WireCallCenter should not be initialized on syncMOC")
        if let callCenter = userInfo[NSManagedObjectContext.WireCallCenterV2Key] as? WireCallCenterV2 {
            return callCenter
        }
        
        let callCenter = WireCallCenterV2(context: self)
        userInfo[NSManagedObjectContext.WireCallCenterV2Key] = callCenter
        return callCenter
    }
}


@objc
public class WireCallCenterV2 : NSObject {
    
    @objc
    public static let CallStateDidChangeNotification = Notification.Name("CallStateDidChangeNotification")
    
    unowned var context : NSManagedObjectContext
    private var voiceChannelSnapshots : [ZMConversation : VoiceChannelStateSnapshot] = [:]
    private var videoSnapshot : ReceivedVideoStateSnapshot?
    private var participantSnapshot : VoiceChannelParticipantSnapshot?
        
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    public init(context: NSManagedObjectContext) {
        self.context = context
        super.init()
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(applicationDidBecomeActive(note:)),
                                               name: Notification.Name.UIApplicationDidBecomeActive,
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(flowManagerDidChangeReceivedVideoState(note:)),
                                               name: NSNotification.Name(rawValue: FlowManagerVideoReceiveStateNotification),
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(managedObjectContextDidChange(note:)),
                                               name: NSNotification.Name.NSManagedObjectContextObjectsDidChange,
                                               object: context)
    }
    
    fileprivate func createParticipantSnapshotIfNeeded(for conversation: ZMConversation) {
        if participantSnapshot?.conversation != conversation {
            participantSnapshot = VoiceChannelParticipantSnapshot(conversation: conversation)
        }
    }
    
    fileprivate func createVideoStateSnapshotIfNeeded(for conversation: ZMConversation) {
        if videoSnapshot?.conversation != conversation {
            videoSnapshot = ReceivedVideoStateSnapshot(conversation: conversation)
        }
    }
    
    // MARK : Processing changes
    
    public func managedObjectContextDidChange(note: Notification) {
        guard let userInfo = note.userInfo as? [String : Any] else { return }
        
        let updatedObjects = userInfo[NSUpdatedObjectsKey] as? Set<NSManagedObject> ?? Set<NSManagedObject>()
        let insertedObjects = userInfo[NSInsertedObjectsKey] as? Set<NSManagedObject> ?? Set<NSManagedObject>()
        let refreshedObjects = userInfo[NSRefreshedObjectsKey] as? Set<NSManagedObject> ?? Set<NSManagedObject>()
        
        let changedObjects = updatedObjects.union(insertedObjects).union(refreshedObjects)
        let changedConversations = changedObjects.flatMap({ $0 as? ZMConversation })
        
        for conversation in changedConversations {
            updateVoiceChannelState(forConversation: conversation)
            
            if participantSnapshot?.conversation == conversation {
                participantSnapshot?.recalculateSet()
            }
        }
    }
    
    @objc
    public func callStateDidChange(conversations: Set<ZMConversation>) {
        conversations.forEach{
            if updateVoiceChannelState(forConversation: $0), let context = $0.managedObjectContext {
                NotificationDispatcher.notifyNonCoreDataChanges(
                    objectID: $0.objectID,
                    changedKeys: [ZMConversationListIndicatorKey],
                    uiContext: context
                )
            }
        }
        videoSnapshot?.callStateDidChange(for: conversations)
        participantSnapshot?.callStateDidChange(for: conversations)
    }
    
    @objc
    func flowManagerDidChangeReceivedVideoState(note: Notification) {
        context.performGroupedBlock { [weak self] in
            guard let changeInfo = note.object as? AVSVideoStateChangeInfo else { return }
            self?.videoSnapshot?.updateState(changeInfo: changeInfo)
        }
    }
    
    @discardableResult
    func updateVoiceChannelState(forConversation conversation: ZMConversation) -> Bool {
        if let snapshot = voiceChannelSnapshots[conversation] {
            guard snapshot.updateVoiceChannelState(for: conversation) else { return false }
            if snapshot.currentVoiceChannelState == .invalid {
                voiceChannelSnapshots.removeValue(forKey: conversation)
            } else {
                return true
            }
        } else if let snapshot = VoiceChannelStateSnapshot(conversation: conversation) {
            voiceChannelSnapshots[conversation] = snapshot
            return true
        }
        return false
    }
    
    func conversations(withVoiceChannelStates expectedStates: [VoiceChannelV2State]) -> [ZMConversation] {
        return voiceChannelSnapshots.flatMap { (conversation: ZMConversation, snapshot: VoiceChannelStateSnapshot) -> ZMConversation? in
            return expectedStates.contains(snapshot.currentVoiceChannelState) ? conversation : nil
        }
    }
    
    public func applicationWillEnterForeground() {
        // Do nothing
        participantSnapshot?.recalculateSet()
        voiceChannelSnapshots.forEach{$0.value.recalculateState()}
    }
    
    public func applicationDidEnterBackground() {
        // Do nothing
    }
}


// MARK: Adding and Removing Observers

/// Wraps the NSObserver Token returned from NSNotificationCenter
class NotificationCenterObserverToken : NSObject {
    
    var token : AnyObject?
    
    deinit {
        guard let token = token else { return }
        NotificationCenter.default.removeObserver(token)
    }
    
    init(name: NSNotification.Name, object: AnyObject?, queue: OperationQueue?, block: @escaping (_ note: Notification) -> Void) {
        token = NotificationCenter.default.addObserver(forName: name, object: object, queue: queue, using: block)
    }
    
}

extension WireCallCenterV2 {

    /// Add observer of the state of all voice channels. Returns a token which needs to be retained as long as the observer should be active.
    public class func addVoiceChannelStateObserver(observer: WireCallCenterV2CallStateObserver, context: NSManagedObjectContext) -> WireCallCenterObserverToken {
        return NotificationCenterObserverToken(name: VoiceChannelStateNotification.notificationName, object: nil, queue: .main) {
            [weak observer] (note) in
            guard let note = note.userInfo?[VoiceChannelStateNotification.userInfoKey] as? VoiceChannelStateNotification,
                  let strongObserver = observer
            else { return }
                
            context.performGroupedBlock {
                guard let conversation = (try? context.existingObject(with: note.conversationId)) as? ZMConversation else { return }
                strongObserver.callCenterDidChange(voiceChannelState: note.voiceChannelState, conversation: conversation)
            }
        }
    }
    
    /// Add observer of particpants in a voice channel. Returns a token which needs to be retained as long as the observer should be active.
    public class func addVoiceChannelParticipantObserver(observer: VoiceChannelParticipantObserver, forConversation conversation: ZMConversation, context: NSManagedObjectContext) -> WireCallCenterObserverToken {
        context.wireCallCenterV2.createParticipantSnapshotIfNeeded(for: conversation)
        
        return NotificationCenterObserverToken(name: VoiceChannelParticipantNotification.notificationName, object: conversation, queue: .main) {
            [weak observer] (note) in
            guard let note = note.userInfo?[VoiceChannelParticipantNotification.userInfoKey] as? VoiceChannelParticipantNotification,
                let strongObserver = observer
                else { return }
            
                strongObserver.voiceChannelParticipantsDidChange(note.setChangeInfo)
        }
    }
    
    /// Add observer of voice gain. Returns a token which needs to be retained as long as the observer should be active.
    public class func addVoiceGainObserver(observer: VoiceGainObserver, forConversation conversation: ZMConversation, context: NSManagedObjectContext) -> WireCallCenterObserverToken {
        return NotificationCenterObserverToken(name: VoiceGainNotification.notificationName, object: conversation.remoteIdentifier! as NSUUID, queue: .main) { [weak observer] (note) in
            guard let note = note.userInfo?[VoiceGainNotification.userInfoKey] as? VoiceGainNotification,
                let observer = observer,
                let user = ZMUser(remoteID: note.userId, createIfNeeded: false, in: context)
            else { return }
            
            observer.voiceGainDidChange(forParticipant: user, volume: note.volume)
        }
    }
    
    /// Add observer of received video. Returns a token which needs to be retained as long as the observer should be active.
    public class func addReceivedVideoObserver(observer: ReceivedVideoObserver, forConversation conversation: ZMConversation, context: NSManagedObjectContext) -> WireCallCenterObserverToken {
        context.wireCallCenterV2.createVideoStateSnapshotIfNeeded(for: conversation)
        
        return NotificationCenterObserverToken(name: VoiceChannelVideoChangedNotification.notificationName, object: conversation, queue: .main) {
            [weak observer] (note) in
            guard let note = note.userInfo?[VoiceChannelVideoChangedNotification.userInfoKey] as? VoiceChannelVideoChangedNotification,
                let strongObserver = observer
                else { return }
            
            context.performGroupedBlock {
                strongObserver.callCenterDidChange(receivedVideoState: note.receivedVideoState)
            }
        }
    }
    
    public class func removeObserver(token: WireCallCenterObserverToken) {
        NotificationCenter.default.removeObserver(token)
    }
    
}

extension WireCallCenterV2 {
    
    @objc
    func applicationDidBecomeActive(note: Notification) {
        context.performGroupedBlock { [weak self] in
            guard let `self` = self,
                  let connectedCallConversation =  self.conversations(withVoiceChannelStates: [.selfConnectedToActiveChannel]).first, connectedCallConversation.isVideoCall
            else { return }
                // We need to start video in conversation that accepted video call in background but did not start the recording yet
                try? connectedCallConversation.voiceChannelRouter?.v2.setVideoSendActive(true)
            self.context.enqueueDelayedSave()
        }
    }
    
}
