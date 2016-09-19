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

@testable import zmessaging

class ImageDownloadRequestStrategyTests: MessagingTest {
    
    fileprivate var authenticationStatus : MockAuthenticationStatus!
    fileprivate var clientRegistrationStatus : ZMMockClientRegistrationStatus!
    fileprivate var sut : ImageDownloadRequestStrategy!
    
    override func setUp() {
        super.setUp()
        
        self.authenticationStatus = MockAuthenticationStatus(phase: .authenticated)
        self.sut = ImageDownloadRequestStrategy(authenticationStatus: authenticationStatus , managedObjectContext: self.syncMOC)
        
        createSelfClient()
    }
    
    func createImageMessage(withAssetId assetId: UUID?) -> ZMAssetClientMessage {
        let conversation = ZMConversation.insertNewObject(in: syncMOC)
        conversation.remoteIdentifier = UUID.create()
        
        let message = conversation.appendOTRMessage(withImageData: verySmallJPEGData(), nonce: UUID.create())
        
        let imageData = message.imageAssetStorage?.originalImageData()
        let imageSize = ZMImagePreprocessor.sizeOfPrerotatedImage(with: imageData)
        let properties = ZMIImageProperties(size: imageSize, length: UInt(imageData!.count), mimeType: "image/jpeg")
        let keys = ZMImageAssetEncryptionKeys(otrKey: Data.randomEncryptionKey(), macKey: Data.zmRandomSHA256Key(), mac: Data.zmRandomSHA256Key())
        
        message.add(ZMGenericMessage(
            mediumImageProperties: properties,
            processedImageProperties: properties,
            encryptionKeys: keys,
            nonce: message.nonce.transportString(),
            format: .medium))
        
        message.add(ZMGenericMessage(
            mediumImageProperties: properties,
            processedImageProperties: properties,
            encryptionKeys: keys,
            nonce: message.nonce.transportString(),
            format: .preview))
    
        message.resetLocallyModifiedKeys(Set(arrayLiteral: ZMAssetClientMessageUploadedStateKey))
        message.assetId = assetId
        syncMOC.saveOrRollback()
        
        return message
    }
    
    func createFileMessage() -> ZMAssetClientMessage {
        let conversation = ZMConversation.insertNewObject(in: syncMOC)
        conversation.remoteIdentifier = UUID.create()
        
        let nonce = UUID.create()
        let fileURL = Bundle(for: ImageDownloadRequestStrategyTests.self).url(forResource: "Lorem Ipsum", withExtension: "txt")!
        let metadata = ZMFileMetadata(fileURL: fileURL)
        let message = conversation.appendOTRMessage(with: metadata, nonce: nonce)
        
        syncMOC.saveOrRollback()
        
        return message
    }
    
    func requestToDownloadAsset(withMessage message: ZMAssetClientMessage) -> ZMTransportRequest {
        // remove image data or it won't be downloaded
        self.syncMOC.zm_imageAssetCache.deleteAssetData(message.nonce, format: .original, encrypted: false)
        
        message.requestImageDownload()
        
        return sut.nextRequest()!
    }
    
    func testRequestToDownloadAsset_whenAssetIdIsAvailable() {
        // given
        var assetId: UUID?
        var conversationId : UUID?
        
        self.syncMOC.performGroupedBlock {
            assetId = UUID.create()
            let message = self.createImageMessage(withAssetId: assetId!)
            conversationId = message.conversation!.remoteIdentifier
            
            // remove image data or it won't be downloaded
            self.syncMOC.zm_imageAssetCache.deleteAssetData(message.nonce, format: .Original, encrypted: false)
            message.requestImageDownload()
        }
        
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // when
        guard let request = self.sut.nextRequest() else { XCTFail(); return }
        
        // then
        XCTAssertNotNil(request)
        XCTAssertEqual(request.path, "/conversations/\(conversationId!.transportString())/otr/assets/\(assetId!.transportString())")
    }
    
    func testRequestToDownloadAssetIsNotCreated_whenAssetIdIsNotAvailable() {
        // given
        self.syncMOC.performGroupedBlock {
            let message = self.createImageMessage(withAssetId: nil)
            
            // remove image data or it won't be downloaded
            self.syncMOC.zm_imageAssetCache.deleteAssetData(message.nonce, format: .original, encrypted: false)
            message.requestImageDownload()
        }
        
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // when
        let request = self.sut.nextRequest()
        
        // then
        XCTAssertNil(request)
    }
    
    func testRequestToDownloadFileAssetIsNotCreated() {
        syncMOC.performGroupedBlock {
            // given
            let message = self.createFileMessage()
            message.transferState = .uploaded
            message.delivered = true
            message.assetId = UUID.create()
            
            // when
            let request = self.sut.nextRequest()
            
            // then
            XCTAssertNil(request)
        }
        
         XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
    }
    
    func testMessageImageDataIsUpdated_whenParsingAssetDownloadResponse() {
        self.syncMOC.performGroupedBlock {
            // given
            let imageData = self.verySmallJPEGData()
            let message = self.createImageMessage(withAssetId: UUID.create())
            message.isEncrypted = false
            let response = ZMTransportResponse(imageData: imageData, HTTPstatus: 200, transportSessionError: nil, headers: nil)
            
            // when
            self.sut.updateObject(message, withResponse: response, downstreamSync: nil)
            let storedData = message.imageAssetStorage?.imageDataForFormat(.Medium, encrypted: false)
            
            // then
            XCTAssertEqual(storedData, imageData)
            
        }
        
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
    }
    
    func testMessageIsDeleted_whenDownloadRequestFail() {
        self.syncMOC.performGroupedBlock { 
            // given
            let message = self.createImageMessage(withAssetId: UUID.create())
            
            // when
            self.sut.deleteObject(message, downstreamSync: nil)
            
            // then
            XCTAssertTrue(message.deleted)
        }
        
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
    }
    
}
