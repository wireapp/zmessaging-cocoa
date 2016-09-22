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
import ZMUtilities
import ZMTransport


@objc
public final class PingBackRequestStrategy: ZMObjectSyncStrategy, ZMObjectStrategy {
    
    weak fileprivate(set) var authenticationStatus: ZMAuthenticationStatus?
    weak fileprivate(set) var pingBackStatus: BackgroundAPNSPingBackStatus?
    
    fileprivate(set) var pingBackSync: ZMSingleRequestSync!
    
    public init(managedObjectContext moc: NSManagedObjectContext, backgroundAPNSPingBackStatus: BackgroundAPNSPingBackStatus,
        authenticationStatus: ZMAuthenticationStatus) {
        self.authenticationStatus = authenticationStatus
        pingBackStatus = backgroundAPNSPingBackStatus
        super.init(managedObjectContext: moc)
        pingBackSync = ZMSingleRequestSync(singleRequestTranscoder: self, managedObjectContext: moc)
    }
    
    public var isSlowSyncDone: Bool {
        return true
    }
    
    public var requestGenerators: [ZMRequestGenerator] {
        return []
    }
    
    public var contextChangeTrackers: [ZMContextChangeTracker] {
        return []
    }
    
    public func nextRequest() -> ZMTransportRequest? {
        guard authenticationStatus?.currentPhase == .authenticated && pingBackStatus?.status == .pinging,
             let hasNotification = pingBackStatus?.hasNotificationIDs , hasNotification
        else { return nil }
        
        pingBackSync.readyForNextRequest()
        return pingBackSync.nextRequest()
    }
    
    public func setNeedsSlowSync() {
        // no op
    }
    
    public func processEvents(_ events: [ZMUpdateEvent], liveEvents: Bool, prefetchResult: ZMFetchRequestBatchResult?) {
        // no op
    }
    
}

// MARK: - ZMSingleRequestTranscoder

extension PingBackRequestStrategy: ZMSingleRequestTranscoder {
    
    public func request(for sync: ZMSingleRequestSync!) -> ZMTransportRequest! {
        guard sync == pingBackSync else { return nil }
        guard let nextEventsWithID = pingBackStatus?.nextNotificationEventsWithID() else { return nil }
        let path = "/push/fallback/\(nextEventsWithID.identifier.transportString())/cancel"
        let request = ZMTransportRequest(path: path, method: .methodPOST, payload: nil)
        request.forceToVoipSession()
        let completion = ZMCompletionHandler(on: managedObjectContext)  { [weak self] response in
            self?.pingBackStatus?.didPerfomPingBackRequest(nextEventsWithID, responseStatus: response.result)
        }
        
        request.add(completion)
        
        APNSPerformanceTracker.sharedTracker.trackNotification(
            nextEventsWithID.identifier,
            state: .pingBackStrategy(notice: false),
            analytics: managedObjectContext.analytics
        )
        
        return request
    }
    
    public func didReceive(_ response: ZMTransportResponse!, forSingleRequest sync: ZMSingleRequestSync!) {
        // no op
    }
    
}
