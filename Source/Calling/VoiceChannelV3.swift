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

public class VoiceChannelV3 : NSObject, CallProperties {
    
    public var selfUserConnectionState: VoiceChannelV2ConnectionState {
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

    public func state(forParticipant participant: ZMUser) -> VoiceChannelV2ParticipantState {
        let participantState = VoiceChannelV2ParticipantState()
        
        participantState.connectionState = .connected
        participantState.muted = false
        participantState.isSendingVideo = false
        
        return participantState
    }

    public var state: VoiceChannelV2State {
        if let conversation = conversation, let remoteIdentifier = conversation.remoteIdentifier, let callCenter = WireCallCenterV3.activeInstance {
            return callCenter.callState(conversationId:remoteIdentifier).voiceChannelState(securityLevel: conversation.securityLevel)
        } else {
            return .noActiveUsers
        }
    }
    
    public var isVideoCall: Bool {
        guard let remoteIdentifier = conversation?.remoteIdentifier else { return false }
        
        return WireCallCenterV3.isVideoCall(conversationId: remoteIdentifier)
    }
    
    public func toggleVideo(active: Bool) throws {
        guard let remoteIdentifier = conversation?.remoteIdentifier else { throw VoiceChannelV2Error.videoNotActiveError() }
        
        WireCallCenterV3.activeInstance?.toogleVideo(conversationID: remoteIdentifier, active: active)
    }
    
}

extension VoiceChannelV3 : CallActionsInternal {
    
    public func join(video: Bool) -> Bool {
        guard let conversation = conversation, let remoteIdentifier = conversation.remoteIdentifier else { return false }
        var joined = false
        
        switch state {
        case .incomingCall, .incomingCallDegraded:
            joined = WireCallCenterV3.activeInstance?.answerCall(conversationId: remoteIdentifier) ?? false
        default:
            joined = WireCallCenterV3.activeInstance?.startCall(conversationId: remoteIdentifier, video: video) ?? false
        }
        
        return joined
    }
    
    public func leave() {
        guard let remoteIdentifier = conversation?.remoteIdentifier else { return }
        
        WireCallCenterV3.activeInstance?.closeCall(conversationId: remoteIdentifier)
    }
    
    public func ignore() {
        guard let remoteIdentifier = conversation?.remoteIdentifier else { return }
        
        WireCallCenterV3.activeInstance?.rejectCall(conversationId: remoteIdentifier)
    }
    
}

public extension CallState {
    
    var connectionState : VoiceChannelV2ConnectionState {
        switch self {
        case .unknown, .terminating, .incoming, .none:
            return .notConnected
        case .established:
            return .connected
        case .outgoing, .answered:
            return .connecting
        }
    }
    
    func voiceChannelState(securityLevel: ZMConversationSecurityLevel) -> VoiceChannelV2State {
        switch self {
        case .none:
            return .noActiveUsers
        case .incoming where securityLevel == .secureWithIgnored:
            return .incomingCallDegraded
        case .incoming:
            return .incomingCall
        case .answered:
            return .selfIsJoiningActiveChannel
        case .established:
            return .selfConnectedToActiveChannel
        case .outgoing where securityLevel == .secureWithIgnored:
            return .outgoingCallDegraded
        case .outgoing:
            return .outgoingCall
        case .terminating:
            return .noActiveUsers
        case .unknown:
            return .invalid
        }
    }
    
}
