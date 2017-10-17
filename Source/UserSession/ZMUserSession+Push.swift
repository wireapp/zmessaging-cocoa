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
    internal func isPayload(for user: ZMUser) -> Bool {
        if self.isPayloadMissingUserInformation() {
            return true
        }
        
        let userInfoData = self[PushChannelDataKey as! Key] as! [String: Any]
        let userId = userInfoData[PushChannelUserIDKey] as! String
        
        return user.remoteIdentifier == UUID(uuidString: userId)
    }
    
    internal func isPayloadMissingUserInformation() -> Bool {
        guard let userInfoData = self[PushChannelDataKey as! Key] as? [String: Any] else {
            log.debug("No data dictionary in notification userInfo payload");
            return true // Old-style push might not contain the user id
        }
        
        guard let _ = userInfoData[PushChannelUserIDKey] as? String else {
            // Old-style push might not contain the user id
            return true
        }
        
        return false
    }
    
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

extension NSDictionary {
    @objc(isPayloadForUser:)
    public func isPayload(for user: ZMUser) -> Bool {
        return (self as Dictionary).isPayload(for: user)
    }
}

extension ZMUserSession: PushDispatcherOptionalClient {
    
    public func updatedPushToken(to newToken: PushToken) {
        
        guard let managedObjectContext = self.managedObjectContext else {
            return
        }
        
        switch newToken.type {
        case .regular:
            if let data = newToken.data {
                let oldToken = self.managedObjectContext.pushToken?.deviceToken
                if oldToken == nil || oldToken != data {
                    managedObjectContext.pushToken = nil
                    self.setPushToken(data)
                    managedObjectContext.forceSaveOrRollback()
                }
            }
        case .voip:
            if let data = newToken.data {
                managedObjectContext.pushKitToken = nil
                self.setPushKitToken(data)
                managedObjectContext.forceSaveOrRollback()
            }
            else {
                self.deletePushKitToken()
                managedObjectContext.forceSaveOrRollback()
            }
        }
    }

    public func mustHandle(payload: [AnyHashable: Any]) -> Bool {
        assert(Thread.isMainThread)
        return payload.isPayload(for: ZMUser.selfUser(in: self.managedObjectContext))
    }
    
    public func receivedPushNotification(with payload: [AnyHashable: Any],
                                         from source: ZMPushNotficationType,
                                         completion: ZMPushNotificationCompletionHandler?) {
        
        self.syncManagedObjectContext.performGroupedBlock {
            let notAuthenticated = !self.isAuthenticated()
            
            if notAuthenticated {
                log.debug("Not displaying notification because app is not authenticated")
                completion?(.success)
                return
            }
            
            // once notification processing is finished, it's safe to update the badge
            let completionHandler: ZMPushNotificationCompletionHandler = { result in
                completion?(result)
                self.sessionManager?.updateAppIconBadge()
            }
            
            self.operationLoop.saveEventsAndSendNotification(forPayload: payload,
                                                             fetchCompletionHandler: completionHandler,
                                                             source: source)
        }
    }
    
}

extension ZMUserSession: ForegroundNotificationsDelegate {
    
    public func didReceieveLocalMessage(notification: UILocalNotification, application: ZMApplication) {
        DispatchQueue.main.performAsync {
            self.sessionManager?.localMessageNotificationResponder?.processLocalMessage(notification, forSession: self)
        }
    }

    public func didReceiveLocal(notification: UILocalNotification, application: ZMApplication) {
        
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

// Testing
extension ZMUserSession {
    @objc(updatePushKitTokenTo:forType:)
    public func updatedPushToken(to data: Data, for type: PushTokenType) {
        self.updatedPushToken(to: PushToken(type: type, data: data))
    }
}

