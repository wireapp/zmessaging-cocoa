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

/// An abstraction of the application (UIApplication, NSApplication)
@objc(ZMApplication) public protocol Application : NSObjectProtocol {
    
    /// Whether the application is currently in the background
    var isInBackground : Bool { get }

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
}

extension UIApplication : Application {
    
    public var isInBackground : Bool {
        return self.applicationState == .Background
    }
    
    public var alertNotificationsEnabled : Bool {
        return self.currentUserNotificationSettings()?.types.contains(.Alert) ?? false
    }
}