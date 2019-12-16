
//
// Wire
// Copyright (C) 2017 Wire Swiss GmbH
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


fileprivate extension Team {
    
    static var predicateForTeamRolesNeedingToBeUpdated: NSPredicate = {
        NSPredicate(format: "%K == YES AND %K != NULL", #keyPath(Team.needsToRedownloadMembers), Team.remoteIdentifierDataKey()!)
    }()
    
}

@objc
public final class TeamRolesDownloadRequestStrategy: AbstractRequestStrategy, ZMContextChangeTrackerSource, ZMRequestGeneratorSource {
    
    private (set) var downstreamSync: ZMDownstreamObjectSync!
    fileprivate unowned var syncStatus: SyncStatus
    
    public init(withManagedObjectContext managedObjectContext: NSManagedObjectContext, applicationStatus: ApplicationStatus, syncStatus: SyncStatus) {
        self.syncStatus = syncStatus
        super.init(withManagedObjectContext: managedObjectContext, applicationStatus: applicationStatus)
        configuration = [.allowsRequestsDuringEventProcessing]
        downstreamSync = ZMDownstreamObjectSync(
            transcoder: self,
            entityName: Team.entityName(),
            predicateForObjectsToDownload: Team.predicateForTeamRolesNeedingToBeUpdated,
            filter: nil,
            managedObjectContext: managedObjectContext
        )
    }
    
    public override func nextRequestIfAllowed() -> ZMTransportRequest? {
        return downstreamSync.nextRequest()
    }
    
    public var contextChangeTrackers: [ZMContextChangeTracker] {
        return [downstreamSync]
    }
    
    public var requestGenerators: [ZMRequestGenerator] {
        return [downstreamSync]
    }
    
}


extension TeamRolesDownloadRequestStrategy: ZMDownstreamTranscoder {
    
    public func request(forFetching object: ZMManagedObject!, downstreamSync: ZMObjectSync!) -> ZMTransportRequest! {
        guard downstreamSync as? ZMDownstreamObjectSync == self.downstreamSync, let team = object as? Team else { fatal("Wrong sync or object for: \(object.safeForLoggingDescription)") }
        return TeamDownloadRequestFactory.requestToDownloadRoles(for: team.remoteIdentifier!)
    }
    
    public func update(_ object: ZMManagedObject!, with response: ZMTransportResponse!, downstreamSync: ZMObjectSync!) {
        guard downstreamSync as? ZMDownstreamObjectSync == self.downstreamSync,
            let team = object as? Team,
            let payload = response.payload?.asDictionary() as? [String: Any] else { return }
        
        
        team.needsToRedownloadMembers = true
        team.update(with: payload)
    }
    
    public func delete(_ object: ZMManagedObject!, with response: ZMTransportResponse!, downstreamSync: ZMObjectSync!) {
        // pass
    }
}
