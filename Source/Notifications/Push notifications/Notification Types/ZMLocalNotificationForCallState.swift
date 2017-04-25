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

final public class ZMLocalNotificationForCallState : ZMLocalNotification {
    
    var callState : CallState = .none
    var numberOfMissedCalls = 0
    let sender : ZMUser
    let conversation: ZMConversation
    
    public var notifications : [UILocalNotification] = []
    
    public override var uiNotifications: [UILocalNotification] {
        return notifications
    }
    
    public init(conversation: ZMConversation, sender: ZMUser) {
        
        self.conversation = conversation
        self.sender = sender
        
        super.init(conversationID: conversation.remoteIdentifier)
    }
    
    public func update(forCallState callState: CallState) {
        self.callState = callState
        
        notifications.removeAll()
        
        guard shouldCreateNotificationFor(callState: callState) else { return }
        
        let notification = configureNotification()
        notifications.append(notification)
    }
    
    public func updateForMissedCall() {
        self.callState = .none
        self.numberOfMissedCalls += 1
        
        notifications.removeAll()
        
        let notification = configureNotification()
        notifications.append(notification)
    }
    
    func configureAlertBody() -> String {
        switch (callState) {
        case .incoming(video: let video, shouldRing: _):
            let baseString = video ? ZMPushStringVideoCallStarts : ZMPushStringCallStarts
            return baseString.localizedString(with: sender, conversation: conversation, count: nil)
        case .terminating,
             .none where numberOfMissedCalls > 0:
            return ZMPushStringCallMissed.localizedString(with: sender, conversation: conversation, count: NSNumber(value: max(numberOfMissedCalls, 1)))
        default :
            return ""
        }
    }
    
    var soundName : String {
        if case .incoming = callState {
            return ZMCustomSound.notificationRingingSoundName()
        } else {
            return ZMCustomSound.notificationNewMessageSoundName()
        }
    }
    
    var category : String {
        switch (callState) {
        case .incoming:
            return ZMIncomingCallCategory
        case .terminating(reason: .timeout),
             .none where numberOfMissedCalls > 0:
            return ZMMissedCallCategory
        default :
            return ZMConversationCategory
        }
    }
    
    func shouldCreateNotificationFor(callState: CallState) -> Bool {
        switch callState {
        case .terminating(reason: .anweredElsewhere), .terminating(reason: .normal):
            return false
        case .incoming,
             .terminating,
             .none where numberOfMissedCalls > 0:
            return true
        default:
            return false
        }
    }
    
    public func configureNotification() -> UILocalNotification {
        let notification = UILocalNotification()
        
        notification.alertBody = configureAlertBody().escapingPercentageSymbols()
        notification.soundName = soundName
        notification.category = category
        notification.setupUserInfo(conversation, sender: sender)
        return notification
    }
    
}
