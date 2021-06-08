//
// Wire
// Copyright (C) 2019 Wire Swiss GmbH
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

class ConversationTests_Join: ConversationTestsBase {
    
    func testThatTheUserJoinsAConversation_OnSuccessfulResponse() {
        // GIVEN
        XCTAssert(login())

        let uuid = UUID.create()
        let connectedUser = user(for: self.selfUser)!
        let newConversation = ZMConversation.fetch(withRemoteIdentifier: uuid, in: connectedUser.managedObjectContext!)
        XCTAssertNil(newConversation)

        mockTransportSession.responseGeneratorBlock = {[weak self] request in
            guard request.path == "/conversations/join" else { return nil }

            self?.mockTransportSession.responseGeneratorBlock = nil
            let responsePayload = [
                "conversation" : uuid.transportString(),
                "type" : "conversation.member-join",
                "time" : NSDate().transportString(),
                "data": [
                    "users" : [
                        [
                            "conversation_role": "wire_member",
                            "id": connectedUser.remoteIdentifier.transportString()
                        ]
                    ],
                    "user_ids": [
                        connectedUser.remoteIdentifier.transportString()
                    ]
                ],
                "from" :connectedUser.remoteIdentifier.transportString()] as ZMTransportData

            return ZMTransportResponse(payload: responsePayload, httpStatus: 200, transportSessionError: nil)
        }

        // WHEN
        ZMConversation.join(key: "test-key",
                            code: "test-code",
                            userSession: userSession!,
                            managedObjectContext: connectedUser.managedObjectContext!,
                            completion: { _ in })
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))

        // THEN
        let conversation = ZMConversation.fetch(withRemoteIdentifier: uuid, in: connectedUser.managedObjectContext!)
        XCTAssertNotNil(conversation)
        XCTAssertTrue(conversation!.localParticipants.contains(connectedUser))
    }

    func testThatTheUserDoesNotJoinAConversation_OnFailureResponse() {
        // GIVEN
        XCTAssert(login())
        let connectedUser = user(for: self.selfUser)!

        mockTransportSession.responseGeneratorBlock = {[weak self] request in
            guard request.path == "/conversations/join" else { return nil }

            self?.mockTransportSession.responseGeneratorBlock = nil

            return ZMTransportResponse(payload: nil, httpStatus: 404, transportSessionError: nil)
        }

        // WHEN
        let conversationJoiningFailed = expectation(description: "Failed to join the conversation")
        ZMConversation.join(key: "test-key",
                            code: "test-code",
                            userSession: userSession!,
                            managedObjectContext: connectedUser.managedObjectContext!,
                            completion: { result in
                                // THEN
                                if case .failure = result {
                                    conversationJoiningFailed.fulfill()
                                } else {
                                    XCTFail()
                                }
                            })
    }

    func testThatTheUserIsAParticipantInTheConversation() {
        // GIVEN
        XCTAssert(login())
        let connectedUser = user(for: self.selfUser)!

        mockTransportSession.responseGeneratorBlock = {[weak self] request in
            guard request.path == "/conversations/join" else { return nil }

            self?.mockTransportSession.responseGeneratorBlock = nil

            return ZMTransportResponse(payload: nil, httpStatus: 204, transportSessionError: nil)
        }

        // WHEN
        let userIsParticipant = expectation(description: "The user was already a participant in the conversation")
        ZMConversation.join(key: "test-key",
                            code: "test-code",
                            userSession: userSession!,
                            managedObjectContext: connectedUser.managedObjectContext!,
                            completion: { result in
                                // THEN
                                if case .success = result {
                                    userIsParticipant.fulfill()
                                } else {
                                    XCTFail()
                                }
                            })
    }


}
