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

@objc public final class LinkPreviewDetectorHelper : NSObject {
    fileprivate static var _test_debug_linkPreviewDetector : LinkPreviewDetectorType? = nil
    
    @objc public class func test_debug_linkPreviewDetector() -> LinkPreviewDetectorType?
    {
        return _test_debug_linkPreviewDetector
    }
    
    @objc public class func setTest_debug_linkPreviewDetector(_ detectorType: LinkPreviewDetectorType?)
    {
        _test_debug_linkPreviewDetector = detectorType
    }
    
    @objc public class func tearDown()
    {
        _test_debug_linkPreviewDetector = nil
    }
    
}


public final class LinkPreviewAssetUploadRequestStrategy : ZMObjectSyncStrategy, RequestStrategy, ZMContextChangeTrackerSource {
    
    
    
    let requestFactory = AssetRequestFactory()
    
    /// Auth status to know whether we can make requests
    fileprivate let authenticationStatus : AuthenticationStatusProvider
    
    /// Processors
    fileprivate let linkPreviewPreprocessor : LinkPreviewPreprocessor
    fileprivate let previewImagePreprocessor : ZMImagePreprocessingTracker
    
    /// Upstream sync
    fileprivate var assetUpstreamSync : ZMUpstreamModifiedObjectSync!
    
    public convenience init(authenticationStatus: AuthenticationStatusProvider, managedObjectContext: NSManagedObjectContext) {
        
        if nil == LinkPreviewDetectorHelper.test_debug_linkPreviewDetector() {
            LinkPreviewDetectorHelper.setTest_debug_linkPreviewDetector(LinkPreviewDetector(resultsQueue: OperationQueue.current!))
        }
        
        let linkPreviewPreprocessor = LinkPreviewPreprocessor(linkPreviewDetector: LinkPreviewDetectorHelper.test_debug_linkPreviewDetector()!, managedObjectContext: managedObjectContext)

        let imageFetchPredicate = NSPredicate(format: "%K == %d",ZMClientMessageLinkPreviewStateKey, ZMLinkPreviewState.downloaded.rawValue)
        let needsProccessing = NSPredicate { object, _ in
            guard let message = object as? ZMClientMessage else { return false }
            return nil != managedObjectContext.zm_imageAssetCache.assetData(message.nonce, format: .original, encrypted: false)
        }
        
        let previewImagePreprocessor = ZMImagePreprocessingTracker(
            managedObjectContext:       managedObjectContext,
            imageProcessingQueue:       OperationQueue(),
            fetch:             imageFetchPredicate,
            needsProcessingPredicate:   needsProccessing,
            entityClass:                ZMClientMessage.self
        )
        self.init(authenticationStatus:authenticationStatus, linkPreviewPreprocessor: linkPreviewPreprocessor, previewImagePreprocessor:  previewImagePreprocessor!, managedObjectContext: managedObjectContext)
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
            update: predicateForAssetUpload,
            filter: filterForAssetUpload,
            keysToSync: [ZMClientMessageLinkPreviewStateKey],
            managedObjectContext: managedObjectContext)

    }
    
    var predicateForAssetUpload : NSPredicate {
        return NSPredicate(format: "%K == %d", ZMClientMessageLinkPreviewStateKey, ZMLinkPreviewState.processed.rawValue)
    }
    
    var filterForAssetUpload: NSPredicate {
        return NSPredicate { object, _ in
            guard let message = object as? ZMClientMessage else { return false }
            return nil != self.managedObjectContext.zm_imageAssetCache.assetData(message.nonce, format: .medium, encrypted: true)
        }
    }
    
    public var contextChangeTrackers : [ZMContextChangeTracker] {
        return [self.linkPreviewPreprocessor, self.previewImagePreprocessor, self.assetUpstreamSync]
    }
    
    public func nextRequest() -> ZMTransportRequest? {
        guard self.authenticationStatus.currentPhase == .authenticated else { return nil }
        return self.assetUpstreamSync.nextRequest()
    }
}

extension LinkPreviewAssetUploadRequestStrategy : ZMUpstreamTranscoder {
    
    public func request(forUpdating managedObject: ZMManagedObject, forKeys keys: Set<String>) -> ZMUpstreamRequest? {
        guard let message = managedObject as? ZMClientMessage else { return nil }
        guard keys.contains(ZMClientMessageLinkPreviewStateKey) else { return nil }

        guard let imageData = managedObjectContext.zm_imageAssetCache.assetData(message.nonce, format: .medium, encrypted: true) else { return nil }
        return ZMUpstreamRequest(keys: [ZMClientMessageLinkPreviewStateKey], transportRequest: requestFactory.upstreamRequestForAsset(withData: imageData))
    }
    
    public func request(forInserting managedObject: ZMManagedObject, forKeys keys: Set<String>?) -> ZMUpstreamRequest? {
        return nil
    }
    
    public func shouldProcessUpdatesBeforeInserts() -> Bool {
        return false
    }
    
    public func objectToRefetchForFailedUpdate(of managedObject: ZMManagedObject) -> ZMManagedObject? {
        return nil
    }
    
    public func updateUpdatedObject(_ managedObject: ZMManagedObject, requestUserInfo: [AnyHashable: Any]?, response: ZMTransportResponse, keysToParse: Set<String>) -> Bool {
        guard let message = managedObject as? ZMClientMessage else { return false }
        guard let payload = response.payload?.asDictionary(), let assetKey = payload["key"] as? String else { fatal("No asset ID present in payload: \(response.payload)") }
        
        if let linkPreview = message.genericMessage?.text.linkPreview.first as? ZMLinkPreview {
            let updatedPreview = linkPreview.update(withAssetKey: assetKey, assetToken: payload["token"] as? String)
            let genericMessage = ZMGenericMessage(text: (message.textMessageData?.messageText)!, linkPreview: updatedPreview, nonce: message.nonce.transportString())
            message.add(genericMessage.data())
            message.linkPreviewState = .uploaded
        } else {
            message.linkPreviewState = .done
        }

        return false
    }
    
    public func updateInsertedObject(_ managedObject: ZMManagedObject, request upstreamRequest: ZMUpstreamRequest, response: ZMTransportResponse) {
        // nop
    }
    
}
