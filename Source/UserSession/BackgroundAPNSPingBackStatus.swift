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
import ZMUtilities

private let zmLog = ZMSLog(tag: "Pingback")

// MARK: - AuthenticationStatusProvider

@objc public protocol AuthenticationStatusProvider {
    var currentPhase: ZMAuthenticationPhase { get }
}

extension ZMAuthenticationStatus: AuthenticationStatusProvider {}


// MARK: - LocalNotificationDispatchType

@objc public protocol LocalNotificationDispatchType {
    func didReceiveUpdateEvents(events: [ZMUpdateEvent]?, notificationID: NSUUID)
}

extension ZMLocalNotificationDispatcher: LocalNotificationDispatchType {}


// MARK: - EventsWithIdentifier

@objc public class EventsWithIdentifier: NSObject  {
    public let events: [ZMUpdateEvent]?
    public let identifier: NSUUID
    public let isNotice : Bool
    
    public init(events: [ZMUpdateEvent]?, identifier: NSUUID, isNotice: Bool) {
        self.events = events
        self.identifier = identifier
        self.isNotice = isNotice
    }
    
    public func filteredWithoutPreexistingNonces(nonces: [NSUUID]) -> EventsWithIdentifier {
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


// MARK: - BackgroundAPNSPingBackStatus

@objc public enum PingBackStatus: Int  {
    case Done, Pinging, FetchingNotificationStream, FetchingNotice
}

@objc public protocol ZMMissingUpdateEventTranscoderDelegate : NSObjectProtocol {
    func missingUpdateEventTranscoder(didReceiveEvents decryptedEvents: [ZMUpdateEvent], originalEvents:EventsWithIdentifier, hasMore: Bool)
    func missingUpdateEventTranscoderFailedDownloadingEvents(originalEvents: EventsWithIdentifier)
}

@objc public protocol ZMLastNotificationIDStore: ZMKeyValueStore {
    var zm_lastNotificationID : NSUUID? { get set }
    var zm_hasLastNotificationID : Bool { get }
}

extension NSManagedObjectContext : ZMLastNotificationIDStore {
    public var zm_lastNotificationID: NSUUID? {
        set (newValue) {
            if let value = newValue, previousValue = zm_lastNotificationID where
                value.isType1UUID && previousValue.isType1UUID &&
                  (previousValue.compareWithType1(value) != .OrderedAscending)
            {
                return
            }
            
            setValue(newValue?.UUIDString, forKey: "LastUpdateEventID")
        }
        
        get {
            guard let uuidString = valueForKey("LastUpdateEventID") as? String,
                  let uuid = NSUUID(UUIDString: uuidString)
            else { return nil }
            
            return uuid
        }
    }
    
    public var zm_hasLastNotificationID: Bool {
        return zm_lastNotificationID != nil
    }
}

@objc public class BackgroundAPNSPingBackStatus: NSObject, ZMMissingUpdateEventTranscoderDelegate {

    public typealias PingBackResultHandler = (ZMPushPayloadResult, [ZMUpdateEvent]) -> Void
    public typealias EventsWithHandler = (events: [ZMUpdateEvent]?, handler: PingBackResultHandler)
    
    public private(set) var eventsWithHandlerByNotificationID: [NSUUID: EventsWithHandler] = [:]
    public private(set) var backgroundActivity: ZMBackgroundActivity?
    public var status: PingBackStatus = .Done
    
    public var hasNotificationIDs: Bool {
        if let next = notificationIDs.first {
            return !next.isNotice || isOutdatedNotification(next.identifier)
        }
        return false
    }
    
    public var hasNoticeNotificationIDs: Bool {
        if notificationInProgress {
            return false
        }
        if let next = notificationIDs.first {
            return next.isNotice && !isOutdatedNotification(next.identifier)
        }
        return false
    }
    
    public private (set) var notificationIDs: [EventsWithIdentifier] = []
    private var notificationIDToEventsMap : [NSUUID : [ZMUpdateEvent]] = [:]
    private var failedOnLastFetch : Bool = false
    public private (set) var notificationInProgress: Bool = false
    
    private var syncManagedObjectContext: NSManagedObjectContext
    private weak var authenticationStatusProvider: AuthenticationStatusProvider?
    private weak var notificationDispatcher: LocalNotificationDispatchType?
    
    public init(
        syncManagedObjectContext moc: NSManagedObjectContext,
        authenticationProvider: AuthenticationStatusProvider,
        localNotificationDispatcher: LocalNotificationDispatchType
        ) {
        syncManagedObjectContext = moc
        authenticationStatusProvider = authenticationProvider
        notificationDispatcher = localNotificationDispatcher
        super.init()
    }
    
    deinit {
        backgroundActivity?.endActivity()
    }
    
    public func nextNotificationEventsWithID() -> EventsWithIdentifier? {
        return hasNotificationIDs ? notificationIDs.removeFirst() : .None
    }
    
    public func nextNoticeNotificationEventsWithID() -> EventsWithIdentifier? {
        if hasNoticeNotificationIDs {
            notificationInProgress = true
            return notificationIDs.removeFirst()
        }
        return nil
    }
    
    func isOutdatedNotification(uuid: NSUUID) -> Bool {
        let lastUUID = syncManagedObjectContext.zm_lastNotificationID;
        if lastUUID == nil {
            return false
        }
        return (uuid.compareWithType1(lastUUID!) != .OrderedDescending)
    }
    
    public func didReceiveVoIPNotification(eventsWithID: EventsWithIdentifier, handler: PingBackResultHandler) {
        APNSPerformanceTracker.sharedTracker.trackNotification(
            eventsWithID.identifier,
            state: .PingBackStatus,
            analytics: syncManagedObjectContext.analytics
        )
        guard authenticationStatusProvider?.currentPhase == .Authenticated else { return }

        notificationIDs.append(eventsWithID)
        eventsWithHandlerByNotificationID[eventsWithID.identifier] = (eventsWithID.events, handler)
        
        backgroundActivity = backgroundActivity ?? BackgroundActivityFactory.sharedInstance().backgroundActivity(withName:"Ping back to BE")
        
        if status == .Done {
            updateStatus()
        } else {
            ZMOperationLoop.notifyNewRequestsAvailable(self)
        }

    }
    
    public func didPerfomPingBackRequest(eventsWithID: EventsWithIdentifier, responseStatus: ZMTransportResponseStatus) {
        let notificationID = eventsWithID.identifier
        zmLog.debug("Pingback with status \(responseStatus) for notification ID: \(notificationID)")
        
        if let events = eventsWithID.events where responseStatus == .Success {
            notificationDispatcher?.didReceiveUpdateEvents(events, notificationID: notificationID)
        }
        
        finish(eventsWithID, finalEvents: eventsWithID.events, responseStatus: responseStatus)
    }
    
    func finish(initalEvents: EventsWithIdentifier, finalEvents: [ZMUpdateEvent]?, responseStatus: ZMTransportResponseStatus) {

        updateStatus()
        guard let handler = eventsWithHandlerByNotificationID.removeValueForKey(initalEvents.identifier)?.handler
        else { return }

        switch responseStatus {
        case .Success:
            handler(.Success, finalEvents ?? [])
        case .TryAgainLater:
            didReceiveVoIPNotification(initalEvents, handler: handler)
            updateStatus()
        default:
            handler(.Failure, [])
        }
    }
    
    public func didFetchNoticeNotification(eventsWithID: EventsWithIdentifier, responseStatus: ZMTransportResponseStatus, events: [ZMUpdateEvent]) {
        var finalEvents = [ZMUpdateEvent]()
        let notificationID = eventsWithID.identifier
        
        zmLog.debug("Fetching notification with status \(responseStatus) for notification ID: \(notificationID)")

        if responseStatus == .Success { // we fetched the event and pinged back
            let cryptoBox = syncManagedObjectContext.zm_cryptKeyStore.box
            let decryptedEvents = events.flatMap {
                cryptoBox.decryptUpdateEventAndAddClient($0, managedObjectContext: syncManagedObjectContext)
            }
            finalEvents = decryptedEvents
            notificationDispatcher?.didReceiveUpdateEvents(finalEvents, notificationID: notificationID)
        }

        finish(eventsWithID, finalEvents: finalEvents, responseStatus: responseStatus)
    }
    
    func updateStatus() {
        if notificationIDs.isEmpty {
            backgroundActivity?.endActivity()
            backgroundActivity = nil
            status = .Done
        } else {
            let fetchModus : PingBackStatus = failedOnLastFetch ? .FetchingNotice : .FetchingNotificationStream
            
            status = hasNoticeNotificationIDs ? fetchModus : .Pinging
            ZMOperationLoop.notifyNewRequestsAvailable(self)
        }
    }
    
    
    public func missingUpdateEventTranscoder(didReceiveEvents decryptedEvents: [ZMUpdateEvent], originalEvents:EventsWithIdentifier, hasMore: Bool) {
        notificationInProgress = hasMore

        if !decryptedEvents.map({$0.uuid}).contains(originalEvents.identifier) && !hasMore {
            // we didn't get the event from the stream / we might have already fetched it?
            finish(originalEvents, finalEvents: [], responseStatus: .PermanentError)
            return
        }
        
        notificationDispatcher?.didReceiveUpdateEvents(decryptedEvents, notificationID: originalEvents.identifier)
        if !hasMore {
            // we only want to call the completionHandler when all requests finished
            // in addition we don't want to forward the events again, since that is already done by the missingUpdateEventTranscoder
            finish(originalEvents, finalEvents: [], responseStatus: .Success)
        }
    }
    
    public func missingUpdateEventTranscoderFailedDownloadingEvents(originalEvents: EventsWithIdentifier) {
        notificationInProgress = false
        failedOnLastFetch = true
        notificationIDs.insert(originalEvents, atIndex: 0)
        updateStatus()
    }
}
