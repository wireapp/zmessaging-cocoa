//
// Wire
// Copyright (C) 2017 Wire Swiss GmbH
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


@objcMembers public class MockUserInfoParser: NSObject, UserInfoParser {

    public var accountExistsLocallyCalled = 0
    public var existingAccounts = [ZMTransportResponse]()
    public func accountExistsLocally(from response: ZMTransportResponse) -> Bool {
        accountExistsLocallyCalled += 1
        return existingAccounts.contains(response)
    }

    var parseCallCount = 0
    var parsedResponses = [ZMTransportResponse]()

    public func parseUserInfo(from response: ZMTransportResponse) {
        parseCallCount += 1
        parsedResponses.append(response)
    }

    public var userId: UUID?
    public var userIdentifierCalled = 0
    public func userIdentifier(from response: ZMTransportResponse) -> UUID? {
        userIdentifierCalled += 1
        return userId
    }

}
