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
    case Undefined, Image, Video, Audio, Location, FileUpload, Knock
    case System(ZMSystemMessageType)
    case Text(String)
    
    static func typeForMessage(message: ZMConversationMessage) -> ZMLocalNotificationContentType {
        if let text = message.textMessageData?.messageText where !text.isEmpty {
            return .Text(text)
        }
        if message.knockMessageData != nil {
            return .Knock
        }
        if message.imageMessageData != nil {
            return .Image
        }
        if let systemMessage = message.systemMessageData {
            return .System(systemMessage.systemMessageType)
        }
        if let fileData = message.fileMessageData {
            if fileData.isAudio() {
                return .Audio
            }
            else if fileData.isVideo() {
                return .Video
            }
            return .FileUpload
        }
        if message.locationMessageData != nil {
            return .Location
        }
        return .Undefined
    }
    
    var localizationString : String? {
        switch self {
        case .Text:
            return ZMPushStringMessageAdd
        case .Image:
            return ZMPushStringImageAdd
        case .Video:
            return ZMPushStringVideoAdd
        case .Audio:
            return ZMPushStringAudioAdd
        case .Location:
            return ZMPushStringLocationAdd
        case .FileUpload:
            return ZMPushStringFileAdd
        case .Knock:
            return ZMPushStringKnock
        default:
            return nil
        }
    }
}

public func ==(rhs: ZMLocalNotificationContentType, lhs: ZMLocalNotificationContentType) -> Bool {
    switch (rhs, lhs) {
    case (.Text(let left), .Text(let right)):
        return left == right
    case (.System(let lType), .System(let rType)):
        return lType == rType
    case (.Image, .Image), (.Video, .Video), (.Audio, .Audio), (.Location, .Location), (.FileUpload, .FileUpload), (.Knock, .Knock):
        return true
    default:
        return false
    }
}

