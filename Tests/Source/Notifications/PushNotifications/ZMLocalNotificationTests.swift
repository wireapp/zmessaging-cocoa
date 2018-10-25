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

class ZMLocalNotificationTests: MessagingTest {
    
    var sender: ZMUser!
    var selfUser: ZMUser!
    var otherUser1: ZMUser!
    var otherUser2: ZMUser!
    var userWithNoName: ZMUser!
    var oneOnOneConversation: ZMConversation!
    var groupConversation: ZMConversation!
    var groupConversationWithoutUserDefinedName: ZMConversation!
    var groupConversationWithoutName: ZMConversation!
    var invalidConversation: ZMConversation!
    
    override func setUp() {
        super.setUp()
        sender = insertUser(with: UUID.create(), name: "Super User")
        otherUser1 = insertUser(with: UUID.create(), name: "Other User1")
        otherUser2 = insertUser(with: UUID.create(), name: "Other User2")
        userWithNoName = insertUser(with: UUID.create(), name: nil)
        oneOnOneConversation = insertConversation(with: UUID.create(), name: "Super Conversation", type: .oneOnOne, mutedMessages: .none)
        groupConversation = insertConversation(with: UUID.create(), name: "Super Conversation", type: .group, mutedMessages: .none)
        
        // an empty conversation will have no meaninful display name
        groupConversationWithoutName = insertConversation(with: UUID.create(), name: nil, type: .group, mutedMessages: .none, isEmpty: true)
        groupConversationWithoutUserDefinedName = insertConversation(with: UUID.create(), name: nil, type: .group, mutedMessages: .none)
        invalidConversation = insertConversation(with: UUID.create(), name: nil, type: .invalid, mutedMessages: .none)

        syncMOC.performGroupedBlockAndWait {
            self.selfUser = ZMUser.selfUser(in: self.syncMOC)
            self.selfUser.remoteIdentifier = UUID.create()
            self.syncMOC.saveOrRollback()
        }
    }
    
    override func tearDown() {
        sender = nil
        otherUser1 = nil
        otherUser2 = nil
        userWithNoName = nil
        oneOnOneConversation = nil
        groupConversation = nil
        groupConversationWithoutName = nil
        groupConversationWithoutUserDefinedName = nil
        invalidConversation = nil
        selfUser.remoteIdentifier = nil
        super.tearDown()
    }
    
    // MARK: - Helpers
    
    func insertUser(with remoteID: UUID, name: String?) -> ZMUser {
        var user: ZMUser!
        syncMOC.performGroupedBlockAndWait {
            user = ZMUser.insertNewObject(in: self.syncMOC)
            user.name = name
            user.remoteIdentifier = remoteID
            self.syncMOC.saveOrRollback()
        }
        return user
    }
    
    func insertConversation(with remoteID: UUID, name: String?, type: ZMConversationType, mutedMessages: MutedMessageTypes, isEmpty: Bool = false) -> ZMConversation {
        var conversation: ZMConversation!
        syncMOC.performGroupedBlockAndWait {
            conversation = ZMConversation.insertNewObject(in: self.syncMOC)
            conversation.remoteIdentifier = remoteID
            conversation.userDefinedName = name
            conversation.conversationType = type
            conversation.mutedMessageTypes = mutedMessages
            conversation.lastServerTimeStamp = Date()
            conversation.lastReadServerTimeStamp = conversation.lastServerTimeStamp
            if !isEmpty { conversation.mutableLastServerSyncedActiveParticipants.addObjects(from: [self.sender, self.otherUser1]) }
            self.syncMOC.saveOrRollback()
        }
        return conversation
    }
    
    func noteWithPayload(_ data: NSDictionary?, fromUserID: UUID?, in conversation: ZMConversation, type: String) -> ZMLocalNotification? {
        var note: ZMLocalNotification?
        syncMOC.performGroupedBlockAndWait {
            let payload = self.payloadForEvent(in: conversation, type: type, data: data, from: fromUserID)
            if let event = ZMUpdateEvent(fromEventStreamPayload: payload, uuid: nil) {
                note = ZMLocalNotification(event: event, conversation: conversation, managedObjectContext: self.syncMOC)
            }
        }
        return note
    }
    
    func noteWithPayload(_ data: NSDictionary?, from user: ZMUser, in conversation: ZMConversation, type: String) -> ZMLocalNotification? {
        return noteWithPayload(data, fromUserID: user.remoteIdentifier, in: conversation, type: type)
    }
    
    func payloadForEvent(in conversation: ZMConversation, type: String, data: NSDictionary?, from userID: UUID?) -> NSMutableDictionary {
        let userRemoteID = userID ?? UUID.create()
        let convRemoteID = conversation.remoteIdentifier ?? UUID.create()
        let serverTimeStamp = conversation.lastReadServerTimeStamp?.addingTimeInterval(5) ?? Date()
        
        return NSMutableDictionary(dictionary: [
            "conversation" : convRemoteID.transportString(),
            "data" : data ?? [:],
            "from" : userRemoteID.transportString(),
            "type" : type,
            "time" : serverTimeStamp.transportString()
        ]).mutableCopy() as! NSMutableDictionary
    }
}
