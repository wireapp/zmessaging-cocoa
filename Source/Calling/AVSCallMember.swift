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
import avs

/**
 * An object that represents the member of an AVS call.
 */

public struct AVSCallMember: Hashable {

    /// The remote identifier of the user.
    public let remoteId: UUID

    /// Whether an audio connection was established.
    public let audioEstablished: Bool

    /// The state of video connection.
    public let videoState: VideoState

    // MARK: - Initialization

    /**
     * Creates the call member from its raw C counterpart.
     * - parameter wcallMember: The struct object representing the call member in AVS.
     * - returns: The call member, if the raw struct contains a valid remote ID.
     */

    public init?(wcallMember: wcall_member) {
        guard let remoteId = UUID(cString: wcallMember.userid) else { return nil }
        self.remoteId = remoteId
        audioEstablished = (wcallMember.audio_estab != 0)
        videoState = VideoState(rawValue: wcallMember.video_recv) ?? .stopped
    }

    /**
     * Creates the call member from its values.
     * - parameter userId: The remote identifier of the user.
     * - parameter audioEstablished: Whether an audio connection was established. Defaults to `false`.
     * - parameter videoState: The state of video connection. Defaults to `stopped`.
     */

    public init(userId : UUID, audioEstablished: Bool = false, videoState: VideoState = .stopped) {
        self.remoteId = userId
        self.audioEstablished = audioEstablished
        self.videoState = videoState
    }

    // MARK: - Properties

    /// The state of the participant.
    var callParticipantState: CallParticipantState {
        if audioEstablished {
            return .connected(videoState: videoState)
        } else {
            return .connecting
        }
    }

    // MARK: - Hashable

    public var hashValue: Int {
        return remoteId.hashValue
    }

    public static func == (lhs: AVSCallMember, rhs: AVSCallMember) -> Bool {
        return lhs.remoteId == rhs.remoteId
    }

}
