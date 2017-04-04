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

class VoiceChannelStateSnapshotTests : MessagingTest {

    private var conversation : ZMConversation!
    private var user1 : ZMUser!
    private var user2 : ZMUser!

    override func setUp() {
        super.setUp()
        
        user1 = ZMUser.insertNewObject(in: self.uiMOC)
        user1.name = "User 1"
        user1.remoteIdentifier = UUID()

        conversation = ZMConversation.insertNewObject(in: self.uiMOC)
        conversation.remoteIdentifier = UUID()
        conversation.internalAddParticipants(Set<ZMUser>(arrayLiteral:user1), isAuthoritative: true)
    }
    
    func testThatItDoesNotCreateASnapshotForAConversationWithNoActiveUsers(){
        // given
        conversation.conversationType = .oneOnOne

        // when
        let snapshot = VoiceChannelStateSnapshot(conversation: conversation)
        
        // then
        XCTAssertNil(snapshot)
    }
    
    func testThatItDoesNotCreateASnapshotForAConversationWithInvalidVoiceChannelState(){
        // given
        conversation.conversationType = .invalid
        
        // when
        let snapshot = VoiceChannelStateSnapshot(conversation: conversation)
        
        // then
        XCTAssertNil(snapshot)
    }
    
    func testThatItCreatesASnapshotForAConversationWithValidVoiceChannelState(){
        // given
        conversation.conversationType = .oneOnOne
        conversation.callDeviceIsActive = true

        // when
        let snapshot = VoiceChannelStateSnapshot(conversation: conversation)
        
        // then
        XCTAssertNotNil(snapshot)
    }
}
