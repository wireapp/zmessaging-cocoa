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

import Foundation

///FIXME: rename and save to new file
class RegistrationStatus {
    var phase : Phase = .none

    /// for UI to verity the email
    ///
    /// - Parameter email: <#email description#>
    func verify(email: String) {
        ///TODO: set the phrase to verifyEmail
    }

    enum Phase {
        case verify(email: String)
        case none
    }
}

class EmailVerificationStrategy : NSObject {
    let registrationStatus: RegistrationStatus
    var singleRequestSync: ZMSingleRequestSync!

    init(status : RegistrationStatus, groupQueue: ZMSGroupQueue) {
        registrationStatus = status

        super.init()

        singleRequestSync = ZMSingleRequestSync(singleRequestTranscoder: self, groupQueue: groupQueue)

    }

}

extension EmailVerificationStrategy : ZMSingleRequestTranscoder {
    func request(for sync: ZMSingleRequestSync) -> ZMTransportRequest? {
        let currentStatus = registrationStatus
        var payload : [String: Any]
        var path : String

        switch (currentStatus.phase) {
        case let .verify(email: email):
            path = "/activate/send"
            payload = ["email": email,
                       "locale": NSLocale.formattedLocaleIdentifier()!]
        default:
            return nil
        }

        return ZMTransportRequest(path: path, method: .methodPOST, payload: payload  as ZMTransportData)
    }

    func didReceive(_ response: ZMTransportResponse, forSingleRequest sync: ZMSingleRequestSync) {
        ///TODO: error/success handling
    }

}

extension EmailVerificationStrategy : RequestStrategy {
    func nextRequest() -> ZMTransportRequest? {
        let currentStatus = registrationStatus

        switch (currentStatus.phase) {
        case let .verify(email: email):
            return singleRequestSync.nextRequest()
        default:
            return nil
        }

    }


}
