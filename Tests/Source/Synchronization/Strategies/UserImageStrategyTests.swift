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

@testable import WireSyncEngine
import WireDataModel

class MockRequestStrategy : ImageRequestSource {
    static var mockRequest : ZMTransportRequest?
    public static func request(for imageOwner: ZMImageOwner, format: ZMImageFormat, conversationID: UUID, correlationID: UUID, resultHandler completionHandler: ZMCompletionHandler?) -> ZMTransportRequest? {
        return mockRequest
    }
}

class UserImageStrategyTests : MessagingTest {

    var sut : UserImageStrategy!
    var queue : OperationQueue!
    var requestStrategy : MockRequestStrategy!
    var mockApplicationStatus : MockApplicationStatus!
    var user1 : ZMUser!
    var user1ID: UUID!
    
    override func setUp() {
        super.setUp()
        syncMOC.zm_userImageCache = UserImageLocalCache()
        uiMOC.zm_userImageCache = syncMOC.zm_userImageCache
        
        queue = OperationQueue()
        queue.name = name
        queue.maxConcurrentOperationCount = 1
        mockApplicationStatus = MockApplicationStatus()
        mockApplicationStatus.mockSynchronizationState = .eventProcessing

        requestStrategy = MockRequestStrategy()
        sut = UserImageStrategy(managedObjectContext: syncMOC, applicationStatus:mockApplicationStatus, imageProcessingQueue: queue, requestFactory: requestStrategy)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        self.user1ID = UUID()
        syncMOC.performGroupedBlockAndWait{
            self.user1 = ZMUser.insertNewObject(in:self.syncMOC)
            self.user1.remoteIdentifier = self.user1ID;
            
            XCTAssert(self.syncMOC.saveOrRollback())
        }

    }
    
    override func tearDown() {
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        mockApplicationStatus = nil
        self.sut.tearDown()
        self.sut = nil;
        self.user1 = nil;
        self.user1ID = nil;
        super.tearDown()
    }

}

// MARK: DownloadPredicate
extension UserImageStrategyTests {
    
    func matches(mediumRemoteIdentifier: UUID?, localMediumRemoteIdentifier: UUID?) -> Bool {
        var didMatch : Bool = false
        syncMOC.performGroupedBlockAndWait{
            // given
            let p = ZMUser.predicateForMediumImageNeedingToBeUpdatedFromBackend()
            
            // when
            self.user1.mediumRemoteIdentifier = mediumRemoteIdentifier
            self.user1.localMediumRemoteIdentifier = localMediumRemoteIdentifier
            
            // then
            didMatch = p.evaluate(with:self.user1)
        }
        return didMatch
    }
    
    func testThatItMatchesUserWithoutALocalImage() {
        XCTAssertTrue(matches(mediumRemoteIdentifier: UUID(), localMediumRemoteIdentifier: nil))
    }
    
    func testThatItMatchesUserWithALocalImageAndRemoteImage() {
        XCTAssertTrue(matches(mediumRemoteIdentifier: UUID(), localMediumRemoteIdentifier: UUID()))
    }
    
    func testThatItDoesNotMatchAUserWithNoLocalImageAndNoRemoteImage() {
        XCTAssertFalse(matches(mediumRemoteIdentifier: nil, localMediumRemoteIdentifier: nil))
    }
    
    func testThatItDoesNotMatchAUserWithALocalImageButNoRemoteImage(){
        XCTAssertFalse(matches(mediumRemoteIdentifier: nil, localMediumRemoteIdentifier: UUID()))
    }
}



extension UserImageStrategyTests {
    
    func testThatItDoesntFilterSelfUserWithALocalImageAndADifferentRemoteImage() {
        syncMOC.performGroupedBlockAndWait{
            // given
            let p = ZMUser.predicateForMediumImageDownloadFilter()
            
            // when
            let selfUser = ZMUser.selfUser(in:self.syncMOC)
            selfUser.remoteIdentifier = UUID()
            selfUser.mediumRemoteIdentifier = UUID()
            selfUser.localMediumRemoteIdentifier = UUID()
            
            // then
            XCTAssertTrue(p.evaluate(with:selfUser))
        }
    }
    
    func testThatItFiltersSelfUserWithALocalImageAndTheSameRemoteImage() {
        syncMOC.performGroupedBlockAndWait{
            // given
            let p = ZMUser.predicateForMediumImageDownloadFilter()
            
            // when
            let selfUser = ZMUser.selfUser(in:self.syncMOC)
            selfUser.remoteIdentifier = UUID()
            selfUser.mediumRemoteIdentifier = UUID()
            selfUser.localMediumRemoteIdentifier = selfUser.mediumRemoteIdentifier;
            
            // then
            XCTAssertFalse(p.evaluate(with:selfUser))
        }
    }
    
    func testThatItFiltersAUserWithALocalImageWhichExistsInTheCache() {
        syncMOC.performGroupedBlockAndWait{
            // given
            let p = ZMUser.predicateForMediumImageDownloadFilter()
            
            // when
            self.user1.mediumRemoteIdentifier = UUID()
            self.user1.imageMediumData = "data".data(using: .utf8)
            
            // then
            XCTAssertFalse(p.evaluate(with:self.user1))
        }
    }
    
    func testThatItDoesNotFiltersAUserWithoutALocalImageInTheCache() {
        syncMOC.performGroupedBlockAndWait{
            // given
            let p = ZMUser.predicateForMediumImageDownloadFilter()
            
            // when
            self.user1.mediumRemoteIdentifier = UUID()
            
            // then
            XCTAssertTrue(p.evaluate(with:self.user1))
        }
    }
    
}

// MARK: Requests
extension UserImageStrategyTests {
    
    func forwardChanges(for user: ZMUser) {
        sut.contextChangeTrackers.forEach{$0.objectsDidChange(Set(arrayLiteral: user))}
    }

    func testThatItGeneratesARequestWhenTheMediumSelfUserImageIsMissing() {
        syncMOC.performGroupedBlockAndWait{
            // given
            let imageID = UUID()
            let selfUserID = UUID()
            
            let selfUser = ZMUser.selfUser(in:self.syncMOC)
            selfUser.remoteIdentifier = selfUserID;
            selfUser.mediumRemoteIdentifier = imageID;
            selfUser.localMediumRemoteIdentifier = nil;
            selfUser.imageMediumData = nil;
            selfUser.localSmallProfileRemoteIdentifier = nil;
            selfUser.imageSmallProfileData = nil;
            
            // when
            self.forwardChanges(for:selfUser)
            let request = self.sut.nextRequest()
        
            // then
            guard let req = request else {return XCTFail()}
            let path = "/assets/\(imageID.transportString())?conv_id=\(selfUserID.transportString())"
            XCTAssertEqual(req.path, path)
        }
    }
    
    
    func testThatItGeneratesARequestWhenTheSmallSelfUserImageIsMissing() {
        syncMOC.performGroupedBlockAndWait{
            // given
            let imageID = UUID()
            let selfUserID = UUID()
            
            let selfUser = ZMUser.selfUser(in:self.syncMOC)
            selfUser.remoteIdentifier = selfUserID;
            selfUser.mediumRemoteIdentifier = nil;
            selfUser.localMediumRemoteIdentifier = nil;
            selfUser.imageMediumData = nil;
            selfUser.localSmallProfileRemoteIdentifier = nil;
            selfUser.imageSmallProfileData = nil;
            selfUser.smallProfileRemoteIdentifier = imageID;
        
            // when
            self.forwardChanges(for:selfUser)
            let request = self.sut.nextRequest()
        
            // then
            guard let req = request else {return XCTFail()}
            let path = "/assets/\(imageID.transportString())?conv_id=\(selfUserID.transportString())"
            XCTAssertEqual(req.path, path)
        }
    }
    
    func testThatItDoesntGeneratesARequestWhenAUserImageIsMissing() {
        syncMOC.performGroupedBlockAndWait{
            // given
            let imageID = UUID()
            
            self.user1.mediumRemoteIdentifier = imageID;
            self.user1.smallProfileRemoteIdentifier = imageID;
            self.user1.localMediumRemoteIdentifier = nil;
            self.user1.imageMediumData = nil;
            self.user1.localSmallProfileRemoteIdentifier = nil;
            self.user1.imageSmallProfileData = nil;
            
            // when
            self.forwardChanges(for:self.user1)
            let request = self.sut.nextRequest()
            
            // then
            XCTAssertNil(request)
        }
    }
    
    func testThatItGeneratesARequestWhenAUserImageIsMissingAndItHasBeenRequested() {
        // given
        let imageID = UUID()

        syncMOC.performGroupedBlockAndWait{
            self.user1.mediumRemoteIdentifier = imageID;
            self.user1.localMediumRemoteIdentifier = nil;
            self.user1.imageMediumData = nil;
            self.user1.localSmallProfileRemoteIdentifier = nil;
            self.user1.imageSmallProfileData = nil;
        }
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
    
        // when
        expectation(forNotification: "ZMRequestUserProfileAssetNotification", object: nil, handler: nil)
        UserImageStrategy.requestAssetForUser(with:self.user1.objectID)
        XCTAssert(waitForCustomExpectations(withTimeout: 0.5))
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 1.5))

        syncMOC.performGroupedBlockAndWait{
            self.forwardChanges(for:self.user1)
            let request = self.sut.nextRequest()

            // then
            guard let req = request else {return XCTFail()}
            let path = "/assets/\(imageID.transportString())?conv_id=\(self.user1.remoteIdentifier!.transportString())"
            XCTAssertEqual(req.path, path)
        }
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
    }
    
    func testThatItGeneratesARequestForRetrievingASmallProfileUserImage() {
        syncMOC.performGroupedBlockAndWait{
            // given
            let imageID = UUID()
            self.user1.smallProfileRemoteIdentifier = imageID;
            
            // when
            let request = self.sut.request(forFetching: self.user1, downstreamSync: self.sut.smallProfileDownstreamSync)
            
            // then
            guard let req = request else {return XCTFail()}
            XCTAssertEqual(req.method, .methodGET);
            
            let path = "/assets/\(imageID.transportString())?conv_id=\(self.user1.remoteIdentifier!.transportString())"
            XCTAssertEqual(req.path, path)
            XCTAssertEqual(req.method, .methodGET);
            
            XCTAssertEqual(req.acceptedResponseMediaTypes, .image);
            XCTAssertNil(req.payload);
        }
    }
    
    func testThatItGeneratesARequestForRetrievingAMediumUserImage() {
        syncMOC.performGroupedBlockAndWait{
            // given
            let imageID = UUID()
            self.user1.mediumRemoteIdentifier = imageID
            
            // when
            let request = self.sut.request(forFetching: self.user1, downstreamSync: self.sut.mediumDownstreamSync)
            
            // then
            guard let req = request else {return XCTFail()}
            XCTAssertEqual(req.method, .methodGET);
            
            let path = "/assets/\(imageID.transportString())?conv_id=\(self.user1.remoteIdentifier!.transportString())"
            XCTAssertEqual(req.path, path)
            XCTAssertEqual(req.method, .methodGET);
            
            XCTAssertEqual(req.acceptedResponseMediaTypes, .image);
            XCTAssertNil(req.payload);
        }
    }
    
    func testThatItUdpatesTheMediumImageFromAResponse() {
        // TODO: There's a race condition here.
        // If the mediumRemoteIdentifier changes while we're retrieving image data
        // we'll still assume that the data is the newest. In order to fix that,
        // we would have to change the ZMDownloadTranscoder protocol such
        // that we can send the mediumRemoteIdentifier along the request and receive
        // it back with the response. This is similar to how the upstream sync works.
        
        syncMOC.performGroupedBlockAndWait{
            // given
            let imageID = UUID()
            self.user1.mediumRemoteIdentifier = imageID
            self.user1.imageMediumData = nil;
            let imageData = self.verySmallJPEGData()
            
            let response = ZMTransportResponse(imageData:imageData, httpStatus:200, transportSessionError:nil, headers:[:])
            
            // when
            self.sut.update(self.user1, with: response, downstreamSync: self.sut.mediumDownstreamSync)
            
            // then
            XCTAssertEqual(self.user1.imageMediumData, imageData);
            XCTAssertEqual(self.user1.mediumRemoteIdentifier, imageID);
            XCTAssertEqual(self.user1.localMediumRemoteIdentifier, imageID);
        }
    }
    
    func testThatItUdpatesTheSmallProfileImageFromAResponse() {
        // TODO: There's a race condition here.
        // If the mediumRemoteIdentifier changes while we're retrieving image data
        // we'll still assume that the data is the newest. In order to fix that,
        // we would have to change the ZMDownloadTranscoder protocol such
        // that we can send the mediumRemoteIdentifier along the request and receive
        // it back with the response. This is similar to how the upstream sync works.
        
        syncMOC.performGroupedBlockAndWait{
            // given
            let imageID = UUID()

            self.user1.mediumRemoteIdentifier = imageID
            self.user1.smallProfileRemoteIdentifier = imageID;
            self.user1.imageSmallProfileData = nil;
            let imageData = self.verySmallJPEGData()
            let response = ZMTransportResponse(imageData:imageData, httpStatus:200, transportSessionError:nil, headers:[:])
            
            // when
            self.sut.update(self.user1, with: response, downstreamSync: self.sut.smallProfileDownstreamSync)
            
            // then
            XCTAssertEqual(self.user1.imageSmallProfileData, imageData);
            XCTAssertEqual(self.user1.smallProfileRemoteIdentifier, imageID);
            XCTAssertEqual(self.user1.localSmallProfileRemoteIdentifier, imageID);
        }
    }
}

// MARK: ImagePreprocessing

extension UserImageStrategyTests {

    func testThatSmallProfileImageAndMediumImageDataGetsGeneratedForNewlyUpdatedSelfUser() {
        
        // given
        var selfUser: ZMUser!
        syncMOC.performGroupedBlockAndWait{
            selfUser = ZMUser.selfUser(in:self.syncMOC)
            selfUser.setValue(self.data(forResource:"1900x1500", extension:"jpg"), forKey:"originalProfileImageData")
            self.forwardChanges(for:selfUser)
            
            XCTAssertNil(selfUser.imageSmallProfileData)
            XCTAssertNil(selfUser.imageMediumData)
        }

        // when
        syncMOC.performAndWait {
            _ = self.sut.nextRequest()
        }
        
        // then
        XCTAssert(self.wait(withTimeout: 0.5, forSaveOf: self.syncMOC, until: { () -> Bool in
            return selfUser.originalProfileImageData == nil;
        }))
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))

        syncMOC.performGroupedBlockAndWait{
            XCTAssertTrue(selfUser.imageSmallProfileData?.count > 0)
            XCTAssertTrue(selfUser.imageMediumData?.count > 0)
            XCTAssertNil(selfUser.originalProfileImageData)
        }
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
    }

    func setUp(selfUser:ZMUser, with remoteID:UUID, formats:[ZMImageFormat], locallyModifiedKeys:[String]) {
        // given
        syncMOC.performGroupedBlockAndWait{
            selfUser.remoteIdentifier = remoteID
            selfUser.imageCorrelationIdentifier = UUID()
            
            formats.forEach{
                let profileImageData : Data
                switch $0 {
                case .profile: profileImageData = self.data(forResource:"tiny", extension:"jpg")
                case .medium: profileImageData = self.data(forResource:"medium", extension:"jpg")
                default: return XCTFail("Unrecognized image format in test");
                }
                selfUser.setImageData(profileImageData, for:$0, properties:nil)
            }
            
            let selfConv = ZMConversation.insertNewObject(in: self.syncMOC)
            selfConv.conversationType = .self;
            selfConv.remoteIdentifier = remoteID;
            
            selfUser.needsToBeUpdatedFromBackend = false;
            selfUser.setLocallyModifiedKeys(Set(locallyModifiedKeys))
        }
        
        XCTAssertFalse(selfUser.needsToBeUpdatedFromBackend);
        forwardChanges(for: selfUser)
        selfUser.setValue(self.data(forResource:"medium", extension:"jpg"), forKey:"originalProfileImageData")
    }
    
    func expect(request: ZMTransportRequest, for selfUser: ZMUser, format: ZMImageFormat, convID: UUID, handler:@escaping ((ZMTransportRequest?) -> Void)) {
        var receivedRequest : ZMTransportRequest!
        syncMOC.performGroupedBlockAndWait{
            MockRequestStrategy.mockRequest = request
            
            // when
            receivedRequest = self.sut.nextRequest()
        }
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        syncMOC.performGroupedBlockAndWait{
            // then
            handler(receivedRequest)
        }
    }
    
    func checkImageUpload(with format:ZMImageFormat, modifiedKeys: [String]) -> Bool {
        // given
        let selfUserAndSelfConversationID = UUID()
        let selfUser = ZMUser.selfUser(in: self.syncMOC)
        setUp(selfUser: selfUser, with: selfUserAndSelfConversationID, formats: [format], locallyModifiedKeys: modifiedKeys)
        
        // expect
        let expectedRequest = ZMTransportRequest(getFromPath: "/TEST-SUCCESSFUL")
        
        // then
        var success = false
        self.expect(request: expectedRequest, for: selfUser, format: format, convID: selfUserAndSelfConversationID) { (request) in
            success = (request != nil) && (request == expectedRequest)
        }
        return success
    }
    
    func testThatItUploadsProfileImageDataToSelfConversation() {
        XCTAssertTrue(checkImageUpload(with:.profile, modifiedKeys:["imageSmallProfileData"]))
    }
    
    func testThatItUploadsMediumImageDataToSelfConversation() {
        XCTAssertTrue(checkImageUpload(with:.medium, modifiedKeys:["imageMediumData"]))
    }
    
    func testThatItDoesNotUploadMediumImageDataIfThereIsNoCorrelationIdentifier() {
        // given
        let selfUserAndSelfConversationID = UUID()
        let selfUser = ZMUser.selfUser(in: self.syncMOC)
        setUp(selfUser: selfUser, with: selfUserAndSelfConversationID, formats: [ZMImageFormat.medium], locallyModifiedKeys: ["imageMediumData"])
        selfUser.imageCorrelationIdentifier = nil
        MockRequestStrategy.mockRequest = ZMTransportRequest(getFromPath: "/TEST-SUCCESSFUL")
        
        // expect
        var receivedRequest : ZMTransportRequest!
        syncMOC.performGroupedBlockAndWait{
            
            // when
            receivedRequest = self.sut.nextRequest()
        }
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertNil(receivedRequest)
    }
    
    
    func testThatItSetsTheRemoteIdentifierForSmallProfile() {
        // given
        let selfUserAndSelfConversationID = UUID()
        let selfUser = ZMUser.selfUser(in: self.syncMOC)
        setUp(selfUser: selfUser, with: selfUserAndSelfConversationID, formats: [.profile], locallyModifiedKeys: ["imageSmallProfileData"])
        
        let imageID = UUID()
        let smallProfileAsset = ZMAssetMetaDataEncoder.createAssetData(with: imageID, imageOwner: selfUser, format: .profile, correlationID: selfUser.imageCorrelationIdentifier!)
        
        // expect
        let expectedSmallProfileRequest = ZMTransportRequest(getFromPath:"/small-profile-upload-request")
        let smallProfileResponse = ZMTransportResponse(payload:["data": smallProfileAsset] as ZMTransportData, httpStatus:200, transportSessionError:nil)
        self.expect(request: expectedSmallProfileRequest, for: selfUser, format: .profile, convID: selfUserAndSelfConversationID) { (request) in
            XCTAssertEqual(request, expectedSmallProfileRequest)
            request?.complete(with: smallProfileResponse)
        }
        
        // then
        syncMOC.performGroupedBlockAndWait{
            XCTAssertEqual(selfUser.smallProfileRemoteIdentifier, imageID);
            XCTAssertEqual(selfUser.localSmallProfileRemoteIdentifier, imageID);
            XCTAssertFalse(selfUser.keysThatHaveLocalModifications.contains("smallProfileRemoteIdentifier_data"))
            XCTAssertFalse(selfUser.keysThatHaveLocalModifications.contains("imageSmallProfileData"))
        }
    }
    
    func testThatItSetsTheRemoteIdentifierForMedium() {
        // given
        let selfUserAndSelfConversationID = UUID()
        let selfUser = ZMUser.selfUser(in: self.syncMOC)
        setUp(selfUser: selfUser, with: selfUserAndSelfConversationID, formats: [.medium], locallyModifiedKeys: ["imageMediumData"])
        
        let imageID = UUID()
        let mediumAsset = ZMAssetMetaDataEncoder.createAssetData(with: imageID, imageOwner: selfUser, format: .medium, correlationID: selfUser.imageCorrelationIdentifier!)
        
        // expect
        let expectedMediumRequest = ZMTransportRequest(getFromPath:"/medium-upload-request")
        let mediumResponse = ZMTransportResponse(payload:["data": mediumAsset] as ZMTransportData, httpStatus:200, transportSessionError:nil)
        self.expect(request: expectedMediumRequest, for: selfUser, format: .medium, convID: selfUserAndSelfConversationID) { (request) in
            XCTAssertEqual(request, expectedMediumRequest);
            request?.complete(with: mediumResponse)
        }
        
        // then
        syncMOC.performGroupedBlockAndWait{
            XCTAssertEqual(selfUser.mediumRemoteIdentifier, imageID)
            XCTAssertEqual(selfUser.localMediumRemoteIdentifier, imageID)
            XCTAssertFalse(selfUser.keysThatHaveLocalModifications.contains("mediumRemoteIdentifier_data"))
            XCTAssertFalse(selfUser.keysThatHaveLocalModifications.contains("imageMediumData"))
        }
    }

    func testThatItRecoverFromInconsistenUserImageState() {
        // given
        let modifiedKeys = ["imageMediumData", "imageSmallProfileData"]
        let selfUserAndSelfConversationID = UUID()
        let selfUser = ZMUser.selfUser(in: self.syncMOC)
        setUp(selfUser: selfUser, with: selfUserAndSelfConversationID, formats: [.medium, .profile], locallyModifiedKeys: modifiedKeys)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        selfUser.imageMediumData = nil;
        selfUser.imageSmallProfileData = nil;
        
        XCTAssertTrue(selfUser.hasLocalModifications(forKeys: Set(modifiedKeys)))
        XCTAssertNil(selfUser.imageSmallProfileData)
        XCTAssertNil(selfUser.imageMediumData)
        
        // when
        let localSUT = UserImageStrategy(managedObjectContext:self.syncMOC, applicationStatus:mockApplicationStatus, imageProcessingQueue:self.queue)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        syncMOC.performGroupedBlockAndWait{
            XCTAssertFalse(selfUser.hasLocalModifications(forKeys:Set(modifiedKeys)))
            localSUT.tearDown()
        }
    }
    
    func testThatItDoesNotUpdateTheImageIfTheCorrelationIDFromTheBackendResponseDiffersFromTheUserImageCorrelationID(){
        // given
        let modifiedKeys = ["imageMediumData", "imageSmallProfileData"]
        let selfUserAndSelfConversationID = UUID()
        let selfUser = ZMUser.selfUser(in: self.syncMOC)
        setUp(selfUser: selfUser, with: selfUserAndSelfConversationID, formats: [.medium, .profile], locallyModifiedKeys: modifiedKeys)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        let originalImageCorrelationIdentifier = selfUser.imageCorrelationIdentifier;
        
        let imageID = UUID()
        let invalidCorrelationID = UUID()
        let smallProfileAsset = ZMAssetMetaDataEncoder.createAssetData(with: imageID, imageOwner: selfUser, format: .profile, correlationID: invalidCorrelationID)
        
        // expect
        let expectedSmallProfileRequest = ZMTransportRequest(getFromPath:"/upload-request")
        let response = ZMTransportResponse(payload:["data": smallProfileAsset, "id": UUID().transportString()] as ZMTransportData, httpStatus:200, transportSessionError:nil)
        self.expect(request: expectedSmallProfileRequest, for: selfUser, format: .profile, convID: selfUserAndSelfConversationID) { (request) in
            XCTAssertEqual(request, expectedSmallProfileRequest);
            request?.complete(with: response)
        }

        // then
        syncMOC.performGroupedBlockAndWait{
            XCTAssertEqual(selfUser.imageCorrelationIdentifier, originalImageCorrelationIdentifier);
            XCTAssertNil(selfUser.smallProfileRemoteIdentifier);
            XCTAssertFalse(selfUser.keysThatHaveLocalModifications.contains("mediumRemoteIdentifier_data"))
        }
    }
    
    func testThatItMarksImageIdentifiersAsToBeUploadedAfterUploadingSmallProfileWhenBothImagesAreUploaded() {
        // given
        let modifiedKeys = ["imageSmallProfileData"]
        let selfUserAndSelfConversationID = UUID()
        let selfUser = ZMUser.selfUser(in: self.syncMOC)
        setUp(selfUser: selfUser, with: selfUserAndSelfConversationID, formats: [.profile], locallyModifiedKeys: modifiedKeys)
        
        let imageID = UUID()
        let smallProfileAsset = ZMAssetMetaDataEncoder.createAssetData(with: imageID, imageOwner: selfUser, format: .profile, correlationID: selfUser.imageCorrelationIdentifier!)
        selfUser.processingDidFinish()
        
        // expect
        let expectedSmallProfileRequest = ZMTransportRequest(getFromPath:"/small-profile-upload-request")
        let response = ZMTransportResponse(payload:["data": smallProfileAsset] as ZMTransportData, httpStatus:200, transportSessionError:nil)
        self.expect(request: expectedSmallProfileRequest, for: selfUser, format: .profile, convID: selfUserAndSelfConversationID) { (request) in
            XCTAssertEqual(request, expectedSmallProfileRequest);
            request?.complete(with: response)
        }
        
        // then
        syncMOC.performGroupedBlockAndWait{
            XCTAssertEqual(selfUser.smallProfileRemoteIdentifier, imageID);
            XCTAssertEqual(selfUser.localSmallProfileRemoteIdentifier, imageID);
            XCTAssertTrue(selfUser.keysThatHaveLocalModifications.contains("smallProfileRemoteIdentifier_data"))
            XCTAssertTrue(selfUser.keysThatHaveLocalModifications.contains("mediumRemoteIdentifier_data"))
            XCTAssertFalse(selfUser.keysThatHaveLocalModifications.contains("imageSmallProfileData"))
        }
    }
}
