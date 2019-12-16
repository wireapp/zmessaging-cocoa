//
// Wire
// Copyright (C) 2018 Wire Swiss GmbH
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
import WireSyncEngine

extension ZMUserSession {
    @discardableResult func insertUnreadDotGeneratingMessageMessage(in conversation: ZMConversation) -> ZMSystemMessage {
        let newTime = conversation.lastServerTimeStamp?.addingTimeInterval(5) ?? Date()
        
        let message = ZMSystemMessage(nonce: UUID(), managedObjectContext: self.managedObjectContext)
        message.serverTimestamp = newTime
        message.systemMessageType = .missedCall
        conversation.lastServerTimeStamp = message.serverTimestamp
        conversation.mutableMessages.add(message)
        return message
    }
    
    @discardableResult func insertConversationWithUnreadMessage() -> ZMConversation {
        let conversation = ZMConversation.insertGroupConversation(session: self, participants: [])!
        conversation.remoteIdentifier = UUID()
        
        self.insertUnreadDotGeneratingMessageMessage(in: conversation)
        // then
        XCTAssertNotNil(conversation.firstUnreadMessage)
        return conversation
    }
}

class ZMUserSessionSwiftTests: ZMUserSessionTestsBase {
  
    
    func testThatItMarksTheConversationsAsRead() throws {
        // given
        let conversationsRange: CountableClosedRange = 1...10
        
        let conversations: [ZMConversation] = conversationsRange.map { _ in
            return self.sut.insertConversationWithUnreadMessage()
        }

        try self.uiMOC.save()
        
        // when
        self.sut.markAllConversationsAsRead()
        
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.5))

        // then
        XCTAssertEqual(conversations.filter { $0.firstUnreadMessage != nil }.count, 0)
    }
}
