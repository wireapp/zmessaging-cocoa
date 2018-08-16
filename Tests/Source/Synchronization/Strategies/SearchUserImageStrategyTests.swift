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

let UserRequestURL = "/users?ids="

class FakeSearchDirectory : NSObject {}

extension SearchUserImageStrategyTests: ZMManagedObjectContextProvider {
    
    var managedObjectContext: NSManagedObjectContext! {
        return uiMOC
    }
    
    var syncManagedObjectContext: NSManagedObjectContext! {
        return syncMOC
    }
    
}

class SearchUserImageStrategyTests : MessagingTest {
    
    var sut: SearchUserImageStrategy!
    var mockApplicationStatus : MockApplicationStatus!
    
    override func setUp() {
        super.setUp()
        uiMOC.zm_searchUserCache = NSCache()
        mockApplicationStatus = MockApplicationStatus()
        mockApplicationStatus.mockSynchronizationState = .eventProcessing
        sut = SearchUserImageStrategy(applicationStatus: mockApplicationStatus, managedObjectContext: uiMOC)
    }
    
    override func tearDown() {
        sut = nil
        uiMOC.zm_searchUserCache = nil
        mockApplicationStatus = nil
        super.tearDown()
    }
    
    func createSearchUser() -> ZMSearchUser {
        return ZMSearchUser(contextProvider: self, name: "Foo", handle: "foo", accentColor: .brightOrange, remoteIdentifier: UUID())
    }
    
    func userIDs(from searchUsers: Set<ZMSearchUser>) -> Set<UUID> {
        return Set(searchUsers.compactMap { $0.remoteIdentifier })
    }
    
    func userData(smallProfilePictureID: UUID?, mediumPictureID: UUID? = nil, for userID: UUID, assetPayload: [[String: Any]] = []) -> [String : Any] {
        return [
            "id" : userID.transportString(),
            "picture": [
                [
                    "id": smallProfilePictureID?.transportString() ?? UUID().transportString(),
                    "info": ["tag": "smallProfile"]
                ],
                [
                    "id": mediumPictureID?.transportString() ?? UUID().transportString(),
                    "info": [ "tag": "medium" ]
                ],
            ],
            "assets": assetPayload // We include an empty assets payload to ensure it does not get picked up
        ]
    }

    func userData(previewAssetKey: String?, completeAssetKey: String? = nil, for userID: UUID) -> [String : Any] {
        return [
            "id" : userID.transportString(),
            "assets" : assetPayload(previewAssetKey: previewAssetKey, completeAssetKey: completeAssetKey)
        ]
    }

    func assetPayload(previewAssetKey: String?, completeAssetKey: String? = nil) -> [[String: Any]] {
        return [
            [
                "size": "preview",
                "type": "image",
                "key": previewAssetKey ?? UUID().transportString()
            ],
            [
                "size": "complete",
                "type": "image",
                "key": completeAssetKey ?? UUID().transportString()
            ]
        ]
    }

    func userIDs(in getRequest: ZMTransportRequest) -> Set<UUID> {
        if !getRequest.path.hasPrefix(UserRequestURL) {
            return Set()
        }
        let userIDs = String(getRequest.path[UserRequestURL.endIndex...])
        let tokens = userIDs.components(separatedBy: ",").compactMap { UUID(uuidString:$0) }
        return Set(tokens)
    }
    
    func setupSearchDirectory(userCount: Int) -> Set<ZMSearchUser> {
        var users = Set<ZMSearchUser>()
        for _ in 0..<userCount {
            let user = createSearchUser()
            users.insert(user)
        }
        return users
    }
}

extension SearchUserImageStrategyTests {
    
    func testThatItReturnsNoRequestIfThereIsNoRequestUserProfile() {
        // given
        _ = setupSearchDirectory(userCount: 1)

        // when
        let request = sut.nextRequest()

        // then
        XCTAssertNil(request);
    }
    
    func testThatNextRequestCreatesARequestForAllUserIDsWeHaveRequested(){
        // given
        let searchSet = setupSearchDirectory(userCount: 3)
        searchSet.forEach({ $0.requestPreviewProfileImage() })
        
        // when
        guard let request = sut.nextRequest() else { return XCTFail() }
        
        // then
        XCTAssertNotNil(request);
        XCTAssertEqual(request.method, .methodGET);
        XCTAssertTrue(request.needsAuthentication);
        
        XCTAssertTrue(request.path.hasPrefix(UserRequestURL))
        let expectedUserIDs = userIDs(from: searchSet)
        XCTAssertEqual(userIDs(in:request), expectedUserIDs)
    }
    
    func testThatNextRequestDoesNotCreateARequestClientNotReady(){
        // given
        let searchSet = setupSearchDirectory(userCount: 3)
        searchSet.forEach({ $0.requestPreviewProfileImage() })
        mockApplicationStatus.mockSynchronizationState = .unauthenticated
        
        // when
        let request = sut.nextRequest()
        
        // then
        XCTAssertNil(request);
    }

    func testThatNextRequestCreatesARequestForAllUserIDsForAllUserIDsWeHaveRequestedThatWeAreNotAlreadyRequesting() {
        // given
        let searchSet1 = setupSearchDirectory(userCount: 2)
        searchSet1.forEach({ $0.requestPreviewProfileImage() })
        guard sut.nextRequest() != nil else { return XCTFail() } // start first request
        
        // when
        let searchSet2 = setupSearchDirectory(userCount: 1)
        searchSet2.forEach({ $0.requestPreviewProfileImage() })
        guard let request2 = sut.nextRequest() else { return XCTFail() }
        
        // then
        XCTAssertNotNil(request2)
        XCTAssertEqual(request2.method, .methodGET)
        XCTAssertTrue(request2.needsAuthentication)
        
        let expectedUserIDs = userIDs(from: searchSet2)
        XCTAssertEqual(userIDs(in:request2), expectedUserIDs)
    }
    
    
    func testThatCompletingARequestUpdatesAssetKeysOnSearchUsers_LegacyIds() {
        // given
        let searchUsers = Array(setupSearchDirectory(userCount: 2))
        let searchUser1 = searchUsers.first!
        let searchUser2 = searchUsers.last!
        searchUsers.forEach({ $0.requestPreviewProfileImage() })
        
        let smallAssetID1 = UUID(), mediumAssetID1 = UUID()
        let smallAssetID2 = UUID(), mediumAssetID2 = UUID()
        
        let payload = [
            userData(smallProfilePictureID: smallAssetID1, mediumPictureID: mediumAssetID1,  for: searchUser1.remoteIdentifier!),
            userData(smallProfilePictureID: smallAssetID2, mediumPictureID: mediumAssetID2, for: searchUser2.remoteIdentifier!)
        ]
        let response = ZMTransportResponse(payload: payload as ZMTransportData, httpStatus: 200, transportSessionError: nil)
        
        // when
        guard let request = sut.nextRequest() else { return XCTFail() }
        request.complete(with: response)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        if case SearchUserAssetKeys.legacy(small: let smallAssetID, medium: let mediumAssetID) = searchUser1.assetKeys! {
            XCTAssertEqual(smallAssetID, smallAssetID1)
            XCTAssertEqual(mediumAssetID, mediumAssetID1)
        } else {
            XCTFail()
        }
        
        if case SearchUserAssetKeys.legacy(small: let smallAssetID, medium: let mediumAssetID) = searchUser2.assetKeys! {
            XCTAssertEqual(smallAssetID, smallAssetID2)
            XCTAssertEqual(mediumAssetID, mediumAssetID2)
        } else {
            XCTFail()
        }
    }

    func testThatCompletingARequestUpdatesAssetKeysOnSearchUsers_AssetKeys() {
        // Given
        let searchUsers = Array(setupSearchDirectory(userCount: 2))
        let searchUser1 = searchUsers.first!
        let searchUser2 = searchUsers.last!
        searchUsers.forEach({ $0.requestPreviewProfileImage() })

        let previewAssetKey1 = "previewAssetKey1", completeAssetKey1 = "completeAssetKey1"
        let previewAssetKey2 = "previewAssetKey2", completeAssetKey2 = "completeAssetKey2"

        let payload = [
            userData(previewAssetKey: previewAssetKey1, completeAssetKey: completeAssetKey1, for: searchUser1.remoteIdentifier!),
            userData(previewAssetKey: previewAssetKey2, completeAssetKey: completeAssetKey2, for: searchUser2.remoteIdentifier!)
        ]

        let response = ZMTransportResponse(payload: payload as ZMTransportData, httpStatus: 200, transportSessionError: nil)

        // When
        guard let request = sut.nextRequest() else { return XCTFail() }
        request.complete(with: response)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))

        // Then
        if case SearchUserAssetKeys.asset(preview: let previewAssetKey, complete: let completeAssetKey) = searchUser1.assetKeys! {
            XCTAssertEqual(previewAssetKey, previewAssetKey1)
            XCTAssertEqual(completeAssetKey, completeAssetKey1)
        } else {
            XCTFail()
        }
        
        if case SearchUserAssetKeys.asset(preview: let previewAssetKey, complete: let completeAssetKey) = searchUser2.assetKeys! {
            XCTAssertEqual(previewAssetKey, previewAssetKey2)
            XCTAssertEqual(completeAssetKey, completeAssetKey2)
        } else {
            XCTFail()
        }
    }

    func testThatCompletingARequestUpdatesAssetKeysOnSearchUsers_MixedAssetKeysAndLegacy() {
        // Given
        let users = Array(setupSearchDirectory(userCount: 3))
        let user1 = users[0], user2 = users[1], user3 = users[2]
        let assetKey1 = "asset-key-1", assetKey2 = "asset-key-2"
        let legacyId1 = UUID.create(), legacyId2 = UUID.create()
        users.forEach({ $0.requestPreviewProfileImage() })

        let payload = [
            userData(previewAssetKey: assetKey1, for: user1.remoteIdentifier!),
            userData(smallProfilePictureID: legacyId1, for: user2.remoteIdentifier!, assetPayload: assetPayload(previewAssetKey: assetKey2)),
            userData(smallProfilePictureID: legacyId2, for: user3.remoteIdentifier!)
        ]

        let response = ZMTransportResponse(payload: payload as ZMTransportData, httpStatus: 200, transportSessionError: nil)

        // When
        guard let request = sut.nextRequest() else { return XCTFail() }
        request.complete(with: response)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))

        // Then
        if case SearchUserAssetKeys.asset(preview: let previewAssetKey, complete: _) = user1.assetKeys! {
            XCTAssertEqual(previewAssetKey, assetKey1)
        } else {
            XCTFail()
        }
        
        if case SearchUserAssetKeys.asset(preview: let previewAssetKey, complete: _) = user2.assetKeys! {
            XCTAssertEqual(previewAssetKey, assetKey2)
        } else {
            XCTFail()
        }
        
        if case SearchUserAssetKeys.legacy(small: let smallID, medium: _) = user3.assetKeys! {
            XCTAssertEqual(smallID, legacyId2)
        } else {
            XCTFail()
        }
    }

    func testThatAFailingUserProfileRequestWithAPermanentErrorClearsThemFromTheDownloadQueue() {
        // given
        let searchUsers = setupSearchDirectory(userCount: 2)
        searchUsers.forEach({ $0.requestPreviewProfileImage() })
        let response = ZMTransportResponse(payload: nil, httpStatus: 400, transportSessionError: nil)
        
        // when
        guard let request = sut.nextRequest() else { return XCTFail() }
        request.complete(with: response)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertNil(sut.nextRequest())
    }
    
    func testThatFailingAUserProfileRequestWithATemporaryErrorAllowsThemToBeDownloadedAgain() {
        // given
        let searchUsers = setupSearchDirectory(userCount: 2)
        searchUsers.forEach({ $0.requestPreviewProfileImage() })
        let response = ZMTransportResponse(payload: nil, httpStatus: 500, transportSessionError: nil)
        
        // when
        guard let request1 = sut.nextRequest() else { return XCTFail() }
        request1.complete(with: response)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        guard let request2 = sut.nextRequest() else { return XCTFail() }
        let expectedUserIDs = userIDs(from: searchUsers)
        XCTAssertEqual(userIDs(in:request2), expectedUserIDs)
    }
    
    func testThatCompletingAUserProfileRequestDoesNotAllowForThemToBeDownloadedAgain() {
        // given
        let searchUsers = Array(setupSearchDirectory(userCount: 2))
        searchUsers.forEach({ $0.requestPreviewProfileImage() })

        let payload = [
            userData(smallProfilePictureID: UUID(), for: searchUsers.first!.remoteIdentifier!),
            userData(smallProfilePictureID: UUID(), for: searchUsers.last!.remoteIdentifier!)
        ]
        let response = ZMTransportResponse(payload: payload as ZMTransportData, httpStatus: 200, transportSessionError: nil)
        
        // when
        guard let request1 = sut.nextRequest() else { return XCTFail() }
        request1.complete(with: response)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        guard let request2 = sut.nextRequest() else { return XCTFail() }
        XCTAssertEqual(userIDs(in:request2).count, 0)
    }
    
}


// MARK: - ImageAssets
extension SearchUserImageStrategyTests {
    
    func requestPath(for assetID: UUID, of userID: UUID) -> String {
        return "/assets/\(assetID.transportString())?conv_id=\(userID.transportString())"
    }
    
    func testThatNextRequestCreatesARequestForAnAssetID() {
        // given
        let searchUser = setupSearchDirectory(userCount: 1).first!
        let assetID = UUID()
        searchUser.update(from: userData(smallProfilePictureID: assetID, for: searchUser.remoteIdentifier!))
        searchUser.requestPreviewProfileImage()
        
        // when
        guard let request = sut.nextRequest() else { return XCTFail() }
        
        // then
        XCTAssertNotNil(request);
        XCTAssertEqual(request.method, .methodGET);
        XCTAssertTrue(request.needsAuthentication);
        
        let expectedPath = requestPath(for:assetID, of:searchUser.remoteIdentifier!)
        XCTAssertEqual(request.path, expectedPath);
    }
    
    func testThatNextRequestDoesNotCreatesARequestForAnAssetIDIfTheFirstRequestIsStillRunning() {
        // given
        let searchUser = setupSearchDirectory(userCount: 1).first!
        let assetID = UUID()
        searchUser.update(from: userData(smallProfilePictureID: assetID, for: searchUser.remoteIdentifier!))
        searchUser.requestPreviewProfileImage()
        
        // when
        let request1 = sut.nextRequest()
        let request2 = sut.nextRequest()
        
        // then
        XCTAssertNotNil(request1);
        XCTAssertNil(request2);
    }
    
    func testThatNextRequestCreatesARequestForAnAssetIDThatWeAreNotAlreadyRequesting() {
        // given
        let searchUser1 = setupSearchDirectory(userCount: 1).first!
        let searchUser2 = setupSearchDirectory(userCount: 1).first!
        
        let assetID1 = UUID()
        let assetID2 = UUID()
        
        searchUser1.update(from: userData(smallProfilePictureID: assetID1, for: searchUser1.remoteIdentifier!))
        searchUser2.update(from: userData(smallProfilePictureID: assetID2, for: searchUser2.remoteIdentifier!))
        searchUser1.requestPreviewProfileImage()
        searchUser2.requestPreviewProfileImage()
        
        // when
        guard let request1 = sut.nextRequest() else { return XCTFail() }
        guard let request2 = sut.nextRequest() else { return XCTFail() }

        // then
        XCTAssertNotNil(request1);
        XCTAssertEqual(request1.method, .methodGET);
        XCTAssertTrue(request1.needsAuthentication);
        
        XCTAssertNotNil(request2);
        XCTAssertEqual(request2.method, .methodGET);
        XCTAssertTrue(request2.needsAuthentication);
        
        let expectedPath1 = requestPath(for:assetID1, of:searchUser1.remoteIdentifier!)
        let expectedPath2 = requestPath(for:assetID2, of:searchUser2.remoteIdentifier!)
        XCTAssertTrue(request1.path == expectedPath1 || request1.path == expectedPath2)
        XCTAssertTrue(request2.path == expectedPath1 || request2.path == expectedPath2)
        XCTAssertNotEqual(request2.path, request1.path)
    }
    
    
    func testThatCompletingARequestUpdatesTheImageDataOnSearchUser() {
        // given
        let imageData = verySmallJPEGData()
        let searchUser1 = setupSearchDirectory(userCount: 1).first!
        let assetID1 = UUID()
        searchUser1.update(from: userData(smallProfilePictureID: assetID1, for: searchUser1.remoteIdentifier!))
        searchUser1.requestPreviewProfileImage()
        
        let response = ZMTransportResponse(imageData: imageData, httpStatus: 200, transportSessionError: nil, headers: nil)
        
        // when
        guard let request = sut.nextRequest() else { return XCTFail() }
        XCTAssertEqual(request.path, requestPath(for:assetID1, of:searchUser1.remoteIdentifier!));

        request.complete(with: response)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertEqual(searchUser1.previewImageData, imageData)
    }
    
    func testThatCompletingARequestRemovesTheAssetFromTheDownloadQueue() {
        // given
        let imageData = verySmallJPEGData()
        let searchUser1 = setupSearchDirectory(userCount: 1).first!
        let assetID1 = UUID()
        searchUser1.update(from: userData(smallProfilePictureID: assetID1, for: searchUser1.remoteIdentifier!))
        searchUser1.requestPreviewProfileImage()
        
        let response = ZMTransportResponse(imageData: imageData, httpStatus: 200, transportSessionError: nil, headers: nil)
        
        // when
        guard let request = sut.nextRequest() else { return XCTFail() }
        XCTAssertEqual(request.path, requestPath(for:assetID1, of:searchUser1.remoteIdentifier!));
        
        request.complete(with: response)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertNil(sut.nextRequest())
    }
    
    func testThatFailingAnAssetRequestWithAPermanentErrorDeletesAssetKeysFromSearchUser() {
        // given
        let searchUser1 = setupSearchDirectory(userCount: 1).first!
        let assetID1 = UUID()
        searchUser1.update(from: userData(smallProfilePictureID: assetID1, for: searchUser1.remoteIdentifier!))
        searchUser1.requestPreviewProfileImage()
        let response = ZMTransportResponse(payload: nil, httpStatus: 400, transportSessionError: nil)
        
        // when
        guard let request = sut.nextRequest() else { return XCTFail() }
        XCTAssertEqual(request.path, requestPath(for:assetID1, of:searchUser1.remoteIdentifier!));
        
        request.complete(with: response)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertNil(searchUser1.assetKeys)
    }
    
    func testThatFailingAnAssertRequestWithATemporaryErrorAllowsForThoseAssetIDsToBeDownloadedAgain() {
        // given
        let searchUser1 = setupSearchDirectory(userCount: 1).first!
        let assetID1 = UUID()
        searchUser1.update(from: userData(smallProfilePictureID: assetID1, for: searchUser1.remoteIdentifier!))
        searchUser1.requestPreviewProfileImage()
        
        let response = ZMTransportResponse(payload: nil, httpStatus: 500, transportSessionError: nil)
        
        // when
        guard let request1 = sut.nextRequest() else { return XCTFail() }
        XCTAssertEqual(request1.path, requestPath(for:assetID1, of:searchUser1.remoteIdentifier!));
        
        request1.complete(with: response)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        guard let request2 = sut.nextRequest() else { return XCTFail() }
        XCTAssertEqual(request2.path, requestPath(for:assetID1, of:searchUser1.remoteIdentifier!));
    }
    
    func testThatItNotifiesTheSearchUserWhenAnImageIsDownloaded_preview() {
        // given
        let imageData = verySmallJPEGData()
        let searchUser1 = setupSearchDirectory(userCount: 1).first!
        let assetID1 = UUID()
        searchUser1.update(from: userData(smallProfilePictureID: assetID1, for: searchUser1.remoteIdentifier!))
        searchUser1.requestPreviewProfileImage()
        
        let response = ZMTransportResponse(imageData: imageData, httpStatus: 200, transportSessionError: nil, headers: nil)
        uiMOC.searchUserObserverCenter.addSearchUser(searchUser1) // This is called when the searchDirectory returns the searchUsers
        let userObserver = UserChangeObserver(user: searchUser1, managedObjectContext:self.uiMOC)!
        
        // when
        guard let request = sut.nextRequest() else { return XCTFail() }
        request.complete(with: response)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        guard let note = userObserver.notifications.firstObject as? UserChangeInfo else { return XCTFail() }
        XCTAssertTrue(note.imageSmallProfileDataChanged)
        XCTAssertEqual(note.user as? ZMSearchUser, searchUser1)
    }
    
    func testThatItNotifiesTheSearchUserWhenAnImageIsDownloaded_complete() {
        // given
        let imageData = verySmallJPEGData()
        let searchUser1 = setupSearchDirectory(userCount: 1).first!
        let previewAssetKey = "previewKey123"
        let completeAssetKey = "previewKey123"
        searchUser1.update(from: userData(previewAssetKey: previewAssetKey, completeAssetKey: completeAssetKey, for: searchUser1.remoteIdentifier!))
        searchUser1.requestCompleteProfileImage()
        
        let response = ZMTransportResponse(imageData: imageData, httpStatus: 200, transportSessionError: nil, headers: nil)
        uiMOC.searchUserObserverCenter.addSearchUser(searchUser1) // This is called when the searchDirectory returns the searchUsers
        let userObserver = UserChangeObserver(user: searchUser1, managedObjectContext:self.uiMOC)!
        
        // when
        guard let request = sut.nextRequest() else { return XCTFail() }
        request.complete(with: response)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        guard let note = userObserver.notifications.firstObject as? UserChangeInfo else { return XCTFail() }
        XCTAssertTrue(note.imageMediumDataChanged)
        XCTAssertEqual(note.user as? ZMSearchUser, searchUser1)
    }

}


