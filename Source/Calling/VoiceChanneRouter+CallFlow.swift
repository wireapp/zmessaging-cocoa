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


public protocol CallFlow {
    
    var isVideoCall : Bool { get }
    
    func join(video: Bool)
    
    func leave()
    
    func ignore()
    
}

extension VoiceChannelRouter : CallFlow {
    
    public var isVideoCall: Bool {
        guard let callFlow = currentVoiceChannel as? CallFlow else { return false }
        return callFlow.isVideoCall
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
    
}

extension VoiceChannelV3 : CallFlow {
    
    public var isVideoCall: Bool {
        guard let remoteIdentifier = conversation?.remoteIdentifier else { return false }
        
        return WireCallCenter.isVideoCall(conversationId: remoteIdentifier)
    }
    
    public func join(video: Bool) {
        guard let remoteIdentifier = conversation?.remoteIdentifier else { return }
        
        WireCallCenter.toogleVideo(conversationID: remoteIdentifier, active: video)
        
        if state == .incomingCall {
            _ = WireCallCenter.answerCall(conversationId: remoteIdentifier)
        } else {
            _ = WireCallCenter.startCall(conversationId: remoteIdentifier, video: video)
        }
    }
    
    public func leave() {
        guard let remoteIdentifier = conversation?.remoteIdentifier else { return }
        
        WireCallCenter.closeCall(conversationId: remoteIdentifier)
    }
    
    public func ignore() {
        guard let remoteIdentifier = conversation?.remoteIdentifier else { return }
        
        WireCallCenter.ignoreCall(conversationId: remoteIdentifier)
    }
    
}


extension ZMVoiceChannel : CallFlow {
    
    public var isVideoCall: Bool {
        return conversation?.isVideoCall ?? false
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
