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



public enum LocalNotificationEventType {
    case connectionRequestAccepted, connectionRequestPending, newConnection, conversationCreated
}

public enum LocalNotificationContentType : Equatable {
    case undefined, image, video, audio, location, fileUpload, knock, text(String), reaction(emoji: String), ephemeral, hidden, participantsRemoved, participantsAdded, messageTimerUpdate(String?)
    
    static func typeForMessage(_ message: ZMConversationMessage) -> LocalNotificationContentType? {
        
        if message.isEphemeral {
            return .ephemeral
        }
        
        if let text = message.textMessageData?.messageText , !text.isEmpty {
            return .text(text)
        }
        
        if message.knockMessageData != nil {
            return .knock
        }
        
        if message.imageMessageData != nil {
            return .image
        }
        
        if let fileData = message.fileMessageData {
            if fileData.isAudio {
                return .audio
            }
            else if fileData.isVideo {
                return .video
            }
            return .fileUpload
        }
        
        if message.locationMessageData != nil {
            return .location
        }
        
        if let systemMessageData = message.systemMessageData{
            switch systemMessageData.systemMessageType {
            case .participantsAdded:
                return .participantsAdded
            case .participantsRemoved:
                return .participantsRemoved
            case .messageTimerUpdate:
                let value = MessageDestructionTimeoutValue(rawValue: TimeInterval(systemMessageData.messageTimer.doubleValue))
                if value == .none {
                    return .messageTimerUpdate(nil)
                } else {
                    return .messageTimerUpdate(value.displayString)
                }
            default:
                return nil
            }
        }
        
        return .undefined
    }
    
}

public func ==(rhs: LocalNotificationContentType, lhs: LocalNotificationContentType) -> Bool {
    switch (rhs, lhs) {
    case (.text(let left), .text(let right)):
        return left == right
    case (.image, .image), (.video, .video), (.audio, .audio), (.location, .location), (.fileUpload, .fileUpload), (.knock, .knock), (.undefined, .undefined), (.reaction, .reaction), (.messageTimerUpdate, .messageTimerUpdate):
        return true
    default:
        return false
    }
}


