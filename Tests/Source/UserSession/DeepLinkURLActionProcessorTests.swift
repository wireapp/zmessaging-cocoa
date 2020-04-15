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

import Foundation
@testable import WireSyncEngine

class DeepLinkURLActionProcessorTests: DatabaseTest {

    var urlActionDelegate: MockURLActionDelegate!
    var showContentDelegate: MockShowContentDelegate!
    var sut: WireSyncEngine.DeepLinkURLActionProcessor!

    
    override func setUp() {
        super.setUp()
        
        urlActionDelegate = MockURLActionDelegate()
        showContentDelegate = MockShowContentDelegate()
        sut = WireSyncEngine.DeepLinkURLActionProcessor(contextProvider: contextDirectory!, showContentdelegate: showContentDelegate)
    }
    
    override func tearDown() {
        showContentDelegate = nil
        sut = nil
        
        super.tearDown()
    }
    
    // MARK: Tests
    
    func testThatItAsksForConversationToBeShown() {
        // given
        let conversationId = UUID()
        let action: URLAction = .openConversation(id: conversationId)
        let conversation = ZMConversation.insertNewObject(in: uiMOC)
        conversation.remoteIdentifier = conversationId
        
        // when
        sut.process(urlAction: action, delegate: urlActionDelegate)
        
        // then
        XCTAssertEqual(showContentDelegate.showConversationCalls.count, 1)
        XCTAssertEqual(showContentDelegate.showConversationCalls.first, conversation)
    }
    
    func testThatItReportsTheActionAsFailed_WhenTheConversationDoesntExist() {
        // given
        let conversationId = UUID()
        let action: URLAction = .openConversation(id: conversationId)
        
        // when
        sut.process(urlAction: action, delegate: urlActionDelegate)
        
        // then
        XCTAssertEqual(urlActionDelegate.failedToPerformActionCalls.count, 1)
        XCTAssertEqual(urlActionDelegate.failedToPerformActionCalls.first?.0, action)
        XCTAssertEqual(urlActionDelegate.failedToPerformActionCalls.first?.1 as? DeepLinkRequestError, .invalidConversationLink)
    }
    
    func testThatItAsksToShowUserProfile_WhenUserIsKnown() {
        // given
        let userId = UUID()
        let action: URLAction = .openUserProfile(id: userId)
        let user = ZMUser.insertNewObject(in: uiMOC)
        user.remoteIdentifier = userId
        
        // when
        sut.process(urlAction: action, delegate: urlActionDelegate)
        
        // then
        XCTAssertEqual(showContentDelegate.showUserProfileCalls.count, 1)
        XCTAssertEqual(showContentDelegate.showUserProfileCalls.first as? ZMUser, user)
    }
    
    func testThatItAsksToShowConnectionRequest_WhenUserIsUnknown() {
        // given
        let userId = UUID()
        let action: URLAction = .openUserProfile(id: userId)
        
        // when
        sut.process(urlAction: action, delegate: urlActionDelegate)
        
        // then
        XCTAssertEqual(showContentDelegate.showConnectionRequestCalls.count, 1)
        XCTAssertEqual(showContentDelegate.showConnectionRequestCalls.first, userId)
    }
    
}
