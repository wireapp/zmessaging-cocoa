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

@objc
public enum CallingProtocol : Int {
    case version2 = 2
    case version3 = 3
}

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
    
    @objc(callCenterDidChangeVoiceChannelState:conversation:callingProtocol:)
    func callCenterDidChange(voiceChannelState: VoiceChannelV2State, conversation: ZMConversation, callingProtocol: CallingProtocol)
    
    func callCenterDidFailToJoinVoiceChannel(error: Error?, conversation: ZMConversation)
    
    func callCenterDidEndCall(reason: VoiceChannelV2CallEndReason, conversation: ZMConversation, callingProtocol: CallingProtocol)
    
}

extension CallClosedReason {
    
    func voiceChannelCallEndReason(with user: ZMUser?) -> VoiceChannelV2CallEndReason {
        switch self {
        case .lostMedia:
            return VoiceChannelV2CallEndReason.disconnected
        case .normal, .anweredElsewhere, .canceled, .stillOngoing:
            return user?.isSelfUser == true ? .requestedSelf : .requested
        case .timeout:
            return VoiceChannelV2CallEndReason.requestedAVS
        case .inputOutputError:
            return VoiceChannelV2CallEndReason.inputOutputError
        case .internalError, .unknown:
            return VoiceChannelV2CallEndReason.interrupted
        }
    }
    
}


class VoiceChannelStateObserverToken : NSObject, WireCallCenterCallStateObserver {
    
    let context : NSManagedObjectContext
    weak var observer : VoiceChannelStateObserver?
    
    var token : Any?
    
    init(context: NSManagedObjectContext, observer: VoiceChannelStateObserver) {
        self.context = context
        self.observer = observer
        
        super.init()
        
        token = WireCallCenterV3.addCallStateObserver(observer: self, context: context)
    }
    
    func callCenterDidChange(callState: CallState, conversationId: UUID, userId: UUID?, timeStamp: Date?) {
        guard let conversation = ZMConversation(remoteID: conversationId, createIfNeeded: false, in: context) else { return }
        let voiceChannelState = callState.voiceChannelState(securityLevel: conversation.securityLevel)
        observer?.callCenterDidChange(voiceChannelState: voiceChannelState, conversation: conversation, callingProtocol: .version3)
        
        if case let .terminating(reason: reason) = callState {
            let user = userId.flatMap { ZMUser(remoteID: $0, createIfNeeded: false, in: context) }
            observer?.callCenterDidEndCall(
                reason: reason.voiceChannelCallEndReason(with: user),
                conversation: conversation,
                callingProtocol: .version3
            )
        }
    }
    
}

class VoiceChannelStateObserverFilter : NSObject,  VoiceChannelStateObserver {
    
    let observedConversation : ZMConversation
    var token : VoiceChannelStateObserverToken?
    var conversationToken : NSObjectProtocol?
    weak var observer : VoiceChannelStateObserver?
    
    init (context: NSManagedObjectContext, observer: VoiceChannelStateObserver, conversation: ZMConversation) {
        self.observer = observer
        self.observedConversation = conversation
        
        super.init()
        
        self.token = VoiceChannelStateObserverToken(context: context, observer: self)
        self.conversationToken = ConversationChangeInfo.add(observer: self, for: conversation)
    }
        
    func callCenterDidChange(voiceChannelState: VoiceChannelV2State, conversation: ZMConversation, callingProtocol: CallingProtocol) {
        if conversation == observedConversation {
            observer?.callCenterDidChange(voiceChannelState: voiceChannelState, conversation: conversation, callingProtocol: callingProtocol)
        }
    }
    
    func callCenterDidFailToJoinVoiceChannel(error: Error?, conversation: ZMConversation) {
        if conversation == observedConversation {
            observer?.callCenterDidFailToJoinVoiceChannel(error: error, conversation: conversation)
        }
    }
    
    func callCenterDidEndCall(reason: VoiceChannelV2CallEndReason, conversation: ZMConversation, callingProtocol: CallingProtocol) {
        if conversation == observedConversation {
            observer?.callCenterDidEndCall(reason: reason, conversation: conversation, callingProtocol: callingProtocol)
        }
    }
}

extension VoiceChannelStateObserverFilter: ZMConversationObserver {
    func conversationDidChange(_ changeInfo: ConversationChangeInfo) {
        if changeInfo.securityLevelChanged {
            guard let state =  observedConversation.voiceChannel?.state else { return }
            observer?.callCenterDidChange(voiceChannelState:state, conversation: observedConversation, callingProtocol: .version3)
        }
    }
}

@objc
public class WireCallCenter : NSObject {
    
    /// Add observer of the state of a converations's voice channel. Returns a token which needs to be retained as long as the observer should be active.
    public class func addVoiceChannelStateObserver(conversation: ZMConversation, observer: VoiceChannelStateObserver, context: NSManagedObjectContext) -> Any {
        return VoiceChannelStateObserverFilter(context: context, observer: observer, conversation: conversation)
    }
    
    /// Add observer of the state of all voice channels. Returns a token which needs to be retained as long as the observer should be active.
    public class func addVoiceChannelStateObserver(observer: VoiceChannelStateObserver, context: NSManagedObjectContext) -> Any {
        return VoiceChannelStateObserverToken(context: context, observer: observer)
    }
    
    /// Add observer of particpants in a voice channel. Returns a token which needs to be retained as long as the observer should be active.
    public class func addVoiceChannelParticipantObserver(observer: VoiceChannelParticipantObserver, forConversation conversation: ZMConversation, context: NSManagedObjectContext) -> Any {
        let remoteID = conversation.remoteIdentifier!
        
        return NotificationInContext.addObserver(name: VoiceChannelParticipantNotification.notificationName, context: context.notificationContext, queue: OperationQueue.main) { [weak observer] (note : NotificationInContext) in
            guard
                let note = note.userInfo[VoiceChannelParticipantNotification.userInfoKey] as? VoiceChannelParticipantNotification,
                let strongObserver = observer
            else { return }
            
            if note.conversationId == remoteID {
                strongObserver.voiceChannelParticipantsDidChange(note)
            }
        }
    }
    
    /// Add observer of voice gain. Returns a token which needs to be retained as long as the observer should be active.
    public class func addVoiceGainObserver(observer: VoiceGainObserver, forConversation conversation: ZMConversation, context: NSManagedObjectContext) -> Any {
        return NotificationInContext.addObserver(name: VoiceGainNotification.notificationName,
                                                 context: context.notificationContext,
                                                 object: conversation.remoteIdentifier! as NSUUID,
                                                 queue: .main)
        { [weak observer] note in
            guard let note = note.userInfo[VoiceGainNotification.userInfoKey] as? VoiceGainNotification,
                let observer = observer,
                let user = ZMUser(remoteID: note.userId, createIfNeeded: false, in: context)
                else { return }
            
            observer.voiceGainDidChange(forParticipant: user, volume: note.volume)
        }
    }
    
    /// Add observer of received video. Returns a token which needs to be retained as long as the observer should be active.
    public class func addReceivedVideoObserver(observer: ReceivedVideoObserver, forConversation conversation: ZMConversation, context: NSManagedObjectContext) -> Any {
        return WireCallCenterV3.addReceivedVideoObserver(observer: observer, context: context)
    }
    
    /// Returns conversations with active calls
    public class func activeCallConversations(inUserSession userSession: ZMUserSession) -> [ZMConversation] {
        let conversationsV3 = userSession.managedObjectContext.zm_callCenter?.nonIdleCalls.flatMap({ (key: UUID, value: CallState) -> ZMConversation? in
            if value == CallState.established {
                return ZMConversation(remoteID: key, createIfNeeded: false, in: userSession.managedObjectContext)
            } else {
                return nil
            }
        })
        
        return conversationsV3 ?? []
    }
    
    // Returns conversations with a non idle call state
    public class func nonIdleCallConversations(inUserSession userSession: ZMUserSession) -> [ZMConversation] {
        var nonIdleConversations : Set<ZMConversation> = Set()
        
        let conversationsV3 = userSession.managedObjectContext.zm_callCenter?.nonIdleCalls.flatMap({ (key: UUID, value: CallState) -> ZMConversation? in
            return ZMConversation(remoteID: key, createIfNeeded: false, in: userSession.managedObjectContext)
        })
        
        nonIdleConversations.formUnion(conversationsV3 ?? [])
        
        return Array(nonIdleConversations)
    }
    
}
