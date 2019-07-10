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
import WireRequestStrategy

//@objc
public final class TeamImageAssetUpdateStrategy: AbstractRequestStrategy {
    let moc: NSManagedObjectContext
    var downstreamRequestSync: ZMDownstreamObjectSyncWithWhitelist!
    fileprivate var observer: Any!

    override init(withManagedObjectContext managedObjectContext: NSManagedObjectContext,
                  applicationStatus: ApplicationStatus) {
        moc = managedObjectContext

        super.init(withManagedObjectContext: managedObjectContext, applicationStatus: applicationStatus)

        downstreamRequestSync = whitelistUserImageSync
        ///TODO: this line causes memory issue?
//        downstreamRequestSync.whiteListObject(ZMUser.selfUser(in: managedObjectContext).team)

        observer = NotificationInContext.addObserver(name: .teamDidRequestAsset, context: managedObjectContext.notificationContext, using: { [weak self] in self?.requestAssetForNotification(note: $0) })
    }

//    deinit {
//        observer = nil
//    }

    private func requestAssetForNotification(note: NotificationInContext) {
        moc.performGroupedBlock {
            guard let objectID = note.object as? NSManagedObjectID,
                let object = self.moc.object(with: objectID) as? ZMManagedObject
                else { return }

            switch note.name {
            case .teamDidRequestAsset:
                self.downstreamRequestSync.whiteListObject(object)
            default:
                break
            }

            RequestAvailableNotification.notifyNewRequestsAvailable(nil)
        }
    }

    fileprivate var whitelistUserImageSync: ZMDownstreamObjectSyncWithWhitelist {
        let predicate: NSPredicate = Team.imageDownloadFilter

        return ZMDownstreamObjectSyncWithWhitelist(transcoder:self,
                                                   entityName:Team.entityName(),
                                                   predicateForObjectsToDownload:predicate,
                                                   managedObjectContext:moc)
    }

}

extension TeamImageAssetUpdateStrategy : ZMDownstreamTranscoder {
    public func request(forFetching object: ZMManagedObject!,
                        downstreamSync: ZMObjectSync!) -> ZMTransportRequest! {
        guard let team = object as? Team else { return nil }

        guard let assetId = team.pictureAssetId else { return nil }
        let path = "/assets/v3/\(assetId)"
        return ZMTransportRequest.imageGet(fromPath: path)
    }

    public func delete(_ object: ZMManagedObject!, with response: ZMTransportResponse!, downstreamSync: ZMObjectSync!) {
        //TODO

    }

    public func update(_ object: ZMManagedObject!, with response: ZMTransportResponse!, downstreamSync: ZMObjectSync!) {
        //TODO

    }

}

extension TeamImageAssetUpdateStrategy: ZMContextChangeTrackerSource {
    public var contextChangeTrackers: [ZMContextChangeTracker] {
        //TODO
        return []
    }

}
