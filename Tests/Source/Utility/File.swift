//
//  File.swift
//  zmessaging-cocoa
//
//  Created by Marco Conti on 02/09/16.
//  Copyright © 2016 Zeta Project Gmbh. All rights reserved.
//

import Foundation
import zmessaging

@objc public class ApplicationMock : NSObject, Application {
    
    public var isInBackground: Bool = false
    public var alertNotificationsEnabled: Bool = false
    
    public var scheduledLocalNotifications : [UILocalNotification] = []
    public func scheduleLocalNotification(notification: UILocalNotification) {
        scheduledLocalNotifications.append(notification)
    }
    
    public var cancelledLocalNotifications : [UILocalNotification] = []
    public func cancelLocalNotification(notification: UILocalNotification) {
        cancelledLocalNotifications.append(notification)
    }
    
    public var registerForRemoteNotificationCount = 0
    public func registerForRemoteNotifications() {
        registerForRemoteNotificationCount += 1
    }
    
    public var applicationIconBadgeNumber: Int = 0
}

