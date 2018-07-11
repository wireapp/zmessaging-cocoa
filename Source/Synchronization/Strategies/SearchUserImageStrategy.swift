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


fileprivate let userPath = "/users?ids="


fileprivate enum ResponseKey: String {
    case pictureTag = "tag"
    case pictures = "picture"
    case id
    case pictureInfo = "info"
    case assets
    case assetSize = "size"
    case assetKey = "key"
    case assetType = "type"
}


fileprivate enum ImageTag: String {
    case smallProfile
    case medium
}

fileprivate enum AssetSize: String {
    case preview
    case complete
}

fileprivate enum AssetType: String {
    case image
}


/// Either we have assetKeys (Strings) or old style legacy UUIDs.
enum SearchUserAssetKeys {
    case asset(preview: String?, complete: String?)
    case legacy(small: UUID?, medium: UUID?)

    init?(payload: [String: Any]) {
        // V3
        if let assetsPayload = payload[ResponseKey.assets.rawValue] as? [[String : Any]], assetsPayload.count > 0 {
            var smallKey: String?, completeKey: String?


            for asset in assetsPayload {
                guard let size = (asset[ResponseKey.assetSize.rawValue] as? String).flatMap(AssetSize.init),
                    let key = asset[ResponseKey.assetKey.rawValue] as? String,
                    let type = (asset[ResponseKey.assetType.rawValue] as? String).flatMap(AssetType.init),
                    type == .image else { continue }

                switch size {
                case .preview: smallKey = key
                case .complete: completeKey = key
                }
            }

            if nil != smallKey || nil != completeKey {
                self = .asset(preview: smallKey, complete: completeKey)
                return
            }
        }
        // Legacy
        else if let pictures = payload[ResponseKey.pictures.rawValue] as? [[String : Any]] {
            var smallId: UUID?, mediumId: UUID?

            for pictureData in pictures {
                guard let info = (pictureData[ResponseKey.pictureInfo.rawValue] as? [String : Any]),
                    let tag = (info[ResponseKey.pictureTag.rawValue] as? String).flatMap(ImageTag.init),
                    let uuid = (pictureData[ResponseKey.id.rawValue] as? String).flatMap(UUID.init) else { continue }

                switch tag {
                case .smallProfile: smallId = uuid
                case .medium: mediumId = uuid
                }
            }

            if smallId != nil || mediumId != nil {
                self = .legacy(small: smallId, medium: mediumId)
                return
            }
        }

        return nil
    }

}


public class SearchUserImageStrategy : AbstractRequestStrategy {

    typealias MediumAssetCache = NSCache<NSUUID, SearchUserAssetObjC>

    fileprivate unowned var uiContext: NSManagedObjectContext
    fileprivate unowned var syncContext: NSManagedObjectContext
    let imagesByUserIDCache: NSCache<NSUUID, NSData>
    let mediumAssetCache: MediumAssetCache
    let userIDsTable: SearchDirectoryUserIDTable
    fileprivate var userIDsBeingRequested = Set<UUID>()
    fileprivate var assetIDsBeingRequested = Set<SearchUserAndAsset>()
    
    @available (*, unavailable)
    public override init(withManagedObjectContext moc: NSManagedObjectContext, applicationStatus: ApplicationStatus) {
        fatalError()
    }
    
    public convenience init(applicationStatus: ApplicationStatus, managedObjectContext: NSManagedObjectContext){
        self.init(applicationStatus: applicationStatus,
                  managedObjectContext: managedObjectContext,
                  imagesByUserIDCache: nil,
                  mediumAssetCache: nil,
                  userIDsTable: nil)
    }
    
    internal init(applicationStatus: ApplicationStatus,
                  managedObjectContext: NSManagedObjectContext,
                  imagesByUserIDCache : NSCache<NSUUID, NSData>?,
                  mediumAssetCache: NSCache<NSUUID, SearchUserAssetObjC>?,
                  userIDsTable: SearchDirectoryUserIDTable?) {
        self.syncContext = managedObjectContext
        self.uiContext = managedObjectContext.zm_userInterface
        self.imagesByUserIDCache = imagesByUserIDCache ?? ZMSearchUser.searchUserToSmallProfileImageCache() as! NSCache<NSUUID, NSData>
        self.mediumAssetCache = mediumAssetCache ?? ZMSearchUser.searchUserToMediumAssetIDCache() as! MediumAssetCache
        self.userIDsTable = userIDsTable ?? SearchDirectory.userIDsMissingProfileImage
        super.init(withManagedObjectContext: managedObjectContext, applicationStatus: applicationStatus)
    }
    
    public override func nextRequestIfAllowed() -> ZMTransportRequest? {
        let request = fetchUsersRequest() ?? fetchAssetRequest()
        request?.setDebugInformationTranscoder(self)
        return request
    }
    
    func fetchAssetRequest() -> ZMTransportRequest? {
        let assetsToDownload = userIDsTable.allUsersWithAssets().subtracting(assetIDsBeingRequested)
        guard let userAssetID = assetsToDownload.first else { return nil }
        assetIDsBeingRequested.insert(userAssetID)

        switch userAssetID.asset {
        case .legacyId(let id):
            let request = UserImageStrategy.requestForFetchingAsset(with: id, forUserWith: userAssetID.userId)
            request?.add(ZMCompletionHandler(on: syncContext) { [weak self] response in
                self?.processAsset(response: response, for: userAssetID)
            })
            return request
        case .assetKey(let key):
            let request = UserImageStrategy.requestForFetchingV3Asset(with: key)
            request.add(ZMCompletionHandler(on: syncContext) { [weak self] response in
                self?.processAsset(response: response, for: userAssetID)
            })
            return request
        case .none: return nil
        }
    }
    
    func processAsset(response: ZMTransportResponse, for userAssetID: SearchUserAndAsset) {
        assetIDsBeingRequested.remove(userAssetID)
        if response.result == .success {
            if let imageData = response.imageData ?? response.rawData {
                imagesByUserIDCache.setObject(imageData as NSData, forKey: userAssetID.userId as NSUUID)
                uiContext.performGroupedBlock {
                    userAssetID.user.notifyNewSmallImageData(imageData, searchUserObserverCenter: self.uiContext.searchUserObserverCenter)
                }
                userIDsTable.removeAllEntries(with: [userAssetID.userId])
            }
        }
        else if response.result == .permanentError {
            userIDsTable.removeAllEntries(with: [userAssetID.userId])
        }
    }
    
    func fetchUsersRequest() -> ZMTransportRequest? {
        let userIDsToDownload = userIDsTable.allUserIds().subtracting(userIDsBeingRequested)
        guard userIDsToDownload.count > 0 else { return nil }
        
        userIDsBeingRequested.formUnion(userIDsToDownload)
        
        let completionHandler = ZMCompletionHandler(on: managedObjectContext) { [weak self] response in
            self?.processUserProfile(response:response, for:userIDsToDownload)
        }

        return SearchUserImageStrategy.requestForFetchingAssets(for:userIDsToDownload, completionHandler:completionHandler)
    }
    
    public static func requestForFetchingAssets(for usersWithIDs: Set<UUID>, completionHandler:ZMCompletionHandler) -> ZMTransportRequest {
        let usersList = usersWithIDs.map{$0.transportString()}.joined(separator: ",")
        let request = ZMTransportRequest(getFromPath: userPath + usersList)
        request.add(completionHandler)
        return request;
    }

    func processUserProfile(response: ZMTransportResponse, for userIDs: Set<UUID>){
        userIDsBeingRequested.subtract(userIDs)

        if response.result == .success {
            guard let userList = response.payload as? [[String : Any]] else { return }

            for userData in userList {
                guard let userId = (userData[ResponseKey.id.rawValue] as? String).flatMap(UUID.init) else { continue }
                if let assetKeys = SearchUserAssetKeys(payload: userData) {
                    switch assetKeys {
                    case .asset(preview: let preview, complete: let complete):
                        if let preview = preview {
                            userIDsTable.replaceUserId(userId, withAsset: .assetKey(preview))
                        } else {
                            userIDsTable.removeAllEntries(with: [userId])
                        }
                        if let complete = complete {
                            mediumAssetCache.setObject(SearchUserAssetObjC(assetKey: complete), forKey: userId as NSUUID)
                        }
                    case .legacy(small: let small, medium: let medium):
                        if let small = small {
                            userIDsTable.replaceUserId(userId, withAsset: .legacyId(small))
                        } else {
                            userIDsTable.removeAllEntries(with: [userId])
                        }
                        if let medium = medium {
                            mediumAssetCache.setObject(SearchUserAssetObjC(legacyId: medium), forKey: userId as NSUUID)
                        }
                    }
                } else {
                    userIDsTable.removeAllEntries(with: [userId])
                }
            }
        }
        else if (response.result == .permanentError) {
            userIDsTable.removeAllEntries(with: userIDs)
        }
    }

    public static func processSingleUserProfile(response: ZMTransportResponse,
                                  for userID: UUID,
                                  mediumAssetIDCache: NSCache<NSUUID, SearchUserAssetObjC>) {
        guard response.result == .success else { return }
        guard let userList = response.payload as? [[String : Any]] else { return }

        for userData in userList {
            processSingleUser(payload: userData, for: userID, cache: mediumAssetIDCache)
        }
    }

    private static func processSingleUser(payload: [String: Any], for userId: UUID, cache: MediumAssetCache) {
        guard let receivedId = (payload[ResponseKey.id.rawValue] as? String).flatMap(UUID.init), receivedId == userId else { return }
        guard let asset = mediumAsset(from: payload).objcCompatibilityValue() else { return }
        cache.setObject(asset, forKey: userId as NSUUID)
    }

    private static func mediumAsset(from payload: [String: Any]) -> SearchUserAsset {
        guard let asset = SearchUserAssetKeys(payload: payload) else { return nil }
        switch asset {
        case .asset(preview: _, complete: let complete):
            if let complete = complete {
                return .assetKey(complete)
            }
        case .legacy(small: _, medium: let medium):
            if let medium = medium {
                return .legacyId(medium)
            }
        }

        return nil
    }
}
