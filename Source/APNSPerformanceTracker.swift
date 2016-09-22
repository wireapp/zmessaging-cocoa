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

public typealias Timestamp = Date

public enum NotificationFunnelState {
    case operationLoop(serverTimestamp: Timestamp, notificationsEnabled: Bool, background: Bool, currentDate: Date)
    case pingBackStatus
    case pingBackStrategy(notice: Bool)
    case notificationDispatcher
    
    var attributes: [String: NSObject] {
        var attributes = customTrackingAttributes
        attributes["state_description"] = stateDescription as NSObject?
        attributes["state_index"] = stateIndex as NSObject?
        return attributes
    }
    
    var isInitialState: Bool {
        if case .operationLoop = self {
            return true
        }
        
        return false
    }
    
    var isLastState: Bool {
        if case .notificationDispatcher = self {
            return true
        }
        
        return false
    }
    
    fileprivate var customTrackingAttributes: [String: NSObject] {
        switch self {
        case .operationLoop(serverTimestamp: let timestamp, notificationsEnabled: let enabled, background: let background, currentDate: let date):
            let difference = Int(round(date.timeIntervalSince(timestamp) * TimeInterval.millisecondsPerSecond)) // In milliseconds
            let clusterized = IntegerClusterizer.voipTimeDifferenceClusterizer.clusterize(difference)
            return ["server_timestamp_difference": clusterized as NSObject, "background": background as NSObject, "allowed_notifications": enabled as NSObject]
        case .pingBackStrategy(notice: let notice):
            return ["notice": notice as NSObject]
        default:
            return [:]
        }
    }
    
    fileprivate var stateDescription: String {
        switch self {
        case .operationLoop: return "OperationLoop"
        case .pingBackStatus: return "PingBackStatus"
        case .pingBackStrategy: return "PingBackStrategy"
        case .notificationDispatcher: return "NotificationDispatcher"
        }
    }
    
    fileprivate var stateIndex: Int {
        switch self {
        case .operationLoop: return 0
        case .pingBackStatus: return 1
        case .pingBackStrategy: return 2
        case .notificationDispatcher: return 3
        }
    }
}

private let notificationEventName = "apns_performance"
private let notificationNotCreatedEventName = "apns_no_notification"
private let notificationReceivedEventName = "apns_received"
private let notificationUserSessionEventName = "apns_user_session"
private let notificationDecryptionFailedEventName = "apns_decryption_failed"

extension TimeInterval {
    static var millisecondsPerSecond: TimeInterval { return 1000.0 }
}

@objc public final class APNSPerformanceTracker: NSObject {
    @objc public static let sharedTracker = APNSPerformanceTracker()
    
    /// Map from notification ID to the last timestamp
    var timestampsByNotificationID = [UUID: Timestamp]()
    
    /// Tracks a step in the notification funnel, `currentDate` can be injected for testing
    func trackNotification(_ identifier: UUID, state: NotificationFunnelState, analytics: AnalyticsType?, currentDate: Date? = nil) {
        guard let analytics = analytics else { return }
        var attributes = state.attributes
        
        if !state.isInitialState, let lastTimestamp = timestampsByNotificationID[identifier] {
            let date = currentDate ?? Date()
            print(date.timeIntervalSince(lastTimestamp))
            let difference = round(date.timeIntervalSince(lastTimestamp) * TimeInterval.millisecondsPerSecond) // In milliseconds
            let clusterized = IntegerClusterizer.apnsPerformanceClusterizer.clusterize(Int(difference))
            attributes["time_since_last"] = clusterized as NSObject?
        }

        attributes["notification_identifier"] = identifier.transportString() as NSObject?
        timestampsByNotificationID[identifier] = currentDate ?? Date()
        analytics.tagEvent(notificationEventName, attributes: attributes)
        
        if state.isLastState {
            removeTrackedNotification(identifier)
        }
    }
    
    @objc public func removeTrackedNotification(_ identifier: UUID) {
        timestampsByNotificationID[identifier] = nil
    }
    
    @objc public func removeAllTrackedNotifications() {
        timestampsByNotificationID.removeAll()
    }
    
}

// MARK: - Helper to make associated value enums work with ojbc

public extension APNSPerformanceTracker {

    @objc static func trackVOIPNotificationInOperationLoop(_ eventsWithIdentifier: EventsWithIdentifier, analytics: AnalyticsType?, application: Application) {
        guard analytics != nil, let payload = eventsWithIdentifier.events?.first?.payload, let timestamp = (payload as NSDictionary).date(forKey: "time") else { return }
        let background = application.applicationState == .background
        APNSPerformanceTracker.sharedTracker.trackNotification(
            eventsWithIdentifier.identifier,
            state: .operationLoop(serverTimestamp: timestamp, notificationsEnabled: application.alertNotificationsEnabled, background: background, currentDate: Date()),
            analytics: analytics
        )
    }
    
    @objc static func trackVOIPNotificationInOperationLoopNotCreatingNotification(_ analytics: AnalyticsType?) {
        analytics?.tagEvent(notificationNotCreatedEventName)
    }

    @objc static func trackVOIPNotificationInNotificationDispatcher(_ identifier: UUID, analytics: AnalyticsType) {
        APNSPerformanceTracker.sharedTracker.trackNotification(
            identifier,
            state: .notificationDispatcher,
            analytics: analytics
        )
    }
    
    @objc static func trackAPNSPayloadDecryptionFailure(_ analytics: AnalyticsType?) {
        analytics?.tagEvent(notificationDecryptionFailedEventName)
    }
    
    @objc static func trackAPNSInUserSession(_ analytics: AnalyticsType?, authenticated: Bool, isInBackground: Bool) {
        analytics?.tagEvent(notificationUserSessionEventName, attributes: ["authenticated": NSNumber(value: authenticated),
                                                                           "background": (isInBackground ? "background" : "active") as NSString])
    }
    
    @objc static func trackReceivedNotification(_ analytics: AnalyticsType?) {
        analytics?.tagEvent(notificationReceivedEventName)
    }

}

