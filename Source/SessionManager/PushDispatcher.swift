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

@objc public enum PushTokenType: Int {
    case voip
    case regular
}

public struct PushToken {
    let type: PushTokenType
    let data: Data?
}

// Non-optional push client.
public protocol PushDispatcherClient: NSObjectProtocol {
    func receivedPushNotification(with payload: [AnyHashable: Any], from source: ZMPushNotficationType, completion: ZMPushNotificationCompletionHandler?)
}

// Optional push client.
public protocol PushDispatcherOptionalClient: PushDispatcherClient {
    func updatedPushToken(to: PushToken)
    
    // Returns true if it must handle the given payload.
    func mustHandle(payload: [AnyHashable: Any]) -> Bool
}

private let log = ZMSLog(tag: "Push")

// This class is designed to deliver the push notification payloads and push token updates from multiple sources to 
// multiple consumers.
public final class PushDispatcher: NSObject {
    
    class WeakSet<T>: Sequence {
        
        var count: Int {
            return weakStorage.count
        }
        
        private let weakStorage = NSHashTable<AnyObject>.weakObjects()
        
        func add(_ object: T) {
            weakStorage.add(object as AnyObject)
        }
        
        func makeIterator() -> AnyIterator<T> {
            let enumerator = weakStorage.objectEnumerator()
            return AnyIterator {
                return enumerator.nextObject() as! T?
            }
        }
    }

    private let clients = WeakSet<PushDispatcherOptionalClient>()
    public weak var fallbackClient: PushDispatcherClient? = nil
    private var remoteNotificationHandler: ApplicationRemoteNotification!
    internal var pushRegistrant: PushKitRegistrant!
    private(set) var lastKnownPushTokens: [PushTokenType: Data] = [:]
    private let callbackQueue: DispatchQueue = DispatchQueue.main
    private let notificationsTracker: NotificationsTracker?
    
    init(analytics: AnalyticsType?) {
        if let analytics = analytics {
            notificationsTracker = NotificationsTracker(analytics: analytics)
        } else {
            notificationsTracker = nil
        }

        super.init()
        let didReceivePayload: DidReceivePushCallback = { [weak self] (payload, source, onCompletion) in
            
            log.debug("push notification: \(payload), source \(source)")
            
            guard let `self` = self else {
                return
            }

            let completion: ZMPushNotificationCompletionHandler = {
                self.notificationsTracker?.registerNotificationProcessingCompleted()
                onCompletion?($0)
            }

            self.notificationsTracker?.registerReceivedPush()

            self.callbackQueue.async {
                let possibleHandlers = self.clients.filter { $0.mustHandle(payload: payload) }
                
                if let handler = possibleHandlers.last {
                    handler.receivedPushNotification(with: payload, from: source, completion: completion)
                } else {
                    self.fallbackClient?.receivedPushNotification(with: payload, from: source, completion: completion)
                }
            }
        }
        
        self.enableAlertPushNotifications(with: didReceivePayload)
        self.enableVoIPPushNotifications(with: didReceivePayload)
    }
    
    // Adds one more consumer @c client. The consumer is not retained and is removed from the pool when being deallocated.
    func add(client: PushDispatcherOptionalClient) {
        lastKnownPushTokens.forEach { type, data in
            client.updatedPushToken(to: PushToken(type: type, data: data))
        }
        clients.add(client)
    }
    
    private func updatePushToken(to token: PushToken) {
        if let data = token.data {
            self.lastKnownPushTokens[token.type] = data
        }
        
        self.clients.forEach { client in
            self.callbackQueue.async {
                client.updatedPushToken(to: token)
            }
        }
    }
    
    private func enableAlertPushNotifications(with callback: @escaping DidReceivePushCallback) {
        let didUpdateToken: (Data) -> () = { [weak self] (data: Data) in
            self?.updatePushToken(to: PushToken(type: .regular, data: data))
        }
        remoteNotificationHandler = ApplicationRemoteNotification(didUpdateCredentials: didUpdateToken,
                                                                  didReceivePayload: callback,
                                                                  didInvalidateToken: {})
    }
    
    private func enableVoIPPushNotifications(with callback: @escaping DidReceivePushCallback) {
        let didUpdateToken: (Data) -> () = { [weak self] (data: Data) in
            self?.updatePushToken(to: PushToken(type: .voip, data: data))
        }
        
        let didInvalidateToken: () -> () = { [weak self] in
            self?.updatePushToken(to: PushToken(type: .voip, data: nil))
        }
        
        pushRegistrant = PushKitRegistrant(didUpdateCredentials: didUpdateToken,
                                           didReceivePayload: callback,
                                           didInvalidateToken: didInvalidateToken)
        pushRegistrant.notificationsTracker = self.notificationsTracker
        if let token = pushRegistrant.pushToken {
            self.lastKnownPushTokens[.voip] = token
        }
    }
    
    // Called to update the consumers with the new available `.regular` push token data.
    public func didRegisteredForRemoteNotifications(with token: Data) {
        self.updatePushToken(to: PushToken(type: .regular, data: token))
    }
    
    // Can be called to dispatch the newcoming notification to the consumers. Usually used from the AppDelegate's
    // -application:didReceiveRemoteNotification:completionHandler:
    public func didReceiveRemoteNotification(_ payload: [AnyHashable: Any],
                                             fetchCompletionHandler: @escaping (UIBackgroundFetchResult)->()) {
        self.remoteNotificationHandler.didReceiveRemoteNotification(payload,
                                                                    fetchCompletionHandler: fetchCompletionHandler)
    }
}

