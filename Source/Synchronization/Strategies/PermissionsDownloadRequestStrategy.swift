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

fileprivate extension Member {

    static let predicateForObjectsNeedingToBeUpdated = NSPredicate(format: "%K == YES", #keyPath(Member.needsToBeUpdatedFromBackend))

}


public final class PermissionsDownloadRequestStrategy: AbstractRequestStrategy, ZMContextChangeTrackerSource, ZMRequestGeneratorSource {

    fileprivate var sync: ZMDownstreamObjectSync!

    public override init(withManagedObjectContext managedObjectContext: NSManagedObjectContext, applicationStatus: ApplicationStatus) {
        super.init(withManagedObjectContext: managedObjectContext, applicationStatus: applicationStatus)
        configuration = .allowsRequestsDuringEventProcessing
        sync = ZMDownstreamObjectSync(
            transcoder: self,
            entityName: Member.entityName(),
            predicateForObjectsToDownload: Member.predicateForObjectsNeedingToBeUpdated,
            filter: nil,
            managedObjectContext: managedObjectContext
        )
    }

    public override func nextRequestIfAllowed() -> ZMTransportRequest? {
        return sync.nextRequest()
    }

    public var contextChangeTrackers: [ZMContextChangeTracker] {
        return [sync]
    }

    public var requestGenerators: [ZMRequestGenerator] {
        return [sync]
    }

}


extension PermissionsDownloadRequestStrategy: ZMDownstreamTranscoder {

    public func request(forFetching object: ZMManagedObject!, downstreamSync: ZMObjectSync!) -> ZMTransportRequest! {
        guard let member = object as? Member, downstreamSync as? ZMDownstreamObjectSync == sync else { fatal("Wrong object: \(object.safeForLoggingDescription)") }
        guard let identifier = member.remoteIdentifier, let teamId = member.team?.remoteIdentifier else { fatal("No ids to sync: \(object.safeForLoggingDescription)") }
        return TeamDownloadRequestFactory.getSingleMemberRequest(for: identifier, in: teamId)
    }

    public func update(_ object: ZMManagedObject!, with response: ZMTransportResponse!, downstreamSync: ZMObjectSync!) {
        guard downstreamSync as? ZMDownstreamObjectSync == sync, let member = object as? Member else { return }
        member.needsToBeUpdatedFromBackend = false
        guard let payload = response.payload as? [String: Any] else { return }
        member.updatePermissions(with: payload)
    }

    public func delete(_ object: ZMManagedObject!, with response: ZMTransportResponse!, downstreamSync: ZMObjectSync!) {
        guard downstreamSync as? ZMDownstreamObjectSync == sync, let member = object as? Member else { return }
        managedObjectContext.delete(member)
    }
}
