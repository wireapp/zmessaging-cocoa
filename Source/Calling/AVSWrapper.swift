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

public struct AVSCallMember : Hashable {
    
    let remoteId: UUID
    let audioEstablished: Bool
    let videoState: VideoState
    
    init?(wcallMember: wcall_member) {
        guard let remoteId = UUID(cString:wcallMember.userid) else { return nil }
        self.remoteId = remoteId
        audioEstablished = (wcallMember.audio_estab != 0)
        videoState = VideoState(rawValue: wcallMember.video_recv) ?? .stopped
    }
    
    init(userId : UUID, audioEstablished: Bool = false, videoState: VideoState = .stopped) {
        self.remoteId = userId
        self.audioEstablished = audioEstablished
        self.videoState = videoState
    }
    
    public var hashValue: Int {
        return remoteId.hashValue
    }
    
    public static func ==(lhs: AVSCallMember, rhs: AVSCallMember) -> Bool {
        return lhs.remoteId == rhs.remoteId
    }
}

public enum VideoState: Int32 {
    /// Sender is not sending video
    case stopped = 0
    /// Sender is sending video
    case started = 1
    /// Sender is sending video but currently has a bad connection
    case badConnection = 2
    /// Sender has paused the video
    case paused = 3
}

public enum AVSCallType: Int32 {
    case normal = 0
    case video = 1
    case audioOnly = 2
}

public enum AVSConversationType: Int32 {
    case oneToOne = 0
    case group = 1
    case conference = 2
}

public protocol AVSWrapperType {
    init(userId: UUID, clientId: String, observer: UnsafeMutableRawPointer?)
    func startCall(conversationId: UUID, callType: AVSCallType, conversationType: AVSConversationType, useCBR: Bool) -> Bool
    func answerCall(conversationId: UUID, callType: AVSCallType, useCBR: Bool) -> Bool
    func endCall(conversationId: UUID)
    func rejectCall(conversationId: UUID)
    func close()
    func received(callEvent: CallEvent)
    func setVideoState(conversationId: UUID, videoState: VideoState)
    func handleResponse(httpStatus: Int, reason: String, context: WireCallMessageToken)
    func members(in conversationId: UUID) -> [AVSCallMember]
    func update(callConfig: String?, httpStatusCode: Int)
}

typealias ConstantBitRateChangeHandler = @convention(c) (UnsafePointer<Int8>?, Int32, UnsafeMutableRawPointer?) -> Void
typealias VideoStateChangeHandler = @convention(c) (UnsafePointer<Int8>?, Int32, UnsafeMutableRawPointer?) -> Void
typealias IncomingCallHandler = @convention(c) (UnsafePointer<Int8>?, UInt32, UnsafePointer<Int8>?, Int32, Int32, UnsafeMutableRawPointer?) -> Void
typealias MissedCallHandler = @convention(c) (UnsafePointer<Int8>?, UInt32, UnsafePointer<Int8>?, Int32, UnsafeMutableRawPointer?) -> Void
typealias AnsweredCallHandler = @convention(c) (UnsafePointer<Int8>?, UnsafeMutableRawPointer?) -> Void
typealias DataChannelEstablishedHandler = @convention(c) (UnsafePointer<Int8>?, UnsafePointer<Int8>?, UnsafeMutableRawPointer?) -> Void
typealias CallEstablishedHandler = @convention(c) (UnsafePointer<Int8>?, UnsafePointer<Int8>?, UnsafeMutableRawPointer?) -> Void
typealias CloseCallHandler = @convention(c) (Int32, UnsafePointer<Int8>?, UInt32, UnsafePointer<Int8>?, UnsafeMutableRawPointer?) -> Void
typealias CallMetricsHandler = @convention(c) (UnsafePointer<Int8>?, UnsafePointer<Int8>?, UnsafeMutableRawPointer?) -> Void
typealias CallConfigRefreshHandler = @convention(c) (UnsafeMutableRawPointer?, UnsafeMutableRawPointer?) -> Int32
typealias CallReadyHandler = @convention(c) (Int32, UnsafeMutableRawPointer?) -> Void
typealias CallMessageSendHandler = @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<Int8>?, UnsafePointer<Int8>?, UnsafePointer<Int8>?, UnsafePointer<Int8>?, UnsafePointer<Int8>?, UnsafePointer<UInt8>?, Int, Int32, UnsafeMutableRawPointer?) -> Int32
typealias CallGroupChangedHandler = @convention(c) (UnsafePointer<Int8>?, UnsafeMutableRawPointer?) -> Void

protocol AVSValue {
    associatedtype AVSType
    init?(rawValue: AVSType)
}

extension Bool: AVSValue {
    init(rawValue: Int32) {
        self = rawValue == 1 ? true : false
    }
}

extension UUID: AVSValue {
    init?(rawValue: UnsafePointer<Int8>?) {
        self.init(cString: rawValue)
    }
}

extension VideoState: AVSValue {}

extension Date: AVSValue {
    init(rawValue: UInt32) {
        self = Date(timeIntervalSince1970: TimeInterval(rawValue))
    }
}

extension CallClosedReason: AVSValue {
    public init?(rawValue: Int32) {
        self.init(wcall_reason: rawValue)
    }
}

extension String: AVSValue {
    init?(rawValue: UnsafePointer<Int8>) {
        self.init(cString: rawValue)
    }
}

/// Wraps AVS calls for dependency injection and better testing
public class AVSWrapper : AVSWrapperType {

    private let handle : UnsafeMutableRawPointer

    // MARK: - C Callback Handlers

    let constantBitRateChangeHandler: ConstantBitRateChangeHandler = { _, enabledFlag, contextRef in
        AVSWrapper.withCallCenter(contextRef, enabledFlag) {
            $0.handleConstantBitRateChange(enabled: $1)
        }
    }

    let videoStateChangeHandler: VideoStateChangeHandler = { userId, state, contextRef in
        AVSWrapper.withCallCenter(contextRef, userId, state) {
            $0.handleVideoStateChange(userId: $1, newState: $2)
        }
    }

    let incomingCallHandler: IncomingCallHandler = { conversationId, messageTime, userId, isVideoCall, shouldRing, contextRef in
        AVSWrapper.withCallCenter(contextRef, conversationId, messageTime, userId, isVideoCall, shouldRing) {
            $0.handleIncomingCall(conversationId: $1, messageTime: $2, userId: $3, isVideoCall: $4, shouldRing: $5)
        }
    }

    let missedCallHandler: MissedCallHandler = { conversationId, messageTime, userId, isVideoCall, contextRef in
        AVSWrapper.withCallCenter(contextRef, conversationId, messageTime, userId, isVideoCall) {
            $0.handleMissedCall(conversationId: $1, messageTime: $2, userId: $3, isVideoCall: $4)
        }
    }

    let answeredCallHandler: AnsweredCallHandler = { conversationId, contextRef in
        AVSWrapper.withCallCenter(contextRef, conversationId) {
            $0.handleAnsweredCall(conversationId: $1)
        }
    }

    let dataChannelEstablishedHandler: DataChannelEstablishedHandler = { conversationId, userId, contextRef in
        AVSWrapper.withCallCenter(contextRef, conversationId, userId) {
            $0.handleDataChannelEstablishement(conversationId: $1, userId: $2)
        }
    }

    let establishedCallHandler: CallEstablishedHandler = { conversationId, userId, contextRef in
        AVSWrapper.withCallCenter(contextRef, conversationId, userId) {
            $0.handleEstablishedCall(conversationId: $1, userId: $2)
        }
    }

    let closedCallHandler: CloseCallHandler = { reason, conversationId, messageTime, userId, contextRef in
        AVSWrapper.withCallCenter(contextRef, reason, conversationId, messageTime, userId) {
            $0.handleCallEnd(reason: $1, conversationId: $2, messageTime: $3, userId: $4)
        }
    }

    let callMetricsHandler: CallMetricsHandler = { conversationId, metrics, contextRef in
        AVSWrapper.withCallCenter(contextRef, conversationId, metrics) {
            $0.handleCallMetrics(conversationId: $1, metrics: $2)
        }
    }

    let requestCallConfigHandler: CallConfigRefreshHandler = { handle, contextRef in
        zmLog.debug("AVS: requestCallConfigHandler \(String(describing: handle)) \(String(describing: contextRef))")
        return AVSWrapper.withCallCenter(contextRef) {
            $0.handleCallConfigRefreshRequest()
        }
    }

    let readyHandler: CallReadyHandler = { version, contextRef in
        AVSWrapper.withCallCenter(contextRef) {
            $0.setCallReady(version: version)
        }
    }

    let sendCallMessageHandler: CallMessageSendHandler = { token, conversationId, senderUserId, senderClientId, _, _, data, dataLength, _, contextRef in
        guard let token = token else {
            return EINVAL
        }

        let bytes = UnsafeBufferPointer<UInt8>(start: data, count: dataLength)
        let transformedData = Data(buffer: bytes)

        return AVSWrapper.withCallCenter(contextRef, conversationId, senderUserId, senderClientId) {
            $0.handleCallMessageRequest(token: token, conversationId: $1, senderUserId: $2, senderClientId: $3, data: transformedData)
        }
    }

    let groupMemberHandler: CallGroupChangedHandler = { conversationIdRef, contextRef in
        AVSWrapper.withCallCenter(contextRef, conversationIdRef) {
            $0.handleGroupMemberChange(conversationId: $1)
        }
    }

    // MARK: - 

    private static var initialize: () -> Void = {
        let resultValue = wcall_init()
        if resultValue != 0 {
            fatal("Failed to initialise AVS (error code: \(resultValue))")
        }
        return {}
    }()
    
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
        wcall_set_group_changed_handler(handle, groupMemberHandler, observer)
        wcall_set_media_stopped_handler(handle, mediaStoppedChangeHandler)
    }
    
    public func startCall(conversationId: UUID, callType: AVSCallType, conversationType: AVSConversationType, useCBR: Bool) -> Bool {
        let didStart = wcall_start(handle, conversationId.transportString(), callType.rawValue, conversationType.rawValue, useCBR ? 1 : 0)
        return didStart == 0
    }
    
    public func answerCall(conversationId: UUID, callType: AVSCallType, useCBR: Bool) -> Bool {
        let didAnswer = wcall_answer(handle, conversationId.transportString(), callType.rawValue, useCBR ? 1 : 0)
        return didAnswer == 0
    }
    
    public func endCall(conversationId: UUID) {
        wcall_end(handle, conversationId.transportString())
    }
    
    public func rejectCall(conversationId: UUID) {
        wcall_reject(handle, conversationId.transportString())
    }
    
    public func close() {
        wcall_destroy(handle)
    }
    
    public func setVideoState(conversationId: UUID, videoState: VideoState) {
        wcall_set_video_send_state(handle, conversationId.transportString(), videoState.rawValue)
    }
    
    public func handleResponse(httpStatus: Int, reason: String, context: WireCallMessageToken) {
        wcall_resp(handle, Int32(httpStatus), "", context)
    }
    
    public func received(callEvent: CallEvent) {
        callEvent.data.withUnsafeBytes { (bytes: UnsafePointer<UInt8>) in
            let currentTime = UInt32(callEvent.currentTimestamp.timeIntervalSince1970)
            let serverTime = UInt32(callEvent.serverTimestamp.timeIntervalSince1970)
            
            wcall_recv_msg(handle, bytes, callEvent.data.count, currentTime, serverTime, callEvent.conversationId.transportString(), callEvent.userId.transportString(), callEvent.clientId)
        }
    }
    
    public func update(callConfig: String?, httpStatusCode: Int) {
        wcall_config_update(handle, httpStatusCode == 200 ? 0 : EPROTO, callConfig ?? "")
    }
        
    public func members(in conversationId: UUID) -> [AVSCallMember] {
        guard let membersRef = wcall_get_members(handle, conversationId.transportString()) else { return [] }
        
        let cMembers = membersRef.pointee
        var callMembers = [AVSCallMember]()
        for i in 0..<cMembers.membc {
            guard let cMember = cMembers.membv?[Int(i)],
                let member = AVSCallMember(wcallMember: cMember)
                else { continue }
            callMembers.append(member)
        }
        wcall_free_members(membersRef)
        
        return callMembers
    }
}

extension AVSWrapper {

    @discardableResult
    static func withCallCenter(_ contextRef: UnsafeMutableRawPointer?, _ block: (WireCallCenterV3) -> Void) -> Int32 {
        guard let contextRef = contextRef else { return EINVAL }
        let callCenter = Unmanaged<WireCallCenterV3>.fromOpaque(contextRef).takeUnretainedValue()
        block(callCenter)
        return 0
    }

    @discardableResult
    static func withCallCenter<A1: AVSValue>(_ contextRef: UnsafeMutableRawPointer?, _ v1: A1.AVSType?, _ block: (WireCallCenterV3, A1) -> Void) -> Int32 {
        guard let contextRef = contextRef, let value1 = v1.flatMap(A1.init) else { return EINVAL }
        let callCenter = Unmanaged<WireCallCenterV3>.fromOpaque(contextRef).takeUnretainedValue()
        block(callCenter, value1)
        return 0
    }

    @discardableResult
    static func withCallCenter<A1: AVSValue, A2: AVSValue>(_ contextRef: UnsafeMutableRawPointer?, _ v1: A1.AVSType?, _ v2: A2.AVSType?, _ block: (WireCallCenterV3, A1, A2) -> Void) -> Int32 {
        guard let contextRef = contextRef, let value1 = v1.flatMap(A1.init), let value2 = v2.flatMap(A2.init) else { return EINVAL }
        let callCenter = Unmanaged<WireCallCenterV3>.fromOpaque(contextRef).takeUnretainedValue()
        block(callCenter, value1, value2)
        return 0
    }

    @discardableResult
    static func withCallCenter<A1: AVSValue, A2: AVSValue, A3: AVSValue>(_ contextRef: UnsafeMutableRawPointer?, _ v1: A1.AVSType?, _ v2: A2.AVSType?, _ v3: A3.AVSType?, _ block: (WireCallCenterV3, A1, A2, A3) -> Void) -> Int32 {
        guard let contextRef = contextRef, let value1 = v1.flatMap(A1.init), let value2 = v2.flatMap(A2.init), let value3 = v3.flatMap(A3.init) else { return EINVAL }
        let callCenter = Unmanaged<WireCallCenterV3>.fromOpaque(contextRef).takeUnretainedValue()
        block(callCenter, value1, value2, value3)
        return 0
    }

    @discardableResult
    static func withCallCenter<A1: AVSValue, A2: AVSValue, A3: AVSValue, A4: AVSValue>(_ contextRef: UnsafeMutableRawPointer?, _ v1: A1.AVSType?, _ v2: A2.AVSType?, _ v3: A3.AVSType?, _ v4: A4.AVSType?, _ block: (WireCallCenterV3, A1, A2, A3, A4) -> Void) -> Int32 {
        guard let contextRef = contextRef, let value1 = v1.flatMap(A1.init), let value2 = v2.flatMap(A2.init), let value3 = v3.flatMap(A3.init), let value4 = v4.flatMap(A4.init) else { return EINVAL }
        let callCenter = Unmanaged<WireCallCenterV3>.fromOpaque(contextRef).takeUnretainedValue()
        block(callCenter, value1, value2, value3, value4)
        return 0
    }

    @discardableResult
    static func withCallCenter<A1: AVSValue, A2: AVSValue, A3: AVSValue, A4: AVSValue, A5: AVSValue>(_ contextRef: UnsafeMutableRawPointer?, _ v1: A1.AVSType?, _ v2: A2.AVSType?, _ v3: A3.AVSType?, _ v4: A4.AVSType?, _ v5: A5.AVSType?, _ block: (WireCallCenterV3, A1, A2, A3, A4, A5) -> Void) -> Int32 {
        guard let contextRef = contextRef, let value1 = v1.flatMap(A1.init), let value2 = v2.flatMap(A2.init), let value3 = v3.flatMap(A3.init), let value4 = v4.flatMap(A4.init), let value5 = v5.flatMap(A5.init) else { return EINVAL }
        let callCenter = Unmanaged<WireCallCenterV3>.fromOpaque(contextRef).takeUnretainedValue()
        block(callCenter, value1, value2, value3, value4, value5)
        return 0
    }

    @discardableResult
    static func withCallCenter<A1: AVSValue, A2: AVSValue, A3: AVSValue, A4: AVSValue, A5: AVSValue, A6: AVSValue>(_ contextRef: UnsafeMutableRawPointer?, _ v1: A1.AVSType?, _ v2: A2.AVSType?, _ v3: A3.AVSType?, _ v4: A4.AVSType?, _ v5: A5.AVSType?, _ v6: A6.AVSType?, _ block: (WireCallCenterV3, A1, A2, A3, A4, A5, A6) -> Void) -> Int32 {
        guard let contextRef = contextRef, let value1 = v1.flatMap(A1.init), let value2 = v2.flatMap(A2.init), let value3 = v3.flatMap(A3.init), let value4 = v4.flatMap(A4.init), let value5 = v5.flatMap(A5.init), let value6 = v6.flatMap(A6.init) else { return EINVAL }
        let callCenter = Unmanaged<WireCallCenterV3>.fromOpaque(contextRef).takeUnretainedValue()
        block(callCenter, value1, value2, value3, value4, value5, value6)
        return 0
    }

}
