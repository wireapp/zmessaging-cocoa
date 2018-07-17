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

/// The result of a shared identity session request.
public enum SharedIdentitySessionResponse {

    /// A user session was created.
    case success(Data)

    /// A session was created, but the user still needs to provide information.
    case pendingAdditionalInformation(Data)

    /// A failure occured.
    case error(LocalizedError)

}

/**
 * A protocol for objects that can request user sessions from
 */

public protocol SharedIdentitySessionRequester {

    /// Asks the provider to authenticate the user with the given SSO code.
    /// The result from the provider is passed to the completion handler after the request has completed.
    func requestIdentity(for token: UUID, _ completion: @escaping (SharedIdentitySessionResponse) -> Void)

}
