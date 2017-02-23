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

class ZMConversationVoiceChannelRouterTests : MessagingTest {
    
    private var oneToOneconversation : ZMConversation!
    private var groupConversation : ZMConversation!

    override func setUp() {
        super.setUp()
        
        ZMUserSession.callingProtocolStrategy = .version2
        
        oneToOneconversation = ZMConversation.insertNewObject(in: self.syncMOC)
        oneToOneconversation?.remoteIdentifier = UUID.create()
        oneToOneconversation.conversationType = .oneOnOne
        
        groupConversation = ZMConversation.insertNewObject(in: self.syncMOC)
        groupConversation?.remoteIdentifier = UUID.create()
        groupConversation.conversationType = .group
    }
    
    override func tearDown() {
        ZMUserSession.callingProtocolStrategy = .negotiate
        
        super.tearDown()
    }
    
    
    func testThatItReturnsAVoiceChannelRouterForAOneOnOneConversations() {
        // when
        let router = oneToOneconversation.voiceChannelRouter
        
        // then
        XCTAssertNotNil(router)
        XCTAssertEqual(router?.conversation, oneToOneconversation)
    }
    
    func testThatItReturnsAVoiceChannelRouterForAGroupConversation() {
        // when
        let router = groupConversation.voiceChannelRouter
        
        // then
        XCTAssertNotNil(router)
        XCTAssertEqual(router?.conversation, groupConversation)
    }
    
    func testThatItAlwaysReturnsTheSameVoiceChannelRouterForAOneOnOneConversations() {
        // when
        let router = oneToOneconversation.voiceChannelRouter
        
        // then
        XCTAssertEqual(oneToOneconversation.voiceChannelRouter, router)
    }
    
}
