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
import WireDataModel


extension CallClosedReason {
    
    @available(iOS 10.0, *)
    var CXCallEndedReason : CXCallEndedReason {
        switch self {
        case .timeout:
            return .unanswered
        case .normal, .canceled:
            return .remoteEnded
        case .anweredElsewhere:
            return .answeredElsewhere
        default:
            return .failed
        }
    }
    
}

@objc(ZMCallObserver)
public class CallObserver : NSObject, VoiceChannelStateObserver {
    
    private var token : WireCallCenterObserverToken?
    
    public init(conversation: ZMConversation) {
        super.init()
        
        token = WireCallCenter.addVoiceChannelStateObserver(conversation: conversation, observer: self, context: conversation.managedObjectContext!)
    }
    
    public var onAnswered : (() -> Void)?
    public var onEstablished : (() -> Void)?
    public var onFailedToJoin : (() -> Void)?
    
    public func callCenterDidChange(voiceChannelState: VoiceChannelV2State, conversation: ZMConversation, callingProtocol: CallingProtocol) {

        switch voiceChannelState {
        case .selfIsJoiningActiveChannel:
            onAnswered?()
        case .selfConnectedToActiveChannel:
            onEstablished?()
        default:
            break
        }
    }
    
    public func callCenterDidEndCall(reason: VoiceChannelV2CallEndReason, conversation: ZMConversation, callingProtocol: CallingProtocol) {
        
    }
    
    public func callCenterDidFailToJoinVoiceChannel(error: Error?, conversation: ZMConversation) {
        onFailedToJoin?()
    }
}

extension ZMCallKitDelegate : WireCallCenterCallStateObserver, WireCallCenterMissedCallObserver {
    
    public func callCenterDidChange(callState: CallState, conversationId: UUID, userId: UUID?) {
        guard let conversation = ZMConversation(remoteID: conversationId, createIfNeeded: false, in: userSession.managedObjectContext) else {
            return
        }
        
        switch callState {
        case .incoming(video: let video, shouldRing: let shouldRing):
            guard
                let userId = userId,
                let user = ZMUser(remoteID: userId, createIfNeeded: false, in: userSession.managedObjectContext) else {
                    break
            }
            if shouldRing && !conversation.isSilenced {
                indicateIncomingCall(from: user, in: conversation, video: video)
            }
        case let .terminating(reason: reason) where !(reason == .normal && userId == ZMUser.selfUser(inUserSession: userSession).remoteIdentifier):
            if #available(iOS 10.0, *) {
                provider.reportCall(with: conversationId, endedAt: nil, reason: UInt(reason.CXCallEndedReason.rawValue))
            }
        default:
            break
        }
    }
    
    public func callCenterMissedCall(conversationId: UUID, userId: UUID, timestamp: Date, video: Bool) {
        if #available(iOS 10.0, *) {
            provider.reportCall(with: conversationId, endedAt: timestamp, reason: UInt(CXCallEndedReason.unanswered.rawValue))
        }
    }
    
    public func observeCallState() -> WireCallCenterObserverToken {
        return WireCallCenterV3.addCallStateObserver(observer: self)
    }
    
    public func observeMissedCalls() -> WireCallCenterObserverToken {
        return WireCallCenterV3.addMissedCallObserver(observer: self)
    }
    
}

extension ZMCallKitDelegate : VoiceChannelStateObserver {
    
    public func callCenterDidChange(voiceChannelState: VoiceChannelV2State, conversation: ZMConversation, callingProtocol: CallingProtocol) {
        guard callingProtocol == .version2 else { return }
    
        if voiceChannelState == .incomingCall {
            guard let user = conversation.voiceChannelRouter?.v2.participants.firstObject as? ZMUser else { return }
            if !conversation.isSilenced {
                indicateIncomingCall(from: user, in: conversation, video: conversation.voiceChannelRouter?.v2.isVideoCall ?? false)
            }
        }
        
        if voiceChannelState == .selfIsJoiningActiveChannel {
            connectedCallConversation = conversation
        }
    }
    
    public func callCenterDidEndCall(reason: VoiceChannelV2CallEndReason, conversation: ZMConversation, callingProtocol: CallingProtocol) {
        guard callingProtocol == .version2 && reason != .requestedSelf else {
            resetCallProperties(forConversation: conversation)
            return
        }
        
        if #available(iOS 10.0, *) {
            if conversation == connectedCallConversation {
                provider.reportCall(with: conversation.remoteIdentifier!, endedAt: nil, reason: UInt(CXCallEndedReason.remoteEnded.rawValue))
            } else {
                provider.reportCall(with: conversation.remoteIdentifier!, endedAt: nil, reason: UInt(CXCallEndedReason.unanswered.rawValue))
            }
        }
        
        resetCallProperties(forConversation: conversation)
    }
    
    public func callCenterDidFailToJoinVoiceChannel(error: Error?, conversation: ZMConversation) {
        
    }
    
    private func resetCallProperties(forConversation conversation : ZMConversation) {
        connectedCallConversation = nil
        conversation.voiceChannelRouter?.v2.callStartDate = nil
    }
}
