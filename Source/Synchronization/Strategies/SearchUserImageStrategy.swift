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


fileprivate enum SearchUserResponseKey: String {
    case pictureTag = "tag"
    case pictures = "picture"
    case smallProfileTag = "smallProfile"
    case mediumProfileTag = "medium"
    case id = "id"
    case pictureInfo = "info"
    case assets = "assets"
    case assetSize = "size"
    case assetKey = "key"
    case assetType = "type"
}


fileprivate enum AssetType: String {
    case preview = "preview"
    case complete = "complete"
}


struct SearchUserAssetIDs {
    let smallImageAssetID: UUID?
    let mediumImageAssetID: UUID?


    init?(userImageResponse: [[String: Any]]) {
        var smallAssetID : UUID?
        var mediumAssetID : UUID?
        
        for pictureData in userImageResponse {
            guard let info = (pictureData[SearchUserResponseKey.pictureInfo.rawValue] as? [String : Any]),
                let tag = info[SearchUserResponseKey.pictureTag.rawValue] as? String,
                let uuidString = pictureData[SearchUserResponseKey.id.rawValue] as? String,
                let uuid = UUID(uuidString: uuidString)
                else { continue }

            if tag == SearchUserResponseKey.smallProfileTag.rawValue {
                smallAssetID = uuid
            } else if tag == SearchUserResponseKey.mediumProfileTag.rawValue {
                mediumAssetID = uuid
            }
        }
        
        if smallAssetID != nil || mediumAssetID != nil {
            self.init(smallImageAssetID: smallAssetID, mediumImageAssetID: mediumAssetID)
        } else {
            return nil
        }
    }
    
    init(smallImageAssetID: UUID?, mediumImageAssetID: UUID?) {
        self.mediumImageAssetID = mediumImageAssetID
        self.smallImageAssetID = smallImageAssetID
    }
}


struct SearchUserAssetKeys {
    let smallAssetKey: String?
    let completeAssetKey: String?

    init?(response: [[String: Any]]) {
        var smallKey: String?, completeKey: String?

        for assetPayload in response {
            guard let size = (assetPayload[SearchUserResponseKey.assetSize.rawValue] as? String).flatMap(AssetType.init),
                let key = assetPayload[SearchUserResponseKey.assetKey.rawValue] as? String,
                let type = assetPayload[SearchUserResponseKey.assetType.rawValue] as? String,
                type == "image" else { continue }

            switch size {
            case .preview: smallKey = key
            case .complete: completeKey = key
            default: continue
            }
        }

        if nil != smallKey || nil != completeKey {
            self.init(smallKey: smallKey, completeKey: completeKey)
        } else {
            return nil
        }
    }

    init(smallKey: String?, completeKey: String?) {
        smallAssetKey = smallKey
        completeAssetKey = completeKey
    }
}


public class SearchUserImageStrategy : NSObject, ZMRequestGenerator {

    fileprivate unowned var uiContext : NSManagedObjectContext
    fileprivate unowned var syncContext : NSManagedObjectContext
    fileprivate unowned var clientRegistrationDelegate : ClientRegistrationDelegate
    let imagesByUserIDCache : NSCache<NSUUID, NSData>
    let mediumAssetIDByUserIDCache : NSCache<NSUUID, NSUUID>
    let userIDsTable : SearchDirectoryUserIDTable
    fileprivate var userIDsBeingRequested = Set<UUID>()
    fileprivate var assetIDsBeingRequested = Set<SearchUserAndAsset>()
    
    public init(managedObjectContext: NSManagedObjectContext, clientRegistrationDelegate: ClientRegistrationDelegate){
        self.syncContext = managedObjectContext
        self.uiContext = managedObjectContext.zm_userInterface
        self.clientRegistrationDelegate = clientRegistrationDelegate
        self.imagesByUserIDCache = ZMSearchUser.searchUserToSmallProfileImageCache() as! NSCache<NSUUID, NSData>
        self.mediumAssetIDByUserIDCache = ZMSearchUser.searchUserToMediumAssetIDCache() as! NSCache<NSUUID, NSUUID>
        self.userIDsTable = ZMSearchDirectory.userIDsMissingProfileImage()
    }
    
    init(managedObjectContext: NSManagedObjectContext,
         clientRegistrationDelegate: ClientRegistrationDelegate,
         imagesByUserIDCache : NSCache<NSUUID, NSData>?,
         mediumAssetIDByUserIDCache : NSCache<NSUUID, NSUUID>?,
         userIDsTable: SearchDirectoryUserIDTable?) {
        self.syncContext = managedObjectContext
        self.uiContext = managedObjectContext.zm_userInterface
        self.clientRegistrationDelegate = clientRegistrationDelegate
        self.imagesByUserIDCache = imagesByUserIDCache ?? ZMSearchUser.searchUserToSmallProfileImageCache() as! NSCache<NSUUID, NSData>
        self.mediumAssetIDByUserIDCache = mediumAssetIDByUserIDCache ?? ZMSearchUser.searchUserToMediumAssetIDCache() as! NSCache<NSUUID, NSUUID>
        self.userIDsTable = userIDsTable ?? ZMSearchDirectory.userIDsMissingProfileImage()
    }
    
    public func nextRequest() -> ZMTransportRequest? {
        guard clientRegistrationDelegate.clientIsReadyForRequests else { return nil }
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
            if let imageData = response.imageData {
                imagesByUserIDCache.setObject(imageData as NSData, forKey: userAssetID.userId as NSUUID)
            }
            uiContext.performGroupedBlock {
                userAssetID.user.notifyNewSmallImageData(response.imageData, searchUserObserverCenter: self.uiContext.searchUserObserverCenter)
            }
            userIDsTable.removeAllEntries(with: [userAssetID.userId])
        }
        else if (response.result == .permanentError) {
            userIDsTable.removeAllEntries(with: [userAssetID.userId])
        }
    }
    
    func fetchUsersRequest() -> ZMTransportRequest? {
        let userIDsToDownload = userIDsTable.allUserIds().subtracting(userIDsBeingRequested)
        guard userIDsToDownload.count > 0
        else { return nil}
        userIDsBeingRequested.formUnion(userIDsToDownload)
        
        let completionHandler = ZMCompletionHandler(on :syncContext){ [weak self] (response) in
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
                guard let userId = (userData[SearchUserResponseKey.id.rawValue] as? String).flatMap(UUID.init) else { continue }

                // Check if there is a V3 asset first
                if let assetsPayload = userData[SearchUserResponseKey.assets.rawValue] as? [[String : Any]], assetsPayload.count > 0 {
                    let assetKeys = SearchUserAssetKeys(response: assetsPayload)
                    if let smallKey = assetKeys?.smallAssetKey {
                        userIDsTable.replaceUserId(userId, withAsset: .assetKey(smallKey))
                    } else {
                        userIDsTable.removeAllEntries(with: [userId])
                    }
                }
                // V2
                else if let pictures = userData[SearchUserResponseKey.pictures.rawValue] as? [[String : Any]] {
                    let assetIds = SearchUserAssetIDs(userImageResponse: pictures)
                    if let smallImageAssetID = assetIds?.smallImageAssetID {
                        userIDsTable.replaceUserId(userId, withAsset: .legacyId(smallImageAssetID))
                    } else {
                        userIDsTable.removeAllEntries(with: [userId])
                    }
                    if let mediumImageAssetID = assetIds?.mediumImageAssetID {
                        mediumAssetIDByUserIDCache.setObject(mediumImageAssetID as NSUUID, forKey: userId as NSUUID)
                    }
                }
            }
        }
        else if (response.result == .permanentError) {
            userIDsTable.removeAllEntries(with: userIDs)
        }
    }

    public static func processSingleUserProfile(response: ZMTransportResponse,
                                  for userID: UUID,
                                  mediumAssetIDCache: NSCache<NSUUID, NSUUID>) {
        guard response.result == .success else { return }
        
        guard let userList = response.payload as? [[String : Any]] else { return }
        for userData in userList {
            guard let userIdString = userData[SearchUserResponseKey.id.rawValue] as? String,
                let receivedUserID = UUID(uuidString: userIdString), receivedUserID == userID,
                let pictures = userData[SearchUserResponseKey.pictures.rawValue] as? [[String : Any]],
                let assetIds = SearchUserAssetIDs(userImageResponse: pictures)
                else { continue }
            
            if let mediumImageAssetID = assetIds.mediumImageAssetID {
                mediumAssetIDCache.setObject(mediumImageAssetID as NSUUID, forKey: receivedUserID as NSUUID)
            }
        }
    }
}
