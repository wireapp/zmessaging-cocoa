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


import Foundation


private let reponseHeaderAssetIdKey = "Location"

@objc public class FileUploadRequestStrategyNotification: NSObject {
    public static let uploadFinishedNotificationName = "FileUploadRequestStrategyUploadFinishedNotificationName"
    public static let requestStartTimestampKey = "requestStartTimestamp"
    public static let uploadFailedNotificationName = "FileUploadRequestStrategyUploadFailedNotificationName"
}


@objc public class FileUploadRequestStrategy : ZMObjectSyncStrategy, RequestStrategy, ZMUpstreamTranscoder, ZMContextChangeTrackerSource {
    
    /// Auth status to know whether we can make requests
    private let authenticationStatus : AuthenticationStatusProvider
    
    /// Client status to know whether we can make requests and to delete client
    private var clientRegistrationStatus : ZMClientClientRegistrationStatusProvider
    
    /// Upstream sync
    private var fullFileUpstreamSync : ZMUpstreamModifiedObjectSync!
    
    /// Preprocessor
    private var thumbnailPreprocessorTracker : ZMImagePreprocessingTracker
    private var filePreprocessor : FilePreprocessor
    
    private var requestFactory : ClientMessageRequestFactory
    
    // task cancellation provider
    private weak var taskCancellationProvider: ZMRequestCancellation?
    
    
    public init(authenticationStatus: AuthenticationStatusProvider,
        clientRegistrationStatus : ZMClientClientRegistrationStatusProvider,
        managedObjectContext: NSManagedObjectContext,
        taskCancellationProvider: ZMRequestCancellation)
    {
        
        let thumbnailProcessingPredicate = NSPredicate { (obj, _) -> Bool in
            guard let message = obj as? ZMAssetClientMessage,
                let fileMessageData = message.fileMessageData
            else { return false }
            
            return !message.genericAssetMessage!.asset.hasPreview() && fileMessageData.previewData != nil
        }
        let thumbnailFetchPredicate = NSPredicate(format: "delivered == NO")
        
        self.thumbnailPreprocessorTracker = ZMImagePreprocessingTracker(
            managedObjectContext: managedObjectContext,
            imageProcessingQueue: NSOperationQueue(),
            fetchPredicate: thumbnailFetchPredicate,
            needsProcessingPredicate: thumbnailProcessingPredicate,
            entityClass: ZMAssetClientMessage.self
        )
        
        self.filePreprocessor = FilePreprocessor(managedObjectContext: managedObjectContext)
        self.authenticationStatus = authenticationStatus
        self.clientRegistrationStatus = clientRegistrationStatus
        self.requestFactory = ClientMessageRequestFactory()
        self.taskCancellationProvider = taskCancellationProvider
        super.init(managedObjectContext: managedObjectContext)

        
        self.fullFileUpstreamSync = ZMUpstreamModifiedObjectSync(
            transcoder: self,
            entityName: ZMAssetClientMessage.entityName(),
            updatePredicate: ZMAssetClientMessage.predicateForFileToUpload,
            filter: ZMAssetClientMessage.filterForFileToUpload,
            keysToSync: [ZMAssetClientMessageUploadedStateKey],
            managedObjectContext: managedObjectContext
        )
    }
    
    public var contextChangeTrackers : [ZMContextChangeTracker] {
        return [self.fullFileUpstreamSync, self.filePreprocessor, self.thumbnailPreprocessorTracker, self]
    }
    
    public func shouldProcessUpdatesBeforeInserts() -> Bool {
        return false
    }
    
    public func dependentObjectNeedingUpdateBeforeProcessingObject(dependant: ZMManagedObject) -> ZMManagedObject? {
        guard let message = dependant as? ZMAssetClientMessage else { return nil }
        let dependency = message.dependendObjectNeedingUpdateBeforeProcessing()
        return dependency
    }
    
    public func requestForUpdatingObject(managedObject: ZMManagedObject, forKeys keys: Set<NSObject>) -> ZMUpstreamRequest? {
        guard let message = managedObject as? ZMAssetClientMessage else { return nil }
        guard keys.contains(ZMAssetClientMessageUploadedStateKey) else { return nil }
        
        if message.uploadState == .UploadingFailed {
            cancelOutstandingUploadRequests(forMessage: message)
            return ZMUpstreamRequest(
                keys: Set(arrayLiteral: ZMAssetClientMessageUploadedStateKey),
                transportRequest: requestToUploadNotUploaded(message)
            )
        }
        if message.uploadState == .UploadingThumbnail {
            return ZMUpstreamRequest(
                keys: Set(arrayLiteral: ZMAssetClientMessageUploadedStateKey),
                transportRequest: self.requestToUploadThumbnail(message)
            )
        }
        if message.uploadState == .UploadingFullAsset {
            return ZMUpstreamRequest(
                keys: Set(arrayLiteral: ZMAssetClientMessageUploadedStateKey),
                transportRequest: self.requestToUploadFull(message)
            )
        }
        if message.uploadState == .UploadingPlaceholder {
            return ZMUpstreamRequest(keys: Set(arrayLiteral: ZMAssetClientMessageUploadedStateKey),
                transportRequest: self.requestToUploadPlaceholder(message)
            )
        }
        return nil
    }
    
    public func requestForInsertingObject(managedObject: ZMManagedObject,
        forKeys keys: Set<NSObject>?) -> ZMUpstreamRequest?
    {
        return nil
    }
    
    public func updateInsertedObject(managedObject: ZMManagedObject,request upstreamRequest: ZMUpstreamRequest,response: ZMTransportResponse)
    {
        guard let message = managedObject as? ZMAssetClientMessage else { return }
        message.updateWithPostPayload(response.payload.asDictionary(), updatedKeys: Set<NSObject>())
        message.parseUploadResponse(response, clientDeletionDelegate: self.clientRegistrationStatus)
    }
    
    public func updateUpdatedObject(managedObject: ZMManagedObject,
        requestUserInfo: [NSObject : AnyObject]?,
        response: ZMTransportResponse,
        keysToParse: Set<NSObject>) -> Bool
    {
        guard let message = managedObject as? ZMAssetClientMessage else { return false	 }
        if let payload = response.payload?.asDictionary() {
            message.updateWithPostPayload(payload, updatedKeys: keysToParse)
        }
        message.parseUploadResponse(response, clientDeletionDelegate: self.clientRegistrationStatus)
        
        guard keysToParse.contains(ZMAssetClientMessageUploadedStateKey) else { return false }
        
        switch message.uploadState {
        case .UploadingPlaceholder:
            if message.fileMessageData?.previewData != nil {
                message.uploadState =  .UploadingThumbnail
            } else {
                message.uploadState =  .UploadingFullAsset
            }
            return true
        case .UploadingThumbnail:
            message.uploadState = .UploadingFullAsset
            return true
        case .UploadingFullAsset:
            message.transferState = .Downloaded
            message.uploadState = .Done
            message.delivered = true
            let assetIDTransportString = response.headers?[reponseHeaderAssetIdKey] as? String
            if let assetID = assetIDTransportString.flatMap(NSUUID.uuidWithTransportString) {
                message.assetId = assetID
            }
            self.deleteRequestData(forMessage: message, includingEncryptedAssetData: true)
            
            let messageObjectId = message.objectID
            self.managedObjectContext.zm_userInterfaceContext.performGroupedBlock({ () -> Void in
                let uiMessage = try? self.managedObjectContext.zm_userInterfaceContext.existingObjectWithID(messageObjectId)
                
                let userInfo = [FileUploadRequestStrategyNotification.requestStartTimestampKey: response.startOfUploadTimestamp ?? NSDate()]
                
                NSNotificationCenter.defaultCenter().postNotificationName(FileUploadRequestStrategyNotification.uploadFinishedNotificationName, object: uiMessage, userInfo: userInfo)
            })
            
        case .UploadingFailed, .Done: break
        }
        
        return false
    }
    
    public func objectToRefetchForFailedUpdateOfObject(managedObject: ZMManagedObject) -> ZMManagedObject? {
        return nil
    }
    
    public func shouldRetryToSyncAfterFailedToUpdateObject(managedObject: ZMManagedObject,
        request upstreamRequest: ZMUpstreamRequest,
        response: ZMTransportResponse,
        keysToParse keys: Set<NSObject>)-> Bool {
        guard let message = managedObject as? ZMAssetClientMessage else { return false }
        let failedBecauseOfMissingClients = message.parseUploadResponse(response, clientDeletionDelegate: self.clientRegistrationStatus)
        if !failedBecauseOfMissingClients {
            let shouldUploadFailed = [ZMAssetUploadState.UploadingFullAsset, .UploadingThumbnail].contains(message.uploadState)
            failMessageUpload(message, keys: keys, request: upstreamRequest.transportRequest)
            return shouldUploadFailed
        }
        
        return failedBecauseOfMissingClients
    }
    
    
    /// marks the upload as failed
    private func failMessageUpload(message: ZMAssetClientMessage, keys: Set<NSObject>, request: ZMTransportRequest?) {
        
        if message.transferState != .CancelledUpload {
            message.transferState = .FailedUpload
            message.expire()
        }
        
        if keys.contains(ZMAssetClientMessageUploadedStateKey) {
            
            switch message.uploadState {
            case .UploadingPlaceholder:
                deleteRequestData(forMessage: message, includingEncryptedAssetData: true)
                
            case .UploadingFullAsset, .UploadingThumbnail:
                message.didFailToUploadFileData()
                deleteRequestData(forMessage: message, includingEncryptedAssetData: false)
                
            case .UploadingFailed: return
            case .Done: break
            }
            
            message.uploadState = .UploadingFailed
        }
        
        
        // Tracking
        let messageObjectId = message.objectID
        self.managedObjectContext.zm_userInterfaceContext.performGroupedBlock({ () -> Void in
            let uiMessage = try? self.managedObjectContext.zm_userInterfaceContext.existingObjectWithID(messageObjectId)
            
            let userInfo = [FileUploadRequestStrategyNotification.requestStartTimestampKey: request?.startOfUploadTimestamp != nil ?? NSDate()]
            
            NSNotificationCenter.defaultCenter().postNotificationName(FileUploadRequestStrategyNotification.uploadFailedNotificationName, object: uiMessage, userInfo: userInfo)
        })
    }
    
    func nextRequest() -> ZMTransportRequest? {
        guard self.authenticationStatus.currentPhase == .Authenticated else { return nil }
        guard self.clientRegistrationStatus.currentClientReadyToUse else  { return nil }
        return self.fullFileUpstreamSync.nextRequest()
    }
    
    /// Returns a request to upload original
    private func requestToUploadPlaceholder(message: ZMAssetClientMessage) -> ZMTransportRequest? {
        guard let conversationId = message.conversation?.remoteIdentifier else { return nil }
        let request = requestFactory.upstreamRequestForEncryptedFileMessage(.Placeholder, message: message, forConversationWithId: conversationId)
        
        request?.addTaskCreatedHandler(ZMTaskCreatedHandler(onGroupQueue: managedObjectContext) { taskIdentifier in
            message.associatedTaskIdentifier = taskIdentifier
        })
        
        request?.addCompletionHandler(ZMCompletionHandler(onGroupQueue: managedObjectContext) { [weak request] response in
            message.associatedTaskIdentifier = nil
            
            let keys = Set(arrayLiteral: ZMAssetClientMessageUploadedStateKey)
            
            if response.result == .Expired || response.result == .TemporaryError || response.result == .TryAgainLater {
                self.failMessageUpload(message, keys: keys, request: request)
                // When we fail to upload the placeholder we do not want to send a notUploaded (UploadingFailed) message
                message.resetLocallyModifiedKeys(keys)
            }
        })
        return request
    }
    
    /// Returns a request to upload the thumbnail
    private func requestToUploadThumbnail(message: ZMAssetClientMessage) -> ZMTransportRequest? {
        guard let conversationId = message.conversation?.remoteIdentifier else { return nil }
        let request = requestFactory.upstreamRequestForEncryptedFileMessage(.Thumbnail, message: message, forConversationWithId: conversationId)
        request?.addTaskCreatedHandler(ZMTaskCreatedHandler(onGroupQueue: managedObjectContext) { taskIdentifier in
            message.associatedTaskIdentifier = taskIdentifier
        })
        
        request?.addCompletionHandler(ZMCompletionHandler(onGroupQueue: managedObjectContext) { [weak request] response in
            message.associatedTaskIdentifier = nil
            
            if response.result == .Expired || response.result == .TemporaryError || response.result == .TryAgainLater {
                self.failMessageUpload(message, keys: Set(arrayLiteral: ZMAssetClientMessageUploadedStateKey), request: request)
            }
        })
        
        return request
    }
    
    /// Returns a request to upload full file
    private func requestToUploadFull(message: ZMAssetClientMessage) -> ZMTransportRequest? {
        guard let conversationId = message.conversation?.remoteIdentifier else { return nil }
        let request = requestFactory.upstreamRequestForEncryptedFileMessage(.FullAsset, message: message, forConversationWithId: conversationId)
        
        request?.addTaskCreatedHandler(ZMTaskCreatedHandler(onGroupQueue: managedObjectContext) { taskIdentifier in
          message.associatedTaskIdentifier = taskIdentifier
        })
        
        request?.addCompletionHandler(ZMCompletionHandler(onGroupQueue: managedObjectContext) { [weak request] response in
            message.associatedTaskIdentifier = nil
            
            if response.result == .Expired || response.result == .TemporaryError || response.result == .TryAgainLater {
                self.failMessageUpload(message, keys: Set(arrayLiteral: ZMAssetClientMessageUploadedStateKey), request: request)
            }
        })
        request?.addProgressHandler(ZMTaskProgressHandler(onGroupQueue: self.managedObjectContext) { progress in
            message.progress = progress
            self.managedObjectContext.enqueueDelayedSave()
        })
        return request
    }
    
    /// Returns a request to upload full file
    private func requestToUploadNotUploaded(message: ZMAssetClientMessage) -> ZMTransportRequest? {
        guard let conversationId = message.conversation?.remoteIdentifier else { return nil }
        let request = requestFactory.upstreamRequestForEncryptedFileMessage(.Placeholder, message: message, forConversationWithId: conversationId)
        return request
    }
    
    private func deleteRequestData(forMessage message: ZMAssetClientMessage, includingEncryptedAssetData: Bool) {
        // delete request data
        message.managedObjectContext?.zm_fileAssetCache.deleteRequestData(message.nonce)
        
        // delete asset data
        if includingEncryptedAssetData {
            message.managedObjectContext?.zm_fileAssetCache.deleteAssetData(message.nonce, fileName: message.filename!, encrypted: true)
        }
    }
    
    private func cancelOutstandingUploadRequests(forMessage message: ZMAssetClientMessage) {
        guard let identifier = message.associatedTaskIdentifier else { return }
        self.taskCancellationProvider?.cancelTaskWithIdentifier(identifier)
    }
}

extension FileUploadRequestStrategy: ZMContextChangeTracker {
    
    // we need to cancel the requests manually as the upstream modified object sync
    // will not pick up a change to keys which are already being synchronized (uploadState)
    // when the user cancels a file upload
    public func objectsDidChange(object: Set<NSObject>) {
        let assetClientMessages = object.flatMap { object -> ZMAssetClientMessage? in
            guard let message = object as? ZMAssetClientMessage where
                nil != message.fileMessageData && message.transferState == .CancelledUpload
                else { return nil }
            return message
        }
        
        assetClientMessages.forEach(cancelOutstandingUploadRequests)
    }
    
    public func fetchRequestForTrackedObjects() -> NSFetchRequest? {
        return nil
    }
    
    public func addTrackedObjects(objects: Set<NSObject>) {
        // no op
    }
}

extension ZMAssetClientMessage {
    
    static var predicateForFileToUpload : NSPredicate {
        
        let notUploadedPredicate = NSPredicate(format: "%K == %d || %K == %d",
            ZMAssetClientMessageTransferStateKey,
            ZMFileTransferState.FailedUpload.rawValue,
            ZMAssetClientMessageTransferStateKey,
            ZMFileTransferState.CancelledUpload.rawValue
        )
        
        let needsUploadPredicate = NSPredicate(format: "%K != %d && %K == %d",
            ZMAssetClientMessageUploadedStateKey, ZMAssetUploadState.Done.rawValue,
            ZMAssetClientMessageTransferStateKey, ZMFileTransferState.Uploading.rawValue
        )
        
        return NSCompoundPredicate(orPredicateWithSubpredicates: [needsUploadPredicate, notUploadedPredicate])
    }
    
    static var filterForFileToUpload : NSPredicate {
        return NSPredicate(format: "isReadyToUploadFile == YES")
    }
    
    /// We want to upload messages that represent a file where the transfer state is
    /// one of @c Uploading, @c FailedUpload or @c CancelledUpload and only if we are not done uploading.
    /// We also want to wait for the preprocessing of the file data (encryption) to finish (thus the check for an existing otrKey).
    /// If this message has a thumbnail, we additionally want to wait for the thumbnail preprocessing to finish (check for existing preview image)
    /// We check if this message has a thumbnail by checking @c hasDownloadedImage which will be true if the original or medium image exists on disk.
    var isReadyToUploadFile : Bool {
        return self.fileMessageData != nil
            && [.Uploading, .FailedUpload, .CancelledUpload].contains(transferState)
            && self.uploadState != .Done
            && self.genericAssetMessage?.asset.uploaded.otrKey.length > 0
            && (!self.hasDownloadedImage || self.genericAssetMessage?.asset.preview.image.width > 0)
    }
}
