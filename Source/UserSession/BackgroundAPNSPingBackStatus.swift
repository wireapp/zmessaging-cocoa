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


private let lastUpdateEventIDKey = "LastUpdateEventID"
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

@objc public protocol ZMLastNotificationIDStore {
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

            self.setPersistentStoreMetadata(newValue?.uuidString, key: lastUpdateEventIDKey)
        }

        get {
            guard let uuidString = self.persistentStoreMetadata(forKey: "LastUpdateEventID") as? String,
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

@objc open class BackgroundAPNSPingBackStatus: NSObject {

    public typealias PingBackResultHandler = (ZMPushPayloadResult, [ZMUpdateEvent]) -> Void
    public typealias EventsWithHandler = (events: [ZMUpdateEvent]?, handler: PingBackResultHandler)
    
    public private(set) var eventsWithHandlerByNotificationID: [UUID: EventsWithHandler] = [:]
    public private(set) var backgroundActivity: ZMBackgroundActivity?
    public var status: PingBackStatus = .done

    public var hasNotificationIDs: Bool {
        return nil != notificationIDs.first
    }

    internal private(set) var notificationIDs: [EventsWithIdentifier] = []
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
        return notificationIDs.first
    }
    
    public func didReceiveVoIPNotification(_ eventsWithID: EventsWithIdentifier, handler: @escaping PingBackResultHandler) {
        APNSPerformanceTracker.sharedTracker.trackNotification(
            eventsWithID.identifier,
            state: .pingBackStatus,
            analytics: syncManagedObjectContext.analytics
        )

        zmLog.debug("Notification fetch triggered for \(eventsWithID.identifier)")
        notificationIDs.append(eventsWithID)

        eventsWithHandlerByNotificationID[eventsWithID.identifier] = (eventsWithID.events, handler)
        guard authenticationStatusProvider?.currentPhase == .authenticated else { return }

        backgroundActivity = backgroundActivity ?? BackgroundActivityFactory.sharedInstance().backgroundActivity(withName:"Ping back to BE")

        if status == .done {
            updateStatus()
        }

        RequestAvailableNotification.notifyNewRequestsAvailable(self)
    }

    @objc(didReceiveEncryptedEvents:originalEvents:hasMore:)
    public func didReceive(encryptedEvents: [ZMUpdateEvent], originalEvents: EventsWithIdentifier, hasMore: Bool) {
        let receivedIdentifiers = encryptedEvents.flatMap { $0.uuid }
        let identifier = originalEvents.identifier
        let receivedOriginal = receivedIdentifiers.contains(identifier)

        if let index = notificationIDs.index(of: originalEvents) {
            notificationIDs.remove(at: index)
        }

        zmLog.debug("Received events from notification stream for \(identifier), received original: \(receivedOriginal), hasMore: \(hasMore)")

        // If we do not have any more notifications to fetch we want to 
        // update the status, end the background activity and remove the handler
        defer {
            if !hasMore {
                zmLog.debug("Received last batch for \(identifier), updating status")
                updateStatus()
                eventsWithHandlerByNotificationID[identifier] = nil
            }
        }

        // Call the handler with the events fetched from the notification stream
        eventsWithHandlerByNotificationID[identifier]?.handler(.success, encryptedEvents)
    }

    @objc(didFailDownloadingOriginalEvents:)
    public func didFailDownloading(originalEvents: EventsWithIdentifier) {
        if let index = notificationIDs.index(of: originalEvents) {
            notificationIDs.remove(at: index)
        }
        updateStatus()
        guard let handler = eventsWithHandlerByNotificationID.removeValue(forKey: originalEvents.identifier)?.handler else { return }
        handler(.failure, [])
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
