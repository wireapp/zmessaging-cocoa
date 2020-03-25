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

    // MARK: - Properties

    private unowned var callCenter: WireCallCenterV3
    private let conversationId: UUID
    private(set) var members: OrderedSetState<AVSCallMember>

    /// Worst network quality of all the participants.

    var networkQuality: NetworkQuality {
        return members.array
            .map(\.networkQuality)
            .sorted { $0.rawValue < $1.rawValue }
            .last ?? .normal
    }

    // MARK: - Life Cycle

    init(conversationId: UUID, members: [AVSCallMember], callCenter: WireCallCenterV3) {
        self.callCenter = callCenter
        self.conversationId = conversationId
        self.members = type(of: self).removeDuplicateMembers(members)
    }

    // MARK: - Updates

    func callParticipantsChanged(participants: [AVSCallMember]) {
        members = type(of:self).removeDuplicateMembers(participants)
        notifyChange()
    }

    func callParticipantVideoStateChanged(userId: UUID, clientId: String, videoState: VideoState) {
        updateMember(userId: userId, clientId: clientId, videoState: videoState)
    }

    func callParticipantAudioEstablished(userId: UUID, clientId: String) {
        updateMember(userId: userId, clientId: clientId, audioState: .established)
    }

    func callParticipantNetworkQualityChanged(userId: UUID, clientId: String, networkQuality: NetworkQuality) {
        updateMember(userId: userId, clientId: clientId, networkQuality: networkQuality)
    }

    // MARK: - Helpers

    /// Updates the locally stored member for the given userId and clientId with the given non nil properties.

    private func updateMember(userId: UUID,
                              clientId: String,
                              audioState: AudioState? = nil,
                              videoState: VideoState? = nil,
                              networkQuality: NetworkQuality? = nil) {

        guard let localMember = findMember(with: userId, clientId: clientId) else { return }

        let updatedMember = AVSCallMember(userId: userId,
                                          clientId: clientId,
                                          audioState: audioState ?? localMember.audioState,
                                          videoState: videoState ?? localMember.videoState,
                                          networkQuality: networkQuality ?? localMember.networkQuality)

        members = OrderedSetState(array: members.array.map({ member in
            member == localMember ? updatedMember : member
        }))
    }

    /// Returns the member matching the given userId and clientId.

    private func findMember(with userId: UUID, clientId: String) -> AVSCallMember? {
        return members.array.first { $0.remoteId == userId && $0.clientId == clientId }
    }

    /// Notifies observers of a potential change in the participants set.

    private func notifyChange() {
        guard let context = callCenter.uiMOC else { return }
        
        let participants = members
            .map { CallParticipant(member: $0, context: context) }
            .compactMap(\.self)

        WireCallCenterCallParticipantNotification(conversationId: conversationId, participants: participants)
            .post(in: context.notificationContext)
    }

}

extension CallParticipantsSnapshot {

    // Remove duplicates see: https://wearezeta.atlassian.net/browse/ZIOS-8610
    private static func removeDuplicateMembers(_ members: [AVSCallMember]) -> OrderedSetState<AVSCallMember> {
        let callMembers = members.reduce([AVSCallMember]()) { (filtered, member) in
            filtered + (filtered.contains(member) ? [] : [member])
        }

        return callMembers.toOrderedSetState()
    }
}
