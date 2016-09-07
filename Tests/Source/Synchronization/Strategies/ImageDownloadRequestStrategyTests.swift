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
    
    private var authenticationStatus : MockAuthenticationStatus!
    private var clientRegistrationStatus : ZMMockClientRegistrationStatus!
    private var sut : ImageDownloadRequestStrategy!
    
    override func setUp() {
        super.setUp()
        
        self.authenticationStatus = MockAuthenticationStatus(phase: .Authenticated)
        self.sut = ImageDownloadRequestStrategy(authenticationStatus: authenticationStatus , managedObjectContext: self.syncMOC)
        
        createSelfClient()
    }
    
    func createImageMessage(withAssetId assetId: NSUUID?) -> ZMAssetClientMessage {
        let conversation = ZMConversation.insertNewObjectInManagedObjectContext(syncMOC)
        conversation!.remoteIdentifier = NSUUID.createUUID()
        
        let message = conversation.appendOTRMessageWithImageData(verySmallJPEGData(), nonce: NSUUID.createUUID())
        
        let imageData = message.imageAssetStorage?.originalImageData()
        let imageSize = ZMImagePreprocessor.sizeOfPrerotatedImageWithData(imageData)
        let properties = ZMIImageProperties(size: imageSize, length: UInt(imageData!.length), mimeType: "image/jpeg")
        let keys = ZMImageAssetEncryptionKeys(otrKey: NSData.randomEncryptionKey(), macKey: NSData.zmRandomSHA256Key(), mac: NSData.zmRandomSHA256Key())
        
        message.addGenericMessage(ZMGenericMessage(
            mediumImageProperties: properties,
            processedImageProperties: properties,
            encryptionKeys: keys,
            nonce: message.nonce.transportString(),
            format: .Medium))
        
        message.addGenericMessage(ZMGenericMessage(
            mediumImageProperties: properties,
            processedImageProperties: properties,
            encryptionKeys: keys,
            nonce: message.nonce.transportString(),
            format: .Preview))
    
        message.resetLocallyModifiedKeys(Set(arrayLiteral: ZMAssetClientMessageUploadedStateKey))
        message.assetId = assetId
        
        syncMOC.saveOrRollback()
        
        return message
    }
    
    func createFileMessage() -> ZMAssetClientMessage {
        let conversation = ZMConversation.insertNewObjectInManagedObjectContext(syncMOC)
        conversation!.remoteIdentifier = NSUUID.createUUID()
        
        let nonce = NSUUID.createUUID()
        let fileURL = NSBundle(forClass: ImageDownloadRequestStrategyTests.self).URLForResource("Lorem Ipsum", withExtension: "txt")!
        let metadata = ZMFileMetadata(fileURL: fileURL)
        let message = conversation!.appendOTRMessageWithFileMetadata(metadata, nonce: nonce)
        
        syncMOC.saveOrRollback()
        
        return message
    }
    
    func requestToDownloadAsset(withMessage message: ZMAssetClientMessage) -> ZMTransportRequest {
        // remove image data or it won't be downloaded
        self.syncMOC.zm_imageAssetCache.deleteAssetData(message.nonce, format: .Original, encrypted: false)
        
        message.requestImageDownload()
        
        return sut.nextRequest()!
    }
    
    func testRequestToDownloadAsset_whenAssetIdIsAvailable() {
        // given
        var assetId: NSUUID?
        var conversationId : NSUUID?
        
        self.syncMOC.performGroupedBlock {
            assetId = NSUUID.createUUID()
            let message = self.createImageMessage(withAssetId: assetId!)
            conversationId = message.conversation!.remoteIdentifier
            
            // remove image data or it won't be downloaded
            self.syncMOC.zm_imageAssetCache.deleteAssetData(message.nonce, format: .Original, encrypted: false)
            message.requestImageDownload()
        }
        
        XCTAssertTrue(waitForAllGroupsToBeEmptyWithTimeout(0.5))
        
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
            self.syncMOC.zm_imageAssetCache.deleteAssetData(message.nonce, format: .Original, encrypted: false)
            message.requestImageDownload()
        }
        
        XCTAssertTrue(waitForAllGroupsToBeEmptyWithTimeout(0.5))
        
        // when
        let request = self.sut.nextRequest()
        
        // then
        XCTAssertNil(request)
    }
    
    func testRequestToDownloadFileAssetIsNotCreated() {
        syncMOC.performGroupedBlock {
            // given
            let message = self.createFileMessage()
            message.transferState = .Uploaded
            message.delivered = true
            message.assetId = NSUUID.createUUID()
            
            // when
            let request = self.sut.nextRequest()
            
            // then
            XCTAssertNil(request)
        }
        
         XCTAssertTrue(waitForAllGroupsToBeEmptyWithTimeout(0.5))
    }
    
    func testMessageImageDataIsUpdated_whenParsingAssetDownloadResponse() {
        self.syncMOC.performGroupedBlock {
            // given
            let imageData = self.verySmallJPEGData()
            let message = self.createImageMessage(withAssetId: NSUUID.createUUID())
            message.isEncrypted = false
            let response = ZMTransportResponse(imageData: imageData, HTTPstatus: 200, transportSessionError: nil, headers: nil)
            
            // when
            self.sut.updateObject(message, withResponse: response, downstreamSync: nil)
            let storedData = message.imageAssetStorage?.imageDataForFormat(.Medium, encrypted: false)
            
            // then
            XCTAssertEqual(storedData, imageData)
            
        }
        
        XCTAssertTrue(waitForAllGroupsToBeEmptyWithTimeout(0.5))
    }
    
    func testMessageIsDeleted_whenDownloadRequestFail() {
        self.syncMOC.performGroupedBlock { 
            // given
            let message = self.createImageMessage(withAssetId: NSUUID.createUUID())
            
            // when
            self.sut.deleteObject(message, downstreamSync: nil)
            
            // then
            XCTAssertTrue(message.deleted)
        }
        
        XCTAssertTrue(waitForAllGroupsToBeEmptyWithTimeout(0.5))
    }
    
}
