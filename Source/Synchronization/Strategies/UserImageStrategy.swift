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

import WireDataModel

let ImageMediumDataKey = "imageMediumData"
let ImageSmallProfileDataKey = "imageSmallProfileData"
let ImageOrigionalProfileDataKey = "originalProfileImageData"
let MediumRemoteIdentifierDataKey = "mediumRemoteIdentifier_data"
let SmallProfileRemoteIdentifierDataKey = "smallProfileRemoteIdentifier_data"
let RequestUserProfileAssetNotificationName = Notification.Name(rawValue: "ZMRequestUserProfileAssetNotification")
let RequestUserProfileSmallAssetNotificationName = Notification.Name(rawValue: "ZMRequestUserProfileSmallAssetNotificationName")

public class UserImageStrategy : AbstractRequestStrategy, ZMDownstreamTranscoder {
    
    var smallProfileDownstreamSync: ZMDownstreamObjectSyncWithWhitelist!
    var mediumDownstreamSync: ZMDownstreamObjectSyncWithWhitelist!
    var observers: [Any] = []
    
    override public init(withManagedObjectContext managedObjectContext: NSManagedObjectContext, applicationStatus: ApplicationStatus) {
        super.init(withManagedObjectContext: managedObjectContext, applicationStatus: applicationStatus)
        
        // Small profiles
        let filterForSmallImage = NSCompoundPredicate(andPredicateWithSubpredicates:[ ZMUser.predicateForSmallImageNeedingToBeUpdatedFromBackend(),
                                                                                      ZMUser.predicateForSmallImageDownloadFilter() ])
        self.smallProfileDownstreamSync = ZMDownstreamObjectSyncWithWhitelist(transcoder:self,
                                                                              entityName:ZMUser.entityName(),
                                                                              predicateForObjectsToDownload:filterForSmallImage,
                                                                              managedObjectContext:managedObjectContext)
        
        // Medium profile
        let filterForMediumImage = NSCompoundPredicate(andPredicateWithSubpredicates:[ZMUser.predicateForMediumImageNeedingToBeUpdatedFromBackend(),
                                                                                      ZMUser.predicateForMediumImageDownloadFilter() ])
        self.mediumDownstreamSync = ZMDownstreamObjectSyncWithWhitelist(transcoder:self,
                                                                        entityName:ZMUser.entityName(),
                                                                        predicateForObjectsToDownload:filterForMediumImage,
                                                                        managedObjectContext:managedObjectContext)
        
        self.mediumDownstreamSync.whiteListObject(ZMUser.selfUser(in: managedObjectContext))
        self.smallProfileDownstreamSync.whiteListObject(ZMUser.selfUser(in: managedObjectContext))
        
        observers.append(NotificationInContext.addObserver(
            name: RequestUserProfileAssetNotificationName,
            context: managedObjectContext.notificationContext,
            using: { [weak self] in self?.requestAssetForNotification(note: $0) })
        )
        observers.append(NotificationInContext.addObserver(
            name: RequestUserProfileSmallAssetNotificationName,
            context: managedObjectContext.notificationContext,
            using: { [weak self] in self?.requestAssetForNotification(note: $0) })
        )
    }

    public override func nextRequestIfAllowed() -> ZMTransportRequest? {
        for sync in [self.smallProfileDownstreamSync, self.mediumDownstreamSync] as [ZMRequestGenerator] {
            if let request = sync.nextRequest() {
                return request
            }
        }
        return nil
    }
    
    func requestAssetForNotification(note: NotificationInContext) {
        managedObjectContext.performGroupedBlock {
            guard let objectID = note.object as? NSManagedObjectID,
                  let object = self.managedObjectContext.object(with: objectID) as? ZMManagedObject
            else { return }
            
            switch note.name {
            case RequestUserProfileAssetNotificationName:
                self.mediumDownstreamSync.whiteListObject(object)
            case RequestUserProfileSmallAssetNotificationName:
                self.smallProfileDownstreamSync.whiteListObject(object)
            default:
                break
            }
        }
    }
    
    // MARK - Downloading
    public func request(forFetching object: ZMManagedObject!, downstreamSync: ZMObjectSync!) -> ZMTransportRequest! {
        guard let downstreamSync = downstreamSync as? ZMDownstreamObjectSyncWithWhitelist,
              let user = object as? ZMUser,
              let userID = user.remoteIdentifier
        else { return nil }
        
        let remoteID: UUID?
        if downstreamSync == self.mediumDownstreamSync {
            if user.keysThatHaveLocalModifications.contains(MediumRemoteIdentifierDataKey) {
                return nil
            }
            remoteID = user.mediumRemoteIdentifier;
        }
        else if (downstreamSync == self.smallProfileDownstreamSync) {
            if user.keysThatHaveLocalModifications.contains(SmallProfileRemoteIdentifierDataKey) {
                return nil;
            }
            remoteID = user.smallProfileRemoteIdentifier;
        }
        else {
            preconditionFailure("Invalid downstream sync")
        }
        
        
        assert(remoteID != nil, "Should not receive users with <nil> mediumRemoteIdentifier")
        let path = type(of:self).path(for:remoteID!, ofUserWith:userID)
        let request = ZMTransportRequest.imageGet(fromPath: path)
        
        let values: [String]
        if downstreamSync == self.mediumDownstreamSync {
            values = [
                user.isSelfUser ? "self: true" : "self: false",
                "mediumRemoteIdentifier : \(String(describing: user.mediumRemoteIdentifier))",
                "completeProfileAssetIdentifier : \(String(describing: user.completeProfileAssetIdentifier))",
                "localMediumRemoteIdentifier : \(String(describing: user.localMediumRemoteIdentifier))",
                "imageMediumData : \(String(describing: user.imageMediumData))"
            ]
        } else {
            values = [
                user.isSelfUser ? "self: true" : "self: false",
                "smallProfileRemoteIdentifier : \(String(describing: user.smallProfileRemoteIdentifier))",
                "previewProfileAssetIdentifier : \(String(describing: user.previewProfileAssetIdentifier))",
                "localSmallProfileRemoteIdentifier : \(String(describing: user.localSmallProfileRemoteIdentifier))",
                "imageSmallProfileData : \(String(describing: user.imageSmallProfileData))"
            ]
        }
        
        request.addContentDebugInformation("Predicate values: [\(values.joined(separator: ", "))]")
        return request
    }
    
    static func path(for assetID: UUID, ofUserWith userID: UUID) -> String {
        let last = assetID.transportString()+"?conv_id="+userID.transportString()
        return "/assets/\(last)"
    }
    
    public func delete(_ object: ZMManagedObject!, with response: ZMTransportResponse!, downstreamSync: ZMObjectSync!) {
        guard let user = object as? ZMUser else { return }

        switch downstreamSync as? ZMDownstreamObjectSyncWithWhitelist {
        case smallProfileDownstreamSync?:
            user.localSmallProfileRemoteIdentifier = nil
            user.smallProfileRemoteIdentifier = nil
            user.imageSmallProfileData = nil
        case mediumDownstreamSync?:
            user.localMediumRemoteIdentifier = nil
            user.mediumRemoteIdentifier = nil
            user.imageMediumData = nil
        default:
            preconditionFailure("Invalid downstream sync")
        }
    }
    
    public func update(_ object: ZMManagedObject!, with response: ZMTransportResponse!, downstreamSync: ZMObjectSync!) {
        guard let downstreamSync = downstreamSync as? ZMDownstreamObjectSyncWithWhitelist,
              let user = object as? ZMUser
        else { return }
        
        if (downstreamSync == self.smallProfileDownstreamSync) {
            user.localSmallProfileRemoteIdentifier = user.smallProfileRemoteIdentifier
            user.imageSmallProfileData = response.imageData
        }
        else if (downstreamSync == self.mediumDownstreamSync) {
            user.localMediumRemoteIdentifier = user.mediumRemoteIdentifier
            user.imageMediumData = response.imageData
        }
        else {
            preconditionFailure("Invalid downstream sync")
        }
    }
}

extension UserImageStrategy : ZMContextChangeTrackerSource {

    public var contextChangeTrackers: [ZMContextChangeTracker] {
        return [self.smallProfileDownstreamSync, self.mediumDownstreamSync]
    }
    
}


// MARK - SearchUser
extension UserImageStrategy {

    public static func requestForFetchingAsset(with assetID: UUID, forUserWith userID: UUID) -> ZMTransportRequest? {
        let path = self.path(for: assetID, ofUserWith: userID)
        return ZMTransportRequest(path:path, method:.methodGET, payload:nil)
    }

    public static func requestForFetchingV3Asset(with key: String) -> ZMTransportRequest {
        return ZMTransportRequest(getFromPath: "/assets/v3/\(key)")
    }
}

extension UserImageStrategy {
    
    public static func requestAsset(for user: ZMUser) {
        NotificationInContext(name: RequestUserProfileAssetNotificationName,
                              context: user.managedObjectContext!.notificationContext,
                              object: user.objectID).post()
    }
    
    public static func requestSmallAsset(for user: ZMUser) {
        NotificationInContext(name: RequestUserProfileSmallAssetNotificationName,
                              context: user.managedObjectContext!.notificationContext,
                              object: user.objectID).post()
    }
}


