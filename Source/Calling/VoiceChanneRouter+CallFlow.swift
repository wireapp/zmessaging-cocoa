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
    
    func join(video: Bool) -> Bool
    
    func leave()
    
    func ignore()
    
}

public extension VoiceChannelRouter {
    
    func addStateObserver(_ observer: VoiceChannelStateObserver) -> WireCallCenterObserverToken {
        return WireCallCenter.addVoiceChannelStateObserver(conversation: conversation!, observer: observer, context: conversation!.managedObjectContext!)
    }
    
    func addParticipantObserver(_ observer: VoiceChannelParticipantObserver) -> WireCallCenterObserverToken {
        return WireCallCenter.addVoiceChannelParticipantObserver(observer: observer, forConversation: conversation!, context: conversation!.managedObjectContext!)
    }
    
    func addVoiceGainObserver(_ observer: VoiceGainObserver) -> WireCallCenterObserverToken {
        return WireCallCenter.addVoiceGainObserver(observer: observer, forConversation: conversation!, context: conversation!.managedObjectContext!)
    }
    
    class func addStateObserver(_ observer: VoiceChannelStateObserver, userSession: ZMUserSession) -> WireCallCenterObserverToken {
        return WireCallCenter.addVoiceChannelStateObserver(observer: observer, context: userSession.managedObjectContext!)
    }
    
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
    
    public func join(video: Bool) -> Bool {
        guard let callFlow = currentVoiceChannel as? CallFlow else { return false }
        return callFlow.join(video: video)
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
        guard let flowManager = ZMAVSBridge.flowManagerInstance(), flowManager.isReady() else { throw VoiceChannelV2Error.noFlowManagerError() }
        guard let remoteIdentifier = conversation?.remoteIdentifier else { throw VoiceChannelV2Error.switchToVideoNotAllowedError() }
        
        flowManager.setVideoCaptureDevice(device.deviceIdentifier, forConversation: remoteIdentifier.transportString())
    }
    
}

extension VoiceChannelV3 : CallFlow {
    
    public var isVideoCall: Bool {
        guard let remoteIdentifier = conversation?.remoteIdentifier else { return false }
        
        return WireCallCenterV3.isVideoCall(conversationId: remoteIdentifier)
    }
    
    @objc(toggleVideoActive:error:)
    public func toggleVideo(active: Bool) throws {
        guard let remoteIdentifier = conversation?.remoteIdentifier else { throw VoiceChannelV2Error.videoNotActiveError() }
        
        WireCallCenterV3.activeInstance?.toogleVideo(conversationID: remoteIdentifier, active: active)
    }
    
    public func join(video: Bool) -> Bool {
        guard let remoteIdentifier = conversation?.remoteIdentifier else { return false }
        
        if state == .incomingCall {
            _ = WireCallCenterV3.activeInstance?.answerCall(conversationId: remoteIdentifier)
        } else {
            _ = WireCallCenterV3.activeInstance?.startCall(conversationId: remoteIdentifier, video: video)
        }
        
        return true
    }
    
    public func leave() {
        guard let remoteIdentifier = conversation?.remoteIdentifier else { return }
        
        WireCallCenterV3.activeInstance?.closeCall(conversationId: remoteIdentifier)
    }
    
    public func ignore() {
        guard let remoteIdentifier = conversation?.remoteIdentifier else { return }
        
        WireCallCenterV3.activeInstance?.ignoreCall(conversationId: remoteIdentifier)
    }
    
}


extension VoiceChannelV2 : CallFlow {
    
    public var isVideoCall: Bool {
        return conversation?.isVideoCall ?? false
    }
    
    @objc(toggleVideoActive:error:)
    public func toggleVideo(active: Bool) throws {
        try setVideoSendActive(active)
    }
    
    public func join(video: Bool) -> Bool {
        var joined = true
        
        if video {
            joined = joinVideoCall()
        } else {
            joined = join()
        }
        
        return joined
    }
    
    public func ignore() {
        ignoreIncomingCall()
    }

}
