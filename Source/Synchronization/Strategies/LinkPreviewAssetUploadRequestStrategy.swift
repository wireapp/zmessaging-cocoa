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
import ZMCLinkPreview

@objc public class LinkPreviewDetectorHelper : NSObject {
    private static var _test_debug_linkPreviewDetector : LinkPreviewDetectorType? = nil
    
    @objc public class func test_debug_linkPreviewDetector() -> LinkPreviewDetectorType?
    {
        return _test_debug_linkPreviewDetector
    }
    
    @objc public class func setTest_debug_linkPreviewDetector(detectorType: LinkPreviewDetectorType?)
    {
        _test_debug_linkPreviewDetector = detectorType
    }
    
    @objc public class func tearDown()
    {
        _test_debug_linkPreviewDetector = nil
    }
    
}


public class LinkPreviewAssetUploadRequestStrategy : ZMObjectSyncStrategy, RequestStrategy, ZMContextChangeTrackerSource {
    
    
    
    let requestFactory = AssetRequestFactory()
    
    /// Auth status to know whether we can make requests
    private let authenticationStatus : AuthenticationStatusProvider
    
    /// Processors
    private let linkPreviewPreprocessor : LinkPreviewPreprocessor
    private let previewImagePreprocessor : ZMImagePreprocessingTracker
    
    /// Upstream sync
    private var assetUpstreamSync : ZMUpstreamModifiedObjectSync!
    
    public convenience init(authenticationStatus: AuthenticationStatusProvider, managedObjectContext: NSManagedObjectContext) {
        
        if nil == LinkPreviewDetectorHelper.test_debug_linkPreviewDetector() {
            LinkPreviewDetectorHelper.setTest_debug_linkPreviewDetector(LinkPreviewDetector(resultsQueue: NSOperationQueue.currentQueue()!))
        }
        
        let linkPreviewPreprocessor = LinkPreviewPreprocessor(linkPreviewDetector: LinkPreviewDetectorHelper.test_debug_linkPreviewDetector()!, managedObjectContext: managedObjectContext)

        let imageFetchPredicate = NSPredicate(format: "%K == %d",ZMClientMessageLinkPreviewStateKey, ZMLinkPreviewState.Downloaded.rawValue)
        let needsProccessing = NSPredicate { object, _ in
            guard let message = object as? ZMClientMessage else { return false }
            return nil != managedObjectContext.zm_imageAssetCache.assetData(message.nonce, format: .Original, encrypted: false)
        }
        
        let previewImagePreprocessor = ZMImagePreprocessingTracker(
            managedObjectContext:       managedObjectContext,
            imageProcessingQueue:       NSOperationQueue(),
            fetchPredicate:             imageFetchPredicate,
            needsProcessingPredicate:   needsProccessing,
            entityClass:                ZMClientMessage.self
        )
        self.init(authenticationStatus:authenticationStatus, linkPreviewPreprocessor: linkPreviewPreprocessor, previewImagePreprocessor:  previewImagePreprocessor, managedObjectContext: managedObjectContext)
    }
    
    init(authenticationStatus: AuthenticationStatusProvider, linkPreviewPreprocessor: LinkPreviewPreprocessor, previewImagePreprocessor: ZMImagePreprocessingTracker, managedObjectContext: NSManagedObjectContext)
    {
        self.authenticationStatus = authenticationStatus
        self.linkPreviewPreprocessor = linkPreviewPreprocessor
        self.previewImagePreprocessor = previewImagePreprocessor
        
        super.init(managedObjectContext: managedObjectContext)
        
        self.assetUpstreamSync = ZMUpstreamModifiedObjectSync(
            transcoder: self,
            entityName: ZMClientMessage.entityName(),
            updatePredicate: predicateForAssetUpload,
            filter: filterForAssetUpload,
            keysToSync: [ZMClientMessageLinkPreviewStateKey],
            managedObjectContext: managedObjectContext)

    }
    
    var predicateForAssetUpload : NSPredicate {
        return NSPredicate(format: "%K == %d", ZMClientMessageLinkPreviewStateKey, ZMLinkPreviewState.Processed.rawValue)
    }
    
    var filterForAssetUpload: NSPredicate {
        return NSPredicate { object, _ in
            guard let message = object as? ZMClientMessage else { return false }
            return nil != self.managedObjectContext.zm_imageAssetCache.assetData(message.nonce, format: .Medium, encrypted: true)
        }
    }
    
    public var contextChangeTrackers : [ZMContextChangeTracker] {
        return [self.linkPreviewPreprocessor, self.previewImagePreprocessor, self.assetUpstreamSync]
    }
    
    func nextRequest() -> ZMTransportRequest? {
        guard self.authenticationStatus.currentPhase == .Authenticated else { return nil }
        return self.assetUpstreamSync.nextRequest()
    }
}

extension LinkPreviewAssetUploadRequestStrategy : ZMUpstreamTranscoder {
    
    public func requestForUpdatingObject(managedObject: ZMManagedObject, forKeys keys: Set<NSObject>) -> ZMUpstreamRequest? {
        guard let message = managedObject as? ZMClientMessage else { return nil }
        guard keys.contains(ZMClientMessageLinkPreviewStateKey) else { return nil }

        guard let imageData = managedObjectContext.zm_imageAssetCache.assetData(message.nonce, format: .Medium, encrypted: true) else { return nil }
        return ZMUpstreamRequest(keys: [ZMClientMessageLinkPreviewStateKey], transportRequest: requestFactory.upstreamRequestForAsset(withData: imageData))
    }
    
    public func requestForInsertingObject(managedObject: ZMManagedObject, forKeys keys: Set<NSObject>?) -> ZMUpstreamRequest? {
        return nil
    }
    
    public func shouldProcessUpdatesBeforeInserts() -> Bool {
        return false
    }
    
    public func objectToRefetchForFailedUpdateOfObject(managedObject: ZMManagedObject) -> ZMManagedObject? {
        return nil
    }
    
    public func updateUpdatedObject(managedObject: ZMManagedObject, requestUserInfo: [NSObject : AnyObject]?, response: ZMTransportResponse, keysToParse: Set<NSObject>) -> Bool {
        guard let message = managedObject as? ZMClientMessage else { return false }
        guard let payload = response.payload.asDictionary(), assetKey = payload["key"] as? String else { fatal("No asset ID present in payload: \(response.payload)") }
        
        if let linkPreview = message.genericMessage?.text.linkPreview.first as? ZMLinkPreview {
            let updatedPreview = linkPreview.update(withAssetKey: assetKey, assetToken: payload["token"] as? String)
            let genericMessage = ZMGenericMessage(text: message.textMessageData?.messageText, linkPreview: updatedPreview, nonce: message.nonce.transportString())
            message.addData(genericMessage.data())
            message.linkPreviewState = .Uploaded
        } else {
            message.linkPreviewState = .Done
        }

        return false
    }
    
    public func updateInsertedObject(managedObject: ZMManagedObject, request upstreamRequest: ZMUpstreamRequest, response: ZMTransportResponse) {
        // nop
    }
    
}
