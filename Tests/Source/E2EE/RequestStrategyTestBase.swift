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
    
    func createClients() -> (UserClient, UserClient) {
        let selfClient = self.createSelfClient()
        return (selfClient, createRemoteClient())
    }
    
    func createRemoteClient() -> UserClient {
        
        var mockUser: MockUser!
        var mockClient: MockUserClient!
        
        self.mockTransportSession.performRemoteChanges { (session) -> Void in
            mockUser = session.insertUser(withName: "foo")
            mockClient = session.registerClient(for: mockUser, label: mockUser.name!, type: "permanent")
        }
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        let client = UserClient.insertNewObject(in: syncMOC)
        client.remoteIdentifier = mockClient.identifier
        let user = ZMUser.insertNewObject(in: syncMOC)
        user.remoteIdentifier = UUID(uuidString: mockUser.identifier)
        client.user = user
        return client
    }
}

