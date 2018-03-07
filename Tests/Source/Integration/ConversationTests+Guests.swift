////
// Wire
// Copyright (C) 2018 Wire Swiss GmbH
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

class ConversationTests_Guests : TeamTests {

    override func setUp() {
        super.setUp()
        createTeamAndConversations()
    }

    func createConversation(in team: MockTeam) -> MockConversation {
        var result: MockConversation!
        mockTransportSession.performRemoteChanges({ session in

            let teamConversation = session.insertGroupConversation(withSelfUser:self.selfUser, otherUsers: [self.user1])
            teamConversation.team = team
            teamConversation.creator = self.selfUser
            teamConversation.changeName(by:self.selfUser, name:"Team Group conversation")
            result = teamConversation
        })
        
        return result
    }
    
    func testThatItSendsRequestToChangeAccessMode() {
        // given
        let mockTeam = remotelyInsertTeam(members: [self.selfUser, self.user1])
        let mockConversation = self.createConversation(in: mockTeam)
        XCTAssert(login())
        
        let conversation = self.conversation(for: mockConversation)!
        
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.1))
        XCTAssertFalse(conversation.allowGuests)
        mockTransportSession?.resetReceivedRequests()

        // when
        conversation.setAllowGuests(true, in: self.userSession!) { result in
            switch result {
            case .success:
                break
            case .failure:
                XCTFail()
            }
        }
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.1))

        // then
        XCTAssertTrue(conversation.allowGuests)
        XCTAssertEqual(mockTransportSession.receivedRequests().count, 1)
        guard let request = mockTransportSession.receivedRequests().first else { return }
        XCTAssertEqual(request.path, "/conversations/\(conversation.remoteIdentifier!.transportString())/access")
    }

    func testThatAccessModeChangeEventIsHandled() {
        // given
        XCTAssert(login())

        let conversation = self.conversation(for: self.groupConversationWithWholeTeam!)!
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.1))
        XCTAssertFalse(conversation.allowGuests)

        // when
        mockTransportSession?.performRemoteChanges { session in
            self.groupConversationWithWholeTeam.set(allowGuests: true)
        }
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.1))

        // then
        XCTAssertTrue(conversation.allowGuests)
    }
}
