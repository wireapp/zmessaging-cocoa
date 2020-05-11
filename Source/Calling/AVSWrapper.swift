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
import avs

private let zmLog = ZMSLog(tag: "calling")

/**
 * The type of objects that can provide an interface to calling APIs.
 * This provides strong typing, dependency injection and better testing.
 */

public protocol AVSWrapperType {
    init(userId: UUID, clientId: String, observer: UnsafeMutableRawPointer?)
    func startCall(conversationId: UUID, callType: AVSCallType, conversationType: AVSConversationType, useCBR: Bool) -> Bool
    func answerCall(conversationId: UUID, callType: AVSCallType, useCBR: Bool) -> Bool
    func endCall(conversationId: UUID)
    func rejectCall(conversationId: UUID)
    func close()
    func received(callEvent: CallEvent) -> CallError?
    func setVideoState(conversationId: UUID, videoState: VideoState)
    func handleResponse(httpStatus: Int, reason: String, context: WireCallMessageToken)
    func update(callConfig: String?, httpStatusCode: Int)
    var muted: Bool { get set }
}


/**
 * An object that provides an interface to the AVS APIs.
 */

public class AVSWrapper: AVSWrapperType {

    /// The wrapped `wcall` instance.
    private let handle: UInt32

    // MARK: - Initialization

    /// Initializes avs.
    private static var initialize: () -> Void = {
        let resultValue = wcall_init(WCALL_ENV_DEFAULT)
        if resultValue != 0 {
            fatal("Failed to initialise AVS (error code: \(resultValue))")
        }
        return {}
    }()

    /**
     * Creates the wrapper around `wcall`.
     * - parameter userId: The identifier of the user that owns the calling center.
     * - parameter clientId: The identifier of the current client (this device).
     * - parameter observer: The raw pointer to the object that will receive events from AVS.
     * This must be a pointer to a `WireCallCenterV3` object. If it isn't, the notifications
     * won't be handled.
     */

    required public init(userId: UUID, clientId: String, observer: UnsafeMutableRawPointer?) {
        AVSWrapper.initialize()
        
        handle = wcall_create(userId.transportString(),
                              clientId,
                              readyHandler,
                              sendCallMessageHandler,
                              incomingCallHandler,
                              missedCallHandler,
                              answeredCallHandler,
                              establishedCallHandler,
                              closedCallHandler,
                              callMetricsHandler,
                              requestCallConfigHandler,
                              constantBitRateChangeHandler,
                              videoStateChangeHandler,
                              observer)

        wcall_set_data_chan_estab_handler(handle, dataChannelEstablishedHandler)
        let timerIntervalInSeconds: Int32 = 5
        wcall_set_network_quality_handler(handle, networkQualityHandler, timerIntervalInSeconds, observer)
        wcall_set_media_stopped_handler(handle, mediaStoppedChangeHandler)
        wcall_set_mute_handler(handle, muteChangeHandler, observer)
        wcall_set_participant_changed_handler(handle, callParticipantHandler, observer)
    }

    // MARK: - Convenience Methods
    
    public var muted: Bool {
        get {
            return wcall_get_mute(handle) != 0
        }
        set {
            wcall_set_mute(handle, newValue ? 1 : 0)
        }
    }

    /// Requests AVS to initiate a call.
    public func startCall(conversationId: UUID, callType: AVSCallType, conversationType: AVSConversationType, useCBR: Bool) -> Bool {
        let didStart = wcall_start(handle, conversationId.transportString(), callType.rawValue, conversationType.rawValue, useCBR ? 1 : 0)
        return didStart == 0
    }

    /// Marks the call as answered in AVS.
    public func answerCall(conversationId: UUID, callType: AVSCallType, useCBR: Bool) -> Bool {
        let didAnswer = wcall_answer(handle, conversationId.transportString(), callType.rawValue, useCBR ? 1 : 0)
        return didAnswer == 0
    }

    /// Marks the call as ended in AVS.
    public func endCall(conversationId: UUID) {
        wcall_end(handle, conversationId.transportString())
    }

    /// Marks the call as rejected in AVS.
    public func rejectCall(conversationId: UUID) {
        wcall_reject(handle, conversationId.transportString())
    }

    /// Closes the `wcall` handler. This object becomes invalid after this method is called.
    public func close() {
        wcall_destroy(handle)
    }

    /// Changes the video state in AVS for the given conversation.
    public func setVideoState(conversationId: UUID, videoState: VideoState) {
        wcall_set_video_send_state(handle, conversationId.transportString(), videoState.rawValue)
    }

    /// Passes the response of the calling config request to AVS.
    public func handleResponse(httpStatus: Int, reason: String, context: WireCallMessageToken) {
        wcall_resp(handle, Int32(httpStatus), "", context)
    }

    /// Notifies AVS that we received a remote event.
    public func received(callEvent: CallEvent) -> CallError? {
        var result: CallError? = nil

        callEvent.data.withUnsafeBytes { (pointer: UnsafeRawBufferPointer) in
            guard let bytes = pointer.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            let currentTime = UInt32(callEvent.currentTimestamp.timeIntervalSince1970)
            let serverTime = UInt32(callEvent.serverTimestamp.timeIntervalSince1970)
            zmLog.debug("wcall_recv_msg: currentTime = \(currentTime), serverTime = \(serverTime)")
            result = CallError(wcall_error: wcall_recv_msg(handle, bytes, callEvent.data.count, currentTime, serverTime, callEvent.conversationId.transportString(), callEvent.userId.transportString(), callEvent.clientId))
        }

        return result
    }

    /// Updates the calling config.
    public func update(callConfig: String?, httpStatusCode: Int) {
        wcall_config_update(handle, httpStatusCode == 200 ? 0 : EPROTO, callConfig ?? "")
    }

    // MARK: - C Callback Handlers

    private let constantBitRateChangeHandler: ConstantBitRateChangeHandler = { _, _, enabledFlag, contextRef in
        AVSWrapper.withCallCenter(contextRef, enabledFlag) {
            $0.handleConstantBitRateChange(enabled: $1)
        }
    }

    private let videoStateChangeHandler: VideoStateChangeHandler = { conversationId, userId, clientId, state, contextRef in
        AVSWrapper.withCallCenter(contextRef, userId, clientId, state) {
            $0.handleVideoStateChange(userId: $1, clientId: $2, newState: $3)
        }
    }

    private let incomingCallHandler: IncomingCallHandler = { conversationId, messageTime, userId, clientId, isVideoCall, shouldRing, contextRef in
        AVSWrapper.withCallCenter(contextRef, conversationId, messageTime, userId, isVideoCall, shouldRing) {
            $0.handleIncomingCall(conversationId: $1, messageTime: $2, userId: $3, isVideoCall: $4, shouldRing: $5)
        }
    }

    private let missedCallHandler: MissedCallHandler = { conversationId, messageTime, userId, clientId, isVideoCall, contextRef in
        zmLog.debug("missedCallHandler: messageTime = \(messageTime)")
        let nonZeroMessageTime: UInt32 = messageTime != 0 ? messageTime : UInt32(Date().timeIntervalSince1970)

        AVSWrapper.withCallCenter(contextRef, conversationId, nonZeroMessageTime, userId, isVideoCall) {
            $0.handleMissedCall(conversationId: $1, messageTime: $2, userId: $3, isVideoCall: $4)
        }
    }

    private let answeredCallHandler: AnsweredCallHandler = { conversationId, contextRef in
        AVSWrapper.withCallCenter(contextRef, conversationId) {
            $0.handleAnsweredCall(conversationId: $1)
        }
    }

    private let dataChannelEstablishedHandler: DataChannelEstablishedHandler = { conversationId, userId, clientId, contextRef in
        AVSWrapper.withCallCenter(contextRef, conversationId, userId) {
            $0.handleDataChannelEstablishement(conversationId: $1, userId: $2)
        }
    }

    private let establishedCallHandler: CallEstablishedHandler = { conversationId, userId, clientId, contextRef in
        AVSWrapper.withCallCenter(contextRef, conversationId, userId) {
            $0.handleEstablishedCall(conversationId: $1, userId: $2)
        }
    }

    private let closedCallHandler: CloseCallHandler = { reason, conversationId, messageTime, userId, clientId, contextRef in
        zmLog.debug("closedCallHandler: messageTime = \(messageTime)")
        let nonZeroMessageTime: UInt32 = messageTime != 0 ? messageTime : UInt32(Date().timeIntervalSince1970)

        AVSWrapper.withCallCenter(contextRef, reason, conversationId, nonZeroMessageTime) {
            $0.handleCallEnd(reason: $1, conversationId: $2, messageTime: $3, userId: UUID(rawValue: userId))
        }
    }

    private let callMetricsHandler: CallMetricsHandler = { conversationId, metrics, contextRef in
        AVSWrapper.withCallCenter(contextRef, conversationId, metrics) {
            $0.handleCallMetrics(conversationId: $1, metrics: $2)
        }
    }

    private let requestCallConfigHandler: CallConfigRefreshHandler = { handle, contextRef in
        zmLog.debug("AVS: requestCallConfigHandler \(String(describing: handle)) \(String(describing: contextRef))")
        return AVSWrapper.withCallCenter(contextRef) {
            $0.handleCallConfigRefreshRequest()
        }
    }

    private let readyHandler: CallReadyHandler = { version, contextRef in
        AVSWrapper.withCallCenter(contextRef) {
            $0.setCallReady(version: version)
        }
    }

    private let sendCallMessageHandler: CallMessageSendHandler = { token, conversationId, senderUserId, senderClientId, _, _, data, dataLength, _, contextRef in
        guard let token = token else {
            return EINVAL
        }

        let bytes = UnsafeBufferPointer<UInt8>(start: data, count: dataLength)
        let transformedData = Data(buffer: bytes)

        return AVSWrapper.withCallCenter(contextRef, conversationId, senderUserId, senderClientId) {
            $0.handleCallMessageRequest(token: token, conversationId: $1, senderUserId: $2, senderClientId: $3, data: transformedData)
        }
    }
    
    private let callParticipantHandler: CallParticipantChangedHandler = { conversationIdRef, json, contextRef in
        AVSWrapper.withCallCenter(contextRef, json, conversationIdRef) {
            $0.handleParticipantChange(conversationId: $2, data: $1)
        }
    }

    private let mediaStoppedChangeHandler: MediaStoppedChangeHandler = { conversationIdRef, contextRef in
        AVSWrapper.withCallCenter(contextRef, conversationIdRef) {
            $0.handleMediaStopped(conversationId: $1)
        }
    }

    private let networkQualityHandler: NetworkQualityChangeHandler = { conversationIdRef, userIdRef, clientId, quality, rtt, uplinkLoss, downlinkLoss, contextRef in
        AVSWrapper.withCallCenter(contextRef, conversationIdRef, userIdRef, quality, { (callCenter, conversationId, userId, quality) in
            callCenter.handleNetworkQualityChange(conversationId: conversationId, userId: userId, quality: quality)
        })
    }

    private let muteChangeHandler: MuteChangeHandler = { muted, contextRef in
        AVSWrapper.withCallCenter(contextRef, muted) {
            $0.handleMuteChange(muted: $1)
        }
    }
}
