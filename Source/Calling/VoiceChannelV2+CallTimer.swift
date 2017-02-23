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


extension VoiceChannelV2 {

    public func startTimer(){
        guard let conversation = conversation,
            let context = conversation.managedObjectContext , context.zm_isSyncContext
        else { return }
        context.zm_addAndStartCallTimer(conversation)
    }
    
    public func resetTimer(){
        guard let conversation = conversation,
            let context = conversation.managedObjectContext , context.zm_isSyncContext
        else { return }
        context.zm_resetCallTimer(conversation)
        conversation.callTimedOut = false
    }
    
    public func callTimerDidFire(_ timer: ZMCallTimer) {
        guard let conversation = conversation,
              let context = conversation.managedObjectContext , context.zm_isSyncContext
        else { return }
        let uiContext = context.zm_userInterface
        
        uiContext?.performGroupedBlock { () -> Void in
            guard let uiConv = (try? uiContext?.existingObject(with: conversation.objectID)) as? ZMConversation, !uiConv.isZombieObject
                else { return }

            if  uiConv.conversationType == .group ||
                (uiConv.conversationType == .oneOnOne && !uiConv.isOutgoingCall)
            {
                uiConv.callTimedOut = true;
            }
            else if (uiConv.conversationType == .oneOnOne && uiConv.isOutgoingCall) {
                uiConv.voiceChannelRouter?.v2.leave()
            }
            uiContext?.enqueueDelayedSave()
        }
    }
}
