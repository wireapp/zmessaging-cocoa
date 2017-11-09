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


final class EmailActivationStrategy : NSObject {
    let codeVerificationStatus: ActivationStatusProtocol
    var codeActivationSync: ZMSingleRequestSync!

    init(status : ActivationStatusProtocol, groupQueue: ZMSGroupQueue) {
        codeVerificationStatus = status
        super.init()
        codeActivationSync = ZMSingleRequestSync(singleRequestTranscoder: self, groupQueue: groupQueue)
    }
}

extension EmailActivationStrategy : ZMSingleRequestTranscoder {
    func request(for sync: ZMSingleRequestSync) -> ZMTransportRequest? {
        let currentStatus = codeVerificationStatus
        var payload : [String: Any]
        var path : String

        switch (currentStatus.phase) {
        case let .activate(email: email, code: code):
            path = "/activate"
            payload = ["email": email,
                       "code": code,
                       "dryrun": true]
        default:
            fatal("Generating request for invalid phase: \(currentStatus.phase)")
        }

        return ZMTransportRequest(path: path, method: .methodPOST, payload: payload as ZMTransportData)
    }

    func didReceive(_ response: ZMTransportResponse, forSingleRequest sync: ZMSingleRequestSync) {
        if response.result == .success {
            codeVerificationStatus.success()
        } else {
            let error = NSError.invalidActivationCode(with: response) ??
                NSError.userSessionErrorWith(.unknownError, userInfo: [:])

            codeVerificationStatus.handleError(error)
        }
    }

}

extension EmailActivationStrategy : RequestStrategy {
    func nextRequest() -> ZMTransportRequest? {
        switch (codeVerificationStatus.phase) {
        case .activate:
            codeActivationSync.readyForNextRequestIfNotBusy()
            return codeActivationSync.nextRequest()
        default:
            return nil
        }
    }
}
