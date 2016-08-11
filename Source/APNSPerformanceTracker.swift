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

public typealias Timestamp = NSDate

public enum NotificationFunnelState {
    case OperationLoop(serverTimestamp: Timestamp, notificationsEnabled: Bool, background: Bool, currentDate: NSDate)
    case PingBackStatus
    case PingBackStrategy(notice: Bool)
    case NotificationDispatcher
    
    var attributes: [String: NSObject] {
        var attributes = customTrackingAttributes
        attributes["state_description"] = stateDescription
        attributes["state_index"] = stateIndex
        return attributes
    }
    
    var isInitialState: Bool {
        if case .OperationLoop = self {
            return true
        }
        
        return false
    }
    
    var isLastState: Bool {
        if case .NotificationDispatcher = self {
            return true
        }
        
        return false
    }
    
    private var customTrackingAttributes: [String: NSObject] {
        switch self {
        case .OperationLoop(serverTimestamp: let timestamp, notificationsEnabled: let enabled, background: let background, currentDate: let date):
            let difference = Int(round(date.timeIntervalSinceDate(timestamp) * NSTimeInterval.millisecondsPerSecond)) // In milliseconds
            let clusterized = IntegerClusterizer.voipTimeDifferenceClusterizer.clusterize(difference)
            return ["server_timestamp_difference": clusterized, "background": background, "allowed_notifications": enabled]
        case .PingBackStrategy(notice: let notice):
            return ["notice": notice]
        default:
            return [:]
        }
    }
    
    private var stateDescription: String {
        switch self {
        case .OperationLoop: return "OperationLoop"
        case .PingBackStatus: return "PingBackStatus"
        case .PingBackStrategy: return "PingBackStrategy"
        case .NotificationDispatcher: return "NotificationDispatcher"
        }
    }
    
    private var stateIndex: Int {
        switch self {
        case .OperationLoop: return 0
        case .PingBackStatus: return 1
        case .PingBackStrategy: return 2
        case .NotificationDispatcher: return 3
        }
    }
}

private let notificationEventName = "apns_performance"
private let notificationNotCreatedEventName = "apns_no_notification"
private let notificationReceivedEventName = "apns_received"
private let notificationUserSessionEventName = "apns_user_session"
private let notificationDecryptionFailedEventName = "apns_decryption_failed"

extension NSTimeInterval {
    static var millisecondsPerSecond: NSTimeInterval { return 1000.0 }
}

@objc public final class APNSPerformanceTracker: NSObject {
    @objc public static let sharedTracker = APNSPerformanceTracker()
    
    /// Map from notification ID to the last timestamp
    var timestampsByNotificationID = [NSUUID: Timestamp]()
    
    /// Tracks a step in the notification funnel, `currentDate` can be injected for testing
    func trackNotification(identifier: NSUUID, state: NotificationFunnelState, analytics: AnalyticsType?, currentDate: NSDate? = nil) {
        guard let analytics = analytics else { return }
        var attributes = state.attributes
        
        if !state.isInitialState, let lastTimestamp = timestampsByNotificationID[identifier] {
            let date = currentDate ?? NSDate()
            print(date.timeIntervalSinceDate(lastTimestamp))
            let difference = round(date.timeIntervalSinceDate(lastTimestamp) * NSTimeInterval.millisecondsPerSecond) // In milliseconds
            let clusterized = IntegerClusterizer.apnsPerformanceClusterizer.clusterize(Int(difference))
            attributes["time_since_last"] = clusterized
        }

        attributes["notification_identifier"] = identifier.transportString()
        timestampsByNotificationID[identifier] = currentDate ?? NSDate()
        analytics.tagEvent(notificationEventName, attributes: attributes)
        
        if state.isLastState {
            removeTrackedNotification(identifier)
        }
    }
    
    @objc public func removeTrackedNotification(identifier: NSUUID) {
        timestampsByNotificationID[identifier] = nil
    }
    
    @objc public func removeAllTrackedNotifications() {
        timestampsByNotificationID.removeAll()
    }
    
}

// MARK: - Helper to make associated value enums work with ojbc

public extension APNSPerformanceTracker {

    @objc static func trackVOIPNotificationInOperationLoop(eventsWithIdentifier: EventsWithIdentifier, analytics: AnalyticsType?) {
        guard analytics != nil, let payload = eventsWithIdentifier.events?.first?.payload, timestamp = (payload as NSDictionary).dateForKey("time") else { return }
        let application = UIApplication.sharedApplication()
        let notificationTypes = application.currentUserNotificationSettings()?.types
        let alertEnabled = notificationTypes?.contains(.Alert) ?? false
        let background = application.applicationState == .Background
        APNSPerformanceTracker.sharedTracker.trackNotification(
            eventsWithIdentifier.identifier,
            state: .OperationLoop(serverTimestamp: timestamp, notificationsEnabled: alertEnabled, background: background, currentDate: NSDate()),
            analytics: analytics
        )
    }
    
    @objc static func trackVOIPNotificationInOperationLoopNotCreatingNotification(analytics: AnalyticsType?) {
        analytics?.tagEvent(notificationNotCreatedEventName)
    }

    @objc static func trackVOIPNotificationInNotificationDispatcher(identifier: NSUUID, analytics: AnalyticsType) {
        APNSPerformanceTracker.sharedTracker.trackNotification(
            identifier,
            state: .NotificationDispatcher,
            analytics: analytics
        )
    }
    
    @objc static func trackAPNSPayloadDecryptionFailure(analytics: AnalyticsType?) {
        analytics?.tagEvent(notificationDecryptionFailedEventName)
    }
    
    @objc static func trackAPNSInUserSession(analytics: AnalyticsType?, authenticated: Bool, applicationState: UIApplicationState) {
        analytics?.tagEvent(notificationUserSessionEventName, attributes: ["authenticated": authenticated, "background": applicationState.description])
    }
    
    @objc static func trackReceivedNotification(analytics: AnalyticsType?) {
        analytics?.tagEvent(notificationReceivedEventName)
    }

}

extension UIApplicationState: CustomStringConvertible {
    
    public var description: String {
        switch self {
        case .Active: return "active"
        case .Inactive: return "inactive"
        case .Background: return "background"
        }
    }
    
}
