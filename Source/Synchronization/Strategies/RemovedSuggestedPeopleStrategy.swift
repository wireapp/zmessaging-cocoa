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


public class RemovedSuggestedPeopleStrategy : NSObject, ZMRequestGenerator, ZMRemoteIdentifierObjectTranscoder {

    var tornDown : Bool = false
    var remoteIDSync : ZMRemoteIdentifierObjectSync!
    unowned var managedObjectContext: NSManagedObjectContext
    unowned var clientRegistrationDelegate : ClientRegistrationDelegate
    
    public init(managedObjectContext: NSManagedObjectContext, clientRegistrationDelegate: ClientRegistrationDelegate) {
        self.managedObjectContext = managedObjectContext
        self.clientRegistrationDelegate = clientRegistrationDelegate
        super.init()
        
        remoteIDSync = ZMRemoteIdentifierObjectSync(transcoder: self, managedObjectContext: managedObjectContext)
        NotificationCenter.default.addObserver(forName: Notification.Name(rawValue:ZMRemovedSuggestedContactRemoteIdentifiersDidChange), object:nil, queue:nil, using: remoteIdentifiersDidChange)
    }
    
    public func tearDown() {
        tornDown = true
        NotificationCenter.default.removeObserver(self)
    }
    
    deinit {
        precondition(tornDown, "Needs to tear down RemovedSuggestedPeopleStrategy")
    }
    
    func remoteIdentifiersDidChange(note: Notification) {
        managedObjectContext.performGroupedBlock {
            guard let identifiers = self.managedObjectContext.removedSuggestedContactRemoteIdentifiers as? [UUID] else { return }
            self.remoteIDSync.addRemoteIdentifiersThatNeedDownload(Set(identifiers))
            RequestAvailableNotification.notifyNewRequestsAvailable(self)
        }
    }
    
    public func maximumRemoteIdentifiersPerRequest(for sync: ZMRemoteIdentifierObjectSync!) -> UInt {
        return 1
    }
    
    public func nextRequest() -> ZMTransportRequest? {
        guard clientRegistrationDelegate.clientIsReadyForRequests else { return nil }
        return remoteIDSync.nextRequest()
    }
    
    public func request(for sync: ZMRemoteIdentifierObjectSync!, remoteIdentifiers identifiers: Set<UUID>!) -> ZMTransportRequest! {
        precondition(identifiers.count == 1, "More than one identifiers in request to block user")
        
        let remoteID = identifiers.first!
        let path = "/search/suggestions/\(remoteID.transportString())/ignore"
        return ZMTransportRequest.emptyPut(withPath: path)
    }
    
    public func didReceive(_ response: ZMTransportResponse!, remoteIdentifierObjectSync sync: ZMRemoteIdentifierObjectSync!, forRemoteIdentifiers remoteIdentifiers: Set<UUID>!) {
        switch response.result {
        case .success, .permanentError:
            didComplete(remoteIdentifiers:remoteIdentifiers)
        case .temporaryError, .expired, .tryAgainLater:
            break;
        }
    }
    
    func didComplete(remoteIdentifiers: Set<UUID>) {
        guard let oldIdentifiers = self.managedObjectContext.removedSuggestedContactRemoteIdentifiers as? [UUID] else { return }
        let result = oldIdentifiers.filter{!remoteIdentifiers.contains($0)}
        managedObjectContext.removedSuggestedContactRemoteIdentifiers = result
        managedObjectContext.enqueueDelayedSave()
    }
}

