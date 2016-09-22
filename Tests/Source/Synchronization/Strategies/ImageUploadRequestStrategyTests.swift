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
    
    fileprivate var authenticationStatus : MockAuthenticationStatus!
    fileprivate var clientRegistrationStatus : ZMMockClientRegistrationStatus!
    fileprivate var sut : ImageUploadRequestStrategy!
    
    override func setUp() {
        super.setUp()
        
        self.authenticationStatus = MockAuthenticationStatus(phase: .authenticated)
        self.clientRegistrationStatus = ImageUploadMockClientRegistrationStatus()
        self.clientRegistrationStatus.mockPhase = .registered
        self.sut = ImageUploadRequestStrategy(authenticationStatus: authenticationStatus, clientRegistrationStatus: clientRegistrationStatus, managedObjectContext: self.syncMOC)
        
        createSelfClient()
    }
    
    /// MARK - Helpers
    
    func createImageMessage() -> ZMAssetClientMessage {
        let conversation = ZMConversation.insertNewObject(in: syncMOC)
        conversation.remoteIdentifier = UUID.create()
        
        let message = conversation.appendOTRMessage(withImageData: verySmallJPEGData(), nonce: UUID.create())
        syncMOC.saveOrRollback()
        
        return message
    }
    
    func prepare(_ message: ZMAssetClientMessage, forUploadingFormat format: ZMImageFormat) {
        let otherFormat : ZMImageFormat = format == .medium ? .preview : .medium
        
        let properties = ZMIImageProperties(size: message.imageAssetStorage!.originalImageSize(), length: 1000, mimeType: "image/jpg")
        message.imageAssetStorage?.setImageData(message.imageAssetStorage?.originalImageData(), for:format, properties: properties)
        message.imageAssetStorage?.setImageData(message.imageAssetStorage?.originalImageData(), for:otherFormat, properties: properties)
        message.uploadState = format == .medium ? .uploadingFullAsset : .uploadingPlaceholder
        
        syncMOC.saveOrRollback()
    }
        
    func assertRequestIsGeneratedToSendOTRAssetWhenAMessageIsInserted(withFormat format: ZMImageFormat, block: @escaping (_ message: ZMMessage) -> Void) {
        
        syncMOC.performGroupedBlock { 
            let message = self.createImageMessage()
            let conversationId = message.conversation!.remoteIdentifier!.transportString()
            
            self.prepare(message, forUploadingFormat: format)
            
            // when
            block(message)
            let request = self.sut.nextRequest()
            
            // then
            let expectedPath = "/conversations/\(conversationId)/otr/assets"
            XCTAssertEqual(expectedPath, request?.path)
            
            let metadataItem = request?.multipartBodyItems()?.first as! ZMMultipartBodyItem
            let messageFromSync = self.sut.managedObjectContext.object(with: message.objectID) as! ZMAssetClientMessage
            let messageDataFromSync = messageFromSync.encryptedMessagePayloadForImageFormat(format)?.data()
            
            XCTAssertEqual(metadataItem.data, messageDataFromSync)
        }
        
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
    }
 
    func testRequestIsGeneratedToSendAsset_whenOTRAssetIsInsertedOnInitialization() {
        assertRequestIsGeneratedToSendOTRAssetWhenAMessageIsInserted(withFormat: .medium) { (message) in
            ZMChangeTrackerBootstrap.bootStrapChangeTrackers(self.sut.contextChangeTrackers, on: self.syncMOC)
        }
    }
    
    func testRequestIsGeneratedToSendAsset_whenOTRAssetIsInsertedOnObjectsDidChange() {
        assertRequestIsGeneratedToSendOTRAssetWhenAMessageIsInserted(withFormat: .medium) { (message) in
            let messageFromSyncMoc = self.sut.managedObjectContext .object(with: message.objectID)
            
            for changeTracker in self.sut.contextChangeTrackers {
                changeTracker.objectsDidChange(Set(arrayLiteral: messageFromSyncMoc))
            }
        }
    }
        
    func assertMessageIsDeleted_whenFailedToCreatedUpdateRequestAndNoOriginalDataStored(_ format: ZMImageFormat) {
        syncMOC.performGroupedBlock {
            //given
            let message = self.createImageMessage()
            let properties = ZMIImageProperties(size: CGSize(width: 100, height: 100), length: UInt(100), mimeType: "")
            
            message.add(ZMGenericMessage(
                mediumImageProperties: properties,
                processedImageProperties: properties,
                encryptionKeys: nil,
                nonce: message.nonce.transportString(),
                format: format))
            
            // when
            switch format {
            case .preview:
                message.uploadState = .uploadingPlaceholder
            case .medium:
                message.uploadState = .uploadingFullAsset
            default:
                break
            }
            
            _ = self.sut.request(forUpdating: message, forKeys: Set(arrayLiteral: ZMAssetClientMessageUploadedStateKey))
            
            // then
            XCTAssertTrue(message.isZombieObject)
        }
        
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
    }
    
    func testMessageIsDeleted_whenFailedToCreatedUpdateRequestForMediumFormatAndNoOriginalDataStored() {
        assertMessageIsDeleted_whenFailedToCreatedUpdateRequestAndNoOriginalDataStored(.medium)
    }
    
    func testMessageIsDeleted_whenFailedToCreatedUpdateRequestForPreviewFormatAndNoOriginalDataStored() {
        assertMessageIsDeleted_whenFailedToCreatedUpdateRequestAndNoOriginalDataStored(.preview)
    }
    
    func testNoRequestIsGenerated_whenProcessingIsNeeded() {
        syncMOC.performGroupedBlock {
            // given
            let message = self.createImageMessage()
            self.prepare(message, forUploadingFormat: .medium)
            
            for changeTracker in self.sut.contextChangeTrackers {
                changeTracker.objectsDidChange(Set(arrayLiteral: message))
            }
            
            // when
            message.managedObjectContext?.zm_imageAssetCache.deleteAssetData(message.nonce, format: .medium, encrypted: true)
            let request = self.sut.nextRequest()
            
            // then
            XCTAssertNil(request)
        }
        
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
    }
    
    func testNeedsToUploadMediumKeyIsReset_whenParsingTheResponseForPreviewImage() {
        syncMOC.performGroupedBlock { 
            // given
            let key = ZMAssetClientMessageUploadedStateKey
            let message = self.createImageMessage()
            message.uploadState = .uploadingPlaceholder
            XCTAssertTrue(message.hasLocalModifications(forKey: key))
            
            let responsePayload = ["time" : Date().transportString()] as ZMTransportData
            let response = ZMTransportResponse(payload: responsePayload, httpStatus: 200, transportSessionError: nil)
            
            // when
            _ = self.sut.updateUpdatedObject(message, requestUserInfo: nil, response: response, keysToParse: Set(arrayLiteral: key))
            
            // then
            XCTAssertTrue(message.hasLocalModifications(forKey: key))
            XCTAssertEqual(message.uploadState, ZMAssetUploadState.uploadingFullAsset)
        }
        
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
    }
    
    func testAssetIdIsNotSet_whenParsingTheResponseForPreviewImage() {
        syncMOC.performGroupedBlock {
            // given
            let message = self.createImageMessage()
            message.uploadState = .uploadingPlaceholder
            
            let responsePayload = ["time" : Date().transportString()] as ZMTransportData
            let response = ZMTransportResponse(payload: responsePayload, httpStatus: 200, transportSessionError: nil)
            
            // when
            _ = self.sut.updateUpdatedObject(message, requestUserInfo: nil, response: response, keysToParse: Set(arrayLiteral: ZMAssetClientMessageUploadedStateKey))
            
            // then
            XCTAssertNil(message.assetId)
        }
        
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
    }
    
    func testNeedsToUploadMediumKeyIsReset_whenParsingTheResponseForMediumImage() {
        syncMOC.performGroupedBlock {
            // given
            let key = ZMAssetClientMessageUploadedStateKey
            let message = self.createImageMessage()
            let assetId = UUID.create()
            message.uploadState = .uploadingFullAsset
            XCTAssertTrue(message.hasLocalModifications(forKey: key))
            
            let responsePayload = ["time" : Date().transportString()] as ZMTransportData
            let responseHeader = ["Location" : assetId.transportString()]
            let response = ZMTransportResponse(payload: responsePayload, httpStatus: 200, transportSessionError: nil, headers: responseHeader)
            
            //when
            _ = self.sut.updateUpdatedObject(message, requestUserInfo: nil, response: response, keysToParse: Set(arrayLiteral: key))
            
            // then
            XCTAssertFalse(message.hasLocalModifications(forKey: key))
            XCTAssertEqual(message.uploadState, ZMAssetUploadState.done)
        }
        
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
    }
    
    func testAssetIdIsSet_whenParsingTheResponseForMediumImage() {
        syncMOC.performGroupedBlock {
            // given
            let message = self.createImageMessage()
            let assetId = UUID.create()
            message.uploadState = .uploadingFullAsset
            
            let responsePayload = ["time" : Date().transportString()] as ZMTransportData
            let responseHeader = ["Location" : assetId.transportString()]
            let response = ZMTransportResponse(payload: responsePayload, httpStatus: 200, transportSessionError: nil, headers: responseHeader)
            
            //when
            _ = self.sut.updateUpdatedObject(message, requestUserInfo: nil, response: response, keysToParse: Set(arrayLiteral: ZMAssetClientMessageUploadedStateKey))
            
            // then
            XCTAssertEqual(message.assetId, assetId)
        }
        
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
    }
    
    func testKeysAreReset_whenRequestFailsBecauseSelfClientWasDeleted() {
        self.syncMOC.performGroupedBlock { 
            // given
            let keys = Set(arrayLiteral: ZMAssetClientMessageUploadedStateKey)
            let message = self.createImageMessage()
            
            message.setLocallyModifiedKeys(keys)
            let request = ZMUpstreamRequest(transportRequest: ZMTransportRequest(getFromPath: "foo"))!
            
            // when
            let response = ZMTransportResponse(payload: ["label" : "unknown-client"] as ZMTransportData, httpStatus: 403, transportSessionError: nil)
            _ = self.sut.shouldRetryToSyncAfterFailed(toUpdate: message, request: request, response: response, keysToParse: keys)
            
            // then
            XCTAssertEqual(message.uploadState, ZMAssetUploadState.uploadingFailed);
            XCTAssertTrue(message.hasLocalModifications(forKeys: keys))
            XCTAssertFalse(message.conversation!.needsToBeUpdatedFromBackend)
        }
        
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
    }
    
}
