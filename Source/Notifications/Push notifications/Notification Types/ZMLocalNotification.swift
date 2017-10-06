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

import UIKit
import UserNotifications
import WireSystem
import WireUtilities
import WireTransport
import WireDataModel


/// Defines the various types of local notifications, some of which
/// have associated subtypes.
///
public enum LocalNotificationType {
    
    case event(ZMUpdateEventType)
    case calling(CallState)
    case reaction
    case message(ZMLocalNotificationContentType)
    case failedMessage
}


/// This class encapsulates all the data necessary to produce a local
/// notification. It configures and formats the textual content for
/// various notification types (message, calling, etc.) and includes
/// information regarding the conversation, sender, and team name.
///
open class ZMLocalNotification: NSObject {
    
    public var title: String
    public var body: String?
    public var soundName: String?
    public var category: String?
    
    public let conversationID: UUID
    public let type: LocalNotificationType
    
    init(conversationID: UUID, type: LocalNotificationType) {
        self.conversationID = conversationID
        self.type = type
        super.init()
    }
    
    /// Sets the title for the notification using the name of the given conversation
    /// and if possible, the team name of the self user.
    ///
    func configureTitle(for conversation: ZMConversation) {

        title = conversation.displayName

        if let moc = conversation.managedObjectContext,
            let teamName = ZMUser.selfUser(in: moc).team?.name {
            title += " in \(teamName)"
        }
    }
    
    /// Returns a configured concrete UILocalNotification object.
    ///
    public lazy var uiLocalNotification: UILocalNotification = {
        // TODO: configure (including user info)
        return UILocalNotification()
    }()
    
    /// Returns a configured concrete UNNotification object.
    ///
    public lazy var unNotification: UNNotification = {
        // TODO: configure (including user info)
        return UNNotification()
    }()
}
