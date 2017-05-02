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
@testable import WireSyncEngine

class CallSystemMessageGeneratorTests : MessagingTest {

    var sut : WireSyncEngine.CallSystemMessageGenerator!
    var mockWireCallCenterV3 : WireCallCenterV3Mock!
    var selfUserID : UUID!
    var clientID: String!
    var conversation : ZMConversation!
    var user : ZMUser!
    var selfUser : ZMUser!
    
    override func setUp() {
        super.setUp()
        conversation = ZMConversation.insertNewObject(in: uiMOC)
        conversation.conversationType = .group
        conversation.remoteIdentifier = UUID()
        
        user = ZMUser.insertNewObject(in: uiMOC)
        user.remoteIdentifier = UUID()
        user.name = "Hans"
        
        selfUser = ZMUser.selfUser(in: uiMOC)
        selfUser.remoteIdentifier = UUID()
        selfUserID = selfUser.remoteIdentifier
        clientID = "foo"
        
        sut = WireSyncEngine.CallSystemMessageGenerator()
        mockWireCallCenterV3 = WireCallCenterV3Mock(userId: selfUserID, clientId: clientID, uiMOC: uiMOC)
    }
    
    override func tearDown() {
        sut = nil
        selfUserID = nil
        clientID = nil
        selfUser = nil
        conversation = nil
        user = nil
        super.tearDown()
        mockWireCallCenterV3 = nil
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
    }
    
    func testThatItAppendsPerformedCallSystemMessage_OutgoingCall_V3(){
        // given
        ZMUserSession.callingProtocolStrategy = .version3
        let messageCount = conversation.messages.count
        
        // when
        sut.callCenterDidChange(callState: .outgoing, conversation: conversation, user: selfUser, timeStamp: nil)
        sut.callCenterDidChange(callState: .established, conversation: conversation, user: selfUser, timeStamp: nil)
        sut.callCenterDidChange(callState: .terminating(reason: .canceled), conversation: conversation, user: user, timeStamp: nil)
        
        // then
        XCTAssertEqual(conversation.messages.count, messageCount+1)
        if let message = conversation.messages.lastObject as? ZMSystemMessage {
            XCTAssertEqual(message.systemMessageType, .performedCall)
            XCTAssertTrue(message.users.contains(selfUser))
        } else {
            XCTFail("No system message inserted")
        }
    }
    
    func testThatItAppendsPerformedCallSystemMessage_IncomingCall_V3(){
        // given
        ZMUserSession.callingProtocolStrategy = .version3
        let messageCount = conversation.messages.count
        
        // when
        sut.callCenterDidChange(callState: .incoming(video: false, shouldRing: true), conversation: conversation, user: user, timeStamp: nil)
        sut.callCenterDidChange(callState: .established , conversation: conversation, user: user, timeStamp: nil)
        sut.callCenterDidChange(callState: .terminating(reason: .canceled), conversation: conversation, user: user, timeStamp: nil)
        
        // then
        XCTAssertEqual(conversation.messages.count, messageCount+1)
        if let message = conversation.messages.lastObject as? ZMSystemMessage {
            XCTAssertEqual(message.systemMessageType, .performedCall)
            XCTAssertTrue(message.users.contains(user))
        } else {
            XCTFail("No system message inserted")
        }
    }
    
    func testThatItAppendsMissedCallSystemMessage_UnansweredIncomingCall_V3(){
        // given
        ZMUserSession.callingProtocolStrategy = .version3
        let messageCount = conversation.messages.count
        
        // when
        sut.callCenterDidChange(callState: .incoming(video:false, shouldRing: true), conversation: conversation, user: user, timeStamp: nil)
        self.performIgnoringZMLogError { 
            self.sut.callCenterDidChange(callState: .terminating(reason: .canceled), conversation: self.conversation, user: self.user, timeStamp: nil)
        }

        // then
        XCTAssertEqual(conversation.messages.count, messageCount+1)
        if let message = conversation.messages.lastObject as? ZMSystemMessage {
            XCTAssertEqual(message.systemMessageType, .missedCall)
            XCTAssertTrue(message.users.contains(user))
        } else {
            XCTFail("No system message inserted")
        }
    }
}
