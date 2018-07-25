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

class UserImageStrategyTests : MessagingTest {

    var sut : UserImageStrategy!
    var mockApplicationStatus : MockApplicationStatus!
    var user1 : ZMUser!
    var user1ID: UUID!
    
    override func setUp() {
        super.setUp()
        syncMOC.zm_userImageCache = UserImageLocalCache()
        uiMOC.zm_userImageCache = syncMOC.zm_userImageCache
        
        mockApplicationStatus = MockApplicationStatus()
        mockApplicationStatus.mockSynchronizationState = .eventProcessing

        sut = UserImageStrategy(withManagedObjectContext: syncMOC, applicationStatus:mockApplicationStatus)
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
        self.sut = nil;
        self.user1 = nil;
        self.user1ID = nil;
        super.tearDown()
    }
    
    static func requestCompleteAsset(for user: ZMUser) {
        NotificationInContext(name: .userDidRequestCompleteAsset,
                              context: user.managedObjectContext!.notificationContext,
                              object: user.objectID).post()
    }
    
    static func requestPreviewAsset(for user: ZMUser) {
        NotificationInContext(name: .userDidRequestPreviewAsset,
                              context: user.managedObjectContext!.notificationContext,
                              object: user.objectID).post()
    }

}

// MARK:- DownloadPredicate
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
        syncMOC.saveOrRollback()
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
    
        // when        
        uiMOC.performGroupedBlock {
            (self.uiMOC.object(with: self.user1.objectID) as? ZMUser)?.requestCompleteProfileImage()
        }
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))

        syncMOC.performGroupedBlockAndWait {
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
    
    func testThatItUpdatesTheSmallProfileImageFromAResponse() {
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
    
    func testThatItHandlesMediumImageNotBeingPresentOnTheRemote() {
        func prepareForMediumAssetRequest() {
            forwardChanges(for: user1)
            UserImageStrategyTests.requestCompleteAsset(for: user1)
            XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        }
        
        // given
        syncMOC.performGroupedBlockAndWait { [user1] in
            user1?.mediumRemoteIdentifier = .create()
        }
        
        prepareForMediumAssetRequest()

        syncMOC.performGroupedBlockAndWait {
            guard let request = self.sut.nextRequest() else { return XCTFail() }
            
            let response = ZMTransportResponse(
                payload: nil,
                httpStatus: 404,
                transportSessionError: nil
            )
            
            // when
            request.complete(with: response)
        }
        
        // when
        prepareForMediumAssetRequest()
        
        // then
        syncMOC.performGroupedBlockAndWait {
            XCTAssertNil(self.sut.nextRequest())
            XCTAssertNil(self.user1.mediumRemoteIdentifier)
            XCTAssertNil(self.user1.localMediumRemoteIdentifier)
        }
        
        // when
        prepareForMediumAssetRequest()
        
        // then
        syncMOC.performGroupedBlockAndWait {
            XCTAssertNil(self.sut.nextRequest())
            XCTAssertNil(self.user1.mediumRemoteIdentifier)
            XCTAssertNil(self.user1.localMediumRemoteIdentifier)
        }
    }

    func testThatItHandlesSmallImageNotBeingPresentOnTheRemote() {
        func prepareForSmallAssetRequest() {
            forwardChanges(for: user1)
            UserImageStrategyTests.requestPreviewAsset(for: user1)
            XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        }
        
        // given
        syncMOC.performGroupedBlockAndWait { [user1] in
            user1?.smallProfileRemoteIdentifier = .create()
        }
        
        prepareForSmallAssetRequest()
        
        syncMOC.performGroupedBlockAndWait {
            guard let request = self.sut.nextRequest() else { return XCTFail() }
            
            let response = ZMTransportResponse(
                payload: nil,
                httpStatus: 404,
                transportSessionError: nil
            )
            
            // when
            request.complete(with: response)
        }
        
        // when
        prepareForSmallAssetRequest()
        
        // then
        syncMOC.performGroupedBlockAndWait {
            XCTAssertNil(self.sut.nextRequest())
            XCTAssertNil(self.user1.smallProfileRemoteIdentifier)
            XCTAssertNil(self.user1.localSmallProfileRemoteIdentifier)
        }
        
        // when
        prepareForSmallAssetRequest()
        
        syncMOC.performGroupedBlockAndWait {
            XCTAssertNil(self.sut.nextRequest())
            XCTAssertNil(self.user1.smallProfileRemoteIdentifier)
            XCTAssertNil(self.user1.localSmallProfileRemoteIdentifier)
        }
    }
}
