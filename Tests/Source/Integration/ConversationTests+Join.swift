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

    func testConversationJoin_WhenTheSelfUserJoinsAConversation_OnSuccessfulResponse() {
        // GIVEN
        XCTAssert(login())

        // Convert MockUser -> ZMUser
        let selfUser_zmUser = user(for: self.selfUser)!

        let uuid = UUID.create()
        let newConversation = ZMConversation.fetch(withRemoteIdentifier: uuid, in: selfUser_zmUser.managedObjectContext!)
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
                            "id": selfUser_zmUser.remoteIdentifier.transportString()
                        ]
                    ],
                    "user_ids": [
                        selfUser_zmUser.remoteIdentifier.transportString()
                    ]
                ],
                "from": selfUser_zmUser.remoteIdentifier.transportString()] as ZMTransportData

            return ZMTransportResponse(payload: responsePayload, httpStatus: 200, transportSessionError: nil)
        }

        // WHEN
        /// Key and code values don't affect the test result, because the result is mocked
        ZMConversation.join(key: "test-key",
                            code: "test-code",
                            userSession: userSession!,
                            managedObjectContext: self.selfUser.managedObjectContext!,
                            completion: { _ in })
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))

        // THEN
        let conversation = ZMConversation.fetch(withRemoteIdentifier: uuid, in: selfUser_zmUser.managedObjectContext!)
        XCTAssertNotNil(conversation)
        XCTAssertTrue(conversation!.localParticipants.contains(user(for: self.selfUser)!))
    }

    func testConversationJoin_WhenTheSelfUserDoesNotJoinAConversation_OnFailureResponse() {
        // GIVEN
        XCTAssert(login())

        ///Convert MockUser -> ZMUser
        let selfUser_zmUser = user(for: self.selfUser)!

        mockTransportSession.responseGeneratorBlock = {[weak self] request in
            guard request.path == "/conversations/join" else { return nil }

            self?.mockTransportSession.responseGeneratorBlock = nil

            return ZMTransportResponse(payload: nil, httpStatus: 404, transportSessionError: nil)
        }

        // WHEN
        let conversationJoiningFailed = expectation(description: "Failed to join the conversation")
        /// Key and code values don't affect the test result, because the result is mocked
        ZMConversation.join(key: "test-key",
                            code: "test-code",
                            userSession: userSession!,
                            managedObjectContext: selfUser_zmUser.managedObjectContext!,
                            completion: { result in
                                // THEN
                                if case .failure = result {
                                    conversationJoiningFailed.fulfill()
                                } else {
                                    XCTFail()
                                }
                            })
    }

    func testConversationJoin_WhenTheSelfUsersIsAlreadyAParticipant() {
        // GIVEN
        XCTAssert(login())

        ///Convert MockUser -> ZMUser
        let selfUser_zmUser = user(for: self.selfUser)!

        mockTransportSession.responseGeneratorBlock = {[weak self] request in
            guard request.path == "/conversations/join" else { return nil }

            self?.mockTransportSession.responseGeneratorBlock = nil

            return ZMTransportResponse(payload: nil, httpStatus: 204, transportSessionError: nil)
        }

        // WHEN
        let userIsParticipant = expectation(description: "The user was already a participant in the conversation")
        /// Key and code values don't affect the test result, because the result is mocked
        ZMConversation.join(key: "test-key",
                            code: "test-code",
                            userSession: userSession!,
                            managedObjectContext: selfUser_zmUser.managedObjectContext!,
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
