//
// Wire
// Copyright (C) 2017 Wire Swiss GmbH
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
import XCTest
@testable import zmessaging

class MockImageUpdateStatus: UserProfileImageUploadStatusProtocol {
    var allSizes: [ProfileImageSize] { return [.preview, .complete] }
    
    var dataToConsume = [ProfileImageSize : Data]()
    func consumeImage(for size: ProfileImageSize) -> Data? {
        return dataToConsume[size]
    }
    func hasImageToUpload(for size: ProfileImageSize) -> Bool {
        return dataToConsume[size] != nil
    }
    
    var uploadDoneForSize: ProfileImageSize?
    var uploadDoneWithAssetId: String?
    func uploadingDone(imageSize: ProfileImageSize, assetId: String) {
        uploadDoneForSize = imageSize
        uploadDoneWithAssetId = assetId
    }
    
    var uploadFailedForSize: ProfileImageSize?
    var uploadFailedWithError: Error?
    func uploadingFailed(imageSize: ProfileImageSize, error: Error) {
        uploadFailedForSize = imageSize
        uploadFailedWithError = error
    }
}

class UserImageAssetUploadStrategyTests : MessagingTest {
    
    var sut: UserImageAssetUploadStrategy!
    var authenticationStatus: MockAuthenticationStatus!
    var updateStatus: MockImageUpdateStatus!
    
    override func setUp() {
        super.setUp()
        self.authenticationStatus = MockAuthenticationStatus(phase: .authenticated)
        self.updateStatus = MockImageUpdateStatus()
        self.sut = UserImageAssetUploadStrategy(managedObjectContext: syncMOC,
                                                imageUpdateStatus: updateStatus,
                                                authenticationStatus: authenticationStatus)
    }
    
    func testThatItDoesNotReturnARequestWhenThereIsNoImageToUpload() {
        // WHEN
        updateStatus.dataToConsume.removeAll()
        
        // THEN
        XCTAssertNil(sut.nextRequest())
    }
    
    func testThatItDoesNotReturnARequestWhenUserIsNotLoggedIn() {
        // WHEN
        updateStatus.dataToConsume[.preview] = Data()
        updateStatus.dataToConsume[.complete] = Data()
        authenticationStatus.mockPhase = .unauthenticated
        
        // THEN
        XCTAssertNil(sut.nextRequest())
    }
    
    func testThatItDoesNotCreateRequestSyncsInitially() {
        XCTAssertTrue(sut.requestSyncs.isEmpty)
    }
    
    func testThatItCreatesRequestSyncForTheSizeWhenAsked() {
        // WHEN
        _ = sut.requestSync(for: .preview)
        
        // THEN
        XCTAssertNotNil(sut.requestSyncs[.preview])
        XCTAssertNil(sut.requestSyncs[.complete])
        
        // WHEN
        _ = sut.requestSync(for: .complete)
        
        // THEN
        XCTAssertNotNil(sut.requestSyncs[.preview])
        XCTAssertNotNil(sut.requestSyncs[.complete])
    }

    func testThatItReturnsCorrectSizeFromRequestSync() {
        // WHEN
        let previewSync = sut.requestSync(for: .preview)
        let completeSync = sut.requestSync(for: .complete)
        
        // THEN
        XCTAssertEqual(sut.size(for: previewSync), .preview)
        XCTAssertEqual(sut.size(for: completeSync), .complete)
    }
    
    func testThatItCreatesRequestWhenThereIsData() {
        // WHEN
        updateStatus.dataToConsume.removeAll()
        updateStatus.dataToConsume[.preview] = "Some".data(using: .utf8)
        
        // THEN
        XCTAssertNotNil(sut.nextRequest())
        
        // WHEN
        updateStatus.dataToConsume.removeAll()
        updateStatus.dataToConsume[.complete] = "Other".data(using: .utf8)
        
        // THEN
        XCTAssertNotNil(sut.nextRequest())
    }
    
    func testThatItCreatesRequestWithExpectedData() {
        // GIVEN
        let previewData = "--1--".data(using: .utf8)
        let previewRequest = sut.requestFactory.upstreamRequestForAsset(withData: previewData!, shareable: true, retention: .eternal)
        let completeData = "1111111".data(using: .utf8)
        let completeRequest = sut.requestFactory.upstreamRequestForAsset(withData: completeData!, shareable: true, retention: .eternal)
        
        // WHEN
        updateStatus.dataToConsume.removeAll()
        updateStatus.dataToConsume[.preview] = previewData

        // THEN
        XCTAssertEqual(sut.nextRequest()?.binaryData, previewRequest?.binaryData)
        
        // WHEN
        updateStatus.dataToConsume.removeAll()
        updateStatus.dataToConsume[.complete] = completeData
        
        // THEN
        XCTAssertEqual(sut.nextRequest()?.binaryData, completeRequest?.binaryData)
    }
    
    func testThatUploadMarkedAsFailedOnUnsuccessfulResponse() {
        // GIVEN
        let size = ProfileImageSize.preview
        let sync = sut.requestSync(for: size)
        let failedResponse = ZMTransportResponse(payload: nil, httpStatus: 500, transportSessionError: nil)
        
        // WHEN
        sut.didReceive(failedResponse, forSingleRequest: sync)
        
        // THEN
        XCTAssertEqual(updateStatus.uploadFailedForSize, size)
    }
    
    func testThatUploadIsMarkedAsDoneAfterSuccessfulResponse() {
        // GIVEN
        let size = ProfileImageSize.preview
        let sync = sut.requestSync(for: size)
        let assetId = "123123"
        let payload: [String : String] = ["key" : assetId]
        let successResponse = ZMTransportResponse(payload: payload as NSDictionary, httpStatus: 200, transportSessionError: nil)
        
        // WHEN
        sut.didReceive(successResponse, forSingleRequest: sync)

        // THEN
        XCTAssertEqual(updateStatus.uploadDoneForSize, size)
        XCTAssertEqual(updateStatus.uploadDoneWithAssetId, assetId)

    }
    
}
