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
@testable import zmessaging

class CallStateObserverTests : MessagingTest {
    
    var sut : CallStateObserver!
    var sender : ZMUser!
    var conversation : ZMConversation!
    var localNotificationDispatcher : ZMLocalNotificationDispatcher!
    
    override func setUp() {
        super.setUp()
        
        syncMOC.performGroupedBlockAndWait {
            let sender = ZMUser.insertNewObject(in: self.syncMOC)
            sender.name = "Callie"
            sender.remoteIdentifier = UUID()
            
            self.sender = sender
            
            let conversation = ZMConversation.insertNewObject(in: self.syncMOC)
            conversation.conversationType = .oneOnOne
            conversation.remoteIdentifier = UUID()
            conversation.internalAddParticipant(sender, isAuthoritative: true)
            
            self.conversation = conversation
        }
        
        localNotificationDispatcher = ZMLocalNotificationDispatcher(managedObjectContext: syncMOC, sharedApplication: application)!
        sut = CallStateObserver(localNotificationDispatcher: localNotificationDispatcher, managedObjectContext: syncMOC)
    }
    
    override func tearDown() {
        localNotificationDispatcher.tearDown()
        
        super.tearDown()
    }
    
    func testThatInstanceDoesntHaveRetainCycles() {
        weak var instance = CallStateObserver(localNotificationDispatcher: localNotificationDispatcher, managedObjectContext: syncMOC)
        XCTAssertNil(instance)
    }
    
    func testThatMissedCallMessageIsAppendedForCanceledCalls() {
        
        // given when
        sut.callCenterDidChange(callState: .terminating(reason: .canceled), conversationId: conversation.remoteIdentifier!, userId: sender.remoteIdentifier!)
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        if let message =  conversation.messages.lastObject as? ZMSystemMessage {
            XCTAssertEqual(message.systemMessageType, .missedCall)
            XCTAssertEqual(message.sender, sender)
        } else {
            XCTFail()
        }
    }
    
    func testThatMissedCallMessageIsAppendedForCallsThatTimeout() {
        
        // given when
        sut.callCenterDidChange(callState: .terminating(reason: .timeout), conversationId: conversation.remoteIdentifier!, userId: sender.remoteIdentifier!)
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        if let message =  conversation.messages.lastObject as? ZMSystemMessage {
            XCTAssertEqual(message.systemMessageType, .missedCall)
            XCTAssertEqual(message.sender, sender)
        } else {
            XCTFail()
        }
    }
    
    func testThatMissedCallMessageIsNotAppendedForCallsOtherCallStates() {
        
        // given
        let ignoredCallStates : [CallState] = [.terminating(reason: .anweredElsewhere),
                                               .terminating(reason: .normal),
                                               .terminating(reason: .normalSelf),
                                               .terminating(reason: .lostMedia),
                                               .terminating(reason: .internalError),
                                               .terminating(reason: .unknown),
                                               .incoming(video: true),
                                               .incoming(video: false),
                                               .answered,
                                               .established,
                                               .outgoing]
        
        // when
        for callState in ignoredCallStates {
            sut.callCenterDidChange(callState: callState, conversationId: conversation.remoteIdentifier!, userId: sender.remoteIdentifier!)
        }
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertEqual(conversation.messages.count, 0)
    }
    
    func testThatMissedCallMessageIsAppendedForMissedCalls() {
        
        // given when
        sut.callCenterMissedCall(conversationId: conversation.remoteIdentifier!, userId: sender.remoteIdentifier!, timestamp: Date(), video: false)
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        if let message =  conversation.messages.lastObject as? ZMSystemMessage {
            XCTAssertEqual(message.systemMessageType, .missedCall)
            XCTAssertEqual(message.sender, sender)
        } else {
            XCTFail()
        }
    }
    
    func testThatMissedCallsAreForwardedToTheNotificationDispatcher() {
        // given when
        sut.callCenterMissedCall(conversationId: conversation.remoteIdentifier!, userId: sender.remoteIdentifier!, timestamp: Date(), video: false)
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertEqual(application.scheduledLocalNotifications.count, 1)
    }
    
    func testThatCallStatesAreForwardedToTheNotificationDispatcher() {
        // given when
        sut.callCenterDidChange(callState: .incoming(video: false), conversationId: conversation.remoteIdentifier!, userId: sender.remoteIdentifier!)
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertEqual(application.scheduledLocalNotifications.count, 1)
    }
    
}
