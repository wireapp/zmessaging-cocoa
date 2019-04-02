//
// Wire
// Copyright (C) 2018 Wire Swiss GmbH
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
import avs

/**
 * Reasons why a call can be received correctly.
 */

public enum CallReceivedResult : Int32 {
    
    /// Impossible to receive a call due to incompatible protocol (e.g. older versions)
    case unknownProtocol
    /// Call is ok
    case ok
    /// Call was not received for an unknown reason. This is most likely a bug.
    case unknown
    
    // MARK: - Briding
    
    /**
     * Creates the call error from the AVS flag.
     * - parameter wcall_error: The flag
     * - returns: The decoded error, or `.unknown` if the flag couldn't be processed.
     */
    
    init(wcall_error: Int32) {
        switch wcall_error {
        case 0:
            self = .ok
        case WCALL_ERROR_UNKNOWN_PROTOCOL:
            self = .unknownProtocol
        default:
            self = .unknown
        }
    }
    
    /// The raw flag for the call end.
    var wcall_error : Int32 {
        switch self {
        case .unknownProtocol:
            return WCALL_REASON_NORMAL
        case .ok:
            return 0
        case .unknown:
            return -1
        }
    }
}
