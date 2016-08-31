//
//  RequestStrategyTestType.swift
//  zmessaging-cocoa
//
//  Created by Sabine Geithner on 30/08/16.
//  Copyright © 2016 Zeta Project Gmbh. All rights reserved.
//

import Foundation

extension ZMContextChangeTrackerSource {
    func notifyChangeTrackers(client : UserClient) {
        contextChangeTrackers.forEach{$0.objectsDidChange(Set(arrayLiteral:client))}
    }
}


class RequestStrategyTestBase : MessagingTest {
    
    func generatePrekeyAndLastKey(selfClient: UserClient, count: UInt16 = 2) -> (prekeys: [String], lastKey: String) {
        var preKeys : [String] = []
        var lastKey : String = ""
        selfClient.keysStore.encryptionContext.perform { (sessionsDirectory) in
            preKeys = try! sessionsDirectory.generatePrekeys(Range(0..<count)).map{ $0.prekey }
            lastKey = try! sessionsDirectory.generateLastPrekey()
        }
        return (preKeys, lastKey)
    }
    
    func createClients() -> (UserClient, UserClient) {
        let selfClient = self.createSelfClient()
        let (prekeys, lastKey) = generatePrekeyAndLastKey(selfClient)
        let otherClient = createRemoteClient(prekeys, lastKey: lastKey)
        return (selfClient, otherClient)
    }
    
    func createRemoteClient(preKeys: [String]?, lastKey: String?) -> UserClient {
        
        var mockUser: MockUser!
        var mockClient: MockUserClient!
        
        self.mockTransportSession.performRemoteChanges { (session) -> Void in
            if let session = session as? MockTransportSessionObjectCreation {
                mockUser = session.insertUserWithName("foo")
                if let preKeys = preKeys, lastKey = lastKey {
                    mockClient = session.registerClientForUser(mockUser, label: mockUser.name, type: "permanent", preKeys: preKeys, lastPreKey: lastKey)
                }
                else {
                    mockClient = session.registerClientForUser(mockUser, label: mockUser.name, type: "permanent")
                }
            }
        }
        XCTAssertTrue(waitForAllGroupsToBeEmptyWithTimeout(0.5))
        
        let client = UserClient.insertNewObjectInManagedObjectContext(syncMOC)
        client.remoteIdentifier = mockClient.identifier
        let user = ZMUser.insertNewObjectInManagedObjectContext(syncMOC)
        user.remoteIdentifier = NSUUID.uuidWithTransportString(mockUser.identifier)
        client.user = user
        return client
    }
}

