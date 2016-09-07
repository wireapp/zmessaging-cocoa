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
import zimages
import ZMTransport

@objc public class AssetDownloadRequestStrategyNotification: NSObject {
    public static let downloadFinishedNotificationName = "AssetDownloadRequestStrategyDownloadFinishedNotificationName"
    public static let downloadStartTimestampKey = "requestStartTimestamp"
    public static let downloadFailedNotificationName = "AssetDownloadRequestStrategyDownloadFailedNotificationName"
}

@objc final public class AssetDownloadRequestStrategy: NSObject, RequestStrategy, ZMDownstreamTranscoder, ZMContextChangeTrackerSource {
    
    private var assetDownstreamObjectSync: ZMDownstreamObjectSync!
    private let managedObjectContext: NSManagedObjectContext
    private let authStatus: AuthenticationStatusProvider
    private weak var taskCancellationProvider: ZMRequestCancellation?
    
    public init(authStatus: AuthenticationStatusProvider, taskCancellationProvider: ZMRequestCancellation, managedObjectContext: NSManagedObjectContext) {
        self.managedObjectContext = managedObjectContext
        self.authStatus = authStatus
        self.taskCancellationProvider = taskCancellationProvider
        super.init()
        registerForCancellationNotification()
        
        let downstreamPredicate = NSPredicate(format: "transferState == %d AND assetId_data != nil", ZMFileTransferState.Downloading.rawValue)
        
        self.assetDownstreamObjectSync = ZMDownstreamObjectSync(
            transcoder: self,
            entityName: ZMAssetClientMessage.entityName(),
            predicateForObjectsToDownload: downstreamPredicate,
            filter: NSPredicate(format: "fileMessageData != nil"),
            managedObjectContext: managedObjectContext
        )
    }
    
    deinit {
        NSNotificationCenter.defaultCenter().removeObserver(self)
    }
    
    func registerForCancellationNotification() {
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(AssetDownloadRequestStrategy.cancelOngoingRequestForAssetClientMessage(_:)), name: ZMAssetClientMessageDidCancelFileDownloadNotificationName, object: nil)
    }
    
    func cancelOngoingRequestForAssetClientMessage(note: NSNotification) {
        guard let objectID = note.object as? NSManagedObjectID else { return }
        managedObjectContext.performGroupedBlock { [weak self] in
            guard let message = self?.managedObjectContext.objectRegisteredForID(objectID) as? ZMAssetClientMessage else { return }
            guard let identifier = message.associatedTaskIdentifier else { return }
            self?.taskCancellationProvider?.cancelTaskWithIdentifier(identifier)
            message.associatedTaskIdentifier = nil
        }
    }

    public func nextRequest() -> ZMTransportRequest? {
        guard self.authStatus.currentPhase == .Authenticated else {
            return .None
        }
        
        return self.assetDownstreamObjectSync.nextRequest()
    }
    
    private func handleResponse(response: ZMTransportResponse, forMessage assetClientMessage: ZMAssetClientMessage) {
        if response.result == .Success {
            guard let fileMessageData = assetClientMessage.fileMessageData, asset = assetClientMessage.genericAssetMessage?.asset else { return }
            // TODO: create request that streams directly to the cache file, otherwise the memory would overflow on big files
            let fileCache = self.managedObjectContext.zm_fileAssetCache
            fileCache.storeAssetData(assetClientMessage.nonce, fileName: fileMessageData.filename, encrypted: true, data: response.rawData)

            let decryptionSuccess = fileCache.decryptFileIfItMatchesDigest(
                assetClientMessage.nonce,
                fileName: fileMessageData.filename,
                encryptionKey: asset.uploaded.otrKey,
                sha256Digest: asset.uploaded.sha256
            )
            
            if decryptionSuccess {
                assetClientMessage.transferState = .Downloaded
            }
            else {
                assetClientMessage.transferState = .FailedDownload
            }
        }
        else {
            if assetClientMessage.transferState == .Downloading {
                assetClientMessage.transferState = .FailedDownload
            }
        }
        
        let messageObjectId = assetClientMessage.objectID
        self.managedObjectContext.zm_userInterfaceContext.performGroupedBlock({ () -> Void in
            let uiMessage = try? self.managedObjectContext.zm_userInterfaceContext.existingObjectWithID(messageObjectId)
            
            let userInfo = [AssetDownloadRequestStrategyNotification.downloadStartTimestampKey: response.startOfUploadTimestamp ?? NSDate()]
            if assetClientMessage.transferState == .Downloaded {
                NSNotificationCenter.defaultCenter().postNotificationName(AssetDownloadRequestStrategyNotification.downloadFinishedNotificationName, object: uiMessage, userInfo: userInfo)
            }
            else {
                NSNotificationCenter.defaultCenter().postNotificationName(AssetDownloadRequestStrategyNotification.downloadFailedNotificationName, object: uiMessage, userInfo: userInfo)
            }
        })
    }
    
    // MARK: - ZMContextChangeTrackerSource
    
    public var contextChangeTrackers: [ZMContextChangeTracker] {
        get {
            return [self.assetDownstreamObjectSync]
        }
    }

    // MARK: - ZMDownstreamTranscoder
    
    public func requestForFetchingObject(object: ZMManagedObject!, downstreamSync: ZMObjectSync!) -> ZMTransportRequest! {
        if let assetClientMessage = object as? ZMAssetClientMessage {
            
            let taskCreationHandler = ZMTaskCreatedHandler(onGroupQueue: managedObjectContext) { taskIdentifier in
                assetClientMessage.associatedTaskIdentifier = taskIdentifier
            }
            
            let completionHandler = ZMCompletionHandler(onGroupQueue: self.managedObjectContext) { response in
                self.handleResponse(response, forMessage: assetClientMessage)
            }
            
            let progressHandler = ZMTaskProgressHandler(onGroupQueue: self.managedObjectContext) { progress in
                assetClientMessage.progress = progress
                self.managedObjectContext.enqueueDelayedSave()
            }
            
            if let request = ClientMessageRequestFactory().downstreamRequestForEcryptedOriginalFileMessage(assetClientMessage) {
                request.addTaskCreatedHandler(taskCreationHandler)
                request.addCompletionHandler(completionHandler)
                request.addProgressHandler(progressHandler)
                return request
            }
        }
        
        fatalError("Cannot generate request for \(object)")
    }
    
    public func deleteObject(object: ZMManagedObject!, downstreamSync: ZMObjectSync!) {
        // no-op
    }
    
    public func updateObject(object: ZMManagedObject!, withResponse response: ZMTransportResponse!, downstreamSync: ZMObjectSync!) {
        // no-op
    }
}
