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

// MARK: - Fakes
@objc class FakeClientRegistrationStatus : NSObject, ZMClientClientRegistrationStatusProvider {
    
    var readyToUse : Bool = true
    
    var currentClientReadyToUse : Bool {
        return self.readyToUse
    }
    
    func didDetectCurrentClientDeletion() {
        // noop
    }
}

private class FakeCancelationProvider : NSObject, ZMRequestCancellation {
    
    var cancelledIdentifiers = [ZMTaskIdentifier]()
    
    @objc func cancelTask(with identifier: ZMTaskIdentifier) {
        cancelledIdentifiers.append(identifier)
    }
}

@objc class FakeZMURLSessionDelegate: NSObject, ZMURLSessionDelegate {
    @objc func urlSessionDidReceiveData(_ URLSession: ZMURLSession) {}
    @objc func urlSession(_ URLSession: ZMURLSession, dataTask: URLSessionDataTask, didReceive didReceiveResponse: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {}
    @objc func urlSessionDidFinishEvents(forBackgroundURLSession URLSession: ZMURLSession) {}
    @objc func urlSession(_ URLSession: ZMURLSession, taskDidComplete: URLSessionTask, transportRequest: ZMTransportRequest, responseData:Data) {}
}

private let testDataURL = Bundle(for: FilePreprocessorTests.self).url(forResource: "Lorem Ipsum", withExtension: "txt")!
private let testData = try! Data(contentsOf: testDataURL)

// MARK: - Tests setup
class FileUploadRequestStrategyTests: MessagingTest {

    fileprivate var sut: FileUploadRequestStrategy!
    fileprivate var authStatus: MockAuthenticationStatus!
    fileprivate var cancellationProvider: FakeCancelationProvider!
	fileprivate var clientRegistrationStatus : FakeClientRegistrationStatus!
    
    override func setUp() {
        super.setUp()
        createSelfClient()
        self.authStatus = MockAuthenticationStatus(phase: .authenticated)
        self.cancellationProvider = FakeCancelationProvider()
		self.clientRegistrationStatus = FakeClientRegistrationStatus()
        self.sut = FileUploadRequestStrategy(
            authenticationStatus: self.authStatus,
			clientRegistrationStatus: self.clientRegistrationStatus,
            managedObjectContext: self.syncMOC,
            taskCancellationProvider: self.cancellationProvider
        )
    }
    
    /// Creates a message that should generate request
    func createMessage(_ name: String, uploadState: ZMAssetUploadState = .uploadingPlaceholder, inConversation: ZMConversation? = nil, thumbnail: Data? = nil, url: URL = testDataURL) -> ZMAssetClientMessage {
        let conversation = inConversation ?? ZMConversation.insertNewObject(in: self.syncMOC)
        conversation.remoteIdentifier = UUID.create()
        // This is a video metadata since it's the only file type which supports thumbnails at the moment.
        let msg = conversation.appendMessage(with: ZMVideoMetadata(fileURL: url, thumbnail: thumbnail)) as! ZMAssetClientMessage
        msg.uploadState = uploadState
        self.syncMOC.saveOrRollback()
        return msg
    }
    
    func createOtherClientAndConversation() -> (UserClient, ZMConversation) {
        let otherUser = ZMUser.insertNewObject(in: syncMOC)
        otherUser.remoteIdentifier = UUID.create()
        let otherClient = createClient(for: otherUser, createSessionWithSelfUser: true)
        let conversation = ZMConversation.insertNewObject(in: syncMOC)
        conversation.conversationType = .group
        conversation.addParticipant(otherUser)
        XCTAssertTrue(syncMOC.saveOrRollback())
        
        return (otherClient, conversation)
    }

    /// Forces the strategy to process the message
    func process(_ strategy: FileUploadRequestStrategy, message: ZMAssetClientMessage) {
        // first change will start preprocessing
        strategy.contextChangeTrackers.forEach { $0.objectsDidChange(Set(arrayLiteral: message)) }
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // second change will make it be picked up by uploader
        strategy.contextChangeTrackers.forEach { $0.objectsDidChange(Set(arrayLiteral: message)) }
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
    }
    
    func completeRequest(_ request: ZMTransportRequest?, HTTPStatus: Int) {
        request?.complete(with: ZMTransportResponse(payload: [] as ZMTransportData, httpStatus: HTTPStatus, transportSessionError: nil))
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
    }
}

// MARK: - Request generation
extension FileUploadRequestStrategyTests {

    func testThatItGeneratesARequestForAFileMessageThatIsPreprocessed() {
        
        // given
        let (otherClient, conversation) = createOtherClientAndConversation()

        let msg = createMessage("foo", inConversation: conversation)
        self.process(sut, message: msg)
        
        // when
        let placeholderRequest = sut.nextRequest() // Asset.Original request (message-add)
        
        guard let msgConversation = msg.conversation else { return XCTFail("message conversation was nil") }
        
        // then
        XCTAssertNotNil(placeholderRequest)
        guard let requestUploaded = placeholderRequest else { return XCTFail() }
        XCTAssertEqual(requestUploaded.path, "/conversations/\(msgConversation.remoteIdentifier!.transportString())/otr/messages")
        XCTAssertEqual(requestUploaded.method, ZMTransportRequestMethod.methodPOST)
        
        guard let genericMessage = decryptedMessage(fromRequestData: requestUploaded.binaryData!, forClient: otherClient) else { return XCTFail() }
        XCTAssertFalse(genericMessage.asset.hasNotUploaded())
        XCTAssertTrue(genericMessage.asset.hasOriginal())
        let original = genericMessage.asset.original!
        XCTAssertEqual(original.name, msg.filename)
        XCTAssertEqual(original.mimeType, msg.mimeType)
        XCTAssertEqual(original.size, msg.size)
        XCTAssertFalse(genericMessage.asset.hasUploaded())
    }
    
    func testThatItSets_UploadingThumbnail_OnMessageWhenAssetOriginalRequestCompletesSuccesfully_Video() {
        
        // given
        guard let url = Bundle(for: type(of: self)).url(forResource: "video", withExtension:"mp4") else { return XCTFail() }
        let msg = createMessage(name!, thumbnail: mediumJPEGData(), url: url)
        process(sut, message: msg)
        XCTAssertEqual(msg.uploadState, ZMAssetUploadState.uploadingPlaceholder)
        
        // when
        let placeholderRequest = sut.nextRequest() // Asset.Original request (message-add)
        completeRequest(placeholderRequest, HTTPStatus: 201)
        
        // then
        XCTAssertEqual(msg.uploadState, ZMAssetUploadState.uploadingThumbnail)
        XCTAssertEqual(msg.transferState, ZMFileTransferState.uploading)
    }
    
    
    func testThatItSets_UploadingThumbnail_OnMessageWhenAssetOriginalRequestCompletesSuccesfully_Text() {
        
        // given
        guard let url = Bundle(for: type(of: self)).url(forResource: "Lorem Ipsum", withExtension:"txt") else { return XCTFail() }
        let msg = createMessage(name!, thumbnail: mediumJPEGData(), url: url)
        process(sut, message: msg)
        XCTAssertEqual(msg.uploadState, ZMAssetUploadState.uploadingPlaceholder)
        
        // when
        let placeholderRequest = sut.nextRequest() // Asset.Original request (message-add)
        completeRequest(placeholderRequest, HTTPStatus: 201)
        
        // then
        XCTAssertEqual(msg.uploadState, ZMAssetUploadState.uploadingThumbnail)
        XCTAssertEqual(msg.transferState, ZMFileTransferState.uploading)
    }
    
    func testThatItSets_UploadingFullAsset_OnMessageWithoutThumbnail_Text() {
        
        // given
        guard let url = Bundle(for: type(of: self)).url(forResource: "Lorem Ipsum", withExtension:"txt") else { return XCTFail() }
        let msg = createMessage(name!, thumbnail: nil, url: url)
        process(sut, message: msg)
        XCTAssertEqual(msg.uploadState, ZMAssetUploadState.uploadingPlaceholder)
        
        // when
        let placeholderRequest = sut.nextRequest() // Asset.Original request (message-add)
        completeRequest(placeholderRequest, HTTPStatus: 201)
        
        // then
        XCTAssertEqual(msg.uploadState, ZMAssetUploadState.uploadingFullAsset)
        XCTAssertEqual(msg.transferState, ZMFileTransferState.uploading)
    }

    
    func testThatItSets_UploadingFullAsset_OnVideoFileMessageWhenTheThumbnailRequestCompletesSuccesfully() {
        
        // given
        guard let url = Bundle(for: type(of: self)).url(forResource: "video", withExtension:"mp4") else { return XCTFail() }
        let msg = createMessage(name!, thumbnail: mediumJPEGData(), url: url)
        self.process(sut, message: msg)
        XCTAssertEqual(msg.uploadState, ZMAssetUploadState.uploadingPlaceholder)
        
        // when
        guard let placeholderRequest = sut.nextRequest() else { return XCTFail("Unable to create placeholder request") } // Asset.Original request (message-add / .UploadingPlaceholder)
        completeRequest(placeholderRequest, HTTPStatus: 201)
        XCTAssertEqual(placeholderRequest.path, "/conversations/\(msg.conversation!.remoteIdentifier!.transportString())/otr/messages")
        XCTAssertEqual(placeholderRequest.method, ZMTransportRequestMethod.methodPOST)
        XCTAssertEqual(msg.uploadState, ZMAssetUploadState.uploadingThumbnail)
        
        guard let thumbnailRequest = sut.nextRequest() else { return XCTFail("Unable to create thumbnail request") } // Asset.Preview request (message-add / .UploadingThumbnail)
        completeRequest(thumbnailRequest, HTTPStatus: 201)
        XCTAssertEqual(thumbnailRequest.path, "/conversations/\(msg.conversation!.remoteIdentifier!.transportString())/otr/assets")
        XCTAssertEqual(thumbnailRequest.method, ZMTransportRequestMethod.methodPOST)
        
        // then
        XCTAssertEqual(msg.uploadState, ZMAssetUploadState.uploadingFullAsset)
        XCTAssertEqual(msg.transferState, ZMFileTransferState.uploading)

        // when
        guard let fullRequest = sut.nextRequest() else { return XCTFail("Unable to create full asset request") } // Asset.Uploaded request (message-add / .UploadingFullAsset)
        completeRequest(fullRequest, HTTPStatus: 201)
        
        // then
        XCTAssertEqual(fullRequest.path, "/conversations/\(msg.conversation!.remoteIdentifier!.transportString())/otr/assets")
        XCTAssertEqual(fullRequest.method, ZMTransportRequestMethod.methodPOST)
        XCTAssertNil(sut.nextRequest())
    }
    
    func testThatItSets_UploadingFullAsset_OnFileMessageWhenThePlaceholderRequestCompletesSuccesfully() {
        
        // given
        let msg = createMessage(name!)
        self.process(sut, message: msg)
        XCTAssertEqual(msg.uploadState, ZMAssetUploadState.uploadingPlaceholder)
        
        // when
        guard let placeholderRequest = sut.nextRequest() else { return XCTFail("Unable to create placeholder request") } // Asset.Original request (message-add / .UploadingPlaceholder)
        completeRequest(placeholderRequest, HTTPStatus: 201)
        XCTAssertEqual(placeholderRequest.path, "/conversations/\(msg.conversation!.remoteIdentifier!.transportString())/otr/messages")
        XCTAssertEqual(placeholderRequest.method, ZMTransportRequestMethod.methodPOST)
        
        // then
        XCTAssertEqual(msg.uploadState, ZMAssetUploadState.uploadingFullAsset)
        XCTAssertEqual(msg.transferState, ZMFileTransferState.uploading)
        
        // when
        guard let fullRequest = sut.nextRequest() else { return XCTFail("Unable to create full asset request") } // Asset.Uploaded request (message-add / .UploadingFullAsset)
        completeRequest(fullRequest, HTTPStatus: 201)
        
        // then
        XCTAssertEqual(fullRequest.path, "/conversations/\(msg.conversation!.remoteIdentifier!.transportString())/otr/assets")
        XCTAssertEqual(fullRequest.method, ZMTransportRequestMethod.methodPOST)
        XCTAssertNil(sut.nextRequest())
    }
    
    func testThatItDoesNotGeneratesARequestWhenNotAuthenticated() {
        
        // given
		self.authStatus.mockPhase = .unauthenticated
        let msg = createMessage("foo")
        self.process(sut, message: msg)
        
        // when
        let reqUploaded = sut.nextRequest() // uploaded
        
        // then
        XCTAssertNil(reqUploaded)
    }
    
    func testThatItDoesNotGeneratesARequestWhenStillRegisteringClient() {
        
        // given
		self.clientRegistrationStatus.readyToUse = false
        let msg = createMessage("foo")
        self.process(sut, message: msg)
        
        // when
        let reqUploaded = sut.nextRequest() // uploaded
        
        // then
        XCTAssertNil(reqUploaded)
    }
    
    func testThatItDoesNotGenerateARequestForTheNextMessageWhenThereIsAPreviousOriginalBeingUploaded() {
        
        // given
        let msg1 = createMessage("foo")
        self.process(sut, message: msg1)
        let msg2 = createMessage("foo", inConversation: msg1.conversation)
        self.process(sut, message: msg2)
        
        // when
        _ = sut.nextRequest() // original
        let nextRequest = sut.nextRequest()
        
        
        // then
        XCTAssertNil(nextRequest)
    }
    
    func testThatItGeneratesRequestForTheNextMessageWhenThereIsAPreviousFileBeingUploaded() {
        
        // given
        let msg1 = createMessage("foo")
        self.process(sut, message: msg1)
        
        guard let msg1Conversation = msg1.conversation else { return XCTFail("message conversation was nil") }
        
        // first request: msg1 original
        let msg1Original = sut.nextRequest() // original
        XCTAssertEqual(msg1Original?.path, "/conversations/\(msg1Conversation.remoteIdentifier!.transportString())/otr/messages")
        
        // when
        msg1Original?.complete(with: ZMTransportResponse(payload: [] as ZMTransportData, httpStatus: 200, transportSessionError: nil))
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        self.syncMOC.saveOrRollback()
        self.process(sut, message: msg1)
        
        // second request: msg1 file
        let msg1File = sut.nextRequest()
        XCTAssertEqual(msg1File?.path, "/conversations/\(msg1Conversation.remoteIdentifier!.transportString())/otr/assets")
        
        // Given 
        let msg2 = createMessage("foo", inConversation: msg1.conversation)
        self.process(sut, message: msg2)
        
        // third request: msg2 original
        let msg2Original = sut.nextRequest()
        XCTAssertEqual(msg2Original?.path, "/conversations/\(msg1Conversation.remoteIdentifier!.transportString())/otr/messages")
        msg2Original?.complete(with: ZMTransportResponse(payload: [] as ZMTransportData, httpStatus: 200, transportSessionError: nil))
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        self.syncMOC.saveOrRollback()
        self.process(sut, message: msg1)
    }
}

// MARK: - Parse response
extension FileUploadRequestStrategyTests {
    
    func testThatItMarksAnUploadedFileAsFailedToUploadWhenTheRequestCompletesUnsuccesfully() {
        
        // given
        let msg = createMessage("foo")
        self.process(sut, message: msg)
        XCTAssertEqual(msg.uploadState, ZMAssetUploadState.uploadingPlaceholder)
        
        // when
        let placeholderRequest = sut.nextRequest() // Asset.Original request (message-add)
        completeRequest(placeholderRequest, HTTPStatus: 400)
        
        // then
        XCTAssertEqual(msg.transferState, ZMFileTransferState.failedUpload)
        XCTAssertEqual(msg.uploadState, ZMAssetUploadState.uploadingFailed)
        let nextRequest = sut.nextRequest()
        XCTAssertNil(nextRequest)
    }
    
    func testThatItDoesGenerateTheRequestToUploadTheMediumAfterThePreviewCompletedSuccessfully() {
        
        // given
        let (otherClient, conversation) = createOtherClientAndConversation()
        let msg = createMessage("foo", inConversation: conversation)
        self.process(sut, message: msg)
        XCTAssertEqual(msg.uploadState, ZMAssetUploadState.uploadingPlaceholder)
        
        // when
        let placeholderRequest = sut.nextRequest() // Asset.Original request (message-add)
        completeRequest(placeholderRequest, HTTPStatus: 201)
        let uploadedRequest = sut.nextRequest() // Uploaded request (asset-add)
        syncMOC.saveOrRollback()

        guard let msgConversation = msg.conversation else { return XCTFail("Conversation was nil") }
        
        // then
        XCTAssertEqual(msg.uploadState, ZMAssetUploadState.uploadingFullAsset)
        XCTAssertNotNil(placeholderRequest)
        XCTAssertNotNil(uploadedRequest)
        XCTAssertNotNil(uploadedRequest?.fileUploadURL)
        XCTAssertEqual(uploadedRequest?.path, "/conversations/\(msgConversation.remoteIdentifier!.transportString())/otr/assets")
     
        guard let request = uploadedRequest,
            let requestMultipart = try? Data(contentsOf: request.fileUploadURL!) else {
                return XCTFail("No data at fileUploadURL")
        }
        
        let genericPartData = (requestMultipart as NSData).multipartDataItemsSeparated(withBoundary: "frontier").first as! ZMMultipartBodyItem
        guard let genericMessage = decryptedMessage(fromRequestData: genericPartData.data, forClient: otherClient) else { return XCTFail() }
        XCTAssertTrue(genericMessage.asset.hasOriginal())
        XCTAssertFalse(genericMessage.asset.hasNotUploaded())
        XCTAssertTrue(genericMessage.asset.hasUploaded())
        XCTAssertNil(sut.nextRequest())
    }
    
    func testThatItUpdatesTheMessageWithTheAssetIDFromTheUploadedReponseHeader() {
        
        // given
        let msg = createMessage(name!, uploadState: .uploadingFullAsset)
        self.process(sut, message: msg)
        guard let request = sut.nextRequest() else { return XCTFail() }
        
        // when
        let assetId = UUID.create()
        let response = ZMTransportResponse(payload: [] as ZMTransportData, httpStatus: 200, transportSessionError: nil, headers: ["Location": assetId.transportString()])
        request.complete(with: response)
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertTrue(msg.delivered)
        XCTAssertEqual(msg.transferState, ZMFileTransferState.downloaded)
        XCTAssertEqual(msg.assetId, assetId)
    }
    
    func testThatItDeletesDataForAnUploadedFile() {
        
        // given
        let msg = createMessage(name!, uploadState: .uploadingFullAsset)
        self.process(sut, message: msg)
        guard let request = sut.nextRequest() else { return XCTFail() }
        
        // when
        request.complete(with: ZMTransportResponse(payload: [] as ZMTransportData, httpStatus: 200, transportSessionError: nil))
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertNil(self.syncMOC.zm_fileAssetCache.assetData(msg.nonce, fileName: msg.filename!, encrypted: true))
    }
    
    func testThatItMarksAFailedFile_OriginalFailed() {
        
        // given
        let msg = createMessage("foo")
        self.process(sut, message: msg)
        guard let request = sut.nextRequest() else { return XCTFail() }
        
        // when
        request.complete(with: ZMTransportResponse(payload: [] as ZMTransportData, httpStatus: 400, transportSessionError: nil))
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertFalse(msg.delivered)
        XCTAssertEqual(msg.transferState, ZMFileTransferState.failedUpload)
    }
    
    func testThatItMarksAFailedFile_UploadedFailed() {
        
        // given
        let msg = createMessage("foo")
        self.process(sut, message: msg)
        guard let request = sut.nextRequest() else { return XCTFail() }
        
        // when
        request.complete(with: ZMTransportResponse(payload: [] as ZMTransportData, httpStatus: 400, transportSessionError: nil))
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertFalse(msg.delivered)
        XCTAssertEqual(msg.transferState, ZMFileTransferState.failedUpload)
    }
    
    func testThatItMarksAFailedFile_UploadedFailed_TemporaryError() {
        
        // given
        let msg = createMessage("foo")
        self.process(sut, message: msg)
        guard let request = sut.nextRequest() else { return XCTFail() }
        
        // when
        request.complete(with: ZMTransportResponse(payload: [] as ZMTransportData, httpStatus: 500, transportSessionError: nil))
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertFalse(msg.delivered)
        XCTAssertEqual(msg.transferState, ZMFileTransferState.failedUpload)
    }
    
    func testThatItDeletesDataForAFailedFile_OriginalFailed() {
        
        // given
        let msg = createMessage(name!)
        self.process(sut, message: msg)
        guard let request = sut.nextRequest() else { return XCTFail() }
        
        // when
        request.complete(with: ZMTransportResponse(payload: [] as ZMTransportData, httpStatus: 400, transportSessionError: nil))
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertNil(self.syncMOC.zm_fileAssetCache.assetData(msg.nonce, fileName: msg.filename!, encrypted: true))
    }
    
    func testThatItDeletesUnencryptedDataForAFailedFile_UploadedFailed() {
        
        // given
        let msg = createMessage(name!, uploadState: .uploadingFullAsset)
        self.process(sut, message: msg)
        guard let request = sut.nextRequest() else { return XCTFail() }
        
        // when
        request.complete(with: ZMTransportResponse(payload: [] as ZMTransportData, httpStatus: 400, transportSessionError: nil))
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertNotNil(self.syncMOC.zm_fileAssetCache.assetData(msg.nonce, fileName: msg.filename!, encrypted: true))
        XCTAssertNotNil(self.syncMOC.zm_fileAssetCache.assetData(msg.nonce, fileName: msg.filename!, encrypted: false))
    }
    
    func testThatItSendsNotificaitonForAnUploadedFile() {
        
        // given
        let msg = createMessage(name!, uploadState: .uploadingFullAsset)
        self.process(sut, message: msg)
        guard let request = sut.nextRequest() else { return XCTFail() }
        
        request.markStartOfUploadTimestamp()
        let notificationExpectation = self.expectation(description: "Notification fired")
        
        let _ = NotificationCenter.default.addObserver(forName: NSNotification.Name(rawValue: FileUploadRequestStrategyNotification.uploadFinishedNotificationName), object: nil, queue: .main) { notification in
            XCTAssertNotNil(notification.userInfo![FileUploadRequestStrategyNotification.requestStartTimestampKey])
            notificationExpectation.fulfill()
        }
        // when
        let assetId = UUID.create()
        let response = ZMTransportResponse(payload: [] as ZMTransportData, httpStatus: 200, transportSessionError: nil, headers: ["Location": assetId.transportString()])
        request.complete(with: response)
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertTrue(self.waitForCustomExpectations(withTimeout: 0.5))
    }
    
    func testThatItSendsNotificaitonForAFailedFile() {
        
        // given
        let msg = createMessage("foo")
        self.process(sut, message: msg)
        guard let request = sut.nextRequest() else { return XCTFail() }
        request.markStartOfUploadTimestamp()
        let notificationExpectation = self.expectation(description: "Notification fired")
        
        let _ = NotificationCenter.default.addObserver(forName: NSNotification.Name(rawValue: FileUploadRequestStrategyNotification.uploadFailedNotificationName), object: nil, queue: .main) { notification in
            XCTAssertNotNil(notification.userInfo![FileUploadRequestStrategyNotification.requestStartTimestampKey])
            notificationExpectation.fulfill()
        }
        // when
        request.complete(with: ZMTransportResponse(payload: [] as ZMTransportData, httpStatus: 400, transportSessionError: nil))
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertTrue(self.waitForCustomExpectations(withTimeout: 0.5))
    }
    
    func testThatItDoesNotCancelCurrentlyRunningRequestWhenTheUploadFails_FullAsset() {
        
        // given
        let msg = createMessage(name!, uploadState: .uploadingFullAsset)
        let identifier = ZMTaskIdentifier(identifier: 12345, sessionIdentifier: "background-session")
        msg.associatedTaskIdentifier = identifier
        process(sut, message: msg)
        guard let request = sut.nextRequest() else { return XCTFail() }
        XCTAssertEqual(cancellationProvider.cancelledIdentifiers.count, 0)
        
        // when
        request.complete(with: ZMTransportResponse(payload: [] as ZMTransportData, httpStatus: 400, transportSessionError: nil))
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then there should not be a running upload request as the upload failed by itself,
        // next request would be the Asset.NotUploaded request
        XCTAssertEqual(cancellationProvider.cancelledIdentifiers.count, 0)
    }
    
    func testThatItDoesNotCancelCurrentlyRunningRequestWhenTheUploadFails_Thumbnail() {
        
        // given
        guard let url = Bundle(for: type(of: self)).url(forResource: "video", withExtension:"mp4") else { return XCTFail() }
        let msg = createMessage(name!, uploadState: .uploadingThumbnail, thumbnail: mediumJPEGData(), url: url)
        
        let identifier = ZMTaskIdentifier(identifier: 12345, sessionIdentifier: "background-session")
        msg.associatedTaskIdentifier = identifier
        process(sut, message: msg)
        
        XCTAssertEqual(msg.genericAssetMessage?.asset.preview.hasImage(), true)
        guard let request = sut.nextRequest() else { return XCTFail() }
        XCTAssertEqual(cancellationProvider.cancelledIdentifiers.count, 0)
        
        // when
        request.complete(with: ZMTransportResponse(payload: [] as ZMTransportData, httpStatus: 400, transportSessionError: nil))
        msg.fileMessageData!.cancelTransfer()
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then there should not be a running upload request as the upload failed by itself,
        // next request would be the Asset.NotUploaded request
        XCTAssertEqual(cancellationProvider.cancelledIdentifiers.count, 0)
    }
    
    func testThatItCancelsCurrentlyRunningRequestWhenTheUploadIsCancelledAndItCreatesThe_NotUploaded_Request() {
        
        // given
        let msg = createMessage(name!, uploadState: .uploadingFullAsset)
        let identifier = ZMTaskIdentifier(identifier: 12345, sessionIdentifier: "background-session")
        msg.associatedTaskIdentifier = identifier
        process(sut, message: msg)
        guard let request = sut.nextRequest() else { return XCTFail() }
        XCTAssertEqual(cancellationProvider.cancelledIdentifiers.count, 0)
        
        // when
        msg.fileMessageData?.cancelTransfer()
        sut.objectsDidChange(Set(arrayLiteral: msg))
        request.complete(with: ZMTransportResponse(payload: [] as ZMTransportData, httpStatus: 0, transportSessionError: NSError.tryAgainLaterError() as Error))
        
        
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        guard let _ = sut.nextRequest() else { return XCTFail("Request was nil") } // Asset.NotUploaded
        
        // then
        XCTAssertEqual(cancellationProvider.cancelledIdentifiers.count, 1)
        XCTAssertEqual(cancellationProvider.cancelledIdentifiers.first, identifier)
    }
    
    func testThatItUpdatesTheAssociatedTaskIdentifierWhenTheTaskHasBeenCreated_PlaceholderUpload() {
        // given
        let msg = createMessage(name!) // We did not yet generate the request to upload the Asset.Original
        process(sut, message: msg)
        
        // when
        guard let originalRequest = sut.nextRequest() else { return XCTFail() } // Asset.Original
        originalRequest.callTaskCreationHandlers(withIdentifier: 42, sessionIdentifier: name!)
        
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertNotNil(msg.associatedTaskIdentifier);
        XCTAssertEqual(msg.associatedTaskIdentifier?.sessionIdentifier, name);
        XCTAssertEqual(msg.associatedTaskIdentifier?.identifier, 42);
    }
    
    func testThatItUpdatesTheAssociatedTaskIdentifierWhenTheTaskHasBeenCreated_ThumbnailUpload() {
        // given
        guard let url = Bundle(for: type(of: self)).url(forResource: "video", withExtension:"mp4") else { return XCTFail() }
        let msg = createMessage(name!, uploadState: .uploadingThumbnail, thumbnail: mediumJPEGData(), url: url)
        process(sut, message: msg)
        
        // when
        guard let originalRequest = sut.nextRequest() else { return XCTFail() } // Asset.Preview
        originalRequest.callTaskCreationHandlers(withIdentifier: 42, sessionIdentifier: name!)
        
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertNotNil(msg.associatedTaskIdentifier);
        XCTAssertEqual(msg.associatedTaskIdentifier?.sessionIdentifier, name);
        XCTAssertEqual(msg.associatedTaskIdentifier?.identifier, 42);
    }
    
    func testThatItUpdatesTheAssociatedTaskIdentifierWhenTheTaskHasBeenCreated_FileDataUpload() {
        // given
        let msg = createMessage(name!, uploadState: .uploadingFullAsset) // We did  generate the request to upload the Asset.Original
        process(sut, message: msg)
        
        // when
        guard let originalRequest = sut.nextRequest() else { return XCTFail() } // Asset.Uploaded
        originalRequest.callTaskCreationHandlers(withIdentifier: 42, sessionIdentifier: name!)
        
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertNotNil(msg.associatedTaskIdentifier);
        XCTAssertEqual(msg.associatedTaskIdentifier?.sessionIdentifier, name);
        XCTAssertEqual(msg.associatedTaskIdentifier?.identifier, 42);
    }
    
    func testThatItResetTheAssociatedTaskIdentifierAfterThe_Placeholder_UploadCompleted_Successfully() {
        assertThatItResetsTheAssociatedTaskIdentifier(.uploadingPlaceholder, HTTPStatus: 200)
    }
    
    func testThatItResetTheAssociatedTaskIdentifierAfterThe_Placeholder_UploadCompleted_Failure() {
        assertThatItResetsTheAssociatedTaskIdentifier(.uploadingPlaceholder, HTTPStatus: 401)
    }
    
    func testThatItResetTheAssociatedTaskIdentifierAfterThe_Thumbnail_UploadCompleted_Succesfully() {
        assertThatItResetsTheAssociatedTaskIdentifier(.uploadingThumbnail, HTTPStatus: 200)
    }
    
    func testThatItResetTheAssociatedTaskIdentifierAfterThe_Thumbnail_UploadCompleted_Failure() {
        assertThatItResetsTheAssociatedTaskIdentifier(.uploadingThumbnail, HTTPStatus: 401)
    }
    
    func testThatItResetTheAssociatedTaskIdentifierAfterThe_FileData_UploadCompleted_Succesfully() {
        assertThatItResetsTheAssociatedTaskIdentifier(.uploadingFullAsset, HTTPStatus: 200)
    }
    
    func testThatItResetTheAssociatedTaskIdentifierAfterThe_FileData_UploadCompleted_Failure() {
        assertThatItResetsTheAssociatedTaskIdentifier(.uploadingFullAsset, HTTPStatus: 401)
    }
    
    func assertThatItResetsTheAssociatedTaskIdentifier(_ uploadState: ZMAssetUploadState, HTTPStatus: Int) {
        // given
        let msg: ZMAssetClientMessage
        if uploadState == .uploadingThumbnail {
            guard let url = Bundle(for: type(of: self)).url(forResource: "video", withExtension:"mp4") else { return XCTFail() }
            msg = createMessage(name!, uploadState: .uploadingThumbnail, thumbnail: mediumJPEGData(), url: url)
        } else {
            msg = createMessage(name!, uploadState: uploadState)
        }
        
        process(sut, message: msg)
        guard let originalRequest = sut.nextRequest() else { return XCTFail("Did not generate a request") }

        originalRequest.callTaskCreationHandlers(withIdentifier: 42, sessionIdentifier: name!)
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        XCTAssertNotNil(msg.associatedTaskIdentifier);
        
        // when
        completeRequest(originalRequest, HTTPStatus: HTTPStatus)
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertNil(msg.associatedTaskIdentifier)
    }
    
    func testThatItGeneratesARequestWhenTheFileTransferIsSetTo_NotUploaded_Cancelled_PreviewNotYetUploaded() {
        
        // given
        let (otherClient, conversation) = createOtherClientAndConversation()
        let msg = createMessage(name!, inConversation: conversation)
        process(sut, message: msg)
        XCTAssertEqual(msg.transferState, ZMFileTransferState.uploading)
        
        // when
        msg.fileMessageData?.cancelTransfer()
        
        // then
        XCTAssertEqual(msg.transferState, ZMFileTransferState.cancelledUpload)
        XCTAssertTrue(syncMOC.saveOrRollback())
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        guard let request = sut.nextRequest() else { return XCTFail("Request was nil") }
        guard let msgConversation = msg.conversation else { return XCTFail("Conversation was nil") }
        let expectedPath = "/conversations/\(msgConversation.remoteIdentifier!.transportString())/otr/messages"

        XCTAssertEqual(request.path, expectedPath)
        XCTAssertEqual(request.method, ZMTransportRequestMethod.methodPOST)

        guard let genericMessage = decryptedMessage(fromRequestData: request.binaryData!, forClient: otherClient) else { return XCTFail() }
        XCTAssertTrue(genericMessage.asset.hasNotUploaded())
        XCTAssertTrue(genericMessage.asset.hasOriginal())
        XCTAssertEqual(genericMessage.asset.notUploaded, ZMAssetNotUploaded.CANCELLED)
        XCTAssertFalse(genericMessage.asset.hasUploaded())
        
        // Asset should still be there in case we want to retry
        XCTAssertNotNil(syncMOC.zm_fileAssetCache.assetData(msg.nonce, fileName: msg.filename!, encrypted: true))
        XCTAssertNil(sut.nextRequest())
    }
    
    func testThatItGeneratesARequestWhenTheFileTransferIsSetTo_NotUploaded_Cancelled_ThumbnailUploading() {
        
        // given
        let (otherClient, conversation) = createOtherClientAndConversation()
        guard let url = Bundle(for: type(of: self)).url(forResource: "video", withExtension:"mp4") else { return XCTFail() }
        let msg = createMessage(name!, uploadState: .uploadingThumbnail, inConversation: conversation, thumbnail: mediumJPEGData(), url: url)
        process(sut, message: msg)
        XCTAssertEqual(msg.transferState, ZMFileTransferState.uploading)
        
        // when
        msg.fileMessageData?.cancelTransfer()
        
        // then
        XCTAssertEqual(msg.transferState, ZMFileTransferState.cancelledUpload)
        XCTAssertTrue(syncMOC.saveOrRollback())
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        guard let request = sut.nextRequest() else { return XCTFail("Request was nil") }
        guard let msgConversation = msg.conversation else { return XCTFail("Conversation was nil") }
        let expectedPath = "/conversations/\(msgConversation.remoteIdentifier!.transportString())/otr/messages"

        XCTAssertEqual(request.path, expectedPath)
        XCTAssertEqual(request.method, ZMTransportRequestMethod.methodPOST)
        
        guard let genericMessage = decryptedMessage(fromRequestData: request.binaryData!, forClient: otherClient) else { return XCTFail() }
        XCTAssertTrue(genericMessage.asset.hasNotUploaded())
        XCTAssertTrue(genericMessage.asset.hasOriginal())
        XCTAssertEqual(genericMessage.asset.notUploaded, ZMAssetNotUploaded.CANCELLED)
        XCTAssertFalse(genericMessage.asset.hasUploaded())
        
        // Asset should still be there in case we want to retry
        XCTAssertNotNil(syncMOC.zm_fileAssetCache.assetData(msg.nonce, fileName: msg.filename!, encrypted: true))
        XCTAssertNil(sut.nextRequest())
    }
    
    func testThatItGeneratesARequestWhenTheFileTransferIsSetTo_NotUploaded_Cancelled_ThumbnailUploaded_Video() {
        
        // given
        let (otherClient, conversation) = createOtherClientAndConversation()
        guard let url = Bundle(for: type(of: self)).url(forResource: "video", withExtension:"mp4") else { return XCTFail() }
        let msg = createMessage(name!, uploadState: .uploadingFullAsset, inConversation: conversation, thumbnail: mediumJPEGData(), url: url)
        process(sut, message: msg)
        XCTAssertEqual(msg.transferState, ZMFileTransferState.uploading)
        
        // when
        msg.fileMessageData?.cancelTransfer()
        
        // then
        XCTAssertEqual(msg.transferState, ZMFileTransferState.cancelledUpload)
        XCTAssertTrue(syncMOC.saveOrRollback())
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        guard let request = sut.nextRequest() else { return XCTFail("Request was nil") }
        guard let msgConversation = msg.conversation else { return XCTFail("message conversation was nil") }
        let expectedPath = "/conversations/\(msgConversation.remoteIdentifier!.transportString())/otr/messages"

        XCTAssertEqual(request.path, expectedPath)
        XCTAssertEqual(request.method, ZMTransportRequestMethod.methodPOST)
        
        guard let genericMessage = decryptedMessage(fromRequestData: request.binaryData!, forClient: otherClient) else { return XCTFail() }
        XCTAssertTrue(genericMessage.asset.hasNotUploaded())
        XCTAssertTrue(genericMessage.asset.hasOriginal())
        XCTAssertEqual(genericMessage.asset.notUploaded, ZMAssetNotUploaded.CANCELLED)
        XCTAssertFalse(genericMessage.asset.hasUploaded())
        
        // Asset should still be there in case we want to retry
        XCTAssertNotNil(syncMOC.zm_fileAssetCache.assetData(msg.nonce, fileName: msg.filename!, encrypted: true))
        XCTAssertNil(sut.nextRequest())
    }
    
    func testThatItGeneratesARequestWhenTheFileTransferIsSetTo_NotUploaded_Cancelled_PreviewUploaded() {
        
        // given
        let (otherClient, conversation) = createOtherClientAndConversation()
        let msg = createMessage(name!, uploadState: .uploadingFullAsset, inConversation: conversation)
        process(sut, message: msg)
        XCTAssertEqual(msg.transferState, ZMFileTransferState.uploading)
        
        // when
        msg.fileMessageData?.cancelTransfer()
        
        // then
        XCTAssertEqual(msg.transferState, ZMFileTransferState.cancelledUpload)
        XCTAssertTrue(syncMOC.saveOrRollback())
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        guard let request = sut.nextRequest() else { return XCTFail("Request was nil") }
        let expectedPath = "/conversations/\(msg.conversation!.remoteIdentifier!.transportString())/otr/messages"
        XCTAssertEqual(request.path, expectedPath)
        XCTAssertEqual(request.method, ZMTransportRequestMethod.methodPOST)

        guard let genericMessage = decryptedMessage(fromRequestData: request.binaryData!, forClient: otherClient) else { return XCTFail() }
        XCTAssertTrue(genericMessage.asset.hasNotUploaded())
        XCTAssertTrue(genericMessage.asset.hasOriginal())
        XCTAssertEqual(genericMessage.asset.notUploaded, ZMAssetNotUploaded.CANCELLED)
        XCTAssertFalse(genericMessage.asset.hasUploaded())
        
        // Asset should still be there in case we want to retry
        XCTAssertNotNil(syncMOC.zm_fileAssetCache.assetData(msg.nonce, fileName: msg.filename!, encrypted: true))
        XCTAssertNil(sut.nextRequest())
    }
    
    func testThatItGeneratesARequestWhenTheFileTransferIsSetTo_NotUploaded_Cancelled_PreviewAndOriginalUploaded() {
        
        // given
        let (otherClient, conversation) = createOtherClientAndConversation()
        let msg = createMessage(name!, uploadState: .uploadingFullAsset, inConversation: conversation)
        process(sut, message: msg)
        guard let request = sut.nextRequest() else { return XCTFail("Should return the request to upload Asset.Uploaded") }
        XCTAssertEqual(msg.transferState, ZMFileTransferState.uploading)
        
        // when
        msg.fileMessageData?.cancelTransfer()
        sut.objectsDidChange(Set(arrayLiteral: msg))
        request.complete(with: ZMTransportResponse(payload: [] as ZMTransportData, httpStatus: 0, transportSessionError: NSError.tryAgainLaterError() as Error))
        
        // then
        XCTAssertEqual(msg.transferState, ZMFileTransferState.cancelledUpload)
        XCTAssertTrue(syncMOC.saveOrRollback())
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        guard let secondRequest = sut.nextRequest() else { return XCTFail("Request was nil") }
        let expectedPath = "/conversations/\(msg.conversation!.remoteIdentifier!.transportString())/otr/messages"
        XCTAssertEqual(secondRequest.path, expectedPath)
        XCTAssertEqual(secondRequest.method, ZMTransportRequestMethod.methodPOST)
        
        guard let genericMessage = decryptedMessage(fromRequestData: secondRequest.binaryData!, forClient: otherClient) else { return XCTFail() }
        XCTAssertTrue(genericMessage.asset.hasNotUploaded())
        XCTAssertTrue(genericMessage.asset.hasOriginal())
        XCTAssertEqual(genericMessage.asset.notUploaded, ZMAssetNotUploaded.CANCELLED)
        XCTAssertFalse(genericMessage.asset.hasUploaded())
        
        // Asset should still be there in case we want to retry
        XCTAssertNotNil(syncMOC.zm_fileAssetCache.assetData(msg.nonce, fileName: msg.filename!, encrypted: true))
        XCTAssertNil(sut.nextRequest())
    }
    
    func testThatItCreatesARequestToUploadA_NotUploaded_WhenTheFileDataFailsToUpload() {
        
        // given
        let (otherClient, conversation) = createOtherClientAndConversation()
        let msg = createMessage(name!, uploadState: .uploadingFullAsset, inConversation: conversation)
        
        process(sut, message: msg)
        guard let uploadedRequest = sut.nextRequest() else { return XCTFail("Should return the request to upload Asset.Uploaded") }
        XCTAssertEqual(msg.transferState, ZMFileTransferState.uploading)
        
        // when
        completeRequest(uploadedRequest, HTTPStatus: 401)
        
        // then
        guard let notUploadedRequest = sut.nextRequest() else { return XCTFail("Request was nil") }
        guard let msgConversation = msg.conversation else { return XCTFail("Conversation was nil") }
        let expectedPath = "/conversations/\(msgConversation.remoteIdentifier!.transportString())/otr/messages"

        XCTAssertEqual(notUploadedRequest.path, expectedPath)
        XCTAssertEqual(notUploadedRequest.method, ZMTransportRequestMethod.methodPOST)
        XCTAssertEqual(msg.transferState, ZMFileTransferState.failedUpload)
        
        guard let genericMessage = decryptedMessage(fromRequestData: notUploadedRequest.binaryData!, forClient: otherClient) else { return XCTFail() }
        XCTAssertTrue(genericMessage.asset.hasNotUploaded())
        XCTAssertTrue(genericMessage.asset.hasOriginal())
        XCTAssertEqual(genericMessage.asset.notUploaded, ZMAssetNotUploaded.FAILED)
        XCTAssertFalse(genericMessage.asset.hasUploaded())
        
        // Encrypted Asset should still be there in case we want to retry
        XCTAssertNotNil(syncMOC.zm_fileAssetCache.assetData(msg.nonce, fileName: msg.filename!, encrypted: true))
        XCTAssertNotNil(syncMOC.zm_fileAssetCache.assetData(msg.nonce, fileName: msg.filename!, encrypted: false))
        XCTAssertNil(sut.nextRequest())
    }
    
    
    // MARK: - Decryption Helper
    
    func decryptedMessage(fromRequestData data: Data, forClient client: UserClient) -> ZMGenericMessage? {
        let otrMessage = ZMNewOtrMessage.builder().merge(from: data).build() as? ZMNewOtrMessage
        XCTAssertNotNil(otrMessage, "Unable to generate OTR message")
        let clientEntries = otrMessage?.recipients.flatMap { $0 as? ZMUserEntry }.flatMap { $0.clients }.joined()
        XCTAssertEqual(clientEntries?.count, 1)
        
        let encryptionContext = syncMOC.zm_cryptKeyStore.encryptionContext
        guard let entry = clientEntries?.first as? ZMClientEntry else { XCTFail("Unable to get client entry"); return nil }
        
        var message : ZMGenericMessage?
        encryptionContext.perform { sessionsDirectory in
            do {
                let decryptedData = try sessionsDirectory.decrypt(entry.text, senderClientId: client.remoteIdentifier!)
                message = ZMGenericMessage.builder().merge(from: decryptedData).build() as? ZMGenericMessage
            } catch {
                XCTFail("Failed to decrypt generic message: \(error)")
            }
        }
        return message
    }

    func testThatItRemovesDeletedClients() {
        
        // given
        let msg = createMessage("foo")

        // client and user
        let user = ZMUser.insertNewObject(in: self.syncMOC)
        user.remoteIdentifier = UUID.create()
        let client = UserClient.insertNewObject(in: self.syncMOC)
        client.remoteIdentifier = "abc123123"
        client.user = user
        
        self.syncMOC.saveOrRollback()
        XCTAssertEqual(user.clients.count, 1)
        
        self.process(sut, message: msg)
        guard let request = sut.nextRequest() else { return XCTFail() }
        
        // payload
        let payload: [String : Any] = [
            "time" : "2015-03-11T09:34:00.436Z",
            "deleted" : [
                user.remoteIdentifier!.transportString() : [
                    client.remoteIdentifier!
                ]
            ],
        ]
        
        // when
        request.complete(with: ZMTransportResponse(payload: payload as ZMTransportData, httpStatus: 200, transportSessionError: nil))
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertEqual(user.clients.count, 0)
    }
    
    func testThatItAddMissingClients() {
        
        // given
        let msg = createMessage("foo")
        let clientID = "1234567abc"
        
        // user
        let user = ZMUser.insertNewObject(in: self.syncMOC)
        user.remoteIdentifier = UUID.create()
        
        self.syncMOC.saveOrRollback()
        XCTAssertEqual(user.clients.count, 0)
        
        self.process(sut, message: msg)
        guard let request = sut.nextRequest() else { return XCTFail() }
        
        // payload
        let payload = [
            "missing" : [
                user.remoteIdentifier!.transportString() : [
                    clientID
                ]
            ]
        ]
        
        // when
        request.complete(with: ZMTransportResponse(payload: payload as ZMTransportData, httpStatus: 412, transportSessionError: nil))
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        if let client = user.clients.first {
            XCTAssertEqual(client.remoteIdentifier, clientID)
        } else {
            XCTFail()
        }
    }
    
    func testThatAMessageWithMissingClientsDependsOnThoseClients() {
        
        // given
        let msg = createMessage("foo")
        let clientID = "1234567abc"
        
        // user
        let user = ZMUser.insertNewObject(in: self.syncMOC)
        user.remoteIdentifier = UUID.create()
        
        self.syncMOC.saveOrRollback()
        XCTAssertEqual(user.clients.count, 0)
        
        self.process(sut, message: msg)
        guard let request = sut.nextRequest() else { return XCTFail() }
        
        // payload
        let payload = [
            "missing" : [
                user.remoteIdentifier!.transportString() : [
                    clientID
                ]
            ]
        ]
        
        // when
        request.complete(with: ZMTransportResponse(payload: payload as ZMTransportData, httpStatus: 412, transportSessionError: nil))
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        let nextRequest = sut.nextRequest()
        
        // then
        XCTAssertNil(nextRequest)
    }
}

// MARK: - Preprocessing
extension FileUploadRequestStrategyTests {

    func testThatItPreprocessMessages() {
        
        // given
        let msg = createMessage("foo")
        XCTAssertFalse(msg.isReadyToUploadFile)
        
        // when
        sut.contextChangeTrackers.forEach { $0.objectsDidChange(Set(arrayLiteral: msg)) }
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
    
        // then after processing it should set 'needsToUploadPreview' to true
        XCTAssertTrue(msg.isReadyToUploadFile)
        XCTAssertNotNil(self.syncMOC.zm_fileAssetCache.assetData(msg.nonce, fileName: "foo", encrypted:true))
    }
    
    func testThatItPreprocessesAFileMessageAndGeneratesTheThumbnail() {
        
        // given
        guard let url = Bundle(for: type(of: self)).url(forResource: "video", withExtension:"mp4") else { return XCTFail() }
        let message = createMessage(name!, thumbnail: mediumJPEGData(), url: url)
        
        // when
        sut.contextChangeTrackers.forEach { $0.objectsDidChange(Set(arrayLiteral: message)) }
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
    
        // then
        XCTAssertEqual(message.genericAssetMessage?.asset.hasPreview(), true)
        guard let preview = message.genericAssetMessage?.asset.preview else { return XCTFail("Unable to get the preview") }
        
        let encrypted = syncMOC.zm_imageAssetCache.assetData(message.nonce, format: .medium, encrypted: true)
        let decrypted = syncMOC.zm_imageAssetCache.assetData(message.nonce, format: .medium, encrypted: false)
        
        XCTAssertNotNil(decrypted)
        XCTAssertNotNil(encrypted)
        
        let (otrKey, sha256) = (preview.remote.otrKey, preview.remote.sha256)
        
        XCTAssertEqual(encrypted?.zmSHA256Digest(), sha256)
        XCTAssertEqual(decrypted, encrypted?.zmDecryptPrefixedPlainTextIV(key: otrKey!))
        
        XCTAssertNil(syncMOC.zm_imageAssetCache.assetData(message.nonce, format: .preview, encrypted: false))
        XCTAssertNil(syncMOC.zm_imageAssetCache.assetData(message.nonce, format: .preview, encrypted: true))
        XCTAssertNil(syncMOC.zm_imageAssetCache.assetData(message.nonce, format: .original, encrypted: false))
        
        XCTAssertTrue(preview.hasImage())
        XCTAssertTrue(preview.image.width > 0)
    }
    
    func testThatItDoesNotPreprocessAFileMessageAndGeneratesThePreviewIfTheMessageIsNotAVideo() {
        // given
        let message = createMessage(name!)
        
        // when
        sut.contextChangeTrackers.forEach { $0.objectsDidChange(Set(arrayLiteral: message)) }
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertEqual(message.genericAssetMessage?.asset.hasPreview(), false)
        XCTAssertNil(syncMOC.zm_imageAssetCache.assetData(message.nonce, format: .medium, encrypted: true))
        XCTAssertNil(syncMOC.zm_imageAssetCache.assetData(message.nonce, format: .medium, encrypted: false))
        XCTAssertNil(syncMOC.zm_imageAssetCache.assetData(message.nonce, format: .preview, encrypted: false))
        XCTAssertNil(syncMOC.zm_imageAssetCache.assetData(message.nonce, format: .preview, encrypted: true))
        XCTAssertNil(syncMOC.zm_imageAssetCache.assetData(message.nonce, format: .original, encrypted: false))
    }
    
    func testThatItDoesNotGeneratePreviewsForImageMessages() {
        // given
        let (_, conversation) = createOtherClientAndConversation()
        let messageNonce = UUID.create()
        let message = conversation.appendOTRMessage(withImageData: mediumJPEGData(), nonce: messageNonce)
        
        // when
        sut.contextChangeTrackers.forEach { $0.objectsDidChange(Set(arrayLiteral: message)) }
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertNil(message.genericAssetMessage)
        XCTAssertNil(syncMOC.zm_imageAssetCache.assetData(message.nonce, format: .medium, encrypted: true))
        XCTAssertNil(syncMOC.zm_imageAssetCache.assetData(message.nonce, format: .medium, encrypted: false))
        XCTAssertNil(syncMOC.zm_imageAssetCache.assetData(message.nonce, format: .preview, encrypted: false))
        XCTAssertNil(syncMOC.zm_imageAssetCache.assetData(message.nonce, format: .preview, encrypted: true))
        
        XCTAssertNotNil(syncMOC.zm_imageAssetCache.assetData(message.nonce, format: .original, encrypted: false))
    }
}
