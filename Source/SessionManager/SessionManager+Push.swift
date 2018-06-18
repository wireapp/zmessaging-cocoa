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
import PushKit

private let log = ZMSLog(tag: "Push")

protocol PushRegistry {
    
    var delegate: PKPushRegistryDelegate? { get set }
    var desiredPushTypes: Set<PKPushType>? { get set }
    
    func pushToken(for type: PKPushType) -> Data?
    
}

extension PKPushRegistry: PushRegistry {}

extension SessionManager {
    
    public func updatePushToken(for session: ZMUserSession) {
        session.managedObjectContext.performGroupedBlock {
            // Refresh the tokens if needed
            if let token = self.pushRegistry.pushToken(for: .voIP) {
                session.setPushKitToken(token)
            }
        }
    }
        
    // Must be called when the AppDelegate receives the new local push notification.
    @objc(didReceiveLocalNotification:application:)
    public func didReceiveLocal(notification: UILocalNotification, application: ZMApplication) {
        if let selfUserId = notification.zm_selfUserUUID,
            let account = self.accountManager.account(with: selfUserId) {
            
            self.withSession(for: account) { userSession in
                userSession.didReceiveLocal(notification: notification, application: application)
            }
        }
    }
    
    // Must be called when the user action with @c identifier is completed on the local notification 
    // @c localNotification (see UIApplicationDelegate).
    @objc(handleActionWithIdentifier:forLocalNotification:withResponseInfo:completionHandler:application:)
    public func handleAction(with identifier: String?,
                             for localNotification: UILocalNotification,
                             with responseInfo: [AnyHashable: Any],
                             completionHandler: @escaping () -> (),
                             application: ZMApplication) {
        if let selfUserId = localNotification.zm_selfUserUUID,
            let account = self.accountManager.account(with: selfUserId) {
            
            self.withSession(for: account) { userSession in
                userSession.handleAction(application: application,
                                         with: identifier,
                                         for: localNotification,
                                         with: responseInfo,
                                         completionHandler: completionHandler)
            }
        }
    }
        
    fileprivate func activateAccount(for session: ZMUserSession, completion: @escaping () -> ()) {
        if session == activeUserSession {
            completion()
            return
        }
        
        var foundSession: Bool = false
        self.backgroundUserSessions.forEach { accountId, backgroundSession in
            if session == backgroundSession, let account = self.accountManager.account(with: accountId) {
                self.select(account) { _ in
                    completion()
                }
                foundSession = true
                return
            }
        }
        
        if !foundSession {
            fatalError("User session \(session) is not present in backgroundSessions")
        }
    }
}

extension SessionManager: ZMRequestsToOpenViewsDelegate {
    public func showConversationList(for userSession: ZMUserSession!) {
        self.activateAccount(for: userSession) { 
            self.requestToOpenViewDelegate?.showConversationList(for: userSession)
        }
    }
    
    public func userSession(_ userSession: ZMUserSession!, show conversation: ZMConversation!) {
        self.activateAccount(for: userSession) {
            self.requestToOpenViewDelegate?.userSession(userSession, show: conversation)
        }
    }
    
    public func userSession(_ userSession: ZMUserSession!, show message: ZMMessage!, in conversation: ZMConversation!) {
        self.activateAccount(for: userSession) {
            self.requestToOpenViewDelegate?.userSession(userSession, show: message, in: conversation)
        }
    }
}

extension SessionManager: PKPushRegistryDelegate {
    
    public func pushRegistry(_ registry: PKPushRegistry, didUpdate pushCredentials: PKPushCredentials, forType type: PKPushType) {
        guard type == .voIP else { return }
        
        log.debug("PushKit token was updated: \(pushCredentials.token)")
        
        // give new push token to all running sessions
        backgroundUserSessions.values.forEach({ userSession in
            userSession.setPushKitToken(pushCredentials.token)
        })
    }
    
    public func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenForType type: PKPushType) {
        guard type == .voIP else { return }
        
        log.debug("PushKit token was invalidated")
        
        // delete push token from all running sessions
        backgroundUserSessions.values.forEach({ userSession in
            userSession.deletePushKitToken()
        })
    }
    
    public func pushRegistry(_ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload, forType type: PKPushType) {
        self.pushRegistry(registry, didReceiveIncomingPushWith: payload, for: type, completion: {})
    }
    
    public func pushRegistry(_ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload, for type: PKPushType, completion: @escaping () -> Void) {
        log.debug("Received push payload: \(payload.dictionaryPayload)")
        
        guard type == .voIP,
            let accountId = payload.dictionaryPayload.accountId(),
            let account = self.accountManager.account(with: accountId),
            let activity = BackgroundActivityFactory.sharedInstance().backgroundActivity(withName: "Process PushKit payload", expirationHandler: { [weak self] in
                log.debug("Processing push payload expired")
                self?.notificationsTracker?.registerProcessingExpired()
            }) else {
            return completion()
        }
        
        notificationsTracker?.registerReceivedPush()
        
        withSession(for: account, perform: { userSession in
            log.debug("Forwarding push payload to user session with account \(account.userIdentifier)")
            
            userSession.receivedPushNotification(with: payload.dictionaryPayload, completion: { [weak self] in
                log.debug("Processing push payload completed")
                self?.notificationsTracker?.registerNotificationProcessingCompleted()
                activity.end()
                completion()
            })
        })
    }
    
}

