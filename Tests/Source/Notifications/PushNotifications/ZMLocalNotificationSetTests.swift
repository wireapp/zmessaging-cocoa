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


import WireTesting;
import WireDataModel;

@testable import WireSyncEngine;

public final class MockKVStore : NSObject, ZMSynchonizableKeyValueStore {

    var keysAndValues = [String : Any]()
    
    public func store(value: PersistableInMetadata?, key: String) {
        keysAndValues[key] = value
    }
    
    public func storedValue(key: String) -> Any? {
        return keysAndValues[key]
    }
    
    @objc public func enqueueDelayedSave() {
        // no op
    }
    
}

//class MockLocalNotification : ZMLocalNotification {
//
//    internal var notifications = [UILocalNotification]()
//
//    func add(_ notification: UILocalNotification){
//        notifications.append(notification)
//    }
//
//    override var uiNotifications : [UILocalNotification] {
//        return notifications
//    }
//}
//
//class MockEventNotification : MockLocalNotification, EventNotification {
//    var eventTypeUnderTest : ZMUpdateEventType?
//    var ignoresSilencedState : Bool { return false }
//    var eventType : ZMUpdateEventType { return eventTypeUnderTest ?? .unknown }
//    unowned var application: ZMApplication
//    unowned var managedObjectContext: NSManagedObjectContext
//    required init?(events: [ZMUpdateEvent], conversation: ZMConversation?, managedObjectContext: NSManagedObjectContext, application: ZMApplication?) {
//        self.managedObjectContext = managedObjectContext
//        self.application = application!
//        super.init(conversationID: conversation?.remoteIdentifier)
//    }
//}

class ZMLocalNotificationSetTests : MessagingTest {

    var sut : ZMLocalNotificationSet!
    var keyValueStore : MockKVStore!
    let archivingKey = "archivingKey"
    
    var sender : ZMUser!
    var conversation1 : ZMConversation!
    var conversation2 : ZMConversation!

    override func setUp(){
        super.setUp()
        keyValueStore = MockKVStore()
        sut = ZMLocalNotificationSet(application: self.application, archivingKey: archivingKey, keyValueStore: keyValueStore)
        
        let selfUser = ZMUser.selfUser(in: self.uiMOC)
        selfUser.remoteIdentifier = UUID.create()
        sender = ZMUser.insertNewObject(in: self.uiMOC)
        sender.remoteIdentifier = UUID.create()
        conversation1 = ZMConversation.insertNewObject(in: self.uiMOC)
        conversation1.remoteIdentifier = UUID.create()
        conversation2 = ZMConversation.insertNewObject(in: self.uiMOC)
        conversation2.remoteIdentifier = UUID.create()
    }

    override func tearDown(){
        keyValueStore = nil
        sut = nil
        sender = nil
        conversation1 = nil
        conversation2 = nil
        super.tearDown()
    }
    
    func createMessage(with text: String, in conversation: ZMConversation) -> ZMOTRMessage {
        let message = conversation.appendMessage(withText: text) as! ZMOTRMessage
        message.sender = sender
        message.serverTimestamp = Date()
        return message
    }

    func testThatYouCanAddNAndRemoveNotifications(){
        
        // given
        let note = ZMLocalNote(message: createMessage(with: "Hello Hello", in: conversation1))!

        // when
        sut.addObject(note)

        // then
        XCTAssertEqual(sut.notifications.count, 1)

        // and when
        let _ = sut.remove(note)

        // then
        XCTAssertEqual(sut.notifications.count, 0)
    }

    func testThatItCancelsNotificationsOnlyForSpecificConversations(){
        
        // given
        let note1 = ZMLocalNote(message: createMessage(with: "Hello Hello", in: conversation1))!
        let note2 = ZMLocalNote(message: createMessage(with: "Bye BYe", in: conversation2))!
        
        // when
        sut.addObject(note1)
        sut.addObject(note2)
        sut.cancelNotifications(conversation1)

        // then
        XCTAssertFalse(sut.notifications.contains(note1))
        XCTAssertTrue(self.application.cancelledLocalNotifications.contains(note1.uiLocalNotification))

        XCTAssertTrue(sut.notifications.contains(note2))
        XCTAssertFalse(self.application.cancelledLocalNotifications.contains(note2.uiLocalNotification))
    }

    func testThatItOnlyCancelsCallNotificationsIfSpecified(){
        
        // given
        let note1 = ZMLocalNote(callState: .terminating(reason: .canceled), conversation: conversation1, sender: sender)!
        XCTAssertEqual(note1.conversationID, conversation1.remoteIdentifier)

        let note2 = ZMLocalNote(message: createMessage(with: "Not A Call!", in: conversation1))!
        XCTAssertEqual(note2.conversationID, conversation1.remoteIdentifier)

        sut.addObject(note1)
        sut.addObject(note2)

        // when
        sut.cancelNotificationForIncomingCall(conversation1)

        // then
        XCTAssertFalse(sut.notifications.contains(note1))
        XCTAssertTrue(self.application.cancelledLocalNotifications.contains(note1.uiLocalNotification))

        XCTAssertTrue(sut.notifications.contains(note2))
        XCTAssertFalse(self.application.cancelledLocalNotifications.contains(note2.uiLocalNotification))
    }

    func testThatItPersistsNotifications() {
        
        // given
        let note = ZMLocalNote(message: createMessage(with: "Hello", in: conversation1))!
        sut.addObject(note)

        // when recreate sut to release non-persisted objects
        sut = ZMLocalNotificationSet(application: self.application, archivingKey: archivingKey, keyValueStore: keyValueStore)

        // then
        XCTAssertTrue(sut.oldNotifications.contains(note.uiLocalNotification))
    }

    func testThatItResetsTheNotificationSetWhenCancellingAllNotifications(){
        
        // given
        let note = ZMLocalNote(message: createMessage(with: "Hello", in: conversation1))!
        sut.addObject(note)
        
        // when
        sut.cancelAllNotifications()
        
        // then
        XCTAssertEqual(sut.notifications.count, 0)
    }
}
