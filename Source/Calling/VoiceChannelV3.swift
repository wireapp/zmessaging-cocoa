//
//  VoiceChannelV3.swift
//  ZMCDataModel
//
//  Created by Jacob on 22/11/16.
//  Copyright © 2016 Wire Swiss GmbH. All rights reserved.
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
        case .unknown:
            fallthrough
        case .terminating:
            fallthrough
        case .incoming:
            fallthrough
        case .none:
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
