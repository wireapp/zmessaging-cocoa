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

protocol NotificationConstructor {
    func shouldCreateNotification() -> Bool
    func bodyText() -> String
    func soundName() -> String
    func category() -> String
    func userInfo() -> [AnyHashable: Any]?
}

public enum ZMLocalNoteUserInfoKey: String {
    case selfUserID = "selfUserID"
    case senderID = "senderID"
    case messageNonce = "messageNonce"
    case conversationID = "conversationID"
    case eventTime = "eventTime"
}

/// This class encapsulates all the data necessary to produce a local
/// notification. It configures and formats the textual content for
/// various notification types (message, calling, etc.) and includes
/// information regarding the conversation, sender, and team name.
///
open class ZMLocalNote: NSObject {
    
    // User Info Keys
    static let SelfUserIDStringKey = "selfUserIDString"
    static let SenderIDStringKey = "senderIDString"
    static let MessageNonceIDStringKey = "messageNonceString"
    static let ConversationIDStringKey = "conversationIDString"
    static let EventTimeKey = "eventTime"
    
    public var title: String?
    public var body: String?
    public var category: String?
    public var soundName: String?
    public var userInfo: [AnyHashable: Any]?
    
    public let conversationID: UUID?
    public let type: LocalNotificationType
    
    init(conversation: ZMConversation?, type: LocalNotificationType) {
        self.conversationID = conversation?.remoteIdentifier
        self.type = type
        super.init()
    }
    
    convenience init?(conversation: ZMConversation?, type: LocalNotificationType, constructor: NotificationConstructor) {
        self.init(conversation: conversation, type: type)
        guard constructor.shouldCreateNotification() else { return nil }
        self.body = constructor.bodyText().escapingPercentageSymbols()
        self.category = constructor.category()
        self.soundName = constructor.soundName()
        self.userInfo = constructor.userInfo()
        self.title = title(for: conversation)
    }
    
    /// Sets the title for the notification using the name of the given conversation
    /// and if possible, the team name of the self user.
    ///
    func title(for conversation: ZMConversation?) -> String? {
        guard let conversation = conversation else { return nil }
        var title = conversation.displayName

        if let moc = conversation.managedObjectContext,
            let teamName = ZMUser.selfUser(in: moc).team?.name {
            title += " in \(teamName)"
        }
        
        return title
    }
    
    /// Returns a configured concrete UILocalNotification object.
    ///
    public lazy var uiLocalNotification: UILocalNotification = {
        
        let note = UILocalNotification()
        note.alertTitle = self.title
        note.alertBody = self.body
        note.category = self.category
        note.soundName = self.soundName
        note.userInfo = self.userInfo
        return note
    }()
    
}
