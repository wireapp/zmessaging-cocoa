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
import UserNotifications

@testable import WireSyncEngine

class LocalNotificationDispatcherTests: DatabaseTest {

    typealias ZMLocalNotification = WireSyncEngine.ZMLocalNotification
    
    var sut: LocalNotificationDispatcher!
    var conversation1: ZMConversation!
    var conversation2: ZMConversation!
    
    var notificationCenter: UserNotificationCenterMock!
    
    var scheduledRequests: [UNNotificationRequest] {
        return self.notificationCenter.scheduledRequests
    }

    var user1: ZMUser!
    var user2: ZMUser!
    
    var selfUser: ZMUser {
        return ZMUser.selfUser(in: self.syncMOC)
    }
    
    override func setUp() {
        super.setUp()
        self.notificationCenter = UserNotificationCenterMock()
        self.sut = LocalNotificationDispatcher(in: self.syncMOC)
        self.sut.notificationCenter = self.notificationCenter
        
        [self.sut.eventNotifications,
         self.sut.failedMessageNotifications,
         self.sut.messageNotifications,
         self.sut.callingNotifications].forEach { $0.notificationCenter = notificationCenter }
        
        syncMOC.performGroupedBlockAndWait {
            self.user1 = ZMUser.insertNewObject(in: self.syncMOC)
            self.user2 = ZMUser.insertNewObject(in: self.syncMOC)
            self.user1.remoteIdentifier = UUID.create()
            self.user1.name = "User 1"
            self.user2.remoteIdentifier = UUID.create()
            self.user2.name = "User 2"
            self.conversation1 = ZMConversation.insertNewObject(in: self.syncMOC)
            self.conversation1.userDefinedName = "Conversation 1"
            self.conversation2 = ZMConversation.insertNewObject(in: self.syncMOC)
            self.conversation2.userDefinedName = "Conversation 2"
            [self.conversation1!, self.conversation2!].forEach {
                $0.conversationType = .group
                $0.remoteIdentifier = UUID.create()
                $0.addParticipantAndUpdateConversationState(user: self.user1, role: nil)
            }
            self.conversation2.addParticipantAndUpdateConversationState(user: self.user2, role: nil)
            
            self.selfUser.remoteIdentifier = UUID.create()
        }
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
    }
    
    override func tearDown() {
        self.notificationCenter = nil
        self.user1 = nil
        self.user2 = nil
        self.conversation1 = nil
        self.conversation2 = nil
        self.sut = nil
        super.tearDown()
    }
}


extension LocalNotificationDispatcherTests {

    func testThatItCreatesNotificationFromMessagesIfNotActive() {
        // GIVEN
        let text = UUID.create().transportString()
        let message = self.conversation1.append(text: text) as! ZMClientMessage
        message.sender = self.user1
        
        // WHEN
        self.sut.process(message)
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // THEN
        XCTAssertEqual(self.sut.messageNotifications.notifications.count, 1)
        XCTAssertEqual(self.scheduledRequests.count, 1)
        
        guard
            let note = self.sut.messageNotifications.notifications.first,
            let request = self.scheduledRequests.first
            else { return XCTFail() }
        
        XCTAssertTrue(note.body.contains(text))
        XCTAssertEqual(note.body, request.content.body)
        XCTAssertEqual(note.id.uuidString, request.identifier)
    }
    
    func testThatItCreatesNotificationFromSystemMessagesIfNotActive() {
        // GIVEN
        conversation1.messageDestructionTimeout = .synced(.fiveMinutes)
        let message = conversation1.appendMessageTimerUpdateMessage(
            fromUser: user1,
            timer: conversation1.messageDestructionTimeoutValue,
            timestamp: .init()
        )

        message.sender = user1

        // WHEN
        sut.process(message)
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))

        // THEN
        XCTAssertEqual(self.sut.messageNotifications.notifications.count, 1)
        XCTAssertEqual(self.scheduledRequests.count, 1)
        
        guard
            let note = self.sut.messageNotifications.notifications.first,
            let request = self.scheduledRequests.first
            else { return XCTFail() }
        
        XCTAssertTrue(note.body.contains("User 1 set the message timer to"))
        XCTAssertEqual(note.body, request.content.body)
        XCTAssertEqual(note.id.uuidString, request.identifier)
    }

    func testThatItAddsNotificationOfDifferentConversationsToTheList() {
        // GIVEN
        let message1 = self.conversation1.append(text: "foo1") as! ZMClientMessage
        message1.sender = self.user1
        let message2 = self.conversation2.append(text: "boo2") as! ZMClientMessage
        message2.sender = self.user2

        // WHEN
        self.sut.process(message1)
        self.sut.process(message2)
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.5))

        // THEN
        XCTAssertEqual(self.scheduledRequests.count, 2)
        let userInfos = self.scheduledRequests.map { NotificationUserInfo(storage: $0.content.userInfo) }
        XCTAssertEqual(userInfos[0].conversation(in: self.syncMOC), self.conversation1)
        XCTAssertEqual(userInfos[1].conversation(in: self.syncMOC), self.conversation2)
    }

    func testThatItDoesNotCreateANotificationForAnUnsupportedEventType() {
        // GIVEN
        let event = self.event(withPayload: nil, type: .conversationTyping, in: self.conversation1, user: self.user1)

        // WHEN
        self.sut.didReceive(events: [event], conversationMap: [:])

        // THEN
        XCTAssertEqual(self.scheduledRequests.count, 0)
    }

    func testThatWhenFailingAMessageItSchedulesANotification() {
        self.syncMOC.performGroupedBlockAndWait {
            // GIVEN
            let message = self.conversation1.append(text: "bar") as! ZMClientMessage
            message.sender = self.user1

            // WHEN
            self.sut.didFailToSend(message)

            // THEN
            XCTAssertEqual(self.scheduledRequests.count, 1)
        }
    }

    func testThatItCancelsAllNotificationsForFailingMessagesWhenCancelingAllNotifications() {
        // GIVEN
        let note1 = ZMLocalNotification(expiredMessageIn: self.conversation1)!
        let note2 = ZMLocalNotification(expiredMessageIn: self.conversation1)!
        self.sut.eventNotifications.addObject(note1)
        self.sut.failedMessageNotifications.addObject(note2)

        // WHEN
        self.sut.cancelAllNotifications()

        // THEN
        XCTAssertEqual(self.notificationCenter.removedNotifications, Set([note1.id.uuidString, note2.id.uuidString]))
    }

    func testThatItCancelsNotificationsForFailingMessagesWhenCancelingNotificationsForASpecificConversation() {
        // GIVEN
        let note1 = ZMLocalNotification(expiredMessageIn: self.conversation1)!
        let note2 = ZMLocalNotification(expiredMessageIn: self.conversation2)!
        let note3 = ZMLocalNotification(expiredMessageIn: self.conversation1)!
        let note4 = ZMLocalNotification(expiredMessageIn: self.conversation2)!
        self.sut.eventNotifications.addObject(note1)
        self.sut.eventNotifications.addObject(note2)
        self.sut.failedMessageNotifications.addObject(note3)
        self.sut.failedMessageNotifications.addObject(note4)

        // WHEN
        self.sut.cancelNotification(for: self.conversation1)

        // THEN
        XCTAssertEqual(self.notificationCenter.removedNotifications, Set([note1.id.uuidString, note3.id.uuidString]))
    }

    func testThatItCancelsReadNotificationsIfTheLastReadChanges() {
        // GIVEN
        let message = conversation1.append(text: "foo") as! ZMClientMessage
        message.sender = user1
        let note1 = ZMLocalNotification(expiredMessage: message)!
        let note2 = ZMLocalNotification(expiredMessageIn: self.conversation1)!
        sut.eventNotifications.addObject(note1)
        sut.eventNotifications.addObject(note2)
        conversation1.lastServerTimeStamp = Date.distantFuture
        syncMOC.saveOrRollback()

        // WHEN
        let conversationOnUI = uiMOC.object(with: conversation1.objectID) as? ZMConversation
        conversationOnUI?.markAsRead()
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.5))

        // THEN
        XCTAssertEqual(self.notificationCenter.removedNotifications, Set([note1.id.uuidString, note2.id.uuidString]))
    }

    func testThatItSchedulesADefaultNotificationIfContentShouldNotBeVisible() {
        // GIVEN
        self.syncMOC.setPersistentStoreMetadata(NSNumber(value: true), key: LocalNotificationDispatcher.ZMShouldHideNotificationContentKey)
        self.syncMOC.saveOrRollback()
        let message = self.conversation1.append(text: "foo") as! ZMClientMessage
        message.sender = self.user1

        // WHEN
        self.sut.process(message)
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.5))

        // THEN
        XCTAssertEqual(self.scheduledRequests.count, 1)
        XCTAssertEqual(self.scheduledRequests[0].content.body, "New message")
        XCTAssertEqual(self.scheduledRequests[0].content.sound, UNNotificationSound(named: convertToUNNotificationSoundName("new_message_apns.caf")))
    }

    func testThatItDoesNotCreateNotificationForTwoMessageEventsWithTheSameNonce() {

        // GIVEN
        let message = self.conversation1.append(text: "foobar") as! ZMClientMessage
        message.sender = self.user1

        // WHEN
        self.sut.process(message)
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.5))

        // THEN
        XCTAssertEqual(self.sut.messageNotifications.notifications.count, 1)
        XCTAssertEqual(self.scheduledRequests.count, 1)
        
        // WHEN
        self.sut.process(message)
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.5))

        // THEN
        XCTAssertEqual(self.sut.messageNotifications.notifications.count, 1)
        XCTAssertEqual(self.scheduledRequests.count, 1)
    }

    func testThatItDoesNotCreateNotificationForFileUploadEventsWithTheSameNonce() {
        // GIVEN
        let url = Bundle(for: LocalNotificationDispatcherTests.self).url(forResource: "video", withExtension: "mp4")
        let audioMetadata = ZMAudioMetadata(fileURL: url!, duration: 100)
        let message = self.conversation1.append(file: audioMetadata) as! ZMAssetClientMessage
        message.sender = self.user1

        // WHEN
        self.sut.process(message)
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.5))

        // THEN
        XCTAssertEqual(self.sut.messageNotifications.notifications.count, 1)
        XCTAssertEqual(self.scheduledRequests.count, 1)

        // WHEN
        self.sut.process(message)
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.5))

        // THEN
        XCTAssertEqual(self.sut.messageNotifications.notifications.count, 1)
        XCTAssertEqual(self.scheduledRequests.count, 1)
    }

    func testThatItCreatesNotificationForSelfGroupParticipation() {
        // GIVEN
        let message = ZMSystemMessage(nonce: UUID(), managedObjectContext: syncMOC)
        message.visibleInConversation = self.conversation1
        message.sender = self.user1
        message.systemMessageType = .participantsAdded
        message.users = [self.selfUser]

        // notification content
        let text = "\(message.sender!.name!) added you"

        // WHEN
        self.sut.process(message)
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.5))

        // THEN
        XCTAssertEqual(self.scheduledRequests.count, 1)
        XCTAssertTrue(self.scheduledRequests.first!.content.body.contains(text))
    }

    func testThatItDoesNotCreateNotificationForOtherGroupParticipation() {
        // GIVEN
        let message = ZMSystemMessage(nonce: UUID(), managedObjectContext: syncMOC)
        message.visibleInConversation = self.conversation1
        message.sender = self.user1
        message.systemMessageType = .participantsAdded
        message.users = [self.user2]

        // WHEN
        self.sut.process(message)
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.5))

        // THEN
        XCTAssertEqual(self.scheduledRequests.count, 0)
    }

    func testThatItCancelsNotificationWhenUserDeletesLike() {
        let conversation = ZMConversation.insertNewObject(in: self.syncMOC)
        conversation.remoteIdentifier = UUID.create()
        let sender = ZMUser.insertNewObject(in: self.syncMOC)
        sender.remoteIdentifier = UUID.create()

        let message = conversation.append(text: "text") as! ZMClientMessage
        
        let reaction1 = GenericMessage(content: WireProtos.Reaction(emoji: "❤️", messageID: message.nonce!))
        let reaction2 = GenericMessage(content: WireProtos.Reaction(emoji: "", messageID: message.nonce!))

        let event1 = createUpdateEvent(UUID.create(), conversationID: conversation.remoteIdentifier!, genericMessage: reaction1, senderID: sender.remoteIdentifier!)
        let event2 = createUpdateEvent(UUID.create(), conversationID: conversation.remoteIdentifier!, genericMessage: reaction2, senderID: sender.remoteIdentifier!)

        sut.didReceive(events: [event1], conversationMap: [:])
        XCTAssertEqual(self.scheduledRequests.count, 1)
        let id = self.scheduledRequests.first!.identifier
        
        // WHEN
        sut.didReceive(events: [event2], conversationMap: [:])

        // THEN
        XCTAssertTrue(self.notificationCenter.removedNotifications.contains(id))
    }
    
    func testThatNotifyAvailabilityBehaviourChangedIfNeededSchedulesNotification_WhenNeedsToNotifyAvailabilityBehaviourChangeIsSet() {
        // given
        selfUser.availability = .away
        selfUser.needsToNotifyAvailabilityBehaviourChange = [.notification]
        
        // when
        sut.notifyAvailabilityBehaviourChangedIfNeeded()
        
        // then
        XCTAssertEqual(self.notificationCenter.scheduledRequests.count, 1)
        XCTAssertEqual(selfUser.needsToNotifyAvailabilityBehaviourChange, [])
    }
    
    func testThatNotifyAvailabilityBehaviourChangedIfNeededDoesNotScheduleNotification_WhenneedsToNotifyAvailabilityBehaviourChangeIsNotSet() {
        // given
        selfUser.needsToNotifyAvailabilityBehaviourChange = []
        
        // when
        sut.notifyAvailabilityBehaviourChangedIfNeeded()
        
        // then
        XCTAssertEqual(self.notificationCenter.scheduledRequests.count, 0)
    }
}



// MARK: - Helpers
extension LocalNotificationDispatcherTests {
    
    func payloadForEncryptedOTRMessage(text: String, nonce: UUID) -> [String: Any] {
        let message = GenericMessage(content: Text(content: text), nonce: nonce)
        return self.payloadForOTRAsset(with: message)
    }
    
    func payloadForOTRAsset(with message: GenericMessage) -> [String: Any] {
        return [
            "data": [
                "info": try? message.serializedData().base64String()
            ],
            "conversation": self.conversation1.remoteIdentifier!.transportString(),
            "type": EventConversationAddOTRAsset,
            "time": Date().transportString()
        ]
    }

    func payloadForOTRMessage(with message: GenericMessage) -> [String: Any] {
        return [
            "data": [
                "text": try? message.serializedData().base64String()
            ],
            "conversation": self.conversation1.remoteIdentifier!.transportString(),
            "type": EventConversationAddOTRAsset,
            "time": Date().transportString()
        ]
    }
    
    func createUpdateEvent(_ nonce: UUID, conversationID: UUID, genericMessage: GenericMessage, senderID: UUID = UUID.create()) -> ZMUpdateEvent {
        let payload : [String : Any] = [
            "id": UUID.create().transportString(),
            "conversation": conversationID.transportString(),
            "from": senderID.transportString(),
            "time": Date().transportString(),
            "data": ["text": try? genericMessage.serializedData().base64String()],
            "type": "conversation.otr-message-add"
        ]
        
        return ZMUpdateEvent(fromEventStreamPayload: payload as ZMTransportData, uuid: nonce)!
    }
}

// Helper function inserted by Swift 4.2 migrator.
fileprivate func convertToUNNotificationSoundName(_ input: String) -> UNNotificationSoundName {
	return UNNotificationSoundName(rawValue: input)
}
