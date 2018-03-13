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

private let log = ZMSLog(tag: "SessionManager")

extension SessionManager {
    public func registerSessionForRemoteNotificationsIfNeeded(_ session: ZMUserSession) {
        session.managedObjectContext.performGroupedBlock {
            // Refresh the tokens if needed
            self.pushDispatcher.lastKnownPushTokens.forEach { type, actualToken in
                switch type {
                case .voip:
                    if actualToken != session.managedObjectContext.pushKitToken?.deviceToken {
                        session.managedObjectContext.pushKitToken = nil
                        session.setPushKitToken(actualToken)
                    }
                case .regular:
                    if actualToken != session.managedObjectContext.pushToken?.deviceToken {
                        session.managedObjectContext.pushToken = nil
                        session.setPushToken(actualToken)
                    }
                }
            }
            
            session.registerForRemoteNotifications()
        }
    }
    
    // Must be called when the AppDelegate receives the new push token.
    public func didRegisteredForRemoteNotifications(with token: Data) {
        self.pushDispatcher.didRegisteredForRemoteNotifications(with: token)
    }
    
    // Must be called when the AppDelegate receives the new push notification.
    @objc(didReceiveRemoteNotification:fetchCompletionHandler:)
    public func didReceiveRemote(notification: [AnyHashable: Any],
                                fetchCompletionHandler: @escaping (UIBackgroundFetchResult)->()) {
        self.pushDispatcher.didReceiveRemoteNotification(notification, fetchCompletionHandler: fetchCompletionHandler)
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

extension SessionManager: PushDispatcherClient {
    // Called by PushDispatcher when the pust notification is received. Wakes up or creates the user session for the
    // account mentioned in the notification.
    public func receivedPushNotification(with payload: [AnyHashable: Any],
                                         from source: ZMPushNotficationType,
                                         completion: ZMPushNotificationCompletionHandler?) {
        
        guard let accountId = payload.accountId(), let account = self.accountManager.account(with: accountId) else {
            completion?(.noData)
            return
        }
            
        withSession(for: account, perform: { userSession in
            userSession.receivedPushNotification(with: payload, from: source, completion: completion)
        })
    }
}
