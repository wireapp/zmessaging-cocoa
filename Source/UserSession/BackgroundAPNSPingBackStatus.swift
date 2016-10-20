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
import ZMCDataModel

private let zmLog = ZMSLog(tag: "Pingback")

// MARK: - AuthenticationStatusProvider

@objc public protocol AuthenticationStatusProvider {
    var currentPhase: ZMAuthenticationPhase { get }
}

extension ZMAuthenticationStatus: AuthenticationStatusProvider {}


// MARK: - EventsWithIdentifier

@objc public final class EventsWithIdentifier: NSObject  {
    public let events: [ZMUpdateEvent]?
    public let identifier: UUID
    public let isNotice : Bool
    
    public init(events: [ZMUpdateEvent]?, identifier: UUID, isNotice: Bool) {
        self.events = events
        self.identifier = identifier
        self.isNotice = isNotice
    }
    
    public func filteredWithoutPreexistingNonces(_ nonces: [UUID]) -> EventsWithIdentifier {
        let filteredEvents = events?.filter { event in
            guard let nonce = event.messageNonce() else { return true }
            return !nonces.contains(nonce)
        }
        return EventsWithIdentifier(events: filteredEvents, identifier: identifier, isNotice: isNotice)
    }
}

extension EventsWithIdentifier {
    override public var debugDescription: String {
        return "<EventsWithIdentifier>: identifier: \(identifier), events: \(events)"
    }
}

@objc public protocol ZMLastNotificationIDStore: ZMKeyValueStore {
    var zm_lastNotificationID : UUID? { get set }
    var zm_hasLastNotificationID : Bool { get }
}

extension UUID {
    func compare(withType1 uuid: UUID) -> ComparisonResult {
        return (self as NSUUID).compare(withType1UUID: uuid as NSUUID)
    }
}

extension NSManagedObjectContext : ZMLastNotificationIDStore {
    public var zm_lastNotificationID: UUID? {
        set (newValue) {
            if let value = newValue, let previousValue = zm_lastNotificationID,
                value.isType1UUID && previousValue.isType1UUID &&
                previousValue.compare(withType1: value) != .orderedAscending {
                return
            }

            setValue(newValue?.uuidString, forKey: "LastUpdateEventID")
        }

        get {
            guard let uuidString = value(forKey: "LastUpdateEventID") as? String,
                let uuid = UUID(uuidString: uuidString)
                else { return nil }
            return uuid
        }
    }

    public var zm_hasLastNotificationID: Bool {
        return zm_lastNotificationID != nil
    }
}


// MARK: - BackgroundAPNSPingBackStatus

@objc public enum PingBackStatus: UInt8 {
    case done, inProgress
}

@objc public class BackgroundAPNSPingBackStatus: NSObject {

    public typealias PingBackResultHandler = (ZMPushPayloadResult, [ZMUpdateEvent]) -> Void
    public typealias EventsWithHandler = (events: [ZMUpdateEvent]?, handler: PingBackResultHandler)
    
    public private(set) var eventsWithHandlerByNotificationID: [UUID: EventsWithHandler] = [:]
    public private(set) var backgroundActivity: ZMBackgroundActivity?
    public var status: PingBackStatus = .done

    private var failedOnLastFetch = false

    // We do not care if the notification is a notice or not as we will fetch the notification stream in both cases
    public var hasNotificationIDs: Bool {
        if let next = notificationIDs.first {
            return true
        }
        return false
    }

    private var notificationIDs: [EventsWithIdentifier] = []
    private var notificationIDToEventsMap : [UUID : [ZMUpdateEvent]] = [:]
    
    private var syncManagedObjectContext: NSManagedObjectContext
    private weak var authenticationStatusProvider: AuthenticationStatusProvider?
    
    public init(syncManagedObjectContext moc: NSManagedObjectContext, authenticationProvider: AuthenticationStatusProvider) {
        syncManagedObjectContext = moc
        authenticationStatusProvider = authenticationProvider
        super.init()
    }
    
    deinit {
        backgroundActivity?.end()
    }
    
    public func nextNotificationEventsWithID() -> EventsWithIdentifier? {
        return hasNotificationIDs ? notificationIDs.removeFirst() : .none
    }
    
    public func didReceiveVoIPNotification(_ eventsWithID: EventsWithIdentifier, handler: @escaping PingBackResultHandler) {
        APNSPerformanceTracker.sharedTracker.trackNotification(
            eventsWithID.identifier,
            state: .pingBackStatus,
            analytics: syncManagedObjectContext.analytics
        )

        guard authenticationStatusProvider?.currentPhase == .authenticated else { return }
        notificationIDs.append(eventsWithID)

        eventsWithHandlerByNotificationID[eventsWithID.identifier] = (eventsWithID.events, handler)
        backgroundActivity = backgroundActivity ?? BackgroundActivityFactory.sharedInstance().backgroundActivity(withName:"Ping back to BE")

        if status == .done {
            updateStatus()
        }

        RequestAvailableNotification.notifyNewRequestsAvailable(self)
    }
    
//    public func didPerfomPingBackRequest(_ eventsWithID: EventsWithIdentifier, responseStatus: ZMTransportResponseStatus) {
//        let notificationID = eventsWithID.identifier
//        let eventsWithHandler = eventsWithHandlerByNotificationID.removeValue(forKey: notificationID)
//
//        updateStatus()
//        zmLog.debug("Pingback with status \(status) for notification ID: \(notificationID)")
//        
//        if responseStatus == .tryAgainLater {
//            guard let handler = eventsWithHandler?.handler else { return }
//            didReceiveVoIPNotification(eventsWithID, handler: handler)
//        }
//        
//        if responseStatus != .tryAgainLater {
//            let result: ZMPushPayloadResult = (responseStatus == .success) ? .success : .failure
//            eventsWithHandler?.handler(result, notificationIDToEventsMap[notificationID] ?? [])
//        }
//    }
//    
//    public func didFetchNoticeNotification(_ eventsWithID: EventsWithIdentifier, responseStatus: ZMTransportResponseStatus, events: [ZMUpdateEvent]) {
//        let notificationID = eventsWithID.identifier
//        
//        switch responseStatus {
//        case .success: // we fetched the event and pinged back
//            notificationIDToEventsMap[notificationID] = events
//            fallthrough
//        case .tryAgainLater:
//            didPerfomPingBackRequest(eventsWithID, responseStatus: responseStatus)
//        default: // we could't fetch the event and want the fallback
//            let eventsWithHandler = eventsWithHandlerByNotificationID.removeValue(forKey: notificationID)
//            defer { eventsWithHandler?.handler(.failure, []) }
//            updateStatus()
//        }
//        
//        zmLog.debug("Fetching notification with status \(responseStatus) for notification ID: \(notificationID)")
//    }

    public func didReceiveEvents(_ encryptedEvents: [ZMUpdateEvent], originalEvents: EventsWithIdentifier, hasMore: Bool) {
        let receivedIdentifiers = encryptedEvents.flatMap { $0.uuid }
        let identifier = originalEvents.identifier
        let receivedOriginal = receivedIdentifiers.contains(identifier)

        zmLog.debug("Received events from notification stream for \(identifier), received original: \(receivedOriginal), hasMore: \(hasMore)")

        // If we do not have any more notifications to fetch we want to 
        // update the status, end the background activity and remove the handler
        defer {
            if !hasMore {
                updateStatus()
                eventsWithHandlerByNotificationID[identifier] = nil
            }
        }

        // We did not get the notification for the push and there are no more notifications to be fetched
        if !receivedOriginal && !hasMore {
            // TODO
            return
        }

        // Call the handler with the events fetched from the notification stream
        eventsWithHandlerByNotificationID[identifier]?.handler(.success, encryptedEvents)
    }
    
    func updateStatus() {
        if notificationIDs.isEmpty {
            backgroundActivity?.end()
            backgroundActivity = nil
            status = .done
        } else {
            status = .inProgress
        }
    }
    
}
