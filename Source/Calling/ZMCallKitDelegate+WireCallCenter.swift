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
import ZMCDataModel


extension CallClosedReason {
    
    @available(iOS 10.0, *)
    var CXCallEndedReason : CXCallEndedReason {
        switch self {
        case .timeout:
            return .unanswered
        case .normal:
            return .remoteEnded
        default:
            return .failed
        }
    }
    
}

extension ZMCallKitDelegate : WireCallCenterCallStateObserver, WireCallCenterMissedCallObserver {
    
    public func callCenterDidChange(callState: CallState, conversationId: UUID, userId: UUID) {
        
        switch callState {
        case .incoming(video: _):
            guard
                let conversation = ZMConversation(remoteID: conversationId, createIfNeeded: false, in: userSession.managedObjectContext),
                let user = ZMUser(remoteID: userId, createIfNeeded: false, in: userSession.managedObjectContext) else {
                    break
            }
            
            indicateIncomingCall(from: user, in: conversation)
        case .terminating(reason: let reason):
            if #available(iOS 10.0, *) {
                provider.reportCall(with: conversationId, endedAt: nil, reason: UInt(reason.CXCallEndedReason.rawValue))
            }
        case .established:
            provider.reportOutgoingCall(with: conversationId, connectedAt: Date())
        case .outgoing:
            provider.reportOutgoingCall(with: conversationId, startedConnectingAt: Date())
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
        return WireCallCenter.addCallStateObserver(observer: self)
    }
    
    public func observeMissedCalls() -> WireCallCenterObserverToken {
        return WireCallCenter.addMissedCallObserver(observer: self)
    }
    
}

extension ZMCallKitDelegate : WireCallCenterV2CallStateObserver {
    
    public func callCenterDidChange(voiceChannelState: ZMVoiceChannelState, conversation: ZMConversation) {
        switch voiceChannelState {
        case .incomingCall:
            guard let user = conversation.voiceChannel?.v2.participants.firstObject as? ZMUser else { return }
            indicateIncomingCall(from: user, in: conversation)
        case .outgoingCall:
            provider.reportOutgoingCall(with: conversation.remoteIdentifier!, startedConnectingAt: Date())
        case .selfIsJoiningActiveChannel:
            connectedCallConversation = conversation
        case .selfConnectedToActiveChannel:
            conversation.voiceChannel?.v2.callStartDate = Date()
            provider.reportOutgoingCall(with: conversation.remoteIdentifier!, connectedAt: Date())
        case .noActiveUsers:
            if #available(iOS 10.0, *) {
                if conversation == connectedCallConversation {
                    provider.reportCall(with: conversation.remoteIdentifier!, endedAt: nil, reason: UInt(CXCallEndedReason.remoteEnded.rawValue))
                } else {
                    provider.reportCall(with: conversation.remoteIdentifier!, endedAt: nil, reason: UInt(CXCallEndedReason.unanswered.rawValue))
                }
            }
            connectedCallConversation = nil
            conversation.voiceChannel?.v2.callStartDate = nil
        default:
            break
        }
    }
    
}
