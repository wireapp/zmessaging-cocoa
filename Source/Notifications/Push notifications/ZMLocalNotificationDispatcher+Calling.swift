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

public extension ZMLocalNotificationDispatcher {
    
    public func process(callState: CallState, in conversation: ZMConversation, sender: ZMUser) {
        
        let note =  notification(for: conversation, sender: sender)
        
        callingNotifications.cancelNotifications(conversation)
        
        note.update(forCallState: callState)
        scheduleNotification(note)
    }
    
    public func processMissedCall(in conversation: ZMConversation, sender: ZMUser) {
        let note =  notification(for: conversation, sender: sender)
        
        callingNotifications.cancelNotifications(conversation)
        
        note.updateForMissedCall()
        scheduleNotification(note)
    }
    
    private func scheduleNotification(_ note: ZMLocalNotification) {
        if let uiNote = note.uiNotifications.first {
            callingNotifications.addObject(note)
            (sharedApplicationForSwift as! Application).scheduleLocalNotification(uiNote)
        }
    }
    
    private func notification(for conversation: ZMConversation, sender: ZMUser) -> ZMLocalNotificationForCallState {
        if let existingNote = callingNotifications.notifications.first(where: { (note) -> Bool in note.conversationID == conversation.remoteIdentifier }), let callStateNote = existingNote as? ZMLocalNotificationForCallState {
            return callStateNote
        }
        
        return ZMLocalNotificationForCallState(conversation: conversation, sender: sender)
    }
    
}
