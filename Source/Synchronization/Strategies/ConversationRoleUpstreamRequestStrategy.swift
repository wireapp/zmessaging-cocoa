//
// Wire
// Copyright (C) 2019 Wire Swiss GmbH
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
public class ConversationRoleUpstreamRequestStrategy: AbstractRequestStrategy {
    
    fileprivate let jsonEncoder = JSONEncoder()
    fileprivate var upstreamSync: ZMSingleRequestSync!
    
    override public init(withManagedObjectContext managedObjectContext: NSManagedObjectContext, applicationStatus: ApplicationStatus) {
        super.init(withManagedObjectContext: managedObjectContext, applicationStatus: applicationStatus)
        
        self.configuration = .allowsRequestsDuringEventProcessing
        self.upstreamSync = ZMSingleRequestSync(singleRequestTranscoder: self, groupQueue: managedObjectContext)
    }
    
    override public func nextRequestIfAllowed() -> ZMTransportRequest? {
        return upstreamSync.nextRequest()
    }
    
}

extension ConversationRoleUpstreamRequestStrategy: ZMContextChangeTracker, ZMContextChangeTrackerSource {
    
    public var contextChangeTrackers: [ZMContextChangeTracker] {
        return [self]
    }
    
    public func fetchRequestForTrackedObjects() -> NSFetchRequest<NSFetchRequestResult>? {
        
        ///TODO:
    }
    
    public func addTrackedObjects(_ objects: Set<NSManagedObject>) {
        guard !objects.isEmpty  else { return }
        
        upstreamSync.readyForNextRequestIfNotBusy()
    }
    
    public func objectsDidChange(_ object: Set<NSManagedObject>) {
        ///TODO:
    }
    
}

extension ConversationRoleUpstreamRequestStrategy: ZMSingleRequestTranscoder {
    
    public func request(for sync: ZMSingleRequestSync) -> ZMTransportRequest? {
        ///TODO:
    }
    
    private func didReceive(_ response: ZMTransportResponse, updatedKeys: [(Label, Set<AnyHashable>?)]) {
        ///TODO:
    }
    
    public func didReceive(_ response: ZMTransportResponse, forSingleRequest sync: ZMSingleRequestSync) {
        ///TODO:
    }
    
}
