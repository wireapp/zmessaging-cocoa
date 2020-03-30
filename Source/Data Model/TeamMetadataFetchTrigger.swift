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

public protocol TeamMetadataFetchTriggerType: class {

    func triggerUserFetch(for user: UserType)
    func triggerUserRichprofileFetch(for user: UserType)
    func triggerMembershipFetch(for user: UserType)
    func triggerTeamFetch(for team: TeamType)

}

/// A helper type that is able to trigger fetching metadata from the backend.
///
/// For use primarily from the UI where we don't have concrete model types.

public final class TeamMetadataFetchTrigger: TeamMetadataFetchTriggerType {

    public init() { }

    public func triggerUserFetch(for user: UserType) {
        concreteUser(from: user)?.needsToBeUpdatedFromBackend = true
    }

    public func triggerUserRichprofileFetch(for user: UserType) {
        concreteUser(from: user)?.needsRichProfileUpdate = true
    }

    public func triggerMembershipFetch(for user: UserType) {
        concreteUser(from: user)?.membership?.needsToBeUpdatedFromBackend = true
    }

    public func triggerTeamFetch(for team: TeamType) {
        concreteTeam(from: team)?.needsToBeUpdatedFromBackend = true
    }

    // MARK: - Helpers

    private func concreteUser(from user: UserType) -> ZMUser? {
        if let zmUser = user as? ZMUser {
            return zmUser
        } else if let searchUser = user as? ZMSearchUser {
            return searchUser.user
        } else {
            return nil
        }
    }

    private func concreteTeam(from team: TeamType) -> Team? {
        return team as? Team
    }

}
