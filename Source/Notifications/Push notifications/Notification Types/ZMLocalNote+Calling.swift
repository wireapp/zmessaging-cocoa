//
// Wire
// Copyright (C) 2017 Wire Swiss GmbH
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


// MARK: - Calling

extension ZMLocalNote {
    
    convenience init?(callState: CallState, conversation: ZMConversation, sender: ZMUser) {
        guard conversation.remoteIdentifier != nil else { return nil }
        let constructor = CallNotificationConstructor(callState: callState, sender: sender, conversation: conversation)
        self.init(conversation: conversation, type: .calling(callState), constructor: constructor)
    }
    
    private class CallNotificationConstructor: NotificationConstructor {
        
        let callState: CallState
        let sender: ZMUser
        let conversation: ZMConversation
        
        init(callState: CallState, sender: ZMUser, conversation: ZMConversation) {
            self.callState = callState
            self.sender = sender
            self.conversation = conversation
        }
        
        func shouldCreateNotification() -> Bool {
            switch callState {
            case .terminating(reason: .anweredElsewhere), .terminating(reason: .normal):
                return false
            case .incoming(video: _, shouldRing: let shouldRing, degraded: _):
                return shouldRing
            case .terminating, .none:
                return true
            default:
                return false
            }
        }
        
        func bodyText() -> String {
            
            var text: String?
            
            switch (callState) {
            case .incoming(video: let video, shouldRing: _, degraded: _):
                let baseString = video ? ZMPushStringVideoCallStarts : ZMPushStringCallStarts
                text = baseString.localizedString(with: sender, conversation: conversation, count: nil)
            case .terminating, .none:   // TODO: missed call count
                text = ZMPushStringCallMissed.localizedString(with: sender, conversation: conversation, count: 1)
            default :
                break
            }
            
            if nil != text {
                text = text!.escapingPercentageSymbols()
            }

            return text ?? ""
        }
        
        func category() -> String {
            switch (callState) {
            case .incoming:
                return ZMIncomingCallCategory
            case .terminating(reason: .timeout):
                return ZMMissedCallCategory
            default :
                return ZMConversationCategory
            }
        }

        func soundName() -> String {
            if case .incoming = callState {
                return ZMCustomSound.notificationRingingSoundName()
            } else {
                return ZMCustomSound.notificationNewMessageSoundName()
            }
        }
        
        func userInfo() -> [AnyHashable: Any]? {
            
            guard
                let moc = conversation.managedObjectContext,
                let selfUserID = ZMUser.selfUser(in: moc).remoteIdentifier,
                let senderID = sender.remoteIdentifier,
                let conversationID = conversation.remoteIdentifier
                else { return nil }
            
            var userInfo = [AnyHashable: Any]()
            userInfo[SelfUserIDStringKey] = selfUserID.transportString()
            userInfo[SenderIDStringKey] = senderID.transportString()
            userInfo[ConversationIDStringKey] = conversationID.transportString()
            return userInfo
        }
    }
}
