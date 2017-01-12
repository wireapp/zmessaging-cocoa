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

@objc
public enum ReceivedVideoState : UInt {
    /// Sender is not sending video
    case stopped
    /// Sender is sending video
    case started
    /// Sender is sending video but currently has a bad connection
    case badConnection
}

@objc
public protocol ReceivedVideoObserver : class {
    
    @objc(callCenterDidChangeReceivedVideoState:)
    func callCenterDidChange(receivedVideoState: ReceivedVideoState)
    
}



@objc
public protocol VoiceChannelStateObserver : class {
    
    @objc(callCenterDidChangeVoiceChannelState:conversation:)
    func callCenterDidChange(voiceChannelState: VoiceChannelV2State, conversation: ZMConversation)
    
    func callCenterDidFailToJoinVoiceChannel(error: Error?, conversation: ZMConversation)
    
    func callCenterDidEndCall(reason: VoiceChannelV2CallEndReason, conversation: ZMConversation)
    
}

extension CallClosedReason {
    
    var voiceChannelCallEndReason : VoiceChannelV2CallEndReason {
        switch self {
        case .lostMedia:
            return VoiceChannelV2CallEndReason.disconnected
        case .normal:
            return VoiceChannelV2CallEndReason.requested
        case .normalSelf:
            return VoiceChannelV2CallEndReason.requestedSelf
        case .timeout:
            return VoiceChannelV2CallEndReason.requestedAVS
        case .internalError:
            return VoiceChannelV2CallEndReason.interrupted
        case .unknown:
            return VoiceChannelV2CallEndReason.interrupted
        }
    }
    
}


class VoiceChannelStateObserverToken : NSObject, WireCallCenterV2CallStateObserver, WireCallCenterCallStateObserver {
    
    let context : NSManagedObjectContext
    weak var observer : VoiceChannelStateObserver?
    
    var tokenV2 : WireCallCenterObserverToken?
    var tokenV3 : WireCallCenterObserverToken?
    var tokenJoinFailedV2 : NSObjectProtocol?
    var tokenCallEndedV2 : NSObjectProtocol?
    
    deinit {
        if let token = tokenV3 {
            WireCallCenterV3.removeObserver(token: token)
        }
        
        if let token = tokenV2 {
            WireCallCenterV2.removeObserver(token: token)
        }
        
        if let token = tokenJoinFailedV2 {
            NotificationCenter.default.removeObserver(token)
        }
        
        if let token = tokenCallEndedV2 {
            NotificationCenter.default.removeObserver(token)
        }
        
    }
    
    init(context: NSManagedObjectContext, observer: VoiceChannelStateObserver) {
        self.context = context
        self.observer = observer
        
        super.init()
        
        tokenV3 = WireCallCenterV3.addCallStateObserver(observer: self)
        tokenV2 = WireCallCenterV2.addVoiceChannelStateObserver(observer: self, context: context)
        
        tokenJoinFailedV2 = NotificationCenter.default.addObserver(forName: NSNotification.Name.ZMConversationVoiceChannelJoinFailed, object: nil, queue: .main) { [weak observer] (note) in
            if let conversationId = note.object as? UUID, let conversation = ZMConversation(remoteID: conversationId, createIfNeeded: false, in: context) {
                observer?.callCenterDidFailToJoinVoiceChannel(error: note.userInfo?["error"] as? Error, conversation: conversation)
            }
        }
        
        tokenCallEndedV2 = NotificationCenter.default.addObserver(forName: CallEndedNotification.notificationName, object: nil, queue: .main, using: { [weak observer] (note) in
            guard let note = note.userInfo?[CallEndedNotification.userInfoKey] as? CallEndedNotification else { return }
            
            if let conversation = ZMConversation(remoteID: note.conversationId, createIfNeeded: false, in: context) {
                observer?.callCenterDidEndCall(reason: note.reason, conversation: conversation)
            }
        })
    }
    
    func callCenterDidChange(callState: CallState, conversationId: UUID, userId: UUID) {
        guard let conversation = ZMConversation(remoteID: conversationId, createIfNeeded: false, in: context) else { return }
        
        observer?.callCenterDidChange(voiceChannelState: callState.voiceChannelState, conversation: conversation)
        
        if case let .terminating(reason: reason) = callState {
            observer?.callCenterDidEndCall(reason: reason.voiceChannelCallEndReason, conversation: conversation)
        }
    }
    
    func callCenterDidChange(voiceChannelState: VoiceChannelV2State, conversation: ZMConversation) {
        observer?.callCenterDidChange(voiceChannelState: voiceChannelState, conversation: conversation)
    }
    
}

class VoiceChannelStateObserverFilter : NSObject,  VoiceChannelStateObserver {
    
    let observedConversation : ZMConversation
    var token : VoiceChannelStateObserverToken?
    weak var observer : VoiceChannelStateObserver?
    
    init (context: NSManagedObjectContext, observer: VoiceChannelStateObserver, conversation: ZMConversation) {
        self.observer = observer
        self.observedConversation = conversation
        
        super.init()
        
        self.token = VoiceChannelStateObserverToken(context: context, observer: self)
    }
    
    func callCenterDidChange(voiceChannelState: VoiceChannelV2State, conversation: ZMConversation) {
        if conversation == observedConversation {
            observer?.callCenterDidChange(voiceChannelState: voiceChannelState, conversation: conversation)
        }
    }
    
    func callCenterDidFailToJoinVoiceChannel(error: Error?, conversation: ZMConversation) {
        if conversation == observedConversation {
            observer?.callCenterDidFailToJoinVoiceChannel(error: error, conversation: conversation)
        }
    }
    
    func callCenterDidEndCall(reason: VoiceChannelV2CallEndReason, conversation: ZMConversation) {
        if conversation == observedConversation {
            observer?.callCenterDidEndCall(reason: reason, conversation: conversation)
        }
    }
}

class ReceivedVideoObserverToken : NSObject {
    
    var tokenV2 : WireCallCenterObserverToken?
    var tokenV3 : WireCallCenterObserverToken?
    
    deinit {
        if let token = tokenV3 {
            WireCallCenterV3.removeObserver(token: token)
        }
    }
    
    init(context: NSManagedObjectContext, observer: ReceivedVideoObserver, conversation: ZMConversation) {
        tokenV2 = WireCallCenterV2.addReceivedVideoObserver(observer: observer, forConversation: conversation, context: context)
        tokenV3 = WireCallCenterV3.addReceivedVideoObserver(observer: observer)
    }
    
}


@objc
public class WireCallCenter : NSObject {
    
    public class func addVoiceChannelStateObserver(conversation: ZMConversation, observer: VoiceChannelStateObserver, context: NSManagedObjectContext) -> WireCallCenterObserverToken {
        return VoiceChannelStateObserverFilter(context: context, observer: observer, conversation: conversation)
    }
    
    public class func addVoiceChannelStateObserver(observer: VoiceChannelStateObserver, context: NSManagedObjectContext) -> WireCallCenterObserverToken {
        return VoiceChannelStateObserverToken(context: context, observer: observer)
    }
    
    public class func addVoiceChannelParticipantObserver(observer: VoiceChannelParticipantObserver, forConversation conversation: ZMConversation, context: NSManagedObjectContext) -> WireCallCenterObserverToken {
        return WireCallCenterV2.addVoiceChannelParticipantObserver(observer: observer, forConversation: conversation, context: context)
    }
    
    public class func addVoiceGainObserver(observer: VoiceGainObserver, forConversation conversation: ZMConversation, context: NSManagedObjectContext) -> WireCallCenterObserverToken {
        return WireCallCenterV2.addVoiceGainObserver(observer: observer, forConversation: conversation, context: context)
    }
    
    public class func addReceivedVideoObserver(observer: ReceivedVideoObserver, forConversation conversation: ZMConversation, context: NSManagedObjectContext) -> WireCallCenterObserverToken {
        return ReceivedVideoObserverToken(context: context, observer: observer, conversation: conversation)
    }
    
    public class func activeCallConversations(inUserSession userSession: ZMUserSession) -> [ZMConversation] {
        // FIXME achive this in a more optimized way
        if let conversations = ZMConversationList.conversationsIncludingArchived(inUserSession: userSession).asArray() as? [ZMConversation] {
            return conversations.filter({ (conversation) -> Bool in
                return conversation.voiceChannel?.state == .selfConnectedToActiveChannel
            })
        } else {
            return []
        }
    }
    
    public class func nonIdleCallConversations(inUserSession userSession: ZMUserSession) -> [ZMConversation] {
        // FIXME achive this in a more optimized way
        if let conversations = ZMConversationList.conversationsIncludingArchived(inUserSession: userSession).asArray() as? [ZMConversation] {
            return conversations.filter({ (conversation) -> Bool in
                let voiceChannelState = conversation.voiceChannel?.state
                return voiceChannelState != .noActiveUsers && voiceChannelState != .invalid
            })
        } else {
            return []
        }
    }
    
}
