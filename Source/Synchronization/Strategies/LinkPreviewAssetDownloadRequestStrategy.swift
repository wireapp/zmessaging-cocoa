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
import WireRequestStrategy


@objc final public class LinkPreviewAssetDownloadRequestStrategy: ZMObjectSyncStrategy, RequestStrategy {
    
    private var assetDownstreamObjectSync: ZMDownstreamObjectSyncWithWhitelist!
    private let authStatus: AuthenticationStatusProvider
    private let assetRequestFactory = AssetDownloadRequestFactory()
    
    public init(authStatus: AuthenticationStatusProvider, managedObjectContext: NSManagedObjectContext) {
        self.authStatus = authStatus
        super.init(managedObjectContext: managedObjectContext)
        
        let downloadFilter = NSPredicate { object, _ in
            guard let message = object as? ZMClientMessage, genericMessage = message.genericMessage where genericMessage.hasText() else { return false }
            guard let preview = genericMessage.text.linkPreview?.first, remote: ZMAssetRemoteData = preview.remote  else { return false }
            guard nil == managedObjectContext.zm_imageAssetCache.assetData(message.nonce, format: .Medium, encrypted: false) else { return false }
            return remote.hasAssetId()
        }
        
        assetDownstreamObjectSync = ZMDownstreamObjectSyncWithWhitelist(
            transcoder: self,
            entityName: ZMClientMessage.entityName(),
            predicateForObjectsToDownload: downloadFilter,
            managedObjectContext: managedObjectContext
        )
        
        registerForWhitelistingNotification()
    }
    
    deinit {
        NSNotificationCenter.defaultCenter().removeObserver(self)
    }
    
    func registerForWhitelistingNotification() {
        NSNotificationCenter.defaultCenter().addObserver(
            self,
            selector: #selector(didWhitelistAssetDownload),
            name: ZMClientMessageLinkPreviewImageDownloadNotificationName,
            object: nil
        )
    }
    
    func didWhitelistAssetDownload(note: NSNotification) {
        managedObjectContext.performGroupedBlock { [weak self] in
            guard let `self` = self else { return }
            guard let objectID = note.object as? NSManagedObjectID else { return }
            guard let message = try? self.managedObjectContext.existingObjectWithID(objectID) as? ZMClientMessage else { return }
            self.assetDownstreamObjectSync.whiteListObject(message)
            RequestAvailableNotification.notifyNewRequestsAvailable(self)
//            ZMOperationLoop.notifyNewRequestsAvailable(self)
        }
    }
    
    public func nextRequest() -> ZMTransportRequest? {
        guard authStatus.currentPhase == .Authenticated else { return nil }
        return assetDownstreamObjectSync.nextRequest()
    }
    
    func handleResponse(response: ZMTransportResponse!, forMessage message: ZMClientMessage) {
        guard response.result == .Success else { return }
        let cache = managedObjectContext.zm_imageAssetCache
        
        guard let remote = message.genericMessage?.text.linkPreview.first?.remote else { return }
        cache.storeAssetData(message.nonce, format: .Medium, encrypted: true, data: response.rawData)
        let success = cache.decryptFileIfItMatchesDigest(
            message.nonce,
            format: .Medium,
            encryptionKey: remote.otrKey,
            sha256Digest: remote.sha256
        )
        
        guard success else { return }
        
        let uiMOC = managedObjectContext.zm_userInterfaceContext
        let objectID = message.objectID
        uiMOC.performGroupedBlock {
            guard let uiMessage = try? uiMOC.existingObjectWithID(objectID) else { return }
            uiMOC.globalManagedObjectContextObserver.notifyNonCoreDataChangeInManagedObject(uiMessage)
        }
    }

}

extension LinkPreviewAssetDownloadRequestStrategy: ZMContextChangeTrackerSource {
    
    public var contextChangeTrackers: [ZMContextChangeTracker] {
        return [assetDownstreamObjectSync]
    }
    
}


extension LinkPreviewAssetDownloadRequestStrategy: ZMDownstreamTranscoder {
    
    public func requestForFetchingObject(object: ZMManagedObject!, downstreamSync: ZMObjectSync!) -> ZMTransportRequest! {
        guard let message = object as? ZMClientMessage else { fatal("Unable to generate request for \(object)") }
        let linkPreview = message.genericMessage?.text.linkPreview.first
        guard let remoteData = linkPreview?.remote else { return nil }

        // Protobuf initializes the token to an empty string when set to nil
        let token = remoteData.hasAssetToken() && remoteData.assetToken != "" ? remoteData.assetToken : nil
        let request = assetRequestFactory.requestToGetAsset(withKey: remoteData.assetId, token: token)
        request?.addCompletionHandler(ZMCompletionHandler(onGroupQueue: managedObjectContext) { response in
            self.handleResponse(response, forMessage: message)
        })
        return request
    }
    
    public func deleteObject(object: ZMManagedObject!, downstreamSync: ZMObjectSync!) {
        // no-op
    }
    
    public func updateObject(object: ZMManagedObject!, withResponse response: ZMTransportResponse!, downstreamSync: ZMObjectSync!) {
        // no-op
    }
    
}

extension ZMLinkPreview {
    var remote: ZMAssetRemoteData? {
        if let image = article.image where image.hasUploaded() {
            return image.uploaded
        } else if let image = image where hasImage() {
            return image.uploaded
        }
        
        return nil
    }
}
