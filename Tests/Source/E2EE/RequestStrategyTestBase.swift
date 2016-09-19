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

import Foundation

extension ZMContextChangeTrackerSource {
    func notifyChangeTrackers(_ client : UserClient) {
        contextChangeTrackers.forEach{$0.objectsDidChange(Set(arrayLiteral:client))}
    }
}


class RequestStrategyTestBase : MessagingTest {
    
    func generatePrekeyAndLastKey(_ selfClient: UserClient, count: UInt16 = 2) -> (prekeys: [String], lastKey: String) {
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
    
    func createRemoteClient(_ preKeys: [String]?, lastKey: String?) -> UserClient {
        
        var mockUser: MockUser!
        var mockClient: MockUserClient!
        
        self.mockTransportSession.performRemoteChanges { (session) -> Void in
            if let session = session as? MockTransportSessionObjectCreation {
                mockUser = session.insertUser(withName: "foo")
                if let preKeys = preKeys, let lastKey = lastKey {
                    mockClient = session.registerClient(for: mockUser, label: mockUser.name, type: "permanent", preKeys: preKeys, lastPreKey: lastKey)
                }
                else {
                    mockClient = session.registerClient(for: mockUser, label: mockUser.name, type: "permanent")
                }
            }
        }
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        let client = UserClient.insertNewObject(in: syncMOC)
        client.remoteIdentifier = mockClient.identifier
        let user = ZMUser.insertNewObject(in: syncMOC)
        user.remoteIdentifier = UUID.uuid(transport: mockUser.identifier)
        client.user = user
        return client
    }
}

