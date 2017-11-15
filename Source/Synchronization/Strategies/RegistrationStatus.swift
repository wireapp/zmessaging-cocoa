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
    /// Team was successfully created
    func teamRegistered()

    /// Team creation error
    func teamRegistrationFailed(with error: Error)

    /// Verify email should be sent with code
    func emailActivationCodeSent()

    /// Failed sending email verification code
    func emailActivationCodeSendingFailed(with error: Error)

    /// code activated sucessfully
    func emailActivationCodeValidated()

    /// Failed sending email verification code
    func emailActivationCodeValidationFailed(with error: Error)
}

// Empty default implementations to let users of the protocol implement only subset of methods
extension RegistrationStatusDelegate {
    func teamRegistered() {}
    func teamRegistrationFailed(with error: Error) {}
    func emailActivationCodeSent() {}
    func emailActivationCodeSendingFailed(with error: Error) {}
    func emailActivationCodeValidated() {}
    func emailActivationCodeValidationFailed(with error: Error) {}
}

final public class RegistrationStatus {
    var phase : Phase = .none

    public weak var delegate: RegistrationStatusDelegate?

    /// Used to start email activation process by sending an email with a
    /// code to supplied address.
    ///
    /// - Parameter email: email address to send activation code to
    public func sendActivationCode(to email: String) {
        phase = .sendActivationCode(email: email)
        RequestAvailableNotification.notifyNewRequestsAvailable(nil)
    }

    /// For checking the activation code (received form email sent from backend) with email
    ///
    /// - Parameter email: email address to check activation code of
    ///  - Parameter code: activation code to check
    public func checkActivationCode(email: String, code: String) {
        phase = .checkActivationCode(email: email, code: code)
        RequestAvailableNotification.notifyNewRequestsAvailable(nil)
    }

    /// Used to create a team. Also creates a new administrator account
    ///
    /// - Parameter team: team object containing all information needed
    public func create(team: TeamToRegister) {
        phase = .createTeam(team: team)
        RequestAvailableNotification.notifyNewRequestsAvailable(nil)
    }

    func handleError(_ error: Error) {
        switch self.phase {
        case .sendActivationCode:
            self.delegate?.emailActivationCodeSendingFailed(with: error)
        case .checkActivationCode:
            self.delegate?.emailActivationCodeValidationFailed(with: error)
        case .createTeam:
            delegate?.teamRegistrationFailed(with: error)
        case .none:
            break
        }
        self.phase = .none
    }

    func success() {
        switch self.phase {
        case .sendActivationCode:
            self.delegate?.emailActivationCodeSent()
        case .checkActivationCode:
            self.delegate?.emailActivationCodeValidated()
        case .createTeam:
            delegate?.teamRegistered()
        case .none:
            break
        }
        self.phase = .none
    }

    enum Phase {
        case sendActivationCode(email: String)
        case checkActivationCode(email: String, code: String)
        case createTeam(team: TeamToRegister)
        case none
    }
}

extension RegistrationStatus.Phase: Equatable {
    static func ==(lhs: RegistrationStatus.Phase, rhs: RegistrationStatus.Phase) -> Bool {
        switch (lhs, rhs) {
        case let (.sendActivationCode(l), .sendActivationCode(r)):
            return l == r
        case let (.checkActivationCode(l, lCode), .checkActivationCode(r, rCode)):
            return l == r && lCode == rCode
        case let (.createTeam(l), .createTeam(r)): return l == r
        case (.none, .none): return true
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

extension RegistrationStatus: RegistrationStatusProtocol {

}
