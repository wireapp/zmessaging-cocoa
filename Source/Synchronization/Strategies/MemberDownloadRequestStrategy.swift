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

import WireUtilities
import WireDataModel

fileprivate extension Team {

    static var predicateForObjectsNeedingToDownloadMembers: NSPredicate = {
        NSPredicate(format: "%K == YES AND %K != NULL", #keyPath(Team.needsToRedownloadMembers), Team.remoteIdentifierDataKey()!)
    }()

    func updateMembers(with response: ZMTransportResponse) {
        guard let membersPayload = response.payload?.asDictionary()?["members"] as? [[String: Any]] else { return }
        let existingMembers = members
        
        // Update or insert new members
        let newMembers = membersPayload.compactMap { Member.createOrUpdate(with: $0, in: self, context: managedObjectContext!) }
        
        // Delete removed members
        let membersToDelete = existingMembers.subtracting(newMembers)
        membersToDelete.forEach {
            managedObjectContext?.delete($0)
        }
    }

}


public final class MemberDownloadRequestStrategy: AbstractRequestStrategy, ZMContextChangeTrackerSource, ZMRequestGeneratorSource {

    private (set) var downstreamSync: ZMDownstreamObjectSync!

    public override init(withManagedObjectContext managedObjectContext: NSManagedObjectContext, applicationStatus: ApplicationStatus) {
        super.init(withManagedObjectContext: managedObjectContext, applicationStatus: applicationStatus)
        configuration = [.allowsRequestsDuringEventProcessing]
        downstreamSync = ZMDownstreamObjectSync(
            transcoder: self,
            entityName: Team.entityName(),
            predicateForObjectsToDownload: Team.predicateForObjectsNeedingToDownloadMembers,
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


extension MemberDownloadRequestStrategy: ZMDownstreamTranscoder {

    public func request(forFetching object: ZMManagedObject!, downstreamSync: ZMObjectSync!) -> ZMTransportRequest! {
        guard downstreamSync as? ZMDownstreamObjectSync == self.downstreamSync, let team = object as? Team else { fatal("Wrong sync or object for: \(object.safeForLoggingDescription)") }
        return team.remoteIdentifier.map(TeamDownloadRequestFactory.getMembersRequest)
    }

    public func update(_ object: ZMManagedObject!, with response: ZMTransportResponse!, downstreamSync: ZMObjectSync!) {
        guard downstreamSync as? ZMDownstreamObjectSync == self.downstreamSync, let team = object as? Team else { return }
        team.needsToRedownloadMembers = false
        team.updateMembers(with: response)
    }

    public func delete(_ object: ZMManagedObject!, with response: ZMTransportResponse!, downstreamSync: ZMObjectSync!) {
        guard downstreamSync as? ZMDownstreamObjectSync == self.downstreamSync, let team = object as? Team else { return }
        managedObjectContext.delete(team)
    }
}
