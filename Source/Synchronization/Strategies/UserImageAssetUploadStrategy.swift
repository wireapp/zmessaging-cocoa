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
    fileprivate var previewImageSync: ZMSingleRequestSync!
    fileprivate var completeImageSync: ZMSingleRequestSync!
    fileprivate weak var imageUpdateStatus: UserProfileImageUpdateStatus?
    

    init(managedObjectContext: NSManagedObjectContext, imageUpdateStatus: UserProfileImageUpdateStatus) {
        super.init()
        previewImageSync = ZMSingleRequestSync(singleRequestTranscoder: self, managedObjectContext: managedObjectContext)
        completeImageSync = ZMSingleRequestSync(singleRequestTranscoder: self, managedObjectContext: managedObjectContext)
        self.imageUpdateStatus = imageUpdateStatus
    }
}

extension UserImageAssetUploadStrategy: RequestStrategy {
    public func nextRequest() -> ZMTransportRequest? {
        if let _ = imageUpdateStatus?.hasImageToUpload(for: .preview) {
            previewImageSync.readyForNextRequestIfNotBusy()
            return previewImageSync.nextRequest()
        } else if let _ = imageUpdateStatus?.hasImageToUpload(for: .complete) {
            completeImageSync.readyForNextRequestIfNotBusy()
            return completeImageSync.nextRequest()
        }
        return nil
    }
}

extension UserImageAssetUploadStrategy: ZMSingleRequestTranscoder {
    public func request(for sync: ZMSingleRequestSync!) -> ZMTransportRequest! {
        let imageSize: ImageSize = (sync === previewImageSync) ? .preview : .complete
        guard let image = imageUpdateStatus?.consumeImage(for: imageSize),
            let request = requestFactory.upstreamRequestForAsset(withData: image, shareable: true, retention: .eternal) else {
                return nil
        }
        return request
    }
    
    public func didReceive(_ response: ZMTransportResponse!, forSingleRequest sync: ZMSingleRequestSync!) {
        
    }
}
