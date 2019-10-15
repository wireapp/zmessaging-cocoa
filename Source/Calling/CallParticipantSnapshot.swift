//
// Wire
// Copyright (C) 2018 Wire Swiss GmbH
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
import WireUtilities

class CallParticipantsSnapshot {
    
    public private(set) var members : OrderedSetState<AVSCallMember>

    // We take the worst quality of all the legs
    public var networkQuality: NetworkQuality {
        return members.array.map(\.networkQuality)
            .sorted() { $0.rawValue < $1.rawValue }
            .last ?? .normal
    }
    
    fileprivate unowned var callCenter : WireCallCenterV3
    fileprivate let conversationId : UUID
    
    init(conversationId: UUID, members: [AVSCallMember], callCenter: WireCallCenterV3) {
        self.callCenter = callCenter
        self.conversationId = conversationId
        self.members = type(of: self).removeDuplicateMembers(members)
    }
    
    static func removeDuplicateMembers(_ members: [AVSCallMember]) -> OrderedSetState<AVSCallMember> {
        // remove duplicates see: https://wearezeta.atlassian.net/browse/ZIOS-8610
        // When a user joins with two devices, we would have a duplicate entry for this user in the member array returned from AVS
        // For now, we will keep the one with "the highest state", meaning if one entry has `audioEstablished == false` and the other one `audioEstablished == true`, we keep the one with `audioEstablished == true`
        let callMembers = members.reduce([AVSCallMember]()){ (filtered, member) in
            var newFiltered = filtered
            if let idx = newFiltered.firstIndex(of: member) {
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
    
    func callParticipantsChanged(participants: [AVSCallMember]) {
        members = type(of:self).removeDuplicateMembers(participants)
        notifyChange()
    }
    
    func callParticpantVideoStateChanged(userId: UUID, videoState: VideoState) {
        guard let callMember = members.array.first(where: { $0.remoteId == userId }) else { return }
        
        update(updatedMember: AVSCallMember(userId: userId, clientId: callMember.clientId, audioEstablished: callMember.audioEstablished, videoState: videoState))
    }
    
    func callParticpantAudioEstablished(userId: UUID) {
        guard let callMember = members.array.first(where: { $0.remoteId == userId }) else { return }
        
        update(updatedMember: AVSCallMember(userId: userId, clientId: callMember.clientId, audioEstablished: true, videoState: callMember.videoState))
    }

    func callParticpantNetworkQualityChanged(userId: UUID, networkQuality: NetworkQuality) {
        guard let callMember = members.array.first(where: { $0.remoteId == userId }) else { return }

        update(updatedMember: AVSCallMember(userId: userId, clientId: callMember.clientId, audioEstablished: callMember.audioEstablished, videoState: callMember.videoState, networkQuality: networkQuality))
    }
    
    func update(updatedMember: AVSCallMember) {
        members = OrderedSetState(array: members.array.map({ member in
            if member.remoteId == updatedMember.remoteId {
                return updatedMember
            } else {
                return member
            }
        }))
        notifyChange()
    }
    
    func notifyChange() {
        if let context = callCenter.uiMOC {
            WireCallCenterCallParticipantNotification(conversationId: conversationId, participants: members.map({ ($0.remoteId, $0.callParticipantState) })).post(in: context.notificationContext)
        }
        
    }
    
    public func callParticipantState(forUser userId: UUID) -> CallParticipantState {
        guard let callMember = members.array.first(where: { $0.remoteId == userId }) else { return .unconnected }
        
        return callMember.callParticipantState
    }
}
