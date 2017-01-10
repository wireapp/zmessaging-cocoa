//
//  VoiceChannelRouter.swift
//  ZMCDataModel
//
//  Created by Jacob on 23/11/16.
//  Copyright © 2016 Wire Swiss GmbH. All rights reserved.
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
