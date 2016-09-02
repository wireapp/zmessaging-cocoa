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

let OneOnOneKey = "oneonone"
let GroupKey = "group"
let SelfKey = "self"
let NoConversationNameKey = "noconversationname"
let NoUserNameKey = "nousername"
let NoOtherUserNameKey = "nootherusername"


public class LocalizationInfo : NSObject {
    
    public let localizationString : String
    public let arguments : [String]
    public init(localizationString: String, arguments: [String]) {
        self.localizationString = localizationString
        self.arguments = arguments
    }
}


public extension NSString {

    public func localizationInfo(forUser user: ZMUser, conversation: ZMConversation) -> LocalizationInfo {
        
        let userName = user.name
        let convName = conversation.userDefinedName
        var arguments = [String]()
        var keyComponents = [String]()
        
        let convTypeKey = (conversation.conversationType != .OneOnOne) ? GroupKey : OneOnOneKey
        keyComponents.append(convTypeKey)

        
        if userName == nil || userName.isEmpty {
            keyComponents.append(NoUserNameKey)
        }
        else {
            arguments.append(userName)
        }
        
        if (conversation.conversationType != .OneOnOne) {
            if convName == nil || convName!.isEmpty {
                keyComponents.append(NoConversationNameKey)
            }
            else {
                arguments.append(convName!)
            }
        }
        let localizationString = keyComponents.reduce(self){$0.0.stringByAppendingPathExtension($0.1)!}
        return LocalizationInfo(localizationString: localizationString as String, arguments: arguments)
    }
}

