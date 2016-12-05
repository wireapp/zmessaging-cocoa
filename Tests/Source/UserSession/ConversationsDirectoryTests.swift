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
import XCTest
@testable import zmessaging

class ConversationsDirectoryTests : MessagingTest {

    var sut : ConversationsDirectory!
    
    var newRequestObserver : OperationLoopNewRequestObserver!
    
    override func setUp() {
        super.setUp()
        self.newRequestObserver = OperationLoopNewRequestObserver()
        self.sut = ConversationsDirectory(managedObjectContext: self.uiMOC)
    }
    
    override func tearDown() {
        self.sut = nil
        self.newRequestObserver = nil
        super.tearDown()
    }
    
    func testThatItIsNotFetchingWhenCreated() {
        XCTAssertFalse(self.sut.fetchingTopConversations)
        XCTAssertEqual(self.sut.topConversations, [])
    }
    
    func testThatItIsFetchingAfterRefreshing() {
        
        // WHEN
        self.sut.refreshTopConversations()
        
        // THEN
        XCTAssertTrue(self.sut.fetchingTopConversations)
        XCTAssertEqual(self.newRequestObserver.notifications.count, 1)
    }
    
    func testThatItIsNotFetchingAfterDownloading() {
        
        // GIVEN
        self.sut.refreshTopConversations()
        
        // WHEN
        self.sut.didDownloadTopConversations(conversations: [])
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.2))
        
        // THEN
        XCTAssertFalse(self.sut.fetchingTopConversations)
    }
    
    func testThatItSetsTheDownloadedTopConversations() {
        
        // GIVEN
        let conv1 = self.createConversation(in: self.uiMOC)
        let conv2 = self.createConversation(in: self.uiMOC)
        _ = self.createConversation(in: self.uiMOC)
        self.sut.refreshTopConversations()
        
        // WHEN
        self.sut.didDownloadTopConversations(conversations: [conv1, conv2])
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.2))
        
        // THEN
        XCTAssertEqual(self.sut.topConversations, [conv1, conv2])

    }
    
    func testThatItSetsTopConversationFromTheRightContext() {
        // GIVEN
        self.sut.refreshTopConversations()
        var expectedConversationsIds : [NSManagedObjectID] = []
        
        // WHEN
        self.syncMOC.performGroupedBlockAndWait {
            let conv1 = self.createConversation(in: self.uiMOC)
            expectedConversationsIds.append(conv1.objectID)
            let conv2 = self.createConversation(in: self.uiMOC)
            expectedConversationsIds.append(conv2.objectID)
            _ = self.createConversation(in: self.uiMOC)
            self.sut.didDownloadTopConversations(conversations: [conv1, conv2])
        }
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.2))
        
        // THEN
        XCTAssertEqual(self.sut.topConversations.map { $0.objectID }, expectedConversationsIds)
        XCTAssertEqual(self.sut.topConversations.map { $0.managedObjectContext! }, [self.uiMOC, self.uiMOC])
    }
    
    func testThatItDoesNotReturnConversationsIfTheyAreDeleted() {
        
        // GIVEN
        let conv1 = self.createConversation(in: self.uiMOC)
        let conv2 = self.createConversation(in: self.uiMOC)
        _ = self.createConversation(in: self.uiMOC)
        self.sut.refreshTopConversations()
        
        // WHEN
        self.sut.didDownloadTopConversations(conversations: [conv1, conv2])
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.2))
        self.uiMOC.delete(conv1)
        
        // THEN
        XCTAssertEqual(self.sut.topConversations, [conv2])
    }
    
    func testThatItDoesNotReturnConversationsIfTheyAreBlocked() {
        
        // GIVEN
        let conv1 = self.createConversation(in: self.uiMOC)
        let conv2 = self.createConversation(in: self.uiMOC)
        _ = self.createConversation(in: self.uiMOC)
        self.sut.refreshTopConversations()
        
        // WHEN
        self.sut.didDownloadTopConversations(conversations: [conv1, conv2])
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.2))
        conv1.connection?.status = .blocked
        
        // THEN
        XCTAssertEqual(self.sut.topConversations, [conv2])
    }
    
    func testThatItDoesPersistsResults() {
        
        // GIVEN
        let conv1 = self.createConversation(in: self.uiMOC)
        let conv2 = self.createConversation(in: self.uiMOC)
        _ = self.createConversation(in: self.uiMOC)
        self.sut.refreshTopConversations()
        
        // WHEN
        self.sut.didDownloadTopConversations(conversations: [conv1, conv2])
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.2))
        self.uiMOC.saveOrRollback()
        
        // THEN
        let sut2 = ConversationsDirectory(managedObjectContext: self.uiMOC)
        XCTAssertEqual(sut2.topConversations, self.sut.topConversations)
        
    }
}

// MARK: - Helpers
extension ConversationsDirectoryTests {
    
    func createConversation(in managedObjectContext: NSManagedObjectContext) -> ZMConversation {
        let conversation = ZMConversation.insertNewObject(in: managedObjectContext)
        conversation.remoteIdentifier = UUID.create()
        conversation.conversationType = .oneOnOne
        conversation.connection = ZMConnection.insertNewObject(in: managedObjectContext)
        conversation.connection?.status = .accepted
        managedObjectContext.saveOrRollback()
        return conversation
    }
}

