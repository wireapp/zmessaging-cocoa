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
@testable import WireSyncEngine

class CallStateObserverTests : MessagingTest {
    
    var sut : CallStateObserver!
    var sender : ZMUser!
    var receiver : ZMUser!
    var conversation : ZMConversation!
    var localNotificationDispatcher : LocalNotificationDispatcher!
    
    override func setUp() {
        super.setUp()
        
        syncMOC.performGroupedBlockAndWait {
            let sender = ZMUser.insertNewObject(in: self.syncMOC)
            sender.name = "Sender"
            sender.remoteIdentifier = UUID()
            
            self.sender = sender
            
            let receiver = ZMUser.insertNewObject(in: self.syncMOC)
            receiver.name = "Receiver"
            receiver.remoteIdentifier = UUID()
            
            self.receiver = receiver
            
            let conversation = ZMConversation.insertNewObject(in: self.syncMOC)
            conversation.conversationType = .oneOnOne
            conversation.remoteIdentifier = UUID()
            conversation.internalAddParticipants(Set<ZMUser>(arrayLiteral:sender), isAuthoritative: true)
            conversation.internalAddParticipants(Set<ZMUser>(arrayLiteral:receiver), isAuthoritative: true)
            
            self.conversation = conversation
        }
        
        localNotificationDispatcher = LocalNotificationDispatcher(in: syncMOC, application: application)
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
    
    func testThatMissedCallMessageIsAppendedForCanceledCallByReceiver() {
        
        // given when
        sut.callCenterDidChange(callState: .incoming(video: false, shouldRing: false), conversationId: conversation.remoteIdentifier!, userId: sender.remoteIdentifier!, timeStamp: nil)
        sut.callCenterDidChange(callState: .terminating(reason: .canceled), conversationId: conversation.remoteIdentifier!, userId: receiver.remoteIdentifier!, timeStamp: nil)
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        if let message =  conversation.messages.lastObject as? ZMSystemMessage {
            XCTAssertEqual(message.systemMessageType, .missedCall)
            XCTAssertEqual(message.sender, sender)
        } else {
            XCTFail()
        }
    }
    
    func testThatMissedCallMessageIsAppendedForCanceledCallBySender() {
        
        // given when
        sut.callCenterDidChange(callState: .incoming(video: false, shouldRing: false), conversationId: conversation.remoteIdentifier!, userId: sender.remoteIdentifier!, timeStamp: nil)
        sut.callCenterDidChange(callState: .terminating(reason: .canceled), conversationId: conversation.remoteIdentifier!, userId: sender.remoteIdentifier!, timeStamp: nil)
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
                                               .terminating(reason: .lostMedia),
                                               .terminating(reason: .internalError),
                                               .terminating(reason: .unknown),
                                               .incoming(video: true, shouldRing: false),
                                               .incoming(video: false, shouldRing: false),
                                               .incoming(video: true, shouldRing: true),
                                               .incoming(video: false, shouldRing: true),
                                               .answered,
                                               .established,
                                               .outgoing]
        
        // when
        for callState in ignoredCallStates {
            sut.callCenterDidChange(callState: callState, conversationId: conversation.remoteIdentifier!, userId: sender.remoteIdentifier!, timeStamp: nil)
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
        sut.callCenterDidChange(callState: .incoming(video: false, shouldRing: false), conversationId: conversation.remoteIdentifier!, userId: sender.remoteIdentifier!, timeStamp: nil)
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertEqual(application.scheduledLocalNotifications.count, 1)
    }
    
    func testThatWeKeepTheWebsocketOpenOnIncomingCalls() {
        // expect
        expectation(forNotification: ZMTransportSessionShouldKeepWebsocketOpenNotificationName, object: nil) { (note) -> Bool in
            if let open = note.userInfo?[ZMTransportSessionShouldKeepWebsocketOpenKey] as? Bool, open == true {
                return true
            } else {
                return false
            }
        }
        
        // given when
        sut.callCenterDidChange(callState: .incoming(video: false, shouldRing: false), conversationId: conversation.remoteIdentifier!, userId: sender.remoteIdentifier!, timeStamp: nil)
        XCTAssertTrue(waitForCustomExpectations(withTimeout: 0.5))
    }
    
    func testThatWeKeepTheWebsocketOpenOnOutgoingCalls() {
        // expect
        expectation(forNotification: ZMTransportSessionShouldKeepWebsocketOpenNotificationName, object: nil) { (note) -> Bool in
            if let open = note.userInfo?[ZMTransportSessionShouldKeepWebsocketOpenKey] as? Bool, open == true {
                return true
            } else {
                return false
            }
        }
        
        // given when
        sut.callCenterDidChange(callState: .outgoing, conversationId: conversation.remoteIdentifier!, userId: sender.remoteIdentifier!, timeStamp: nil)
        XCTAssertTrue(waitForCustomExpectations(withTimeout: 0.5))
    }
    
    func testThatWeDontKeepTheWebsocketOpenAfterACallIsTerminated() {
        // expect
        expectation(forNotification: ZMTransportSessionShouldKeepWebsocketOpenNotificationName, object: nil) { (note) -> Bool in
            if let open = note.userInfo?[ZMTransportSessionShouldKeepWebsocketOpenKey] as? Bool, open == false {
                return true
            } else {
                return false
            }
        }
        
        // given when
        sut.callCenterDidChange(callState: .terminating(reason: .normal), conversationId: conversation.remoteIdentifier!, userId: sender.remoteIdentifier!, timeStamp: nil)
        XCTAssertTrue(waitForCustomExpectations(withTimeout: 0.5))
    }
    
}
