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
@testable import zmessaging

class TopConversationsRequestStrategyTests : MessagingTest {
    
    var sut : zmessaging.TopConversationsRequestStrategy!
    
    var authenticationStatus : MockAuthenticationStatus!

    var conversationsDirectory : TopConversationsDirectory!
    
    override func setUp() {
        super.setUp()
        self.authenticationStatus = MockAuthenticationStatus()
        self.conversationsDirectory = TopConversationsDirectory(managedObjectContext: self.uiMOC)
        self.sut = TopConversationsRequestStrategy(managedObjectContext: self.uiMOC, authenticationStatus: self.authenticationStatus, conversationDirectory: self.conversationsDirectory)
    }
    
    override func tearDown() {
        self.sut = nil
        self.conversationsDirectory = nil
        self.authenticationStatus = nil
    }
}

extension TopConversationsRequestStrategyTests {
    
    func testThatItDoesNotCreateRequestOnStart() {
        XCTAssertNil(self.sut.nextRequest())
    }
    
    func testThatItCreatesRequestWhenNeedsToFetch() {
        
        // GIVEN
        self.conversationsDirectory.refreshTopConversations()
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.2))
        
        // WHEN
        let request = self.sut.nextRequest()
        
        // THEN
        XCTAssertEqual(request?.path, "/search/top?size=24")
        XCTAssertEqual(request?.methodAsString, "GET")
    }
    
    func testThatItDoesNotCreateRequestWhenNeedsToFetchUnauthenticated() {
        
        // GIVEN
        self.conversationsDirectory.refreshTopConversations()
        self.authenticationStatus.mockPhase = .unauthenticated
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.2))
        
        // WHEN
        let request = self.sut.nextRequest()
        
        // THEN
        XCTAssertNil(request)
    }
    
    func testThatItParsesTheResponseSettingTopConversations() {
        
        // GIVEN
        let user1 = self.createConversationWithUser()
        let user2 = self.createConversationWithUser()
        _ = self.createConversationWithUser()
        
        self.conversationsDirectory.refreshTopConversations()
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.2))
        
        let payload  = ["documents" : [
                ["id" : user1.remoteIdentifier!.transportString()],
                ["id" : user2.remoteIdentifier!.transportString()],
            ]
        ] as NSDictionary
        
        // WHEN
        let request = self.sut.nextRequest()
        request?.complete(with: ZMTransportResponse(payload: payload, httpStatus: 200, transportSessionError: nil))
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.2))
        
        // THEN
        let expectedConversations = [user1.connection!.conversation!, user2.connection!.conversation!]
        XCTAssertEqual(self.conversationsDirectory.topConversations, expectedConversations)
    }
}

// MARK: - Helper

private var userCounter = 0

extension TopConversationsRequestStrategyTests {
    
    func createConversationWithUser() -> ZMUser {
        userCounter += 1
        let user = ZMUser.insertNewObject(in: self.uiMOC)
        user.remoteIdentifier = UUID.create()
        user.name = "NAME\(userCounter)"
        let connection = ZMConnection.insertNewObject(in: self.uiMOC)
        user.connection = connection
        connection.status = .accepted
        let conversation = ZMConversation.insertNewObject(in: self.uiMOC)
        conversation.conversationType = .oneOnOne
        conversation.remoteIdentifier = UUID.create()
        conversation.connection = connection
        self.uiMOC.saveOrRollback()
        return user
    }
}
