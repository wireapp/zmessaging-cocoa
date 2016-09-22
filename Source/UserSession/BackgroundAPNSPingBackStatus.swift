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


// MARK: - BackgroundAPNSPingBackStatus

@objc public enum PingBackStatus: Int  {
    case pinging, fetchingNotice, done
}

@objc open class BackgroundAPNSPingBackStatus: NSObject {

    public typealias PingBackResultHandler = (ZMPushPayloadResult, [ZMUpdateEvent]) -> Void
    public typealias EventsWithHandler = (events: [ZMUpdateEvent]?, handler: PingBackResultHandler)
    
    public fileprivate(set) var eventsWithHandlerByNotificationID: [UUID: EventsWithHandler] = [:]
    public fileprivate(set) var backgroundActivity: ZMBackgroundActivity?
    public var status: PingBackStatus = .done

    open var hasNotificationIDs: Bool {
        if let next = notificationIDs.first {
            return !next.isNotice
        }
        return false
    }
    
    open var hasNoticeNotificationIDs: Bool {
        if let next = notificationIDs.first {
            return next.isNotice
        }
        return false
    }
    
    fileprivate var notificationIDs: [EventsWithIdentifier] = []
    fileprivate var notificationIDToEventsMap : [UUID : [ZMUpdateEvent]] = [:]
    
    fileprivate var syncManagedObjectContext: NSManagedObjectContext
    fileprivate weak var authenticationStatusProvider: AuthenticationStatusProvider?
    
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
        backgroundActivity?.end()
    }
    
    open func nextNotificationEventsWithID() -> EventsWithIdentifier? {
        return hasNotificationIDs ?  notificationIDs.removeFirst() : .none
    }
    
    open func nextNoticeNotificationEventsWithID() -> EventsWithIdentifier? {
        return hasNoticeNotificationIDs ? notificationIDs.removeFirst() : .none
    }
    
    open func didReceiveVoIPNotification(_ eventsWithID: EventsWithIdentifier, handler: @escaping PingBackResultHandler) {
        APNSPerformanceTracker.sharedTracker.trackNotification(
            eventsWithID.identifier,
            state: .pingBackStatus,
            analytics: syncManagedObjectContext.analytics
        )
        
        notificationIDs.append(eventsWithID)
        if !eventsWithID.isNotice {
            notificationIDToEventsMap[eventsWithID.identifier] = eventsWithID.events
        }
        eventsWithHandlerByNotificationID[eventsWithID.identifier] = (eventsWithID.events, handler)
        
        if authenticationStatusProvider?.currentPhase == .authenticated {
            backgroundActivity = backgroundActivity ?? BackgroundActivityFactory.sharedInstance().backgroundActivity(withName:"Ping back to BE")
        }
        
        if status == .done {
            updateStatus()
        }
        
        RequestAvailableNotification.notifyNewRequestsAvailable(self)
    }
    
    open func didPerfomPingBackRequest(_ eventsWithID: EventsWithIdentifier, responseStatus: ZMTransportResponseStatus) {
        let notificationID = eventsWithID.identifier
        let eventsWithHandler = eventsWithHandlerByNotificationID.removeValue(forKey: notificationID)

        updateStatus()
        zmLog.debug("Pingback with status \(status) for notification ID: \(notificationID)")
        
        if responseStatus == .tryAgainLater {
            guard let handler = eventsWithHandler?.handler else { return }
            didReceiveVoIPNotification(eventsWithID, handler: handler)
        }
        
        if responseStatus != .tryAgainLater {
            let result : ZMPushPayloadResult = (responseStatus == .success) ? .success : .failure
            eventsWithHandler?.handler(result, notificationIDToEventsMap[notificationID] ?? [])
        }
    }
    
    open func didFetchNoticeNotification(_ eventsWithID: EventsWithIdentifier, responseStatus: ZMTransportResponseStatus, events: [ZMUpdateEvent]) {
        var finalEvents = events
        let notificationID = eventsWithID.identifier
        
        switch responseStatus {
        case .success: // we fetched the event and pinged back
            finalEvents = events
            notificationIDToEventsMap[notificationID] = events
            fallthrough
        case .tryAgainLater:
            didPerfomPingBackRequest(eventsWithID, responseStatus: responseStatus)
        default: // we could't fetch the event and want the fallback
            let eventsWithHandler = eventsWithHandlerByNotificationID.removeValue(forKey: notificationID)
            defer { eventsWithHandler?.handler(.failure, []) }
            updateStatus()
        }
        
        zmLog.debug("Fetching notification with status \(responseStatus) for notification ID: \(notificationID)")
    }
    
    func updateStatus() {
        if notificationIDs.isEmpty {
            backgroundActivity?.end()
            backgroundActivity = nil
            status = .done
        } else {
            status = hasNoticeNotificationIDs ? .fetchingNotice : .pinging
        }
    }
    
}
