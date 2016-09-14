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
@objc(ZMApplication) public protocol Application : NSObjectProtocol {
    
    /// the current application state
    var applicationState : UIApplicationState { get }

    /// Schedules a local notification
    func scheduleLocalNotification(notification: UILocalNotification)
    
    /// Cancels a local notification
    func cancelLocalNotification(notification: UILocalNotification)
    
    /// Register for remote notification
    func registerForRemoteNotifications()
    
    /// whether alert notifications are enabled
    var alertNotificationsEnabled : Bool { get }
    
    /// Badge count
    var applicationIconBadgeNumber : Int { get set }
    
    /// Register for change in application state: didBecomeActive
    @objc func registerObserverForDidBecomeActive(object: NSObject, selector: Selector)

    /// Register for change in application state: willResignActive
    @objc func registerObserverForWillResignActive(object: NSObject, selector: Selector)
    
    /// Register for change in application state: didBecomeActive
    @objc func registerObserverForWillEnterForeground(object: NSObject, selector: Selector)
    
    /// Register for change in application state: willResignActive
    @objc func registerObserverForDidEnterBackground(object: NSObject, selector: Selector)
    
    /// Register for application will terminate
    @objc func registerObserverForApplicationWillTerminate(object: NSObject, selector: Selector)
    
    /// Unregister for change in application state
    @objc func unregisterObserverForStateChange(object: NSObject)
    
    /// Register user notification settings
    @objc func registerUserNotificationSettings(settings: UIUserNotificationSettings)
    
    /// Sets minimum interval for background fetch
    @objc func setMinimumBackgroundFetchInterval(minimumBackgroundFetchInterval: NSTimeInterval)
}


extension UIApplication : Application {
    
    public var alertNotificationsEnabled : Bool {
        return self.currentUserNotificationSettings()?.types.contains(.Alert) ?? false
    }
    
    @objc public func registerObserverForDidBecomeActive(object: NSObject, selector: Selector) {
        NSNotificationCenter.defaultCenter().addObserver(object, selector: selector, name: UIApplicationDidBecomeActiveNotification, object: nil)
    }
    
    @objc public func registerObserverForWillResignActive(object: NSObject, selector: Selector) {
        NSNotificationCenter.defaultCenter().addObserver(object, selector: selector, name: UIApplicationWillResignActiveNotification, object: nil)
    }
    
    @objc public func registerObserverForWillEnterForeground(object: NSObject, selector: Selector) {
        NSNotificationCenter.defaultCenter().addObserver(object, selector: selector, name: UIApplicationWillEnterForegroundNotification, object: nil)
    }
    
    @objc public func registerObserverForDidEnterBackground(object: NSObject, selector: Selector) {
        NSNotificationCenter.defaultCenter().addObserver(object, selector: selector, name: UIApplicationDidEnterBackgroundNotification, object: nil)
    }
    
    @objc public func registerObserverForApplicationWillTerminate(object: NSObject, selector: Selector) {
        NSNotificationCenter.defaultCenter().addObserver(object, selector: selector, name: UIApplicationWillTerminateNotification, object: nil)
    }
    
    @objc public func unregisterObserverForStateChange(object: NSObject) {
        NSNotificationCenter.defaultCenter().removeObserver(object, name: UIApplicationWillResignActiveNotification, object: nil)
        NSNotificationCenter.defaultCenter().removeObserver(object, name: UIApplicationDidBecomeActiveNotification, object: nil)
        NSNotificationCenter.defaultCenter().removeObserver(object, name: UIApplicationWillEnterForegroundNotification, object: nil)
        NSNotificationCenter.defaultCenter().removeObserver(object, name: UIApplicationDidEnterBackgroundNotification, object: nil)
        NSNotificationCenter.defaultCenter().removeObserver(object, name: UIApplicationWillTerminateNotification, object: nil)
    }
}