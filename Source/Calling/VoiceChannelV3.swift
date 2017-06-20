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

public class VoiceChannelV3 : NSObject, CallProperties, VoiceChannel {
    
    public var callingProtocol: CallingProtocol {
        return .version3
    }
    
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
        guard let callCenter = WireCallCenterV3.activeInstance,
              let conversationId = conversation?.remoteIdentifier,
              let context = conversation?.managedObjectContext
        else { return NSOrderedSet() }
        
        let userIds = callCenter.callParticipants(conversationId: conversationId)
        let users = userIds.flatMap{ ZMUser(remoteID: $0, createIfNeeded: false, in:context) }
        return NSOrderedSet(array: users)
    }
    
    init(conversation: ZMConversation) {
        self.conversation = conversation
        super.init()
    }

    public func state(forParticipant participant: ZMUser) -> VoiceChannelV2ParticipantState {
        guard let conv = self.conversation,
            let convID = conv.remoteIdentifier,
            let userID = participant.remoteIdentifier,
            let callCenter = WireCallCenterV3.activeInstance
        else { return VoiceChannelV2ParticipantState() }
        
        let state = VoiceChannelV2ParticipantState()
        state.isSendingVideo = false // TODO Sabine
        if participant.isSelfUser {
            state.connectionState = selfUserConnectionState
        } else {
            state.connectionState = callCenter.connectionState(forUserWith: userID, in: convID)
        }
        return state;
    }
    
    public var state: VoiceChannelV2State {
        if let conversation = conversation, let remoteIdentifier = conversation.remoteIdentifier, let callCenter = WireCallCenterV3.activeInstance {
            let callState = callCenter.callState(conversationId:remoteIdentifier)
            return callState.voiceChannelState(securityLevel: conversation.securityLevel)
        } else {
            return .noActiveUsers
        }
    }
    
    public var isVideoCall: Bool {
        guard let remoteIdentifier = conversation?.remoteIdentifier else { return false }
        
        return WireCallCenterV3.activeInstance?.isVideoCall(conversationId: remoteIdentifier) ?? false
    }
    
    public var initiator : ZMUser? {
        guard let context = conversation?.managedObjectContext,
              let convId = conversation?.remoteIdentifier,
              let userId = WireCallCenterV3.activeInstance?.initiatorForCall(conversationId: convId)
        else {
            return nil
        }
        return ZMUser.fetch(withRemoteIdentifier: userId, in: context)
    }
    
    public func toggleVideo(active: Bool) throws {
        guard let remoteIdentifier = conversation?.remoteIdentifier else { throw VoiceChannelV2Error.videoNotActiveError() }
        
        WireCallCenterV3.activeInstance?.toogleVideo(conversationID: remoteIdentifier, active: active)
    }
    
    public func setVideoCaptureDevice(device: CaptureDevice) throws {
        guard let flowManager = ZMAVSBridge.flowManagerInstance(), flowManager.isReady() else { throw VoiceChannelV2Error.noFlowManagerError() }
        guard let remoteIdentifier = conversation?.remoteIdentifier else { throw VoiceChannelV2Error.switchToVideoNotAllowedError() }
        
        flowManager.setVideoCaptureDevice(device.deviceIdentifier, forConversation: remoteIdentifier.transportString())
    }
    
}

extension VoiceChannelV3 : CallActions {
    
    public func continueByDecreasingConversationSecurity(userSession: ZMUserSession) {
        guard let conversation = conversation else { return }
        conversation.makeNotSecure()
    }
    
    public func leaveAndKeepDegradedConversationSecurity(userSession: ZMUserSession) {
        guard let conversation = conversation else { return }
        userSession.syncManagedObjectContext.performGroupedBlock {
            let conversationId = conversation.objectID
            if let syncConversation = (try? userSession.syncManagedObjectContext.existingObject(with: conversationId)) as? ZMConversation {
                userSession.callingStrategy.dropPendingCallMessages(for: syncConversation)
            }
        }
        leave(userSession: userSession)
    }
    
    public func join(video: Bool, userSession: ZMUserSession) -> Bool {
        if ZMUserSession.useCallKit {
            userSession.callKitDelegate.requestStartCall(in: conversation!, videoCall: video)
            return true
        } else {
            return join(video: video)
        }
    }
    
    public func leave(userSession: ZMUserSession) {
        if ZMUserSession.useCallKit {
            userSession.callKitDelegate.requestEndCall(in: conversation!)
        } else {
            return leave()
        }
    }
    
    public func ignore(userSession: ZMUserSession) {
        if ZMUserSession.useCallKit {
            userSession.callKitDelegate.requestEndCall(in: conversation!)
        } else {
            return ignore()
        }
    }
    
}

extension VoiceChannelV3 : CallActionsInternal {
    
    public func join(video: Bool) -> Bool {
        guard let conversation = conversation,
              let remoteIdentifier = conversation.remoteIdentifier
        else { return false }
        
        let isGroup = (conversation.conversationType == .group)
        var joined = false
        
        switch state {
        case .incomingCall, .incomingCallInactive:
            joined = WireCallCenterV3.activeInstance?.answerCall(conversationId: remoteIdentifier, isGroup: isGroup) ?? false
        case .incomingCallDegraded:
            joined = true // Don't answer call
        default:
            joined = WireCallCenterV3.activeInstance?.startCall(conversationId: remoteIdentifier, video: video, isGroup: isGroup) ?? false
        }
        
        return joined
    }
    
    public func leave() {
        guard let conv = conversation,
              let remoteID = conv.remoteIdentifier
        else { return }
        
        let isGroup = (conv.conversationType == .group)
        WireCallCenterV3.activeInstance?.closeCall(conversationId: remoteID, isGroup: isGroup)
    }
    
    public func ignore() {
        guard let conv = conversation,
              let remoteID = conv.remoteIdentifier
        else { return }
        
        let isGroup = (conv.conversationType == .group)
        WireCallCenterV3.activeInstance?.rejectCall(conversationId: remoteID, isGroup: isGroup)
    }
    
}

extension VoiceChannelV3 : CallObservers {
    
    /// Add observer of voice channel state. Returns a token which needs to be retained as long as the observer should be active.
    public func addStateObserver(_ observer: VoiceChannelStateObserver) -> WireCallCenterObserverToken {
        return WireCallCenter.addVoiceChannelStateObserver(conversation: conversation!, observer: observer, context: conversation!.managedObjectContext!)
    }
    
    /// Add observer of voice channel participants. Returns a token which needs to be retained as long as the observer should be active.
    public func addParticipantObserver(_ observer: VoiceChannelParticipantObserver) -> WireCallCenterObserverToken {
        return WireCallCenter.addVoiceChannelParticipantObserver(observer: observer, forConversation: conversation!, context: conversation!.managedObjectContext!)
    }
    
    /// Add observer of voice gain. Returns a token which needs to be retained as long as the observer should be active.
    public func addVoiceGainObserver(_ observer: VoiceGainObserver) -> WireCallCenterObserverToken {
        return WireCallCenter.addVoiceGainObserver(observer: observer, forConversation: conversation!, context: conversation!.managedObjectContext!)
    }
    
    /// Add observer of received video. Returns a token which needs to be retained as long as the observer should be active.
    public func addReceivedVideoObserver(_ observer: ReceivedVideoObserver) -> WireCallCenterObserverToken {
        return WireCallCenter.addReceivedVideoObserver(observer: observer, forConversation: conversation!, context: conversation!.managedObjectContext!)
    }
    
    /// Add observer of the state of all voice channels. Returns a token which needs to be retained as long as the observer should be active.
    public class func addStateObserver(_ observer: VoiceChannelStateObserver, userSession: ZMUserSession) -> WireCallCenterObserverToken {
        return WireCallCenter.addVoiceChannelStateObserver(observer: observer, context: userSession.managedObjectContext!)
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
        case .incoming(video:_, shouldRing: let shouldRing) where shouldRing == false:
            return .incomingCallInactive
        case .incoming:
            return .incomingCall
        case .answered where securityLevel == .secureWithIgnored:
            return .selfIsJoiningActiveChannelDegraded
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
