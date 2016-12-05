//
// Wire
// Copyright (C) 2016 Wire Swiss GmbH
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

@objc(ZMCaptureDevice)
public enum CaptureDevice : Int {
    case front
    case back
    
    var deviceIdentifier : String {
        switch  self {
        case .front:
            return "com.apple.avfoundation.avcapturedevice.built-in_video:1"
        case .back:
            return "com.apple.avfoundation.avcapturedevice.built-in_video:0"
        }
    }
}

public protocol CallFlow {
    
    var isVideoCall : Bool { get }
    
    func toggleVideo(active: Bool) throws
    
    func join(video: Bool)
    
    func leave()
    
    func ignore()
    
}


extension VoiceChannelRouter : CallFlow {
    
    public var isVideoCall: Bool {
        guard let callFlow = currentVoiceChannel as? CallFlow else { return false }
        
        return callFlow.isVideoCall
    }
    
    @objc(toggleVideoActive:error:)
    public func toggleVideo(active: Bool) throws {
        if let callFlow = currentVoiceChannel as? CallFlow {
            try callFlow.toggleVideo(active: active)
        }
    }
    
    public func join(video: Bool) {
        if let callFlow = currentVoiceChannel as? CallFlow {
            callFlow.join(video: video)
        }
    }
    
    public func leave() {
        if let callFlow = currentVoiceChannel as? CallFlow {
            callFlow.leave()
        }
    }
    
    public func ignore() {
        if let callFlow = currentVoiceChannel as? CallFlow {
            callFlow.ignore()
        }
    }
    
    public func setVideoCaptureDevice(device: CaptureDevice) throws {
        guard flowManager.isReady() else { throw ZMVoiceChannelError.noFlowManagerError() }
        guard let remoteIdentifier = conversation?.remoteIdentifier else { throw ZMVoiceChannelError.switchToVideoNotAllowedError() }
        
        flowManager.setVideoCaptureDevice(device.deviceIdentifier, forConversation: remoteIdentifier.transportString())
    }
    
    private var flowManager : AVSFlowManager {
        return ZMAVSBridge.flowManagerClass().getInstance() as! AVSFlowManager
    }
    
}

extension VoiceChannelV3 : CallFlow {
    
    public var isVideoCall: Bool {
        guard let remoteIdentifier = conversation?.remoteIdentifier else { return false }
        
        return WireCallCenter.isVideoCall(conversationId: remoteIdentifier)
    }
    
    @objc(toggleVideoActive:error:)
    public func toggleVideo(active: Bool) throws {
        guard let remoteIdentifier = conversation?.remoteIdentifier else { throw ZMVoiceChannelError.videoNotActiveError() }
        
        WireCallCenter.toogleVideo(conversationID: remoteIdentifier, active: active)
    }
    
    public func join(video: Bool) {
        guard let remoteIdentifier = conversation?.remoteIdentifier else { return }
        
        if state == .incomingCall {
            _ = WireCallCenter.activeInstance?.answerCall(conversationId: remoteIdentifier)
        } else {
            _ = WireCallCenter.activeInstance?.startCall(conversationId: remoteIdentifier, video: video)
        }
    }
    
    public func leave() {
        guard let remoteIdentifier = conversation?.remoteIdentifier else { return }
        
        WireCallCenter.activeInstance?.closeCall(conversationId: remoteIdentifier)
    }
    
    public func ignore() {
        guard let remoteIdentifier = conversation?.remoteIdentifier else { return }
        
        WireCallCenter.activeInstance?.ignoreCall(conversationId: remoteIdentifier)
    }
    
}


extension ZMVoiceChannel : CallFlow {
    
    public var isVideoCall: Bool {
        return conversation?.isVideoCall ?? false
    }
    
    @objc(toggleVideoActive:error:)
    public func toggleVideo(active: Bool) throws {
        try setVideoSendActive(active)
    }
    
    public func join(video: Bool) {
        if video {
            try? joinVideoCall() // FIXME
        } else {
            join()
        }
    }
    
    public func ignore() {
        ignoreIncomingCall()
    }

}
