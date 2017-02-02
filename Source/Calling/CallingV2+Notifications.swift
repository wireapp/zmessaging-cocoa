//
//  CallingV2+Notifications.swift
//  zmessaging-cocoa
//
//  Created by Sabine Geithner on 02/02/17.
//  Copyright © 2017 Zeta Project Gmbh. All rights reserved.
//

import Foundation

///////////
//// VoiceGainObserver
//////////

@objc
public protocol VoiceGainObserver : class {
    func voiceGainDidChange(forParticipant participant: ZMUser, volume: Float)
}

@objc
public class VoiceGainNotification : NSObject  {
    
    public static let notificationName = Notification.Name("VoiceGainNotification")
    public static let userInfoKey = notificationName.rawValue
    
    public let volume : Float
    public let userId : UUID
    public let conversationId : UUID
    
    public init(volume: Float, conversationId: UUID, userId: UUID) {
        self.volume = volume
        self.conversationId = conversationId
        self.userId = userId
        
        super.init()
    }
    
    public var notification : Notification {
        return Notification(name: VoiceGainNotification.notificationName,
                            object: conversationId as NSUUID,
                            userInfo: [VoiceGainNotification.userInfoKey : self])
    }
    
    public func post() {
        NotificationCenter.default.post(notification)
    }
}


///////////
//// CallEndedObserver
//////////

@objc
public class CallEndedNotification : NSObject {
    
    public static let notificationName = Notification.Name("CallEndedNotification")
    public static let userInfoKey = notificationName.rawValue
    
    public let reason : VoiceChannelV2CallEndReason
    public let conversationId : UUID
    
    public init(reason: VoiceChannelV2CallEndReason, conversationId: UUID) {
        self.reason = reason
        self.conversationId = conversationId
        
        super.init()
    }
    
    public func post() {
        NotificationCenter.default.post(name: CallEndedNotification.notificationName,
                                        object: nil,
                                        userInfo: [CallEndedNotification.userInfoKey : self])
    }
}




////////
//// VoiceChannelStateObserver
///////

@objc
public protocol WireCallCenterV2CallStateObserver : class {
    
    @objc(callCenterDidChangeVoiceChannelState:conversation:)
    func callCenterDidChange(voiceChannelState: VoiceChannelV2State, conversation: ZMConversation)
}


struct VoiceChannelStateNotification {
    
    static let notificationName = Notification.Name("VoiceChannelStateNotification")
    static let userInfoKey = notificationName.rawValue
    
    let voiceChannelState : VoiceChannelV2State
    let conversationId : NSManagedObjectID
    
    func post() {
        NotificationCenter.default.post(name: VoiceChannelStateNotification.notificationName,
                                        object: nil,
                                        userInfo: [VoiceChannelStateNotification.userInfoKey : self])
    }
}



///////////
//// VoiceChannelParticipantsObserver
///////////

@objc
public protocol VoiceChannelParticipantObserver : class {
    func voiceChannelParticipantsDidChange(_ changeInfo : SetChangeInfo)
}

struct VoiceChannelParticipantNotification {

    static let notificationName = Notification.Name("VoiceChannelParticipantNotification")
    static let userInfoKey = notificationName.rawValue
    let setChangeInfo : SetChangeInfo
    let conversation : ZMConversation
    
    func post() {
        NotificationCenter.default.post(name: VoiceChannelParticipantNotification.notificationName,
                                        object: conversation,
                                        userInfo: [VoiceChannelParticipantNotification.userInfoKey : self])
    }
}



///////
//// VideoObserver
//////

struct VoiceChannelVideoChangedNotification {
    
    static let notificationName = Notification.Name("VoiceChannelVideoChangedNotification")
    static let userInfoKey = notificationName.rawValue
    let receivedVideoState : ReceivedVideoState
    let conversation : ZMConversation
    
    func post() {
        NotificationCenter.default.post(name: VoiceChannelVideoChangedNotification.notificationName,
                                        object: conversation,
                                        userInfo: [VoiceChannelVideoChangedNotification.userInfoKey : self])
    }
}


