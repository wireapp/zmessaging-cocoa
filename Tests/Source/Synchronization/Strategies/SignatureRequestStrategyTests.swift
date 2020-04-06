//
// Wire
// Copyright (C) 2020 Wire Swiss GmbH
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

class SignatureRequestStrategyTests: MessagingTest {
     var sut: SignatureRequestStrategy!
     var mockApplicationStatus: MockApplicationStatus!
     var signatureStatus: SignatureStatus?
     var asset: ZMAsset?
    
    override func setUp() {
        super.setUp()
        mockApplicationStatus = MockApplicationStatus()
        asset = randomAsset()
        signatureStatus = SignatureStatus(asset: asset, managedObjectContext: syncMOC)
        sut = SignatureRequestStrategy(withManagedObjectContext: syncMOC, applicationStatus: mockApplicationStatus)
    }
    
    override func tearDown() {
        sut = nil
        mockApplicationStatus = nil
        asset = nil
        signatureStatus = nil
        signatureStatusPublic = nil
        super.tearDown()
    }
    
    func testThatItGeneratesCorrectRequestIfStateIsWaitingForConsentURL() {
        //given
        signatureStatus?.state = .waitingForConsentURL

        //when
        signatureStatusPublic = signatureStatus
        let request = sut.nextRequestIfAllowed()
        
        //then
        XCTAssertNotNil(request)
        let payload = request?.payload?.asDictionary()
        XCTAssertEqual(payload?["documentId"] as? String, signatureStatus?.documentID)
        XCTAssertEqual(payload?["name"] as? String, signatureStatus?.fileName)
        XCTAssertEqual(payload?["hash"] as? String, signatureStatus?.encodedHash)
        XCTAssertEqual(request?.path, "/signature/request")
        XCTAssertEqual(request?.method, ZMTransportRequestMethod.methodPOST)
    }
    
    func testThatItGeneratesCorrectRequestIfStateIsWaitingForSignature() {
        //given
        signatureStatus?.state = .waitingForSignature
        let responseId = "123123"
        let payload: [String : String] = ["consentURL": "http://test.com",
                                          "responseId" : responseId]
        let successResponse = ZMTransportResponse(payload: payload as NSDictionary, httpStatus: 200, transportSessionError: nil)
        
        //when
        sut.didReceive(successResponse, forSingleRequest: sut.requestSync!)
        signatureStatusPublic = signatureStatus
        let request = sut.nextRequestIfAllowed()
        
        //then
        XCTAssertNotNil(request)
        XCTAssertEqual(request?.path, "/signature/pending/\(responseId)")
        XCTAssertEqual(request?.method, ZMTransportRequestMethod.methodGET)
    }
    
    func testThatItNotifiesSignatureStatusAfterSuccessfulResponseToReceiveConsentURL() {
        //given
        let responseId = "123123"
        let payload: [String : String] = ["consentURL": "http://test.com",
                                          "responseId" : responseId]
        let successResponse = ZMTransportResponse(payload: payload as NSDictionary, httpStatus: 200, transportSessionError: nil)

        //when
        signatureStatusPublic = signatureStatus
        let _ = sut.nextRequestIfAllowed()
        sut.didReceive(successResponse, forSingleRequest: sut.requestSync!)

        //then
        XCTAssertEqual(signatureStatusPublic?.state, .waitingForCodeVerification)
    }
    
    func testThatItNotifiesSignatureStatusAfterSuccessfulResponseToReceiveSignature() {
        //given
        let documentId = "123123"
        let payload: [String : String] = ["documentId": documentId,
                                          "cms" : "Test"]
        let successResponse = ZMTransportResponse(payload: payload as NSDictionary, httpStatus: 200, transportSessionError: nil)
        
        //when
        signatureStatusPublic = signatureStatus
        let _ = sut.nextRequestIfAllowed()
        sut.didReceive(successResponse, forSingleRequest: sut.retrieveSync!)
        
        //then
        XCTAssertEqual(signatureStatusPublic?.state, .finished)
    }
    
    func testThatItNotifiesSignatureStatusAfterFailedResponseToReceiveConsentURL() {
        //given
        let successResponse = ZMTransportResponse(payload: nil, httpStatus: 400, transportSessionError: nil)
        
        //when
        signatureStatusPublic = signatureStatus
        let _ = sut.nextRequestIfAllowed()
        sut.didReceive(successResponse, forSingleRequest: sut.requestSync!)
        
        //then
        XCTAssertEqual(signatureStatusPublic?.state, .signatureInvalid)
    }

    
    func testThatItNotifiesSignatureStatusAfterFailedResponseToReceiveSignature() {
        //given
        let successResponse = ZMTransportResponse(payload: nil, httpStatus: 400, transportSessionError: nil)
        
        //when
        signatureStatusPublic = signatureStatus
        let _ = sut.nextRequestIfAllowed()
        sut.didReceive(successResponse, forSingleRequest: sut.retrieveSync!)
        
        //then
        XCTAssertEqual(signatureStatusPublic?.state, .signatureInvalid)
    }
    
    private func randomAsset() -> ZMAsset? {
        let imageMetaData = ZMAssetImageMetaData.imageMetaData(withWidth: 30, height: 40)
        let imageMetaDataBuilder = imageMetaData.toBuilder()!
        let original  = ZMAssetOriginal.original(withSize: 200, mimeType: "application/pdf", name: "PDF test", imageMetaData: imageMetaData)
        let remoteData = ZMAssetRemoteData.remoteData(withOTRKey: Data(), sha256: Data(), assetId: "id", assetToken: "token")
        let preview = ZMAssetPreview.preview(withSize: 200, mimeType: "application/pdf", remoteData: remoteData, imageMetadata: imageMetaDataBuilder.build())

        return ZMAsset.asset(withOriginal: original, preview: preview)
    }
}
