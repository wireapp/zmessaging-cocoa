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

import Foundation
import XCTest
import WireTesting
import WireDataModel
@testable import WireSyncEngine

public final class HotFixDuplicatesTests: MessagingTest {
    
    var conversation: ZMConversation!
    var user: ZMUser!
    
    override public func setUp() {
        super.setUp()
        conversation = ZMConversation.insertNewObject(in: self.uiMOC)
        conversation.remoteIdentifier = UUID()
        
        user = ZMUser.insertNewObject(in: self.uiMOC)
        user.remoteIdentifier = UUID()
        user.name = "Test user"
        conversation.internalAddParticipants(Set(arrayLiteral: user), isAuthoritative: true)
    }
    
    override public func tearDown() {
        self.user = nil
        self.conversation = nil
        super.tearDown()
    }

    func client() -> UserClient {
        let client = UserClient.insertNewObject(in: self.uiMOC)
        client.user = user
        client.remoteIdentifier = UUID().transportString()
        return client
    }
    
    
    func appendSystemMessage(type: ZMSystemMessageType,
                                      sender: ZMUser,
                                      users: Set<ZMUser>?,
                                      addedUsers: Set<ZMUser> = Set(),
                                      clients: Set<UserClient>?,
                                      timestamp: Date?,
                                      duration: TimeInterval? = nil
        ) -> ZMSystemMessage {
        
        let systemMessage = ZMSystemMessage.insertNewObject(in: self.uiMOC)
        systemMessage.systemMessageType = type
        systemMessage.sender = sender
        systemMessage.isEncrypted = false
        systemMessage.isPlainText = true
        systemMessage.users = users ?? Set()
        systemMessage.addedUsers = addedUsers
        systemMessage.clients = clients ?? Set()
        systemMessage.nonce = UUID()
        systemMessage.serverTimestamp = timestamp
        if let duration = duration {
            systemMessage.duration = duration
        }
        
        conversation.sortedAppendMessage(systemMessage)
        systemMessage.visibleInConversation = conversation
        return systemMessage
    }
    
    func addedOrRemovedSystemMessages(client: UserClient) -> [ZMSystemMessage] {
        let addedMessage = self.appendSystemMessage(type: .newClient,
                                                                 sender: ZMUser.selfUser(in: self.uiMOC),
                                                                 users: Set(arrayLiteral: user),
                                                                 addedUsers: Set(arrayLiteral: user),
                                                                 clients: Set(arrayLiteral: client),
                                                                 timestamp: Date())

        let ignoredMessage = self.appendSystemMessage(type: .ignoredClient,
                                                                   sender: ZMUser.selfUser(in: self.uiMOC),
                                                                   users: Set(arrayLiteral: user),
                                                                   clients: Set(arrayLiteral: client),
                                                                   timestamp: Date())
        
        return [addedMessage, ignoredMessage]
    }
    
    func messages() -> [ZMMessage] {
        return (0..<5).map { conversation.appendMessage(withText: "Message \($0)")! as! ZMMessage }
    }
    
    public func testThatItMergesTwoUserClients() {
        // GIVEN
        let client1 = client()
        
        let client2 = client()
        client2.remoteIdentifier = client1.remoteIdentifier
        
        let addedOrRemovedInSystemMessages = Set<ZMSystemMessage>(addedOrRemovedSystemMessages(client: client2))
        let ignoredByClients = Set((0..<5).map { _ in client() })
        let messagesMissingRecipient = Set<ZMMessage>(messages())
        let trustedByClients = Set((0..<5).map { _ in client() })
        let missedByClient = client()
        
        client2.addedOrRemovedInSystemMessages = addedOrRemovedInSystemMessages
        client2.ignoredByClients = ignoredByClients
        client2.messagesMissingRecipient = messagesMissingRecipient
        client2.trustedByClients = trustedByClients
        client2.missedByClient = missedByClient
        
        // WHEN
        client1.merge(with: client2)
        uiMOC.delete(client2)
        uiMOC.saveOrRollback()
        
        // THEN
        XCTAssertEqual(addedOrRemovedInSystemMessages.count, 2)
        
        XCTAssertEqual(client1.addedOrRemovedInSystemMessages, addedOrRemovedInSystemMessages)
        XCTAssertEqual(client1.ignoredByClients, ignoredByClients)
        XCTAssertEqual(client1.messagesMissingRecipient, messagesMissingRecipient)
        XCTAssertEqual(client1.trustedByClients, trustedByClients)
        XCTAssertEqual(client1.missedByClient, missedByClient)
        
        addedOrRemovedInSystemMessages.forEach {
            XCTAssertTrue($0.clients.contains(client1))
            XCTAssertFalse($0.clients.contains(client2))
        }
    }

}

public final class HotFixDuplicatesTests_DiskDatabase: DiskDatabaseTest {
    
    var user: ZMUser!
    
    override public func setUp() {
        super.setUp()

        user = ZMUser.insertNewObject(in: self.moc)
        user.remoteIdentifier = UUID()
        user.name = "Test user"
    }
    
    override public func tearDown() {
        user = nil
        super.tearDown()
    }
    
    func client() -> UserClient {
        let client = UserClient.insertNewObject(in: self.moc)
        client.remoteIdentifier = UUID().transportString()
        client.user = user
        return client
    }
    
    public func testThatItRemovesDuplicatedClients() {
        // GIVEN
        let client1 = client()
        let duplicates: [UserClient] = (0..<5).map { _ in
            let otherClient = client()
            otherClient.remoteIdentifier = client1.remoteIdentifier
            return otherClient
        }
        
        self.moc.saveOrRollback()
        
        // WHEN
        ZMHotFixDirectory.deleteDuplicatedClients(in: self.moc)
        self.moc.saveOrRollback()
        
        // THEN
        let totalDeleted = (duplicates + [client1]).filter {
            $0.managedObjectContext == nil
        }.count
        
        XCTAssertEqual(totalDeleted, 5)
    }
}
