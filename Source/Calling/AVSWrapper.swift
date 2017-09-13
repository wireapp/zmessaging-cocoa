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

public protocol AVSWrapperType {
    init(userId: UUID, clientId: String, observer: UnsafeMutableRawPointer?)
    func startCall(conversationId: UUID, video: Bool, isGroup: Bool) -> Bool
    func answerCall(conversationId: UUID) -> Bool
    func endCall(conversationId: UUID)
    func rejectCall(conversationId: UUID)
    func close()
    func received(callEvent: CallEvent)
    func toggleVideo(conversationID: UUID, active: Bool)
    func setVideoSendActive(userId: UUID, active: Bool)
    func enableAudioCbr(shouldUseCbr: Bool)
    func handleResponse(httpStatus: Int, reason: String, context: WireCallMessageToken)
    func members(in conversationId: UUID) -> [CallMember]
    func update(callConfig: String?, httpStatusCode: Int)
}

/// Wraps AVS calls for dependency injection and better testing
public class AVSWrapper : AVSWrapperType {
    
    private static var isInitialized = false
    private let handle : UnsafeMutableRawPointer
    
    required public init(userId: UUID, clientId: String, observer: UnsafeMutableRawPointer?) {
        
        if !AVSWrapper.isInitialized {
            let resultValue = wcall_init()
            if resultValue != 0 {
                fatal("Failed to initialise AVS (error code: \(resultValue))")
            }
        }
        
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
                              observer)
        
        wcall_set_video_state_handler(handle, { (state, _) in
            guard let state = ReceivedVideoState(rawValue: UInt(state)) else { return }
            
            DispatchQueue.main.async {
                WireCallCenterV3VideoNotification(receivedVideoState: state).post()
            }
        })
        
        wcall_set_data_chan_estab_handler(handle, dataChannelEstablishedHandler)
        wcall_set_group_changed_handler(handle, groupMemberHandler, observer)

        wcall_set_audio_cbr_enabled_handler(handle, { _ in
            DispatchQueue.main.async {
                WireCallCenterCBRCallNotification().post()
            }
        })
    }
    
    public func startCall(conversationId: UUID, video: Bool, isGroup: Bool) -> Bool {
        let didStart = wcall_start(handle, conversationId.transportString(), video ? 1 : 0, isGroup ? 1 : 0)
        return didStart == 0
    }
    
    public func answerCall(conversationId: UUID) -> Bool {
        let didAnswer = wcall_answer(handle, conversationId.transportString())
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
    
    public func setVideoSendActive(userId: UUID, active: Bool) {
        wcall_set_video_send_active(handle, userId.transportString(), active ? 1 : 0)
    }
    
    public func enableAudioCbr(shouldUseCbr: Bool) {
        wcall_enable_audio_cbr(handle, shouldUseCbr ? 1 : 0)
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
    
    public func toggleVideo(conversationID: UUID, active: Bool) {
        wcall_set_video_send_active(handle, conversationID.transportString(), active ? 1 : 0)
    }
    
    public func members(in conversationId: UUID) -> [CallMember] {
        guard let membersRef = wcall_get_members(handle, conversationId.transportString()) else { return [] }
        
        let cMembers = membersRef.pointee
        var callMembers = [CallMember]()
        for i in 0..<cMembers.membc {
            guard let cMember = cMembers.membv?[Int(i)],
                let member = CallMember(wcallMember: cMember)
                else { continue }
            callMembers.append(member)
        }
        wcall_free_members(membersRef)
        
        return callMembers
    }
}
