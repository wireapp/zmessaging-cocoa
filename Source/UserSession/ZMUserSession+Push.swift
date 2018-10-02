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

// MARK: - UNUserNotificationCenterDelegate

/*
 * Note: Although ZMUserSession conforms to UNUserNotificationCenterDelegate,
 * it should not actually be assigned as the delegate of UNUserNotificationCenter.
 * Instead, the delegate should be the SessionManager, whose repsonsibility it is
 * to forward the method calls to the appropriate user session.
 */
extension ZMUserSession: UNUserNotificationCenterDelegate {
    
    // Called by the SessionManager when a notification is received while the app
    // is in the foreground.
    public func userNotificationCenter(_ center: UNUserNotificationCenter,
                                       willPresent notification: UNNotification,
                                       withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void)
    {
        log.debug("Notification center wants to present in-app notification: \(notification)")
        let categoryIdentifier = notification.request.content.categoryIdentifier
        
        handleInAppNotification(with: notification.userInfo,
                                categoryIdentifier: categoryIdentifier,
                                completionHandler: completionHandler)
    }
    
    // Called by the SessionManager when the user engages a notification action.
    public func userNotificationCenter(_ center: UNUserNotificationCenter,
                                       didReceive response: UNNotificationResponse,
                                       withCompletionHandler completionHandler: @escaping () -> Void)
    {
        log.debug("Did receive notification response: \(response)")
        let userText = (response as? UNTextInputNotificationResponse)?.userText
        let note = response.notification
        
        handleNotificationResponse(actionIdentifier: response.actionIdentifier,
                                   categoryIdentifier: note.request.content.categoryIdentifier,
                                   userInfo: note.userInfo,
                                   userText: userText,
                                   completionHandler: completionHandler)
    }
    
    // MARK: Abstractions
    
    /* The logic for handling notifications/actions is factored out of the
     * delegate methods because we cannot create `UNNotification` and
     * `UNNotificationResponse` objects in unit tests.
     */
    
    func handleInAppNotification(with userInfo: NotificationUserInfo,
                                 categoryIdentifier: String,
                                 completionHandler: @escaping (UNNotificationPresentationOptions) -> Void)
    {
        if categoryIdentifier == PushNotificationCategory.incomingCall.rawValue {
            self.handleTrackingOnCallNotification(with: userInfo)
        }
        
        // foreground notification responder exists on the UI context, so we
        // need to switch to that context
        self.managedObjectContext.perform {
            guard let conv = userInfo.conversation(in: self.managedObjectContext)?.remoteIdentifier
            else { return completionHandler([]) }
            
            let responder = self.sessionManager.foregroundNotificationResponder
            let shouldPresent = responder?.shouldPresentForegroundNotification(for: conv) ?? true
            
            var options = UNNotificationPresentationOptions()
            if shouldPresent { options = [.alert, .sound] }
            
            completionHandler(options)
        }
    }
    
    func handleNotificationResponse(actionIdentifier: String,
                                    categoryIdentifier: String,
                                    userInfo: NotificationUserInfo,
                                    userText: String? = nil,
                                    completionHandler: @escaping () -> Void)
    {
        switch actionIdentifier {
        case CallNotificationAction.ignore.rawValue:
            ignoreCall(with: userInfo, completionHandler: completionHandler)
        case CallNotificationAction.accept.rawValue:
            acceptCall(with: userInfo, completionHandler: completionHandler)
        case ConversationNotificationAction.like.rawValue:
            likeMessage(with: userInfo, completionHandler: completionHandler)
        case ConversationNotificationAction.reply.rawValue:
            if let textInput = userText {
                reply(with: userInfo, message: textInput, completionHandler: completionHandler)
            }
        case ConversationNotificationAction.connect.rawValue:
            acceptConnectionRequest(with: userInfo, completionHandler: completionHandler)
        default:
            open(userInfo.conversation(in: managedObjectContext), at: nil)
            completionHandler()
            break
        }
    }
    
}
