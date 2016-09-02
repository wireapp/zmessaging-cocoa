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
@testable import zmessaging
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
        let conversationId = NSUUID.createUUID()
        message.visibleInConversation = ZMConversation.insertNewObjectInManagedObjectContext(self.syncMOC)
        message.visibleInConversation?.remoteIdentifier = conversationId
        
        //when
        let request = ClientMessageRequestFactory().upstreamRequestForMessage(message, forConversationWithId: conversationId)
        
        //then
        XCTAssertEqual(request?.method, ZMTransportRequestMethod.MethodPOST)
        XCTAssertEqual(request?.path, "/conversations/\(conversationId.transportString())/otr/messages")
        XCTAssertEqual(message.encryptedMessagePayloadDataOnly, request?.binaryData)
    }
}


extension ClientMessageRequestFactoryTests {
    
    func testThatItCreatesRequestToPostOTRConfirmationMessage() {
        //given
        createSelfClient()
        let message = createClientTextMessage(true)
        let user = ZMUser.insertNewObjectInManagedObjectContext(self.syncMOC)
        user.remoteIdentifier = NSUUID.createUUID()
        let client = UserClient.insertNewObjectInManagedObjectContext(self.syncMOC)
        client.remoteIdentifier = NSUUID.createUUID().transportString()
        client.user = user
        message.sender = user
        let conversationId = NSUUID.createUUID()
        message.visibleInConversation = ZMConversation.insertNewObjectInManagedObjectContext(self.syncMOC)
        message.visibleInConversation?.remoteIdentifier = conversationId
        let confirmationMessage = message.confirmReception()
        
        //when
        let request = ClientMessageRequestFactory().upstreamRequestForMessage(confirmationMessage, forConversationWithId: conversationId)
        
        //then
        XCTAssertEqual(request?.method, ZMTransportRequestMethod.MethodPOST)
        XCTAssertEqual(request?.path, "/conversations/\(conversationId.transportString())/otr/messages?report_missing=\(user.remoteIdentifier!.transportString())")
        XCTAssertEqual(message.encryptedMessagePayloadData()?.data, request?.binaryData)
    }
}

// MARK: - Image
extension ClientMessageRequestFactoryTests {

    func testThatItCreatesRequestToPostOTRImageMessage() {
        createSelfClient()
        for _ in [ZMImageFormat.Medium, ZMImageFormat.Preview] {
            //given
            let imageData = self.verySmallJPEGData()
            let format = ZMImageFormat.Medium
            let conversationId = NSUUID.createUUID()
            let message = self.createImageMessageWithImageData(imageData, format: format, processed: true, stored: false, encrypted: true, moc: self.syncMOC)
            message.visibleInConversation = ZMConversation.insertNewObjectInManagedObjectContext(self.syncMOC)
            message.visibleInConversation?.remoteIdentifier = conversationId
            
            //when
            let request = ClientMessageRequestFactory().upstreamRequestForAssetMessage(format, message: message, forConversationWithId: conversationId)
            
            //then
            let expectedPath = "/conversations/\(conversationId.transportString())/otr/assets"

            assertRequest(request, forImageMessage: message, conversationId: conversationId, encrypted: true, expectedPath: expectedPath, expectedPayload: nil, format: format)
            XCTAssertEqual(request?.multipartBodyItems().count, 2)
        }
    }
    
    func testThatItCreatesRequestToReuploadOTRImageMessage() {
        createSelfClient()
        
        for _ in [ZMImageFormat.Medium, ZMImageFormat.Preview] {

            // given
            let imageData = self.verySmallJPEGData()
            let format = ZMImageFormat.Medium
            let conversationId = NSUUID.createUUID()
            let message = self.createImageMessageWithImageData(imageData, format: format, processed: false, stored: false, encrypted: true, moc: self.syncMOC)
            message.assetId = NSUUID.createUUID()
            message.visibleInConversation = ZMConversation.insertNewObjectInManagedObjectContext(self.syncMOC)
            message.visibleInConversation?.remoteIdentifier = conversationId
            
            //when
            let request = ClientMessageRequestFactory().upstreamRequestForAssetMessage(format, message: message, forConversationWithId: conversationId)
            
            //then
            let expectedPath = "/conversations/\(conversationId.transportString())/otr/assets/\(message.assetId!.transportString())"

            XCTAssertEqual(request?.method, ZMTransportRequestMethod.MethodPOST)
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
        let conversationID = NSUUID.createUUID()
        let (message, _, _) = createAssetFileMessage(false, encryptedDataOnDisk: false)
        message.visibleInConversation = ZMConversation.insertNewObjectInManagedObjectContext(self.syncMOC)
        message.visibleInConversation?.remoteIdentifier = conversationID
        
        // when
        let sut = ClientMessageRequestFactory()
        let uploadRequest = sut.upstreamRequestForEncryptedFileMessage(.Placeholder, message: message, forConversationWithId: conversationID)
        
        // then
        guard let request = uploadRequest else { return XCTFail() }
        XCTAssertEqual(request.path, "/conversations/\(conversationID.transportString())/otr/messages")
        XCTAssertEqual(request.method, ZMTransportRequestMethod.MethodPOST)
        XCTAssertEqual(request.binaryDataType, "application/x-protobuf")
        XCTAssertNotNil(request.binaryData)
    }
    
    func testThatItCreatesRequestToUploadAFileMessage_Placeholder_UploadedDataPresent() {
        // given
        createSelfClient()
        let conversationID = NSUUID.createUUID()
        let (message, _, _) = createAssetFileMessage(true, encryptedDataOnDisk: true)
        message.visibleInConversation = ZMConversation.insertNewObjectInManagedObjectContext(self.syncMOC)
        message.visibleInConversation?.remoteIdentifier = conversationID
        
        // when
        let sut = ClientMessageRequestFactory()
        let uploadRequest = sut.upstreamRequestForEncryptedFileMessage(.Placeholder, message: message, forConversationWithId: conversationID)
        
        // then
        guard let request = uploadRequest else { return XCTFail() }
        XCTAssertEqual(request.path, "/conversations/\(conversationID.transportString())/otr/messages")
        XCTAssertEqual(request.method, ZMTransportRequestMethod.MethodPOST)
        XCTAssertEqual(request.binaryDataType, "application/x-protobuf")
        XCTAssertNotNil(request.binaryData)
    }
    
    func testThatItCreatesRequestToUploadAFileMessage_FileData() {
        // given
        createSelfClient()
        let conversationID = NSUUID.createUUID()
        let (message, _, _) = createAssetFileMessage(true)
        message.visibleInConversation = ZMConversation.insertNewObjectInManagedObjectContext(self.syncMOC)
        message.visibleInConversation?.remoteIdentifier = conversationID
        
        // when
        let sut = ClientMessageRequestFactory()
        let uploadRequest = sut.upstreamRequestForEncryptedFileMessage(.FullAsset, message: message, forConversationWithId: conversationID)
        
        // then
        guard let request = uploadRequest else { return XCTFail() }
        XCTAssertEqual(request.path, "/conversations/\(conversationID.transportString())/otr/assets")
        XCTAssertEqual(request.method, ZMTransportRequestMethod.MethodPOST)
    }
    
    func testThatItCreatesRequestToReuploadFileMessageMetaData_WhenAssetIdIsPresent() {
        // given
        createSelfClient()
        let conversationID = NSUUID.createUUID()
        let (message, _, _) = createAssetFileMessage()
        message.visibleInConversation = ZMConversation.insertNewObjectInManagedObjectContext(self.syncMOC)
        message.visibleInConversation?.remoteIdentifier = conversationID
        message.assetId = .createUUID()
        
        // when
        let sut = ClientMessageRequestFactory()
        let uploadRequest = sut.upstreamRequestForEncryptedFileMessage(.FullAsset, message: message, forConversationWithId: conversationID)
        
        // then
        guard let request = uploadRequest else { return XCTFail() }
        XCTAssertEqual(request.path, "/conversations/\(conversationID.transportString())/otr/assets/\(message.assetId!.transportString())")
        XCTAssertEqual(request.method, ZMTransportRequestMethod.MethodPOST)
        XCTAssertNotNil(request.binaryData)
        XCTAssertEqual(request.binaryDataType, "application/x-protobuf")
    }
    
    func testThatTheRequestToReuploadAFileMessageDoesNotContainTheBinaryFileData() {
        // given
        createSelfClient()
        let conversationID = NSUUID.createUUID()
        let (message, _, nonce) = createAssetFileMessage()
        message.visibleInConversation = ZMConversation.insertNewObjectInManagedObjectContext(self.syncMOC)
        message.visibleInConversation?.remoteIdentifier = conversationID
        message.assetId = .createUUID()
        
        // when
        let sut = ClientMessageRequestFactory()
        let uploadRequest = sut.upstreamRequestForEncryptedFileMessage(.FullAsset, message: message, forConversationWithId: conversationID)
        
        // then
        guard let request = uploadRequest else { return XCTFail() }
        XCTAssertNil(syncMOC.zm_fileAssetCache.accessRequestURL(nonce))
        XCTAssertNotNil(request.binaryData)
        XCTAssertEqual(request.path, "/conversations/\(conversationID.transportString())/otr/assets/\(message.assetId!.transportString())")
    }
    
    func testThatItDoesNotCreatesRequestToReuploadFileMessageMetaData_WhenAssetIdIsPresent_Placeholder() {
        // given
        createSelfClient()
        let conversationID = NSUUID.createUUID()
        let (message, _, _) = createAssetFileMessage()
        message.assetId = .createUUID()
        message.visibleInConversation = ZMConversation.insertNewObjectInManagedObjectContext(self.syncMOC)
        message.visibleInConversation?.remoteIdentifier = conversationID
        
        // when
        let sut = ClientMessageRequestFactory()
        let uploadRequest = sut.upstreamRequestForEncryptedFileMessage(.Placeholder, message: message, forConversationWithId: conversationID)
        
        // then
        guard let request = uploadRequest else { return XCTFail() }
        XCTAssertFalse(request.path.containsString(message.assetId!.transportString()))
        XCTAssertEqual(request.method, ZMTransportRequestMethod.MethodPOST)
        XCTAssertEqual(request.path, "/conversations/\(conversationID.transportString())/otr/messages")
    }
    
    func testThatItWritesTheMultiPartRequestDataToDisk() {
        // given
        createSelfClient()
        let conversationID = NSUUID.createUUID()
        let (message, data, nonce) = createAssetFileMessage()
        message.visibleInConversation = ZMConversation.insertNewObjectInManagedObjectContext(self.syncMOC)
        message.visibleInConversation?.remoteIdentifier = conversationID
        
        // when
        let sut = ClientMessageRequestFactory()
        let uploadRequest = sut.upstreamRequestForEncryptedFileMessage(.FullAsset, message:message, forConversationWithId: conversationID)
        XCTAssertNotNil(uploadRequest)
        
        // then
        guard let url = syncMOC.zm_fileAssetCache.accessRequestURL(nonce) else { return XCTFail() }
        guard let multipartData = NSData(contentsOfURL: url) else { return XCTFail() }
        guard let multiPartItems = multipartData.multipartDataItemsSeparatedWithBoundary("frontier") else { return XCTFail() }
        XCTAssertEqual(multiPartItems.count, 2)
        let fileData = (multiPartItems.last as? ZMMultipartBodyItem)?.data
        XCTAssertEqual(data, fileData)
    }
    
    func testThatItSetsTheDataMD5() {
        // given
        createSelfClient()
        let conversationID = NSUUID.createUUID()
        let (message, data, nonce) = createAssetFileMessage(true)
        message.visibleInConversation = ZMConversation.insertNewObjectInManagedObjectContext(self.syncMOC)
        message.visibleInConversation?.remoteIdentifier = conversationID
        
        // when
        let sut = ClientMessageRequestFactory()
        let uploadRequest = sut.upstreamRequestForEncryptedFileMessage(.FullAsset, message: message, forConversationWithId: conversationID)
        XCTAssertNotNil(uploadRequest)
        
        // then
        guard let url = syncMOC.zm_fileAssetCache.accessRequestURL(nonce) else { return XCTFail() }
        guard let multipartData = NSData(contentsOfURL: url) else { return XCTFail() }
        guard let multiPartItems = multipartData.multipartDataItemsSeparatedWithBoundary("frontier") else { return XCTFail() }
        XCTAssertEqual(multiPartItems.count, 2)
        guard let fileData = (multiPartItems.last as? ZMMultipartBodyItem) else { return XCTFail() }
        XCTAssertEqual(fileData.headers["Content-MD5"] as? String, data.zmMD5Digest().base64String())
    }
    
    func testThatItDoesNotCreateARequestIfTheMessageIsNotAFileAssetMessage_AssetClientMessage_Image() {
        // given
        createSelfClient()
        let imageData = verySmallJPEGData()
        let conversationID = NSUUID.createUUID()
        let message = createImageMessageWithImageData(imageData, format: .Medium, processed: true, stored: false, encrypted: true, moc: syncMOC)
        message.visibleInConversation = ZMConversation.insertNewObjectInManagedObjectContext(self.syncMOC)
        message.visibleInConversation?.remoteIdentifier = conversationID
        
        // when
        let sut = ClientMessageRequestFactory()
        let uploadRequest = sut.upstreamRequestForEncryptedFileMessage(.FullAsset, message: message, forConversationWithId: conversationID)
        
        // then
        XCTAssertNil(uploadRequest)
    }
    
    func testThatItReturnsNilWhenThereIsNoEncryptedDataToUploadOnDisk() {
        // given
        createSelfClient()
        let conversationID = NSUUID.createUUID()
        let (message, _, _) = createAssetFileMessage(encryptedDataOnDisk: false)
        message.visibleInConversation = ZMConversation.insertNewObjectInManagedObjectContext(self.syncMOC)
        message.visibleInConversation?.remoteIdentifier = conversationID
        
        // when
        let sut = ClientMessageRequestFactory()
        let uploadRequest = sut.upstreamRequestForEncryptedFileMessage(.FullAsset, message: message, forConversationWithId: conversationID)
        
        // then
        XCTAssertNil(uploadRequest)
    }
    
    func testThatItStoresTheUploadDataInTheCachesDirectoryAndMarksThemAsNotBeingBackedUp() {
        // given
        createSelfClient()
        let conversationID = NSUUID.createUUID()
        let (message, _, nonce) = createAssetFileMessage()
        message.visibleInConversation = ZMConversation.insertNewObjectInManagedObjectContext(self.syncMOC)
        message.visibleInConversation?.remoteIdentifier = conversationID
        
        // when
        let sut = ClientMessageRequestFactory()
        let uploadRequest = sut.upstreamRequestForEncryptedFileMessage(.FullAsset, message: message, forConversationWithId: conversationID)
        
        // then
        XCTAssertNotNil(uploadRequest)
        guard let url = syncMOC.zm_fileAssetCache.accessRequestURL(nonce) else { return XCTFail() }
        XCTAssertNotNil(NSData(contentsOfURL: url))
        
        let fm = NSFileManager.defaultManager()
        guard let path = url.path, attributes = try? fm.attributesOfItemAtPath(path) else { return XCTFail() }
        XCTAssertTrue(path.containsString("/Library/Caches"))
        
        // It's very likely that this is the most un-future proof way of testing this...
        let excludedFromBackup = attributes["NSFileExtendedAttributes"]?["com.apple.metadata:com_apple_backup_excludeItem"]
        XCTAssertNotNil(excludedFromBackup)
    }
    
    func testThatItCreatesTheMultipartDataWithTheCorrectContentTypes() {
        // given
        let metaData = "metadata".dataUsingEncoding(NSUTF8StringEncoding)!
        let fileData = "filedata".dataUsingEncoding(NSUTF8StringEncoding)!
        
        // when
        let multipartData = ClientMessageRequestFactory().dataForMultipartFileUploadRequest(metaData, fileData: fileData)
        
        // then
        guard let parts = multipartData.multipartDataItemsSeparatedWithBoundary("frontier") as? [ZMMultipartBodyItem] else { return XCTFail() }
        XCTAssertEqual(parts.count, 2)
        XCTAssertEqual(parts.first?.contentType, "application/x-protobuf")
        XCTAssertEqual(parts.last?.contentType, "application/octet-stream")
    }
}

// MARK: - Helpers
extension ClientMessageRequestFactoryTests {
    
    var testURL: NSURL {
        let documents = NSSearchPathForDirectoriesInDomains(.DocumentDirectory, .UserDomainMask, true).first!
        let documentsURL = NSURL(fileURLWithPath: documents)
        return documentsURL.URLByAppendingPathComponent("file.dat")
    }
    
    func createAssetFileMessage(withUploaded: Bool = true, encryptedDataOnDisk: Bool = true) -> (ZMAssetClientMessage, NSData, NSUUID) {
        let data = createTestFile(testURL)
        let nonce = NSUUID.createUUID()
        let metadata = ZMFileMetadata(fileURL: testURL)
        let message = ZMAssetClientMessage(
            fileMetadata: metadata,
            nonce: nonce,
            managedObjectContext: self.syncMOC
        )
        
        XCTAssertNotNil(data)
        XCTAssertNotNil(message)
        
        if withUploaded {
            let otrKey = NSData.randomEncryptionKey()
            let sha256 = NSData.randomEncryptionKey()
            let uploadedMessage = ZMGenericMessage.genericMessage(withUploadedOTRKey: otrKey, sha256: sha256, messageID: nonce.transportString())
            XCTAssertNotNil(uploadedMessage)
            message.addGenericMessage(uploadedMessage)
        }
        
        if encryptedDataOnDisk {
            self.syncMOC.zm_fileAssetCache.storeAssetData(nonce, fileName: name!, encrypted: true, data: data)
        }
        
        return (message, data, nonce)
    }
    
    func createTestFile(url: NSURL) -> NSData {
        let data: NSData! = name!.dataUsingEncoding(NSUTF8StringEncoding)
        try! data.writeToURL(url, options: [])
        return data
    }
    
    func assertRequest(request: ZMTransportRequest?, forImageMessage message: ZMAssetClientMessage, conversationId: NSUUID, encrypted: Bool, expectedPath: String, expectedPayload: [String: NSObject]?, format: ZMImageFormat)
    {
        let imageData = message.imageAssetStorage!.imageDataForFormat(format, encrypted: encrypted)!
        
        AssertOptionalNotNil(request, "ClientRequestFactory should create requet to post medium asset message") { request in
            XCTAssertEqual(request.method, ZMTransportRequestMethod.MethodPOST)
            XCTAssertEqual(request.path, expectedPath)
            
            AssertOptionalNotNil(request.multipartBodyItems(), "Request should be multipart data request") { multipartItems in
                XCTAssertEqual(multipartItems.count, 2)
                AssertOptionalNotNil(multipartItems.last, "Request should contain image multipart data") { imageDataItem in
                    XCTAssertEqual(imageDataItem.data, imageData)
                }
                AssertOptionalNotNil(multipartItems.first, "Request should contain metadata multipart data") { metaDataItem in
                    let metaData : [String: NSObject]
                    do {
                        metaData = try NSJSONSerialization.JSONObjectWithData(metaDataItem.data, options: NSJSONReadingOptions()) as! [String : NSObject]
                    }
                    catch {
                        metaData = [:]
                    }
                    if let expectedPayload = expectedPayload {
                        XCTAssertEqual(metaData, expectedPayload)
                    }
                }
            }
        }
    }    
}
