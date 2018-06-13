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
import PushKit
import WireTransport

public typealias ZMPushNotificationCompletionHandler = (ZMPushPayloadResult)->()
public typealias DidReceivePushCallback = (_ payload: [AnyHashable: Any], _ source: ZMPushNotficationType, _ completion: ZMPushNotificationCompletionHandler?) -> ()
/// This is a generic protocol for receiving remote push notifications.
///
/// It is implemented by PushKitRegistrant for PushKit,
/// and by ApplicationRemoteNotification for the 'legacy' UIApplicationDelegate based API.
@objc(ZMPushNotificationSource)
protocol PushNotificationSource {
    /// The current push token (i.e. credentials)
    var pushToken: Data? { get }
    
    /// All callbacks could happen on any queue. Make sure to switch to the right queue when they get called.
    ///
    /// - parameter didUpdateCredentials: will be called with the device token
    /// - parameter didReceivePayload: will be called with the push notification data. The block needs to be called when processing the data is complete and indicate if data was fetched
    /// - parameter didInvalidateToken: will be called when the device token becomes invalid
    init(didUpdateCredentials: @escaping (Data) -> Void, didReceivePayload: @escaping DidReceivePushCallback, didInvalidateToken: @escaping () -> Void)
}


private func ZMLogPushKit_swift( _ text:  @autoclosure () -> String) -> Void {
    if (ZMLogPushKit_enabled()) {
        ZMLogPushKit_s(text())
    }
}



/// A simple wrapper for PushKit remote push notifications
///
/// Simple closures for push events.
@objc(ZMPushRegistrant)
public final class PushKitRegistrant : NSObject, PushNotificationSource {
    
    public var pushToken: Data? {
        get {
            return registry.pushToken(forType: PKPushType.voIP)
        }
    }
    
    public var notificationsTracker: NotificationsTracker?
    public var analytics: AnalyticsType?
    
    public convenience required init(didUpdateCredentials: @escaping (Data) -> Void, didReceivePayload: @escaping DidReceivePushCallback, didInvalidateToken: @escaping () -> Void) {
        self.init(fakeRegistry: nil, didUpdateCredentials: didUpdateCredentials, didReceivePayload: didReceivePayload, didInvalidateToken: didInvalidateToken)
    }
    
    let queue: DispatchQueue
    let registry: PKPushRegistry
    let didUpdateCredentials: (Data) -> Void
    let didReceivePayload: DidReceivePushCallback
    let didInvalidateToken: () -> Void
    
    public init(fakeRegistry: PKPushRegistry?, didUpdateCredentials: @escaping (Data) -> Void, didReceivePayload: @escaping DidReceivePushCallback, didInvalidateToken: @escaping () -> Void) {
        let q = DispatchQueue(label: "PushRegistrant", target: .global())
        self.queue = q
        self.registry = fakeRegistry ?? PKPushRegistry(queue: q)
        self.didUpdateCredentials = didUpdateCredentials
        self.didReceivePayload = didReceivePayload
        self.didInvalidateToken = didInvalidateToken
        super.init()
        
        self.registry.delegate = self
        self.registry.desiredPushTypes = Set(arrayLiteral: PKPushType.voIP)
        ZMLogPushKit_swift("Created registrant. Registry = \(self.registry.description)")
    }
}

extension PushKitRegistrant : PKPushRegistryDelegate {
    public func pushRegistry(_ registry: PKPushRegistry, didUpdate credentials: PKPushCredentials, forType type: PKPushType) {
        ZMLogPushKit_swift("Registry \(self.registry.description) updated credentials for type '\(type)'.")
        if type != PKPushType.voIP {
            return
        }
        didUpdateCredentials(credentials.token)
    }
    
    public func pushRegistry(_ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload, forType type: PKPushType) {
        ZMLogPushKit_swift("Registry \(self.registry.description) did receive '\(payload.type)' payload: \(payload.dictionaryPayload)")
        guard let activity = BackgroundActivityFactory.sharedInstance().backgroundActivity(withName: "Process PushKit payload", expirationHandler: { [weak self] in
            self?.notificationsTracker?.registerProcessingExpired()
        }) else {
            // This should happen only in tests
            return
        }
        didReceivePayload(payload.dictionaryPayload, .voIP) { result in
            ZMLogPushKit_swift("Registry \(self.registry.description) did finish background task")
            activity.end()
        }
    }

    public func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenForType type: PKPushType) {
        ZMLogPushKit_swift("Registry \(self.registry.description) did invalide push token for type '\(type)'.")
        didInvalidateToken()
    }
}

