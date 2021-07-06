//
// Wire
// Copyright (C) 2021 Wire Swiss GmbH
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
