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
@testable import zmessaging

// MARK: - Tests setup
class LinkPreviewAssetUploadRequestStrategyTests: MessagingTest {
    
    fileprivate var sut: LinkPreviewAssetUploadRequestStrategy!
    fileprivate var authStatus: MockAuthenticationStatus!
    
    override func setUp() {
        super.setUp()
        
        self.authStatus = MockAuthenticationStatus(phase: .authenticated)
        self.sut = LinkPreviewAssetUploadRequestStrategy(authenticationStatus: authStatus, managedObjectContext: self.syncMOC)
    }
    
    /// Creates a message that should generate request
    func createMessage(_ text: String, linkPreviewState: ZMLinkPreviewState = .waitingToBeProcessed, linkPreview: LinkPreview) -> ZMClientMessage {
        let conversation = ZMConversation.insertNewObject(in: self.syncMOC)
        conversation.remoteIdentifier = UUID.create()
        
        let message = conversation.appendMessage(withText: text) as! ZMClientMessage
        message.linkPreviewState = linkPreviewState
        message.add(ZMGenericMessage(text: text, linkPreview: linkPreview.protocolBuffer, nonce: message.nonce.transportString()).data())
        self.syncMOC.saveOrRollback()
        
        return message
    }
    
    func createArticle() -> Article {
        let article = Article(
            originalURLString: "example.com/article",
            permamentURLString: "https://example.com/permament",
            offset: 0
        )
        article.title = "title"
        article.summary = "summary"
        article.imageData = [mediumJPEGData()]
        
        return article
    }
    
    /// Forces the strategy to process the message
    func process(_ strategy: LinkPreviewAssetUploadRequestStrategy, message: ZMClientMessage) {
        strategy.contextChangeTrackers.forEach {
            $0.objectsDidChange(Set(arrayLiteral: message))
        }
    }
    
    func completeRequest(_ request: ZMTransportRequest?, HTTPStatus: Int) {
        request?.complete(with: ZMTransportResponse(payload: [] as ZMTransportData, httpStatus: HTTPStatus, transportSessionError: nil))
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
    }
    
    func encryptLinkPreview(inMessage message: ZMClientMessage) -> (Data, Data) {
        let otrKey = "1".data(using: String.Encoding.utf8, allowLossyConversion: false)!
        let sha256 = "2".data(using: String.Encoding.utf8, allowLossyConversion: false)!
        
        var linkPreview = message.genericMessage!.text.linkPreview.first as! ZMLinkPreview
        linkPreview = linkPreview.update(withOtrKey: otrKey, sha256: sha256)
        
        message.add(ZMGenericMessage.init(text: (message.textMessageData?.messageText)!, linkPreview: linkPreview, nonce: message.nonce.transportString()).data())
        
        return (otrKey, sha256)
    }
    
    func completeRequest(_ message: ZMClientMessage, request: ZMTransportRequest?, assetKey: String, token: String) {
        let response = ZMTransportResponse(payload: ["key" : assetKey, "token": token] as ZMTransportData, httpStatus: 201, transportSessionError: nil)
        _ = sut.updateUpdatedObject(message, requestUserInfo: nil, response: response, keysToParse: [ZMClientMessageLinkPreviewStateKey])
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
    }
}

// MARK: - Tests
extension LinkPreviewAssetUploadRequestStrategyTests {
    
    func testThatItCreatesRequestForProcessedLinkPreview() {
        // given
        let article = createArticle()
        let message = createMessage(article.permanentURL!.absoluteString, linkPreviewState: .processed, linkPreview: article)
        syncMOC.zm_imageAssetCache.storeAssetData(message.nonce, format: .medium, encrypted: true, data: article.imageData.first!)
        
        syncMOC.saveOrRollback()
        process(sut, message: message)
        
        // when
        let request = sut.nextRequest()
        
        // then
        XCTAssertNotNil(request)
        XCTAssertEqual(request?.path, "/assets/v3")
        XCTAssertEqual(request?.method, ZMTransportRequestMethod.methodPOST)
    }
    
    func testThatItDoesntCreateUnauthenticatedRequests() {
        // given
        let article = createArticle()
        let message = createMessage(article.permanentURL!.absoluteString, linkPreviewState: .processed, linkPreview: article)
        self.syncMOC.zm_imageAssetCache.storeAssetData(message.nonce, format: .medium, encrypted: true, data: article.imageData.first!)
        process(sut, message: message)
        authStatus.mockPhase = .unauthenticated
        
        // when
        let request = sut.nextRequest()
        
        // then
        XCTAssertNil(request)
    }
    
    func testThatItDoesntCreateRequestsForUnprocessedLinkPreview() {
        // given
        let article = createArticle()
        let message = createMessage(article.permanentURL!.absoluteString, linkPreviewState: .waitingToBeProcessed, linkPreview: article)
        self.syncMOC.zm_imageAssetCache.storeAssetData(message.nonce, format: .medium, encrypted: true, data: article.imageData.first!)
        process(sut, message: message)
        
        // when
        let request = sut.nextRequest()
        
        // then
        XCTAssertNil(request)
    }
    
    func testThatItDoesntCreateRequestsForLinkPreviewStateDone() {
        // given
        let article = createArticle()
        let message = createMessage(article.permanentURL!.absoluteString, linkPreviewState: .done, linkPreview: article)
        self.syncMOC.zm_imageAssetCache.storeAssetData(message.nonce, format: .medium, encrypted: true, data: article.imageData.first!)
        process(sut, message: message)
        
        // when
        let request = sut.nextRequest()
        
        // then
        XCTAssertNil(request)
    }
    
    func testThatItDoesNotCreateARequestIfThereIsNoImageInTheCache() {
        // given
        let article = createArticle()
        let message = createMessage(article.permanentURL!.absoluteString, linkPreviewState: .processed, linkPreview: article)
        process(sut, message: message)
        
        // when & then
        XCTAssertNil(sut.nextRequest())
    }
    
    func testThatItUpdatesMessageWithAssetKeyAndToken() {
        // given
        let article = createArticle()
        let message = createMessage(article.permanentURL!.absoluteString, linkPreviewState: .processed, linkPreview: article)
        let (otrKey, sha256) = encryptLinkPreview(inMessage: message);
        
        syncMOC.zm_imageAssetCache.storeAssetData(message.nonce, format: .medium, encrypted: true, data: article.imageData.first!)
        _ = encryptLinkPreview(inMessage: message)
        message.linkPreviewState = .waitingToBeProcessed
        syncMOC.saveOrRollback()
        
        process(sut, message: message)
        let request = sut.nextRequest()
        
        let assetKey = "key123"
        let token = "qJ8JPFLsiYGx7fnrlL+7Yk9="
        
        // when
        completeRequest(message, request: request, assetKey: assetKey, token: token)
        
        // then
        let linkPreviews = message.genericMessage!.text.linkPreview as! [ZMLinkPreview]
        let articleProtocol: ZMArticle = linkPreviews.first!.article
        XCTAssertEqual(articleProtocol.image.uploaded.otrKey, otrKey)
        XCTAssertEqual(articleProtocol.image.uploaded.sha256, sha256)
        XCTAssertEqual(articleProtocol.image.uploaded.assetId, assetKey)
        XCTAssertEqual(articleProtocol.image.uploaded.assetToken, token)
    }
    
    func testThatItUpdatesTheLinkPreviewState() {
        // given
        let article = createArticle()
        let message = createMessage(article.permanentURL!.absoluteString, linkPreviewState: .processed, linkPreview: article)
        _ = encryptLinkPreview(inMessage: message)
        syncMOC.zm_imageAssetCache.storeAssetData(message.nonce, format: .medium, encrypted: true, data: article.imageData.first!)
        message.linkPreviewState = .processed
        syncMOC.saveOrRollback()
        
        process(sut, message: message)
        let request = sut.nextRequest()
        
        let assetKey = "key123"
        let token = "qJ8JPFLsiYGx7fnrlL+7Yk9="
        
        // when
        completeRequest(message, request: request, assetKey: assetKey, token: token)
        
        // then
        XCTAssertEqual(message.linkPreviewState, ZMLinkPreviewState.uploaded)
    }
    
}
