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

// MARK: - Push Notification Categories

fileprivate extension String {
    
    var localizedPushAction: String {
        return Bundle(for: ZMUserSession.self).localizedString(forKey: "push.notification.action.\(self)", value: "", table: "Push")
    }
    
}

enum PushNotificationCategory: String {
    
    case incomingCall = "incomingCallCategory"
    case missedCall = "missedCallCategory"
    case conversation = "conversationCategory"
    case conversationIncludingLike = "conversationCategoryWithLike"
    case connect = "connectCategory"
    
    static var allCategories: Set<UIUserNotificationCategory> {
        let categories = [PushNotificationCategory.incomingCall,
                          PushNotificationCategory.missedCall,
                          PushNotificationCategory.conversation,
                          PushNotificationCategory.conversationIncludingLike,
                          PushNotificationCategory.connect].map({ $0.userNotificationCategory })
        return Set<UIUserNotificationCategory>(categories)
    }
    
    var userNotificationCategory: UIUserNotificationCategory {
        
        let category = UIMutableUserNotificationCategory()
        var actions: [UIUserNotificationAction]? = nil
        
        category.identifier = rawValue
        
        switch self {
        case .incomingCall:
            actions = [CallAction.ignore, CallAction.message].map({ $0.notificationAction })
        case .missedCall:
            actions = [CallAction.callBack, CallAction.message].map({ $0.notificationAction })
        case .conversation:
            actions = [ConversationAction.reply, ConversationAction.mute].map({ $0.notificationAction })
        case .conversationIncludingLike:
            actions = [ConversationAction.reply, ConversationAction.like, ConversationAction.mute].map({ $0.notificationAction })
        case .connect:
            actions = [ConversationAction.connect].map({ $0.notificationAction })
        }
        
        category.setActions(actions, for: .default)
        category.setActions(actions, for: .minimal)
        
        return category
    }
    
    enum ConversationAction: String {
        case open = "conversationOpenAction"
        case reply = "conversationDirectReplyAction"
        case mute = "conversationMuteAction"
        case like = "messageLikeAction"
        case connect = "acceptConnectAction"
        
        var notificationAction: UIUserNotificationAction {
            let action = UIMutableUserNotificationAction()
            action.identifier = rawValue
            
            switch self {
            case .open:
                action.title = "message.open".localizedPushAction
            case .reply:
                action.title = "message.reply".localizedPushAction
                action.behavior = .textInput
                action.parameters = [UIUserNotificationTextInputActionButtonTitleKey : "message.reply.button.title".localizedPushAction]
                action.activationMode = .background
            case .mute:
                action.title = "conversation.mute".localizedPushAction
                action.activationMode = .background
            case .like:
                action.title = "message.like".localizedPushAction
                action.activationMode = .background
            case .connect:
                action.title = "connection.accept".localizedPushAction
            }
            
            return action
        }
    }
    
    enum CallAction: String {
        case ignore = "ignoreCallAction"
        case accept = "acceptCallAction"
        case callBack = "callbackCallAction"
        case message = "conversationDirectReplyAction"
        
        var notificationAction: UIUserNotificationAction {
            let action = UIMutableUserNotificationAction()
            action.identifier = rawValue
            
            switch self {
            case .ignore:
                action.title = "call.ignore".localizedPushAction
                action.isDestructive = true
                action.activationMode = .background
            case .accept:
                action.title = "call.accept".localizedPushAction
            case .callBack:
                action.title = "call.callback".localizedPushAction
            case .message:
                action.title = "call.message".localizedPushAction
                action.behavior = .textInput
                action.parameters = [UIUserNotificationTextInputActionButtonTitleKey : "message.reply.button.title".localizedPushAction]
                action.activationMode = .background
            }
            
            return action
        }
        
    }
}
