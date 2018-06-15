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
import WireTransport

let PushChannelUserIDKey = "user"
let PushChannelDataKey = "data"

private let log = ZMSLog(tag: "Push")

extension Dictionary {
    
    internal func accountId() -> UUID? {
        guard let userInfoData = self[PushChannelDataKey as! Key] as? [String: Any] else {
            log.debug("No data dictionary in notification userInfo payload");
            return nil
        }
    
        guard let userIdString = userInfoData[PushChannelUserIDKey] as? String else {
            return nil
        }
    
        return UUID(uuidString: userIdString)
    }
}

extension ZMUserSession {
    
    public func receivedPushNotification(with payload: [AnyHashable: Any], completion: @escaping () -> Void) {
        guard let syncMoc = self.syncManagedObjectContext else {
            return
        }

        let accountID = self.storeProvider.userIdentifier;

        syncMoc.performGroupedBlock {
            let notAuthenticated = !self.isAuthenticated()
            
            if notAuthenticated {
                log.debug("Not displaying notification because app is not authenticated")
                completion()
                return
            }
            
            // once notification processing is finished, it's safe to update the badge
            let completionHandler = {
                completion()
                let unreadCount = Int(ZMConversation.unreadConversationCount(in: syncMoc))
                self.sessionManager?.updateAppIconBadge(accountID: accountID, unreadCount: unreadCount)
            }
            
            self.operationLoop.fetchEvents(fromPushChannelPayload: payload, completionHandler: completionHandler)
        }
    }
    
}

extension ZMUserSession: ForegroundNotificationsDelegate {
    
    public func didReceieveLocal(notification: ZMLocalNotification, application: ZMApplication) {
        managedObjectContext.performGroupedBlock {
            self.sessionManager?.localNotificationResponder?.processLocal(notification, forSession: self)
        }
    }

    public func didReceiveLocal(notification: UILocalNotification, application: ZMApplication) {
        
        if let category = notification.category, category == ZMIncomingCallCategory {
            self.handleTrackingOnCallNotification(notification)
        }
        
        self.pendingLocalNotification = ZMStoredLocalNotification(notification: notification,
                                                                  managedObjectContext: self.managedObjectContext,
                                                                  actionIdentifier: nil,
                                                                  textInput: nil)

        if self.didStartInitialSync && !self.isPerformingSync && self.pushChannelIsOpen {
            self.processPendingNotificationActions()
        }
    }
    
    public func handleAction(application: ZMApplication,
                             with identifier: String?,
                             for localNotification: UILocalNotification,
                             with responseInfo: [AnyHashable: Any],
                             completionHandler: @escaping () -> ()) {
        
        let textInput: String = responseInfo[UIUserNotificationActionResponseTypedTextKey] as? String ?? ""

        if let concreteIdentifier = identifier {
            switch concreteIdentifier {
            case ZMCallIgnoreAction:
                self.ignoreCall(with: localNotification, completionHandler: completionHandler)
                return
            case ZMConversationMuteAction:
                self.muteConversation(with: localNotification, completionHandler: completionHandler)
                return
            case ZMMessageLikeAction:
                self.likeMessage(with: localNotification, completionHandler: completionHandler)
                return
            case ZMConversationDirectReplyAction:
                self.reply(with: localNotification, message: textInput, completionHandler: completionHandler)
                return
            default:
                break
            }
        }
        
        if application.applicationState == .inactive {
            self.pendingLocalNotification = ZMStoredLocalNotification(notification: localNotification,
                                                                      managedObjectContext: self.managedObjectContext,
                                                                      actionIdentifier: identifier,
                                                                      textInput: textInput)
        }
         
        if self.didStartInitialSync && !self.isPerformingSync && self.pushChannelIsOpen {
            self.processPendingNotificationActions()
        }
        
        completionHandler();
    }
}
