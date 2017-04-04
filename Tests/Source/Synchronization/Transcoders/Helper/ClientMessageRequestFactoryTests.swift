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


import XCTest
@testable import WireSyncEngine
import ZMProtos
import ZMCDataModel
import ZMUtilities

class ClientMessageRequestFactoryTests: MessagingTest {
}

// MARK: - Text messages
extension ClientMessageRequestFactoryTests {

    func testThatItCreatesRequestToPostOTRTextMessage() {
        //given
        createSelfClient()
        let message = createClientTextMessage(true)
        let conversationId = UUID.create()
        message.visibleInConversation = ZMConversation.insertNewObject(in: self.syncMOC)
        message.visibleInConversation?.remoteIdentifier = conversationId
        
        //when
        let request = ClientMessageRequestFactory().upstreamRequestForMessage(message, forConversationWithId: conversationId)
        
        //then
        XCTAssertEqual(request?.method, ZMTransportRequestMethod.methodPOST)
        XCTAssertEqual(request?.path, "/conversations/\(conversationId.transportString())/otr/messages")
        XCTAssertEqual(message.encryptedMessagePayloadDataOnly, request?.binaryData)
    }
}


extension ClientMessageRequestFactoryTests {
    
    func testThatItCreatesRequestToPostOTRConfirmationMessage() {
        //given
        createSelfClient()
        let message = createClientTextMessage(true)
        let user = ZMUser.insertNewObject(in: self.syncMOC)
        user.remoteIdentifier = UUID.create()
        let client = UserClient.insertNewObject(in: self.syncMOC)
        client.remoteIdentifier = UUID.create().transportString()
        client.user = user
        message.sender = user
        let conversationId = UUID.create()
        message.visibleInConversation = ZMConversation.insertNewObject(in: self.syncMOC)
        message.visibleInConversation?.remoteIdentifier = conversationId
        let confirmationMessage = message.confirmReception()
        
        //when
        let request = ClientMessageRequestFactory().upstreamRequestForMessage(confirmationMessage!, forConversationWithId: conversationId)
        
        //then
        XCTAssertEqual(request?.method, ZMTransportRequestMethod.methodPOST)
        XCTAssertEqual(request?.path, "/conversations/\(conversationId.transportString())/otr/messages?report_missing=\(user.remoteIdentifier!.transportString())")
        XCTAssertEqual(message.encryptedMessagePayloadData()?.data, request?.binaryData)
    }
}

// MARK: - Image
extension ClientMessageRequestFactoryTests {

    func testThatItCreatesRequestToPostOTRImageMessage() {
        createSelfClient()
        for _ in [ZMImageFormat.medium, ZMImageFormat.preview] {
            //given
            let imageData = self.verySmallJPEGData()
            let format = ZMImageFormat.medium
            let conversationId = UUID.create()
            let message = self.createImageMessage(withImageData: imageData, format: format, processed: true, stored: false, encrypted: true, moc: self.syncMOC)
            message.visibleInConversation = ZMConversation.insertNewObject(in: self.syncMOC)
            message.visibleInConversation?.remoteIdentifier = conversationId
            
            //when
            let request = ClientMessageRequestFactory().upstreamRequestForAssetMessage(format, message: message, forConversationWithId: conversationId)
            
            //then
            let expectedPath = "/conversations/\(conversationId.transportString())/otr/assets"

            assertRequest(request, forImageMessage: message, conversationId: conversationId, encrypted: true, expectedPath: expectedPath, expectedPayload: nil, format: format)
            XCTAssertEqual(request?.multipartBodyItems()?.count, 2)
        }
    }
    
    func testThatItCreatesRequestToReuploadOTRImageMessage() {
        createSelfClient()
        
        for _ in [ZMImageFormat.medium, ZMImageFormat.preview] {

            // given
            let imageData = self.verySmallJPEGData()
            let format = ZMImageFormat.medium
            let conversationId = UUID.create()
            let message = self.createImageMessage(withImageData: imageData, format: format, processed: false, stored: false, encrypted: true, moc: self.syncMOC)
            message.assetId = UUID.create()
            message.visibleInConversation = ZMConversation.insertNewObject(in: self.syncMOC)
            message.visibleInConversation?.remoteIdentifier = conversationId
            
            //when
            let request = ClientMessageRequestFactory().upstreamRequestForAssetMessage(format, message: message, forConversationWithId: conversationId)
            
            //then
            let expectedPath = "/conversations/\(conversationId.transportString())/otr/assets/\(message.assetId!.transportString())"

            XCTAssertEqual(request?.method, ZMTransportRequestMethod.methodPOST)
            XCTAssertEqual(request?.path, expectedPath)
            XCTAssertNotNil(request?.binaryData)
            XCTAssertEqual(request?.shouldUseOnlyBackgroundSession, true)
        }
    }
}

// MARK: - File Upload

extension ClientMessageRequestFactoryTests {
    
    func testThatItCreatesRequestToUploadAFileMessage_Placeholder() {
        // given
        createSelfClient()
        let conversationID = UUID.create()
        let (message, _, _) = createAssetFileMessage(false, encryptedDataOnDisk: false)
        message.visibleInConversation = ZMConversation.insertNewObject(in: self.syncMOC)
        message.visibleInConversation?.remoteIdentifier = conversationID
        
        // when
        let sut = ClientMessageRequestFactory()
        let uploadRequest = sut.upstreamRequestForEncryptedFileMessage(.placeholder, message: message, forConversationWithId: conversationID)
        
        // then
        guard let request = uploadRequest else { return XCTFail() }
        XCTAssertEqual(request.path, "/conversations/\(conversationID.transportString())/otr/messages")
        XCTAssertEqual(request.method, ZMTransportRequestMethod.methodPOST)
        XCTAssertEqual(request.binaryDataType, "application/x-protobuf")
        XCTAssertNotNil(request.binaryData)
    }
    
    func testThatItCreatesRequestToUploadAFileMessage_Placeholder_UploadedDataPresent() {
        // given
        createSelfClient()
        let conversationID = UUID.create()
        let (message, _, _) = createAssetFileMessage(true, encryptedDataOnDisk: true)
        message.visibleInConversation = ZMConversation.insertNewObject(in: self.syncMOC)
        message.visibleInConversation?.remoteIdentifier = conversationID
        
        // when
        let sut = ClientMessageRequestFactory()
        let uploadRequest = sut.upstreamRequestForEncryptedFileMessage(.placeholder, message: message, forConversationWithId: conversationID)
        
        // then
        guard let request = uploadRequest else { return XCTFail() }
        XCTAssertEqual(request.path, "/conversations/\(conversationID.transportString())/otr/messages")
        XCTAssertEqual(request.method, ZMTransportRequestMethod.methodPOST)
        XCTAssertEqual(request.binaryDataType, "application/x-protobuf")
        XCTAssertNotNil(request.binaryData)
    }
    
    func testThatItCreatesRequestToUploadAFileMessage_FileData() {
        // given
        createSelfClient()
        let conversationID = UUID.create()
        let (message, _, _) = createAssetFileMessage(true)
        message.visibleInConversation = ZMConversation.insertNewObject(in: self.syncMOC)
        message.visibleInConversation?.remoteIdentifier = conversationID
        
        // when
        let sut = ClientMessageRequestFactory()
        let uploadRequest = sut.upstreamRequestForEncryptedFileMessage(.fullAsset, message: message, forConversationWithId: conversationID)
        
        // then
        guard let request = uploadRequest else { return XCTFail() }
        XCTAssertEqual(request.path, "/conversations/\(conversationID.transportString())/otr/assets")
        XCTAssertEqual(request.method, ZMTransportRequestMethod.methodPOST)
    }
    
    func testThatItCreatesRequestToReuploadFileMessageMetaData_WhenAssetIdIsPresent() {
        // given
        createSelfClient()
        let conversationID = UUID.create()
        let (message, _, _) = createAssetFileMessage()
        message.visibleInConversation = ZMConversation.insertNewObject(in: self.syncMOC)
        message.visibleInConversation?.remoteIdentifier = conversationID
        message.assetId = UUID.create()
        
        // when
        let sut = ClientMessageRequestFactory()
        let uploadRequest = sut.upstreamRequestForEncryptedFileMessage(.fullAsset, message: message, forConversationWithId: conversationID)
        
        // then
        guard let request = uploadRequest else { return XCTFail() }
        XCTAssertEqual(request.path, "/conversations/\(conversationID.transportString())/otr/assets/\(message.assetId!.transportString())")
        XCTAssertEqual(request.method, ZMTransportRequestMethod.methodPOST)
        XCTAssertNotNil(request.binaryData)
        XCTAssertEqual(request.binaryDataType, "application/x-protobuf")
    }
    
    func testThatTheRequestToReuploadAFileMessageDoesNotContainTheBinaryFileData() {
        // given
        createSelfClient()
        let conversationID = UUID.create()
        let (message, _, nonce) = createAssetFileMessage()
        message.visibleInConversation = ZMConversation.insertNewObject(in: self.syncMOC)
        message.visibleInConversation?.remoteIdentifier = conversationID
        message.assetId = UUID.create()
        
        // when
        let sut = ClientMessageRequestFactory()
        let uploadRequest = sut.upstreamRequestForEncryptedFileMessage(.fullAsset, message: message, forConversationWithId: conversationID)
        
        // then
        guard let request = uploadRequest else { return XCTFail() }
        XCTAssertNil(syncMOC.zm_fileAssetCache.accessRequestURL(nonce))
        XCTAssertNotNil(request.binaryData)
        XCTAssertEqual(request.path, "/conversations/\(conversationID.transportString())/otr/assets/\(message.assetId!.transportString())")
    }
    
    func testThatItDoesNotCreatesRequestToReuploadFileMessageMetaData_WhenAssetIdIsPresent_Placeholder() {
        // given
        createSelfClient()
        let conversationID = UUID.create()
        let (message, _, _) = createAssetFileMessage()
        message.assetId = UUID.create()
        message.visibleInConversation = ZMConversation.insertNewObject(in: self.syncMOC)
        message.visibleInConversation?.remoteIdentifier = conversationID
        
        // when
        let sut = ClientMessageRequestFactory()
        let uploadRequest = sut.upstreamRequestForEncryptedFileMessage(.placeholder, message: message, forConversationWithId: conversationID)
        
        // then
        guard let request = uploadRequest else { return XCTFail() }
        XCTAssertFalse(request.path.contains(message.assetId!.transportString()))
        XCTAssertEqual(request.method, ZMTransportRequestMethod.methodPOST)
        XCTAssertEqual(request.path, "/conversations/\(conversationID.transportString())/otr/messages")
    }
    
    func testThatItWritesTheMultiPartRequestDataToDisk() {
        // given
        createSelfClient()
        let conversationID = UUID.create()
        let (message, data, nonce) = createAssetFileMessage()
        message.visibleInConversation = ZMConversation.insertNewObject(in: self.syncMOC)
        message.visibleInConversation?.remoteIdentifier = conversationID
        
        // when
        let sut = ClientMessageRequestFactory()
        let uploadRequest = sut.upstreamRequestForEncryptedFileMessage(.fullAsset, message:message, forConversationWithId: conversationID)
        XCTAssertNotNil(uploadRequest)
        
        // then
        guard let url = syncMOC.zm_fileAssetCache.accessRequestURL(nonce) else { return XCTFail() }
        guard let multipartData = try? Data(contentsOf: url) else { return XCTFail() }
        let multiPartItems = (multipartData as NSData).multipartDataItemsSeparated(withBoundary: "frontier")
        XCTAssertEqual(multiPartItems.count, 2)
        let fileData = (multiPartItems.last as? ZMMultipartBodyItem)?.data
        XCTAssertEqual(data, fileData)
    }
    
    func testThatItSetsTheDataMD5() {
        // given
        createSelfClient()
        let conversationID = UUID.create()
        let (message, data, nonce) = createAssetFileMessage(true)
        message.visibleInConversation = ZMConversation.insertNewObject(in: self.syncMOC)
        message.visibleInConversation?.remoteIdentifier = conversationID
        
        // when
        let sut = ClientMessageRequestFactory()
        let uploadRequest = sut.upstreamRequestForEncryptedFileMessage(.fullAsset, message: message, forConversationWithId: conversationID)
        XCTAssertNotNil(uploadRequest)
        
        // then
        guard let url = syncMOC.zm_fileAssetCache.accessRequestURL(nonce) else { return XCTFail() }
        guard let multipartData = try? Data(contentsOf: url) else { return XCTFail() }
        let multiPartItems = (multipartData as NSData).multipartDataItemsSeparated(withBoundary: "frontier")
        XCTAssertEqual(multiPartItems.count, 2)
        guard let fileData = (multiPartItems.last as? ZMMultipartBodyItem) else { return XCTFail() }
        XCTAssertEqual(fileData.headers?["Content-MD5"] as? String, data.zmMD5Digest().base64String())
    }
    
    func testThatItDoesNotCreateARequestIfTheMessageIsNotAFileAssetMessage_AssetClientMessage_Image() {
        // given
        createSelfClient()
        let imageData = verySmallJPEGData()
        let conversationID = UUID.create()
        let message = createImageMessage(withImageData: imageData, format: .medium, processed: true, stored: false, encrypted: true, moc: syncMOC)
        message.visibleInConversation = ZMConversation.insertNewObject(in: self.syncMOC)
        message.visibleInConversation?.remoteIdentifier = conversationID
        
        // when
        let sut = ClientMessageRequestFactory()
        let uploadRequest = sut.upstreamRequestForEncryptedFileMessage(.fullAsset, message: message, forConversationWithId: conversationID)
        
        // then
        XCTAssertNil(uploadRequest)
    }
    
    func testThatItReturnsNilWhenThereIsNoEncryptedDataToUploadOnDisk() {
        // given
        createSelfClient()
        let conversationID = UUID.create()
        let (message, _, _) = createAssetFileMessage(encryptedDataOnDisk: false)
        message.visibleInConversation = ZMConversation.insertNewObject(in: self.syncMOC)
        message.visibleInConversation?.remoteIdentifier = conversationID
        
        // when
        let sut = ClientMessageRequestFactory()
        let uploadRequest = sut.upstreamRequestForEncryptedFileMessage(.fullAsset, message: message, forConversationWithId: conversationID)
        
        // then
        XCTAssertNil(uploadRequest)
    }
    
    func testThatItStoresTheUploadDataInTheCachesDirectoryAndMarksThemAsNotBeingBackedUp() {
        // given
        createSelfClient()
        let conversationID = UUID.create()
        let (message, _, nonce) = createAssetFileMessage()
        message.visibleInConversation = ZMConversation.insertNewObject(in: self.syncMOC)
        message.visibleInConversation?.remoteIdentifier = conversationID
        
        // when
        let sut = ClientMessageRequestFactory()
        let uploadRequest = sut.upstreamRequestForEncryptedFileMessage(.fullAsset, message: message, forConversationWithId: conversationID)
        
        // then
        XCTAssertNotNil(uploadRequest)
        guard let url = syncMOC.zm_fileAssetCache.accessRequestURL(nonce)
        else { return XCTFail() }
        
        // It's very likely that this is the most un-future proof way of testing this...
        guard let resourceValues = try? url.resourceValues(forKeys: Set(arrayLiteral: .isExcludedFromBackupKey)),
              let isExcludedFromBackup = resourceValues.isExcludedFromBackup
        else {return XCTFail()}
        XCTAssertTrue(isExcludedFromBackup)
    }
    
    func testThatItCreatesTheMultipartDataWithTheCorrectContentTypes() {
        // given
        let metaData = "metadata".data(using: String.Encoding.utf8)!
        let fileData = "filedata".data(using: String.Encoding.utf8)!
        
        // when
        let multipartData = ClientMessageRequestFactory().dataForMultipartFileUploadRequest(metaData, fileData: fileData)
        
        // then
        guard let parts = (multipartData as NSData).multipartDataItemsSeparated(withBoundary: "frontier") as? [ZMMultipartBodyItem] else { return XCTFail() }
        XCTAssertEqual(parts.count, 2)
        XCTAssertEqual(parts.first?.contentType, "application/x-protobuf")
        XCTAssertEqual(parts.last?.contentType, "application/octet-stream")
    }
}

// MARK: - Helpers
extension ClientMessageRequestFactoryTests {
    
    var testURL: URL {
        let documents = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first!
        let documentsURL = URL(fileURLWithPath: documents)
        return documentsURL.appendingPathComponent("file.dat")
    }
    
    func createAssetFileMessage(_ withUploaded: Bool = true, encryptedDataOnDisk: Bool = true) -> (ZMAssetClientMessage, Data, UUID) {
        let data = createTestFile(testURL)
        let nonce = UUID.create()
        let metadata = ZMFileMetadata(fileURL: testURL)
        let message = ZMAssetClientMessage(
            fileMetadata: metadata,
            nonce: nonce,
            managedObjectContext: self.syncMOC
        )
        
        XCTAssertNotNil(data)
        XCTAssertNotNil(message)
        
        if withUploaded {
            let otrKey = Data.randomEncryptionKey()
            let sha256 = Data.randomEncryptionKey()
            let uploadedMessage = ZMGenericMessage.genericMessage(withUploadedOTRKey: otrKey, sha256: sha256, messageID: nonce.transportString())
            XCTAssertNotNil(uploadedMessage)
            message.add(uploadedMessage)
        }
        
        if encryptedDataOnDisk {
            self.syncMOC.zm_fileAssetCache.storeAssetData(nonce, fileName: name!, encrypted: true, data: data)
        }
        
        return (message, data, nonce)
    }
    
    func createTestFile(_ url: URL) -> Data {
        let data: Data! = name!.data(using: String.Encoding.utf8)
        try! data.write(to: url, options: [])
        return data
    }
    
    func assertRequest(_ request: ZMTransportRequest?, forImageMessage message: ZMAssetClientMessage, conversationId: UUID, encrypted: Bool, expectedPath: String, expectedPayload: [String: NSObject]?, format: ZMImageFormat)
    {
        let imageData = message.imageAssetStorage!.imageData(for: format, encrypted: encrypted)!
        guard let request = request else {
            return XCTFail("ClientRequestFactory should create requet to post medium asset message")
        }
        XCTAssertEqual(request.method, ZMTransportRequestMethod.methodPOST)
        XCTAssertEqual(request.path, expectedPath)
        
        guard let multipartItems = request.multipartBodyItems() as? [AnyObject] else {
            return XCTFail("Request should be multipart data request")
        }
        
        XCTAssertEqual(multipartItems.count, 2)
        guard let imageDataItem = multipartItems.last else {
            return XCTFail("Request should contain image multipart data")
        }
        XCTAssertEqual(imageDataItem.data, imageData)
        
        
        guard let metaDataItem = multipartItems.first else {
            return XCTFail("Request should contain metadata multipart data")
        }
        
        let metaData : [String: NSObject]
        do {
            metaData = try JSONSerialization.jsonObject(with: (metaDataItem as AnyObject).data, options: JSONSerialization.ReadingOptions()) as! [String : NSObject]
        }
        catch {
            metaData = [:]
        }
        if let expectedPayload = expectedPayload {
            XCTAssertEqual(metaData, expectedPayload)
        }

    }
}
