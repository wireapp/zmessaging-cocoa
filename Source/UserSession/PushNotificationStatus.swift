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
import WireDataModel

private let lastUpdateEventIDKey = "LastUpdateEventID"

// MARK: - AuthenticationStatusProvider

@objc public protocol AuthenticationStatusProvider { // TODO jacob: move this to another file
    var isAuthenticated: Bool { get }
}

extension ZMPersistentCookieStorage: AuthenticationStatusProvider {
    public var isAuthenticated: Bool {
        return authenticationCookieData != nil
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
            guard let uuidString = self.persistentStoreMetadata(forKey: lastUpdateEventIDKey) as? String,
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


extension BackgroundNotificationFetchStatus: CustomStringConvertible {

    public var description: String {
        switch self {
        case .done: return "done"
        case .inProgress: return "inProgress"
        }
    }

}

@objc
open class PushNotificationStatus: NSObject, BackgroundNotificationFetchStatusProvider {

    private var eventsIdsToFetch: Set<UUID> = Set()
    private var receivedEventsIds: Set<UUID> = Set()
    private var completionHandlers: [UUID: ZMPushResultHandler] = [:]
    
    public var status: BackgroundNotificationFetchStatus {
        return eventsIdsToFetch.isEmpty ? .done : .inProgress
    }
    
    /// Schedule to fetch an event with a given UUID
    ///
    /// - parameter eventId: UUID of the event to fetch
    /// - parameter completionHandler: The completion handler will be run when event has been downloaded and when there's no more events to fetch
    @objc(fetchEventId:completionHandler:)
    public func fetch(eventId: UUID, completionHandler: @escaping (ZMPushPayloadResult) -> Void) {
        // add eventId to list of events to fetch
        
        // TODO jacob: if we receive a push notice for an event which was fetched in a previous launch we would never call the completion handler
        
        guard !receivedEventsIds.contains(eventId) else {
            return completionHandler(.success)
        }
        
        eventsIdsToFetch.insert(eventId)
        completionHandlers[eventId] = completionHandler
        
        RequestAvailableNotification.notifyNewRequestsAvailable(nil)
    }
    
    /// Report events that has successfully been downloaded from the notification stream
    ///
    /// - parameter eventIds: List of UUIDs for events that been downloaded
    /// - parameter finished: True when when all available events have been downloaded
    @objc(didFetchEventIds:finished:)
    public func didFetch(eventIds: [UUID], finished: Bool) {
        // remove eventId from list and call completion handler
        receivedEventsIds.formUnion(eventIds)
        eventsIdsToFetch.subtract(eventIds)
        
        guard !finished else { return }
        
        for eventId in completionHandlers.keys.filter({ self.receivedEventsIds.contains($0) }) {
            let completionHandler = completionHandlers.removeValue(forKey: eventId)
            completionHandler?(.success)
        }
    }
    
    /// Report that events couldn't be fetched due to a permanent error
    public func didFailToFetchEvents() {
        // remove eventId from list and call completion handler
        
        for completionHandler in completionHandlers.values {
            completionHandler(.failure)
        }
        
        eventsIdsToFetch.removeAll()
        completionHandlers.removeAll()
    }
    
}
