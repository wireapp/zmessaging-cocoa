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

@objc public protocol LinkPreviewDetectorType {
    func downloadLinkPreviews(inText text: String, completion: [LinkPreview] -> Void)
}

extension LinkPreviewDetector: LinkPreviewDetectorType {}

@objc public class LinkPreviewPreprocessor : NSObject, ZMContextChangeTracker {
        
    /// List of objects currently being processed
    private var objectsBeingProcessed = Set<ZMClientMessage>()
    private let linkPreviewDetector: LinkPreviewDetectorType

    let managedObjectContext : NSManagedObjectContext
    
    public init(linkPreviewDetector: LinkPreviewDetectorType, managedObjectContext: NSManagedObjectContext) {
        self.linkPreviewDetector = linkPreviewDetector
        self.managedObjectContext = managedObjectContext
        super.init()
    }

    public func objectsDidChange(objects: Set<NSObject>) {
        processObjects(objects)
    }
    
    public func fetchRequestForTrackedObjects() -> NSFetchRequest? {
        let predicate = NSPredicate(format: "%K == %d", ZMClientMessageLinkPreviewStateKey, ZMLinkPreviewState.WaitingToBeProcessed.rawValue)
        return ZMClientMessage.sortedFetchRequestWithPredicate(predicate)
    }
    
    public func addTrackedObjects(objects: Set<NSObject>) {
        processObjects(objects)
    }
    
    func processObjects(objects: Set<NSObject>) {
        objects.flatMap(linkPreviewsToPreprocess)
            .filter { !self.objectsBeingProcessed.contains($0) }
            .forEach(processMessage)
    }
    
    func linkPreviewsToPreprocess(object: NSObject) -> ZMClientMessage? {
        guard let message = object as? ZMClientMessage else { return nil }
        return message.linkPreviewState == .WaitingToBeProcessed ? message : nil
    }
    
    func processMessage(message: ZMClientMessage) {
        objectsBeingProcessed.insert(message)
        
        if let messageText = (message as ZMConversationMessage).textMessageData?.messageText {
            linkPreviewDetector.downloadLinkPreviews(inText: messageText) { [weak self] linkPreviews in
                self?.managedObjectContext.performGroupedBlock({
                    self?.didProcessMessage(message, linkPreviews: linkPreviews)
                })
            }
        } else {
            didProcessMessage(message, linkPreviews: [])
        }
    }
    
    func didProcessMessage(message: ZMClientMessage, linkPreviews: [LinkPreview]) {
        objectsBeingProcessed.remove(message)
        
        if let preview = linkPreviews.first {
            let updatedMessage = ZMGenericMessage(text: message.textMessageData?.messageText, linkPreview: preview.protocolBuffer, nonce: message.nonce.transportString())
            message.addData(updatedMessage.data())
            
            if let imageData = preview.imageData.first {
                managedObjectContext.zm_imageAssetCache.storeAssetData(message.nonce, format:.Original, encrypted: false, data: imageData)
                message.linkPreviewState = .Downloaded
            } else {
                message.linkPreviewState = .Uploaded
            }
        } else {
            message.linkPreviewState = .Done
        }
        
        // The change processor is called as a response to a context save, 
        // which is why we need to enque a save maually here
        managedObjectContext.enqueueDelayedSave()
    }
}
