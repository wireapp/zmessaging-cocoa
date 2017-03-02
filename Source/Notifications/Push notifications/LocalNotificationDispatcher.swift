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

import Foundation

/// Creates and cancels local notifications
public class LocalNotificationDispatcher: NSObject {
    
    public static let ZMConversationCancelNotificationForIncomingCallNotificationName = "ZMConversationCancelNotificationForIncomingCallNotification"
    public static let ZMShouldHideNotificationContentKey = "ZMShouldHideNotificationContentKey"
    
    let eventNotifications: ZMLocalNotificationSet
    let messageNotifications: ZMLocalNotificationSet
    let callingNotifications: ZMLocalNotificationSet
    let failedMessageNotification: ZMLocalNotificationSet
    
    let application: Application
    let sessionTracker: SessionTracker
    let syncMOC: NSManagedObjectContext
    var isTornDown: Bool
    
    @objc(initWithManagedObjectContext:application:)
    public init(in managedObjectContext: NSManagedObjectContext,
                application: Application) {
        self.syncMOC = managedObjectContext
        self.eventNotifications = ZMLocalNotificationSet(application: application, archivingKey: "ZMLocalNotificationDispatcherEventNotificationsKey", keyValueStore: managedObjectContext)
        self.failedMessageNotification = ZMLocalNotificationSet(application: application, archivingKey: "ZMLocalNotificationDispatcherFailedNotificationsKey", keyValueStore: managedObjectContext)
        self.callingNotifications = ZMLocalNotificationSet(application: application, archivingKey: "ZMLocalNotificationDispatcherCallingNotificationsKey", keyValueStore: managedObjectContext)
        self.messageNotifications = ZMLocalNotificationSet(application: application, archivingKey: "ZMLocalNotificationDispatcherMessageNotificationsKey", keyValueStore: managedObjectContext)
        self.application = application
        self.sessionTracker = SessionTracker(managedObjectContext: managedObjectContext)
        self.isTornDown = false
        super.init()
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(self.cancelNotificationForIncomingCall(notification:)),
                                               name: NSNotification.Name(rawValue: LocalNotificationDispatcher.ZMConversationCancelNotificationForIncomingCallNotificationName),
                                               object: nil)
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(self.cancelNotificationForLastReadChanged(notification:)),
                                               name: NSNotification.Name(rawValue: ZMConversationLastReadDidChangeNotificationName),
                                               object: nil)
    }
 
    public func tearDown() {
        self.isTornDown = true
        self.sessionTracker.tearDown()
        NotificationCenter.default.removeObserver(self)
        self.cancelAllNotifications()
    }

    deinit {
         precondition(self.isTornDown)
    }
}

extension LocalNotificationDispatcher: ZMEventConsumer {
    
    public func processEvents(_ events: [ZMUpdateEvent], liveEvents: Bool, prefetchResult: ZMFetchRequestBatchResult?) {
        if self.application.applicationState != .background {
            return
        }
        
        let eventsToForward = events.filter { (event) -> Bool in
            // we only want to process events we received through Push
            if event.source != .pushNotification {
                return false
            }
            // TODO Sabine : Can we maybe filter message events here already for Reactions?
            return true
        }
        
        self.didReceive(events: eventsToForward, conversationMap: prefetchResult?.conversationsByRemoteIdentifier ?? [:], id: events.first?.uuid)
    }
    
    func didReceive(events: [ZMUpdateEvent], conversationMap: [UUID : ZMConversation], id: UUID?) {
        events.forEach {
            // Forward events to the session tracker which keeps track if the selfUser joined or not
            self.sessionTracker.addEvent($0)
            
            // Then create the notification
            guard let note = self.notification(event: $0, conversationMap: conversationMap),
                let localNote = note.uiNotifications.last
            else {
                return
            }
            self.application.scheduleLocalNotification(localNote)
            if let id = id, let analyticsType = self.syncMOC.analytics {
                APNSPerformanceTracker.trackVOIPNotificationInNotificationDispatcher(id, analytics: analyticsType)
            }
        }
    }
    
    func notification(event: ZMUpdateEvent, conversationMap: [UUID : ZMConversation]) -> ZMLocalNotificationForEvent? {
        switch event.type {
        case .conversationCreate, .userConnection, .conversationOtrMessageAdd, // only for reaction
        .userContactJoin, .callState:
            return self.localNotification(event: event, conversationMap: conversationMap)
        default:
            return nil
        }
    }
    
    func localNotification(event: ZMUpdateEvent, conversationMap: [UUID: ZMConversation]) -> ZMLocalNotificationForEvent? {
        for note in self.eventNotifications.notifications.flatMap({ $0 as? ZMLocalNotificationForEvent }) {
            if note.containsIdenticalEvent(event) {
                return nil
            }
        }
        
        var conversation: ZMConversation?
        if let conversationID = event.conversationUUID() {
            // Fetch the conversation here to avoid refetching every time we try to create a notification
            conversation = conversationMap[conversationID] ?? ZMConversation.fetch(withRemoteIdentifier: conversationID, in: self.syncMOC)
            if let conversation = conversation,
                let note = self.eventNotifications.copyExistingEventNotification(event, conversation: conversation) {
                return note
            }
        }
        
        if let newNote = ZMLocalNotificationForEvent.notification(forEvent: event,
                                                               conversation: conversation,
                                                               managedObjectContext: self.syncMOC,
                                                               application: self.application,
                                                               sessionTracker: self.sessionTracker) {
            self.eventNotifications.addObject(newNote)
            return newNote
        }
        return nil
    }
}

// MARK: - Failed messages
extension LocalNotificationDispatcher {
    
    /// Informs the user that the message failed to send
    public func didFailToSend(_ message: ZMMessage) {
        if message.visibleInConversation == nil || message.conversation?.conversationType == .self {
            return
        }
        let note = ZMLocalNotificationForExpiredMessage(expiredMessage: message)
        self.application.scheduleLocalNotification(note.uiNotification)
        self.failedMessageNotification.addObject(note)
    }
    
    /// Informs the user that a message in a conversation failed to send
    public func didFailToSendMessage(in conversation: ZMConversation) {
        let note = ZMLocalNotificationForExpiredMessage(conversation: conversation)
        self.application.scheduleLocalNotification(note.uiNotification)
        self.failedMessageNotification.addObject(note)
    }
}

// MARK: - Canceling notifications
extension LocalNotificationDispatcher {
    
    private var allNotificationSets: [ZMLocalNotificationSet] {
        return [self.eventNotifications,
                self.failedMessageNotification,
                self.messageNotifications,
                self.callingNotifications]
    }
    
    /// Can be used for cancelling all conversations if need
    public func cancelAllNotifications() {
        self.allNotificationSets.forEach { $0.cancelAllNotifications() }
    }
    
    /// Cancels all notifications for a specific conversation
    /// - note: Notifications for a specific conversation are otherwise deleted automatically when the message window changes and
    /// ZMConversationDidChangeVisibleWindowNotification is called
    public func cancelNotification(for conversation: ZMConversation) {
        self.sessionTracker.clearSessions(conversation)
        self.allNotificationSets.forEach { $0.cancelNotifications(conversation) }
    }
    
    /// Cancels a notification for an incoming call in the conversation that is speficied as object of the notification
    func cancelNotificationForIncomingCall(notification: NSNotification) {
        guard let conversation = notification.object as? ZMConversation else { return }
        if conversation.isIgnoringCall {
            self.eventNotifications.cancelNotificationForIncomingCall(conversation)
        }
    }
 
    /// Cancels all notification in the conversation that is speficied as object of the notification
    func cancelNotificationForLastReadChanged(notification: NSNotification) {
        guard let conversation = notification.object as? ZMConversation else { return }
        let isUIObject = conversation.managedObjectContext?.zm_isUserInterfaceContext ?? false
        
        self.syncMOC.performGroupedBlock {
            if isUIObject {
                // clear all notifications for this conversation
                if let syncConversation = (try? self.syncMOC.existingObject(with: conversation.objectID)) as? ZMConversation {
                    self.cancelNotification(for: syncConversation)
                }
            } else {
                self.cancelNotification(for: conversation)
            }
        }
    }


}

