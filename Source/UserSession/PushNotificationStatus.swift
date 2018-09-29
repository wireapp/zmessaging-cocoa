//
// Wire
// Copyright (C) 2018 Wire Swiss GmbH
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

private let zmLog = ZMSLog(tag: "PushNotificationStatus")

extension UUID {
    func compare(withType1 uuid: UUID) -> ComparisonResult {
        return (self as NSUUID).compare(withType1UUID: uuid as NSUUID)
    }
}

extension BackgroundNotificationFetchStatus: CustomStringConvertible {

    public var description: String {
        switch self {
        case .done: return "done"
        case .inProgress: return "inProgress"
        }
    }

}

@objcMembers
open class PushNotificationStatus: NSObject, BackgroundNotificationFetchStatusProvider {

    private var eventIdRanking = NSMutableOrderedSet()
    private var completionHandlers: [UUID: () -> Void] = [:]
    private let managedObjectContext: NSManagedObjectContext
    
    public var status: BackgroundNotificationFetchStatus {
        return eventIdRanking.count == 0 ? .done : .inProgress
    }
    
    public init(managedObjectContext: NSManagedObjectContext) {
        self.managedObjectContext = managedObjectContext
    }
    
    /// Schedule to fetch an event with a given UUID
    ///
    /// - parameter eventId: UUID of the event to fetch
    /// - parameter completionHandler: The completion handler will be run when event has been downloaded and when there's no more events to fetch
    @objc(fetchEventId:completionHandler:)
    public func fetch(eventId: UUID, completionHandler: @escaping () -> Void) {
        guard eventId.isType1UUID else {
            return zmLog.error("Attempt to fetch event id not conforming to UUID type1: \(eventId)")
        }
        
        if lastEventIdIsNewerThan(eventId: eventId){
            // We have already fetched the event and will therefore immediately call the completion handler
            return completionHandler()
        }
        
        Logging.eventProcessing.info("Scheduling to fetch events notified by push")
        
        eventIdRanking.add(eventId)
        completionHandlers[eventId] = completionHandler
        
        RequestAvailableNotification.notifyNewRequestsAvailable(nil)
    }
    
    /// Report events that has successfully been downloaded from the notification stream
    ///
    /// - parameter eventIds: List of UUIDs for events that been downloaded
    /// - parameter finished: True when when all available events have been downloaded
    @objc(didFetchEventIds:finished:)
    public func didFetch(eventIds: [UUID], finished: Bool) {
        let highestRankingEventId = eventIdRanking.firstObject as? UUID
        
        highestRankingEventId.apply(eventIdRanking.remove)
        eventIdRanking.minusSet(Set<UUID>(eventIds))
        
        guard finished else { return }
        
        Logging.eventProcessing.info("Finished to fetching all available events")
        
        for eventId in completionHandlers.keys.filter({  self.lastEventIdIsNewerThan(eventId: $0) || highestRankingEventId == $0 }) {
            let completionHandler = completionHandlers.removeValue(forKey: eventId)
            completionHandler?()
        }
    }
    
    /// Report that events couldn't be fetched due to a permanent error
    public func didFailToFetchEvents() {
        for completionHandler in completionHandlers.values {
            completionHandler()
        }
        
        eventIdRanking.removeAllObjects()
        completionHandlers.removeAll()
    }
    
    private func lastEventIdIsNewerThan(eventId: UUID) -> Bool {
        guard let order = managedObjectContext.zm_lastNotificationID?.compare(withType1: eventId) else { return false }
        return order == .orderedDescending || order == .orderedSame
    }
    
}
