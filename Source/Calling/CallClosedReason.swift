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

public enum CallClosedReason : Int32 {
    /// Ongoing call was closed by remote or self user
    case normal
    /// Incoming call was canceled by remote
    case canceled
    /// Incoming call was answered on another device
    case anweredElsewhere
    /// Outgoing call timed out
    case timeout
    /// Ongoing call lost media and was closed
    case lostMedia
    /// Call was closed because of internal error in AVS
    case internalError
    /// Call was closed due to a input/output error (couldn't access microphone)
    case inputOutputError
    /// Call left by the selfUser but continues until everyone else leaves or AVS closes it
    case stillOngoing
    /// Call was dropped due to the security level degrading
    case securityDegraded
    /// Call was closed for an unknown reason. This is most likely a bug.
    case unknown

    init(wcall_reason: Int32) {
        switch wcall_reason {
        case WCALL_REASON_NORMAL:
            self = .normal
        case WCALL_REASON_CANCELED:
            self = .canceled
        case WCALL_REASON_ANSWERED_ELSEWHERE:
            self = .anweredElsewhere
        case WCALL_REASON_TIMEOUT:
            self = .timeout
        case WCALL_REASON_LOST_MEDIA:
            self = .lostMedia
        case WCALL_REASON_ERROR:
            self = .internalError
        case WCALL_REASON_IO_ERROR:
            self = .inputOutputError
        case WCALL_REASON_STILL_ONGOING:
            self = .stillOngoing
        default:
            self = .unknown
        }
    }

    var wcall_reason : Int32 {
        switch self {
        case .normal:
            return WCALL_REASON_NORMAL
        case .canceled:
            return WCALL_REASON_CANCELED
        case .anweredElsewhere:
            return WCALL_REASON_ANSWERED_ELSEWHERE
        case .timeout:
            return WCALL_REASON_TIMEOUT
        case .lostMedia:
            return WCALL_REASON_LOST_MEDIA
        case .internalError:
            return WCALL_REASON_ERROR
        case .inputOutputError:
            return WCALL_REASON_IO_ERROR
        case .stillOngoing:
            return WCALL_REASON_STILL_ONGOING
        case .securityDegraded:
            return WCALL_REASON_ERROR
        case .unknown:
            return WCALL_REASON_ERROR
        }
    }
}
