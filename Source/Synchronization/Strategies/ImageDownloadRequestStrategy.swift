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

public class ImageDownloadRequestStrategy : ZMObjectSyncStrategy, RequestStrategy {
    
    private let authenticationStatus : AuthenticationStatusProvider
    private var downstreamSync : ZMDownstreamObjectSyncWithWhitelist!
    private let requestFactory : ClientMessageRequestFactory = ClientMessageRequestFactory()
    
    public init(authenticationStatus: AuthenticationStatusProvider, managedObjectContext: NSManagedObjectContext) {
        self.authenticationStatus = authenticationStatus
        
        super.init(managedObjectContext: managedObjectContext)
        
        let downloadPredicate = NSPredicate { (object, _) -> Bool in
            guard let message = object as? ZMAssetClientMessage else { return false }
            let missingMediumImage = message.imageMessageData != nil && !message.hasDownloadedImage && message.assetId != nil
            let missingVideoThumbnail = message.fileMessageData != nil && !message.hasDownloadedImage && message.fileMessageData?.thumbnailAssetID != nil
            return missingMediumImage || missingVideoThumbnail
        }
        
        downstreamSync = ZMDownstreamObjectSyncWithWhitelist(transcoder: self,
                                                             entityName: ZMAssetClientMessage.entityName(),
                                                             predicateForObjectsToDownload: downloadPredicate,
                                                             managedObjectContext: managedObjectContext)
        
        registerForWhitelistingNotification()
    }
    
    deinit {
        NSNotificationCenter.defaultCenter().removeObserver(self)
    }
    
    func registerForWhitelistingNotification() {
        NSNotificationCenter.defaultCenter().addObserver(
            self,
            selector: #selector(didRequestToDownloadImage),
            name: ZMAssetClientMessage.ImageDownloadNotificationName,
            object: nil
        )
    }
    
    func didRequestToDownloadImage(note: NSNotification) {
        managedObjectContext.performGroupedBlock { [weak self] in
            guard let `self` = self else { return }
            guard let objectID = note.object as? NSManagedObjectID else { return }
            guard let object = try? self.managedObjectContext.existingObjectWithID(objectID) else { return }
            guard let message = object as? ZMAssetClientMessage else { return }
            self.downstreamSync.whiteListObject(message)
            ZMOperationLoop.notifyNewRequestsAvailable(self)
        }
    }
    
    func nextRequest() -> ZMTransportRequest? {
        guard authenticationStatus.currentPhase == .Authenticated else { return nil }
        return downstreamSync.nextRequest()
    }

}

extension ImageDownloadRequestStrategy : ZMDownstreamTranscoder {
    
    public func requestForFetchingObject(object: ZMManagedObject!, downstreamSync: ZMObjectSync!) -> ZMTransportRequest! {
        guard let message = object as? ZMAssetClientMessage, let conversation = message.conversation else { return nil }
        
        if let existingData = managedObjectContext.zm_imageAssetCache.assetData(message.nonce, format: .Medium, encrypted: false) {
            updateMediumImage(forMessage: message, imageData: existingData)
            managedObjectContext.enqueueDelayedSave()
            return nil
        } else {
            if message.imageMessageData != nil {
                guard let assetId = message.assetId?.transportString() else { return nil }
                return requestFactory.requestToGetAsset(assetId, inConversation: conversation.remoteIdentifier, isEncrypted: message.isEncrypted)
            } else if (message.fileMessageData != nil) {
                guard let assetId = message.fileMessageData?.thumbnailAssetID else { return nil }
                return requestFactory.requestToGetAsset(assetId, inConversation: conversation.remoteIdentifier, isEncrypted: message.isEncrypted)
            }
        }
        
        return nil
    }
    
    public func updateObject(object: ZMManagedObject!, withResponse response: ZMTransportResponse!, downstreamSync: ZMObjectSync!) {
        guard let message = object as? ZMAssetClientMessage else { return }
        updateMediumImage(forMessage: message, imageData: response.rawData)
    }
    
    public func deleteObject(object: ZMManagedObject!, downstreamSync: ZMObjectSync!) {
        guard let message = object as? ZMAssetClientMessage else { return }
        message.managedObjectContext?.deleteObject(message)
    }
    
    private func updateMediumImage(forMessage message: ZMAssetClientMessage, imageData: NSData) {
        message.imageAssetStorage?.updateMessageWithImageData(imageData, forFormat: .Medium)
        
        let uiMOC = managedObjectContext.zm_userInterfaceContext
        
        uiMOC.performGroupedBlock { 
            guard let message = try? uiMOC.existingObjectWithID(message.objectID) else { return }
            uiMOC.globalManagedObjectContextObserver.notifyNonCoreDataChangeInManagedObject(message)
        }
    }
    
}
