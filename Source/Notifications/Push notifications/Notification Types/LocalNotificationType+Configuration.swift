//
// Wire
// Copyright (C) 2018 Wire Swiss GmbH
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

extension LocalNotificationType {
    
    var category: String {
        switch self {
        case .calling(let callState):
            switch (callState) {
            case .incoming:
                return ZMIncomingCallCategory
            case .terminating(reason: .timeout):
                return ZMMissedCallCategory
            default :
                return ZMConversationCategory
            }
        case .event(let eventType):
            switch eventType {
            case .connectionRequestPending, .conversationCreated:
                return ZMConnectCategory
            default:
                return ZMConversationCategory
            }
        case .message(let contentType):
            switch contentType {
            case .audio, .video, .fileUpload, .image, .text, .location:
                return ZMConversationCategoryIncludingLike
            default:
                return ZMConversationCategory
            }
        case .failedMessage:
            return ZMConversationCategory
        }
    }
    
    var soundName: String {
        switch self {
        case .calling(let callState):
            switch callState {
            case .incoming:
                return ZMCustomSound.notificationRingingSoundName()
            default:
                return ZMCustomSound.notificationNewMessageSoundName()
            }
        case .event:
            return ZMCustomSound.notificationNewMessageSoundName()
        case .message(let contentType):
            switch contentType {
            case .knock:
                return ZMCustomSound.notificationPingSoundName()
            default:
                return ZMCustomSound.notificationNewMessageSoundName()
            }
        case .failedMessage:
            return ZMCustomSound.notificationNewMessageSoundName()
        }
    }
    
}
