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
@testable import WireSyncEngine


class SearchDirectoryUserIDTableTests: MessagingTest {

    var sut: SearchDirectoryUserIDTable!

    override func setUp() {
        super.setUp()
        sut = SearchDirectoryUserIDTable()
    }
    
    override func tearDown() {
        sut = nil
        super.tearDown()
    }

    func createSearchDirectory() -> NSObject {
        return UUID.create() as NSObject // We use a unique id in tests
    }

    func createSearchUser() -> ZMSearchUser {
        return ZMSearchUser(
            name: "foo",
            handle: "foo",
            accentColor: .brightOrange,
            remoteID: .create(),
            user: nil,
            syncManagedObjectContext: syncMOC,
            uiManagedObjectContext: uiMOC
        )
    }

    func extractIds(_ users: Set<ZMSearchUser>) -> Set<UUID> {
        return Set(users.compactMap { $0.remoteIdentifier })
    }

    func testThatItRetrievesAllUserIds() {
        // Given
        let directory1 = createSearchDirectory()
        let users1: Set<ZMSearchUser> = [createSearchUser(), createSearchUser()]
        let directory2 = createSearchDirectory()
        let users2: Set<ZMSearchUser> = [createSearchUser(), createSearchUser()]

        // When
        sut.setUsers(users1, forDirectory: directory1)
        sut.setUsers(users2, forDirectory: directory2)

        // Then
        XCTAssertEqual(sut.allUserIds(), extractIds(users1.union(users2)))
    }

    func testThatWhenAddingIDsForASearchResultTheyAreCopied() {
        // Given
        let directory = createSearchDirectory()
        var users: Set<ZMSearchUser> = [createSearchUser(), createSearchUser()]
        let expected = users

        // When
        sut.setUsers(users, forDirectory: directory)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.2))

        // This will check that it does a copy when inserting. It if is not copied, this will delete all IDs.
        users.removeAll()

        XCTAssertEqual(extractIds(expected), sut.allUserIds())
    }

    func testThatItReplacesUserIDsWithLegacyIDsAndAssetKeys() {
        // Given
        let user1 = createSearchUser(), user2 = createSearchUser(), user3 = createSearchUser(), user4 = createSearchUser()
        let legacyId1 = UUID.create(), legacyId2 = UUID.create()
        let assetKey = "asset-key"
        let directory = createSearchDirectory()

        sut.setUsers([user1, user2, user3, user4], forDirectory: directory)

        let expectedLegacyIds = Set([
            SearchUserAndAsset(searchUser: user1, legacyID: legacyId1),
            SearchUserAndAsset(searchUser: user3, legacyID: legacyId2)
        ])

        let expectedAssets = Set([SearchUserAndAsset(searchUser: user2, assetKey: assetKey)])

        // When
        sut.replaceUserId(user1.remoteIdentifier!, withAsset: .legacyId(legacyId1))
        sut.replaceUserId(user2.remoteIdentifier!, withAsset: .assetKey(assetKey))
        sut.replaceUserId(user3.remoteIdentifier!, withAsset: .legacyId(legacyId2))

        // Then
        XCTAssertEqual(sut.allUserIds(), [user4.remoteIdentifier!])
        XCTAssertEqual(sut.allUsersWithAssets(), expectedAssets.union(expectedLegacyIds))
        XCTAssertEqual(sut.allUsersWithLegacyIds(), expectedLegacyIds)
        XCTAssertEqual(sut.allUsersWithAssetKeys(), expectedAssets)
    }

    func testThatClearingRemovesAllItems() {
        // Given
        let user1 = createSearchUser(), user2 = createSearchUser(), user3 = createSearchUser()
        let directory = createSearchDirectory()

        sut.setUsers([user1, user2, user3], forDirectory: directory)

        // When
        sut.removeAllEntries(with: extractIds([user2, user3]))

        // Then
        XCTAssertEqual(sut.allUserIds().count, 1)
        XCTAssertEqual(sut.allUserIds(), [user1.remoteIdentifier!])
    }

    func testThatReAddingAUserIDDoesNotDeleteTheAssociatedAssetID() {
        // Given
        let user1 = createSearchUser(), user2 = createSearchUser(), user3 = createSearchUser()
        let legacyKey = UUID.create()
        let assetKey = "asset-key"
        let directory = createSearchDirectory()
        sut.setUsers([user1, user2, user3], forDirectory: directory)

        sut.replaceUserId(user1.remoteIdentifier!, withAsset: .legacyId(legacyKey))
        sut.replaceUserId(user2.remoteIdentifier!, withAsset: .assetKey(assetKey))

        // When
        sut.setUsers([user1, user2, user3], forDirectory: directory)

        // Then
        XCTAssertEqual(sut.allUsersWithAssets().count, 2)
        XCTAssertEqual(sut.allUsersWithAssetKeys().count, 1)
        XCTAssertEqual(sut.allUsersWithLegacyIds().count, 1)
        XCTAssertEqual(sut.allUserIds().count, 1)
    }

    func testThatItRemovesTheSearchDirectory() {
        // Given
        let user1 = createSearchUser(), user2 = createSearchUser()
        let directory = createSearchDirectory()
        sut.setUsers([user1, user2], forDirectory: directory)

        // When
        sut.removeDirectory(directory)

        // Then
        XCTAssertEqual(sut.allUserIds().count, 0)
        XCTAssertEqual(sut.allUsersWithAssetKeys().count, 0)
    }

}
