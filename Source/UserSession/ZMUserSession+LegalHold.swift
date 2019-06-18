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
    case couldNotEstablishSession
    case invalidState
}

extension ZMUserSession {

    /**
     * Sends a request to accept a legal hold request for the specified user.
     * - parameter request: The request that was accepted by the user.
     * - parameter password: The password of the user to send in the payload, if it's not a SSO user.
     * - parameter completionHandler: The block that will be called with the result of the request.
     * - parameter error: The error that prevented the approval of legal hold.
     */

    public func accept(legalHoldRequest: LegalHoldRequest, password: String?, completionHandler: @escaping (_ error: LegalHoldActivationError?) -> Void) {

        guard let syncMoc = syncManagedObjectContext else {
            return completionHandler(.invalidState)
        }

        func complete(error: LegalHoldActivationError?) {
            DispatchQueue.main.async {
                completionHandler(error)
            }
        }

        syncMoc.performGroupedBlock {
            let selfUser = ZMUser.selfUser(in: syncMoc)

            // 1) Create the potential LH client
            guard let legalHoldClient: UserClient = selfUser.addLegalHoldClient(from: legalHoldRequest) else {
                return complete(error: .invalidState)
            }

            // 2) Create the Request
            guard let teamID = selfUser.teamIdentifier else {
                return complete(error: .userNotInTeam(selfUser))
            }

            guard let userID = selfUser.remoteIdentifier else {
                return complete(error: .invalidUser(selfUser))
            }

            var payload: [String: Any] = [:]
            payload["password"] = password

            let path = "/teams/\(teamID.transportString())/legalhold/\(userID.transportString())/approve"
            let request = ZMTransportRequest(path: path, method: .methodPUT, payload: payload as NSDictionary)

            // 3) Handle the Response
            request.add(ZMCompletionHandler(on: syncMoc, block: { response in
                guard response.httpStatus == 200 else {
                    legalHoldClient.deleteClientAndEndSession()
                    return complete(error: .invalidResponse)
                }

                selfUser.userDidAcceptLegalHoldRequest(legalHoldRequest)
                completionHandler(nil)
            }))

            // 4) Schedule the Request
            self.transportSession.enqueueOneTime(request)
        }
    }

}
