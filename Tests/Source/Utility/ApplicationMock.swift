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
import zmessaging

/// A mock of Application that records the calls
@objc public class ApplicationMock : NSObject {
    
    public var applicationState: UIApplicationState = .Active
    
    public var alertNotificationsEnabled: Bool = false
    
    /// Records calls to `scheduleLocalNotification`
    public var scheduledLocalNotifications : [UILocalNotification] = []
    
    /// Records calls to `cancelledLocalNotifications`
    public var cancelledLocalNotifications : [UILocalNotification] = []
    
    /// Records calls to `registerForRemoteNotification`
    public var registerForRemoteNotificationCount : Int = 0
    
    /// The current badge icon number
    public var applicationIconBadgeNumber: Int = 0
    
    /// Records calls to `registerUserNotificationSettings`
    public var registeredUserNotificationSettings : [UIUserNotificationSettings] = []
    
    /// Records calls to `setMinimumBackgroundFetchInterval`
    public var minimumBackgroundFetchInverval : NSTimeInterval = UIApplicationBackgroundFetchIntervalNever
    
    /// Callback invoked when `registerUserNotificationSettings` is invoked
    public var registerForRemoteNotificationsCallback : ()->() = { _ in }
}

// MARK: - Application protocol
extension ApplicationMock : Application {
    
    public func scheduleLocalNotification(notification: UILocalNotification) {
        self.scheduledLocalNotifications.append(notification)
    }
    
    public func cancelLocalNotification(notification: UILocalNotification) {
        self.cancelledLocalNotifications.append(notification)
    }
    
    public func registerForRemoteNotifications() {
        self.registerForRemoteNotificationCount += 1
        self.registerForRemoteNotificationsCallback()
    }
    
    public func registerUserNotificationSettings(settings: UIUserNotificationSettings) {
        self.registeredUserNotificationSettings.append(settings)
    }
    
    public func setMinimumBackgroundFetchInterval(minimumBackgroundFetchInterval: NSTimeInterval) {
        self.minimumBackgroundFetchInverval = minimumBackgroundFetchInterval
    }
}

// MARK: - Observers
extension ApplicationMock {
    
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

// MARK: - Simulate application state change
extension ApplicationMock {
    
    @objc public func simulateApplicationDidBecomeActive() {
        NSNotificationCenter.defaultCenter().postNotificationName(UIApplicationDidBecomeActiveNotification, object: nil)
    }
    
    @objc public func simulateApplicationWillResignActive() {
        NSNotificationCenter.defaultCenter().postNotificationName(UIApplicationWillResignActiveNotification, object: nil)
    }
    
    @objc public func simulateApplicationWillEnterForeground() {
        NSNotificationCenter.defaultCenter().postNotificationName(UIApplicationWillEnterForegroundNotification, object: nil)
    }
    
    @objc public func simulateApplicationDidEnterBackground() {
        NSNotificationCenter.defaultCenter().postNotificationName(UIApplicationDidEnterBackgroundNotification, object: nil)
    }
    
    @objc public func simulateApplicationWillTerminate() {
        NSNotificationCenter.defaultCenter().postNotificationName(UIApplicationWillTerminateNotification, object: nil)
    }
    
    var isInBackground : Bool {
        return self.applicationState == .Background
    }
    
    @objc func setBackground() {
        self.applicationState = .Background
    }
    
    var isInactive : Bool {
        return self.applicationState == .Inactive
    }
    
    @objc func setInactive() {
        self.applicationState = .Inactive
    }
    
    var isActive : Bool {
        return self.applicationState == .Active
    }
    
    @objc func setActive() {
        self.applicationState = .Active
    }

}
