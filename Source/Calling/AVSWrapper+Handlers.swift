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

/// Equivalent of `wcall_audio_cbr_change_h`.
typealias ConstantBitRateChangeHandler = @convention(c) (UnsafePointer<Int8>?, Int32, UnsafeMutableRawPointer?) -> Void

/// Equivalent of `wcall_video_state_change_h`.
typealias VideoStateChangeHandler = @convention(c) (UnsafePointer<Int8>?, Int32, UnsafeMutableRawPointer?) -> Void

/// Equivalent of `wcall_incoming_h`.
typealias IncomingCallHandler = @convention(c) (UnsafePointer<Int8>?, UInt32, UnsafePointer<Int8>?, Int32, Int32, UnsafeMutableRawPointer?) -> Void

/// Equivalent of `wcall_missed_h`.
typealias MissedCallHandler = @convention(c) (UnsafePointer<Int8>?, UInt32, UnsafePointer<Int8>?, Int32, UnsafeMutableRawPointer?) -> Void

/// Equivalent of `wcall_answered_h`.
typealias AnsweredCallHandler = @convention(c) (UnsafePointer<Int8>?, UnsafeMutableRawPointer?) -> Void

/// Equivalent of `wcall_data_chan_estab_h`.
typealias DataChannelEstablishedHandler = @convention(c) (UnsafePointer<Int8>?, UnsafePointer<Int8>?, UnsafeMutableRawPointer?) -> Void

/// Equivalent of `wcall_estab_h`.
typealias CallEstablishedHandler = @convention(c) (UnsafePointer<Int8>?, UnsafePointer<Int8>?, UnsafeMutableRawPointer?) -> Void

/// Equivalent of `wcall_close_h`.
typealias CloseCallHandler = @convention(c) (Int32, UnsafePointer<Int8>?, UInt32, UnsafePointer<Int8>?, UnsafeMutableRawPointer?) -> Void

/// Equivalent of `wcall_metrics_h`.
typealias CallMetricsHandler = @convention(c) (UnsafePointer<Int8>?, UnsafePointer<Int8>?, UnsafeMutableRawPointer?) -> Void

/// Equivalent of `wcall_config_req_h`.
typealias CallConfigRefreshHandler = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Int32

/// Equivalent of `wcall_ready_h`.
typealias CallReadyHandler = @convention(c) (Int32, UnsafeMutableRawPointer?) -> Void

/// Equivalent of `wcall_send_h`.
typealias CallMessageSendHandler = @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<Int8>?, UnsafePointer<Int8>?, UnsafePointer<Int8>?, UnsafePointer<Int8>?, UnsafePointer<Int8>?, UnsafePointer<UInt8>?, Int, Int32, UnsafeMutableRawPointer?) -> Int32

/// Equivalent of `wcall_group_changed_h`.
typealias CallGroupChangedHandler = @convention(c) (UnsafePointer<Int8>?, UnsafeMutableRawPointer?) -> Void

/// Equivalent of `wcall_media_stopped_h`.
typealias MediaStoppedChangeHandler = @convention(c) (UnsafePointer<Int8>?, UnsafeMutableRawPointer?) -> Void

/// Equivalent of `wcall_network_quality_h`.
typealias NetworkQualityChangeHandler = @convention(c) (UnsafePointer<Int8>?, UnsafePointer<Int8>?, Int32, Int32, Int32, Int32, UnsafeMutableRawPointer?) -> Void
