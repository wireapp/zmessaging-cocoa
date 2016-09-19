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


@objc public final class LinkPreviewPreprocessor : NSObject, ZMContextChangeTracker {
        
    /// List of objects currently being processed
    fileprivate var objectsBeingProcessed = Set<ZMClientMessage>()
    fileprivate let linkPreviewDetector: LinkPreviewDetectorType

    let managedObjectContext : NSManagedObjectContext
    
    public init(linkPreviewDetector: LinkPreviewDetectorType, managedObjectContext: NSManagedObjectContext) {
        self.linkPreviewDetector = linkPreviewDetector
        self.managedObjectContext = managedObjectContext
        super.init()
    }

    public func objectsDidChange(_ objects: Set<NSManagedObject>) {
        processObjects(objects)
    }
    
    public func fetchRequestForTrackedObjects() -> NSFetchRequest<NSFetchRequestResult>? {
        let predicate = NSPredicate(format: "%K == %d", ZMClientMessageLinkPreviewStateKey, ZMLinkPreviewState.waitingToBeProcessed.rawValue)
        return ZMClientMessage.sortedFetchRequest(with: predicate)
    }
    
    public func addTrackedObjects(_ objects: Set<NSManagedObject>) {
        processObjects(objects)
    }
    
    func processObjects(_ objects: Set<NSObject>) {
        objects.flatMap(linkPreviewsToPreprocess)
            .filter { !self.objectsBeingProcessed.contains($0) }
            .forEach(processMessage)
    }
    
    func linkPreviewsToPreprocess(_ object: NSObject) -> ZMClientMessage? {
        guard let message = object as? ZMClientMessage else { return nil }
        return message.linkPreviewState == .waitingToBeProcessed ? message : nil
    }
    
    func processMessage(_ message: ZMClientMessage) {
        objectsBeingProcessed.insert(message)
        
        if let messageText = (message as ZMConversationMessage).textMessageData?.messageText {
            linkPreviewDetector.downloadLinkPreviews?(inText: messageText) { [weak self] linkPreviews in
                self?.managedObjectContext.performGroupedBlock({
                    self?.didProcessMessage(message, linkPreviews: linkPreviews)
                })
            }
        } else {
            didProcessMessage(message, linkPreviews: [])
        }
    }
    
    func didProcessMessage(_ message: ZMClientMessage, linkPreviews: [LinkPreview]) {
        objectsBeingProcessed.remove(message)
        
        if let preview = linkPreviews.first, let messsageText = message.textMessageData?.messageText {
            let updatedMessage = ZMGenericMessage(text: messsageText, linkPreview: preview.protocolBuffer, nonce: message.nonce.transportString())
            message.add(updatedMessage.data())
            
            if let imageData = preview.imageData.first {
                managedObjectContext.zm_imageAssetCache.storeAssetData(message.nonce, format:.original, encrypted: false, data: imageData)
                message.linkPreviewState = .downloaded
            } else {
                message.linkPreviewState = .uploaded
            }
        } else {
            message.linkPreviewState = .done
        }
        
        // The change processor is called as a response to a context save, 
        // which is why we need to enque a save maually here
        managedObjectContext.enqueueDelayedSave()
    }
}
