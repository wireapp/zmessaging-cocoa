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

/// Used to signal changes to the activation state
public protocol ActivationStatusDelegate: class {
    /// code activated sucessfully
    func emailActivated()

    /// Failed sending email verification code
    func emailActivationFailed(with error: Error)
}

final public class EmailActivationStatus {
    var phase : Phase = .none

    public weak var delegate: ActivationStatusDelegate?

    public func activate(email: String, code: String) {
        phase = .activate(email: email, code: code)
    }


    func handleError(_ error: Error) {
        switch phase {
        case .activate:
            delegate?.emailActivationFailed(with: error)
        case .none:
            break
        }
        phase = .none
    }

    func success() {
        switch phase {
        case .activate:
            delegate?.emailActivated()
        case .none:
            break
        }
        phase = .none
    }

    enum Phase {
        case activate(email: String, code: String)
        case none
    }
}

extension EmailActivationStatus.Phase: Equatable {
    static func ==(lhs: EmailActivationStatus.Phase, rhs: EmailActivationStatus.Phase) -> Bool {
        switch (lhs, rhs) {
        case let (.activate(l, lCode), .activate(r, rCode)):
            return l == r && lCode == rCode
        case (.none, .none):
            return true
        default: return false
        }
    }
}

/// Used for easily mock the object in tests
protocol ActivationStatusProtocol: class {
    func handleError(_ error: Error)
    func success()
    var phase: EmailActivationStatus.Phase { get }
}
