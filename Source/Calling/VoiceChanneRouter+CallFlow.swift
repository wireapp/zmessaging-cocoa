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
    
    func join(video: Bool)
    
    func leave()
    
    func ignore()
    
}

extension VoiceChannelRouter : CallFlow {
    
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
    
    public func join(video: Bool) {
        guard let remoteIdentifier = conversation?.remoteIdentifier else { return }
        
        WireCallCenter.toogleVideo(conversationID: remoteIdentifier, active: video)
        
        if state == .incomingCall {
            _ = WireCallCenter.answerCall(conversationId: remoteIdentifier)
        } else {
            conversation?.isVideoCall = video
            _ = WireCallCenter.startCall(conversationId: remoteIdentifier)
        }
    }
    
    public func leave() {
        guard let remoteIdentifier = conversation?.remoteIdentifier else { return }
        
        WireCallCenter.closeCall(conversationId: remoteIdentifier)
    }
    
    public func ignore() {
        leave()
    }
    
}


extension ZMVoiceChannel : CallFlow {
    
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
