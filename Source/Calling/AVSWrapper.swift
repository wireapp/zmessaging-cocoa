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

/// Wraps AVS calls for dependency injection and better testing
public class AVSWrapper : AVSWrapperType {

    private let handle : UnsafeMutableRawPointer
    
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
