//
//  Analytics+PushChannel.swift
//  WireSyncEngine-ios
//
//  Created by Nicola Giancecchi on 20.02.18.
//  Copyright © 2018 Zeta Project Gmbh. All rights reserved.
//

import Foundation

extension AnalyticsType {
    
    private static var contributionEventName: String {
        return "contribution"
    }
    
    func tagTextReplyFromPushNotification(conversation: ZMConversation?, action: PushChannelAction, message: ZMMessage?) {
        let attributes: [String: NSObject] = [
            "action": action.rawValue as NSString,
            "conversation_type": (conversation?.conversationType.analyticsType ?? "") as NSString,
            "is_ephemeral": NSNumber(value: message?.isEphemeral ?? false)
        ]
        
        tagEvent(Self.contributionEventName, attributes: attributes)
    }
    
}

enum PushChannelAction: String {
    case text = "text"
    case like = "like"
    case call = "call"
}

extension ZMConversationType {
    
     var analyticsType : String {
        switch self {
        case .oneOnOne:
            return "one_to_one"
        case .group:
            return "group"
        default:
            return ""
        }
    }
}
