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
    
    // Remove duplicates see: https://wearezeta.atlassian.net/browse/ZIOS-8610
    static func removeDuplicateMembers(_ members: [AVSCallMember]) -> OrderedSetState<AVSCallMember> {
        let callMembers = members.reduce([AVSCallMember]()){ (filtered, member) in
            filtered + (filtered.contains(member) ? [] : [member])
        }
        
        return callMembers.toOrderedSetState()
    }
    
    func callParticipantsChanged(participants: [AVSCallMember]) {
        members = type(of:self).removeDuplicateMembers(participants)
        notifyChange()
    }

    func callParticpantVideoStateChanged(userId: UUID, clientId: String, videoState: VideoState) {
        guard let callMember = findMember(userId: userId, clientId: clientId) else { return }

        update(updatedMember: AVSCallMember(userId: userId, clientId: clientId, audioState: callMember.audioState, videoState: videoState))
    }

    func callParticpantAudioEstablished(userId: UUID) {
        guard let callMember = members.array.first(where: { $0.remoteId == userId }) else { return }

        update(updatedMember: AVSCallMember(userId: userId, clientId: callMember.clientId, audioState: .established, videoState: callMember.videoState))
    }

    func callParticpantNetworkQualityChanged(userId: UUID, networkQuality: NetworkQuality) {
        guard let callMember = members.array.first(where: { $0.remoteId == userId }) else { return }

        update(updatedMember: AVSCallMember(userId: userId, clientId: callMember.clientId, audioState: callMember.audioState, videoState: callMember.videoState, networkQuality: networkQuality))
    }
    
    func update(updatedMember: AVSCallMember) {
        guard let targetMember = findMember(userId: updatedMember.remoteId, clientId: updatedMember.clientId) else { return }

        members = OrderedSetState(array: members.array.map({ member in
            member == targetMember ? updatedMember : member
        }))
    }

    func notifyChange() {
        guard let context = callCenter.uiMOC else { return }
        
        let participants = members.map { CallParticipant(member: $0, context: context) }.compactMap(\.self)
        WireCallCenterCallParticipantNotification(conversationId: conversationId, participants: participants).post(in: context.notificationContext)
    }

    public func callParticipantState(forUser userId: UUID) -> CallParticipantState {
        guard let callMember = members.array.first(where: { $0.remoteId == userId }) else { return .unconnected }
        
        return callMember.callParticipantState
    }

    /// Tries to find the call member with the matching userId and clientId, otherwise the first member
    /// with the matching userId.
    ///
    private func findMember(userId: UUID, clientId: String?) -> AVSCallMember? {
        let participantsByUser = members.array.filter { $0.remoteId == userId }
        return participantsByUser.first { $0.clientId == clientId } ?? participantsByUser.first
    }
}
