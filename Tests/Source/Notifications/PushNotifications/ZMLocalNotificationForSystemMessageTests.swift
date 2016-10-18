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

import ZMTesting;
@testable import zmessaging

class ZMLocalNotificationForSystemMessageTests : ZMLocalNotificationForEventTest {
    
    
    func testThatItCreatesANotificationForConversationRename(){
        // given
        let systemMessage = ZMSystemMessage.insertNewObject(in: syncMOC)
        systemMessage.systemMessageType = .conversationNameChanged
        systemMessage.text = "New Name"
        systemMessage.sender = sender
        systemMessage.visibleInConversation = groupConversation
        
        // when
        let note = ZMLocalNotificationForSystemMessage(message: systemMessage, application: application)
        
        // then
        XCTAssertNotNil(note)
        guard let uiNote = note?.uiNotifications.first else { return XCTFail() }
        XCTAssertEqual(uiNote.alertBody, "Super User renamed a conversation to New Name")
    }
    
    func alertBodyForParticipantAdded(_ conversation: ZMConversation, aSender: ZMUser, otherUsers: Set<ZMUser>) -> String?{
        // given
        let systemMessage = ZMSystemMessage.insertNewObject(in: syncMOC)
        systemMessage.systemMessageType = .participantsAdded
        systemMessage.addedUsers = otherUsers
        systemMessage.sender = aSender
        systemMessage.visibleInConversation = conversation
        
        // when
        let note = ZMLocalNotificationForSystemMessage(message: systemMessage, application: application)
        
        // then
        guard let uiNote = note?.uiNotifications.first else { return nil }
        return uiNote.alertBody
    }
    
    func testThatItCreatesANotificationForParticipantAdd(){
        
        //    "push.notification.member.join.self" = "%1$@ added you to %2$@";
        //    "push.notification.member.join.self.noconversationname" = "%1$@ added you to a conversation";
        //
        //    "push.notification.member.join" = "%1$@ added %3$@ to %2$@";
        //    "push.notification.member.join.noconversationname" = "%1$@ added %2$@ to a conversation";
        //
        //    "push.notification.member.join.many.nootherusername" = "%1$@ added people to %2$@";
        //    "push.notification.member.join.many.nootherusername.noconversationname" = "%1$@ added people to a conversation";
        //
        //    "push.notification.member.join.nootherusername" = "%1$@ added people to %2$@";
        //    "push.notification.member.join.nootherusername.noconversationname" = "%1$@ added people to a conversation";
        
        XCTAssertEqual(alertBodyForParticipantAdded(groupConversation, aSender: sender, otherUsers: Set(arrayLiteral: otherUser)), "Super User added Other User to Super Conversation")
        XCTAssertEqual(alertBodyForParticipantAdded(groupConversation, aSender: sender, otherUsers: Set(arrayLiteral: selfUser)), "Super User added you to Super Conversation")
        XCTAssertEqual(alertBodyForParticipantAdded(groupConversation, aSender: sender, otherUsers: Set(arrayLiteral: otherUser, otherUser2)), "Super User added people to Super Conversation")
        
        XCTAssertEqual(alertBodyForParticipantAdded(groupConversationWithoutName, aSender: sender, otherUsers: Set(arrayLiteral: otherUser)), "Super User added Other User to a conversation")
        XCTAssertEqual(alertBodyForParticipantAdded(groupConversationWithoutName, aSender: sender, otherUsers: Set(arrayLiteral: selfUser)), "Super User added you to a conversation")
        XCTAssertEqual(alertBodyForParticipantAdded(groupConversationWithoutName, aSender: sender, otherUsers: Set(arrayLiteral: otherUser, otherUser2)), "Super User added people to a conversation")
    }
    
    func alertBodyForParticipantRemoved(_ conversation: ZMConversation, aSender: ZMUser, otherUsers: Set<ZMUser>) -> String?{
        // given
        let systemMessage = ZMSystemMessage.insertNewObject(in: syncMOC)
        systemMessage.systemMessageType = .participantsRemoved
        systemMessage.removedUsers = otherUsers
        systemMessage.sender = aSender
        systemMessage.visibleInConversation = conversation
        
        // when
        let note = ZMLocalNotificationForSystemMessage(message: systemMessage, application: application)
        
        // then
        guard let uiNote = note?.uiNotifications.first else { return nil }
        return uiNote.alertBody
    }
    
    func testThatItDoesNotCreateANotificationWhenTheUserLeaves(){
        // given
        let systemMessage = ZMSystemMessage.insertNewObject(in: syncMOC)
        systemMessage.systemMessageType = .participantsRemoved
        systemMessage.removedUsers = [otherUser]
        systemMessage.sender = otherUser
        systemMessage.visibleInConversation = groupConversation
        
        // when
        let note = ZMLocalNotificationForSystemMessage(message: systemMessage, application: application)

        // then
        XCTAssertNil(note)
    }
    
    func testThatItCreatesANotificationForParticipantRemoved(){
        
        //    "push.notification.member.leave.self" = "%1$@ removed you from %2$@";
        //    "push.notification.member.leave.self.noconversationname" = "%1$@ removed you from a conversation";
        //
        //    "push.notification.member.leave" = "%1$@ removed %3$@ from %2$@";
        //    "push.notification.member.leave.noconversationname" = "%1$@ removed %2$@ from a conversation";
        //
        //    "push.notification.member.leave.nootherusername" = "%1$@ removed people from %2$@";
        //    "push.notification.member.leave.nootherusername.noconversationname" = "%1$@ removed people from a conversation";
        //
        //    "push.notification.member.leave.sender.nootherusername" = "%1$@ left %2$@";
        //    "push.notification.member.leave.sender.nootherusername.noconversationname" = "%1$@ left a conversation";
        //
        //    "push.notification.member.leave.many.nootherusername" = "%1$@ removed people from %2$@";
        //    "push.notification.member.leave.many.nootherusername.noconversationname" = "%1$@ removed people from a conversation";
        
        XCTAssertEqual(alertBodyForParticipantRemoved(groupConversation, aSender: sender, otherUsers: Set(arrayLiteral: otherUser)), "Super User removed Other User from Super Conversation")
        XCTAssertEqual(alertBodyForParticipantRemoved(groupConversation, aSender: sender, otherUsers: Set(arrayLiteral: selfUser)), "Super User removed you from Super Conversation")
        XCTAssertEqual(alertBodyForParticipantRemoved(groupConversation, aSender: sender, otherUsers: Set(arrayLiteral: otherUser, otherUser2)), "Super User removed people from Super Conversation")
        
        XCTAssertEqual(alertBodyForParticipantRemoved(groupConversationWithoutName, aSender: sender, otherUsers: Set(arrayLiteral: otherUser)), "Super User removed Other User from a conversation")
        XCTAssertEqual(alertBodyForParticipantRemoved(groupConversationWithoutName, aSender: sender, otherUsers: Set(arrayLiteral: selfUser)), "Super User removed you from a conversation")
        XCTAssertEqual(alertBodyForParticipantRemoved(groupConversationWithoutName, aSender: sender, otherUsers: Set(arrayLiteral: otherUser, otherUser2)), "Super User removed people from a conversation")
    }

    func testThatItCreatesANotificationForConnectionRequest(){
        
        // given
        let systemMessage = ZMSystemMessage.insertNewObject(in: syncMOC)
        systemMessage.systemMessageType = .connectionRequest
        systemMessage.sender = sender
        systemMessage.text = "Special User"
        
        // when
        let note = ZMLocalNotificationForSystemMessage(message: systemMessage, application: application)
        
        // then
        guard let uiNote = note?.uiNotifications.first else { return XCTFail() }
        XCTAssertEqual(uiNote.alertBody, "Special User wants to connect")
    }
}




            

                

                

                        

