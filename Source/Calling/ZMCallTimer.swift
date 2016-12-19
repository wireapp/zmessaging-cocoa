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
import CoreData
import ZMCSystem


private let zmLog = ZMSLog(tag: "Calling")

private let ZMVoiceChannelTimerTimeOutGroup : TimeInterval = 30;
private let ZMVoiceChannelTimerTimeOutOneOnOne : TimeInterval = 60;
private var ZMVoiceChannelTimerTestTimeout : TimeInterval = 0;

private let UserInfoCallTimerKey = "ZMCallTimer"

extension NSManagedObjectContext {
    
    fileprivate var zm_callTimer: ZMCallTimer {
        if self.zm_isUserInterfaceContext {
            zmLog.warn("CallTimer should only be set on syncContext")
        }
        let oldTimer = self.userInfo[UserInfoCallTimerKey] as? ZMCallTimer
        return oldTimer ?? { () -> ZMCallTimer in
            let timer = ZMCallTimer(managedObjectContext: self)
            zmLog.debug("creating new timer")
            self.userInfo[UserInfoCallTimerKey] = timer
            return timer
            }()
    }
    
    public func zm_addAndStartCallTimer(_ conversation: ZMConversation) {
        if self.zm_isUserInterfaceContext {
            zmLog.warn("CallTimer should not be initiated on uiContext")
        }
        self.zm_callTimer.addAndStartTimer(conversation)
    }
    
    public func zm_resetCallTimer(_ conversation: ZMConversation) {
        if self.zm_isUserInterfaceContext {
            zmLog.warn("CallTimer can not be cancelled on uiContext")
        }
        self.zm_callTimer.resetTimer(conversation)
    }
    
    public func zm_tearDownCallTimer() {
        let oldTimer = self.userInfo[UserInfoCallTimerKey] as? ZMCallTimer
        oldTimer?.tearDown()
    }
    
    public func zm_hasTimerForConversation(_ conversation: ZMConversation) -> Bool {
        return self.zm_callTimer.conversationIDToTimerMap[conversation.objectID] != nil
    }
}

public protocol ZMCallTimerClient {

    func callTimerDidFire(_ timer: ZMCallTimer)
}

public final class ZMCallTimer : NSObject, ZMTimerClient {

    public var conversationIDToTimerMap: [NSManagedObjectID: ZMTimer] = [:]
    fileprivate weak var managedObjectContext: NSManagedObjectContext?
    
    public var testDelegate: ZMCallTimerClient?
    fileprivate var testTimeout : TimeInterval {
        return ZMVoiceChannelTimerTestTimeout
    }
    
    public init(managedObjectContext: NSManagedObjectContext) {
        self.managedObjectContext = managedObjectContext
    }
    
    public class func setTestCallTimeout(_ timeout: TimeInterval) {
        ZMVoiceChannelTimerTestTimeout = timeout
    }
    
    public class func resetTestCallTimeout() {
        ZMVoiceChannelTimerTestTimeout = 0
    }
    
    public func addAndStartTimer(_ conversation: ZMConversation) {
        let objectID = conversation.objectID
        if conversationIDToTimerMap[objectID] == nil && !conversation.callTimedOut {
            let timeOut = (testTimeout > 0) ? testTimeout : conversation.conversationType == .group ? ZMVoiceChannelTimerTimeOutGroup : ZMVoiceChannelTimerTimeOutOneOnOne
            let timer = ZMTimer(target: self)
            timer?.fire(at: Date().addingTimeInterval(timeOut))
            conversationIDToTimerMap[objectID] = timer
        }
    }
    
    public func resetTimer(_ conversation: ZMConversation) {
        cancelAndRemoveTimer(conversation.objectID)
    }
    
    fileprivate func cancelAndRemoveTimer(_ conversationID: NSManagedObjectID) {
        let timer = conversationIDToTimerMap[conversationID]
        if let timer = timer {
            timer.cancel()
        }
        conversationIDToTimerMap.removeValue(forKey: conversationID)
    }
    
    public func timerDidFire(_ aTimer: ZMTimer) {
        for (conversationID, timer) in conversationIDToTimerMap {
            if timer != aTimer {
                return
            }
            self.cancelAndRemoveTimer(conversationID)
            if let testDelegate = self.testDelegate {
                testDelegate.callTimerDidFire(self)
            }
            guard let conversation = self.managedObjectContext?.object(with: conversationID) as? ZMConversation , !conversation.isZombieObject
            else { return }
            conversation.voiceChannel?.v2.callTimerDidFire(self)
            
            break;
        }
    }
    
    public func tearDown() {
        for timer in Array(conversationIDToTimerMap.values) {
            timer.cancel()
        }
        conversationIDToTimerMap = [:]
    }

}
