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

public final class ImageUploadRequestStrategy: ZMObjectSyncStrategy, RequestStrategy, ZMContextChangeTrackerSource {
    
    fileprivate let imagePreprocessor : ZMImagePreprocessingTracker
    fileprivate let authenticationStatus : AuthenticationStatusProvider
    fileprivate let requestFactory : ClientMessageRequestFactory = ClientMessageRequestFactory()
    fileprivate weak var clientRegistrationStatus : ZMClientRegistrationStatus?
    fileprivate var upstreamSync : ZMUpstreamModifiedObjectSync!
    
    
    public init(authenticationStatus: AuthenticationStatusProvider, clientRegistrationStatus: ZMClientRegistrationStatus, managedObjectContext: NSManagedObjectContext) {
        self.authenticationStatus = authenticationStatus
        self.clientRegistrationStatus = clientRegistrationStatus
        
        let fetchPredicate = NSPredicate(format: "delivered == NO")
        let needsProcessingPredicate = NSPredicate(format: "(mediumGenericMessage.image.width == 0 || previewGenericMessage.image.width == 0) && delivered == NO")
        self.imagePreprocessor = ZMImagePreprocessingTracker(managedObjectContext: managedObjectContext,
                                                             imageProcessingQueue: OperationQueue(),
                                                             fetch: fetchPredicate,
                                                             needsProcessingPredicate: needsProcessingPredicate,
                                                             entityClass: ZMAssetClientMessage.self)
        
        super.init(managedObjectContext: managedObjectContext)
        
        let insertPredicate = NSPredicate(format: "\(ZMAssetClientMessageUploadedStateKey) != \(ZMAssetUploadState.done.rawValue)")
        let uploadFilter = NSPredicate { (object : Any, _) -> Bool in
            guard let message = object as? ZMAssetClientMessage else { return false }
            return message.imageMessageData != nil &&
                (message.uploadState == .uploadingPlaceholder || message.uploadState == .uploadingFullAsset) &&
                message.imageAssetStorage?.mediumGenericMessage?.image.width != 0 &&
                message.imageAssetStorage?.previewGenericMessage?.image.width != 0
        }
        
        upstreamSync = ZMUpstreamModifiedObjectSync(transcoder: self,
                                                    entityName: ZMAssetClientMessage.entityName(),
                                                    update:insertPredicate,
                                                    filter: uploadFilter,
                                                    keysToSync: nil,
                                                    managedObjectContext: managedObjectContext)
    }
    
    public var contextChangeTrackers: [ZMContextChangeTracker] {
        return [imagePreprocessor, upstreamSync]
    }
    
    public func nextRequest() -> ZMTransportRequest? {
        guard self.authenticationStatus.currentPhase == .authenticated else { return nil }
        return self.upstreamSync.nextRequest()
    }
}

extension ImageUploadRequestStrategy : ZMUpstreamTranscoder {
    
    public func request(forInserting managedObject: ZMManagedObject, forKeys keys: Set<String>?) -> ZMUpstreamRequest? {
        return nil // no-op
    }
    
    public func dependentObjectNeedingUpdate(beforeProcessingObject dependant: ZMManagedObject) -> ZMManagedObject? {
        guard let message = dependant as? ZMMessage else { return nil }
        return message.dependendObjectNeedingUpdateBeforeProcessing()
    }
    
    fileprivate func update(_ message: ZMAssetClientMessage, withResponse response: ZMTransportResponse, updatedKeys keys: Set<String>) {
        message.markAsSent()
        message.update(withPostPayload: response.payload?.asDictionary(), updatedKeys: keys)
        
        if let clientRegistrationStatus = self.clientRegistrationStatus {
            let _ = message.parseUploadResponse(response, clientDeletionDelegate: clientRegistrationStatus)
        }
    }
    
    public func updateInsertedObject(_ managedObject: ZMManagedObject, request upstreamRequest: ZMUpstreamRequest, response: ZMTransportResponse) {
        guard let message = managedObject as? ZMAssetClientMessage else { return }
        update(message, withResponse: response, updatedKeys: Set())
    }
    
    public func updateUpdatedObject(_ managedObject: ZMManagedObject, requestUserInfo: [AnyHashable : Any]? = nil, response: ZMTransportResponse, keysToParse: Set<String>) -> Bool {
        guard let message = managedObject as? ZMAssetClientMessage else { return false }
        
        update(message, withResponse: response, updatedKeys: keysToParse)
        
        var needsMoreRequests = false
        
        if keysToParse.contains(ZMAssetClientMessageUploadedStateKey) {
            switch message.uploadState {
            case .uploadingPlaceholder:
                message.uploadState = .uploadingFullAsset
                managedObjectContext.zm_imageAssetCache.deleteAssetData(message.nonce, format: .preview, encrypted: false)
                managedObjectContext.zm_imageAssetCache.deleteAssetData(message.nonce, format: .preview, encrypted: true)
                needsMoreRequests = true // want to upload full asset
            case .uploadingFullAsset:
                message.uploadState = .done
                if let assetId = response.headers?["Location"] as? String {
                    message.assetId = UUID(uuidString: assetId)
                }
                message.managedObjectContext?.zm_imageAssetCache.deleteAssetData(message.nonce, format: .medium, encrypted: true)
                message.resetLocallyModifiedKeys(Set(arrayLiteral: ZMAssetClientMessageUploadedStateKey))
            default:
                break
            }
        }
        
        return needsMoreRequests
    }
    
    public func request(forUpdating managedObject: ZMManagedObject, forKeys keys: Set<String>) -> ZMUpstreamRequest? {
        guard let message = managedObject as? ZMAssetClientMessage, let conversation = message.conversation else { return nil }
        
        let format = imageFormatForKeys(keys, message: message)
        
        if format == .invalid {
            ZMTrapUnableToGenerateRequest(keys, self)
            return nil
        }
        
        guard let request = requestFactory.upstreamRequestForAssetMessage(format, message: message, forConversationWithId: conversation.remoteIdentifier!) else {
            // We will crash, but we should still delete the image
            message.managedObjectContext?.delete(message)
            managedObjectContext.saveOrRollback()
            return nil
        }
        
        request.add(ZMCompletionHandler(on: managedObjectContext, block: { [weak self] (response) in
            if response.result == .success {
                message.markAsSent()
                ZMOperationLoop.notifyNewRequestsAvailable(self)
            }
        }))
        
        return ZMUpstreamRequest(keys: Set(arrayLiteral: ZMAssetClientMessageUploadedStateKey), transportRequest: request)        
    }
    
    public func shouldCreateRequest(toSyncObject managedObject: ZMManagedObject, forKeys keys: Set<String>, withSync sync: Any) -> Bool {
        guard let message = managedObject as? ZMAssetClientMessage, let imageAssetStorage = message.imageAssetStorage  else { return false }
        
        let format = imageFormatForKeys(keys, message: message)
        
        if format == .invalid {
            return true // We will ultimately crash here when trying to create the request
        }
        
        if imageAssetStorage.shouldReprocess(for: format) {
            // before we create an upstream request we should check if we can (and should) process image data again
            // if we can we reschedule processing
            // this might cause a loop if the message can not be processed whatsoever
            scheduleImageProcessing(forMessage: message, format: format)
            managedObjectContext.saveOrRollback()
            return false
        }
        
        return true
    }
    
    public func shouldRetryToSyncAfterFailed(toUpdate managedObject: ZMManagedObject, request upstreamRequest: ZMUpstreamRequest, response: ZMTransportResponse, keysToParse keys: Set<String>) -> Bool {
        guard let message = managedObject as? ZMAssetClientMessage, let clientRegistrationStatus = self.clientRegistrationStatus else { return false }
     
        let shouldRetry = message.parseUploadResponse(response, clientDeletionDelegate: clientRegistrationStatus)
        if !shouldRetry {
            message.uploadState = .uploadingFailed
        }
        return shouldRetry
    }
    
    public func objectToRefetchForFailedUpdate(of managedObject: ZMManagedObject) -> ZMManagedObject? {
        return nil
    }
    
    public func shouldProcessUpdatesBeforeInserts() -> Bool {
        return false
    }
    
    func imageFormatForKeys(_ keys: Set<String>, message: ZMAssetClientMessage) -> ZMImageFormat {
        var format : ZMImageFormat = .invalid
        
        if keys.contains(ZMAssetClientMessageUploadedStateKey) {
            switch message.uploadState {
            case .uploadingPlaceholder:
                format = .preview
                
            case .uploadingFullAsset:
                format = .medium
            default:
                break
            }
        }
        
        return format
    }
    
    func scheduleImageProcessing(forMessage message: ZMAssetClientMessage, format : ZMImageFormat) {
        let genericMessage = ZMGenericMessage(mediumImageProperties: nil, processedImageProperties: nil, encryptionKeys: nil, nonce: message.nonce.transportString(), format: format)
        message.add(genericMessage)
        ZMOperationLoop.notifyNewRequestsAvailable(self)
    }
    
}
