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

public final class UserImageAssetUploadStrategy: NSObject {
    fileprivate let requestFactory = AssetRequestFactory()
    fileprivate var requestSyncs = [ProfileImageSize : ZMSingleRequestSync]()
    fileprivate let moc: NSManagedObjectContext
    fileprivate weak var imageUpdateStatus: UserProfileImageUploadStatusProtocol?

    init(managedObjectContext: NSManagedObjectContext, imageUpdateStatus: UserProfileImageUploadStatusProtocol) {
        self.moc = managedObjectContext
        self.imageUpdateStatus = imageUpdateStatus
        super.init()
    }
    
    fileprivate func requestSync(for size: ProfileImageSize) -> ZMSingleRequestSync {
        if let sync = requestSyncs[size] {
            return sync
        } else {
            let sync = ZMSingleRequestSync(singleRequestTranscoder: self, managedObjectContext: moc)!
            requestSyncs[size] = sync
            return sync
        }
    }
    
    fileprivate func size(for requestSync: ZMSingleRequestSync) -> ProfileImageSize? {
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
        guard let updateStatus = imageUpdateStatus else { return nil }
        
        let sync = updateStatus.allSizes.filter(updateStatus.hasImageToUpload).map(requestSync).first
        sync?.readyForNextRequestIfNotBusy()
        return sync?.nextRequest()
    }
}

extension UserImageAssetUploadStrategy: ZMSingleRequestTranscoder {
    public func request(for sync: ZMSingleRequestSync!) -> ZMTransportRequest! {
        if let size = size(for: sync), let image = imageUpdateStatus?.consumeImage(for: size) {
            return requestFactory.upstreamRequestForAsset(withData: image, shareable: true, retention: .eternal)
        }
        return nil
    }
    
    public func didReceive(_ response: ZMTransportResponse!, forSingleRequest sync: ZMSingleRequestSync!) {
    }
}
