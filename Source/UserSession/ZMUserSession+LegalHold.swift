//
// Wire
// Copyright (C) 2019 Wire Swiss GmbH
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
import WireDataModel
import WireTransport

public enum LegalHoldInstallationError: Error {
    case userNotInTeam(ZMUser)
    case invalidUser(ZMUser)
}

extension ZMUserSession {

    /**
     * Sends a request to accept a legal hold request for the specified user.
     * - parameter completionHandler: The block that will be called with the result of the request.
     * - parameter error: The error that prevented the approval of legal hold.
     */

    public func acceptLegalHold(completionHandler: @escaping (_ error: Error?) -> Void) {
        let selfUser = ZMUser.selfUser(in: managedObjectContext)

        // 1) Create the Request
        guard let teamID = selfUser.teamIdentifier else {
            return completionHandler(LegalHoldInstallationError.userNotInTeam(selfUser))
        }

        guard let userID = selfUser.remoteIdentifier else {
            return completionHandler(LegalHoldInstallationError.invalidUser(selfUser))
        }

        let path = "/teams/\(teamID.transportString())/legalhold/\(userID.transportString())/approve"
        let request = ZMTransportRequest(path: path, method: .methodPUT, payload: nil)

        // 2) Handle the Response
        request.add(ZMCompletionHandler(on: managedObjectContext, block: { _ in
            // TODO: Handle errors
            completionHandler(nil)
        }))

        // 3) Schedule the Request
        transportSession.enqueueOneTime(request)
    }

}
