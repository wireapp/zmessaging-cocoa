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

import Foundation
import WireRequestStrategy

internal enum AssetTransportError: Error {
    case invalidLength
    case assetTooLarge
    case other(Error?)
    
    init(response: ZMTransportResponse) {
        switch (response.httpStatus, response.payloadLabel()) {
        case (400, .some("invalid-length")):
            self = .invalidLength
        case (413, .some("client-error")):
            self = .assetTooLarge
        default:
            self = .other(response.transportSessionError)
        }
    }
}

@objc public final class UserImageAssetUploadStrategy: NSObject {
    internal let requestFactory = AssetRequestFactory()
    internal var upstreamRequestSyncs = [ProfileImageSize : ZMSingleRequestSync]()
    internal var downsteamRequestSyncs = [ProfileImageSize : ZMDownstreamObjectSyncWithWhitelist]()
    internal let moc: NSManagedObjectContext
    internal weak var imageUploadStatus: UserProfileImageUploadStatusProtocol?
    internal let authenticationStatus: AuthenticationStatusProvider
    
    @objc public convenience init(managedObjectContext: NSManagedObjectContext, imageUpdateStatus: UserProfileImageUpdateStatus, authenticationStatus: AuthenticationStatusProvider) {
        self.init(managedObjectContext: managedObjectContext, imageUploadStatus: imageUpdateStatus, authenticationStatus: authenticationStatus)
    }

    internal init(managedObjectContext: NSManagedObjectContext, imageUploadStatus: UserProfileImageUploadStatusProtocol, authenticationStatus: AuthenticationStatusProvider) {
        self.moc = managedObjectContext
        self.imageUploadStatus = imageUploadStatus
        self.authenticationStatus = authenticationStatus
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(requestAssetForNotification(note:)), name: ZMUser.previewAssetFetchNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(requestAssetForNotification(note:)), name: ZMUser.completeAssetFetchNotification, object: nil)
    }
    
    fileprivate func whitelistUserImageSync(for size: ProfileImageSize) -> ZMDownstreamObjectSyncWithWhitelist {
        let predicate: NSPredicate
        switch size {
        case .preview:
            predicate = ZMUser.previewImageDownloadFilter
        case .complete:
            predicate = ZMUser.completeImageDownloadFilter
        }
        
        return ZMDownstreamObjectSyncWithWhitelist(transcoder:self,
                                            entityName:ZMUser.entityName(),
                                            predicateForObjectsToDownload:predicate,
                                            managedObjectContext:moc)
    }
    
    internal func requestSync<T>(inList list: inout [ProfileImageSize : T], for size: ProfileImageSize, create: ((ProfileImageSize) -> T)) -> T {
        if let sync = list[size] {
            return sync
        } else {
            let sync = create(size)
            list[size] = sync
            return sync
        }
    }
    
    internal func downstreamRequestSync(for size: ProfileImageSize) -> ZMDownstreamObjectSyncWithWhitelist {
        return requestSync(inList: &downsteamRequestSyncs, for: size, create: whitelistUserImageSync)
    }
    
    internal func size(for requestSync: ZMDownstreamObjectSyncWithWhitelist) -> ProfileImageSize? {
        for (size, sync) in downsteamRequestSyncs {
            if sync === requestSync {
                return size
            }
        }
        return nil
    }

    internal func upstreamRequestSync(for size: ProfileImageSize) -> ZMSingleRequestSync {
        return requestSync(inList: &upstreamRequestSyncs, for: size) { _ in
            return ZMSingleRequestSync(singleRequestTranscoder: self, managedObjectContext: moc)!
        }
    }

    internal func size(for requestSync: ZMSingleRequestSync) -> ProfileImageSize? {
        for (size, sync) in upstreamRequestSyncs {
            if sync === requestSync {
                return size
            }
        }
        return nil
    }
    
    func requestAssetForNotification(note: Notification) {
        moc.performGroupedBlock {
            guard let objectID = note.object as? NSManagedObjectID,
                let object = self.moc.object(with: objectID) as? ZMManagedObject
                else { return }
            
            switch note.name {
            case ZMUser.previewAssetFetchNotification:
                self.downstreamRequestSync(for: .preview).whiteListObject(object)
            case ZMUser.completeAssetFetchNotification:
                self.downstreamRequestSync(for: .complete).whiteListObject(object)
            default:
                break
            }
        }
    }
    
}

extension UserImageAssetUploadStrategy: RequestStrategy {
    public func nextRequest() -> ZMTransportRequest? {
        guard case .authenticated = authenticationStatus.currentPhase else { return nil }
        
        let requests = ProfileImageSize.allSizes.map(downstreamRequestSync).flatMap { $0.nextRequest() }
        if let request = requests.first {
            return request
        }
        
        guard let updateStatus = imageUploadStatus else { return nil }
        
        let sync = ProfileImageSize.allSizes.filter(updateStatus.hasImageToUpload).map(upstreamRequestSync).first
        sync?.readyForNextRequestIfNotBusy()
        return sync?.nextRequest()
    }
}

extension UserImageAssetUploadStrategy: ZMDownstreamTranscoder {
    public func request(forFetching object: ZMManagedObject!, downstreamSync: ZMObjectSync!) -> ZMTransportRequest! {
        guard let whitelistSync = downstreamSync as? ZMDownstreamObjectSyncWithWhitelist else { return nil }
        guard let user = object as? ZMUser else { return nil }
        guard let size = size(for: whitelistSync) else { return nil }

        let remoteId: String?
        switch size {
        case .preview:
            remoteId = user.previewProfileAssetIdentifier
        case .complete:
            remoteId = user.completeProfileAssetIdentifier
        }
        guard let assetId = remoteId else { return nil }
        let path = "/assets/v3/\(assetId)"
        return ZMTransportRequest.imageGet(fromPath: path)
    }
    
    public func delete(_ object: ZMManagedObject!, downstreamSync: ZMObjectSync!) {}
    
    public func update(_ object: ZMManagedObject!, with response: ZMTransportResponse!, downstreamSync: ZMObjectSync!) {
        guard let whitelistSync = downstreamSync as? ZMDownstreamObjectSyncWithWhitelist else { return }
        guard let user = object as? ZMUser else { return }
        guard let size = size(for: whitelistSync) else { return }
        
        user.setImage(data: response.rawData, size: size)
    }
}

extension UserImageAssetUploadStrategy: ZMContextChangeTrackerSource {
    public var contextChangeTrackers: [ZMContextChangeTracker] {
        return Array(downsteamRequestSyncs.values)
    }
}

extension UserImageAssetUploadStrategy: ZMSingleRequestTranscoder {
    public func request(for sync: ZMSingleRequestSync!) -> ZMTransportRequest! {
        if let size = size(for: sync), let image = imageUploadStatus?.consumeImage(for: size) {
            return requestFactory.upstreamRequestForAsset(withData: image, shareable: true, retention: .eternal)
        }
        return nil
    }
    
    public func didReceive(_ response: ZMTransportResponse!, forSingleRequest sync: ZMSingleRequestSync!) {
        guard let size = size(for: sync) else { return }
        guard response.result == .success else {
            let error = AssetTransportError(response: response)
            imageUploadStatus?.uploadingFailed(imageSize: size, error: error)
            return
        }
        guard let payload = response.payload?.asDictionary(), let assetId = payload["key"] as? String else { fatal("No asset ID present in payload: \(response.payload)") }
        imageUploadStatus?.uploadingDone(imageSize: size, assetId: assetId)
    }
}
