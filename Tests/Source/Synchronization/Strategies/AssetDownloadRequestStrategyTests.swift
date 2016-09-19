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

private let testDataURL = Bundle(for: FilePreprocessorTests.self).url(forResource: "Lorem Ipsum", withExtension: "txt")!

class MockTaskCancellationProvider: NSObject, ZMRequestCancellation {
    
    var cancelledIdentifiers = [ZMTaskIdentifier]()
    
    func cancelTask(with identifier: ZMTaskIdentifier) {
        cancelledIdentifiers.append(identifier)
    }
}


class AssetDownloadRequestStrategyTests: MessagingTest {
    
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
    
    fileprivate func createConversation() -> ZMConversation {
        let conversation = ZMConversation.insertNewObject(in: syncMOC)
        conversation.remoteIdentifier = UUID.create()
        return conversation
    }
    
    fileprivate func createFileTransferMessage(_ conversation: ZMConversation) -> ZMAssetClientMessage {
        let message = conversation.appendMessage(with: ZMFileMetadata(fileURL: testDataURL)) as! ZMAssetClientMessage
        message.assetId = UUID.create()
        message.fileMessageData?.transferState = .downloading
        
        self.syncMOC.saveOrRollback()
        
        self.sut.contextChangeTrackers.forEach { tracker in
            tracker.objectsDidChange(Set(arrayLiteral: message))
        }
        
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
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
        self.authStatus.mockPhase = .unauthenticated
        let _ = self.createFileTransferMessage(self.conversation)
        
        // when
        let request : ZMTransportRequest? = self.sut.nextRequest()
        
        // then
        XCTAssertNil(request)
    }
    
    
    func testThatItGeneratesNoRequestsIfMessageDoesNotHaveAnAssetId() {
        // given
        let message = conversation.appendMessage(with: ZMFileMetadata(fileURL: testDataURL)) as! ZMAssetClientMessage
        message.assetId = .none
        message.fileMessageData?.transferState = .downloading
        
        self.syncMOC.saveOrRollback()
        
        self.sut.contextChangeTrackers.forEach { tracker in
            tracker.objectsDidChange(Set(arrayLiteral: message))
        }
        
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // when
        let request : ZMTransportRequest? = self.sut.nextRequest()
        
        // then
        XCTAssertNil(request)
    }
    
    func testThatItGeneratesNoRequestsIfMessageIsUploading() {
        // given
        let message = conversation.appendMessage(with: ZMFileMetadata(fileURL: testDataURL)) as! ZMAssetClientMessage
        message.assetId = UUID.create()
        message.fileMessageData?.transferState = .uploaded
        
        self.syncMOC.saveOrRollback()
        
        self.sut.contextChangeTrackers.forEach { tracker in
            tracker.objectsDidChange(Set(arrayLiteral: message))
        }
        
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
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
            XCTAssertEqual(request.method, ZMTransportRequestMethod.methodGET)
            XCTAssertEqual(request.path, "/conversations/\(self.conversation.remoteIdentifier?.transportString())/otr/assets/\((message.assetId?.transportString())!)")
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
        let plainTextData = Data.secureRandomData(ofLength: 500)
        let key = Data.randomEncryptionKey()
        let encryptedData = plainTextData.zmEncryptPrefixingPlainTextIV(key: key)
        let sha = encryptedData.zmSHA256Digest()
        
        
        let message = self.createFileTransferMessage(self.conversation)
        
        let dataBuilder = ZMAssetRemoteDataBuilder()
        dataBuilder.setSha256(sha)
        dataBuilder.setOtrKey(key)
        
        let assetBuilder = ZMAssetBuilder()
        assetBuilder.setUploaded(dataBuilder.build())
        
        let genericAssetMessageBuilder = ZMGenericMessageBuilder()
        genericAssetMessageBuilder.merge(from: message.genericAssetMessage)
        genericAssetMessageBuilder.setAsset(assetBuilder.build())
        
        message.add(genericAssetMessageBuilder.build())
        
        let request : ZMTransportRequest? = self.sut.nextRequest()
        let response = ZMTransportResponse(imageData: encryptedData, httpStatus: 200, transportSessionError: .none, headers: [:])
        
        // when
        request?.complete(with: response)
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.5))

        // then
        XCTAssertEqual(message.fileMessageData?.transferState.rawValue, ZMFileTransferState.downloaded.rawValue)
    }
    
    func testThatItMarksDownloadAsFailedIfCannotDownload_PermanentError() {
        // given
        let message = self.createFileTransferMessage(self.conversation)
        let request : ZMTransportRequest? = self.sut.nextRequest()
        let response = ZMTransportResponse(payload: [] as ZMTransportData, httpStatus: 404, transportSessionError: .none)
        
        // when
        request?.complete(with: response)
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertEqual(message.fileMessageData?.transferState.rawValue, ZMFileTransferState.failedDownload.rawValue)
    }
    
    func testThatItMarksDownloadAsFailedIfCannotDownload_TemporaryError() {
        // given
        let message = self.createFileTransferMessage(self.conversation)
        let request : ZMTransportRequest? = self.sut.nextRequest()
        let response = ZMTransportResponse(payload: [] as ZMTransportData, httpStatus: 500, transportSessionError: .none)
        
        // when
        request?.complete(with: response)
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertEqual(message.fileMessageData?.transferState.rawValue, ZMFileTransferState.failedDownload.rawValue)
    }
    
    func testThatItMarksDownloadAsFailedIfCannotDownload_CannotDecrypt() {
        // given
        let message = self.createFileTransferMessage(self.conversation)
        let request : ZMTransportRequest? = self.sut.nextRequest()
        let response = ZMTransportResponse(payload: [] as ZMTransportData, httpStatus: 200, transportSessionError: .none)
        
        // when
        request?.complete(with: response)
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertEqual(message.fileMessageData?.transferState.rawValue, ZMFileTransferState.failedDownload.rawValue)
    }
    
    func testThatItDoesNotMarkDownloadAsFailedWhenNotDownloading() {
        // given
        let message = self.createFileTransferMessage(self.conversation)
        let request : ZMTransportRequest? = self.sut.nextRequest()
        let response = ZMTransportResponse(payload: [] as ZMTransportData, httpStatus: 500, transportSessionError: .none)
        
        // when
        message.transferState = .uploaded
        request?.complete(with: response)
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertEqual(message.fileMessageData?.transferState.rawValue, ZMFileTransferState.uploaded.rawValue)
    }
    
    func testThatItUpdatesFileDownloadProgress() {
        // given
        let expectedProgress: Float = 0.5
        let message = self.createFileTransferMessage(self.conversation)
        let request : ZMTransportRequest? = self.sut.nextRequest()
        
        XCTAssertEqual(message.fileMessageData?.progress, 0)

        // when
        request?.updateProgress(expectedProgress)
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertEqual(message.fileMessageData?.progress, expectedProgress)
    }
    
    func testThatItSendsTheNotificationIfSuccessfulDownloadAndDecryption() {
        
        // given
        let plainTextData = Data.secureRandomData(ofLength: 500)
        let key = Data.randomEncryptionKey()
        let encryptedData = plainTextData.zmEncryptPrefixingPlainTextIV(key: key)
        let sha = encryptedData.zmSHA256Digest()
        
        
        let message = self.createFileTransferMessage(self.conversation)
        
        let dataBuilder = ZMAssetRemoteDataBuilder()
        dataBuilder.setSha256(sha)
        dataBuilder.setOtrKey(key)
        
        let assetBuilder = ZMAssetBuilder()
        assetBuilder.setUploaded(dataBuilder.build())
        
        let genericAssetMessageBuilder = ZMGenericMessageBuilder()
        genericAssetMessageBuilder.merge(from: message.genericAssetMessage)
        genericAssetMessageBuilder.setAsset(assetBuilder.build())
        
        message.add(genericAssetMessageBuilder.build())
        
        let notificationExpectation = self.expectation(description: "Notification fired")
        
        let _ = NotificationCenter.default.addObserver(forName: NSNotification.Name(rawValue: AssetDownloadRequestStrategyNotification.downloadFinishedNotificationName), object: nil, queue: .main) { notification in
            XCTAssertNotNil(notification.userInfo![AssetDownloadRequestStrategyNotification.downloadStartTimestampKey])
            notificationExpectation.fulfill()
        }
        
        let request : ZMTransportRequest? = self.sut.nextRequest()
        request?.markStartOfUploadTimestamp()
        let response = ZMTransportResponse(imageData: encryptedData, httpStatus: 200, transportSessionError: .none, headers: [:])
        
        // when
        request?.complete(with: response)
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertTrue(self.waitForCustomExpectations(withTimeout: 0.5))

    }
    
    func testThatItSendsTheNotificationIfCannotDownload() {
        // given
        
        let notificationExpectation = self.expectation(description: "Notification fired")
        
        let _ = NotificationCenter.default.addObserver(forName: NSNotification.Name(rawValue: AssetDownloadRequestStrategyNotification.downloadFailedNotificationName), object: nil, queue: .main) { notification in
            XCTAssertNotNil(notification.userInfo![AssetDownloadRequestStrategyNotification.downloadStartTimestampKey])
            notificationExpectation.fulfill()
        }
        
        let _ = self.createFileTransferMessage(self.conversation)
        let request : ZMTransportRequest? = self.sut.nextRequest()
        request?.markStartOfUploadTimestamp()
        let response = ZMTransportResponse(payload: [] as ZMTransportData, httpStatus: 404, transportSessionError: .none)
        
        // when
        request?.complete(with: response)
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertTrue(self.waitForCustomExpectations(withTimeout: 0.5))
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
        
        request.callTaskCreationHandlers(withIdentifier: 42, sessionIdentifier: name!)
        XCTAssertTrue(syncMOC.saveOrRollback())
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        let identifier = message.associatedTaskIdentifier
        XCTAssertNotNil(identifier)
        
        // when the transfer is cancelled
        message.fileMessageData?.cancelTransfer()
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then the cancellation provider should be informed to cancel the request
        XCTAssertEqual(cancellationProvider.cancelledIdentifiers.count, 1)
        let cancelledIdentifier = cancellationProvider.cancelledIdentifiers.first
        XCTAssertEqual(cancelledIdentifier, identifier)
        
        // It should nil-out the identifier as it has been cancelled
        XCTAssertNil(message.associatedTaskIdentifier)
    }
    
}
