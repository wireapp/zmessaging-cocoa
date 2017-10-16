//
//  ZMStoredLocalNotificationTests.swift
//  WireSyncEngine-iOS-Tests
//
//  Created by John Nguyen on 15.10.17.
//  Copyright © 2017 Zeta Project Gmbh. All rights reserved.
//

import XCTest
@testable import WireSyncEngine

class ZMStoredLocalNotificationTests: MessagingTest {
    
    var sender: ZMUser!
    var conversation: ZMConversation!
    
    override func setUp() {
        super.setUp()
        sender = ZMUser.insertNewObject(in: uiMOC)
        sender.remoteIdentifier = UUID.create()
        conversation = ZMConversation.insertNewObject(in: uiMOC)
        conversation.remoteIdentifier = UUID.create()
        ZMUser.selfUser(in: uiMOC).remoteIdentifier = UUID.create()
        uiMOC.saveOrRollback()
    }
    
    override func tearDown() {
        sender = nil
        conversation = nil
        super.tearDown()
    }
    
    func pushPayloadForEventPayload(_ payload: [AnyHashable: Any]) -> [AnyHashable: Any] {
        return [
            "aps": ["content-available": 1],
            "data": payload
        ]
    }
    
    func testThatItCreatesAStoredLocalNotificationFromALocalNotification() {
        
        // given
        let textInput = "Foobar"
        let message = ZMClientMessage.insertNewObject(in: uiMOC)
        let genericMessage = ZMGenericMessage.message(text: textInput, nonce: UUID.create().transportString(), expiresAfter: nil)
        message.add(genericMessage.data())
        message.sender = sender
        message.visibleInConversation = conversation
        uiMOC.saveOrRollback()
        
        let note = ZMLocalNotification(message: message)
        XCTAssertNotNil(note)
        
        // when
        let storedNote = ZMStoredLocalNotification(notification: note!.uiLocalNotification, managedObjectContext: uiMOC, actionIdentifier: nil, textInput: textInput)
        
        // then
        XCTAssertEqual(storedNote.conversation, conversation)
        XCTAssertEqual(storedNote.senderUUID, sender.remoteIdentifier)
        XCTAssertEqual(storedNote.category, ZMConversationCategoryIncludingLike)
        XCTAssertEqual(storedNote.textInput, textInput)
    }
}
