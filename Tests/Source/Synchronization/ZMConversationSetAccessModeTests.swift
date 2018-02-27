//
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
import XCTest
import WireTesting
@testable import WireSyncEngine

public class ZMConversationSetAccessModeTests : MessagingTest {
    func testThatItGeneratesCorrectSetAccessModeRequest() {
        // given
        let team = Team.insertNewObject(in: self.uiMOC)
        let conversation = ZMConversation.insertGroupConversation(into: self.uiMOC, withParticipants: [], name: "Test Conversation", in: team)!
        conversation.remoteIdentifier = UUID()
        conversation.teamRemoteIdentifier = UUID()
        // when
        let request = WireSyncEngine.WirelessRequestFactory.set(allowGuests: true, for: conversation)
        // then
        XCTAssertEqual(request.method, .methodPUT)
        XCTAssertEqual(request.path, "/conversations/\(conversation.remoteIdentifier!.transportString())/access")
        let payload = request.payload as! [String: AnyHashable]
        XCTAssertNotNil(payload)
        XCTAssertNotNil(payload["access"])
        XCTAssertEqual(Set(payload["access"] as! [String]), Set(["invite", "code"]))
        XCTAssertNotNil(payload["access_role"])
        XCTAssertEqual(payload["access_role"], "non_activated")
    }
}

