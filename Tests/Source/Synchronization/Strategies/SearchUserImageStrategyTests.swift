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

class SearchUserImageStrategyTests : MessagingTest {
    
    var sut: SearchUserImageStrategy!
    var userIDsTable: SearchDirectoryUserIDTable!
    var imagesCache: NSCache<NSUUID, NSData>!
    var assetIDCache: NSCache<NSUUID, SearchUserAssetObjC>!
    var mockApplicationStatus : MockApplicationStatus!
    
    override func setUp() {
        super.setUp()
        imagesCache = NSCache<NSUUID, NSData>()
        assetIDCache = NSCache<NSUUID, SearchUserAssetObjC>()
        userIDsTable = SearchDirectoryUserIDTable()
        mockApplicationStatus = MockApplicationStatus()
        mockApplicationStatus.mockSynchronizationState = .eventProcessing
        sut = SearchUserImageStrategy(applicationStatus: mockApplicationStatus, managedObjectContext: uiMOC, imagesByUserIDCache: imagesCache, mediumAssetCache: assetIDCache, userIDsTable: userIDsTable)
    }
    
    override func tearDown() {
        imagesCache.removeAllObjects()
        assetIDCache.removeAllObjects()
        userIDsTable.clear()
        userIDsTable = nil
        sut = nil
        assetIDCache = nil
        mockApplicationStatus = nil
        super.tearDown()
    }
    
    func createSearchUser() -> ZMSearchUser {
        return ZMSearchUser(name: "foo", handle: "foo", accentColor: .brightOrange, remoteID: UUID(), user: nil, syncManagedObjectContext: syncMOC, uiManagedObjectContext: uiMOC)
    }
    
    func userIDs(from searchUsers: Set<ZMSearchUser>) -> Set<UUID> {
        return Set(searchUsers.flatMap{$0.remoteIdentifier})
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
        let userIDs = getRequest.path.substring(from: UserRequestURL.endIndex)
        let tokens = userIDs.components(separatedBy: ",").flatMap{UUID(uuidString:$0)}
        return Set(tokens)
    }
    
    func setupSearchDirectory(userCount: Int) -> Set<ZMSearchUser> {
        var users = Set<ZMSearchUser>()
        for _ in 0..<userCount {
            let user = createSearchUser()
            users.insert(user)
        }
        userIDsTable.setUsers(users, forDirectory: FakeSearchDirectory())
        return users
    }
}

extension SearchUserImageStrategyTests {

    func testThatTheRightValuesAreStoredByTheInit() {
        XCTAssertEqual(userIDsTable, sut.userIDsTable)
        XCTAssertEqual(imagesCache, sut.imagesByUserIDCache)
    }
    
    func testThatTheDefaultInitCreatesTheCorrectTables() {
        // when
        let strategy = SearchUserImageStrategy(applicationStatus:mockApplicationStatus, managedObjectContext:self.syncMOC)
        
        // then
        XCTAssertEqual(strategy.userIDsTable, SearchDirectory.userIDsMissingProfileImage)
        XCTAssertEqual(strategy.imagesByUserIDCache, ZMSearchUser.searchUserToSmallProfileImageCache())
    }
    
    
    func testThatItReturnsNoRequestIfThereIsNoUserIDMissingProfileImage() {
        // given
        XCTAssertEqual(SearchDirectory.userIDsMissingProfileImage.allUserIds().count, 0)
        
        // when
        let request = sut.nextRequest()
        
        // then
        XCTAssertNil(request);
    }
    
    func testThatNextRequestCreatesARequestForAllUserIDsInTheUserTable(){
        // given
        let searchSet = setupSearchDirectory(userCount: 3)
        
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
        _ = setupSearchDirectory(userCount: 3)
        mockApplicationStatus.mockSynchronizationState = .unauthenticated
        
        // when
        let request = sut.nextRequest()
        
        // then
        XCTAssertNil(request);
    }

    func testThatNextRequestCreatesARequestForAllUserIDsInTheUserTableThatWeAreNotAlreadyRequesting() {
        // given
        _ = setupSearchDirectory(userCount: 2)
        guard sut.nextRequest() != nil else { return XCTFail() } // start first request
        
        // when
        let searchSet2 = setupSearchDirectory(userCount: 1)
        guard let request2 = sut.nextRequest() else { return XCTFail() }
        
        // then
        XCTAssertNotNil(request2)
        XCTAssertEqual(request2.method, .methodGET)
        XCTAssertTrue(request2.needsAuthentication)
        
        let expectedUserIDs = userIDs(from: searchSet2)
        XCTAssertEqual(userIDs(in:request2), expectedUserIDs)
    }
    
    
    func testThatCompletingARequestSetsTheAssetIDForThoseUsersOnTheTable_LegacyIds() {
        // given
        let searchUsers = Array(setupSearchDirectory(userCount: 2))
        let searchUser1 = searchUsers.first!
        let searchUser2 = searchUsers.last!
        
        let assetID1 = UUID()
        let assetID2 = UUID()
        
        let payload = [
            userData(smallProfilePictureID: assetID1, for: searchUser1.remoteIdentifier!),
            userData(smallProfilePictureID: assetID2, for: searchUser2.remoteIdentifier!)
        ]
        let response = ZMTransportResponse(payload: payload as ZMTransportData, httpStatus: 200, transportSessionError: nil)
        
        // when
        guard let request = sut.nextRequest() else { return XCTFail() }
        request.complete(with: response)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        let expectedAssetIDs = Set(arrayLiteral:
                                   SearchUserAndAsset(searchUser: searchUser1, legacyID: assetID1),
                                   SearchUserAndAsset(searchUser: searchUser2, legacyID: assetID2))
        XCTAssertEqual(userIDsTable.allUsersWithAssets(), expectedAssetIDs)
        XCTAssertEqual(userIDsTable.allUserIds().count, 0)
    }

    func testThatCompletingARequestSetsTheAssetIDForThoseUsersOnTheTable_AssetKeys() {
        // Given
        let searchUsers = Array(setupSearchDirectory(userCount: 2))
        let searchUser1 = searchUsers.first!
        let searchUser2 = searchUsers.last!

        let assetKey1 = "asset-key-1", assetKey2 = "asset-key-2"

        let payload = [
            userData(previewAssetKey: assetKey1, for: searchUser1.remoteIdentifier!),
            userData(previewAssetKey: assetKey2, for: searchUser2.remoteIdentifier!)
        ]

        let response = ZMTransportResponse(payload: payload as ZMTransportData, httpStatus: 200, transportSessionError: nil)

        // When
        guard let request = sut.nextRequest() else { return XCTFail() }
        request.complete(with: response)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))

        // Then
        let expectedAssetIDs = Set(arrayLiteral:
            SearchUserAndAsset(searchUser: searchUser1, assetKey: assetKey1),
            SearchUserAndAsset(searchUser: searchUser2, assetKey: assetKey2)
        )

        XCTAssertEqual(userIDsTable.allUsersWithAssets(), expectedAssetIDs)
        XCTAssertEqual(userIDsTable.allUserIds().count, 0)
    }

    func testThatCompletingARequestSetsTheAssetIDForThoseUsersOnTheTable_MixedAssetKeysAndLegacy() {
        // Given
        let users = Array(setupSearchDirectory(userCount: 3))
        let user1 = users[0], user2 = users[1], user3 = users[2]
        let assetKey1 = "asset-key-1", assetKey2 = "asset-key-2"
        let legacyId1 = UUID.create(), legacyId2 = UUID.create()

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
        let expectedWithKeys = Set([
            SearchUserAndAsset(searchUser: user1, assetKey: assetKey1),
            SearchUserAndAsset(searchUser: user2, assetKey: assetKey2)
        ])

        let expectedWithLegacyId = Set([SearchUserAndAsset(searchUser: user3, legacyID: legacyId2)])

        XCTAssertEqual(userIDsTable.allUsersWithAssets(), expectedWithKeys.union(expectedWithLegacyId))
        XCTAssertEqual(userIDsTable.allUsersWithAssetKeys(), expectedWithKeys)
        XCTAssertEqual(userIDsTable.allUsersWithLegacyIds(), expectedWithLegacyId)
        XCTAssertEqual(userIDsTable.allUserIds().count, 0)
    }

    func testThatCompletingARequestWithoutLegacyIDDeletesTheUserFromTheTable() {
        let user = setupSearchDirectory(userCount: 1).first!
        let payload = [[ "id" : user.remoteIdentifier!.transportString(), "picture" : [] ]]
        verifyThatCompletingAreRequestDeletesUserFromTheTable(with: payload)
    }

    func testThatCompletingARequestWithoutAssetKeyDeletesTheUserFromTheTable() {
        let user = setupSearchDirectory(userCount: 1).first!
        let payload = [[ "id" : user.remoteIdentifier!.transportString(), "assets" : [] ]]
        verifyThatCompletingAreRequestDeletesUserFromTheTable(with: payload)
    }

    func testThatCompletingARequestWithoutLegacyIDAndAssetKeyDeletesTheUserFromTheTable() {
        let user = setupSearchDirectory(userCount: 1).first!
        let payload = [[ "id" : user.remoteIdentifier!.transportString(), "assets" : [], "pictures": []]]
        verifyThatCompletingAreRequestDeletesUserFromTheTable(with: payload)
    }

    func verifyThatCompletingAreRequestDeletesUserFromTheTable(with payload: [[String: Any]], file: StaticString = #file, line: UInt = #line) {
        // given
        let response = ZMTransportResponse(payload: payload as ZMTransportData, httpStatus: 200, transportSessionError: nil)

        // when
        guard let request = sut.nextRequest() else { return XCTFail("No request generated", file: file, line: line) }
        request.complete(with: response)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5), file: file, line: line)

        // then
        XCTAssertEqual(userIDsTable.allUserIds().count, 0, file: file, line: line)
        XCTAssertEqual(userIDsTable.allUsersWithAssets().count, 0, file: file, line: line)
    }

    func testThatFailingARequestWithAPermanentErrorRemovesTheUsersFromTheTable() {
        // given
        _ = setupSearchDirectory(userCount: 2)
        let response = ZMTransportResponse(payload: nil, httpStatus: 400, transportSessionError: nil)
        
        // when
        guard let request = sut.nextRequest() else { return XCTFail() }
        request.complete(with: response)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertEqual(userIDsTable.allUserIds().count, 0)
    }
    
    func testThatFailingARequestWithATemporaryErrorAllowsForThoseUserIDsToBeDownloadedAgain() {
        // given
        let searchUsers = setupSearchDirectory(userCount: 2)
        let response = ZMTransportResponse(payload: nil, httpStatus: 500, transportSessionError: nil)
        
        // when
        guard let request1 = sut.nextRequest() else { return XCTFail() }
        request1.complete(with: response)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertEqual(userIDsTable.allUserIds().count, 2)
        
        // and when
        guard let request2 = sut.nextRequest() else { return XCTFail() }
        let expectedUserIDs = userIDs(from: searchUsers)
        XCTAssertEqual(userIDs(in:request2), expectedUserIDs)
    }
    
    func testThatCompletingARequestDoesNotAllowForThoseUserIDsToBeDownloadedAgain() {
        // given
        let searchUsers = Array(setupSearchDirectory(userCount: 2))

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

    func testThatItCachesTheMediumAssetIDWhenDownloadingUserInfo_LegacyId() {
        // given
        let searchUser = setupSearchDirectory(userCount: 1).first!
        let legacyId = UUID()
        let payload = [userData(smallProfilePictureID:nil, mediumPictureID: legacyId, for: searchUser.remoteIdentifier!)]
        let response = ZMTransportResponse(payload: payload as ZMTransportData, httpStatus: 200, transportSessionError: nil)
        
        // when
        guard let request = sut.nextRequest() else { return XCTFail() }
        request.complete(with: response)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        let asset = assetIDCache.object(forKey: searchUser.remoteIdentifier! as NSUUID)?.internalAsset
        XCTAssertEqual(asset, .legacyId(legacyId))
    }

    func testThatItCachesTheMediumAssetIDWhenDownloadingUserInfo_AssetKey() {
        // given
        let user = setupSearchDirectory(userCount: 1).first!
        let assetKey = "asset-key", completeAssetKey = "complete-asset-key"
        let payload = [userData(previewAssetKey: assetKey, completeAssetKey: completeAssetKey, for: user.remoteIdentifier!)]
        let response = ZMTransportResponse(payload: payload as ZMTransportData, httpStatus: 200, transportSessionError: nil)

        // when
        guard let request = sut.nextRequest() else { return XCTFail() }
        request.complete(with: response)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))

        // then
        let asset = assetIDCache.object(forKey: user.remoteIdentifier! as NSUUID)?.internalAsset
        XCTAssertEqual(asset, .assetKey(completeAssetKey))
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
        userIDsTable.replaceUserId(searchUser.remoteIdentifier!, withAsset: .legacyId(assetID))
        
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
        userIDsTable.replaceUserId(searchUser.remoteIdentifier!, withAsset: .legacyId(UUID()))
        
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

        userIDsTable.replaceUserId(searchUser1.remoteIdentifier!, withAsset: .legacyId(assetID1))
        userIDsTable.replaceUserId(searchUser2.remoteIdentifier!, withAsset: .legacyId(assetID2))
        
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
    
    
    func testThatCompletingARequestSetsTheImageDataOnTheCache() {
        // given
        let imageData = verySmallJPEGData()
        let searchUser1 = setupSearchDirectory(userCount: 1).first!
        let assetID1 = UUID()
        userIDsTable.replaceUserId(searchUser1.remoteIdentifier!, withAsset: .legacyId(assetID1))
        
        let response = ZMTransportResponse(imageData: imageData, httpStatus: 200, transportSessionError: nil, headers: nil)
        
        // when
        guard let request = sut.nextRequest() else { return XCTFail() }
        XCTAssertEqual(request.path, requestPath(for:assetID1, of:searchUser1.remoteIdentifier!));

        request.complete(with: response)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertNotNil(imagesCache.object(forKey: (searchUser1.remoteIdentifier!) as NSUUID))
        XCTAssertEqual(imagesCache.object(forKey: (searchUser1.remoteIdentifier!) as NSUUID), imageData as NSData)
    }
    
    func testThatCompletingARequestRemovesTheUserFromTheTable() {
        // given
        let imageData = verySmallJPEGData()
        let searchUser1 = setupSearchDirectory(userCount: 1).first!
        let assetID1 = UUID()
        userIDsTable.replaceUserId(searchUser1.remoteIdentifier!, withAsset: .legacyId(assetID1))
        
        let response = ZMTransportResponse(imageData: imageData, httpStatus: 200, transportSessionError: nil, headers: nil)
        
        // when
        guard let request = sut.nextRequest() else { return XCTFail() }
        XCTAssertEqual(request.path, requestPath(for:assetID1, of:searchUser1.remoteIdentifier!));
        
        request.complete(with: response)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertEqual(userIDsTable.allUserIds().count, 0)
        XCTAssertEqual(userIDsTable.allUsersWithAssets().count, 0)
    }
    
    func testThatCompletingARequestDoesNotAllowForThoseAssetIDsToBeDownloadedAgain() {
        // given
        let imageData = verySmallJPEGData()
        let searchUser1 = createSearchUser()
        let fakeDirectory = FakeSearchDirectory()
        userIDsTable.setUsers([searchUser1], forDirectory: fakeDirectory)

        let assetID1 = UUID()
        userIDsTable.replaceUserId(searchUser1.remoteIdentifier!, withAsset: .legacyId(assetID1))
        
        let response = ZMTransportResponse(imageData: imageData, httpStatus: 200, transportSessionError: nil, headers: nil)
        
        // when
        guard let request = sut.nextRequest() else { return XCTFail() }
        XCTAssertEqual(request.path, requestPath(for:assetID1, of:searchUser1.remoteIdentifier!));
        
        request.complete(with: response)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // and when
        let request2 = sut.nextRequest()
        
        // then
        XCTAssertNil(request2)
    }
    
    func testThatFailingAnAssetRequestWithAPermanentErrorRemovesTheUsersFromTheTable() {
        // given
        let searchUser1 = setupSearchDirectory(userCount: 1).first!
        let assetID1 = UUID()
        userIDsTable.replaceUserId(searchUser1.remoteIdentifier!, withAsset: .legacyId(assetID1))
        let response = ZMTransportResponse(payload: nil, httpStatus: 400, transportSessionError: nil)
        
        // when
        guard let request = sut.nextRequest() else { return XCTFail() }
        XCTAssertEqual(request.path, requestPath(for:assetID1, of:searchUser1.remoteIdentifier!));
        
        request.complete(with: response)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertEqual(userIDsTable.allUserIds().count, 0)
        XCTAssertEqual(userIDsTable.allUsersWithAssets().count, 0)
    }
    
    func testThatFailingARequestWithATemporaryErrorAllowsForThoseAssetIDsToBeDownloadedAgain() {
        // given
        let searchUser1 = setupSearchDirectory(userCount: 1).first!
        let assetID1 = UUID()
        userIDsTable.replaceUserId(searchUser1.remoteIdentifier!, withAsset: .legacyId(assetID1))
        
        let response = ZMTransportResponse(payload: nil, httpStatus: 500, transportSessionError: nil)
        
        // when
        guard let request1 = sut.nextRequest() else { return XCTFail() }
        XCTAssertEqual(request1.path, requestPath(for:assetID1, of:searchUser1.remoteIdentifier!));
        
        request1.complete(with: response)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // and when
        userIDsTable.setUsers([searchUser1], forDirectory: FakeSearchDirectory())
        userIDsTable.replaceUserId(searchUser1.remoteIdentifier!, withAsset: .legacyId(assetID1))
        guard let request2 = sut.nextRequest() else { return XCTFail() }
        
        // then
        XCTAssertEqual(request2.path, requestPath(for:assetID1, of:searchUser1.remoteIdentifier!));
    }
    
    func testThatFailingARequestWithAPermanentErrorAllowsForThoseAssetIDsToBeDownloadedAgain() {
        // given
        let searchUser1 = setupSearchDirectory(userCount: 1).first!
        let assetID1 = UUID()
        userIDsTable.replaceUserId(searchUser1.remoteIdentifier!, withAsset: .legacyId(assetID1))
    
        let response = ZMTransportResponse(payload: nil, httpStatus: 404, transportSessionError: nil)

        // when
        guard let request1 = sut.nextRequest() else { return XCTFail() }
        XCTAssertEqual(request1.path, requestPath(for:assetID1, of:searchUser1.remoteIdentifier!));
        
        request1.complete(with: response)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // and when
        userIDsTable.setUsers([searchUser1], forDirectory: FakeSearchDirectory())
        userIDsTable.replaceUserId(searchUser1.remoteIdentifier!, withAsset: .legacyId(assetID1))
        guard let request2 = sut.nextRequest() else { return XCTFail() }
        
        // then
        XCTAssertEqual(request2.path, requestPath(for:assetID1, of:searchUser1.remoteIdentifier!));
    }
    
    func testThatItNotifiesTheSearchUserWhenAnImageIsDownloaded() {
        // given
        let imageData = verySmallJPEGData()
        let searchUser1 = setupSearchDirectory(userCount: 1).first!
        let assetID1 = UUID()
        userIDsTable.replaceUserId(searchUser1.remoteIdentifier!, withAsset: .legacyId(assetID1))
        
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

}


