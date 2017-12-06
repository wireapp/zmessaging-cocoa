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

extension ZMLocalNotification {
    
    convenience init?(callState: CallState, conversation: ZMConversation, caller: ZMUser) {
        guard conversation.remoteIdentifier != nil else { return nil }
        let builder = CallNotificationBuilder(callState: callState, caller: caller, conversation: conversation)
        self.init(conversation: conversation, type: .calling(callState), builder: builder)
    }
    
    private class CallNotificationBuilder: NotificationBuilder {
        
        let callState: CallState
        let caller: ZMUser
        var conversation: ZMConversation?
        private var teamName: String?
        
        let ignoredCallStates : [CallState] = [
            .established, .answered(degraded: false), .outgoing(degraded: false), .none, .unknown
        ]
        
        init(callState: CallState, caller: ZMUser, conversation: ZMConversation) {
            self.callState = callState
            self.caller = caller
            self.conversation = conversation
        }
        
        func shouldCreateNotification() -> Bool {
            switch callState {
            case .terminating(reason: .anweredElsewhere), .terminating(reason: .normal):
                return false
            case .incoming(video: _, shouldRing: let shouldRing, degraded: _):
                return shouldRing
            case .terminating:
                return true
            default:
                return false
            }
        }
        
        func titleText() -> String? {
            if let moc = conversation?.managedObjectContext {
                teamName = ZMUser.selfUser(in: moc).team?.name
            }
            
            return ZMPushStringTitle.localizedString(withConversationName: conversation?.meaningfulDisplayName, teamName: teamName)
        }
        
        func bodyText() -> String {
            
            var text = ""
            var key: String?
            
            switch (callState) {
            case .incoming(video: let video, shouldRing: _, degraded: _):
                key = video ? ZMPushStringVideoCallStarts : ZMPushStringCallStarts
            case .terminating, .none:
                key = ZMPushStringCallMissed
            default :
                break
            }
            
            if nil != key {
                text = key!.localizedString(with: caller, conversation: conversation) ?? ""
            }
            
            return text.escapingPercentageSymbols()
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
                let moc = conversation?.managedObjectContext,
                let selfUserID = ZMUser.selfUser(in: moc).remoteIdentifier,
                let senderID = caller.remoteIdentifier,
                let conversationID = conversation?.remoteIdentifier
                else { return nil }
            
            var userInfo = [AnyHashable: Any]()
            userInfo[SelfUserIDStringKey] = selfUserID.transportString()
            userInfo[SenderIDStringKey] = senderID.transportString()
            userInfo[ConversationIDStringKey] = conversationID.transportString()
            userInfo[ConversationNameStringKey] = conversation?.meaningfulDisplayName
            userInfo[TeamNameStringKey] = teamName
            return userInfo
        }
    }
}
