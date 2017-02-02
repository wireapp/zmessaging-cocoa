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

enum VoiceChannelChangeInfoKeys : String {
    case voiceChannelState = "voiceChannelState"
}
//
//class VoicechannelObserverCenter {
//
//
//    var snapshots = [ZMConversation : VoiceChannelStateSnapshot]()
//
//    func conversationsWithVoicechannelStateChange(updatedConversationsAndChangedKeys: [ZMConversation : Set<String>]) {
//        updatedConversationsAndChangedKeys.forEach{ conv, changedKeys in
//            if let snapshot = snapshots[conv] {
//                let (partChange, stateChange) = snapshot.conversationDidChange(changedKeys: changedKeys)
//                if snapshot.currentVoiceChannelState == .invalid || snapshot.currentVoiceChannelState == .noActiveUsers {
//                    snapshots.removeValue(forKey: conv)
//                }
//                if let partChange = partChange {
//                    postParticipantChangeNotification(conversation: conv, partChange: partChange)
//                }
//                if let stateChange = stateChange {
//                    postStateChangeNotification(conversation: conv, stateChange: stateChange)
//                }
//            }
//            else {
//                let didInsertNewSnapshot = insertNewSnapshotIfNeeded(converation: conv)
//            }
//        }
//    }
//
//    func insertNewSnapshotIfNeeded(converation: ZMConversation) -> Bool {
//        guard let newSnapshot = VoiceChannelStateSnapshot(conversation: converation) else { return false }
//
//        snapshots[converation] = newSnapshot
//        let stateChange = VoiceChannelStateChangeInfo(object: converation)
//        stateChange.changedKeysAndOldValues[VoiceChannelChangeInfoKeys.voiceChannelState.rawValue] = NSNumber(value: ZMVoiceChannelState.noActiveUsers.rawValue)
//        postStateChangeNotification(conversation: converation, stateChange: stateChange)
//        if let partChange = newSnapshot.initialChangeInfo {
//            postParticipantChangeNotification(conversation: converation, partChange: partChange)
//        }
//        return true
//    }
//
//    func postParticipantChangeNotification(conversation: ZMConversation, partChange: VoiceChannelParticipantsChangeInfo) {
//        NotificationCenter.default.post(Notification(name: .VoiceChannelParticipantStateChange,
//                                                     object: conversation,
//                                                     userInfo: ["changeInfo": partChange]))
//    }
//
//    func postStateChangeNotification(conversation: ZMConversation, stateChange: VoiceChannelStateChangeInfo) {
//        NotificationCenter.default.post(Notification(name: .VoiceChannelStateChange,
//                                                     object: conversation,
//                                                     userInfo: ["changeInfo": stateChange]))
//    }
//}


//
//class VoiceChannelStateSnapshot: NSObject  {
//
//    fileprivate var state : SetSnapshot
//    fileprivate var activeFlowParticipantsState : NSOrderedSet
//    fileprivate var otherActiveVideoParticipantsState : Set<ZMUser>
//
//    fileprivate var conversation : ZMConversation
//
//    fileprivate var shouldRecalculate = false
//    fileprivate var videoParticipantsChanged = false
//    var currentVoiceChannelState : ZMVoiceChannelState
//    let initialChangeInfo : VoiceChannelParticipantsChangeInfo?
//
//    init?(conversation: ZMConversation) {
//        let voiceChannelState = conversation.voiceChannelState
//        if voiceChannelState == .invalid || voiceChannelState == .noActiveUsers {
//            return nil
//        }
//        self.currentVoiceChannelState = voiceChannelState
//        self.conversation = conversation
//        state = SetSnapshot(set: conversation.voiceChannel.participants(), moveType: .uiCollectionView)
//        activeFlowParticipantsState = conversation.activeFlowParticipants.copy() as! NSOrderedSet
//        otherActiveVideoParticipantsState = conversation.otherActiveVideoCallParticipants
//        if let setChangeInfo = SetSnapshot(set: NSOrderedSet(), moveType: .uiCollectionView).updatedState(NSOrderedSet(), observedObject: conversation, newSet: conversation.voiceChannel.participants())?.changeInfo {
//            initialChangeInfo = VoiceChannelParticipantsChangeInfo(setChangeInfo: setChangeInfo)
//            initialChangeInfo?.otherActiveVideoCallParticipantsChanged = (conversation.otherActiveVideoCallParticipants.count != 0)
//        } else {
//            initialChangeInfo = nil
//        }
//        super.init()
//    }
//
//    deinit {
//        tearDown()
//    }
//
//
//    func conversationDidChange(changedKeys: Set<String>) -> (VoiceChannelParticipantsChangeInfo?, VoiceChannelStateChangeInfo?) {
//        var partStateChangeInfo : VoiceChannelParticipantsChangeInfo?
//        let hasChangedKeys = changedKeys.isDisjoint(with: ["activeFlowParticipants", "callParticipants","otherActiveVideoCallParticipants"])
//        let hasNewFlowParticipants = conversation.activeFlowParticipants.array as! [ZMUser] != activeFlowParticipantsState.array as! [ZMUser]
//        let hasNewVideoParticipants = conversation.otherActiveVideoCallParticipants != otherActiveVideoParticipantsState
//        if  hasChangedKeys || hasNewFlowParticipants || hasNewVideoParticipants {
//            videoParticipantsChanged = changedKeys.contains("otherActiveVideoCallParticipants") || hasNewVideoParticipants
//            partStateChangeInfo = recalculateSet()
//        }
//        let stateChangeInfo = updateState()
//        return (partStateChangeInfo, stateChangeInfo)
//    }
//
//    func updateState() -> VoiceChannelStateChangeInfo? {
//        let newState = conversation.voiceChannelState
//        defer {
//            currentVoiceChannelState = newState
//        }
//        if newState != currentVoiceChannelState {
//            let changeInfo = VoiceChannelStateChangeInfo(object: conversation)
//            changeInfo.changedKeysAndOldValues[VoiceChannelChangeInfoKeys.voiceChannelState.rawValue] = NSNumber(value: currentVoiceChannelState.rawValue)
//            return changeInfo
//        } else {
//            return nil
//        }
//    }
//
//    func recalculateSet() -> VoiceChannelParticipantsChangeInfo? {
//
//        shouldRecalculate = false
//        let newParticipants = conversation.voiceChannel.participants() ?? NSOrderedSet()
//        let newFlowParticipants = conversation.activeFlowParticipants
//
//        // participants who have an updated flow, but are still in the voiceChannel
//        let newConnected = newFlowParticipants.subtracting(orderedSet: activeFlowParticipantsState)
//        let newDisconnected = activeFlowParticipantsState.subtracting(orderedSet: newFlowParticipants)
//
//        // participants who left the voiceChannel / call
//        let addedUsers = newParticipants.subtracting(orderedSet: state.set)
//        let removedUsers = state.set.subtracting(orderedSet: newParticipants)
//
//        let updated = newConnected.adding(orderedSet: newDisconnected)
//            .subtracting(orderedSet: removedUsers)
//            .subtracting(orderedSet: addedUsers)
//
//        // calculate inserts / deletes / moves
//        defer {
//            videoParticipantsChanged = false
//        }
//        if let newStateUpdate = state.updatedState(updated, observedObject: conversation, newSet: newParticipants) {
//            state = newStateUpdate.newSnapshot
//            activeFlowParticipantsState = (conversation.activeFlowParticipants.copy() as? NSOrderedSet) ?? NSOrderedSet()
//
//            let changeInfo = VoiceChannelParticipantsChangeInfo(setChangeInfo: newStateUpdate.changeInfo)
//            changeInfo.otherActiveVideoCallParticipantsChanged = videoParticipantsChanged
//            return changeInfo
//        } else if videoParticipantsChanged {
//            let changeInfo = VoiceChannelParticipantsChangeInfo(setChangeInfo: SetChangeInfo(observedObject: conversation))
//            changeInfo.otherActiveVideoCallParticipantsChanged = videoParticipantsChanged
//            return changeInfo
//        }
//        return nil
//    }
//
//}
//
