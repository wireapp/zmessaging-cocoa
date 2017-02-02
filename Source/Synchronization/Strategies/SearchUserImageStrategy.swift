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


let UsersPath = "/users?ids="
let PictureTagKey = "tag"
let PicturesArrayKey = "picture"
let SmallProfilePictureTag = "smallProfile"
let MediumPictureTag = "medium"

let UserIDKey = "id"
let PictureIDKey = "id"
let PictureInfoKey = "info"


struct SearchUserAssetIDs {
    let smallImageAssetID : UUID?
    let mediumImageAssetID : UUID?

    init?(userImageResponse: [[String: Any]]) {
        var smallAssetID : UUID?
        var mediumAssetID : UUID?
        
        for pictureData in userImageResponse {
            guard let info = (pictureData[PictureInfoKey] as? [String : Any]),
                  let tag = info[PictureTagKey] as? String,
                  let uuidString = pictureData[PictureIDKey] as? String,
                  let uuid = UUID(uuidString: uuidString)
            else { continue }
            
            if tag == SmallProfilePictureTag {
                smallAssetID = uuid
            } else if tag == MediumPictureTag {
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


public class SearchUserImageStrategy : NSObject, ZMRequestGenerator {

    fileprivate unowned var uiContext : NSManagedObjectContext
    fileprivate unowned var syncContext : NSManagedObjectContext
    fileprivate unowned var clientRegistrationDelegate : ClientRegistrationDelegate
    let imagesByUserIDCache : NSCache<NSUUID, NSData>
    let mediumAssetIDByUserIDCache : NSCache<NSUUID, NSUUID>
    let userIDsTable : ZMUserIDsForSearchDirectoryTable
    fileprivate var userIDsBeingRequested = Set<UUID>()
    fileprivate var assetIDsBeingRequested = Set<ZMSearchUserAndAssetID>()
    
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
         userIDsTable: ZMUserIDsForSearchDirectoryTable?)
    {
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
        let assetIDsToDownload = userIDsTable.allAssetIDs.subtracting(assetIDsBeingRequested)
        guard let userAssetID = assetIDsToDownload.first
        else { return nil }
        assetIDsBeingRequested.insert(userAssetID)
        
        let request = UserImageStrategy.requestForFetchingAsset(with:userAssetID.assetID, forUserWith:userAssetID.userID)
        request?.add(ZMCompletionHandler(on:syncContext){ [weak self] (response) in
            self?.processAsset(response: response, for: userAssetID)
        })
        return request
    }
    
    func processAsset(response: ZMTransportResponse, for userAssetID:ZMSearchUserAndAssetID) {
        assetIDsBeingRequested.remove(userAssetID)
        if response.result == .success {
            if let imageData = response.imageData {
                imagesByUserIDCache.setObject(imageData as NSData, forKey: userAssetID.userID as NSUUID)
            }
            uiContext.performGroupedBlock {
                userAssetID.searchUser.notifyNewSmallImageData(response.imageData, searchUserObserverCenter: self.uiContext.searchUserObserverCenter)
            }
            userIDsTable.removeAllEntries(withUserIDs: Set(arrayLiteral: userAssetID.userID))
        }
        else if (response.result == .permanentError) {
            userIDsTable.removeAllEntries(withUserIDs: Set(arrayLiteral: userAssetID.userID))
        }
    }
    
    func fetchUsersRequest() -> ZMTransportRequest? {
        let userIDsToDownload = userIDsTable.allUserIDs.subtracting(userIDsBeingRequested)
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
        let request = ZMTransportRequest(getFromPath: UsersPath+usersList)
        request.add(completionHandler)
        return request;
    }

    func processUserProfile(response: ZMTransportResponse, for userIDs: Set<UUID>){
        userIDsBeingRequested.subtract(userIDs)
        if response.result == .success {
            guard let userList = response.payload as? [[String : Any]] else { return }
            for userData in userList {
                guard let userIdString = userData[UserIDKey] as? String,
                      let userId = UUID(uuidString: userIdString),
                      let pictures = userData[PicturesArrayKey] as? [[String : Any]]
                else { continue }
                
                let assetIds = SearchUserAssetIDs(userImageResponse: pictures)
                if let smallImageAssetID = assetIds?.smallImageAssetID {
                    userIDsTable.replaceUserID(toDownload: userId, withAssetIDToDownload: smallImageAssetID)
                } else {
                    userIDsTable.removeAllEntries(withUserIDs: Set(arrayLiteral:userId))
                }
                if let mediumImageAssetID = assetIds?.mediumImageAssetID {
                    mediumAssetIDByUserIDCache.setObject(mediumImageAssetID as NSUUID, forKey: userId as NSUUID)
                }
            }
        }
        else if (response.result == .permanentError) {
            userIDsTable.removeAllEntries(withUserIDs: userIDs)
        }
    }
    
    
    public static func processSingleUserProfile(response: ZMTransportResponse,
                                  for userID: UUID,
                                  mediumAssetIDCache: NSCache<NSUUID, NSUUID>)
    {
        guard response.result == .success else { return }
        
        guard let userList = response.payload as? [[String : Any]] else { return }
        for userData in userList {
            guard let userIdString = userData[UserIDKey] as? String,
                let receivedUserID = UUID(uuidString: userIdString), receivedUserID == userID,
                let pictures = userData[PicturesArrayKey] as? [[String : Any]],
                let assetIds = SearchUserAssetIDs(userImageResponse: pictures)
                else { continue }
            
            if let mediumImageAssetID = assetIds.mediumImageAssetID {
                mediumAssetIDCache.setObject(mediumImageAssetID as NSUUID, forKey: receivedUserID as NSUUID)
            }
        }
    }
}
