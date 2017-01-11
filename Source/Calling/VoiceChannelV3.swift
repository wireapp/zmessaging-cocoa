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

public class VoiceChannelV3 : NSObject, VoiceChannel {
    
    public var selfUserConnectionState: ZMVoiceChannelConnectionState {
        if let remoteIdentifier = conversation?.remoteIdentifier, let callCenter = WireCallCenterV3.activeInstance {
            return callCenter.callState(conversationId:remoteIdentifier).connectionState
        } else {
            return .invalid
        }
    }

    /// The date and time of current call start
    public var callStartDate: Date? {
        return WireCallCenterV3.activeInstance?.establishedDate
    }
    
    weak public var conversation: ZMConversation?
    
    /// Voice channel participants. May be a subset of conversation participants.
    public var participants: NSOrderedSet {
        return conversation?.activeParticipants ?? NSOrderedSet()
    }
    
    init(conversation: ZMConversation) {
        self.conversation = conversation
        
        super.init()
    }

    public func state(forParticipant participant: ZMUser) -> ZMVoiceChannelParticipantState {
        let participantState = ZMVoiceChannelParticipantState()
        
        participantState.connectionState = .connected
        participantState.muted = false
        participantState.isSendingVideo = false
        
        return participantState
    }

    public var state: ZMVoiceChannelState {
        if let remoteIdentifier = conversation?.remoteIdentifier, let callCenter = WireCallCenterV3.activeInstance {
            return callCenter.callState(conversationId:remoteIdentifier).voiceChannelState
        } else {
            return .noActiveUsers
        }
    }
    
}

public extension CallState {
    
    var connectionState : ZMVoiceChannelConnectionState {
        switch self {
        case .unknown, .terminating, .incoming, .none:
            return .notConnected
        case .established:
            return .connected
        case .outgoing:
            return .connecting
        }
    }
    
    var voiceChannelState : ZMVoiceChannelState {
        switch self {
        case .none:
            return .noActiveUsers
        case .incoming:
            return .incomingCall
        case .established:
            return .selfConnectedToActiveChannel
        case .outgoing:
            return .outgoingCall
        case .terminating:
            return .noActiveUsers
        case .unknown:
            return .invalid
        }
    }
    
}
