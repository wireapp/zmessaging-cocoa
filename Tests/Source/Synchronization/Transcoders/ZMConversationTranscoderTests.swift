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
import WireRequestStrategy
import WireDataModel

extension ZMConversation {
    @objc var isFullyMuted: Bool {
        get {
            return mutedMessageTypes == .all
        }
        set {
            mutedMessageTypes = newValue ? .all : .none
        }
    }
    
    @objc var isMutedDisplayingMentions: Bool {
        get {
            return mutedMessageTypes == .regular
        }
        set {
            mutedMessageTypes = newValue ? .regular : .none
        }
    }
}

class ZMConversationTranscoderTests_Swift: ObjectTranscoderTests {
    
    var sut: ZMConversationTranscoder!
    var localNotificationDispatcher: MockPushMessageHandler!
    var conversation: ZMConversation!
    var user: ZMUser!
    var mockSyncStatus : MockSyncStatus!
    
    override func setUp() {
        super.setUp()
        
        self.syncMOC.performGroupedBlockAndWait {
            self.mockSyncStatus = MockSyncStatus(managedObjectContext: self.syncMOC, syncStateDelegate: self)
            self.mockSyncStatus.mockPhase = .done
            self.mockApplicationStatus.mockSynchronizationState = .eventProcessing
            self.localNotificationDispatcher = MockPushMessageHandler()
            self.sut = ZMConversationTranscoder(managedObjectContext: self.syncMOC, applicationStatus: self.mockApplicationStatus, localNotificationDispatcher: self.localNotificationDispatcher, syncStatus: self.mockSyncStatus)
            self.conversation = ZMConversation.insertNewObject(in: self.syncMOC)
            self.conversation.remoteIdentifier = UUID.create()
            self.conversation.conversationType = .group
            self.conversation.lastServerTimeStamp = Date(timeIntervalSince1970: 123124)
            self.conversation.lastReadServerTimeStamp = self.conversation.lastServerTimeStamp
            self.user = ZMUser.insertNewObject(in: self.syncMOC)
            self.user.remoteIdentifier = UUID.create()
            
            self.syncMOC.saveOrRollback()
        }
    }
    
    override func tearDown() {
        self.sut = nil
        self.localNotificationDispatcher = nil
        self.conversation = nil
        self.user = nil
        self.mockSyncStatus = nil
        
        super.tearDown()
    }
    
    func testThatItCreatesAndNotifiesSystemMessagesFromAMemberJoin() {
        
        self.syncMOC.performAndWait {
            
            // GIVEN
            let payload = [
                "from": self.user.remoteIdentifier!.transportString(),
                "conversation": self.conversation.remoteIdentifier!.transportString(),
                "time": NSDate().transportString(),
                "data": [
                    "user_ids": [self.user.remoteIdentifier!.transportString()]
                ],
                "type": "conversation.member-join"
                ] as [String: Any]
            let event = ZMUpdateEvent(fromEventStreamPayload: payload as ZMTransportData, uuid: nil)!
            
            // WHEN
            self.sut.processEvents([event], liveEvents: true, prefetchResult: nil)
            
            // THEN
            guard let message = self.conversation.lastMessage as? ZMSystemMessage else {
                XCTFail()
                return
            }
            XCTAssertEqual(message.systemMessageType, .participantsAdded)
            XCTAssertEqual(self.localNotificationDispatcher.processedMessages.last, message)
        }
    }
    
    func testThatItIgnoresMemberJoinEventsIfMemberIsAlreadyPartOfConversation() {
        
        self.syncMOC.performAndWait {
            
            // GIVEN
            self.conversation.internalAddParticipants([user])
            
            let payload = [
                "from": self.user.remoteIdentifier!.transportString(),
                "conversation": self.conversation.remoteIdentifier!.transportString(),
                "time": NSDate().transportString(),
                "data": [
                    "user_ids": [self.user.remoteIdentifier!.transportString()]
                ],
                "type": "conversation.member-join"
                ] as [String: Any]
            let event = ZMUpdateEvent(fromEventStreamPayload: payload as ZMTransportData, uuid: nil)!
            let messageCountBeforeProcessing = self.conversation.allMessages.count
            
            // WHEN
            self.sut.processEvents([event], liveEvents: true, prefetchResult: nil)
            
            // THEN
            XCTAssertEqual(self.conversation.allMessages.count, messageCountBeforeProcessing)
        }
    }
    
    func testThatItCreatesAndNotifiesSystemMessagesFromAMemberRemove() {
        
        self.syncMOC.performAndWait {
            
            // GIVEN
            self.conversation.internalAddParticipants([user])
            
            let payload = [
                "from": self.user.remoteIdentifier!.transportString(),
                "conversation": self.conversation.remoteIdentifier!.transportString(),
                "time": NSDate().transportString(),
                "data": [
                    "user_ids": [self.user.remoteIdentifier!.transportString()]
                ],
                "type": "conversation.member-leave"
                ] as [String: Any]
            let event = ZMUpdateEvent(fromEventStreamPayload: payload as ZMTransportData, uuid: nil)!
            
            // WHEN
            self.sut.processEvents([event], liveEvents: true, prefetchResult: nil)
            
            // THEN
            guard let message = self.conversation.lastMessage as? ZMSystemMessage else {
                XCTFail()
                return
            }
            XCTAssertEqual(message.systemMessageType, .participantsRemoved)
            XCTAssertEqual(self.localNotificationDispatcher.processedMessages.last, message)
        }
    }
    
    func testThatItIgnoresMemberRemoveEventsIfMemberIsNotPartOfConversation() {
        
        self.syncMOC.performAndWait {
            
            // GIVEN
            let payload = [
                "from": self.user.remoteIdentifier!.transportString(),
                "conversation": self.conversation.remoteIdentifier!.transportString(),
                "time": NSDate().transportString(),
                "data": [
                    "user_ids": [self.user.remoteIdentifier!.transportString()]
                ],
                "type": "conversation.member-leave"
                ] as [String: Any]
            let event = ZMUpdateEvent(fromEventStreamPayload: payload as ZMTransportData, uuid: nil)!
            let messageCountBeforeProcessing = self.conversation.allMessages.count
            
            // WHEN
            self.sut.processEvents([event], liveEvents: true, prefetchResult: nil)
            
            // THEN
            XCTAssertEqual(self.conversation.allMessages.count, messageCountBeforeProcessing)
        }
    }
    
    func testThatItCreatesAndNotifiesSystemMessagesFromConversationRename() {
        
        self.syncMOC.performAndWait {
            
            // GIVEN
            let payload = [
                "from": self.user.remoteIdentifier!.transportString(),
                "conversation": self.conversation.remoteIdentifier!.transportString(),
                "time": NSDate().transportString(),
                "data": [
                    "name": "foobar"
                ],
                "type": "conversation.rename"
                ] as [String: Any]
            let event = ZMUpdateEvent(fromEventStreamPayload: payload as ZMTransportData, uuid: nil)!
            
            // WHEN
            self.sut.processEvents([event], liveEvents: true, prefetchResult: nil)
            
            // THEN
            guard let message = self.conversation.lastMessage as? ZMSystemMessage else {
                XCTFail()
                return
            }
            XCTAssertEqual(message.systemMessageType, .conversationNameChanged)
            XCTAssertEqual(self.localNotificationDispatcher.processedMessages.last, message)
        }
    }
    
    func testThatItCreatesAndNotifiesSystemMessagesFromConversationRenameIfConversationAlreadyHasSameNameButNotYetSynced() {
        
        self.syncMOC.performAndWait {
            
            // GIVEN
            conversation.userDefinedName = "foobar"
            conversation.setLocallyModifiedKeys(Set<AnyHashable>([ZMConversationUserDefinedNameKey]))
            
            let payload = [
                "from": self.user.remoteIdentifier!.transportString(),
                "conversation": self.conversation.remoteIdentifier!.transportString(),
                "time": NSDate().transportString(),
                "data": [
                    "name": "foobar"
                ],
                "type": "conversation.rename"
                ] as [String: Any]
            let event = ZMUpdateEvent(fromEventStreamPayload: payload as ZMTransportData, uuid: nil)!
            
            // WHEN
            self.sut.processEvents([event], liveEvents: true, prefetchResult: nil)
            
            // THEN
            guard let message = self.conversation.lastMessage as? ZMSystemMessage else {
                XCTFail()
                return
            }
            XCTAssertEqual(message.systemMessageType, .conversationNameChanged)
            XCTAssertEqual(self.localNotificationDispatcher.processedMessages.last, message)
        }
    }
    
    func testThatItIgnoresConversationRenameEventsIfConversationAlreadyHasSameName() {
        
        self.syncMOC.performAndWait {
            
            // GIVEN
            conversation.userDefinedName = "foobar"
            
            let payload = [
                "from": self.user.remoteIdentifier!.transportString(),
                "conversation": self.conversation.remoteIdentifier!.transportString(),
                "time": NSDate().transportString(),
                "data": [
                    "name": "foobar"
                ],
                "type": "conversation.rename"
                ] as [String: Any]
            let event = ZMUpdateEvent(fromEventStreamPayload: payload as ZMTransportData, uuid: nil)!
            let messageCountBeforeProcessing = self.conversation.allMessages.count
            
            // WHEN
            self.sut.processEvents([event], liveEvents: true, prefetchResult: nil)
            
            // THEN
            XCTAssertEqual(self.conversation.allMessages.count, messageCountBeforeProcessing)
        }
    }
    
    func testThatItIncludesTheAccessModeAndRoleInTheCreationPayload_Team_AllowGuests() {
        assertAccessRoleAndModeWhenInserting(allowGuests: true, expectedModes: ["invite", "code"], expectedRole: "non_activated")
    }
    
    func testThatItIncludesTheAccessModeAndRoleInTheCreationPayload_Team_NoGuests() {
        assertAccessRoleAndModeWhenInserting(allowGuests: false, expectedModes: [], expectedRole: "team")
    }
    
    func testThatItIncludesTheAccessModeAndRoleInTheCreationPayload_NoTeam_AllowGuests() {
        assertAccessRoleAndModeWhenInserting(team: false, allowGuests: true, expectedModes: nil, expectedRole: nil)
    }
    
    func testThatItIncludesTheAccessModeAndRoleInTheCreationPayload_NoTeam_NoGuests() {
        assertAccessRoleAndModeWhenInserting(team: false, allowGuests: false, expectedModes: nil, expectedRole: nil)
    }
    
    private func assertAccessRoleAndModeWhenInserting(
        team: Bool = true,
        allowGuests: Bool,
        expectedModes: [String]?,
        expectedRole: String?,
        file: StaticString = #file,
        line: UInt = #line
        ) {
        var request: ZMTransportRequest?
        let moc = syncMOC
        
        // When
        moc.performGroupedBlockAndWait {
            let team: Team? = {
                guard team else { return nil }
                let team = Team.insertNewObject(in: moc)
                team.remoteIdentifier = .create()
                let member = Member.getOrCreateMember(for: .selfUser(in: moc), in: team, context: moc)
                member.permissions = .member
                return team
            }()
            
            let conversation = ZMConversation.insertGroupConversation(into: moc, withParticipants: [], name: self.name, in: team, allowGuests: allowGuests)
            guard let inserted = conversation else { return XCTFail("no conversation", file: file, line: line) }
            XCTAssert(moc.saveOrRollback())
            
            self.sut.contextChangeTrackers.forEach {
                $0.objectsDidChange([inserted])
            }
            
            request = self.sut.nextRequestIfAllowed()
        }
        
        // Then
        guard let payload = request?.payload as? [String: Any] else { return XCTFail("no payload", file: file, line: line) }
        
        if let expectedModes = expectedModes, let expectedRole = expectedRole {
            guard let accessModes = payload["access"] as? [String] else { return XCTFail("no access modes", file: file, line: line) }
            guard let accessRole = payload["access_role"] as? String else { return XCTFail("no access role", file: file, line: line) }
            XCTAssertEqual(accessRole, expectedRole, "unexpected access role", file: file, line: line)
            XCTAssertEqual(accessModes.count, expectedModes.count, "number of modes not matching", file: file, line: line)
            expectedModes.forEach {
                XCTAssert(accessModes.contains($0), "access mode missing: \($0)", file: file, line: line)
            }
        } else {
            XCTAssertNil(payload["access_role"], file: file, line: line)
            XCTAssertNil(payload["acces"], file: file, line: line)
        }
    }
    
}

extension ZMConversationTranscoderTests_Swift : ZMSyncStateDelegate {
    
    func didStartSlowSync() {
        // nop
    }
    
    func didFinishSlowSync() {
        // nop
    }
    
    func didStartQuickSync() {
        // nop
    }
    
    func didFinishQuickSync() {
        // nop
    }
        
    func didRegister(_ userClient: UserClient!) {
        // nop
    }
    
}

// MARK: - Update events

extension ZMConversationTranscoderTests_Swift {
    
    // MARK: Receipt Mode
    
    func receiptModeUpdateEvent(enabled: Bool) -> ZMUpdateEvent {
        let payload = [
            "from": self.user.remoteIdentifier!.transportString(),
            "conversation": self.conversation.remoteIdentifier!.transportString(),
            "time": NSDate().transportString(),
            "data": ["receipt_mode": enabled ? 1 : 0],
            "type": "conversation.receipt-mode-update"
            ] as [String: Any]
        return ZMUpdateEvent(fromEventStreamPayload: payload as ZMTransportData, uuid: nil)!
    }
    
    
    func testThatItUpdatesHasReadReceiptsEnabled_WhenReceivingReceiptModeUpdateEvent() {
        self.syncMOC.performAndWait {
            // GIVEN
            let event = receiptModeUpdateEvent(enabled: true)
            
            // WHEN
            self.sut.processEvents([event], liveEvents: true, prefetchResult: nil)
            
            // THEN
            XCTAssertEqual(self.conversation.hasReadReceiptsEnabled, true)
        }
    }
    
    func testThatItInsertsSystemMessageEnabled_WhenReceivingReceiptModeUpdateEvent() {
        self.syncMOC.performAndWait {
            // GIVEN
            let event = receiptModeUpdateEvent(enabled: true)
            
            // WHEN
            self.sut.processEvents([event], liveEvents: true, prefetchResult: nil)
            
            // THEN
            guard let message = self.conversation?.lastMessage as? ZMSystemMessage else { return XCTFail() }
            XCTAssertEqual(message.systemMessageType, .readReceiptsEnabled)
        }
    }
    
    func testThatItInsertsSystemMessageDisabled_WhenReceivingReceiptModeUpdateEvent() {
        self.syncMOC.performAndWait {
            // GIVEN
            let event = receiptModeUpdateEvent(enabled: false)
            
            // WHEN
            self.sut.processEvents([event], liveEvents: true, prefetchResult: nil)
            
            // THEN
            guard let message = self.conversation?.lastMessage as? ZMSystemMessage else { return XCTFail() }
            XCTAssertEqual(message.systemMessageType, .readReceiptsDisabled)
        }
    }
    
    func testThatItDoesntInsertsSystemMessage_WhenReceivingReceiptModeUpdateEventWhichHasAlreadybeenApplied() {
        self.syncMOC.performAndWait {
            // GIVEN
            let event = receiptModeUpdateEvent(enabled: true)
            conversation.lastServerTimeStamp = event.timeStamp()
            
            // WHEN
            self.sut.processEvents([event], liveEvents: true, prefetchResult: nil)
            
            // THEN
            XCTAssertEqual(self.conversation?.allMessages.count, 0)
        }
    }
    
    // MARK: Access Mode
    
    func testThatItHandlesAccessModeUpdateEvent() {
        self.syncMOC.performAndWait {

            let newAccessMode = ConversationAccessMode(values: ["code", "invite"])
            let newAccessRole = ConversationAccessRole.team

            XCTAssertNotEqual(self.conversation.accessMode, newAccessMode)
            XCTAssertNotEqual(self.conversation.accessRole, newAccessRole)

            // GIVEN
            let payload = [
                "from": self.user.remoteIdentifier!.transportString(),
                "conversation": self.conversation.remoteIdentifier!.transportString(),
                "time": NSDate().transportString(),
                "data": [
                    "access": newAccessMode.stringValue,
                    "access_role": newAccessRole.rawValue
                ],
                "type": "conversation.access-update"
                ] as [String: Any]
            let event = ZMUpdateEvent(fromEventStreamPayload: payload as ZMTransportData, uuid: nil)!

            // WHEN
            self.sut.processEvents([event], liveEvents: true, prefetchResult: nil)

            // THEN
            XCTAssertEqual(self.conversation.accessMode, newAccessMode)
            XCTAssertEqual(self.conversation.accessRole, newAccessRole)
        }
    }
    
    // MARK: Message Timer
    
    func testThatItHandlesMessageTimerUpdateEvent_Value() {
        syncMOC.performGroupedBlockAndWait {
            XCTAssertNil(self.conversation.messageDestructionTimeout)
            
            // Given
            let payload: [String: Any] = [
                "from": self.user!.remoteIdentifier!.transportString(),
                "conversation": self.conversation!.remoteIdentifier!.transportString(),
                "time": NSDate().transportString(),
                "data": ["message_timer": 31536000000],
                "type": "conversation.message-timer-update"
                ]
            let event = ZMUpdateEvent(fromEventStreamPayload: payload as ZMTransportData, uuid: nil)!
            
            // WHEN
            self.sut?.processEvents([event], liveEvents: true, prefetchResult: nil)
            
            // THEN
            XCTAssertEqual(self.conversation?.messageDestructionTimeout!, MessageDestructionTimeout.synced(31536000))
            guard let message = self.conversation?.lastMessage as? ZMSystemMessage else { return XCTFail() }
            XCTAssertEqual(message.systemMessageType, .messageTimerUpdate)
            XCTAssertEqual(self.localNotificationDispatcher.processedMessages.last, message)
        }
    }
    
    func testThatItHandlesMessageTimerUpdateEvent_NoValue() {
        syncMOC.performGroupedBlockAndWait {
            self.conversation.messageDestructionTimeout = .synced(300)
            XCTAssertEqual(self.conversation.messageDestructionTimeout!, MessageDestructionTimeout.synced(.fiveMinutes))
            
            // Given
            let payload: [String: Any] = [
                "from": self.user!.remoteIdentifier!.transportString(),
                "conversation": self.conversation!.remoteIdentifier!.transportString(),
                "time": NSDate().transportString(),
                "data": ["message_timer": NSNull()],
                "type": "conversation.message-timer-update"
            ]
            let event = ZMUpdateEvent(fromEventStreamPayload: payload as ZMTransportData, uuid: nil)!

            // WHEN
            self.sut?.processEvents([event], liveEvents: true, prefetchResult: nil)
            
            // THEN
            XCTAssertNil(self.conversation.messageDestructionTimeout)
            guard let message = self.conversation.lastMessage as? ZMSystemMessage else { return XCTFail() }
            XCTAssertEqual(message.systemMessageType, .messageTimerUpdate)
            XCTAssertEqual(self.localNotificationDispatcher.processedMessages.last, message)
        }
    }
    
    func testThatItGeneratesCorrectSystemMessageWhenSyncedTimeoutTurnedOff() {
        // GIVEN: local & synced timeouts exist
        syncMOC.performGroupedBlockAndWait {
            self.conversation.messageDestructionTimeout = .local(.fiveMinutes)
        }
        
        syncMOC.performGroupedBlockAndWait {
            self.conversation.messageDestructionTimeout = .synced(.oneHour)
        }
        
        syncMOC.performGroupedBlockAndWait {
            XCTAssertNotNil(self.conversation.messageDestructionTimeout)
            
            // "turn off" synced timeout
            let payload: [String: Any] = [
                "from": self.user!.remoteIdentifier!.transportString(),
                "conversation": self.conversation!.remoteIdentifier!.transportString(),
                "time": NSDate().transportString(),
                "data": ["message_timer": 0],
                "type": "conversation.message-timer-update"
            ]
            
            let event = ZMUpdateEvent(fromEventStreamPayload: payload as ZMTransportData, uuid: nil)!
            
            // WHEN
            self.sut?.processEvents([event], liveEvents: true, prefetchResult: nil)
            
            // THEN: the local timeout still exists
            XCTAssertEqual(self.conversation?.messageDestructionTimeout!, MessageDestructionTimeout.local(.fiveMinutes))
            guard let message = self.conversation?.lastMessage as? ZMSystemMessage else { return XCTFail() }
            XCTAssertEqual(message.systemMessageType, .messageTimerUpdate)
            
            // but the system message timer reflects the update to the synced timeout
            XCTAssertEqual(0, message.messageTimer)
            XCTAssertEqual(self.localNotificationDispatcher.processedMessages.last, message)
        }
    }
    
    func testThatItDiscardsDoubleSystemMessageWhenSyncedTimeoutChanges_Value() {
        
        syncMOC.performGroupedBlockAndWait {
            XCTAssertNil(self.conversation.messageDestructionTimeout)
            
            // Given
            let messageTimerMillis = 31536000000
            let messageTimer = MessageDestructionTimeoutValue(rawValue: TimeInterval(messageTimerMillis / 1000))
            let selfUser = ZMUser.selfUser(in: self.syncMOC)
            selfUser.remoteIdentifier = UUID.create()
            
            let payload: [String: Any] = [
                "from": selfUser.remoteIdentifier!.transportString(),
                "conversation": self.conversation!.remoteIdentifier!.transportString(),
                "time": NSDate().transportString(),
                "data": ["message_timer": messageTimerMillis],
                "type": "conversation.message-timer-update"
            ]
            
            let event = ZMUpdateEvent(fromEventStreamPayload: payload as ZMTransportData, uuid: nil)!
            
            // WHEN
            self.sut?.processEvents([event], liveEvents: true, prefetchResult: nil) //First event
            
            XCTAssertEqual(self.conversation?.messageDestructionTimeout!, MessageDestructionTimeout.synced(messageTimer))
            guard let firstMessage = self.conversation?.lastMessage as? ZMSystemMessage else { return XCTFail() }
            XCTAssertEqual(firstMessage.systemMessageType, .messageTimerUpdate)
            XCTAssertEqual(self.localNotificationDispatcher.processedMessages.last, firstMessage)
            
            self.sut?.processEvents([event], liveEvents: true, prefetchResult: nil) //Second duplicated event
            
            // THEN
            XCTAssertEqual(self.conversation?.messageDestructionTimeout!, MessageDestructionTimeout.synced(messageTimer))
            guard let secondMessage = self.conversation?.lastMessage as? ZMSystemMessage else { return XCTFail() }
            XCTAssertEqual(firstMessage, secondMessage) //Check that no other messages are appended in the conversation
        }
    }
    
    func testThatItDiscardsDoubleSystemMessageWhenSyncedTimeoutChanges_NoValue() {
        
        syncMOC.performGroupedBlockAndWait {
            XCTAssertNil(self.conversation.messageDestructionTimeout)
            
            // Given
            let valuedMessageTimerMillis = 31536000000
            let valuedMessageTimer = MessageDestructionTimeoutValue(rawValue: TimeInterval(valuedMessageTimerMillis / 1000))
            
            let selfUser = ZMUser.selfUser(in: self.syncMOC)
            selfUser.remoteIdentifier = UUID.create()
            
            let valuedPayload: [String: Any] = [
                "from": selfUser.remoteIdentifier!.transportString(),
                "conversation": self.conversation!.remoteIdentifier!.transportString(),
                "time": NSDate(timeIntervalSinceNow: 0).transportString(),
                "data": ["message_timer": valuedMessageTimerMillis],
                "type": "conversation.message-timer-update"
            ]
            
            let payload: [String: Any] = [
                "from": selfUser.remoteIdentifier!.transportString(),
                "conversation": self.conversation!.remoteIdentifier!.transportString(),
                "time": NSDate(timeIntervalSinceNow: 100).transportString(),
                "data": ["message_timer": 0],
                "type": "conversation.message-timer-update"
            ]
            
            let valuedEvent = ZMUpdateEvent(fromEventStreamPayload: valuedPayload as ZMTransportData, uuid: nil)!
            let event = ZMUpdateEvent(fromEventStreamPayload: payload as ZMTransportData, uuid: nil)!
            
            // WHEN
            
            //First event with valued timer
            self.sut?.processEvents([valuedEvent], liveEvents: true, prefetchResult: nil)
            XCTAssertEqual(self.conversation?.messageDestructionTimeout!, MessageDestructionTimeout.synced(valuedMessageTimer))
            
            //Second event with timer = nil
            self.sut?.processEvents([event], liveEvents: true, prefetchResult: nil)
            XCTAssertNil(self.conversation?.messageDestructionTimeout)
        
            guard let firstMessage = self.conversation?.lastMessage as? ZMSystemMessage else { return XCTFail() }
            XCTAssertEqual(firstMessage.systemMessageType, .messageTimerUpdate)
            XCTAssertEqual(self.localNotificationDispatcher.processedMessages.last, firstMessage)
        
            //Third event with timer = nil
            self.sut?.processEvents([event], liveEvents: true, prefetchResult: nil)
            
            // THEN
            XCTAssertNil(self.conversation?.messageDestructionTimeout)
            guard let secondMessage = self.conversation?.lastMessage as? ZMSystemMessage else { return XCTFail() }
            XCTAssertEqual(firstMessage, secondMessage) //Check that no other messages are appended in the conversation
        }
    }
    
    // MARK: Conversation deletion
    
    func testThatItHandlesConversationDeletedUpdateEvent() {
        
        syncMOC.performAndWait {
            let selfUser = ZMUser.selfUser(in: self.syncMOC)
            selfUser.remoteIdentifier = UUID.create()
            
            // GIVEN
            let payload: [String: Any] = [
                "from": selfUser.remoteIdentifier!.transportString(),
                "conversation": self.conversation!.remoteIdentifier!.transportString(),
                "time": NSDate(timeIntervalSinceNow: 100).transportString(),
                "data": NSNull(),
                "type": "conversation.delete"
            ]
            
            // WHEN
            let event = ZMUpdateEvent(fromEventStreamPayload: payload as ZMTransportData, uuid: nil)!
            self.sut?.processEvents([event], liveEvents: true, prefetchResult: nil)
            
            // THEN
            XCTAssertTrue(self.conversation.isDeleted)
        }
    }
}


