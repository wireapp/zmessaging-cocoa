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
import avs

@objc(ZMCaptureDevice)
public enum CaptureDevice : Int {
    case front
    case back
    
    var deviceIdentifier : String {
        switch  self {
        case .front:
            return "com.apple.avfoundation.avcapturedevice.built-in_video:1"
        case .back:
            return "com.apple.avfoundation.avcapturedevice.built-in_video:0"
        }
    }
}

extension VoiceChannelV2 : VoiceChannelInternal { }

extension VoiceChannelV3 : VoiceChannelInternal { }

public class VoiceChannelRouter : NSObject, VoiceChannel {
    
    private let zmLog = ZMSLog(tag: "calling")
    
    public let v3 : VoiceChannelV3
    public let v2 : VoiceChannelV2
    
    public init(conversation: ZMConversation) {
        v3 = VoiceChannelV3(conversation: conversation)
        v2 = VoiceChannelV2(conversation: conversation)
        
        super.init()
    }
    
    public var currentVoiceChannel : VoiceChannelInternal {
        if v2.state != .noActiveUsers {
            return v2
        }
        
        if v3.state != .noActiveUsers {
            return v3
        }
        
        switch ZMUserSession.callingProtocolStrategy {
        case .negotiate:
            guard let callingProtocol = WireCallCenterV3.activeInstance?.callingProtocol else {
                zmLog.warn("Attempt to use voice channel without an active call center")
                return v2
            }
            
            switch callingProtocol {
            case .version2: return v2
            case .version3: return v3
            }
        case .version2: return v2
        case .version3: return v3
        }
    }
    
    public var conversation: ZMConversation? {
        return currentVoiceChannel.conversation
    }
    
    public var state: VoiceChannelV2State {
        return currentVoiceChannel.state
    }
        
    public var callStartDate: Date? {
        return currentVoiceChannel.callStartDate
    }
    
    public var participants: NSOrderedSet {
        return currentVoiceChannel.participants
    }
    
    public var selfUserConnectionState: VoiceChannelV2ConnectionState {
        return currentVoiceChannel.selfUserConnectionState
    }
    
    public func state(forParticipant participant: ZMUser) -> VoiceChannelV2ParticipantState {
        return currentVoiceChannel.state(forParticipant: participant)
    }
    
    public var isVideoCall: Bool {
        return currentVoiceChannel.isVideoCall
    }
    
    public func toggleVideo(active: Bool) throws {
        try currentVoiceChannel.toggleVideo(active: active)
    }
    
    public func setVideoCaptureDevice(device: CaptureDevice) throws {
        guard let flowManager = ZMAVSBridge.flowManagerInstance(), flowManager.isReady() else { throw VoiceChannelV2Error.noFlowManagerError() }
        guard let remoteIdentifier = conversation?.remoteIdentifier else { throw VoiceChannelV2Error.switchToVideoNotAllowedError() }
        
        flowManager.setVideoCaptureDevice(device.deviceIdentifier, forConversation: remoteIdentifier.transportString())
    }
    
}

extension VoiceChannelRouter : CallObservers {
    
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

extension VoiceChannelRouter : CallActions {
    
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
            return currentVoiceChannel.join(video: video)
        }
    }
    
    public func leave(userSession: ZMUserSession) {
        if ZMUserSession.useCallKit {
            userSession.callKitDelegate.requestEndCall(in: conversation!)
        } else {
            return currentVoiceChannel.leave()
        }
    }
    
    public func ignore(userSession: ZMUserSession) {
        if ZMUserSession.useCallKit {
            userSession.callKitDelegate.requestEndCall(in: conversation!)
        } else {
            return currentVoiceChannel.ignore()
        }
    }
    
}
