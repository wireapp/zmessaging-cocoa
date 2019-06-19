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

public enum LegalHoldActivationError: Error {
    case userNotInTeam(ZMUser)
    case invalidUser(ZMUser)
    case invalidResponse
    case invalidPassword
}

extension ZMUserSession {

    /**
     * Sends a request to accept a legal hold request for the specified user.
     * - parameter password: The password of the user to send in the payload, if it's not a SSO user.
     * - parameter completionHandler: The block that will be called with the result of the request.
     * - parameter error: The error that prevented the approval of legal hold.
     */

    public func acceptLegalHold(password: String?, completionHandler: @escaping (_ error: LegalHoldActivationError?) -> Void) {
        let selfUser = ZMUser.selfUser(in: managedObjectContext)

        // 1) Create the Request
        guard let teamID = selfUser.teamIdentifier else {
            return completionHandler(LegalHoldActivationError.userNotInTeam(selfUser))
        }

        guard let userID = selfUser.remoteIdentifier else {
            return completionHandler(LegalHoldActivationError.invalidUser(selfUser))
        }

        var payload: [String: Any] = [:]
        payload["password"] = password

        let path = "/teams/\(teamID.transportString())/legalhold/\(userID.transportString())/approve"
        let request = ZMTransportRequest(path: path, method: .methodPUT, payload: payload as NSDictionary)

        // 2) Handle the Response
        request.add(ZMCompletionHandler(on: managedObjectContext, block: { response in
            guard response.httpStatus == 200 else {
                return completionHandler(LegalHoldActivationError.invalidResponse)
            }

            completionHandler(nil)
        }))

        // 3) Schedule the Request
        transportSession.enqueueOneTime(request)
    }

}
