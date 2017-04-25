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

class SystemMessageCallObserverTests : MessagingTest {
    
    var sut : SystemMessageCallObserver!
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
        
        sut = WireSyncEngine.SystemMessageCallObserver(managedObjectContext:uiMOC)
        mockWireCallCenterV3 = WireCallCenterV3Mock(userId: selfUserID, clientId: clientID, uiMOC: uiMOC)
    }
    
    override func tearDown() {
        sut = nil
        super.tearDown()
        mockWireCallCenterV3 = nil
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
    }
    
    func testThatItAppendsPerformedCallSystemMessage_OutgoingCall_V3(){
        // given
        ZMUserSession.callingProtocolStrategy = .version3
        let messageCount = conversation.messages.count
        mockWireCallCenterV3.mockInitiator = user // In case of outgoing calls, the user in the perfromedCall message should always be the selfUser
        
        // when
        sut.callCenterDidChange(voiceChannelState: .outgoingCall, conversation: conversation, callingProtocol: .version2)
        sut.callCenterDidChange(voiceChannelState: .selfConnectedToActiveChannel , conversation: conversation, callingProtocol: .version2)
        sut.callCenterDidEndCall(reason: .requested, conversation: conversation, callingProtocol: .version3)
        
        // then
        XCTAssertEqual(conversation.messages.count, messageCount+1)
        if let message = conversation.messages.lastObject as? ZMSystemMessage {
            XCTAssertEqual(message.systemMessageType, .performedCall)
            XCTAssertTrue(message.users.contains(selfUser))
        }
    }
    
    func testThatItAppendsPerformedCallSystemMessage_IncomingCall_V3(){
        // given
        ZMUserSession.callingProtocolStrategy = .version3
        let messageCount = conversation.messages.count
        mockWireCallCenterV3.mockInitiator = user
        
        // when
        sut.callCenterDidChange(voiceChannelState: .incomingCallInactive, conversation: conversation, callingProtocol: .version3)
        sut.callCenterDidChange(voiceChannelState: .selfConnectedToActiveChannel , conversation: conversation, callingProtocol: .version3)
        sut.callCenterDidEndCall(reason: .requested, conversation: conversation, callingProtocol: .version3)
        
        // then
        XCTAssertEqual(conversation.messages.count, messageCount+1)
        if let message = conversation.messages.lastObject as? ZMSystemMessage {
            XCTAssertEqual(message.systemMessageType, .performedCall)
            XCTAssertTrue(message.users.contains(user))
        }
    }
    
    func testThatItDoesNotAppendsPerformedCallSystemMessage_NotJoined_V3(){
        // given
        ZMUserSession.callingProtocolStrategy = .version3
        let messageCount = conversation.messages.count
        mockWireCallCenterV3.mockInitiator = user

        // when
        sut.callCenterDidChange(voiceChannelState: .incomingCallInactive, conversation: conversation, callingProtocol: .version3)
        sut.callCenterDidEndCall(reason: .requested, conversation: conversation, callingProtocol: .version3)
        
        // then
        XCTAssertEqual(conversation.messages.count, messageCount)
    }

    func testThatItAppendsPerformedCallSystemMessage_OutgoingCall_V2(){
        // given
        ZMUserSession.callingProtocolStrategy = .version2
        let messageCount = conversation.messages.count

        let mutableCallPart = conversation.mutableOrderedSetValue(forKey: "callParticipants")
        mutableCallPart.add(user)
        mutableCallPart.add(selfUser)
        
        // when
        sut.callCenterDidChange(voiceChannelState: .outgoingCall, conversation: conversation, callingProtocol: .version2)
        sut.callCenterDidChange(voiceChannelState: .selfConnectedToActiveChannel , conversation: conversation, callingProtocol: .version2)
        sut.callCenterDidEndCall(reason: .requested, conversation: conversation, callingProtocol: .version3)
        
        // then
        XCTAssertEqual(conversation.messages.count, messageCount+1)
        if let message = conversation.messages.lastObject as? ZMSystemMessage {
            XCTAssertEqual(message.systemMessageType, .performedCall)
            XCTAssertTrue(message.users.contains(selfUser))
        }
    }
    
    func testThatItAppendsPerformedCallSystemMessage_IncomingCall_V2(){
        // given
        ZMUserSession.callingProtocolStrategy = .version2
        let messageCount = conversation.messages.count

        let mutableCallPart = conversation.mutableOrderedSetValue(forKey: "callParticipants")
        mutableCallPart.add(user)
        mutableCallPart.add(selfUser)
        
        // when
        sut.callCenterDidChange(voiceChannelState: .incomingCall, conversation: conversation, callingProtocol: .version2)
        sut.callCenterDidChange(voiceChannelState: .selfConnectedToActiveChannel , conversation: conversation, callingProtocol: .version2)
        sut.callCenterDidEndCall(reason: .requested, conversation: conversation, callingProtocol: .version3)
        
        // then
        XCTAssertEqual(conversation.messages.count, messageCount+1)
        if let message = conversation.messages.lastObject as? ZMSystemMessage {
            XCTAssertEqual(message.systemMessageType, .performedCall)
            XCTAssertTrue(message.users.contains(user))
        }
    }
}
