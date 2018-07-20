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
        let message = conversation.appendMessage(withText: textInput) as! ZMClientMessage
        message.sender = sender
        message.serverTimestamp = Date.distantFuture
        uiMOC.saveOrRollback()
        
        let note = ZMLocalNotification(message: message)
        XCTAssertNotNil(note)
        
        // when
        let storedNote = ZMStoredLocalNotification(notification: note!.uiLocalNotification, managedObjectContext: uiMOC, actionIdentifier: nil, textInput: textInput)
        
        // then
        XCTAssertEqual(storedNote.conversation, conversation)
        XCTAssertEqual(storedNote.senderUUID, sender.remoteIdentifier)
        XCTAssertEqual(storedNote.category, WireSyncEngine.PushNotificationCategory.conversationIncludingLike.rawValue)
        XCTAssertEqual(storedNote.textInput, textInput)
    }
}
