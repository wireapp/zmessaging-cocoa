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
    
    var callState : CallState
    let sender : ZMUser
    let conversation: ZMConversation
    
    public var notifications : [UILocalNotification] = []
    
    public override var uiNotifications: [UILocalNotification] {
        return notifications
    }
    
    public init?(callState: CallState, conversation: ZMConversation, sender: ZMUser) {
        guard ZMLocalNotificationForCallState.shouldCreateNotificationFor(callState: callState) else { return nil }
        
        self.callState = callState
        self.conversation = conversation
        self.sender = sender
        
        super.init(conversationID: conversation.remoteIdentifier)
        
        let notification = configureNotification()
        notifications.append(notification)
    }
    
    func configureAlertBody() -> String {
        switch (callState) {
        case .incoming(let video):
            let baseString = video ? ZMPushStringVideoCallStarts : ZMPushStringCallStarts
            return baseString.localizedString(with: sender, conversation: conversation, count: nil)
        default :
            return ""
        }
    }
    
    var soundName : String {
        return ZMCustomSound.notificationRingingSoundName()
    }
    
    class func shouldCreateNotificationFor(callState: CallState) -> Bool {
        return .incoming(video: false) == callState
    }
    
    public func configureNotification() -> UILocalNotification {
        let notification = UILocalNotification()
        
        notification.alertBody = configureAlertBody().escapingPercentageSymbols()
        notification.soundName = soundName
        notification.category = ZMIncomingCallCategory
        notification.setupUserInfo(conversation, sender: sender)
        return notification
    }
    
}
