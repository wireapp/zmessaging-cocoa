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
import UIKit

/// An abstraction of the application (UIApplication, NSApplication)
@objc public protocol ZMApplication : NSObjectProtocol {
    
    /// The current application state
    var applicationState : UIApplicationState { get }
    
    /// Badge count
    var applicationIconBadgeNumber : Int { get set }
    
    /// To determine if notification settings should be registered
    @objc optional var shouldRegisterUserNotificationSettings : Bool { get }
    
    /// Register for remote notification
    func registerForRemoteNotifications()
    
    /// Register for change in application state: didBecomeActive
    @objc func registerObserverForDidBecomeActive(_ object: NSObject, selector: Selector)

    /// Register for change in application state: willResignActive
    @objc func registerObserverForWillResignActive(_ object: NSObject, selector: Selector)
    
    /// Register for change in application state: didBecomeActive
    @objc func registerObserverForWillEnterForeground(_ object: NSObject, selector: Selector)
    
    /// Register for change in application state: willResignActive
    @objc func registerObserverForDidEnterBackground(_ object: NSObject, selector: Selector)
    
    /// Register for application will terminate
    @objc func registerObserverForApplicationWillTerminate(_ object: NSObject, selector: Selector)
    
    /// Unregister for change in application state
    @objc func unregisterObserverForStateChange(_ object: NSObject)
    
    /// Sets minimum interval for background fetch
    @objc func setMinimumBackgroundFetchInterval(_ minimumBackgroundFetchInterval: TimeInterval)
}


extension UIApplication : ZMApplication {
    
    @objc public func registerObserverForDidBecomeActive(_ object: NSObject, selector: Selector) {
        NotificationCenter.default.addObserver(object, selector: selector, name: NSNotification.Name.UIApplicationDidBecomeActive, object: nil)
    }
    
    @objc public func registerObserverForWillResignActive(_ object: NSObject, selector: Selector) {
        NotificationCenter.default.addObserver(object, selector: selector, name: NSNotification.Name.UIApplicationWillResignActive, object: nil)
    }
    
    @objc public func registerObserverForWillEnterForeground(_ object: NSObject, selector: Selector) {
        NotificationCenter.default.addObserver(object, selector: selector, name: NSNotification.Name.UIApplicationWillEnterForeground, object: nil)
    }
    
    @objc public func registerObserverForDidEnterBackground(_ object: NSObject, selector: Selector) {
        NotificationCenter.default.addObserver(object, selector: selector, name: NSNotification.Name.UIApplicationDidEnterBackground, object: nil)
    }
    
    @objc public func registerObserverForApplicationWillTerminate(_ object: NSObject, selector: Selector) {
        NotificationCenter.default.addObserver(object, selector: selector, name: NSNotification.Name.UIApplicationWillTerminate, object: nil)
    }
    
    @objc public func unregisterObserverForStateChange(_ object: NSObject) {
        NotificationCenter.default.removeObserver(object, name: NSNotification.Name.UIApplicationWillResignActive, object: nil)
        NotificationCenter.default.removeObserver(object, name: NSNotification.Name.UIApplicationDidBecomeActive, object: nil)
        NotificationCenter.default.removeObserver(object, name: NSNotification.Name.UIApplicationWillEnterForeground, object: nil)
        NotificationCenter.default.removeObserver(object, name: NSNotification.Name.UIApplicationDidEnterBackground, object: nil)
        NotificationCenter.default.removeObserver(object, name: NSNotification.Name.UIApplicationWillTerminate, object: nil)
    }
}
