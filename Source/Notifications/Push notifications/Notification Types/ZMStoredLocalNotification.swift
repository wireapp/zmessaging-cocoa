////
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

@objc public class ZMStoredLocalNotification: NSObject {
    
    let conversation: ZMConversation?
    let message: ZMMessage?
    let senderID: UUID?
    let category: String
    let actionIdentifier: String?
    
    init(userInfo: NotificationUserInfo,
         moc: NSManagedObjectContext,
         category: String,
         actionIdentifier: String? = nil)
    {
        conversation = userInfo.conversation(in: moc)
        
        if let conversation = conversation {
            message = userInfo.message(in: conversation, managedObjectContext: moc)
        } else {
            message = nil
        }
        
        senderID = userInfo.senderID
        self.category = category
        self.actionIdentifier = actionIdentifier
        super.init()
    }
}
