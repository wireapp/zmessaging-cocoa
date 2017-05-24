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
let RequestUserProfileAssetNotificationName = "ZMRequestUserProfileAssetNotification"
let RequestUserProfileSmallAssetNotificationName = "ZMRequestUserProfileSmallAssetNotificationName"


class ImageRequestFactory : ImageRequestSource {
    static public func request(for imageOwner: ZMImageOwner, format: ZMImageFormat, conversationID: UUID, correlationID: UUID, resultHandler: ZMCompletionHandler?) -> ZMTransportRequest? {
        guard let imageData = imageOwner.imageData(for:format)
        else {
            fatal("Imageowner does not have image data for ZMImageFormat rawValue \(format.rawValue)")
        }
        
        let disposition = contentDisposition(for: imageOwner, format: format, conversationID: conversationID, correlationID: correlationID)
        let request = ZMTransportRequest.post(withPath: "/assets", imageData: imageData, contentDisposition: disposition)
        if let completionHandler = resultHandler {
            request?.add(completionHandler)
        }
        return request
    }
    
    static func contentDisposition(for imageOwner: ZMImageOwner, format: ZMImageFormat, conversationID: UUID, correlationID: UUID) -> [AnyHashable : Any] {
        return ZMAssetMetaDataEncoder.contentDisposition(for: imageOwner,
                                                         format: format,
                                                         conversationID: conversationID,
                                                         correlationID: correlationID)
    }
}

@objc public protocol ImageRequestSource {
    static func request(for imageOwner: ZMImageOwner, format: ZMImageFormat, conversationID: UUID, correlationID: UUID, resultHandler: ZMCompletionHandler?) -> ZMTransportRequest?
}


public class UserImageStrategy : AbstractRequestStrategy, ZMDownstreamTranscoder, ZMUpstreamTranscoder {
    
    var requestFactory : ImageRequestSource
    var smallProfileDownstreamSync: ZMDownstreamObjectSyncWithWhitelist!
    var mediumDownstreamSync: ZMDownstreamObjectSyncWithWhitelist!
    var upstreamSync: ZMUpstreamModifiedObjectSync!
    var assetPreprocessingTracker: ZMImagePreprocessingTracker!
    let imageProcessingQueue: OperationQueue
    var tornDown :Bool = false
    
    @available (*, unavailable)
    override init(withManagedObjectContext moc: NSManagedObjectContext, applicationStatus: ApplicationStatus) {
        fatalError()
    }
    
    @objc public convenience init(managedObjectContext:NSManagedObjectContext, applicationStatus: ApplicationStatus, imageProcessingQueue: OperationQueue) {
        self.init(managedObjectContext: managedObjectContext, applicationStatus: applicationStatus, imageProcessingQueue: imageProcessingQueue, requestFactory: nil)
    }
    
    init(managedObjectContext:NSManagedObjectContext, applicationStatus: ApplicationStatus, imageProcessingQueue: OperationQueue, requestFactory : ImageRequestSource?) {
        self.imageProcessingQueue = imageProcessingQueue;
        self.requestFactory = requestFactory ?? ImageRequestFactory()
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
        
        // Self user upstream
        let filter = NSPredicate(format: "imageCorrelationIdentifier != nil")
        self.upstreamSync = ZMUpstreamModifiedObjectSync(transcoder:self,
                                                entityName:ZMUser.entityName(),
                                                update:nil,
                                                filter:filter,
                                                keysToSync:[ImageSmallProfileDataKey, ImageMediumDataKey],
                                                managedObjectContext:managedObjectContext)
        
        // asset PreprocessingTracker
        let attributePredicate = NSPredicate(format:"%K != NIL", ImageOrigionalProfileDataKey)
        self.assetPreprocessingTracker = ZMImagePreprocessingTracker(managedObjectContext:self.managedObjectContext,
                                                                     imageProcessingQueue:self.imageProcessingQueue,
                                                                     fetch:attributePredicate,
                                                                     needsProcessingPredicate:attributePredicate,
                                                                     entityClass:ZMUser.self)
        NotificationCenter.default.addObserver(self, selector: #selector(requestAssetForNotification(note:)), name: Notification.Name(rawValue:RequestUserProfileAssetNotificationName), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(requestAssetForNotification(note:)), name: Notification.Name(rawValue:RequestUserProfileSmallAssetNotificationName), object: nil)
        
        self.recoverFromInconsistentUserImageStatus()
    }
    
    public func tearDown() {
        tornDown = true
        assetPreprocessingTracker.tearDown()
        NotificationCenter.default.removeObserver(self)
    }
    
    deinit {
        assert(tornDown)
    }
    
    func recoverFromInconsistentUserImageStatus() {
        managedObjectContext.performGroupedBlock{
            let selfUser = ZMUser.selfUser(in: self.managedObjectContext)
            let imageMediumKeys = Set(arrayLiteral: ImageMediumDataKey,ImageSmallProfileDataKey)
            let hasLocalModificationsForImageKeys = selfUser.hasLocalModifications(forKeys: imageMediumKeys)
            let hasMissingImageData = selfUser.imageMediumData == nil || selfUser.imageSmallProfileData == nil;
            
            if (hasLocalModificationsForImageKeys && hasMissingImageData) {
                selfUser.resetLocallyModifiedKeys(imageMediumKeys)
            }
            
            self.smallProfileDownstreamSync.whiteListObject(selfUser)
            self.mediumDownstreamSync.whiteListObject(selfUser)
        }
    }
    
    public override func nextRequestIfAllowed() -> ZMTransportRequest? {
        for sync in [self.smallProfileDownstreamSync, self.mediumDownstreamSync, self.upstreamSync] as [ZMRequestGenerator] {
            if let request = sync.nextRequest() {
                return request
            }
        }
        return nil
    }
    
    func requestAssetForNotification(note: Notification) {
        managedObjectContext.performGroupedBlock {
            guard let objectID = note.object as? NSManagedObjectID,
                  let object = self.managedObjectContext.object(with: objectID) as? ZMManagedObject
            else { return }
            
            switch note.name.rawValue {
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
    
    public func delete(_ object: ZMManagedObject!, downstreamSync: ZMObjectSync!) {
        // no-op
    }
    
    
    // MARK - Updating
    public func request(forUpdating managedObject: ZMManagedObject, forKeys keys: Set<String>) -> ZMUpstreamRequest? {
        guard let user = managedObject as? ZMUser, user.isSelfUser
        else {
            assertionFailure()
            return nil
        }
        
        if keys.contains(ImageSmallProfileDataKey) || keys.contains(ImageMediumDataKey) {
            return requestForUploadingImageToSelfConversation(selfUser:user, keys:keys)
        }
        
        ZMTrapUnableToGenerateRequest(keys, self);
        return nil;
    }
    
    func requestForUploadingImageToSelfConversation(selfUser: ZMUser, keys: Set<String>) -> ZMUpstreamRequest? {
        guard let correlationID = selfUser.imageCorrelationIdentifier
        else {
            fatal("Image correlation identifier is missing")
        }
        
        let imageFormat : ZMImageFormat
        let updatedKey : String
        if keys.contains(ImageSmallProfileDataKey) {
            updatedKey = ImageSmallProfileDataKey;
            imageFormat = .profile;
        }
        else if keys.contains(ImageMediumDataKey) {
            updatedKey = ImageMediumDataKey;
            imageFormat = .medium;
        } else {
            fatal("Modified keys do not contain medium nor smallProfile data key")
        }
    
        let selfConversationID = ZMConversation.selfConversationIdentifier(in: managedObjectContext)
        guard let request = type(of: requestFactory).request(for: selfUser,
                                                             format: imageFormat,
                                                             conversationID: selfConversationID,
                                                             correlationID: correlationID,
                                                             resultHandler: nil)
        else {
            fatal("Request factory returned nil request.")
        }
        return ZMUpstreamRequest(keys: Set(arrayLiteral:updatedKey), transportRequest:request)
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
    
    public func updateUpdatedObject(_ managedObject: ZMManagedObject, requestUserInfo: [AnyHashable : Any]? = nil, response: ZMTransportResponse, keysToParse: Set<String>) -> Bool {
        guard let payloadData = (response.payload as? [String: Any])?["data"] as? [String : Any],
              let payloadInfo = payloadData["info"] as? [String: Any],
              let receivedImageCorrelationID = (payloadInfo["correlation_id"] as? String)?.uuid(),
              let user = managedObject as? ZMUser, user.imageCorrelationIdentifier == receivedImageCorrelationID,
              let imageID = (payloadData["id"] as? String)?.uuid()
        else { return false }
        
        if keysToParse.contains(ImageSmallProfileDataKey) {
            user.smallProfileRemoteIdentifier = imageID
            user.localSmallProfileRemoteIdentifier = user.smallProfileRemoteIdentifier;
            user.resetLocallyModifiedKeys(Set(arrayLiteral:ImageSmallProfileDataKey))
            
            checkIfBothMediumAndSmallProfileHaveBeenUploaded(for: user)
            return true
        }
        else if keysToParse.contains(ImageMediumDataKey) {
            user.mediumRemoteIdentifier = imageID
            user.localMediumRemoteIdentifier = user.mediumRemoteIdentifier;
            user.resetLocallyModifiedKeys(Set(arrayLiteral:ImageMediumDataKey))
            
            checkIfBothMediumAndSmallProfileHaveBeenUploaded(for: user)
            return true;
        }
        return false;
    }
    
    func checkIfBothMediumAndSmallProfileHaveBeenUploaded(for user: ZMUser) {
        let doneProcessingImage = (user.originalProfileImageData == nil)
        let doneUploading = Set(arrayLiteral: ImageSmallProfileDataKey, ImageMediumDataKey).isDisjoint(with: user.keysThatHaveLocalModifications)
        if (doneProcessingImage && doneUploading) {
            user.setLocallyModifiedKeys(Set(arrayLiteral:SmallProfileRemoteIdentifierDataKey, MediumRemoteIdentifierDataKey))
        }
    }
    
    // MARK - Inserting
    public func request(forInserting managedObject: ZMManagedObject, forKeys keys: Set<String>?) -> ZMUpstreamRequest? {
        assertionFailure("requestForInsertingObject should never be called")
        return nil
    }

    public func updateInsertedObject(_ managedObject: ZMManagedObject, request upstreamRequest: ZMUpstreamRequest, response: ZMTransportResponse) {
        assertionFailure("updateInsertedObject should never be called")
    }

    public func objectToRefetchForFailedUpdate(of managedObject: ZMManagedObject) -> ZMManagedObject? {
        return nil
    }
    
    public func shouldProcessUpdatesBeforeInserts() -> Bool {
        return true
    }
}

extension UserImageStrategy : ZMContextChangeTrackerSource {

    public var contextChangeTrackers: [ZMContextChangeTracker] {
        return [self.assetPreprocessingTracker, self.smallProfileDownstreamSync, self.mediumDownstreamSync, self.upstreamSync]
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
    
    public static func requestAssetForUser(with objectID:NSManagedObjectID) {
        NotificationCenter.default.post(name: Notification.Name(rawValue:RequestUserProfileAssetNotificationName), object: objectID)
    }
    
    public static func requestSmallAssetForUser(with objectID:NSManagedObjectID) {
        NotificationCenter.default.post(name: Notification.Name(rawValue:RequestUserProfileSmallAssetNotificationName), object: objectID)
    }
}


