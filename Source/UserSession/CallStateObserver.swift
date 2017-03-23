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
    
    public func callCenterDidChange(callState: CallState, conversationId: UUID, userId: UUID?) {
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
            
            self.callingSystemMessageGenerator.process(callState: callState, in: conversation, sender: user)
            self.managedObjectContext.enqueueDelayedSave()
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
    
    func process(callState: CallState, in conversation: ZMConversation, sender: ZMUser) {
        
        switch callState {
        case .incoming, .outgoing:
            callers[conversation] = sender
        case .terminating(reason: .canceled):
            let caller = callers[conversation] ?? sender
            conversation.appendMissedCallMessage(fromUser: caller, at: Date())
        case .terminating(reason: .timeout):
            conversation.appendPerformedCallMessage(with: 0, caller: sender)
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
