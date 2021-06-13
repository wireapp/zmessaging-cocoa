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

    func testThatTheSelfUserJoinsAConversation_OnSuccessfulResponse() {
        // GIVEN
        XCTAssert(login())

        // Convert MockUser -> ZMUser
        let selfUser_zmUser = user(for: self.selfUser)!

        // WHEN
        /// Key value doesn't affect the test result
        ZMConversation.join(key: "test-key",
                            code: "test-code",
                            userSession: userSession!,
                            managedObjectContext: self.selfUser.managedObjectContext!,
                            completion: { (result, conversation) in
                                // THEN
                                if case .success = result {
                                    XCTAssertNotNil(conversation)
                                    XCTAssertTrue(conversation!.localParticipants.map(\.remoteIdentifier).contains(selfUser_zmUser.remoteIdentifier))
                                } else {
                                    XCTFail()
                                }
                            })
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
    }

    func testThatTheSelfUserDoesNotJoinAConversation_OnFailureResponse() {
        // GIVEN
        XCTAssert(login())

        ///Convert MockUser -> ZMUser
        let selfUser_zmUser = user(for: self.selfUser)!

        // WHEN
        let conversationJoiningFailed = expectation(description: "Failed to join the conversation")
        /// Key value doesn't affect the test result
        ZMConversation.join(key: "test-key",
                            code: "wrong-code",
                            userSession: userSession!,
                            managedObjectContext: selfUser_zmUser.managedObjectContext!,
                            completion: { (result, conversation) in
                                // THEN
                                if case .failure(let error) = result {
                                    XCTAssertEqual(error as! ConversationJoinError, ConversationJoinError.invalidCode)
                                    conversationJoiningFailed.fulfill()
                                } else {
                                    XCTFail()
                                }
                            })
        XCTAssertTrue(waitForCustomExpectations(withTimeout: 0.5, handler: nil))
    }

    func testThatAnErrorIsNotReported_WhenTheSelfUsersIsAlreadyAParticipant() {
        // GIVEN
        XCTAssert(login())

        ///Convert MockUser -> ZMUser
        let selfUser_zmUser = user(for: self.selfUser)!

        mockTransportSession.responseGeneratorBlock = {[weak self] request in
            guard request.path == "/conversations/join" else {
                return nil
            }
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
                            completion: { (result, conversation)  in
                                // THEN
                                if case .success = result {
                                    userIsParticipant.fulfill()
                                } else {
                                    XCTFail()
                                }
                            })
        XCTAssertTrue(waitForCustomExpectations(withTimeout: 0.5))
    }

}
