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

class FakeNotificationScheduler : NSObject, NotificationScheduler {
    var didCallCancel = false
    
    func scheduleLocalNotification(notification: UILocalNotification) {
        // no-op
    }
    
    func cancelLocalNotification(notification: UILocalNotification) {
        didCallCancel = true
    }
}

class ZMLocalNotificationForEventsTests_Reactions : ZMLocalNotificationForEventTest {

    
    func createUpdateEvent(nonce: NSUUID, conversationID: NSUUID, genericMessage: ZMGenericMessage, senderID: NSUUID = .createUUID()) -> ZMUpdateEvent {
        let payload = [
            "id": NSUUID.createUUID().transportString(),
            "conversation": conversationID.transportString(),
            "from": senderID.transportString(),
            "time": NSDate().transportString(),
            "data": [
                "text": genericMessage.data().base64String()
            ],
            "type": "conversation.otr-message-add"
        ]
        
        return ZMUpdateEvent(fromEventStreamPayload: payload, uuid: nonce)
    }

    
    func testThatItCreatesANotifcationForAReaction_SelfUserIsSenderOfOriginalMessage_OtherUserSendsLike(){
        // given
        let message = oneOnOneConversation.appendMessageWithText("text") as! ZMClientMessage
        let reaction = ZMGenericMessage(emojiString: "liked", messageID: message.nonce.transportString(), nonce: NSUUID.createUUID().transportString())
        let event = createUpdateEvent(NSUUID(), conversationID: oneOnOneConversation.remoteIdentifier, genericMessage: reaction, senderID: otherUser.remoteIdentifier!)
        XCTAssertNotNil(event)
        
        // when
        let sut = ZMLocalNotificationForReaction(events: [event], conversation: oneOnOneConversation, managedObjectContext: message.managedObjectContext!, application: nil)
        
        // then
        XCTAssertNotNil(sut)
        
        guard let localNote = sut?.uiNotifications.first else {return XCTFail()}
        XCTAssertEqual(localNote.alertBody, "Other User liked your message")
        XCTAssertEqual(localNote.zm_messageNonce, event.messageNonce())
    }
    
    func alertBody(conversation: ZMConversation, sender: ZMUser) -> String? {
        // given
        let message = conversation.appendMessageWithText("text") as! ZMClientMessage
        let reaction = ZMGenericMessage(emojiString: "liked", messageID: message.nonce.transportString(), nonce: NSUUID.createUUID().transportString())
        let event = createUpdateEvent(NSUUID(), conversationID: conversation.remoteIdentifier, genericMessage: reaction, senderID: sender.remoteIdentifier!)
        
        // when
        let sut = ZMLocalNotificationForReaction(events: [event], conversation: conversation, managedObjectContext: message.managedObjectContext!, application: nil)
        
        // then
        guard let localNote = sut?.uiNotifications.first else {return nil }
        return localNote.alertBody
    }
    
    func testThatItCreatesTheCorrectAlertBody_ConvWithoutName(){
        guard let alertBody = alertBody(groupConversationWithoutName, sender: otherUser) else { return XCTFail()}
        XCTAssertEqual(alertBody, "Other User liked your message in a conversation")
    }
    
    func testThatItCreatesTheCorrectAlertBody(){
        guard let alertBody = alertBody(groupConversation, sender: otherUser) else { return XCTFail()}
        XCTAssertEqual(alertBody, "Other User liked your message in Super Conversation")
    }
    
    func testThatItCreatesTheCorrectAlertBody_UnknownUser(){
        otherUser.name = ""
        guard let alertBody = alertBody(groupConversation, sender: otherUser) else { return XCTFail()}
        XCTAssertEqual(alertBody, "Someone liked your message in Super Conversation")
    }
    
    func testThatItCreatesTheCorrectAlertBody_UnknownUser_UnknownConversationName(){
        otherUser.name = ""
        guard let alertBody = alertBody(groupConversationWithoutName, sender: otherUser) else { return XCTFail()}
        XCTAssertEqual(alertBody, "Someone liked your message in a conversation")
    }
    
    func testThatItCreatesTheCorrectAlertBody_UnknownUser_OneOnOneConv(){
        otherUser.name = ""
        guard let alertBody = alertBody(oneOnOneConversation, sender: otherUser) else { return XCTFail()}
        XCTAssertEqual(alertBody, "Someone liked your message")
    }
    
    func testThatItCreatesANotifcationForAReaction_CallingSuperFunction(){
        // given
        let message = oneOnOneConversation.appendMessageWithText("text") as! ZMClientMessage
        let reaction = ZMGenericMessage(emojiString: "liked", messageID: message.nonce.transportString(), nonce: NSUUID.createUUID().transportString())
        let event = createUpdateEvent(NSUUID(), conversationID: oneOnOneConversation.remoteIdentifier, genericMessage: reaction, senderID: otherUser.remoteIdentifier!)
        XCTAssertNotNil(event)
        
        // when
        let sut = ZMLocalNotificationForEvent.notification(forEvent: event, managedObjectContext: message.managedObjectContext!, application: nil)
        
        // then
        XCTAssertNotNil(sut)
        
        guard let localNote = sut?.uiNotifications.first else {return XCTFail()}
        XCTAssertEqual(localNote.alertBody, "Other User liked your message")
        XCTAssertEqual(localNote.zm_messageNonce, event.messageNonce())
    }
    
    func testThatItDoesNotCreateANotifcationForAnUnlikeReaction(){
        // given
        let message = oneOnOneConversation.appendMessageWithText("text") as! ZMClientMessage
        let reaction = ZMGenericMessage(emojiString: "", messageID: message.nonce.transportString(), nonce: NSUUID.createUUID().transportString())
        let event = createUpdateEvent(NSUUID(), conversationID: oneOnOneConversation.remoteIdentifier, genericMessage: reaction, senderID: otherUser.remoteIdentifier!)
        XCTAssertNotNil(event)
        
        // when
        let sut = ZMLocalNotificationForReaction(events: [event], conversation: oneOnOneConversation, managedObjectContext: message.managedObjectContext!, application: nil)
        
        // then
        XCTAssertNil(sut)
    }
    
    func testThatItDoesNotCreateANotificationForAReaction_SelfUserIsSenderOfOriginalMessage_SelfUserSendsLike(){
        // given
        let message = oneOnOneConversation.appendMessageWithText("text") as! ZMClientMessage
        let reaction = ZMGenericMessage(emojiString: "liked", messageID: message.nonce.transportString(), nonce: NSUUID.createUUID().transportString())
        let event = createUpdateEvent(NSUUID(), conversationID: oneOnOneConversation.remoteIdentifier, genericMessage: reaction, senderID: selfUser.remoteIdentifier!)
        
        // when
        let sut = ZMLocalNotificationForReaction(events: [event], conversation: oneOnOneConversation, managedObjectContext: message.managedObjectContext!, application: nil)
        
        // then
        XCTAssertNil(sut)
    }
    
    func testThatItDoesNotCreateANotificationForAReaction_OtherUserIsSenderOfOriginalMessage_OtherUserSendsLike(){
        // given
        let message = oneOnOneConversation.appendMessageWithText("text") as! ZMClientMessage
        message.sender = otherUser
        
        let reaction = ZMGenericMessage(emojiString: "liked", messageID: message.nonce.transportString(), nonce: NSUUID.createUUID().transportString())
        let event = createUpdateEvent(NSUUID(), conversationID: oneOnOneConversation.remoteIdentifier, genericMessage: reaction, senderID: otherUser.remoteIdentifier!)
        
        // when
        let sut = ZMLocalNotificationForReaction(events: [event], conversation: oneOnOneConversation, managedObjectContext: message.managedObjectContext!, application: nil)
        
        // then
        XCTAssertNil(sut)
    }
    
    func testThatItCancelsNotificationWhenUserDeletesLike(){
        // given
        let fakeNotificationScheduler = FakeNotificationScheduler()
        
        let message = oneOnOneConversation.appendMessageWithText("text") as! ZMClientMessage
        let reaction1 = ZMGenericMessage(emojiString: "liked", messageID: message.nonce.transportString(), nonce: NSUUID.createUUID().transportString())
        let reaction2 = ZMGenericMessage(emojiString: "", messageID: message.nonce.transportString(), nonce: NSUUID.createUUID().transportString())
        
        let event1 = createUpdateEvent(NSUUID(), conversationID: oneOnOneConversation.remoteIdentifier, genericMessage: reaction1, senderID: otherUser.remoteIdentifier!)
        let event2 = createUpdateEvent(NSUUID(), conversationID: oneOnOneConversation.remoteIdentifier, genericMessage: reaction2, senderID: otherUser.remoteIdentifier!)
        
        // when
        let sut1 = ZMLocalNotificationForReaction(events: [event1], conversation: oneOnOneConversation, managedObjectContext: message.managedObjectContext!, application: fakeNotificationScheduler)
        let sut2 = sut1!.copyByAddingEvent(event2)
        
        // then
        XCTAssertTrue(fakeNotificationScheduler.didCallCancel)
        XCTAssertNotNil(sut1)
        XCTAssertTrue(sut1!.shouldBeDiscarded)
        XCTAssertNil(sut2)
    }
    
    func testThatItDoesNotCancelNotificationWhenADifferentUserDeletesLike(){
        // given
        let fakeNotificationScheduler = FakeNotificationScheduler()
        
        let message = oneOnOneConversation.appendMessageWithText("text") as! ZMClientMessage
        let reaction1 = ZMGenericMessage(emojiString: "liked", messageID: message.nonce.transportString(), nonce: NSUUID.createUUID().transportString())
        let reaction2 = ZMGenericMessage(emojiString: "", messageID: message.nonce.transportString(), nonce: NSUUID.createUUID().transportString())
        
        let event1 = createUpdateEvent(NSUUID(), conversationID: oneOnOneConversation.remoteIdentifier, genericMessage: reaction1, senderID: otherUser.remoteIdentifier!)
        let event2 = createUpdateEvent(NSUUID(), conversationID: oneOnOneConversation.remoteIdentifier, genericMessage: reaction2, senderID: otherUser2.remoteIdentifier!)
        
        // when
        let sut1 = ZMLocalNotificationForReaction(events: [event1], conversation: oneOnOneConversation, managedObjectContext: message.managedObjectContext!, application: fakeNotificationScheduler)
        let sut2 = sut1!.copyByAddingEvent(event2)
        
        // then
        XCTAssertNotNil(sut1)
        XCTAssertFalse(sut1!.shouldBeDiscarded)
        XCTAssertFalse(fakeNotificationScheduler.didCallCancel)
        XCTAssertNil(sut2)
    }
}

