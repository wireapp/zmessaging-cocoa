//
// Wire
// Copyright (C) 2020 Wire Swiss GmbH
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
@testable import WireSyncEngine

struct CallSnapshotTestFixture {
    static func degradedCallSnapshot(conversationId: UUID, user: ZMUser, callCenter: WireCallCenterV3) -> CallSnapshot {
        
        let callMember = AVSCallMember(client: AVSClient(userId: user.remoteIdentifier, clientId: UUID().transportString()))
        
        let callParticipantSnapshot = CallParticipantsSnapshot(
            conversationId: conversationId,
            members: [callMember],
            callCenter: callCenter
        )
        
        return CallSnapshot(
            callParticipants: callParticipantSnapshot,
            callState: .established,
            callStarter: UUID(),
            isVideo: false,
            isGroup: true,
            isConstantBitRate: false,
            videoState: .stopped,
            networkQuality: .normal,
            isConferenceCall: true,
            degradedUser: user,
            audioLevels: [],
            conversationObserverToken: nil
        )
    }
    
    static func callSnapshot(conversationId: UUID, callCenter: WireCallCenterV3) -> CallSnapshot {
        let callParticipantsSnapshot = CallParticipantsSnapshot(
            conversationId: conversationId,
            members: [],
            callCenter: callCenter
        )
        
        return CallSnapshot(
            callParticipants: callParticipantsSnapshot,
            callState: .established,
            callStarter: UUID(),
            isVideo: false,
            isGroup: true,
            isConstantBitRate: false,
            videoState: .stopped,
            networkQuality: .normal,
            isConferenceCall: true,
            degradedUser: nil,
            audioLevels: [],
            conversationObserverToken: nil
        )
    }
}
