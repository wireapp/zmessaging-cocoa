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

class SearchDirectoryTests : MessagingTest {
    
    func testThatWhenReceivingSearchUsersWeMarkTheProfileImageAsMissing() {
        // given
        let resultArrived = expectation(description: "received result")
        let request = SearchRequest(query: "User", searchOptions: [.directory])
        
        mockTransportSession.performRemoteChanges { (remoteChanges) in
            remoteChanges.insertUser(withName: "User A")
        }
        
        let sut = SearchDirectory(userSession: mockUserSession)
        
        // when
        let task = sut.perform(request)
        task.onResult { (result, _) in
            if !result.directory.isEmpty {
                resultArrived.fulfill()
            }
        }
        task.start()
        XCTAssertTrue(waitForCustomExpectations(withTimeout: 0.5))
        
        // then
        XCTAssertEqual(SearchDirectory.userIDsMissingProfileImage.allUserIds().count, 1)
        
        // cleanup
        sut.tearDown()
    }
    
    func testThatWhenReceivingSearchUsersWeDontMarkTheProfileImageAsMissingIfItExistsInCache() {
        // given
        let resultArrived = expectation(description: "received result")
        var userIdentifier1 : String = ""
        var userIdentifier2 : String = ""
        
        mockTransportSession.performRemoteChanges { (remoteChanges) in
            userIdentifier1 = remoteChanges.insertUser(withName: "User A").identifier
            userIdentifier2 = remoteChanges.insertUser(withName: "User B").identifier
        }
        
        let uuid1 = UUID(uuidString: userIdentifier1)!
        let uuid2 = UUID(uuidString: userIdentifier2)!
        let request = SearchRequest(query: "User", searchOptions: [.directory])
        
        ZMSearchUser.searchUserToMediumImageCache().setObject(Data(count: 1) as NSData, forKey: uuid1 as NSUUID)
        ZMSearchUser.searchUserToSmallProfileImageCache().setObject(Data(count: 1) as NSData, forKey: uuid1 as NSUUID)
        
        let sut = SearchDirectory(userSession: mockUserSession)
        
        // when
        let task = sut.perform(request)
        task.onResult { (result, _) in
            if !result.directory.isEmpty {
                resultArrived.fulfill()
            }
        }
        task.start()
        XCTAssertTrue(waitForCustomExpectations(withTimeout: 0.5))
        
        // then
        XCTAssertEqual(SearchDirectory.userIDsMissingProfileImage.allUserIds(), Set([uuid2]))
        
        // cleanup
        sut.tearDown()
    }
    
    func testThatWhenReceivingSearchUsersWeDontMarkTheProfileImageAsMissingIfThereIsACorrespondingZMUser() {
        // given
        let resultArrived = expectation(description: "received result")
        var userIdentifier1 : String = ""
        var userIdentifier2 : String = ""
        
        mockTransportSession.performRemoteChanges { (remoteChanges) in
            userIdentifier1 = remoteChanges.insertUser(withName: "User A").identifier
            userIdentifier2 = remoteChanges.insertUser(withName: "User B").identifier
        }
        
        let uuid1 = UUID(uuidString: userIdentifier1)!
        let uuid2 = UUID(uuidString: userIdentifier2)!
        let request = SearchRequest(query: "User", searchOptions: [.directory])
        
        let user1 = ZMUser.insertNewObject(in: uiMOC)
        user1.remoteIdentifier = uuid1
        uiMOC.saveOrRollback()
        
        let sut = SearchDirectory(userSession: mockUserSession)
        
        // when
        let task = sut.perform(request)
        task.onResult { (result, _) in
            if !result.directory.isEmpty {
                resultArrived.fulfill()
            }
        }
        task.start()
        XCTAssertTrue(waitForCustomExpectations(withTimeout: 0.5))
        
        // then
        XCTAssertEqual(SearchDirectory.userIDsMissingProfileImage.allUserIds(), Set([uuid2]))
        
        // cleanup
        sut.tearDown()
    }
    
    func testThatItEmptiesTheMediumImageCacheOnTeardown() {
        // given
        let uuid = UUID.create()
        let imageCache = ZMSearchUser.searchUserToMediumImageCache()
        let sut = SearchDirectory(userSession: mockUserSession)
        
        imageCache.setObject(Data(count: 1) as NSData, forKey: uuid as NSUUID)
        
        // when
        sut.tearDown()
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertNil(imageCache.object(forKey: uuid as NSUUID))
    }
    
    func testThatItRemovesItselfFromTheTableOnTearDown() {
        // given
        let sut = SearchDirectory(userSession: mockUserSession)
        let request = SearchRequest(query: "User", searchOptions: [.directory])
        
        mockTransportSession.performRemoteChanges { (remoteChanges) in
            remoteChanges.insertUser(withName: "User A")
        }
        
        sut.perform(request).start()
        spinMainQueue(withTimeout: 0.5)
        
        // when
        sut.tearDown()
        
        // then
        XCTAssertEqual(SearchDirectory.userIDsMissingProfileImage.allUserIds().count, 0)
    }
    
}
