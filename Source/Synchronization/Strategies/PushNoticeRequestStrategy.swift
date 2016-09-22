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


@objc
public final class PushNoticeRequestStrategy: ZMObjectSyncStrategy, ZMObjectStrategy {
    
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
        guard authenticationStatus?.currentPhase == .authenticated && pingBackStatus?.status == .fetchingNotice,
              let hasNotification = pingBackStatus?.hasNoticeNotificationIDs , hasNotification
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

extension PushNoticeRequestStrategy: ZMSingleRequestTranscoder {
    
    public func request(for sync: ZMSingleRequestSync!) -> ZMTransportRequest! {
        guard sync == pingBackSync,
              let nextEventsWithID = pingBackStatus?.nextNoticeNotificationEventsWithID(),
              let selfClientID = ZMUser.selfUser(in: self.managedObjectContext).selfClient()?.remoteIdentifier
        else { return nil }
        
        let nextNotificationID = nextEventsWithID.identifier
        let basePath = "/notifications/\((nextNotificationID as NSUUID).transportString())"
        let clientComponent = URLQueryItem(name: "client", value: selfClientID)
        let fallbackComponent = URLQueryItem(name: "cancel_fallback", value: "true")
        var path = URLComponents(string: basePath)
        path!.queryItems = [clientComponent, fallbackComponent]
        
        let request = ZMTransportRequest(path: path!.string!, method: .methodGET, payload: nil)
        request.forceToVoipSession()

        let completion = ZMCompletionHandler(on: managedObjectContext)  { [weak self] response in
            let success = response.result == .success
            var events : [ZMUpdateEvent] = []
            if success {
                events = ZMUpdateEvent.eventsArray(from: response.payload!, source: ZMUpdateEventSource.pushNotification) ?? []
            }
            self?.pingBackStatus?.didFetchNoticeNotification(nextEventsWithID, responseStatus: response.result, events: events)
        }
        
        request.add(completion)
        
        APNSPerformanceTracker.sharedTracker.trackNotification(
            nextNotificationID,
            state: .pingBackStrategy(notice: true),
            analytics: managedObjectContext.analytics
        )
        
        return request
    }
    
    public func didReceive(_ response: ZMTransportResponse!, forSingleRequest sync: ZMSingleRequestSync!) {
        // no op
    }
    
}


