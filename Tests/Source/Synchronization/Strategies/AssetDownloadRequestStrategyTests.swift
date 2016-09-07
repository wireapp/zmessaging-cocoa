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

private let testDataURL = NSBundle(forClass: FilePreprocessorTests.self).URLForResource("Lorem Ipsum", withExtension: "txt")!

class MockTaskCancellationProvider: NSObject, ZMRequestCancellation {
    
    var cancelledIdentifiers = [ZMTaskIdentifier]()
    
    func cancelTaskWithIdentifier(identifier: ZMTaskIdentifier) {
        cancelledIdentifiers.append(identifier)
    }
}


@objc class AssetDownloadRequestStrategyTests: MessagingTest {
    
    var authStatus: MockAuthenticationStatus!
    var cancellationProvider: MockTaskCancellationProvider!
    var sut: AssetDownloadRequestStrategy!
    var conversation: ZMConversation!
    
    override func setUp() {
        super.setUp()
        authStatus = MockAuthenticationStatus()
        cancellationProvider = MockTaskCancellationProvider()
        sut = AssetDownloadRequestStrategy(
            authStatus: authStatus,
            taskCancellationProvider: cancellationProvider,
            managedObjectContext: syncMOC
        )
        conversation = createConversation()
    }
    
    private func createConversation() -> ZMConversation {
        let conversation = ZMConversation.insertNewObjectInManagedObjectContext(syncMOC)
        conversation.remoteIdentifier = .createUUID()
        return conversation
    }
    
    private func createFileTransferMessage(conversation: ZMConversation) -> ZMAssetClientMessage {
        let message = conversation.appendMessageWithFileMetadata(ZMFileMetadata(fileURL: testDataURL)) as! ZMAssetClientMessage
        message.assetId = NSUUID.createUUID()
        message.fileMessageData?.transferState = .Downloading
        
        self.syncMOC.saveOrRollback()
        
        self.sut.contextChangeTrackers.forEach { tracker in
            tracker.objectsDidChange(Set(arrayLiteral: message))
        }
        
        XCTAssertTrue(self.waitForAllGroupsToBeEmptyWithTimeout(0.5))
        
        return message
    }
}

// request generation tests
extension AssetDownloadRequestStrategyTests {
    func testThatItGeneratesNoRequestsIfTheStatusIsEmpty() {
        XCTAssertNil(self.sut.nextRequest())
    }
    
    func testThatItGeneratesNoRequestsIfNotAuthenticated() {
        // given
        self.authStatus.mockPhase = .Unauthenticated
        let _ = self.createFileTransferMessage(self.conversation)
        
        // when
        let request : ZMTransportRequest? = self.sut.nextRequest()
        
        // then
        XCTAssertNil(request)
    }
    
    
    func testThatItGeneratesNoRequestsIfMessageDoesNotHaveAnAssetId() {
        // given
        let message = conversation.appendMessageWithFileMetadata(ZMFileMetadata(fileURL: testDataURL)) as! ZMAssetClientMessage
        message.assetId = .None
        message.fileMessageData?.transferState = .Downloading
        
        self.syncMOC.saveOrRollback()
        
        self.sut.contextChangeTrackers.forEach { tracker in
            tracker.objectsDidChange(Set(arrayLiteral: message))
        }
        
        XCTAssertTrue(self.waitForAllGroupsToBeEmptyWithTimeout(0.5))
        
        // when
        let request : ZMTransportRequest? = self.sut.nextRequest()
        
        // then
        XCTAssertNil(request)
    }
    
    func testThatItGeneratesNoRequestsIfMessageIsUploading() {
        // given
        let message = conversation.appendMessageWithFileMetadata(ZMFileMetadata(fileURL: testDataURL)) as! ZMAssetClientMessage
        message.assetId = NSUUID.createUUID()
        message.fileMessageData?.transferState = .Uploaded
        
        self.syncMOC.saveOrRollback()
        
        self.sut.contextChangeTrackers.forEach { tracker in
            tracker.objectsDidChange(Set(arrayLiteral: message))
        }
        
        XCTAssertTrue(self.waitForAllGroupsToBeEmptyWithTimeout(0.5))
        
        // when
        let request : ZMTransportRequest? = self.sut.nextRequest()
        
        // then
        XCTAssertNil(request)
    }
    
    func testThatItGeneratesARequest() {
        
        // given
        let message = self.createFileTransferMessage(self.conversation)

        // when
        let request : ZMTransportRequest? = self.sut.nextRequest()
        
        // then
        if let request = request {
            XCTAssertEqual(request.method, ZMTransportRequestMethod.MethodGET)
            XCTAssertEqual(request.path, "/conversations/\(self.conversation.remoteIdentifier.transportString())/otr/assets/\((message.assetId?.transportString())!)")
            XCTAssertTrue(request.needsAuthentication)
        } else {
            XCTFail("Empty request")
        }
    }
    
    func testThatItGeneratesARequestOnlyOnce() {
        
        // given
        let _ = self.createFileTransferMessage(self.conversation)

        // when
        let request1 : ZMTransportRequest? = self.sut.nextRequest()
        let request2 : ZMTransportRequest? = self.sut.nextRequest()
        
        // then
        XCTAssertNotNil(request1)
        XCTAssertNil(request2)
        
    }
}

// tests on result of request
extension AssetDownloadRequestStrategyTests {
    func testThatItMarksDownloadAsSuccessIfSuccessfulDownloadAndDecryption() {
        
        // given
        let plainTextData = NSData.secureRandomDataOfLength(500)
        let key = NSData.randomEncryptionKey()
        let encryptedData = plainTextData.zmEncryptPrefixingPlainTextIVWithKey(key)
        let sha = encryptedData.zmSHA256Digest()
        
        
        let message = self.createFileTransferMessage(self.conversation)
        
        let dataBuilder = ZMAssetRemoteDataBuilder()
        dataBuilder.setSha256(sha)
        dataBuilder.setOtrKey(key)
        
        let assetBuilder = ZMAssetBuilder()
        assetBuilder.setUploaded(dataBuilder.build())
        
        let genericAssetMessageBuilder = ZMGenericMessageBuilder()
        genericAssetMessageBuilder.mergeFrom(message.genericAssetMessage)
        genericAssetMessageBuilder.setAsset(assetBuilder.build())
        
        message.addGenericMessage(genericAssetMessageBuilder.build())
        
        let request : ZMTransportRequest? = self.sut.nextRequest()
        let response = ZMTransportResponse(imageData: encryptedData, HTTPstatus: 200, transportSessionError: .None, headers: [:])
        
        // when
        request?.completeWithResponse(response)
        XCTAssertTrue(self.waitForAllGroupsToBeEmptyWithTimeout(0.5))

        // then
        XCTAssertEqual(message.fileMessageData?.transferState.rawValue, ZMFileTransferState.Downloaded.rawValue)
    }
    
    func testThatItMarksDownloadAsFailedIfCannotDownload_PermanentError() {
        // given
        let message = self.createFileTransferMessage(self.conversation)
        let request : ZMTransportRequest? = self.sut.nextRequest()
        let response = ZMTransportResponse(payload: [], HTTPstatus: 404, transportSessionError: .None)
        
        // when
        request?.completeWithResponse(response)
        XCTAssertTrue(self.waitForAllGroupsToBeEmptyWithTimeout(0.5))
        
        // then
        XCTAssertEqual(message.fileMessageData?.transferState.rawValue, ZMFileTransferState.FailedDownload.rawValue)
    }
    
    func testThatItMarksDownloadAsFailedIfCannotDownload_TemporaryError() {
        // given
        let message = self.createFileTransferMessage(self.conversation)
        let request : ZMTransportRequest? = self.sut.nextRequest()
        let response = ZMTransportResponse(payload: [], HTTPstatus: 500, transportSessionError: .None)
        
        // when
        request?.completeWithResponse(response)
        XCTAssertTrue(self.waitForAllGroupsToBeEmptyWithTimeout(0.5))
        
        // then
        XCTAssertEqual(message.fileMessageData?.transferState.rawValue, ZMFileTransferState.FailedDownload.rawValue)
    }
    
    func testThatItMarksDownloadAsFailedIfCannotDownload_CannotDecrypt() {
        // given
        let message = self.createFileTransferMessage(self.conversation)
        let request : ZMTransportRequest? = self.sut.nextRequest()
        let response = ZMTransportResponse(payload: [], HTTPstatus: 200, transportSessionError: .None)
        
        // when
        request?.completeWithResponse(response)
        XCTAssertTrue(self.waitForAllGroupsToBeEmptyWithTimeout(0.5))
        
        // then
        XCTAssertEqual(message.fileMessageData?.transferState.rawValue, ZMFileTransferState.FailedDownload.rawValue)
    }
    
    func testThatItDoesNotMarkDownloadAsFailedWhenNotDownloading() {
        // given
        let message = self.createFileTransferMessage(self.conversation)
        let request : ZMTransportRequest? = self.sut.nextRequest()
        let response = ZMTransportResponse(payload: [], HTTPstatus: 500, transportSessionError: .None)
        
        // when
        message.transferState = .Uploaded
        request?.completeWithResponse(response)
        XCTAssertTrue(self.waitForAllGroupsToBeEmptyWithTimeout(0.5))
        
        // then
        XCTAssertEqual(message.fileMessageData?.transferState.rawValue, ZMFileTransferState.Uploaded.rawValue)
    }
    
    func testThatItUpdatesFileDownloadProgress() {
        // given
        let expectedProgress: Float = 0.5
        let message = self.createFileTransferMessage(self.conversation)
        let request : ZMTransportRequest? = self.sut.nextRequest()
        
        XCTAssertEqual(message.fileMessageData?.progress, 0)

        // when
        request?.updateProgress(expectedProgress)
        XCTAssertTrue(self.waitForAllGroupsToBeEmptyWithTimeout(0.5))
        
        // then
        XCTAssertEqual(message.fileMessageData?.progress, expectedProgress)
    }
    
    func testThatItSendsTheNotificationIfSuccessfulDownloadAndDecryption() {
        
        // given
        let plainTextData = NSData.secureRandomDataOfLength(500)
        let key = NSData.randomEncryptionKey()
        let encryptedData = plainTextData.zmEncryptPrefixingPlainTextIVWithKey(key)
        let sha = encryptedData.zmSHA256Digest()
        
        
        let message = self.createFileTransferMessage(self.conversation)
        
        let dataBuilder = ZMAssetRemoteDataBuilder()
        dataBuilder.setSha256(sha)
        dataBuilder.setOtrKey(key)
        
        let assetBuilder = ZMAssetBuilder()
        assetBuilder.setUploaded(dataBuilder.build())
        
        let genericAssetMessageBuilder = ZMGenericMessageBuilder()
        genericAssetMessageBuilder.mergeFrom(message.genericAssetMessage)
        genericAssetMessageBuilder.setAsset(assetBuilder.build())
        
        message.addGenericMessage(genericAssetMessageBuilder.build())
        
        let notificationExpectation = self.expectationWithDescription("Notification fired")
        
        let _ = NSNotificationCenter.defaultCenter().addObserverForName(AssetDownloadRequestStrategyNotification.downloadFinishedNotificationName, object: nil, queue: .mainQueue()) { notification in
            XCTAssertNotNil(notification.userInfo![AssetDownloadRequestStrategyNotification.downloadStartTimestampKey])
            notificationExpectation.fulfill()
        }
        
        let request : ZMTransportRequest? = self.sut.nextRequest()
        request?.markStartOfUploadTimestamp()
        let response = ZMTransportResponse(imageData: encryptedData, HTTPstatus: 200, transportSessionError: .None, headers: [:])
        
        // when
        request?.completeWithResponse(response)
        XCTAssertTrue(self.waitForAllGroupsToBeEmptyWithTimeout(0.5))
        
        // then
        XCTAssertTrue(self.waitForCustomExpectationsWithTimeout(0.5))

    }
    
    func testThatItSendsTheNotificationIfCannotDownload() {
        // given
        
        let notificationExpectation = self.expectationWithDescription("Notification fired")
        
        let _ = NSNotificationCenter.defaultCenter().addObserverForName(AssetDownloadRequestStrategyNotification.downloadFailedNotificationName, object: nil, queue: .mainQueue()) { notification in
            XCTAssertNotNil(notification.userInfo![AssetDownloadRequestStrategyNotification.downloadStartTimestampKey])
            notificationExpectation.fulfill()
        }
        
        let _ = self.createFileTransferMessage(self.conversation)
        let request : ZMTransportRequest? = self.sut.nextRequest()
        request?.markStartOfUploadTimestamp()
        let response = ZMTransportResponse(payload: [], HTTPstatus: 404, transportSessionError: .None)
        
        // when
        request?.completeWithResponse(response)
        XCTAssertTrue(self.waitForAllGroupsToBeEmptyWithTimeout(0.5))
        
        // then
        XCTAssertTrue(self.waitForCustomExpectationsWithTimeout(0.5))
    }
}

// MARK : - Download Cancellation

extension AssetDownloadRequestStrategyTests {
    
    func testThatItInformsTheTaskCancellationProviderToCancelARequestForAnAssetMessageWhenItReceivesTheNotification() {
        // given
        let message = createFileTransferMessage(conversation)
        XCTAssertNotNil(message.objectID)
        
        // given the task has been created
        guard let request = sut.nextRequest() else { return XCTFail("No request created") }
        
        request.callTaskCreationHandlersWithIdentifier(42, sessionIdentifier: name)
        XCTAssertTrue(syncMOC.saveOrRollback())
        XCTAssertTrue(waitForAllGroupsToBeEmptyWithTimeout(0.5))
        let identifier = message.associatedTaskIdentifier
        XCTAssertNotNil(identifier)
        
        // when the transfer is cancelled
        message.fileMessageData?.cancelTransfer()
        XCTAssertTrue(waitForAllGroupsToBeEmptyWithTimeout(0.5))
        
        // then the cancellation provider should be informed to cancel the request
        XCTAssertEqual(cancellationProvider.cancelledIdentifiers.count, 1)
        let cancelledIdentifier = cancellationProvider.cancelledIdentifiers.first
        XCTAssertEqual(cancelledIdentifier, identifier)
        
        // It should nil-out the identifier as it has been cancelled
        XCTAssertNil(message.associatedTaskIdentifier)
    }
    
}
