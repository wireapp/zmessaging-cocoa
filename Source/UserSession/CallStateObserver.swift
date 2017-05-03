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
import CoreData

@objc(ZMCallStateObserver)
public final class CallStateObserver : NSObject {
    
    static public let CallInProgressNotification = Notification.Name(rawValue: "ZMCallInProgressNotification")
    static public let CallInProgressKey = "callInProgress"
    
    fileprivate weak var userSession: ZMUserSession?
    fileprivate let localNotificationDispatcher : LocalNotificationDispatcher
    fileprivate let syncManagedObjectContext : NSManagedObjectContext
    fileprivate var callStateToken : WireCallCenterObserverToken? = nil
    fileprivate var missedCalltoken : WireCallCenterObserverToken? = nil
    fileprivate let systemMessageGenerator = CallSystemMessageGenerator()
    fileprivate var voiceChannelStatetoken : WireCallCenterObserverToken? = nil

    deinit {
        if let token = callStateToken {
            WireCallCenterV3.removeObserver(token: token)
        }
        if let token = missedCalltoken {
            WireCallCenterV3.removeObserver(token: token)
        }
    }
    
    public init(localNotificationDispatcher : LocalNotificationDispatcher, userSession: ZMUserSession) {
        self.userSession = userSession
        self.localNotificationDispatcher = localNotificationDispatcher
        self.syncManagedObjectContext = userSession.syncManagedObjectContext
        
        super.init()
        
        self.callStateToken = WireCallCenterV3.addCallStateObserver(observer: self)
        self.missedCalltoken = WireCallCenterV3.addMissedCallObserver(observer: self)
        self.voiceChannelStatetoken = WireCallCenter.addVoiceChannelStateObserver(observer: self, context: userSession.managedObjectContext)
    }
    
    fileprivate var callInProgress : Bool = false {
        didSet {
            if callInProgress != oldValue {
                NotificationCenter.default.post(name: CallStateObserver.CallInProgressNotification, object: nil, userInfo: [ CallStateObserver.CallInProgressKey : callInProgress ])
            }
        }
    }
    
}

extension CallStateObserver : WireCallCenterCallStateObserver, WireCallCenterMissedCallObserver  {
    
    public func callCenterDidChange(callState: CallState, conversationId: UUID, userId: UUID?, timeStamp: Date?) {
        
        syncManagedObjectContext.performGroupedBlock {
            guard
                let userId = userId,
                let conversation = ZMConversation(remoteID: conversationId, createIfNeeded: false, in: self.syncManagedObjectContext),
                let user = ZMUser(remoteID: userId, createIfNeeded: false, in: self.syncManagedObjectContext)
            else {
                return
            }
            
            if !ZMUserSession.useCallKit {
                self.localNotificationDispatcher.process(callState: callState, in: conversation, sender: user)
            }
            
            self.updateConversationListIndicator(convObjectID: conversation.objectID, callState: callState)
            
            self.systemMessageGenerator.callCenterDidChange(callState: callState, conversation: conversation, user: user, timeStamp: timeStamp)
            self.updateLastModifiedDate(callState: callState, in: conversation, timeStamp: timeStamp)
            self.syncManagedObjectContext.enqueueDelayedSave()
        }
    }
    
    public func updateConversationListIndicator(convObjectID: NSManagedObjectID, callState: CallState){
        // We need to switch to the uiContext here because we are making changes that need to be present on the UI when the change notification fires
        guard let uiMOC = self.syncManagedObjectContext.zm_userInterface else { return }
        uiMOC.performGroupedBlock {
            guard let uiConv = (try? uiMOC.existingObject(with: convObjectID)) as? ZMConversation else { return }
            
            switch callState {
            case .incoming(video: _, shouldRing: let shouldRing):
                uiConv.isIgnoringCallV3 = uiConv.isSilenced || !shouldRing
                uiConv.isCallDeviceActiveV3 = false
            case .terminating, .none:
                uiConv.isCallDeviceActiveV3 = false
                uiConv.isIgnoringCallV3 = false
            case .outgoing, .answered, .established:
                uiConv.isCallDeviceActiveV3 = true
            case .unknown:
                break
            }
            
            if uiMOC.zm_hasChanges {
                NotificationDispatcher.notifyNonCoreDataChanges(objectID: convObjectID,
                                                                changedKeys: [ZMConversationListIndicatorKey],
                                                                uiContext: uiMOC)
            }
        }
    }
    
    public func callCenterMissedCall(conversationId: UUID, userId: UUID, timestamp: Date, video: Bool) {
        syncManagedObjectContext.performGroupedBlock {
            guard
                let conversation = ZMConversation(remoteID: conversationId, createIfNeeded: false, in: self.syncManagedObjectContext),
                let user = ZMUser(remoteID: userId, createIfNeeded: false, in: self.syncManagedObjectContext)
                else {
                    return
            }
            
            if !ZMUserSession.useCallKit {
                self.localNotificationDispatcher.processMissedCall(in: conversation, sender: user)
            }
            
            conversation.appendMissedCallMessage(fromUser: user, at: timestamp)
            self.syncManagedObjectContext.enqueueDelayedSave()
        }
    }

}

extension CallStateObserver : VoiceChannelStateObserver {
    
    public func callCenterDidChange(voiceChannelState: VoiceChannelV2State, conversation: ZMConversation, callingProtocol: CallingProtocol) {
        guard let userSession = userSession else { return }
        callInProgress = WireCallCenter.nonIdleCallConversations(inUserSession: userSession).count > 0
    }
    
    public func callCenterDidFailToJoinVoiceChannel(error: Error?, conversation: ZMConversation) {
        // no-op
    }
    
    public func callCenterDidEndCall(reason: VoiceChannelV2CallEndReason, conversation: ZMConversation, callingProtocol: CallingProtocol) {
        // no-op
    }
    
    func updateLastModifiedDate(callState: CallState, in conversation: ZMConversation, timeStamp: Date?) {
        if case .incoming = callState, let timeStamp = timeStamp {
            conversation.updateLastModifiedDateIfNeeded(timeStamp)
        }
    }
    
}

