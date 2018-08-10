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
import UserNotifications

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

    @objc public static let registerCurrentPushTokenNotificationName = Notification.Name(rawValue: "ZMUserSessionResetPushTokensNotification")

    @objc public func registerForRegisteringPushTokenNotification() {
        NotificationCenter.default.addObserver(self, selector: #selector(ZMUserSession.registerCurrentPushToken), name: ZMUserSession.registerCurrentPushTokenNotificationName, object: nil)
    }

    func setPushKitToken(_ data: Data) {
        guard let transportType = self.apnsEnvironment.transportType(forTokenType: .voIP) else { return }
        guard let appIdentifier = self.apnsEnvironment.appIdentifier else { return }

        let syncMOC = managedObjectContext.zm_sync!
        syncMOC.performGroupedBlock {
            guard let selfClient = ZMUser.selfUser(in: syncMOC).selfClient() else { return }
            if selfClient.pushToken?.deviceToken != data {
                selfClient.pushToken = PushToken(deviceToken: data, appIdentifier: appIdentifier, transportType: transportType, isRegistered: false)
                syncMOC.saveOrRollback()
            }
        }
    }

    func deletePushKitToken() {
        let syncMOC = managedObjectContext.zm_sync!
        syncMOC.performGroupedBlock {
            guard let selfClient = ZMUser.selfUser(in: syncMOC).selfClient() else { return }
            guard let pushToken = selfClient.pushToken else { return }
            selfClient.pushToken = pushToken.markToDelete()
            syncMOC.saveOrRollback()
        }
    }

    @objc public func registerCurrentPushToken() {
        managedObjectContext.performGroupedBlock {
            self.sessionManager.updatePushToken(for: self)
        }
    }

    /// Will compare the push token registered on backend with the local one
    /// and re-register it if they don't match
    public func validatePushToken() {
        let syncMOC = managedObjectContext.zm_sync!
        syncMOC.performGroupedBlock {
            guard let selfClient = ZMUser.selfUser(in: syncMOC).selfClient() else { return }
            guard let pushToken = selfClient.pushToken else {
                // If we don't have any push token, then try to register it again
                self.sessionManager.updatePushToken(for: self)
                return
            }
            selfClient.pushToken = pushToken.markToDownload()
            syncMOC.saveOrRollback()
        }
    }
}

extension ZMUserSession {
    
    @objc public func receivedPushNotification(with payload: [AnyHashable: Any], completion: @escaping () -> Void) {
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

@objc extension ZMUserSession: ForegroundNotificationsDelegate {
    
    public func didReceieveLocal(notification: ZMLocalNotification, application: ZMApplication) {
        managedObjectContext.performGroupedBlock {
            self.sessionManager?.localNotificationResponder?.processLocal(notification, forSession: self)
        }
    }
}

extension ZMUserSession: UNUserNotificationCenterDelegate {
    
    private func processPendingNotificationActionsIfPossible() {
        // Don't process note while syncing (data may not be ready yet). We will
        // try again once syncing has completed.
        if self.didStartInitialSync && !self.isPerformingSync && self.pushChannelIsOpen {
            self.processPendingNotificationActions()
        }
    }
    
    public func userNotificationCenter(_ center: UNUserNotificationCenter,
                                       willPresent notification: UNNotification,
                                       withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void)
    {
        log.debug("Notification center wants to present in-app notification: \(notification)")
        let category = notification.request.content.categoryIdentifier
        if category == PushNotificationCategory.incomingCall.rawValue {
            self.handleTrackingOnCallNotification(notification)
        }
        
        // Call completionHandler(.alert) to present in app notification
    }
    
    public func userNotificationCenter(_ center: UNUserNotificationCenter,
                                       didReceive response: UNNotificationResponse,
                                       withCompletionHandler completionHandler: @escaping () -> Void)
    {
        log.debug("Did receive notification response: \(response)")
        let textInput = (response as? UNTextInputNotificationResponse)?.userText
        let note = response.notification
        
        switch response.actionIdentifier {
        case CallNotificationAction.ignore.rawValue:
            ignoreCall(with: note, completionHandler: completionHandler)
            return
        case ConversationNotificationAction.mute.rawValue:
            muteConversation(with: note, completionHandler: completionHandler)
            return
        case ConversationNotificationAction.like.rawValue:
            likeMessage(with: note, completionHandler: completionHandler)
            return
        case ConversationNotificationAction.reply.rawValue:
            if let textInput = textInput {
                reply(with: note, message: textInput, completionHandler: completionHandler)
            }
            return
        default:
            break
        }
        
        // if we reach this, then the action requires opening the app
        self.pendingLocalNotification = ZMStoredLocalNotification(userInfo: note.userInfo,
                                                                  moc: self.managedObjectContext,
                                                                  category: note.request.content.categoryIdentifier,
                                                                  actionIdentifier: response.actionIdentifier)
        self.processPendingNotificationActionsIfPossible()
        
        // TODO: should this only be called after processing has succeeded?
        // or is it risky that this could take too long.
        completionHandler()
    }
}
