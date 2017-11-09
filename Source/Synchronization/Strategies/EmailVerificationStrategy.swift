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

public protocol RegistrationStatusDelegate: class {
    func emailVerificationCodeSent()
    func emailVerificationCodeSendingFailed(with error: Error)
}

///FIXME: rename and save to new file
final public class RegistrationStatus {
    var phase : Phase = .none

    public weak var delegate: RegistrationStatusDelegate?

    /// for UI to verify the email
    ///
    /// - Parameter email: email to verify
    public func verify(email: String) {
        phase = .verify(email: email)
    }

    func handleError(_ error: Error) {
        switch phase {
        case .verify:
            delegate?.emailVerificationCodeSendingFailed(with: error)
        case .none:
            break
        }
        phase = .none
    }

    func success() {
        switch phase {
        case .verify:
            delegate?.emailVerificationCodeSent()
        case .none:
            break
        }
        phase = .none
    }

    enum Phase {
        case verify(email: String)
        case none
    }
}

extension RegistrationStatus.Phase: Equatable {
    static func ==(lhs: RegistrationStatus.Phase, rhs: RegistrationStatus.Phase) -> Bool {
        switch (lhs, rhs) {
        case let (.verify(l), .verify(r)): return l == r
        case (.none, .none):
            return true
        default: return false
        }
    }
}

protocol RegistrationStatusProtocol: class {
    func handleError(_ error: Error)
    func success()
    var phase: RegistrationStatus.Phase { get }
}

final class EmailVerificationStrategy : NSObject {
    let registrationStatus: RegistrationStatusProtocol
    var codeSendingSync: ZMSingleRequestSync!

    init(status : RegistrationStatusProtocol, groupQueue: ZMSGroupQueue) {
        registrationStatus = status
        super.init()
        codeSendingSync = ZMSingleRequestSync(singleRequestTranscoder: self, groupQueue: groupQueue)
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

        return ZMTransportRequest(path: path, method: .methodPOST, payload: payload as ZMTransportData)
    }

    func didReceive(_ response: ZMTransportResponse, forSingleRequest sync: ZMSingleRequestSync) {
        if response.result == .permanentError {
            let error = NSError.blacklistedEmail(with: response) ??
                NSError.keyExistsError(with: response) ??
                NSError.invalidEmail(with: response) ??
                NSError.userSessionErrorWith(.unknownError, userInfo: [:])
            registrationStatus.handleError(error)
        } else {
            registrationStatus.success()
        }
    }

}

extension EmailVerificationStrategy : RequestStrategy {
    func nextRequest() -> ZMTransportRequest? {
        let currentStatus = registrationStatus

        switch (currentStatus.phase) {
        case .verify(email: _):
            codeSendingSync.readyForNextRequestIfNotBusy()
            return codeSendingSync.nextRequest()
        default:
            return nil
        }

    }


}
