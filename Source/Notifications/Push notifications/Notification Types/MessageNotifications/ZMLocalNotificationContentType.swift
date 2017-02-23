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



public enum ZMLocalNotificationContentType : Equatable {
    case undefined, image, video, audio, location, fileUpload, knock
    case system(ZMSystemMessageType)
    case text(String)
    
    static func typeForMessage(_ message: ZMConversationMessage) -> ZMLocalNotificationContentType {
        if let text = message.textMessageData?.messageText , !text.isEmpty {
            return .text(text)
        }
        if message.knockMessageData != nil {
            return .knock
        }
        if message.imageMessageData != nil {
            return .image
        }
        if let systemMessage = message.systemMessageData {
            return .system(systemMessage.systemMessageType)
        }
        if let fileData = message.fileMessageData {
            if fileData.isAudio() {
                return .audio
            }
            else if fileData.isVideo() {
                return .video
            }
            return .fileUpload
        }
        if message.locationMessageData != nil {
            return .location
        }
        return .undefined
    }
    
    var localizationString : String? {
        switch self {
        case .text:
            return ZMPushStringMessageAdd
        case .image:
            return ZMPushStringImageAdd
        case .video:
            return ZMPushStringVideoAdd
        case .audio:
            return ZMPushStringAudioAdd
        case .location:
            return ZMPushStringLocationAdd
        case .fileUpload:
            return ZMPushStringFileAdd
        case .knock:
            return ZMPushStringKnock
        default:
            return nil
        }
    }
}

public func ==(rhs: ZMLocalNotificationContentType, lhs: ZMLocalNotificationContentType) -> Bool {
    switch (rhs, lhs) {
    case (.text(let left), .text(let right)):
        return left == right
    case (.system(let lType), .system(let rType)):
        return lType == rType
    case (.image, .image), (.video, .video), (.audio, .audio), (.location, .location), (.fileUpload, .fileUpload), (.knock, .knock), (.undefined, .undefined):
        return true
    default:
        return false
    }
}

