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
public protocol VoiceChannel : CallProperties, CallActions, CallObservers {
    
    func setVideoCaptureDevice(device: CaptureDevice) throws
    
}

@objc
public protocol VoiceChannelInternal : CallProperties, CallActionsInternal { }

@objc
public protocol CallProperties : NSObjectProtocol {
    
    var state: VoiceChannelV2State { get }
    
    weak var conversation : ZMConversation? { get }
    
    /// The date and time of current call start
    var callStartDate : Date? { get }
    
    /// Voice channel participants. May be a subset of conversation participants.
    var participants : NSOrderedSet { get }
    
    var selfUserConnectionState : VoiceChannelV2ConnectionState { get }
    
    func state(forParticipant: ZMUser) -> VoiceChannelV2ParticipantState
    
    var isVideoCall : Bool { get }
    var initiator : ZMUser? { get }
    
    @objc(toggleVideoActive:error:)
    func toggleVideo(active: Bool) throws
    
}

@objc
public protocol CallActions : NSObjectProtocol {
    
    func join(video: Bool, userSession: ZMUserSession) -> Bool
    func leave(userSession: ZMUserSession)
    func ignore(userSession: ZMUserSession)
    func continueByDecreasingConversationSecurity(userSession: ZMUserSession)
    func leaveAndKeepDegradedConversationSecurity(userSession: ZMUserSession)
}

@objc
public protocol CallActionsInternal : NSObjectProtocol {
    
    func join(video: Bool) -> Bool
    func leave()
    func ignore()
    
}

@objc
public protocol CallObservers : NSObjectProtocol {
    
    /// Add observer of voice channel state. Returns a token which needs to be retained as long as the observer should be active.
    func addStateObserver(_ observer: VoiceChannelStateObserver) -> WireCallCenterObserverToken
    
    /// Add observer of voice channel participants. Returns a token which needs to be retained as long as the observer should be active.
    func addParticipantObserver(_ observer: VoiceChannelParticipantObserver) -> WireCallCenterObserverToken
    
    /// Add observer of voice gain. Returns a token which needs to be retained as long as the observer should be active.
    func addVoiceGainObserver(_ observer: VoiceGainObserver) -> WireCallCenterObserverToken
    
    /// Add observer of received video. Returns a token which needs to be retained as long as the observer should be active.
    func addReceivedVideoObserver(_ observer: ReceivedVideoObserver) -> WireCallCenterObserverToken
    
    /// Add observer of the state of all voice channels. Returns a token which needs to be retained as long as the observer should be active.
    static func addStateObserver(_ observer: VoiceChannelStateObserver, userSession: ZMUserSession) -> WireCallCenterObserverToken
    
}
