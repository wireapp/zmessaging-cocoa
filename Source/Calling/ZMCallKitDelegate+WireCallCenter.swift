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
    
    private var token : Any?
    
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
        case .establishedDataChannel:
            onEstablished?()
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
    
    public func callCenterDidChange(callState: CallState, conversationId: UUID, userId: UUID?, timeStamp: Date?) {
        guard #available(iOS 10.0, *) else {
            return
        }
        guard let conversation = ZMConversation(remoteID: conversationId, createIfNeeded: false, in: userSession.managedObjectContext) else {
            return
        }
        
        switch callState {
        case .incoming(video: let video, shouldRing: let shouldRing):
            guard let userId = userId, let user = ZMUser(remoteID: userId, createIfNeeded: false, in: userSession.managedObjectContext) else {
                    break
            }
            if shouldRing {
                if !conversation.isSilenced {
                    indicateIncomingCall(from: user, in: conversation, video: video)
                }
            } else {
                provider.reportCall(with: conversationId,
                                    endedAt: timeStamp,
                                    reason: UInt(CXCallEndedReason.unanswered.rawValue))
            }
        case let .terminating(reason: reason) where !(reason == .normal && userId == ZMUser.selfUser(inUserSession: userSession).remoteIdentifier):
            provider.reportCall(with: conversationId,
                                endedAt: timeStamp,
                                reason: UInt(reason.CXCallEndedReason.rawValue))
        default:
            break
        }
    }
    
    public func callCenterMissedCall(conversationId: UUID, userId: UUID, timestamp: Date, video: Bool) {
        if #available(iOS 10.0, *) {
            provider.reportCall(with: conversationId, endedAt: timestamp, reason: UInt(CXCallEndedReason.unanswered.rawValue))
        }
    }
    
    public func observeCallState() -> Any {
        return WireCallCenterV3.addCallStateObserver(observer: self, context: userSession.managedObjectContext)
    }
    
    public func observeMissedCalls() -> Any {
        return WireCallCenterV3.addMissedCallObserver(observer: self, context: userSession.managedObjectContext)
    }
    
}
