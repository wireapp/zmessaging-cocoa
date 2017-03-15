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
    internal var requestSyncs = [ProfileImageSize : ZMSingleRequestSync]()
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
    }
    
    internal func requestSync(for size: ProfileImageSize) -> ZMSingleRequestSync {
        if let sync = requestSyncs[size] {
            return sync
        } else {
            let sync = ZMSingleRequestSync(singleRequestTranscoder: self, managedObjectContext: moc)!
            requestSyncs[size] = sync
            return sync
        }
    }
    
    internal func size(for requestSync: ZMSingleRequestSync) -> ProfileImageSize? {
        for (size, sync) in requestSyncs {
            if sync === requestSync {
                return size
            }
        }
        return nil
    }
    
}

extension UserImageAssetUploadStrategy: RequestStrategy {
    public func nextRequest() -> ZMTransportRequest? {
        guard case .authenticated = authenticationStatus.currentPhase else { return nil }
        guard let updateStatus = imageUploadStatus else { return nil }
        
        let sync = updateStatus.allSizes.filter(updateStatus.hasImageToUpload).map(requestSync).first
        sync?.readyForNextRequestIfNotBusy()
        return sync?.nextRequest()
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
