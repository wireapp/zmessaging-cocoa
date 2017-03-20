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

public protocol LocalNotification {
    var conversationID : UUID? { get }
    var application : Application {get}
    var notifications : [UILocalNotification] {get set}
    func cancelNotifications()
}

public extension LocalNotification {
    public func cancelNotifications() {
        notifications.forEach{
            application.cancelLocalNotification($0)
        }
    }
}

public protocol EventNotification : LocalNotification {
    var ignoresSilencedState : Bool { get }
    var eventType : ZMUpdateEventType { get }
    var managedObjectContext: NSManagedObjectContext {get }
    init?(events: [ZMUpdateEvent], conversation: ZMConversation?, managedObjectContext: NSManagedObjectContext, application: Application?)
}


public extension ZMLocalNotificationForEvent {
    public static func notification(forEvent event: ZMUpdateEvent, conversation: ZMConversation?, managedObjectContext: NSManagedObjectContext, application: Application?, sessionTracker: SessionTracker) -> ZMLocalNotificationForEvent? {
        switch event.type {
        case .conversationOtrMessageAdd:
            if let note = ZMLocalNotificationForReaction(events: [event], conversation: conversation, managedObjectContext: managedObjectContext, application: application) {
                return note
            }
            return nil
        case .conversationCreate:
            return ZMLocalNotificationForConverstionCreateEvent(events: [event], conversation: conversation,  managedObjectContext: managedObjectContext, application: application)
        case .userConnection:
            return ZMLocalNotificationForUserConnectionEvent(events: [event], conversation: conversation,  managedObjectContext: managedObjectContext, application: application)
        case .userContactJoin:
            return ZMLocalNotificationForNewUserEvent(events: [event], conversation: conversation,  managedObjectContext: managedObjectContext, application: application)
        case .callState:
            if !ZMUserSession.useCallKit {
                return ZMLocalNotificationForCallEvent(events: [event], conversation: conversation, managedObjectContext: managedObjectContext, application: application, sessionTracker: sessionTracker)
            }
            else {
                return nil
            }
        default:
            return nil
        }
    }
}


open class ZMLocalNotificationForEvent : ZMLocalNotification, EventNotification {
    
    open var shouldBeDiscarded : Bool = false
    open let sender : ZMUser?

    open var eventType : ZMUpdateEventType {
        return .unknown
    }
    
    open var notifications : [UILocalNotification] = []
    
    open override var uiNotifications: [UILocalNotification] {
        return notifications
    }
    
    open let application : Application
    open let managedObjectContext : NSManagedObjectContext
    
    open var events : [ZMUpdateEvent] = []

    var lastEvent : ZMUpdateEvent? {
        return events.last
    }
    
    var eventData : [String : AnyObject] {
        if let lastEvent = lastEvent {
            return (lastEvent.payload as? [String : AnyObject])!["data"] as! [String : AnyObject]
        }
        return [:]
    }
    
    required public init?(events: [ZMUpdateEvent], conversation: ZMConversation?, managedObjectContext: NSManagedObjectContext, application: Application?) {
        self.application = application ?? UIApplication.shared
        self.events = events
        if let senderUUID = events.last?.senderUUID() {
            self.sender = ZMUser(remoteID: senderUUID, createIfNeeded: false, in: managedObjectContext)
        } else {
            self.sender = nil
        }
        self.managedObjectContext = managedObjectContext
        super.init(conversationID: conversation?.remoteIdentifier)

        guard canCreateNotification(conversation) else { return nil }
        let notification = configureNotification(conversation)
        notifications.append(notification)
    }
    
    func configureNotification(_ conversation: ZMConversation?) -> UILocalNotification {
        let notification = UILocalNotification()
        let shouldHideContent = managedObjectContext.persistentStoreMetadata(forKey: LocalNotificationDispatcher.ZMShouldHideNotificationContentKey)
        if let shouldHideContent = shouldHideContent as? NSNumber , shouldHideContent.boolValue == true {
            notification.alertBody = ZMPushStringDefault.localizedStringForPushNotification()
            notification.soundName = ZMCustomSound.notificationNewMessageSoundName()
        } else {
            notification.alertBody = configureAlertBody(conversation).escapingPercentageSymbols()
            notification.soundName = soundName
            notification.category = category
        }
        notification.setupUserInfo(conversation, for: lastEvent)
        return notification
    }
    
    open func containsIdenticalEvent(_ event: ZMUpdateEvent) -> Bool {
        guard (eventType == event.type || event.messageNonce() != nil) && conversationID == event.conversationUUID()
        else { return false }
        
        let idx = findIndex(events){$0.messageNonce() == event.messageNonce()}
        return idx != nil
    }
    
    
    /// You HAVE To override configureAlertBody() to configure the alert body
    func configureAlertBody(_ conversation: ZMConversation?) -> String { return "" }
    
    // MARK: Override these if needed
    
    
    /// set to true if notification depends / refers to a specific conversation
    var requiresConversation : Bool { return false }
    /// create a notification even if conversation is silenced
    open var ignoresSilencedState : Bool { return false }
    
    /// if empty, it does not copy events
    var soundName : String { return ZMCustomSound.notificationNewMessageSoundName() }
    var category : String { return ZMConversationCategory }
    
    
    
    func canCreateNotification(_ conversation: ZMConversation?) -> Bool {
        // The notification either has a conversation or does not require one
        guard (conversation != nil || !requiresConversation) else {return false}
        
        // The last event is set
        guard let lastEvent = lastEvent else {return false}
        
        // The eventType is the same as the expected eventType
        guard eventType == lastEvent.type && eventType != .unknown else {return false}
        
        // The sender is not the selfUser or it is a call event (we want to keep track of which calls we joined and cancel notifications if we joined)
        if let sender = sender , (sender.isSelfUser && lastEvent.type != .callState) { return false }

        if let conversation = conversation {
            if conversation.isSilenced && !ignoresSilencedState {
                return false
            }
            if let timeStamp = lastEvent.timeStamp(),
               let lastRead = conversation.lastReadServerTimeStamp , lastRead.compare(timeStamp) != .orderedAscending {
                // don't show notifications that have already been read
                return false
            }
        }
        return true
    }
}




