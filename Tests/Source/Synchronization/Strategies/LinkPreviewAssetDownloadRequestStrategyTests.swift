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

class LinkPreviewAssetDownloadRequestStrategyTests: MessagingTest {

    var sut: LinkPreviewAssetDownloadRequestStrategy!
    var authStatus: MockAuthenticationStatus!
    
    override func setUp() {
        super.setUp()
        authStatus = MockAuthenticationStatus()
        sut = LinkPreviewAssetDownloadRequestStrategy(
            authStatus: authStatus,
            managedObjectContext: syncMOC
        )
        syncMOC.zm_imageAssetCache.wipeCache()
        uiMOC.zm_imageAssetCache.wipeCache()
    }
    
    // MARK: - Request Generation

    func testThatItGeneratesARequestForAWhitelistedMessageWithNoImageInCache() {
        // given
        let message = ZMClientMessage.insertNewObjectInManagedObjectContext(syncMOC)
        let assetID = NSUUID.createUUID().transportString()!
        let linkPreview = createLinkPreviewAndKeys(assetID).preview
        let nonce = NSUUID.createUUID()
        let genericMessage = ZMGenericMessage(text: name!, linkPreview: linkPreview, nonce: nonce.transportString()!)
        message.addData(genericMessage.data())
        _ = try? syncMOC.obtainPermanentIDsForObjects([message])
        
        // when
        message.requestImageDownload()
        XCTAssertTrue(waitForAllGroupsToBeEmptyWithTimeout(0.5))
        
        // then
        guard let request = sut.nextRequest() else { return XCTFail("No request generated") }
        XCTAssertEqual(request.path, "/assets/v3/\(assetID)")
        XCTAssertEqual(request.method, ZMTransportRequestMethod.MethodGET)
        XCTAssertNil(sut.nextRequest())
    }
    
    func testThatItDoesNotGenerateARequestForAMessageWithoutALinkPreview() {
        let message = ZMClientMessage.insertNewObjectInManagedObjectContext(syncMOC)
        let genericMessage = ZMGenericMessage(text: name!, nonce: NSUUID.createUUID().transportString()!)
        message.addData(genericMessage.data())
        _ = try? syncMOC.obtainPermanentIDsForObjects([message])
        
        // when
        message.requestImageDownload()
        XCTAssertTrue(waitForAllGroupsToBeEmptyWithTimeout(0.5))
        
        // then
        XCTAssertTrue(waitForAllGroupsToBeEmptyWithTimeout(0.5))
        XCTAssertNil(sut.nextRequest())
    }
    
    func testThatItDoesNotGenerateARequestForAMessageWithImageInCache() {
        // given
        let message = ZMClientMessage.insertNewObjectInManagedObjectContext(syncMOC)
        let assetID = NSUUID.createUUID().transportString()!
        let linkPreview = createLinkPreviewAndKeys(assetID).preview
        let nonce = NSUUID.createUUID()
        let genericMessage = ZMGenericMessage(text: name!, linkPreview: linkPreview, nonce: nonce.transportString()!)
        message.addData(genericMessage.data())
        _ = try? syncMOC.obtainPermanentIDsForObjects([message])
        syncMOC.zm_imageAssetCache.storeAssetData(nonce, format: .Medium, encrypted: false, data: .secureRandomDataOfLength(256))
        
        // when
        message.requestImageDownload()
        XCTAssertTrue(waitForAllGroupsToBeEmptyWithTimeout(0.5))
        
        // then
        XCTAssertNil(sut.nextRequest())
    }
    
    func testThatItDoesNotGenerateARequestForAMessageWithoutArticleLinkPreview() {
        // given
        let message = ZMClientMessage.insertNewObjectInManagedObjectContext(syncMOC)
        let assetID = NSUUID.createUUID().transportString()!
        let linkPreview = createLinkPreviewAndKeys(assetID, article: false).preview
        let nonce = NSUUID.createUUID()
        let genericMessage = ZMGenericMessage(text: name!, linkPreview: linkPreview, nonce: nonce.transportString()!)
        message.addData(genericMessage.data())
        _ = try? syncMOC.obtainPermanentIDsForObjects([message])
        syncMOC.zm_imageAssetCache.storeAssetData(nonce, format: .Medium, encrypted: false, data: .secureRandomDataOfLength(256))
        
        // when
        message.requestImageDownload()
        XCTAssertTrue(waitForAllGroupsToBeEmptyWithTimeout(0.5))
        
        // then
        XCTAssertNil(sut.nextRequest())
    }
    
    // MARK: - Response Handling
    
    func testThatItDecryptsTheImageDataInTheRequestResponseAndDeletesTheEncryptedVersion() {
        let message = ZMClientMessage.insertNewObjectInManagedObjectContext(syncMOC)
        let assetID = NSUUID.createUUID().transportString()!
        let data = NSData.secureRandomDataOfLength(256)
        let otrKey = NSData.randomEncryptionKey()
        let encrypted = data.zmEncryptPrefixingPlainTextIVWithKey(otrKey)
        let (linkPreview, _, _) = createLinkPreviewAndKeys(assetID, otrKey: otrKey, sha256: encrypted.zmSHA256Digest())
        let nonce = NSUUID.createUUID()
        let genericMessage = ZMGenericMessage(text: name!, linkPreview: linkPreview, nonce: nonce.transportString()!)
        message.addData(genericMessage.data())
        _ = try? syncMOC.obtainPermanentIDsForObjects([message])
        
        // when
        message.requestImageDownload()
        XCTAssertTrue(waitForAllGroupsToBeEmptyWithTimeout(0.5))
        
        // then
        guard let request = sut.nextRequest() else { return XCTFail("No request generated") }
        let response = ZMTransportResponse(imageData: encrypted, HTTPstatus: 200, transportSessionError: nil, headers: nil)
        
        // when
        request.completeWithResponse(response)
        XCTAssertTrue(waitForAllGroupsToBeEmptyWithTimeout(0.5))
        
        // then
        let actual = syncMOC.zm_imageAssetCache.assetData(nonce, format: .Medium, encrypted: false)
        XCTAssertNotNil(actual)
        XCTAssertEqual(actual, data)
        XCTAssertNil(syncMOC.zm_imageAssetCache.assetData(nonce, format: .Medium, encrypted: true))
    }
    
    func testThatItDoesNotDecyptTheImageDataInTheRequestResponseWhenTheResponseIsNotSuccesful() {
        let message = ZMClientMessage.insertNewObjectInManagedObjectContext(syncMOC)
        let assetID = NSUUID.createUUID().transportString()!
        let (linkPreview, _, _) = createLinkPreviewAndKeys(assetID)
        let nonce = NSUUID.createUUID()
        let genericMessage = ZMGenericMessage(text: name!, linkPreview: linkPreview, nonce: nonce.transportString()!)
        message.addData(genericMessage.data())
        _ = try? syncMOC.obtainPermanentIDsForObjects([message])
        
        // when
        message.requestImageDownload()
        XCTAssertTrue(waitForAllGroupsToBeEmptyWithTimeout(0.5))
        
        // then
        guard let request = sut.nextRequest() else { return XCTFail("No request generated") }
        let response = ZMTransportResponse(imageData: .secureRandomDataOfLength(256), HTTPstatus: 400, transportSessionError: nil, headers: nil)
        
        // when
        request.completeWithResponse(response)
        XCTAssertTrue(waitForAllGroupsToBeEmptyWithTimeout(0.5))
        
        // then
        XCTAssertNil(syncMOC.zm_imageAssetCache.assetData(nonce, format: .Medium, encrypted: false))
        XCTAssertNil(syncMOC.zm_imageAssetCache.assetData(nonce, format: .Medium, encrypted: true))
    }
    
    func testThatItNotifiesTheObserversWhenTheImageHasBeenDownloaded() {
        // given
        fireSyncCompletedNotification()
        let conversation = ZMConversation.insertNewObjectInManagedObjectContext(uiMOC)
        let message = conversation.appendMessageWithText("Foo") as! ZMClientMessage
        let observer = MessageChangeObserver(message: message)
        defer { observer.tearDown() }
        let assetID = NSUUID.createUUID().transportString()!
        let data = NSData.secureRandomDataOfLength(256)
        let otrKey = NSData.randomEncryptionKey()
        let encrypted = data.zmEncryptPrefixingPlainTextIVWithKey(otrKey)
        let (linkPreview, _, _) = createLinkPreviewAndKeys(assetID, otrKey: otrKey, sha256: encrypted.zmSHA256Digest())
        let nonce = NSUUID.createUUID()
        let genericMessage = ZMGenericMessage(text: "Link preview", linkPreview: linkPreview, nonce: nonce.transportString()!)
        message.addData(genericMessage.data())
        uiMOC.saveOrRollback()
        XCTAssertTrue(waitForAllGroupsToBeEmptyWithTimeout(0.5))
        
        // when
        message.requestImageDownload()
        XCTAssertTrue(waitForAllGroupsToBeEmptyWithTimeout(0.5))
        guard let request = sut.nextRequest() else { return XCTFail("No request generated") }
        let response = ZMTransportResponse(imageData: encrypted, HTTPstatus: 200, transportSessionError: nil, headers: nil)
        request.completeWithResponse(response)
        uiMOC.saveOrRollback()
        XCTAssertTrue(waitForAllGroupsToBeEmptyWithTimeout(0.5))
        
        // then
        XCTAssertEqual(observer.notifications.count, 1)
        guard let changeInfo = observer.notifications.firstObject as? MessageChangeInfo else { return XCTFail("No change info") }
        XCTAssertTrue(changeInfo.imageChanged)
    }
    
    // MARK: - Helper
    
    private func createLinkPreviewAndKeys(assetID: String, article: Bool = true, otrKey: NSData? = nil, sha256: NSData? = nil) -> (preview: ZMLinkPreview, otrKey: NSData?, sha256: NSData?) {
        let URL = "http://www.example.com"
        
        if article {
            let assetBuilder = ZMAsset.builder()
            let remoteBuilder = ZMAssetRemoteData.builder()
            let (otr, sha) = (otrKey ?? NSData.randomEncryptionKey(), sha256 ?? NSData.zmRandomSHA256Key())
            remoteBuilder.setAssetId(assetID)
            remoteBuilder.setOtrKey(otr)
            remoteBuilder.setSha256(sha)
            assetBuilder.setUploadedBuilder(remoteBuilder)
            let preview = ZMLinkPreview.linkPreview(withOriginalURL: URL, permanentURL: URL, offset: 42, title: "Title", summary: "Summary", imageAsset: assetBuilder.build(), tweet: nil)
            return (preview, otr, sha)
        } else {
            let tweet = ZMTweet.tweet(withAuthor: "Author", username: "UserName")
            let preview = ZMLinkPreview.linkPreview(withOriginalURL: URL, permanentURL: URL, offset: 42, title: "Title", summary: "Summary", imageAsset: nil, tweet: tweet)
            return (preview, nil, nil)
        }
    }
    
    private func fireSyncCompletedNotification() {
        // ManagedObjectContextObserver does not process all changes until the sync is done
        NSNotificationCenter.defaultCenter().postNotificationName("ZMApplicationDidEnterEventProcessingStateNotification", object: nil, userInfo: nil)
    }

}

