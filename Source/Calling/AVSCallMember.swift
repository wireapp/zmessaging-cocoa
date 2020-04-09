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

    let convid: UUID
    let members: [Member]

    public struct Member: Codable {

        let userid: UUID
        let clientid: String
        let aestab: AudioState
        let vrecv: VideoState
    }
}

extension AVSCallMember {

    init(member: AVSParticipantsChange.Member) {
        client = AVSClient(userId: member.userid, clientId: member.clientid)
        audioState = member.aestab
        videoState = member.vrecv
        networkQuality = .normal
    }
}

/**
 * An object that represents the member of an AVS call.
 */

public struct AVSCallMember: Hashable {

    /// The client used in the call.
    public let client: AVSClient

    /// The state of the audio connection.
    public let audioState: AudioState

    /// The state of video connection.
    public let videoState: VideoState

    /// Netwok quality of this leg
    public let networkQuality: NetworkQuality

    // MARK: - Initialization

    /**
     * Creates the call member from its values.
     * - parameter client: The client used in the call.
     * - parameter audioState: The state of the audio connection. Defaults to `.connecting`.
     * - parameter videoState: The state of video connection. Defaults to `stopped`.
     * - parameter networkQuality: The quality of the network connection. Defaults to `.normal`.
     */

    public init(client: AVSClient,
                audioState: AudioState = .connecting,
                videoState: VideoState = .stopped,
                networkQuality: NetworkQuality = .normal)
    {
        self.client = client
        self.audioState = audioState
        self.videoState = videoState
        self.networkQuality = networkQuality
    }

    // MARK: - Properties

    /// The state of the participant.
    var callParticipantState: CallParticipantState {
        switch audioState {
        case .connecting:
            return .connecting
        case .established:
            return .connected(videoState: videoState)
        case .networkProblem:
            return .unconnectedButMayConnect

        }
    }

    // MARK: - Hashable
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(client)
    }
    
    public static func == (lhs: AVSCallMember, rhs: AVSCallMember) -> Bool {
        return lhs.hashValue == rhs.hashValue
    }
}


/// Used to identify a participant in a call.

public struct AVSClient: Hashable {

    public let userId: UUID
    public let clientId: String

    public init(userId: UUID, clientId: String) {
        self.userId = userId
        self.clientId = clientId
    }

    init?(userClient: UserClient) {
        guard
            let userId = userClient.user?.remoteIdentifier,
            let clientId = userClient.remoteIdentifier
        else {
            return nil
        }

        self.init(userId: userId, clientId: clientId)
    }

}

extension AVSClient: Codable {

    enum CodingKeys: String, CodingKey {
        
        case userId = "userid"
        case clientId = "clientid"

    }

}


struct AVSClientList: Codable {

    let clients: [AVSClient]

    var json: String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }

}
