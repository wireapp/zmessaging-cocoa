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
    case event(LocalNotificationEventType)
    case calling(CallState)
    case message(LocalNotificationContentType)
    case failedMessage
}

/// A notification builder provides the main components used to configure
/// a local notification. 
///
protocol NotificationBuilder {
    var notificationType : LocalNotificationType { get }
    func shouldCreateNotification() -> Bool
    func titleText() -> String?
    func bodyText() -> String
    func userInfo() -> [AnyHashable: Any]?
}


/// This class encapsulates all the data necessary to produce a local
/// notification. It configures and formats the textual content for
/// various notification types (message, calling, etc.) and includes
/// information regarding the conversation, sender, and team name.
///
open class ZMLocalNotification: NSObject {
    
    public let type: LocalNotificationType
    public var title: String?
    public var body: String
    public var category: String
    public var soundName: String
    public var userInfo: [AnyHashable: Any]?
        
    public var selfUserID: UUID? { return uuid(for: SelfUserIDStringKey) }
    public var senderID: UUID? { return uuid(for: SenderIDStringKey) }
    public var messageNonce: UUID? { return uuid(for: MessageNonceIDStringKey) }
    public var conversationID: UUID? { return uuid(for: ConversationIDStringKey) }
    
    init?(conversation: ZMConversation?, builder: NotificationBuilder) {
        guard builder.shouldCreateNotification() else { return nil }
        self.type = builder.notificationType
        self.title = builder.titleText()
        self.body = builder.bodyText().escapingPercentageSymbols()
        self.category = builder.notificationType.category
        self.soundName = builder.notificationType.soundName.fileName
        self.userInfo = builder.userInfo()
    }

    /// Returns a configured concrete `UNNotificationContent` object.
    public lazy var userNotificationContent: UNNotificationContent = {
        let content = UNMutableNotificationContent()
        content.body = self.body
        content.categoryIdentifier = self.category
        content.sound = UNNotificationSound(named: soundName)

        if let title = self.title {
            content.title = title
        }

        if let userInfo = self.userInfo {
            content.userInfo = userInfo
        }

        return content
    }()

    /// Returns true if it is a calling notification, else false.
    public var isCallingNotification: Bool {
        switch type {
        case .calling: return true
        default: return false
        }
    }
    
    /// Returns true if it is a ephemeral notification, else false.
    public var isEphemeral: Bool {
        switch type {
        case .message(let contentType):
            if case .ephemeral = contentType {
                return true
            } else {
                return false
            }
        default:
            return false
        }
    }
    
    /// Returns the UUID for the given key from the user info if it exists, else
    /// nil.
    ///
    private func uuid(for key: String) -> UUID? {
        guard let uuidString = userInfo?[key] as? String else { return nil }
        return UUID(uuidString: uuidString)
    }
    
    public func conversation(in moc: NSManagedObjectContext) -> ZMConversation? {
        guard let uuid = conversationID else { return nil }
        return ZMConversation(remoteID: uuid, createIfNeeded: false, in: moc)
    }
    
    public func sender(in moc: NSManagedObjectContext) -> ZMUser? {
        guard let uuid = senderID else { return nil }
        return ZMUser(remoteID: uuid, createIfNeeded: false, in: moc)
    }
}
