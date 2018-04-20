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

import XCTest

class ConversationTests_Participants: ConversationTestsBase {
    
    func testThatAddingAndRemovingAParticipantToAConversationSendsOutChangeNotifications() {
        
        // given
        XCTAssert(login())
        
        let conversation = self.conversation(for: emptyGroupConversation)!
        let connectedUser = user(for: self.user2)!
        
        let observer = ConversationChangeObserver(conversation: conversation)
        observer?.clearNotifications()
        
        // when
        conversation.addParticipants(Set(arrayLiteral: connectedUser), userSession: userSession!, completion: { (_) in })
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then - Participants changes and messages changes (System message for the added user)
        
        XCTAssertEqual(observer?.notifications.count, 1)
        let note1 = observer?.notifications.firstObject as! ConversationChangeInfo
        XCTAssertEqual(note1.conversation, conversation)
        XCTAssertTrue(note1.participantsChanged)
        XCTAssertTrue(note1.messagesChanged)
        observer?.notifications.removeAllObjects()
        
        // when
        conversation.removeParticipant(connectedUser, userSession: userSession!, completion: { (_) in })
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then - Participants changes and messages changes (System message for the removed user)
        XCTAssertEqual(observer?.notifications.count, 1)
        let note2 = observer?.notifications.firstObject as! ConversationChangeInfo
        XCTAssertEqual(note2.conversation, conversation)
        XCTAssertTrue(note2.participantsChanged)
        XCTAssertTrue(note2.messagesChanged)
        
        observer?.notifications.removeAllObjects()
    }
    
    func testThatWhenLeavingAConversationWeSetAndSynchronizeTheLastReadServerTimestamp() {
        
        // given
        XCTAssert(login())
        
        let conversation = self.conversation(for: groupConversation)!
        let selfUser = user(for: self.selfUser)!
        
        mockTransportSession.resetReceivedRequests()
        
        let lastReadPath = "/conversations/\(selfUser.remoteIdentifier!.transportString())/otr/messages"
        let memberLeavePath = "/conversations/\(conversation.remoteIdentifier!.transportString())/members/\(selfUser.remoteIdentifier!.transportString())"
        let archivedPath = "/conversations/\(conversation.remoteIdentifier!.transportString())/self"
        
        var didSendLastReadMessage = false
        var didSendMemberLeaveRequest = false
        var didSendArchivedMessage = false
        var archivedRef: Date? = nil
        var isArchived: Bool?
        
        mockTransportSession.responseGeneratorBlock = { request in
            switch (request.path, request.method) {
            case (lastReadPath, ZMTransportRequestMethod.methodPOST):
                didSendLastReadMessage = true
            case (memberLeavePath, ZMTransportRequestMethod.methodDELETE):
                didSendMemberLeaveRequest = true
            case (archivedPath, ZMTransportRequestMethod.methodPUT):
                didSendArchivedMessage = true
                archivedRef = (request.payload as? NSDictionary)?.date(forKey: "otr_archived_ref")
                isArchived = request.payload?.asDictionary()?["otr_archived"] as? Bool
            default: break
            }
            
            return nil
        }
        
        // when
        conversation.removeParticipant(selfUser, userSession: userSession!, completion: { _ in })
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertNotNil(conversation.lastReadServerTimeStamp);
        XCTAssertTrue(didSendArchivedMessage)
        XCTAssertTrue(didSendLastReadMessage)
        XCTAssertTrue(didSendMemberLeaveRequest)
        XCTAssertTrue(isArchived ?? false)
        XCTAssertEqual(archivedRef, conversation.lastServerTimeStamp);
        XCTAssertEqual(archivedRef, conversation.lastReadServerTimeStamp);
        
        // given
        let unreadCount = conversation.estimatedUnreadCount;
        
        // when - logging in and out again lastRead is still set
        recreateSessionManagerAndDeleteLocalData()
        XCTAssertTrue(login());
        
        // then
        XCTAssertEqual(self.conversation(for: groupConversation)!.estimatedUnreadCount, unreadCount);
    }
    
    func testThatAddingParticipantsToAConversationIsSynchronizedWithBackend() {
        // given
        XCTAssert(login())
        
        let conversation = self.conversation(for: emptyGroupConversation)!
        let connectedUser = user(for: self.user2)!
        
        XCTAssertFalse(conversation.activeParticipants.contains(connectedUser))
        
        // when
        conversation.addParticipants(Set(arrayLiteral: connectedUser), userSession: userSession!, completion: { (_) in })
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertTrue(conversation.activeParticipants.contains(connectedUser))
        
        // Tear down & recreate contexts
        recreateSessionManagerAndDeleteLocalData()
        XCTAssertTrue(login())
        
        // then
        XCTAssertTrue(self.conversation(for: emptyGroupConversation)!.activeParticipants.contains(user(for: self.user2)!))
    }
    
    func testThatRemovingParticipantsFromAConversationIsSynchronizedWithBackend() {
        // given
        XCTAssert(login())
        
        let conversation = self.conversation(for: groupConversation)!
        let connectedUser = user(for: self.user2)!
        
        XCTAssertTrue(conversation.activeParticipants.contains(connectedUser))
        
        // when
        conversation.removeParticipant(connectedUser, userSession: userSession!, completion: { (_) in })
        XCTAssertTrue( waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertFalse(conversation.activeParticipants.contains(connectedUser))
        
        // Tear down & recreate contexts
        recreateSessionManagerAndDeleteLocalData()
        XCTAssertTrue(login())
        
        // then
        XCTAssertFalse(self.conversation(for: groupConversation)!.activeParticipants.contains(user(for: self.user2)!))
    }
    
}
