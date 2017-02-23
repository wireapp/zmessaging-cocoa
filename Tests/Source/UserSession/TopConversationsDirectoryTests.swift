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

class TopConversationsDirectoryTests : MessagingTest {

    var sut : TopConversationsDirectory!
    var topConversationsObserver: FakeTopConversationsDirectoryObserver!
    var topConversationsObserverToken: TopConversationsDirectoryObserverToken!
    
    override func setUp() {
        super.setUp()
        self.sut = TopConversationsDirectory(managedObjectContext: self.uiMOC)
        self.topConversationsObserver = FakeTopConversationsDirectoryObserver()
        self.topConversationsObserverToken = self.sut.add(observer: topConversationsObserver)
    }
    
    override func tearDown() {
        self.sut.removeObserver(with: self.topConversationsObserverToken)
        self.sut = nil
        super.tearDown()
    }
    
    func testThatItHasNoResultsWhenCreatedAndNeverFetched() {
        XCTAssertEqual(self.sut.topConversations, [])
    }
    
    func testThatItSetsTheFetchedTopConversations() {
        // GIVEN
        let conv1 = createConversation(in: uiMOC, fillWithNew: 5)
        let conv2 = createConversation(in: uiMOC, fillWithNew: 15)
        let conv3 = createConversation(in: uiMOC, fillWithNew: 2)

        // WHEN
        sut.refreshTopConversations()
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.2))
        
        // THEN
        XCTAssertEqual(sut.topConversations, [conv2, conv1, conv3])
    }

    func testThatOnlyOneOnOneConversationsAreIncluded() {
        // GIVEN
        let conv1 = createConversation(in: uiMOC, fillWithNew: 5)
        let conv2 = createConversation(in: uiMOC, fillWithNew: 15)
        let conv3 = createConversation(in: uiMOC, fillWithNew: 2)

        let user1 = ZMUser.insertNewObject(in: uiMOC), user2 = ZMUser.insertNewObject(in: uiMOC)
        user1.remoteIdentifier = .create()
        user2.remoteIdentifier = .create()
        let groupConv = ZMConversation.insertGroupConversation(into: uiMOC, withParticipants: [user1, user2])
        groupConv?.remoteIdentifier = .create()

        // WHEN
        sut.refreshTopConversations()
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.2))

        // THEN
        XCTAssertEqual(sut.topConversations, [conv2, conv1, conv3])
    }

    func testThatItDoesNotConsiderMessagesOlderThanOneMonthInTheSorting() {
        // GIVEN
        let conv1 = createConversation(in: uiMOC, fillWithNew: 5, old: 15)
        let conv2 = createConversation(in: uiMOC, fillWithNew: 10, old: 5)
        let conv3 = createConversation(in: uiMOC, fillWithNew: 2, old: 20)

        // WHEN
        sut.refreshTopConversations()
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.2))

        // THEN
        XCTAssertEqual(sut.topConversations, [conv2, conv1, conv3])
    }

    func testThatItUpdatesTheConversationsWhenRefreshIsCalledSubsequently() {
        // GIVEN
        let conv1 = createConversation(in: uiMOC, fillWithNew: 5, old: 15)
        let conv2 = createConversation(in: uiMOC, fillWithNew: 10, old: 5)
        let conv3 = createConversation(in: uiMOC, fillWithNew: 2, old: 20)

        // WHEN
        sut.refreshTopConversations()
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.2))

        // THEN
        XCTAssertEqual(sut.topConversations, [conv2, conv1, conv3])

        // WHEN
        fill(conv3, with: 10)
        sut.refreshTopConversations()
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.2))

        // THEN
    }
    
    func testThatItSetsTopConversationFromTheRightContext() {
        // GIVEN
        var expectedConversationsIds : [NSManagedObjectID] = []
        
        // WHEN
        let conv1 = self.createConversation(in: self.uiMOC, fillWithNew: 2)
        expectedConversationsIds.append(conv1.objectID)
        let conv2 = self.createConversation(in: self.uiMOC)
        expectedConversationsIds.append(conv2.objectID)

        sut.refreshTopConversations()
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.2))

        
        // THEN
        XCTAssertEqual(self.sut.topConversations.map { $0.objectID }, expectedConversationsIds)
        XCTAssertEqual(self.sut.topConversations.map { $0.managedObjectContext! }, [self.uiMOC, self.uiMOC])
    }
    
    func testThatItDoesNotReturnConversationsIfTheyAreDeleted() {
        
        // GIVEN
        let conv1 = self.createConversation(in: self.uiMOC)
        let conv2 = self.createConversation(in: self.uiMOC)

        // WHEN
        self.sut.refreshTopConversations()
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.2))
        self.uiMOC.delete(conv1)
        uiMOC.saveOrRollback()
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.2))
        
        // THEN
        XCTAssertEqual(self.sut.topConversations, [conv2])
    }
    
    func testThatItDoesNotReturnConversationsIfTheyAreBlocked() {
        
        // GIVEN
        let conv1 = self.createConversation(in: self.uiMOC)
        let conv2 = self.createConversation(in: self.uiMOC)
        
        // WHEN
        conv1.connection?.status = .blocked
        sut.refreshTopConversations()
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.2))
        
        // THEN
        XCTAssertEqual(self.sut.topConversations, [conv2])
    }
    
    func testThatItDoesPersistsResults() {
        
        // GIVEN
        createConversation(in: uiMOC)
        createConversation(in: uiMOC)
        createConversation(in: uiMOC)
        
        // WHEN
        self.sut.refreshTopConversations()
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.2))
        self.uiMOC.saveOrRollback()
        
        // THEN
        let sut2 = TopConversationsDirectory(managedObjectContext: self.uiMOC)
        XCTAssertEqual(sut2.topConversations, self.sut.topConversations)
    }

    func testThatItLimitsTheNumberOfResults() {
        // GIVEN
        for _ in 0...30 {
            createConversation(in: uiMOC)
        }

        // WHEN
        sut.refreshTopConversations()
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.2))

        // THEN
        XCTAssertEqual(sut.topConversations.count, 25)
    }
}

// MARK: - Observation
extension TopConversationsDirectoryTests {

    func testThatItDoesNotNotifyTheObserverIfTheTopConversationsDidNotChange() {

        // GIVEN
        XCTAssertEqual(topConversationsObserver.topConversationsDidChangeCallCount, 0)

        // WHEN
        sut.refreshTopConversations()

        // THEN
        XCTAssertEqual(topConversationsObserver.topConversationsDidChangeCallCount, 0)
    }

    func testThatItNotifiesTheObserverWhenTheTopConversationsDidChange() {

        // GIVEN
        XCTAssertEqual(topConversationsObserver.topConversationsDidChangeCallCount, 0)


        // WHEN
                sut.refreshTopConversations()
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.2))

        // THEN
        XCTAssertEqual(topConversationsObserver.topConversationsDidChangeCallCount, 1)
    }

    func testThatItNotifiesTheObserverWhenTheTopConversationsDidChangeSubsequentially() {

        // GIVEN
        XCTAssertEqual(topConversationsObserver.topConversationsDidChangeCallCount, 0)

        // WHEN
        sut.refreshTopConversations()
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.2))

        // THEN
        XCTAssertEqual(topConversationsObserver.topConversationsDidChangeCallCount, 1)

        // WHEN
        createConversation(in: uiMOC)
        createConversation(in: uiMOC)
        sut.refreshTopConversations()
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.2))

        // THEN
        XCTAssertEqual(topConversationsObserver.topConversationsDidChangeCallCount, 2)
    }

}

// MARK: - Helpers
extension TopConversationsDirectoryTests {

    @discardableResult
    func createConversation(
        in managedObjectContext: NSManagedObjectContext,
        fillWithNew new: Int = 0,
        old: Int = 0,
        file: StaticString = #file,
        line: UInt = #line
        ) -> ZMConversation {

        let conversation = ZMConversation.insertNewObject(in: managedObjectContext)
        conversation.remoteIdentifier = UUID.create()
        conversation.conversationType = .oneOnOne
        conversation.connection = ZMConnection.insertNewObject(in: managedObjectContext)
        conversation.connection?.status = .accepted
        fill(conversation, with: (new, old), file: file, line: line)
        managedObjectContext.saveOrRollback()
        return conversation
    }

    func fill(_ conversation: ZMConversation, with messageCount: Int, file: StaticString = #file, line: UInt = #line) {
        fill(conversation, with: (messageCount, 0), file: file, line: line)
    }

    func fill(_ conversation: ZMConversation, with messageCount: (new: Int, old: Int), file: StaticString = #file, line: UInt = #line) {
        guard messageCount.new > 0 || messageCount.old > 0 else { return }
        (0..<messageCount.new).forEach {
            _ = conversation.appendMessage(withText: "Message #\($0)")
        }

        (0..<messageCount.old).forEach {
            let message = conversation.appendMessage(withText: "Message #\($0)") as! ZMMessage
            message.serverTimestamp = Date(timeIntervalSince1970: TimeInterval($0 * 100))
        }

        XCTAssertTrue(uiMOC.saveOrRollback(), file: file, line: line)
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.2), file: file, line: line)
    }
}

class FakeTopConversationsDirectoryObserver: TopConversationsDirectoryObserver {

    var topConversationsDidChangeCallCount = 0

    func topConversationsDidChange() {
        topConversationsDidChangeCallCount += 1
    }

}
