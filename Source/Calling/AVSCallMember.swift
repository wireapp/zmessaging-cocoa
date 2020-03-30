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


public struct AVSParticipantsChange: Codable {
    public struct Member: Codable {
        let userid: UUID
        let clientid: String
        let aestab: Int32
        let vrecv: Int32
    }
    let convid: UUID
    let members: [Member]
}

extension AVSCallMember {
    init(member: AVSParticipantsChange.Member) {
        remoteId = member.userid
        clientId = member.clientid
        audioEstablished = (member.aestab == 1)
        videoState = VideoState(rawValue: member.vrecv) ?? .stopped
        networkQuality = .normal
    }
}

/**
 * An object that represents the member of an AVS call.
 */

public struct AVSCallMember: Hashable {

    /// The remote identifier of the user.
    public let remoteId: UUID
    
    /// The client identifier of the user, this is only available after the call member has connected
    public let clientId: String?

    /// Whether an audio connection was established.
    public let audioEstablished: Bool

    /// The state of video connection.
    public let videoState: VideoState

    /// Netwok quality of this leg
    public let networkQuality: NetworkQuality

    // MARK: - Initialization

    /**
     * Creates the call member from its values.
     * - parameter userId: The remote identifier of the user.
     * - parameter clientId: The client identifier of the user. Default to `nil`
     * - parameter audioEstablished: Whether an audio connection was established. Defaults to `false`.
     * - parameter videoState: The state of video connection. Defaults to `stopped`.
     * - parameter networkQuality: The quality of the network connection. Defaults to `.normal`.
     */

    public init(userId : UUID, clientId: String? = nil, audioEstablished: Bool = false, videoState: VideoState = .stopped, networkQuality: NetworkQuality = .normal) {
        self.remoteId = userId
        self.clientId = clientId
        self.audioEstablished = audioEstablished
        self.videoState = videoState
        self.networkQuality = networkQuality
    }

    // MARK: - Properties

    /// The state of the participant.
    var callParticipantState: CallParticipantState {
        if audioEstablished {
            return .connected(videoState: videoState, clientId: clientId)
        } else {
            return .connecting
        }
    }

    // MARK: - Hashable
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(remoteId)
        hasher.combine(clientId)
    }
    
    public static func == (lhs: AVSCallMember, rhs: AVSCallMember) -> Bool {
        return lhs.hashValue == rhs.hashValue
    }
}
