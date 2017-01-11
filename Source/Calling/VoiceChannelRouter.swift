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

extension ZMVoiceChannel : VoiceChannel { }

public class VoiceChannelRouter : NSObject, VoiceChannel {
    
    public static var isCallingV3Enabled : Bool = false
    
    public let v3 : VoiceChannelV3
    public let v2 : ZMVoiceChannel
    
    public init(conversation: ZMConversation) {
        v3 = VoiceChannelV3(conversation: conversation)
        v2 = ZMVoiceChannel(conversation: conversation)
        
        super.init()
    }
    
    public var currentVoiceChannel : VoiceChannel {
        if v2.state != .noActiveUsers || v2.conversation?.conversationType != .oneOnOne {
            return v2
        }
        
        if v3.state != .noActiveUsers {
            return v3
        }
        
        return VoiceChannelRouter.isCallingV3Enabled ? v3 : v2
    }
    
    public var conversation: ZMConversation? {
        return currentVoiceChannel.conversation
    }
    
    public var state: ZMVoiceChannelState {
        return currentVoiceChannel.state
    }
        
    public var callStartDate: Date? {
        return currentVoiceChannel.callStartDate
    }
    
    public var participants: NSOrderedSet {
        return currentVoiceChannel.participants
    }
    
    public var selfUserConnectionState: ZMVoiceChannelConnectionState {
        return currentVoiceChannel.selfUserConnectionState
    }
    
    public func state(forParticipant participant: ZMUser) -> ZMVoiceChannelParticipantState {
        return currentVoiceChannel.state(forParticipant: participant)
    }
    
}
