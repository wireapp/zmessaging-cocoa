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

import ZMTesting
@testable import zmessaging

class ZMLocalNotificationForEventsTests_Reactions : ZMLocalNotificationForEventTest {
}

extension ZMLocalNotificationForEventsTests_Reactions {
    
    func createUpdateEvent(_ nonce: UUID, conversationID: UUID, genericMessage: ZMGenericMessage, senderID: UUID = UUID.create()) -> ZMUpdateEvent {
        let payload : [String : Any] = [
            "id": UUID.create().transportString(),
            "conversation": conversationID.transportString(),
            "from": senderID.transportString(),
            "time": Date().transportString(),
            "data": [
                "text": genericMessage.data().base64String()
            ],
            "type": "conversation.otr-message-add"
        ]
        
        return ZMUpdateEvent(fromEventStreamPayload: payload as ZMTransportData, uuid: nonce)!
    }

    func eventInOneOnOneConversation() -> ZMUpdateEvent {
        let message = oneOnOneConversation.appendMessage(withText: "text") as! ZMClientMessage
        let reaction = ZMGenericMessage(emojiString: "❤️", messageID: message.nonce.transportString(), nonce: UUID.create().transportString())
        let event = createUpdateEvent(UUID.create(), conversationID: oneOnOneConversation.remoteIdentifier!, genericMessage: reaction, senderID: sender.remoteIdentifier!)
        return event
    }
    
    func testThatItCreatesANotifcationForAReaction_SelfUserIsSenderOfOriginalMessage_OtherUserSendsLike(){
        // given
        let event = eventInOneOnOneConversation()
        
        // when
        let sut = ZMLocalNotificationForReaction(events: [event], conversation: oneOnOneConversation, managedObjectContext: syncMOC, application: nil)
        
        // then
        XCTAssertNotNil(sut)
        
        guard let localNote = sut?.uiNotifications.first else {return XCTFail()}
        XCTAssertEqual(localNote.alertBody, "Super User ❤️ your message")
    }
    
    func testThatItDoesNotCreateANotifcationWhenTheConversationIsSilenced(){
        // given
        oneOnOneConversation.isSilenced = true
        let event = eventInOneOnOneConversation()
        
        // when
        let sut = ZMLocalNotificationForReaction(events: [event], conversation: oneOnOneConversation, managedObjectContext: syncMOC, application: nil)
        
        // then
        XCTAssertNil(sut)
    }
    
    func testThatItSavesTheSenderOfANotification() {
        // given
        let event = eventInOneOnOneConversation()
        
        // when
        let sut = ZMLocalNotificationForReaction(events: [event], conversation: oneOnOneConversation, managedObjectContext: syncMOC, application: nil)
        
        // then
        XCTAssertEqual(sut?.sender!.remoteIdentifier, sender.remoteIdentifier);
        XCTAssertEqual(sut?.uiNotifications.first?.zm_senderUUID, sender.remoteIdentifier);
    }
    
    
    func testThatItSavesTheConversationOfANotification() {
        // given
        let event = eventInOneOnOneConversation()
        
        // when
        let sut = ZMLocalNotificationForReaction(events: [event], conversation: oneOnOneConversation, managedObjectContext: syncMOC, application: nil)
        
        // then
        XCTAssertEqual(sut?.conversationID, oneOnOneConversation.remoteIdentifier);
        XCTAssertEqual(sut?.uiNotifications.first?.zm_conversationRemoteID, oneOnOneConversation.remoteIdentifier);
    }
    
    func testThatItSavesTheMessageNonce() {
        // given
        let message = oneOnOneConversation.appendMessage(withText: "text") as! ZMClientMessage
        let reaction = ZMGenericMessage(emojiString: "liked", messageID: message.nonce.transportString(), nonce: UUID.create().transportString())
        let event = createUpdateEvent(UUID.create(), conversationID: oneOnOneConversation.remoteIdentifier!, genericMessage: reaction, senderID: sender.remoteIdentifier!)
        
        // when
        let sut = ZMLocalNotificationForReaction(events: [event], conversation: oneOnOneConversation, managedObjectContext: syncMOC, application: nil)
        
        // then
        XCTAssertEqual(sut?.uiNotifications.first?.zm_messageNonce, message.nonce);
    }
}



extension ZMLocalNotificationForEventsTests_Reactions {

    func alertBody(_ conversation: ZMConversation, aSender: ZMUser) -> String? {
        // given
        let message = conversation.appendMessage(withText: "text") as! ZMClientMessage
        let reaction = ZMGenericMessage(emojiString: "❤️", messageID: message.nonce.transportString(), nonce: UUID.create().transportString())
        let event = createUpdateEvent(UUID.create(), conversationID: conversation.remoteIdentifier!, genericMessage: reaction, senderID: aSender.remoteIdentifier!)
        
        // when
        let sut = ZMLocalNotificationForReaction(events: [event], conversation: conversation, managedObjectContext: syncMOC, application: nil)
        
        // then
        guard let localNote = sut?.uiNotifications.first else {return nil }
        return localNote.alertBody
    }
    
    func testThatItCreatesTheCorrectAlertBody_ConvWithoutName(){
        guard let alertBody = alertBody(groupConversationWithoutName, aSender: otherUser) else { return XCTFail()}
        XCTAssertEqual(alertBody, "Other User ❤️ your message in a conversation")
    }
    
    func testThatItCreatesTheCorrectAlertBody(){
        guard let alertBody = alertBody(groupConversation, aSender: otherUser) else { return XCTFail()}
        XCTAssertEqual(alertBody, "Other User ❤️ your message in Super Conversation")
    }
    
    func testThatItCreatesTheCorrectAlertBody_UnknownUser(){
        otherUser.name = ""
        guard let alertBody = alertBody(groupConversation, aSender: otherUser) else { return XCTFail()}
        XCTAssertEqual(alertBody, "Someone ❤️ your message in Super Conversation")
    }
    
    func testThatItCreatesTheCorrectAlertBody_UnknownUser_UnknownConversationName(){
        otherUser.name = ""
        guard let alertBody = alertBody(groupConversationWithoutName, aSender: otherUser) else { return XCTFail()}
        XCTAssertEqual(alertBody, "Someone ❤️ your message in a conversation")
    }
    
    func testThatItCreatesTheCorrectAlertBody_UnknownUser_OneOnOneConv(){
        otherUser.name = ""
        guard let alertBody = alertBody(oneOnOneConversation, aSender: otherUser) else { return XCTFail()}
        XCTAssertEqual(alertBody, "Someone ❤️ your message")
    }
    
    func testThatItDoesNotCreateANotifcationForAnUnlikeReaction(){
        // given
        let message = oneOnOneConversation.appendMessage(withText: "text") as! ZMClientMessage
        let reaction = ZMGenericMessage(emojiString: "", messageID: message.nonce.transportString(), nonce: UUID.create().transportString())
        let event = createUpdateEvent(UUID.create(), conversationID: oneOnOneConversation.remoteIdentifier!, genericMessage: reaction, senderID: sender.remoteIdentifier!)
        
        // when
        let sut = ZMLocalNotificationForReaction(events: [event], conversation: oneOnOneConversation, managedObjectContext: syncMOC, application: self.application)
        
        // then
        XCTAssertNil(sut)
    }
    
    func testThatItDoesNotCreateANotificationForAReaction_SelfUserIsSenderOfOriginalMessage_SelfUserSendsLike(){
        // given
        let message = oneOnOneConversation.appendMessage(withText: "text") as! ZMClientMessage
        let reaction = ZMGenericMessage(emojiString: "❤️", messageID: message.nonce.transportString(), nonce: UUID.create().transportString())
        let event = createUpdateEvent(UUID.create(), conversationID: oneOnOneConversation.remoteIdentifier!, genericMessage: reaction, senderID: selfUser.remoteIdentifier!)
        
        // when
        let sut = ZMLocalNotificationForReaction(events: [event], conversation: oneOnOneConversation, managedObjectContext: syncMOC, application: self.application)
        
        // then
        XCTAssertNil(sut)
    }
    
    func testThatItDoesNotCreateANotificationForAReaction_OtherUserIsSenderOfOriginalMessage_OtherUserSendsLike(){
        // given
        let message = oneOnOneConversation.appendMessage(withText: "text") as! ZMClientMessage
        message.sender = otherUser
        
        let reaction = ZMGenericMessage(emojiString: "❤️", messageID: message.nonce.transportString(), nonce: UUID.create().transportString())
        let event = createUpdateEvent(UUID.create(), conversationID: oneOnOneConversation.remoteIdentifier!, genericMessage: reaction, senderID: sender.remoteIdentifier!)
        
        // when
        let sut = ZMLocalNotificationForReaction(events: [event], conversation: oneOnOneConversation, managedObjectContext: syncMOC, application: self.application)
        
        // then
        XCTAssertNil(sut)
    }
    
    func testThatItCancelsNotificationWhenUserDeletesLike(){
        // given
        let message = oneOnOneConversation.appendMessage(withText: "text") as! ZMClientMessage
        let reaction1 = ZMGenericMessage(emojiString: "❤️", messageID: message.nonce.transportString(), nonce: UUID.create().transportString())
        let reaction2 = ZMGenericMessage(emojiString: "", messageID: message.nonce.transportString(), nonce: UUID.create().transportString())
        
        let event1 = createUpdateEvent(UUID.create(), conversationID: oneOnOneConversation.remoteIdentifier!, genericMessage: reaction1, senderID: sender.remoteIdentifier!)
        let event2 = createUpdateEvent(UUID.create(), conversationID: oneOnOneConversation.remoteIdentifier!, genericMessage: reaction2, senderID: sender.remoteIdentifier!)
        
        // when
        let sut1 = ZMLocalNotificationForReaction(events: [event1], conversation: oneOnOneConversation, managedObjectContext: syncMOC, application: self.application)
        XCTAssertNotNil(sut1)
        let note = sut1?.uiNotifications.first
        let sut2 = sut1?.copyByAddingEvent(event2, conversation: oneOnOneConversation)
        
        // then
        XCTAssertNotNil(sut1)
        XCTAssertTrue(self.application.cancelledLocalNotifications.contains(note!))
        XCTAssertTrue(sut1!.shouldBeDiscarded)
        XCTAssertNil(sut2)
    }
    
    func testThatItDoesNotCancelNotificationWhenADifferentUserDeletesLike(){
        // given
        let message = oneOnOneConversation.appendMessage(withText: "text") as! ZMClientMessage
        let reaction1 = ZMGenericMessage(emojiString: "❤️", messageID: message.nonce.transportString(), nonce: UUID.create().transportString())
        let reaction2 = ZMGenericMessage(emojiString: "", messageID: message.nonce.transportString(), nonce: UUID.create().transportString())
        
        let event1 = createUpdateEvent(UUID.create(), conversationID: oneOnOneConversation.remoteIdentifier!, genericMessage: reaction1, senderID: sender.remoteIdentifier!)
        let event2 = createUpdateEvent(UUID.create(), conversationID: oneOnOneConversation.remoteIdentifier!, genericMessage: reaction2, senderID: otherUser.remoteIdentifier!)
        
        // when
        let sut1 = ZMLocalNotificationForReaction(events: [event1], conversation: oneOnOneConversation, managedObjectContext: syncMOC, application: self.application)
        let note = sut1?.uiNotifications.first

        let sut2 = sut1?.copyByAddingEvent(event2, conversation: oneOnOneConversation)
        
        // then
        XCTAssertNotNil(sut1)
        XCTAssertFalse(sut1!.shouldBeDiscarded)
        XCTAssertFalse(self.application.cancelledLocalNotifications.contains(note!))
        XCTAssertNil(sut2)
    }
}

