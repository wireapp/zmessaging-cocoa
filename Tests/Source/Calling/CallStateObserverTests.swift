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
    var mockCallCenter : WireCallCenterV3Mock?
    
    override func setUp() {
        super.setUp()
        
        self.application.applicationState = .background
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
            
            ZMUser.selfUser(in: self.syncMOC).remoteIdentifier = UUID()

            self.syncMOC.saveOrRollback()
            
            self.localNotificationDispatcher = LocalNotificationDispatcher(
                in: self.syncMOC,
                foregroundNotificationDelegate: MockForegroundNotificationDelegate(),
                application: self.application)
        }

        sut = CallStateObserver(localNotificationDispatcher: localNotificationDispatcher, userSession: mockUserSession)
        uiMOC.zm_callCenter = mockCallCenter

    }
    
    override func tearDown() {
        localNotificationDispatcher.tearDown()
        
        sut = nil
        sender = nil
        receiver = nil
        conversation = nil
        localNotificationDispatcher = nil
        mockCallCenter = nil
        
        super.tearDown()
    }
    
    func testThatInstanceDoesntHaveRetainCycles() {
        weak var instance = CallStateObserver(localNotificationDispatcher: localNotificationDispatcher, userSession: mockUserSession)
        XCTAssertNil(instance)
    }
    
    func testThatMissedCallMessageIsAppendedForCanceledCallByReceiver() {

        // when
        sut.callCenterDidChange(callState: .incoming(video: false, shouldRing: false, degraded: false), conversationId: conversation.remoteIdentifier!, userId: sender.remoteIdentifier!, timeStamp: nil)
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
        sut.callCenterDidChange(callState: .incoming(video: false, shouldRing: false, degraded: false), conversationId: conversation.remoteIdentifier!, userId: sender.remoteIdentifier!, timeStamp: nil)
        sut.callCenterDidChange(callState: .terminating(reason: .canceled), conversationId: conversation.remoteIdentifier!, userId: sender.remoteIdentifier!, timeStamp: nil)
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        self.syncMOC.performGroupedBlockAndWait {
            // then
            if let message = self.conversation.messages.lastObject as? ZMSystemMessage {
                XCTAssertEqual(message.systemMessageType, .missedCall)
                XCTAssertEqual(message.sender, self.sender)
            } else {
                XCTFail()
            }
        }
    }
    
    func testThatMissedCallMessageIsNotAppendedForCallsOtherCallStates() {
        
        // given
        let ignoredCallStates : [CallState] = [.terminating(reason: .anweredElsewhere),
                                               .terminating(reason: .normal),
                                               .terminating(reason: .lostMedia),
                                               .terminating(reason: .internalError),
                                               .terminating(reason: .unknown),
                                               .incoming(video: true, shouldRing: false, degraded: false),
                                               .incoming(video: false, shouldRing: false, degraded: false),
                                               .incoming(video: true, shouldRing: true, degraded: false),
                                               .incoming(video: false, shouldRing: true, degraded: false),
                                               .answered(degraded: false),
                                               .established,
                                               .outgoing(degraded: false)]
        
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
        sut.callCenterDidChange(callState: .incoming(video: false, shouldRing: true, degraded: false), conversationId: conversation.remoteIdentifier!, userId: sender.remoteIdentifier!, timeStamp: nil)
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertEqual(self.application.scheduledLocalNotifications.count, 1)
    }
    
    func testThatWeSendNotificationWhenCallStarts() {
        
        // given when
        sut.callCenterDidChange(callState: .incoming(video: false, shouldRing: false, degraded: false), conversationId: conversation.remoteIdentifier!, userId: sender.remoteIdentifier!, timeStamp: nil)
        XCTAssertTrue(waitForCustomExpectations(withTimeout: 0.5))
    }
    
    func testThatWeKeepTheWebsocketOpenOnOutgoingCalls() {
        // expect
        mockCallCenter = WireCallCenterV3Mock(userId: UUID.create(), clientId: "1234567", uiMOC: uiMOC, flowManager: FlowManagerMock(), transport: WireCallCenterTransportMock())
        mockCallCenter?.mockNonIdleCalls = [conversation.remoteIdentifier! : .incoming(video: false, shouldRing: true, degraded: false)]
        mockUserSession.managedObjectContext.zm_callCenter = mockCallCenter
        
        expectation(forNotification: CallStateObserver.CallInProgressNotification.rawValue, object: nil) { (note) -> Bool in
            if let open = note.userInfo?[CallStateObserver.CallInProgressKey] as? Bool, open == true {
                return true
            } else {
                return false
            }
        }
        
        // given when
        sut.callCenterDidChange(callState: .outgoing(degraded: false), conversationId: conversation.remoteIdentifier!, userId: conversation.remoteIdentifier!, timeStamp: Date())
        XCTAssertTrue(waitForCustomExpectations(withTimeout: 0.5))
        
        // tear down
        mockCallCenter = nil
    }
    
    func testThatWeSendNotificationWhenCallTerminates() {
        // given
        mockCallCenter = WireCallCenterV3Mock(userId: UUID.create(), clientId: "1234567", uiMOC: uiMOC, flowManager: FlowManagerMock(), transport: WireCallCenterTransportMock())
        mockCallCenter?.mockNonIdleCalls = [conversation.remoteIdentifier! : .incoming(video: false, shouldRing: true, degraded: false)]
        mockUserSession.managedObjectContext.zm_callCenter = mockCallCenter
        sut.callCenterDidChange(callState: .incoming(video: false, shouldRing: false, degraded: false), conversationId: conversation.remoteIdentifier!, userId: conversation.remoteIdentifier!, timeStamp: Date())
        
        // expect
        expectation(forNotification: CallStateObserver.CallInProgressNotification.rawValue, object: nil) { (note) -> Bool in
            if let open = note.userInfo?[CallStateObserver.CallInProgressKey] as? Bool, open == false {
                return true
            } else {
                return false
            }
        }
        
        // when
        mockCallCenter?.mockNonIdleCalls = [:]
        sut.callCenterDidChange(callState: .none, conversationId: conversation.remoteIdentifier!, userId: conversation.remoteIdentifier!, timeStamp: Date())
        XCTAssertTrue(waitForCustomExpectations(withTimeout: 0.5))
        
        // tear down
        mockCallCenter = nil
    }
    
}
