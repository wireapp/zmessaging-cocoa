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

/// Used to signal changes to the registration state
public protocol RegistrationStatusDelegate: class {
    /// Verify email should be sent with code
    func emailVerificationCodeSent()

    /// Failed sending email verification code
    func emailVerificationCodeSendingFailed(with error: Error)
}

final public class RegistrationStatus {
    var phase : Phase = .none

    public weak var delegate: RegistrationStatusDelegate?

    /// Used to start email verificiation process by sending an email with verification
    /// code to supplied address.
    ///
    /// - Parameter email: email address to send verification code to
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

/// Used for easily mock the object in tests
protocol RegistrationStatusProtocol: class {
    func handleError(_ error: Error)
    func success()
    var phase: RegistrationStatus.Phase { get }
}
