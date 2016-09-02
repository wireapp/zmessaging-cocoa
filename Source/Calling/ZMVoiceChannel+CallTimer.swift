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


extension ZMVoiceChannel {

    public func startTimer(){
        guard let conversation = conversation,
            let context = conversation.managedObjectContext where context.zm_isSyncContext
        else { return }
        context.zm_addAndStartCallTimer(conversation)
    }
    
    public func resetTimer(){
        guard let conversation = conversation,
            let context = conversation.managedObjectContext where context.zm_isSyncContext
        else { return }
        context.zm_resetCallTimer(conversation)
        conversation.callTimedOut = false
    }
    
    public func callTimerDidFire(timer: ZMCallTimer) {
        guard let conversation = conversation,
              let context = conversation.managedObjectContext where context.zm_isSyncContext
        else { return }
        let uiContext = context.zm_userInterfaceContext
        
        guard let uiConv = (try? uiContext.existingObjectWithID(conversation.objectID)) as? ZMConversation where !uiConv.isZombieObject
        else { return }
        
        uiContext.performGroupedBlock { () -> Void in
            if  uiConv.conversationType == .Group ||
                (uiConv.conversationType == .OneOnOne && !uiConv.isOutgoingCall)
            {
                uiConv.callTimedOut = true;
            }
            else if (uiConv.conversationType == .OneOnOne && uiConv.isOutgoingCall) {
                uiConv.voiceChannel.leave()
            }
            uiContext.enqueueDelayedSave()
        }
    }
}
