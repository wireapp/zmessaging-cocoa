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

extension PushNotificationCategory {
    func addMuteIfNeeded(hasTeam: Bool) -> PushNotificationCategory {
        guard !hasTeam else {
            return self
        }
        
        switch self {
        case .conversation:
            return .conversationWithMute
        case .conversationWithLike:
            return .conversationWithLikeAndMute
        default:
            return self
        }
    }
}

extension LocalNotificationType {
    
    func category(hasTeam: Bool) -> String {
        let category: PushNotificationCategory
        
        switch self {
        case .calling(let callState):
            switch (callState) {
            case .incoming:
                category = .incomingCall
            case .terminating(reason: .timeout):
                category = .missedCall
            default :
                category = PushNotificationCategory.conversation.addMuteIfNeeded(hasTeam: hasTeam)
            }
        case .event(let eventType):
            switch eventType {
            case .connectionRequestPending, .conversationCreated:
                category = .connect
            default:
                category = PushNotificationCategory.conversation.addMuteIfNeeded(hasTeam: hasTeam)
            }
        case .message(let contentType):
            switch contentType {
            case .audio, .video, .fileUpload, .image, .text, .location:
                category = PushNotificationCategory.conversationWithLike.addMuteIfNeeded(hasTeam: hasTeam)
            case .hidden:
                category = .alert
            default:
                category = PushNotificationCategory.conversation.addMuteIfNeeded(hasTeam: hasTeam)
            }
        case .failedMessage:
            category = PushNotificationCategory.conversation.addMuteIfNeeded(hasTeam: hasTeam)
        case .availabilityBehaviourChangeAlert:
            category = PushNotificationCategory.alert
        }
        
        return category.rawValue
    }
    
    var sound: NotificationSound {
        switch self {
        case .calling(let callState):
            switch callState {
            case .incoming:
                return .call
            default:
                return .newMessage
            }
        case .event:
            return .newMessage
        case .message(let contentType):
            switch contentType {
            case .knock:
                return .ping
            default:
                return .newMessage
            }
        case .failedMessage, .availabilityBehaviourChangeAlert:
            return .newMessage
        }
    }
    
}
