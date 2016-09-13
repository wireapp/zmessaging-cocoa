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
import ZMCDataModel;

@testable import zmessaging;

public class MockKVStore : NSObject, ZMSynchonizableKeyValueStore {
    
    var keysAndValues = [String : AnyObject]()
    
    @objc public override func setValue(value: AnyObject!, forKey key: String) {
        keysAndValues[key] = value
    }
    
    @objc public override func valueForKey(key: String) -> AnyObject? {
        return keysAndValues[key]
    }
    
    @objc public func enqueueDelayedSave(){
    
    }
}

class MockLocalNotification : ZMLocalNotification {

    var eventTypeUnderTest : ZMUpdateEventType?
    
    internal var notifications = [UILocalNotification]()
    
    func add(notification: UILocalNotification){
        notifications.append(notification)
    }
    
    override var uiNotifications : [UILocalNotification] {
        return notifications
    }
}

class ZMLocalNotificationSetTests : MessagingTest {

    var sut : ZMLocalNotificationSet!
    var keyValueStore : MockKVStore!
    let archivingKey = "archivingKey"
    
    override func setUp(){
        super.setUp()
        keyValueStore = MockKVStore()
        sut = ZMLocalNotificationSet(application: self.application, archivingKey: archivingKey, keyValueStore: keyValueStore)
    }
    
    override func tearDown(){
        keyValueStore = nil
        sut = nil
        super.tearDown()
    }
    
    func testThatYouCanAddNAndRemoveNotifications(){
        // given
        let note = MockLocalNotification()
        
        // when
        sut.addObject(note)
        
        // then
        XCTAssertEqual(sut.notifications.count, 1)
        
        // and when
        sut.remove(note)
        
        // then
        XCTAssertEqual(sut.notifications.count, 0)
    }
    
    func testThatItCancelsNotificationsOnlyForSpecificConversations(){
        // given
        let conversation1 = ZMConversation.insertNewObjectInManagedObjectContext(self.uiMOC)
        conversation1.remoteIdentifier = NSUUID()
        let localNote1 = UILocalNotification()
        localNote1.alertBody = "note1"
        let note1 = MockLocalNotification(conversationID: conversation1.remoteIdentifier)
        note1.add(localNote1)
        
        let conversation2 = ZMConversation.insertNewObjectInManagedObjectContext(self.uiMOC)
        conversation2.remoteIdentifier = NSUUID()
        let localNote2 = UILocalNotification()
        localNote2.alertBody = "note2"
        let note2 = MockLocalNotification(conversationID: conversation2.remoteIdentifier)
        note2.add(localNote2)
        
        // when
        sut.addObject(note1)
        sut.addObject(note2)
        sut.cancelNotifications(conversation1)
        
        // then
        XCTAssertFalse(sut.notifications.contains(note1))
        XCTAssertTrue(self.application.cancelledLocalNotifications.contains(localNote1))

        XCTAssertTrue(sut.notifications.contains(note2))
        XCTAssertFalse(self.application.cancelledLocalNotifications.contains(localNote2))
    }
    
    func testThatItOnlyCancelsCallNotificationsIfSpecified(){
        // given
        let conversation1 = ZMConversation.insertNewObjectInManagedObjectContext(self.uiMOC)
        conversation1.remoteIdentifier = NSUUID()
        let localNote1 = UILocalNotification()
        localNote1.alertBody = "note1"
        let note1 = MockLocalNotification(conversationID: conversation1.remoteIdentifier)
        note1.add(localNote1)
        note1.eventTypeUnderTest = .CallState
        
        let localNote2 = UILocalNotification()
        localNote1.alertBody = "note2"
        let note2 = MockLocalNotification(conversationID: conversation1.remoteIdentifier)
        note2.add(localNote2)
        
        sut.addObject(note1)
        sut.addObject(note2)
        
        // when
        sut.cancelNotificationForIncomingCall(conversation1)
        
        // then
        XCTAssertFalse(sut.notifications.contains(note1))
        XCTAssertTrue(self.application.cancelledLocalNotifications.contains(localNote1))
        
        XCTAssertTrue(sut.notifications.contains(note2))
        XCTAssertFalse(self.application.cancelledLocalNotifications.contains(localNote2))
    }
    
    func testThatItPersistsNotifications() {
        // given
        let localNote1 = UILocalNotification()
        let note1 = MockLocalNotification()
        note1.add(localNote1)
        sut.addObject(note1)
        
        // when recreate sut to release non-persisted objects
        sut = ZMLocalNotificationSet(application: self.application, archivingKey: archivingKey, keyValueStore: keyValueStore)
        
        // then
        XCTAssertTrue(sut.oldNotifications.contains(localNote1))
    }

    func testThatItResetsTheNotificationSetWhenCancellingAllNotifications(){
        // given
        let localNote1 = UILocalNotification()
        let note1 = MockLocalNotification()
        note1.add(localNote1)
        sut.addObject(note1)
        
        // when
        sut.cancelAllNotifications()
        
        // then
        XCTAssertEqual(sut.notifications.count, 0)
    }
}


