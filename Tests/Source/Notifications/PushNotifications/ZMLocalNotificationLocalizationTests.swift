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

import XCTest
@testable import WireSyncEngine

class ZMLocalNotificationLocalizationTests: ZMLocalNotificationTests {
    
    func testThatItLocalizesTitle() {
        // given
        let conversationName = "iOS Team"
        let teamName = "Wire"
        
        let result: (String?, String?) -> String? = {
            ZMPushStringTitle.localizedString(withConversationName: $0, teamName: $1)
        }
        
        // then
        XCTAssertEqual(result(conversationName, teamName), "iOS Team in Wire")
        XCTAssertEqual(result(conversationName, nil), "iOS Team")
        XCTAssertEqual(result(nil, teamName), "in Wire")
        XCTAssertNil(result(nil, nil))
    }
    
    func testThatItLocalizesCallkitPushString() {
        // "push.notification.callkit.call.started.group" = "%1$@ in %2$@";
        // "push.notification.callkit.call.started.group.nousername.noconversationname" = "Someone calling in a conversation";
        // "push.notification.callkit.call.started.group.nousername" = "Someone calling in %1$@";
        // "push.notification.callkit.call.started.group.noconversationname" = "%@ calling in a conversation";
        
        let result: (ZMUser, ZMConversation) -> String = {
            ("callkit.call.started.group" as NSString).localizedCallKitString(with: $0, conversation: $1)
        }
        
        // then
        XCTAssertEqual(result(sender, groupConversation), "Super User in Super Conversation")
        XCTAssertEqual(result(userWithNoName, groupConversationWithoutName), "Someone calling in a conversation")
        XCTAssertEqual(result(userWithNoName, groupConversation), "Someone calling in Super Conversation")
        XCTAssertEqual(result(sender, groupConversationWithoutName), "Super User calling in a conversation")
    }
}
