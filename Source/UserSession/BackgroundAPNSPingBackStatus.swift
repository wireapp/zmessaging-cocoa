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
    case Pinging, FetchingNotice, Done
}

@objc public class BackgroundAPNSPingBackStatus: NSObject {

    public typealias PingBackResultHandler = (ZMPushPayloadResult, [ZMUpdateEvent]) -> Void
    public typealias EventsWithHandler = (events: [ZMUpdateEvent]?, handler: PingBackResultHandler)
    
    public private(set) var eventsWithHandlerByNotificationID: [NSUUID: EventsWithHandler] = [:]
    public private(set) var backgroundActivity: ZMBackgroundActivity?
    public var status: PingBackStatus = .Done

    public var hasNotificationIDs: Bool {
        if let next = notificationIDs.first {
            return !next.isNotice
        }
        return false
    }
    
    public var hasNoticeNotificationIDs: Bool {
        if let next = notificationIDs.first {
            return next.isNotice
        }
        return false
    }
    
    private var notificationIDs: [EventsWithIdentifier] = []
    private var notificationIDToEventsMap : [NSUUID : [ZMUpdateEvent]] = [:]
    
    private var syncManagedObjectContext: NSManagedObjectContext
    private weak var authenticationStatusProvider: AuthenticationStatusProvider?
    
    public init(
        syncManagedObjectContext moc: NSManagedObjectContext,
                                 authenticationProvider: AuthenticationStatusProvider
        )
    {
        syncManagedObjectContext = moc
        authenticationStatusProvider = authenticationProvider
        super.init()
    }
    
    deinit {
        backgroundActivity?.endActivity()
    }
    
    public func nextNotificationEventsWithID() -> EventsWithIdentifier? {
        return hasNotificationIDs ?  notificationIDs.removeFirst() : .None
    }
    
    public func nextNoticeNotificationEventsWithID() -> EventsWithIdentifier? {
        return hasNoticeNotificationIDs ? notificationIDs.removeFirst() : .None
    }
    
    public func didReceiveVoIPNotification(eventsWithID: EventsWithIdentifier, handler: PingBackResultHandler) {
        APNSPerformanceTracker.sharedTracker.trackNotification(
            eventsWithID.identifier,
            state: .PingBackStatus,
            analytics: syncManagedObjectContext.analytics
        )
        
        notificationIDs.append(eventsWithID)
        if !eventsWithID.isNotice {
            notificationIDToEventsMap[eventsWithID.identifier] = eventsWithID.events
        }
        eventsWithHandlerByNotificationID[eventsWithID.identifier] = (eventsWithID.events, handler)
        
        if authenticationStatusProvider?.currentPhase == .Authenticated {
            backgroundActivity = backgroundActivity ?? BackgroundActivityFactory.sharedInstance().backgroundActivity(withName:"Ping back to BE")
        }
        
        if status == .Done {
            updateStatus()
        }
        
        ZMOperationLoop.notifyNewRequestsAvailable(self)
    }
    
    public func didPerfomPingBackRequest(eventsWithID: EventsWithIdentifier, responseStatus: ZMTransportResponseStatus) {
        let notificationID = eventsWithID.identifier
        let eventsWithHandler = eventsWithHandlerByNotificationID.removeValueForKey(notificationID)

        updateStatus()
        zmLog.debug("Pingback with status \(status) for notification ID: \(notificationID)")
        
        if responseStatus == .TryAgainLater {
            guard let handler = eventsWithHandler?.handler else { return }
            didReceiveVoIPNotification(eventsWithID, handler: handler)
        }
        
        if responseStatus != .TryAgainLater {
            let result : ZMPushPayloadResult = (responseStatus == .Success) ? .Success : .Failure
            eventsWithHandler?.handler(result, notificationIDToEventsMap[notificationID] ?? [])
        }
    }
    
    public func didFetchNoticeNotification(eventsWithID: EventsWithIdentifier, responseStatus: ZMTransportResponseStatus, events: [ZMUpdateEvent]) {
        var finalEvents = events
        let notificationID = eventsWithID.identifier
        
        switch responseStatus {
        case .Success: // we fetched the event and pinged back
            finalEvents = events
            notificationIDToEventsMap[notificationID] = events
            fallthrough
        case .TryAgainLater:
            didPerfomPingBackRequest(eventsWithID, responseStatus: responseStatus)
        default: // we could't fetch the event and want the fallback
            let eventsWithHandler = eventsWithHandlerByNotificationID.removeValueForKey(notificationID)
            defer { eventsWithHandler?.handler(.Failure, []) }
            updateStatus()
        }
        
        zmLog.debug("Fetching notification with status \(responseStatus) for notification ID: \(notificationID)")
    }
    
    func updateStatus() {
        if notificationIDs.isEmpty {
            backgroundActivity?.endActivity()
            backgroundActivity = nil
            status = .Done
        } else {
            status = hasNoticeNotificationIDs ? .FetchingNotice : .Pinging
        }
    }
    
}
