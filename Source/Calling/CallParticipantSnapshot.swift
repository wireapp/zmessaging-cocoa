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

        let member = AVSCallMember(userId: userId,
                                   clientId: clientId,
                                   audioState: callMember.audioState,
                                   videoState: videoState)

        update(updatedMember: member)
    }

    func callParticpantAudioEstablished(userId: UUID, clientId: String) {
        guard let callMember = findMember(userId: userId, clientId: clientId) else { return }

        let member = AVSCallMember(userId: userId,
                                   clientId: clientId,
                                   audioState: .established,
                                   videoState: callMember.videoState)

        update(updatedMember: member)
    }

    // FIXME: This never get's called. We would likely want to call this for the new network state.
    func callParticpantNetworkQualityChanged(userId: UUID, clientId: String, networkQuality: NetworkQuality) {
        guard let callMember = findMember(userId: userId, clientId: clientId) else { return }

        let member = AVSCallMember(userId: callMember.remoteId,
                                   clientId: callMember.clientId,
                                   audioState: callMember.audioState,
                                   videoState: callMember.videoState,
                                   networkQuality: networkQuality)

        update(updatedMember: member)
    }
    
    func update(updatedMember: AVSCallMember) {
        if let clientId = updatedMember.clientId, let targetMember = findMember(userId: updatedMember.remoteId, clientId: clientId) {
            // Found a direct match
            members = OrderedSetState(array: members.array.map({ member in
                member == targetMember ? updatedMember : member
            }))
        } else if let targetMember = findMembers(with: updatedMember.remoteId).first {
            // Found a match where don't yet know the client id
            members = OrderedSetState(array: members.array.map({ member in
                member == targetMember ? updatedMember : member
            }))
        }
    }

    func notifyChange() {
        guard let context = callCenter.uiMOC else { return }
        
        let participants = members.map { CallParticipant(member: $0, context: context) }.compactMap(\.self)
        WireCallCenterCallParticipantNotification(conversationId: conversationId, participants: participants).post(in: context.notificationContext)
    }

    public func callParticipantState(forUser userId: UUID) -> CallParticipantState {
        guard let callMember = findMembers(with: userId).first else { return .unconnected }
        
        return callMember.callParticipantState
    }

    /// Returns the first known call member matching the given user and client ids.

    private func findMember(userId: UUID, clientId: String) -> AVSCallMember? {
        return findMembers(with: userId).first { $0.clientId == clientId }
    }

    /// Returns all members matching the given user id.

    private func findMembers(with userId: UUID) -> [AVSCallMember] {
        return members.array.filter { $0.remoteId == userId }
    }
}
