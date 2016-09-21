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


@objc public final class LinkPreviewAssetDownloadRequestStrategy: ZMObjectSyncStrategy, RequestStrategy {
    
    fileprivate var assetDownstreamObjectSync: ZMDownstreamObjectSyncWithWhitelist!
    fileprivate let authStatus: AuthenticationStatusProvider
    fileprivate let assetRequestFactory = AssetDownloadRequestFactory()
    
    public init(authStatus: AuthenticationStatusProvider, managedObjectContext: NSManagedObjectContext) {
        self.authStatus = authStatus
        super.init(managedObjectContext: managedObjectContext)
        
        let downloadFilter = NSPredicate { object, _ in
            guard let message = object as? ZMClientMessage, let genericMessage = message.genericMessage , genericMessage.hasText() else { return false }
            guard let preview = genericMessage.text.linkPreview?.first as? ZMLinkPreview, let remote: ZMAssetRemoteData = preview.remote  else { return false }
            guard nil == managedObjectContext.zm_imageAssetCache.assetData(message.nonce, format: .medium, encrypted: false) else { return false }
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
        NotificationCenter.default.removeObserver(self)
    }
    
    func registerForWhitelistingNotification() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(didWhitelistAssetDownload),
            name: NSNotification.Name(rawValue: ZMClientMessageLinkPreviewImageDownloadNotificationName),
            object: nil
        )
    }
    
    func didWhitelistAssetDownload(_ note: Notification) {
        managedObjectContext.performGroupedBlock { [weak self] in
            guard let `self` = self else { return }
            guard let objectID = note.object as? NSManagedObjectID else { return }
            guard let message = try? self.managedObjectContext.existingObject(with: objectID) as? ZMClientMessage else { return }
            self.assetDownstreamObjectSync.whiteListObject(message)
            ZMOperationLoop.notifyNewRequestsAvailable(self)
        }
    }
    
    func nextRequest() -> ZMTransportRequest? {
        guard authStatus.currentPhase == .authenticated else { return nil }
        return assetDownstreamObjectSync.nextRequest()
    }
    
    func handleResponse(_ response: ZMTransportResponse!, forMessage message: ZMClientMessage) {
        guard response.result == .success else { return }
        let cache = managedObjectContext.zm_imageAssetCache
        
        let linkPreview = message.genericMessage?.text.linkPreview.first as? ZMLinkPreview
        guard let remote = linkPreview?.remote, let data = response.rawData else { return }
        cache?.storeAssetData(message.nonce, format: .medium, encrypted: true, data: data)

        let success = cache?.decryptFileIfItMatchesDigest(
            message.nonce,
            format: .medium,
            encryptionKey: remote.otrKey,
            sha256Digest: remote.sha256
        )
        
        guard success! else { return }
        
        let uiMOC = managedObjectContext.zm_userInterface
        let objectID = message.objectID
        uiMOC?.performGroupedBlock {
            guard let uiMessage = try? uiMOC?.existingObject(with: objectID) else { return }
            uiMOC?.globalManagedObjectContextObserver.notifyNonCoreDataChangeInManagedObject(uiMessage!)
        }
    }

}

extension LinkPreviewAssetDownloadRequestStrategy: ZMContextChangeTrackerSource {
    
    public var contextChangeTrackers: [ZMContextChangeTracker] {
        return [assetDownstreamObjectSync]
    }
    
}


extension LinkPreviewAssetDownloadRequestStrategy: ZMDownstreamTranscoder {
    
    public func request(forFetching object: ZMManagedObject!, downstreamSync: ZMObjectSync!) -> ZMTransportRequest! {
        guard let message = object as? ZMClientMessage else { fatal("Unable to generate request for \(object)") }
        guard let linkPreview = message.genericMessage?.text.linkPreview.first as? ZMLinkPreview else { return nil }
        guard let remoteData = linkPreview.remote else { return nil }

        // Protobuf initializes the token to an empty string when set to nil
        let token = remoteData.hasAssetToken() && remoteData.assetToken != "" ? remoteData.assetToken : nil
        let request = assetRequestFactory.requestToGetAsset(withKey: remoteData.assetId, token: token)
        request?.add(ZMCompletionHandler(on: managedObjectContext) { response in
            self.handleResponse(response, forMessage: message)
        })
        return request
    }
    
    public func delete(_ object: ZMManagedObject!, downstreamSync: ZMObjectSync!) {
        // no-op
    }
    
    public func update(_ object: ZMManagedObject!, with response: ZMTransportResponse!, downstreamSync: ZMObjectSync!) {
        // no-op
    }
    
}

extension ZMLinkPreview {
    var remote: ZMAssetRemoteData? {
        if let image = article.image , image.hasUploaded() {
            return image.uploaded
        } else if let image = image , hasImage() {
            return image.uploaded
        }
        
        return nil
    }
}
