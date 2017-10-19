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
    
    func createUser() -> ZMUser {
        let user = ZMUser.insertNewObject(in: self.uiMOC)
        user.remoteIdentifier = UUID()
        return user
    }
    
    func createConversation() -> ZMConversation {
        let conversation = ZMConversation.insertNewObject(in: self.uiMOC)
        conversation.remoteIdentifier = UUID()
        return conversation
    }
    
    func createTeam() -> Team {
        let team = Team.insertNewObject(in: self.uiMOC)
        team.remoteIdentifier = UUID()
        return team
    }
    
    func createMembership() -> Member {
        let member = Member.insertNewObject(in: self.uiMOC)
        return member
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
    
    public func testThatItMergesTwoUsers() {
        // GIVEN
        let user1 = createUser()
        let user2 = createUser()
        user2.remoteIdentifier = user1.remoteIdentifier
        
        let team = createTeam()
        let membership = createMembership()
        let reaction = Reaction.insertNewObject(in: self.uiMOC)
        let systemMessage = ZMSystemMessage.insertNewObject(in: self.uiMOC)
        
        let lastServerSyncedActiveConversations = NSOrderedSet(object: conversation)
        let conversationsCreated = Set<ZMConversation>([conversation])
        let createdTeams = Set<Team>([team])
        let reactions = Set<Reaction>([reaction])
        let showingUserAdded = Set<ZMSystemMessage>([systemMessage])
        let showingUserRemoved = Set<ZMSystemMessage>([systemMessage])
        let systemMessages = Set<ZMSystemMessage>([systemMessage])
        let connection = ZMConnection.insertNewObject(in: self.uiMOC)
        let addressBoookEntry = AddressBookEntry.insertNewObject(in: self.uiMOC)
        
        user2.setValue(lastServerSyncedActiveConversations, forKey: "lastServerSyncedActiveConversations")
        user2.setValue(conversationsCreated, forKey: "conversationsCreated")
        user2.createdTeams = createdTeams
        user2.connection = connection
        user2.addressBookEntry = addressBoookEntry
        user2.setValue(membership, forKey: "membership")
        user2.setValue(reactions, forKey: "reactions")
        user2.setValue(showingUserAdded, forKey: "showingUserAdded")
        user2.setValue(showingUserRemoved, forKey: "showingUserRemoved")
        user2.setValue(systemMessages, forKey: "systemMessages")
        
        // WHEN
        user1.merge(with: user2)
        uiMOC.delete(user2)
        uiMOC.saveOrRollback()
        
        // THEN
        XCTAssertEqual(user1.activeConversations, lastServerSyncedActiveConversations)
        XCTAssertEqual(user1.value(forKey: "conversationsCreated") as! Set<NSManagedObject>, conversationsCreated)
        XCTAssertEqual(user1.createdTeams, createdTeams)
        XCTAssertEqual(user1.membership, membership)
        XCTAssertEqual(user1.connection, connection)
        XCTAssertEqual(user1.addressBookEntry, addressBoookEntry)
        XCTAssertEqual(user1.value(forKey: "reactions") as! Set<NSManagedObject>, reactions)
        XCTAssertEqual(user1.value(forKey: "showingUserAdded") as! Set<NSManagedObject>, showingUserAdded)
        XCTAssertEqual(user1.value(forKey: "showingUserRemoved") as! Set<NSManagedObject>, showingUserRemoved)
        XCTAssertEqual(user1.value(forKey: "systemMessages") as! Set<NSManagedObject>, systemMessages)
    }
    
    public func testThatItMergesTwoConversations() {
        // GIVEN
        let conversation1 = createConversation()
        let conversation2 = createConversation()
        conversation1.remoteIdentifier = conversation2.remoteIdentifier
        
        let message1 = ZMClientMessage.insertNewObject(in: self.uiMOC)
        let message2 = ZMClientMessage.insertNewObject(in: self.uiMOC)
        
        let messages = NSOrderedSet(arrayLiteral: message1)
        let hiddenMessages = NSOrderedSet(arrayLiteral: message2)
        
        conversation2.setValue(messages, forKey: "messages")
        conversation2.setValue(hiddenMessages, forKey: "hiddenMessages")
        
        // WHEN
        conversation1.merge(with: conversation2)
        uiMOC.delete(conversation2)
        uiMOC.saveOrRollback()
        
        // THEN
        XCTAssertEqual(conversation1.messages, messages)
        XCTAssertEqual(conversation1.hiddenMessages, hiddenMessages)
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
    
    func createClient() -> UserClient {
        let client = UserClient.insertNewObject(in: self.moc)
        client.remoteIdentifier = UUID().transportString()
        client.user = user
        return client
    }
    
    func createUser() -> ZMUser {
        let user = ZMUser.insertNewObject(in: self.moc)
        user.remoteIdentifier = UUID()
        return user
    }
    
    func createConversation() -> ZMConversation {
        let conversation = ZMConversation.insertNewObject(in: self.moc)
        conversation.remoteIdentifier = UUID()
        return conversation
    }
    
    public func testThatItRemovesDuplicatedClients() {
        // GIVEN
        let client1 = createClient()
        let duplicates: [UserClient] = (0..<5).map { _ in
            let otherClient = createClient()
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
    
    public func testThatItRemovesDuplicatedUsers() {
        // GIVEN
        let user1 = createUser()
        let duplicates: [ZMUser] = (0..<5).map { _ in
            let otherUser = createUser()
            otherUser.remoteIdentifier = user1.remoteIdentifier
            return otherUser
        }
        
        self.moc.saveOrRollback()
        
        // WHEN
        ZMHotFixDirectory.deleteDuplicatedUsers(in: self.moc)
        self.moc.saveOrRollback()
        
        // THEN
        let totalDeleted = (duplicates + [user1]).filter {
            $0.managedObjectContext == nil
            }.count
        
        XCTAssertEqual(totalDeleted, 5)
    }
    
    public func testThatItRemovesDuplicatedConversations() {
        // GIVEN
        let conversation1 = createConversation()
        let duplicates: [ZMConversation] = (0..<5).map { _ in
            let otherConversation = createConversation()
            otherConversation.remoteIdentifier = conversation1.remoteIdentifier
            return otherConversation
        }
        
        self.moc.saveOrRollback()
        
        // WHEN
        ZMHotFixDirectory.deleteDuplicatedConversations(in: self.moc)
        self.moc.saveOrRollback()
        
        // THEN
        let totalDeleted = (duplicates + [conversation1]).filter {
            $0.managedObjectContext == nil
            }.count
        
        XCTAssertEqual(totalDeleted, 5)
    }
}
