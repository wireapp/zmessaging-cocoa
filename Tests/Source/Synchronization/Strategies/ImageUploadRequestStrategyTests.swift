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

class ImageUploadMockClientRegistrationStatus : ZMMockClientRegistrationStatus {
    
    override func didDetectCurrentClientDeletion() {
        // nop
    }
    
}

class ImageUploadRequestStrategyTests: MessagingTest {
    
    private var authenticationStatus : MockAuthenticationStatus!
    private var clientRegistrationStatus : ZMMockClientRegistrationStatus!
    private var sut : ImageUploadRequestStrategy!
    
    override func setUp() {
        super.setUp()
        
        self.authenticationStatus = MockAuthenticationStatus(phase: .Authenticated)
        self.clientRegistrationStatus = ImageUploadMockClientRegistrationStatus()
        self.clientRegistrationStatus.mockPhase = .Registered
        self.sut = ImageUploadRequestStrategy(authenticationStatus: authenticationStatus, clientRegistrationStatus: clientRegistrationStatus, managedObjectContext: self.syncMOC)
        
        createSelfClient()
    }
    
    /// MARK - Helpers
    
    func createImageMessage() -> ZMAssetClientMessage {
        let conversation = ZMConversation.insertNewObjectInManagedObjectContext(syncMOC)
        conversation!.remoteIdentifier = NSUUID.createUUID()
        
        let message = conversation.appendOTRMessageWithImageData(verySmallJPEGData(), nonce: NSUUID.createUUID())
        syncMOC.saveOrRollback()
        
        return message
    }
    
    func prepare(message: ZMAssetClientMessage, forUploadingFormat format: ZMImageFormat) {
        let otherFormat : ZMImageFormat = format == .Medium ? .Preview : .Medium
        
        let properties = ZMIImageProperties(size: message.imageAssetStorage!.originalImageSize(), length: 1000, mimeType: "image/jpg")
        message.imageAssetStorage?.setImageData(message.imageAssetStorage?.originalImageData(), forFormat:format, properties: properties)
        message.imageAssetStorage?.setImageData(message.imageAssetStorage?.originalImageData(), forFormat:otherFormat, properties: properties)
        message.uploadState = format == .Medium ? .UploadingFullAsset : .UploadingPlaceholder
        
        syncMOC.saveOrRollback()
    }
        
    func assertRequestIsGeneratedToSendOTRAssetWhenAMessageIsInserted(withFormat format: ZMImageFormat, block: (message: ZMMessage) -> Void) {
        
        syncMOC.performGroupedBlock { 
            let message = self.createImageMessage()
            let conversationId = message.conversation!.remoteIdentifier.transportString()
            
            self.prepare(message, forUploadingFormat: format)
            
            // when
            block(message: message)
            let request = self.sut.nextRequest()
            
            // then
            let expectedPath = "/conversations/\(conversationId)/otr/assets"
            XCTAssertEqual(expectedPath, request?.path)
            
            let metadataItem = request?.multipartBodyItems().first as! ZMMultipartBodyItem
            let messageFromSync = self.sut.managedObjectContext.objectWithID(message.objectID) as! ZMAssetClientMessage
            let messageDataFromSync = messageFromSync.encryptedMessagePayloadForImageFormat(format)?.data()
            
            XCTAssertEqual(metadataItem.data, messageDataFromSync)
        }
        
        XCTAssertTrue(waitForAllGroupsToBeEmptyWithTimeout(0.5))
    }
 
    func testRequestIsGeneratedToSendAsset_whenOTRAssetIsInsertedOnInitialization() {
        assertRequestIsGeneratedToSendOTRAssetWhenAMessageIsInserted(withFormat: .Medium) { (message) in
            ZMChangeTrackerBootstrap.bootStrapChangeTrackers(self.sut.contextChangeTrackers, onContext: self.syncMOC)
        }
    }
    
    func testRequestIsGeneratedToSendAsset_whenOTRAssetIsInsertedOnObjectsDidChange() {
        assertRequestIsGeneratedToSendOTRAssetWhenAMessageIsInserted(withFormat: .Medium) { (message) in
            let messageFromSyncMoc = self.sut.managedObjectContext .objectWithID(message.objectID)
            
            for changeTracker in self.sut.contextChangeTrackers {
                changeTracker.objectsDidChange(Set(arrayLiteral: messageFromSyncMoc))
            }
        }
    }
        
    func assertMessageIsDeleted_whenFailedToCreatedUpdateRequestAndNoOriginalDataStored(format: ZMImageFormat) {
        syncMOC.performGroupedBlock {
            //given
            let message = self.createImageMessage()
            let properties = ZMIImageProperties(size: CGSizeMake(100, 100), length: UInt(100), mimeType: "")
            
            message.addGenericMessage(ZMGenericMessage(
                mediumImageProperties: properties,
                processedImageProperties: properties,
                encryptionKeys: nil,
                nonce: message.nonce.transportString(),
                format: format))
            
            // when
            switch format {
            case .Preview:
                message.uploadState = .UploadingPlaceholder
            case .Medium:
                message.uploadState = .UploadingFullAsset
            default:
                break
            }
            
            self.sut.requestForUpdatingObject(message, forKeys: Set(arrayLiteral: ZMAssetClientMessageUploadedStateKey))
            
            // then
            XCTAssertTrue(message.isZombieObject)
        }
        
        XCTAssertTrue(waitForAllGroupsToBeEmptyWithTimeout(0.5))
    }
    
    func testMessageIsDeleted_whenFailedToCreatedUpdateRequestForMediumFormatAndNoOriginalDataStored() {
        assertMessageIsDeleted_whenFailedToCreatedUpdateRequestAndNoOriginalDataStored(.Medium)
    }
    
    func testMessageIsDeleted_whenFailedToCreatedUpdateRequestForPreviewFormatAndNoOriginalDataStored() {
        assertMessageIsDeleted_whenFailedToCreatedUpdateRequestAndNoOriginalDataStored(.Preview)
    }
    
    func testNoRequestIsGenerated_whenProcessingIsNeeded() {
        syncMOC.performGroupedBlock {
            // given
            let message = self.createImageMessage()
            self.prepare(message, forUploadingFormat: .Medium)
            
            for changeTracker in self.sut.contextChangeTrackers {
                changeTracker.objectsDidChange(Set(arrayLiteral: message))
            }
            
            // when
            message.managedObjectContext?.zm_imageAssetCache.deleteAssetData(message.nonce, format: .Medium, encrypted: true)
            let request = self.sut.nextRequest()
            
            // then
            XCTAssertNil(request)
        }
        
        XCTAssertTrue(waitForAllGroupsToBeEmptyWithTimeout(0.5))
    }
    
    func testNeedsToUploadMediumKeyIsReset_whenParsingTheResponseForPreviewImage() {
        syncMOC.performGroupedBlock { 
            // given
            let key = ZMAssetClientMessageUploadedStateKey
            let message = self.createImageMessage()
            message.uploadState = .UploadingPlaceholder
            XCTAssertTrue(message.hasLocalModificationsForKey(key))
            
            let responsePayload = ["time" : NSDate().transportString()]
            let response = ZMTransportResponse(payload: responsePayload, HTTPstatus: 200, transportSessionError: nil)
            
            // when
            self.sut.updateUpdatedObject(message, requestUserInfo: nil, response: response, keysToParse: Set(arrayLiteral: key))
            
            // then
            XCTAssertTrue(message.hasLocalModificationsForKey(key))
            XCTAssertEqual(message.uploadState, ZMAssetUploadState.UploadingFullAsset)
        }
        
        XCTAssertTrue(waitForAllGroupsToBeEmptyWithTimeout(0.5))
    }
    
    func testAssetIdIsNotSet_whenParsingTheResponseForPreviewImage() {
        syncMOC.performGroupedBlock {
            // given
            let message = self.createImageMessage()
            message.uploadState = .UploadingPlaceholder
            
            let responsePayload = ["time" : NSDate().transportString()]
            let response = ZMTransportResponse(payload: responsePayload, HTTPstatus: 200, transportSessionError: nil)
            
            // when
            self.sut.updateUpdatedObject(message, requestUserInfo: nil, response: response, keysToParse: Set(arrayLiteral: ZMAssetClientMessageUploadedStateKey))
            
            // then
            XCTAssertNil(message.assetId)
        }
        
        XCTAssertTrue(waitForAllGroupsToBeEmptyWithTimeout(0.5))
    }
    
    func testNeedsToUploadMediumKeyIsReset_whenParsingTheResponseForMediumImage() {
        syncMOC.performGroupedBlock {
            // given
            let key = ZMAssetClientMessageUploadedStateKey
            let message = self.createImageMessage()
            let assetId = NSUUID.createUUID()
            message.uploadState = .UploadingFullAsset
            XCTAssertTrue(message.hasLocalModificationsForKey(key))
            
            let responsePayload = ["time" : NSDate().transportString()]
            let responseHeader = ["Location" : assetId.transportString()]
            let response = ZMTransportResponse(payload: responsePayload, HTTPstatus: 200, transportSessionError: nil, headers: responseHeader)
            
            //when
            self.sut.updateUpdatedObject(message, requestUserInfo: nil, response: response, keysToParse: Set(arrayLiteral: key))
            
            // then
            XCTAssertFalse(message.hasLocalModificationsForKey(key))
            XCTAssertEqual(message.uploadState, ZMAssetUploadState.Done)
        }
        
        XCTAssertTrue(waitForAllGroupsToBeEmptyWithTimeout(0.5))
    }
    
    func testAssetIdIsSet_whenParsingTheResponseForMediumImage() {
        syncMOC.performGroupedBlock {
            // given
            let message = self.createImageMessage()
            let assetId = NSUUID.createUUID()
            message.uploadState = .UploadingFullAsset
            
            let responsePayload = ["time" : NSDate().transportString()]
            let responseHeader = ["Location" : assetId.transportString()]
            let response = ZMTransportResponse(payload: responsePayload, HTTPstatus: 200, transportSessionError: nil, headers: responseHeader)
            
            //when
            self.sut.updateUpdatedObject(message, requestUserInfo: nil, response: response, keysToParse: Set(arrayLiteral: ZMAssetClientMessageUploadedStateKey))
            
            // then
            XCTAssertEqual(message.assetId, assetId)
        }
        
        XCTAssertTrue(waitForAllGroupsToBeEmptyWithTimeout(0.5))
    }
    
    func testKeysAreReset_whenRequestFailsBecauseSelfClientWasDeleted() {
        self.syncMOC.performGroupedBlock { 
            // given
            let keys = Set(arrayLiteral: ZMAssetClientMessageUploadedStateKey)
            let message = self.createImageMessage()
            
            message.setLocallyModifiedKeys(keys)
            let request = ZMUpstreamRequest(transportRequest: ZMTransportRequest(getFromPath: "foo"))
            
            // when
            let response = ZMTransportResponse(payload: ["label" : "unknown-client"], HTTPstatus: 403, transportSessionError: nil)
            self.sut.shouldRetryToSyncAfterFailedToUpdateObject(message, request: request, response: response, keysToParse: keys)
            
            // then
            XCTAssertEqual(message.uploadState, ZMAssetUploadState.UploadingFailed);
            XCTAssertTrue(message.hasLocalModificationsForKeys(keys))
            XCTAssertFalse(message.conversation!.needsToBeUpdatedFromBackend)
        }
        
        XCTAssertTrue(waitForAllGroupsToBeEmptyWithTimeout(0.5))
    }
    
}