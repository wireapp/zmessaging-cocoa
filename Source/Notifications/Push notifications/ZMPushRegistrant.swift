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
import ZMTransport


/// This is a generic protocol for receiving remote push notifications.
///
/// It is implemented by PushKitRegistrant for PushKit,
/// and by ApplicationRemoteNotification for the 'legacy' UIApplicationDelegate based API.
@objc(ZMPushNotificationSource)
protocol PushNotificationSource {
    /// The current push token (i.e. credentials)
    var pushToken: NSData? { get }
    
    /// All callbacks could happen on any queue. Make sure to switch to the right queue when they get called.
    ///
    /// - parameter didUpdateCredentials: will be called with the device token
    /// - parameter didReceivePayload: will be called with the push notification data. The block needs to be called when processing the data is complete and indicate if data was fetched
    /// - parameter didInvalidateToken: will be called when the device token becomes invalid
    init(didUpdateCredentials: (NSData) -> Void, didReceivePayload: (NSDictionary, ZMPushNotficationType, (ZMPushPayloadResult) -> Void) -> Void, didInvalidateToken: () -> Void)
}


private func ZMLogPushKit_swift(@autoclosure text:  () -> String) -> Void {
    if (ZMLogPushKit_enabled()) {
        ZMLogPushKit_s(text())
    }
}



/// A simple wrapper for PushKit remote push notifications
///
/// Simple closures for push events.
@objc(ZMPushRegistrant)
public final class PushKitRegistrant : NSObject, PushNotificationSource {
    
    public var pushToken: NSData? {
        get {
            return registry.pushTokenForType(PKPushTypeVoIP)
        }
    }
    
    public var analytics: AnalyticsType?
    
    public convenience required init(didUpdateCredentials: (NSData) -> Void, didReceivePayload: (NSDictionary, ZMPushNotficationType, (ZMPushPayloadResult) -> Void) -> Void, didInvalidateToken: () -> Void) {
        self.init(fakeRegistry: nil, didUpdateCredentials: didUpdateCredentials, didReceivePayload: didReceivePayload, didInvalidateToken: didInvalidateToken)
    }
    
    let queue: dispatch_queue_t
    let registry: PKPushRegistry
    let didUpdateCredentials: (NSData) -> Void
    let didReceivePayload: (NSDictionary, ZMPushNotficationType, (ZMPushPayloadResult) -> Void) -> Void
    let didInvalidateToken: () -> Void
    
    public init(fakeRegistry: PKPushRegistry?, didUpdateCredentials: (NSData) -> Void, didReceivePayload: (NSDictionary, ZMPushNotficationType, (ZMPushPayloadResult) -> Void) -> Void, didInvalidateToken: () -> Void) {
        let q = dispatch_queue_create("PushRegistrant", DISPATCH_QUEUE_SERIAL)
        self.queue = q
        self.registry = fakeRegistry ?? PKPushRegistry(queue: q)
        self.didUpdateCredentials = didUpdateCredentials
        self.didReceivePayload = didReceivePayload
        self.didInvalidateToken = didInvalidateToken
        super.init()
        dispatch_set_target_queue(queue, dispatch_get_global_queue(0, 0))
        self.registry.delegate = self
        self.registry.desiredPushTypes = Set(arrayLiteral: PKPushTypeVoIP)
        ZMLogPushKit_swift("Created registrant. Registry = \(self.registry.description)")
    }
}

extension PushKitRegistrant : PKPushRegistryDelegate {
    public func pushRegistry(registry: PKPushRegistry!, didUpdatePushCredentials credentials: PKPushCredentials!, forType type: String!) {
        ZMLogPushKit_swift("Registry \(self.registry.description) updated credentials for type '\(type)'.")
        if type != PKPushTypeVoIP {
            return
        }
        didUpdateCredentials(credentials.token)
    }
    
    public func pushRegistry(registry: PKPushRegistry!, didReceiveIncomingPushWithPayload payload: PKPushPayload!, forType type: String!) {
        ZMLogPushKit_swift("Registry \(self.registry.description) did receive '\(payload.type)' payload: \(payload.dictionaryPayload)")
        if let a = BackgroundActivityFactory.sharedInstance().backgroundActivity(withName:"Process PushKit payload") {
            APNSPerformanceTracker.trackReceivedNotification(analytics)
            
            didReceivePayload(payload.dictionaryPayload, .VoIP) {
                result in
                ZMLogPushKit_swift("Registry \(self.registry.description) did finish background task")
                a.endActivity()
            }
        }
    }
    public func pushRegistry(registry: PKPushRegistry!, didInvalidatePushTokenForType type: String!) {
        ZMLogPushKit_swift("Registry \(self.registry.description) did invalide push token for type '\(type)'.")
        didInvalidateToken()
    }
}


/// A simple wrapper around UIApplicationDelegate for push notifications
///
/// The UIApplicationDelegate messages need to be forwarded to this class.
@objc(ZMApplicationRemoteNotification)
public class ApplicationRemoteNotification : NSObject, PushNotificationSource {
    
    var pushToken: NSData?
    public required init(didUpdateCredentials: (NSData) -> Void, didReceivePayload: (NSDictionary, ZMPushNotficationType, (ZMPushPayloadResult) -> Void) -> Void, didInvalidateToken: () -> Void) {
        self.didUpdateCredentials = didUpdateCredentials
        self.didReceivePayload = didReceivePayload
    }
    
    let didUpdateCredentials: (NSData) -> Void
    let didReceivePayload: (NSDictionary, ZMPushNotficationType, (ZMPushPayloadResult) -> Void) -> Void
    
}


extension ApplicationRemoteNotification : UIApplicationDelegate {
    public func application(application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: NSData) {
        pushToken = deviceToken
        didUpdateCredentials(deviceToken)
    }
    
    public func application(application: UIApplication, didReceiveRemoteNotification userInfo: [NSObject : AnyObject], fetchCompletionHandler completionHandler: (UIBackgroundFetchResult) -> Void) {
        if let a = BackgroundActivityFactory.sharedInstance().backgroundActivity(withName: "Process remote notification payload") {
            didReceivePayload(userInfo, .Alert) { result in
                completionHandler(self.fetchResult(result))
                a.endActivity()
            }
        }
    }
    
    private func fetchResult(result: ZMPushPayloadResult) -> UIBackgroundFetchResult {
        switch (result) {
        case .Success:
            return .NewData
        case .Failure:
            return .Failed
        case .NoData:
            return .NoData
        }
    }
}
