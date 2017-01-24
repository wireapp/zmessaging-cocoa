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
    
    let localNotificationDispatcher : ZMLocalNotificationDispatcher
    let managedObjectContext : NSManagedObjectContext
    var callStateToken : WireCallCenterObserverToken? = nil
    var missedCalltoken : WireCallCenterObserverToken? = nil
    
    deinit {
        if let token = callStateToken {
            WireCallCenterV3.removeObserver(token: token)
        }
        if let token = missedCalltoken {
            WireCallCenterV3.removeObserver(token: token)
        }
    }
    
    public init(localNotificationDispatcher : ZMLocalNotificationDispatcher, managedObjectContext: NSManagedObjectContext) {
        self.localNotificationDispatcher = localNotificationDispatcher
        self.managedObjectContext = managedObjectContext
        
        super.init()
        
        self.callStateToken = WireCallCenterV3.addCallStateObserver(observer: self)
        self.missedCalltoken = WireCallCenterV3.addMissedCallObserver(observer: self)
    }
    
}

extension CallStateObserver : WireCallCenterCallStateObserver, WireCallCenterMissedCallObserver  {
    
    public func callCenterDidChange(callState: CallState, conversationId: UUID, userId: UUID?) {
        guard !ZMUserSession.useCallKit else { return }
        
        managedObjectContext.performGroupedBlock {
            guard
                let userId = userId,
                let conversation = ZMConversation(remoteID: conversationId, createIfNeeded: false, in: self.managedObjectContext),
                let caller = ZMUser(remoteID: userId, createIfNeeded: false, in: self.managedObjectContext)
                else {
                    return
            }
            
            self.localNotificationDispatcher.process(callState: callState, in: conversation, sender: caller)
            
            if case .terminating(let reason) = callState, reason == .canceled || reason == .timeout {
                conversation.appendMissedCallMessage(fromUser: caller, at: Date())
            }
        }
    }
    
    public func callCenterMissedCall(conversationId: UUID, userId: UUID, timestamp: Date, video: Bool) {
        guard !ZMUserSession.useCallKit else { return }
        
        managedObjectContext.performGroupedBlock {
            guard
                let conversation = ZMConversation(remoteID: conversationId, createIfNeeded: false, in: self.managedObjectContext),
                let caller = ZMUser(remoteID: userId, createIfNeeded: false, in: self.managedObjectContext)
                else {
                    return
            }
            
            self.localNotificationDispatcher.processMissedCall(in: conversation, sender: caller)
            
            conversation.appendMissedCallMessage(fromUser: caller, at: timestamp)
        }
    }
    
    
}
