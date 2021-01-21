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

struct TeamListPayload: Decodable {
    let hasMore: Bool
    let teams: [TeamPayload]
    
    private enum CodingKeys: String, CodingKey {
        case hasMore = "has_more"
        case teams
    }
}

struct TeamPayload: Decodable {
    
    let identifier: UUID
    let name: String
    let creator: UUID
    let binding: Bool
    let icon: String
    let iconKey: String?
    
    private enum CodingKeys: String, CodingKey {
        case identifier = "id"
        case name
        case creator
        case binding
        case icon
        case iconKey = "icon_key"
    }
        
}

extension TeamPayload {
    
    func createOrUpdateTeam(in managedObjectContext: NSManagedObjectContext) -> Team? {
        var created: Bool = false
        guard let team = Team.fetchOrCreate(with: identifier,
                                            create: true,
                                            in: managedObjectContext,
                                            created: &created)
        else {
            return nil
        }
        
        if created {
            let selfUser = ZMUser.selfUser(in: managedObjectContext)
            _ = Member.getOrCreateMember(for: selfUser, in: team, context: managedObjectContext)
        }
        
        updateTeam(team, in: managedObjectContext)
                
        return team
    }
    
    func updateTeam(_ team: Team, in managedObjectContext: NSManagedObjectContext) {
        team.name = name
        team.creator = ZMUser.fetchAndMerge(with: creator, createIfNeeded: true, in: managedObjectContext)
        team.pictureAssetId = icon
        team.pictureAssetKey = iconKey
        
        if !binding {
            managedObjectContext.delete(team)
        }
    }
    
}

fileprivate extension Team {

    static var predicateForObjectsNeedingToBeUpdated: NSPredicate = {
        NSPredicate(format: "%K == YES AND %K != NULL", #keyPath(Team.needsToBeUpdatedFromBackend), Team.remoteIdentifierDataKey()!)
    }()

}

/// Responsible for downloading the team which the self user belongs to during the slow sync
/// and for updating it when processing events or when manually requested.
public final class TeamDownloadRequestStrategy: AbstractRequestStrategy, ZMContextChangeTrackerSource {

    private (set) var downstreamSync: ZMDownstreamObjectSync!
    private (set) var slowSync: ZMSingleRequestSync!
    
    fileprivate unowned var syncStatus: SyncStatus
    
    public init(withManagedObjectContext managedObjectContext: NSManagedObjectContext, applicationStatus: ApplicationStatus, syncStatus: SyncStatus) {
        self.syncStatus = syncStatus
        super.init(withManagedObjectContext: managedObjectContext, applicationStatus: applicationStatus)
        configuration = [.allowsRequestsWhileOnline, .allowsRequestsDuringSlowSync]
        downstreamSync = ZMDownstreamObjectSync(
            transcoder: self,
            entityName: Team.entityName(),
            predicateForObjectsToDownload: Team.predicateForObjectsNeedingToBeUpdated,
            filter: nil,
            managedObjectContext: managedObjectContext
        )
        slowSync = ZMSingleRequestSync(singleRequestTranscoder: self,
                                       groupQueue: managedObjectContext)
    }

    public override func nextRequestIfAllowed() -> ZMTransportRequest? {
        if isSyncing {
            slowSync.readyForNextRequestIfNotBusy()
            return slowSync.nextRequest()
        } else {
            return downstreamSync.nextRequest()
        }
    }

    public var contextChangeTrackers: [ZMContextChangeTracker] {
        return [downstreamSync]
    }
    
    fileprivate var expectedSyncPhase : SyncPhase {
        return .fetchingTeams;
    }
    
    fileprivate var isSyncing: Bool {
        return syncStatus.currentSyncPhase == expectedSyncPhase
    }

}

extension TeamDownloadRequestStrategy: ZMSingleRequestTranscoder {
    
    public func request(for sync: ZMSingleRequestSync) -> ZMTransportRequest? {
        return TeamDownloadRequestFactory.getTeamsRequest
    }
    
    public func didReceive(_ response: ZMTransportResponse, forSingleRequest sync: ZMSingleRequestSync) {
        guard
            let rawData = response.rawData,
            let teamListPayload = TeamListPayload(rawData)
        else {
            syncStatus.failCurrentSyncPhase(phase: expectedSyncPhase)
            return
        }
        
        _ = teamListPayload.teams.first?.createOrUpdateTeam(in: managedObjectContext)
                        
        syncStatus.finishCurrentSyncPhase(phase: expectedSyncPhase)
    }
    
}

extension TeamDownloadRequestStrategy: ZMDownstreamTranscoder {

    public func request(forFetching object: ZMManagedObject!, downstreamSync: ZMObjectSync!) -> ZMTransportRequest! {
        guard downstreamSync as? ZMDownstreamObjectSync == self.downstreamSync, let team = object as? Team else { fatal("Wrong sync or object for: \(object.safeForLoggingDescription)") }
        return team.remoteIdentifier.map { TeamDownloadRequestFactory.getRequest(for: $0) }
    }

    public func update(_ object: ZMManagedObject!, with response: ZMTransportResponse!, downstreamSync: ZMObjectSync!) {
        guard
            downstreamSync as? ZMDownstreamObjectSync == self.downstreamSync,
            let team = object as? Team,
            let rawData = response.rawData,
            let teamPayload = TeamPayload(rawData) else { return }
                    
        teamPayload.updateTeam(team, in: managedObjectContext)
        
        team.needsToBeUpdatedFromBackend = false
        team.needsToDownloadRoles = true
    }

    public func delete(_ object: ZMManagedObject!, with response: ZMTransportResponse!, downstreamSync: ZMObjectSync!) {
        guard downstreamSync as? ZMDownstreamObjectSync == self.downstreamSync, let team = object as? Team else { return }
        
        managedObjectContext.delete(team)
    }
}
