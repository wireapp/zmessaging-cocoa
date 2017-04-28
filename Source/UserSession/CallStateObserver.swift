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
    
    fileprivate let localNotificationDispatcher : LocalNotificationDispatcher
    fileprivate let callingSystemMessageGenerator = CallingSystemMessageGenerator()
    fileprivate let managedObjectContext : NSManagedObjectContext
    fileprivate var callStateToken : WireCallCenterObserverToken? = nil
    fileprivate var missedCalltoken : WireCallCenterObserverToken? = nil
    
    deinit {
        if let token = callStateToken {
            WireCallCenterV3.removeObserver(token: token)
        }
        if let token = missedCalltoken {
            WireCallCenterV3.removeObserver(token: token)
        }
    }
    
    public init(localNotificationDispatcher : LocalNotificationDispatcher, managedObjectContext: NSManagedObjectContext) {
        self.localNotificationDispatcher = localNotificationDispatcher
        self.managedObjectContext = managedObjectContext
        
        super.init()
        
        self.callStateToken = WireCallCenterV3.addCallStateObserver(observer: self)
        self.missedCalltoken = WireCallCenterV3.addMissedCallObserver(observer: self)
    }
    
}

extension CallStateObserver : WireCallCenterCallStateObserver, WireCallCenterMissedCallObserver  {
    
    public func callCenterDidChange(callState: CallState, conversationId: UUID, userId: UUID?, timeStamp: Date?) {
        notifyIfWebsocketShouldBeOpen(forCallState: callState)
        
        managedObjectContext.performGroupedBlock {
            guard
                let userId = userId,
                let conversation = ZMConversation(remoteID: conversationId, createIfNeeded: false, in: self.managedObjectContext),
                let user = ZMUser(remoteID: userId, createIfNeeded: false, in: self.managedObjectContext)
            else {
                return
            }
            
            if !ZMUserSession.useCallKit {
                self.localNotificationDispatcher.process(callState: callState, in: conversation, sender: user)
            }
            
            self.updateConversationListIndicator(convObjectID: conversation.objectID, callState: callState)
            
            self.callingSystemMessageGenerator.process(callState: callState, in: conversation, sender: user, timeStamp: timeStamp)
            self.managedObjectContext.enqueueDelayedSave()
        }
    }
    
    public func updateConversationListIndicator(convObjectID: NSManagedObjectID, callState: CallState){
        // We need to switch to the uiContext here because we are making changes that need to be present on the UI when the change notification fires
        guard let uiMOC = self.managedObjectContext.zm_userInterface else { return }
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
        managedObjectContext.performGroupedBlock {
            guard
                let conversation = ZMConversation(remoteID: conversationId, createIfNeeded: false, in: self.managedObjectContext),
                let user = ZMUser(remoteID: userId, createIfNeeded: false, in: self.managedObjectContext)
                else {
                    return
            }
            
            if !ZMUserSession.useCallKit {
                self.localNotificationDispatcher.processMissedCall(in: conversation, sender: user)
            }
            
            self.callingSystemMessageGenerator.processMissedCall(in: conversation, from: user, at: timestamp)
            self.managedObjectContext.enqueueDelayedSave()
        }
    }
    
    private func notifyIfWebsocketShouldBeOpen(forCallState callState: CallState) {
        
        let notificationName = Notification.Name(rawValue: ZMTransportSessionShouldKeepWebsocketOpenNotificationName)
        
        switch callState {
        case .terminating:
            NotificationCenter.default.post(name: notificationName, object: nil, userInfo: [ZMTransportSessionShouldKeepWebsocketOpenKey : false])
        case .outgoing, .incoming:
            NotificationCenter.default.post(name: notificationName, object: nil, userInfo: [ZMTransportSessionShouldKeepWebsocketOpenKey : true])
        default:
            break
        }
    }
    
}

private final class CallingSystemMessageGenerator {
    
    var callers : [ZMConversation : ZMUser] = [:]
    
    func process(callState: CallState, in conversation: ZMConversation, sender: ZMUser, timeStamp: Date?) {
        
        switch callState {
        case .incoming, .outgoing:
            callers[conversation] = sender
            if let timeStamp = timeStamp {
                conversation.updateLastModifiedDateIfNeeded(timeStamp)
            }
        case .terminating(reason: .canceled):
            let caller = callers[conversation] ?? sender
            conversation.appendMissedCallMessage(fromUser: caller, at: Date())
        default:
            break
        }
        
        if case .terminating = callState {
            callers.removeValue(forKey: conversation)
        }
    }
    
    func processMissedCall(in conversation: ZMConversation, from user: ZMUser, at timestamp: Date) {
        conversation.appendMissedCallMessage(fromUser: user, at: timestamp)
    }
    
}
