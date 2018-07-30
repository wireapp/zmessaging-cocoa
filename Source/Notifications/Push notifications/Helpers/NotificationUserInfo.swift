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
import UserNotifications

/**
 * User info keys for notifications.
 */

private enum NotificationUserInfoKey: String {
    case conversationID = "conversationIDString"
    case messageNonce = "messageNonceString"
    case senderID = "senderIDString"
    case eventTime = "eventTime"
    case selfUserID = "selfUserIDString"
    case conversationName = "conversationNameString"
    case teamName = "teamNameString"
}

/**
 * A structure that describes the content of the user info payload
 * of user notifications.
 */

public struct NotificationUserInfo {

    /// The raw values of the user info.
    public var storage: [AnyHashable: Any]

    /// Creates the user info from its raw value.
    public init(storage: [AnyHashable: Any]) {
        self.storage = storage
    }

    /// Creates an empty notification user info payload.
    public init() {
        self.storage = [:]
    }

    // MARK: - Properties

    public var conversationID: UUID? {
        get { return self[.conversationID] as? UUID }
        set { self[.conversationID] = newValue }
    }

    public var conversatioName: String? {
        get { return self[.conversationName] as? String }
        set { self[.conversationName] = newValue }
    }

    public var teamName: String? {
        get { return self[.teamName] as? String }
        set { self[.teamName] = newValue }
    }

    public var messageNonce: UUID? {
        get { return self[.messageNonce] as? UUID }
        set { self[.messageNonce] = newValue }
    }

    public var senderID: UUID? {
        get { return self[.senderID] as? UUID }
        set { self[.senderID] = newValue }
    }

    public var eventTime: Date? {
        get { return self[.eventTime] as? Date }
        set { self[.eventTime] = newValue }
    }

    public var selfUserID: UUID? {
        get { return self[.selfUserID] as? UUID }
        set { self[.selfUserID] = newValue }
    }

    // MARK: - Utilities

    fileprivate subscript(_ key: NotificationUserInfoKey) -> Any? {
        get {
            return storage[key.rawValue]
        }
        set {
            storage[key.rawValue] = newValue
        }
    }

}

// MARK: - Lookup

extension NotificationUserInfo {

    /**
     * Fetches the conversion that matches the description stored in this user info fields.
     *
     * - parameter managedObjectContext: The context that should be used to perform the lookup.
     * - returns: The conversation, if found.
     */

    public func conversation(in managedObjectContext: NSManagedObjectContext) -> ZMConversation? {
        guard let remoteID = conversationID else {
            return nil
        }

        return ZMConversation(remoteID: remoteID, createIfNeeded: false, in: managedObjectContext)
    }

    /**
     * Fetches the message that matches the description stored in this user info fields.
     *
     * - parameter conversation: The conversation where the message should be searched.
     * - parameter managedObjectContext: The context that should be used to perform the lookup.
     * - returns: The message, if found.
     */

    public func message(in conversation: ZMConversation, managedObjectContext: NSManagedObjectContext) -> ZMMessage? {
        guard let nonce = messageNonce else {
            return nil
        }

        return ZMMessage.fetch(withNonce: nonce, for: conversation, in: managedObjectContext)
    }

    /**
     * Fetches the sender that matches the description stored in this user info fields.
     *
     * - parameter managedObjectContext: The context that should be used to perform the lookup.
     * - returns: The sender of the event, if found.
     */

    public func sender(in managedObjectContext: NSManagedObjectContext) -> ZMUser? {
        guard let senderID = senderID else {
            return nil
        }

        return ZMUser(remoteID: senderID, createIfNeeded: false, in: managedObjectContext)
    }

}

// MARK: - Configuration

extension NotificationUserInfo {

    public mutating func setupUserInfo(for conversation: ZMConversation, sender: ZMUser) {
        addSelfUserInfo(using: conversation)
        self.conversationID = conversation.remoteIdentifier
        self.senderID = sender.remoteIdentifier
    }

    public mutating func setupUserInfo(for conversation: ZMConversation, event: ZMUpdateEvent) {
        addSelfUserInfo(using: conversation)
        self.conversationID = conversation.remoteIdentifier
        self.senderID = event.senderUUID()
        self.messageNonce = event.messageNonce()
        self.eventTime = event.timeStamp()
    }

    public mutating func setupUserInfo(for message: ZMMessage) {
        addSelfUserInfo(using: message)
        self.conversationID = message.conversation?.remoteIdentifier
        self.senderID = message.sender?.remoteIdentifier
        self.messageNonce = message.nonce
        self.eventTime = message.serverTimestamp
    }

    /// Adds the description of the self user using the given managed object.
    private mutating func addSelfUserInfo(using object: NSManagedObject) {
        guard let context = object.managedObjectContext else {
            fatalError("Object doesn't have a managed context.")
        }

        let selfUser = ZMUser.selfUser(in: context)
        self[.selfUserID] = selfUser.remoteIdentifier
    }

}

// MARK: - Accessors

extension UNNotification {

    /// The user info describing the notification context.
    public var userInfo: NotificationUserInfo {
        return NotificationUserInfo(storage: content.userInfo)
    }

}

extension UNNotificationResponse {

    /// The user info describing the notification context.
    public var userInfo: NotificationUserInfo {
        return NotificationUserInfo(storage: self.notification.userInfo)
    }

}
