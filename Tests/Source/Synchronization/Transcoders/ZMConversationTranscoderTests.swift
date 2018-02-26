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
import WireMessageStrategy
import WireDataModel

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
            guard let message = self.conversation.messages.lastObject as? ZMSystemMessage else {
                XCTFail()
                return
            }
            XCTAssertEqual(message.systemMessageType, .participantsAdded)
            XCTAssertEqual(self.localNotificationDispatcher.processedMessages.last, message)
        }
    }
    
    func testThatItCreatesAndNotifiesSystemMessagesIfMemberIsAlreadyPartOfConversationButNotYetSynced() {
        
        self.syncMOC.performAndWait {
            
            // GIVEN
            conversation.setLocallyModifiedKeys(Set<AnyHashable>([ZMConversationUnsyncedActiveParticipantsKey]))
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
            guard let message = self.conversation.messages.lastObject as? ZMSystemMessage else {
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
            self.conversation.internalAddParticipants(Set<ZMUser>([user]), isAuthoritative: true)
            
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
            let messageCountBeforeProcessing = self.conversation.messages.count
            
            // WHEN
            self.sut.processEvents([event], liveEvents: true, prefetchResult: nil)
            
            // THEN
            XCTAssertEqual(self.conversation.messages.count, messageCountBeforeProcessing)
        }
    }
    
    func testThatItCreatesAndNotifiesSystemMessagesFromAMemberRemove() {
        
        self.syncMOC.performAndWait {
            
            // GIVEN
            self.conversation.internalAddParticipants(Set<ZMUser>([user]), isAuthoritative: true)
            
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
            guard let message = self.conversation.messages.lastObject as? ZMSystemMessage else {
                XCTFail()
                return
            }
            XCTAssertEqual(message.systemMessageType, .participantsRemoved)
            XCTAssertEqual(self.localNotificationDispatcher.processedMessages.last, message)
        }
    }
    
    func testThatItCreatesAndNotifiesSystemMessagesIfMemberIsNotPartOfConversationButYetNotSynced() {
        
        self.syncMOC.performAndWait {
            
            // GIVEN
            conversation.setLocallyModifiedKeys(Set<AnyHashable>([ZMConversationUnsyncedInactiveParticipantsKey]))
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
            guard let message = self.conversation.messages.lastObject as? ZMSystemMessage else {
                XCTFail()
                return
            }
            XCTAssertEqual(message.systemMessageType, .participantsRemoved)
            XCTAssertEqual(self.localNotificationDispatcher.processedMessages.last, message)
        }
    }
    
    func testThatItCreatesAndNotifiesSystemMessagesISelfUserIsNotPartOfConversationButYetNotSynced() {
        
        self.syncMOC.performAndWait {
            
            // GIVEN
            let selfUser = ZMUser.selfUser(in: syncMOC)
            selfUser.remoteIdentifier = UUID()
            conversation.internalRemoveParticipants(Set<ZMUser>([selfUser]), sender: selfUser)
            conversation.setLocallyModifiedKeys(Set<AnyHashable>([ZMConversationIsSelfAnActiveMemberKey]))
            
            let payload = [
                "from": selfUser.remoteIdentifier!.transportString(),
                "conversation": self.conversation.remoteIdentifier!.transportString(),
                "time": NSDate().transportString(),
                "data": [
                    "user_ids": [selfUser.remoteIdentifier!.transportString()]
                ],
                "type": "conversation.member-leave"
                ] as [String: Any]
            let event = ZMUpdateEvent(fromEventStreamPayload: payload as ZMTransportData, uuid: nil)!
            
            // WHEN
            self.sut.processEvents([event], liveEvents: true, prefetchResult: nil)
            
            // THEN
            guard let message = self.conversation.messages.lastObject as? ZMSystemMessage else {
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
            let messageCountBeforeProcessing = self.conversation.messages.count
            
            // WHEN
            self.sut.processEvents([event], liveEvents: true, prefetchResult: nil)
            
            // THEN
            XCTAssertEqual(self.conversation.messages.count, messageCountBeforeProcessing)
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
            guard let message = self.conversation.messages.lastObject as? ZMSystemMessage else {
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
            guard let message = self.conversation.messages.lastObject as? ZMSystemMessage else {
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
            let messageCountBeforeProcessing = self.conversation.messages.count
            
            // WHEN
            self.sut.processEvents([event], liveEvents: true, prefetchResult: nil)
            
            // THEN
            XCTAssertEqual(self.conversation.messages.count, messageCountBeforeProcessing)
        }
    }
    
}

extension ZMConversationTranscoderTests_Swift : ZMSyncStateDelegate {
    
    func didStartSync() {
        // nop
    }
    
    func didFinishSync() {
        // nop
    }
    
    func didRegister(_ userClient: UserClient!) {
        // nop
    }
    
}

// MARK: - Update events
extension ZMConversationTranscoderTests_Swift {
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
}


