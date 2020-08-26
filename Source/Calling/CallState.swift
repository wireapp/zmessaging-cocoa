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

private let zmLog = ZMSLog(tag: "calling")

/**
 * A participant in the call.
 */

public struct CallParticipant: Hashable {
    
    public let user: ZMUser
    public let clientId: String
    public let state: CallParticipantState

    public init(user: ZMUser, clientId: String, state: CallParticipantState) {
        self.user = user
        self.clientId = clientId
        self.state = state
    }

    init?(member: AVSCallMember, context: NSManagedObjectContext) {
        guard let user = ZMUser(remoteID: member.client.userId, createIfNeeded: false, in: context) else { return nil }
        self.init(user: user, clientId: member.client.clientId, state: member.callParticipantState)
    }

    // MARK: - Hashable

    public func hash(into hasher: inout Hasher) {
        hasher.combine(user.remoteIdentifier)
        hasher.combine(clientId)
    }

}


/**
 * The state of a participant in a call.
 */

public enum CallParticipantState: Equatable {
    /// Participant is not in the call
    case unconnected
    /// A network problem occured but the call may still connect
    case unconnectedButMayConnect
    /// Participant is in the process of connecting to the call
    case connecting
    /// Participant is connected to the call and audio is flowing
    case connected(videoState: VideoState, microphoneState: MicrophoneState)
}


/**
 * The audio state of a participant in a call.
 */

public enum AudioState: Int32, Codable {
    /// Audio is in the process of connecting.
    case connecting = 0
    /// Audio has been established and is flowing.
    case established = 1
    /// No relay candidate, though audio may still connect.
    case networkProblem = 2
}


/**
 * The state of video in the call.
 */

public enum VideoState: Int32, Codable {
    /// Sender is not sending video
    case stopped = 0
    /// Sender is sending video
    case started = 1
    /// Sender is sending video but currently has a bad connection
    case badConnection = 2
    /// Sender has paused the video
    case paused = 3
    /// Sender is sending a video of his/her desktop
    case screenSharing = 4
}

/**
 * The state of microphone in the call
 */

public enum MicrophoneState: Int32, Codable {
    /// Sender is unmuted
    case unmuted = 0
    /// Sender is muted
    case muted = 1
}
