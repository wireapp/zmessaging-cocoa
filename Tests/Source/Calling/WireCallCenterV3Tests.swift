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

class WireCallCenterV3Tests: MessagingTest {

    var sut : WireCallCenterV3Mock!
    var selfUserID : UUID!
    var clientID: String!
    
    override func setUp() {
        super.setUp()
        selfUserID = UUID()
        clientID = "foo"
        sut = WireCallCenterV3Mock(userId: selfUserID, clientId: clientID, uiMOC: uiMOC)
    }
    
    override func tearDown() {
        sut = nil
        super.tearDown()
    }
    
    func checkThatItPostsNotification(expectedCallState: CallState, userIsNil: Bool = false, expectedUserId: UUID? = nil, line: UInt = #line, file : StaticString = #file, actionBlock: ((UnsafePointer<Int8>?, UnsafePointer<Int8>?, UnsafeMutableRawPointer?) -> Void)){
        // given
        let conversationId = UUID()
        let userId = UUID()
        let conversationIdRef = conversationId.transportString().cString(using: .utf8)
        let userIdRef = userId.transportString().cString(using: .utf8)
        let context = Unmanaged.passUnretained(self.sut).toOpaque()

        // expect
        expectation(forNotification: WireCallCenterCallStateNotification.notificationName.rawValue, object: nil) { wrappedNote in
            guard let note = wrappedNote.userInfo?[WireCallCenterCallStateNotification.userInfoKey] as? WireCallCenterCallStateNotification else { return false }
            XCTAssertEqual(note.conversationId, conversationId, "conversationIds are not the same", file: file, line: line)
            if userIsNil {
                XCTAssertNil(note.userId)
            } else if let otherId = expectedUserId {
                XCTAssertEqual(note.userId, otherId, "userIds are not the same", file: file, line: line)
            }
            else {
                XCTAssertEqual(note.userId, userId, "userIds are not the same", file: file, line: line)
            }
            XCTAssertEqual(note.callState, expectedCallState, "callStates are not the same", file: file, line: line)

            return true
        }
        
        // when
        actionBlock(conversationIdRef, userIdRef, context)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssert(waitForCustomExpectations(withTimeout: 0.5))
    }
    
    func testThatTheIncomingCallHandlerPostsTheRightNotification_IsVideo(){
        checkThatItPostsNotification(expectedCallState: .incoming(video: true, shouldRing: false)) { (conversationIdRef, userIdRef, context) in
            WireSyncEngine.incomingCallHandler(conversationId: conversationIdRef,
                                               messageTime: 0,
                                               userId: userIdRef,
                                               isVideoCall: 1,
                                               shouldRing: 0,
                                               contextRef: context)
        }
    }
    
    func testThatTheIncomingCallHandlerPostsTheRightNotification(){
        checkThatItPostsNotification(expectedCallState: .incoming(video: false, shouldRing: false)) { (conversationIdRef, userIdRef, context) in
            WireSyncEngine.incomingCallHandler(conversationId: conversationIdRef,
                                               messageTime: 0,
                                               userId: userIdRef,
                                               isVideoCall: 0,
                                               shouldRing: 0,
                                               contextRef: context)
        }
    }
    
    func testThatTheIncomingCallHandlerPostsTheRightNotification_IsVideo_ShouldRing(){
        checkThatItPostsNotification(expectedCallState: .incoming(video: true, shouldRing: true)) { (conversationIdRef, userIdRef, context) in
            WireSyncEngine.incomingCallHandler(conversationId: conversationIdRef,
                                               messageTime: 0,
                                               userId: userIdRef,
                                               isVideoCall: 1,
                                               shouldRing: 1,
                                               contextRef: context)
        }
    }
    
    func testThatTheIncomingCallHandlerPostsTheRightNotification_ShouldRing(){
        checkThatItPostsNotification(expectedCallState: .incoming(video: false, shouldRing: true)) { (conversationIdRef, userIdRef, context) in
            WireSyncEngine.incomingCallHandler(conversationId: conversationIdRef,
                                               messageTime: 0,
                                               userId: userIdRef,
                                               isVideoCall: 0,
                                               shouldRing: 1,
                                               contextRef: context)
        }
    }
    
    
    func testThatTheMissedCallHandlerPostANotification(){
        // given
        let conversationId = UUID()
        let userId = UUID()
        let conversationIdRef = conversationId.transportString().cString(using: .utf8)
        let userIdRef = userId.transportString().cString(using: .utf8)
        let context = Unmanaged.passUnretained(self.sut).toOpaque()
        let isVideo = false
        let timestamp = Date()
        
        // expect
        expectation(forNotification: WireCallCenterMissedCallNotification.notificationName.rawValue, object: nil) { wrappedNote in
            guard let note = wrappedNote.userInfo?[WireCallCenterMissedCallNotification.userInfoKey] as? WireCallCenterMissedCallNotification else { return false }
            XCTAssertEqual(note.conversationId, conversationId)
            XCTAssertEqual(note.userId, userId)
            XCTAssertEqualWithAccuracy(note.timestamp.timeIntervalSince1970, timestamp.timeIntervalSince1970, accuracy: 1)
            XCTAssertEqual(note.video, isVideo)
            return true
        }
        
        // when
        WireSyncEngine.missedCallHandler(conversationId: conversationIdRef, messageTime: UInt32(timestamp.timeIntervalSince1970), userId: userIdRef, isVideoCall: 0, contextRef: context)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssert(waitForCustomExpectations(withTimeout: 0.5))
    }
    
    func testThatTheAnsweredCallHandlerPostsTheRightNotification(){
        checkThatItPostsNotification(expectedCallState: .answered, userIsNil: true) { (conversationIdRef, userIdRef, context) in
            WireSyncEngine.answeredCallHandler(conversationId: conversationIdRef, contextRef: context)
        }
    }
    
    func testThatTheEstablishedHandlerPostsTheRightNotification(){
        checkThatItPostsNotification(expectedCallState: .established) { (conversationIdRef, userIdRef, context) in
            WireSyncEngine.establishedCallHandler(conversationId: conversationIdRef, userId: userIdRef, contextRef: context)
        }
    }
    
    func testThatTheEstablishedHandlerSetsTheStartTime(){
        // given
        XCTAssertNil(sut.establishedDate)

        // when
        checkThatItPostsNotification(expectedCallState: .established) { (conversationIdRef, userIdRef, context) in
            WireSyncEngine.establishedCallHandler(conversationId: conversationIdRef, userId: userIdRef, contextRef: context)
        }
        
        // then
        XCTAssertNotNil(sut.establishedDate)
    }
    
    func testThatTheClosedCallHandlerPostsTheRightNotification(){
        checkThatItPostsNotification(expectedCallState: .terminating(reason: .canceled)) { (conversationIdRef, userIdRef, context) in
            WireSyncEngine.closedCallHandler(reason: WCALL_REASON_CANCELED, conversationId: conversationIdRef, messageTime: 0, userId: userIdRef, contextRef: context)
        }
    }
    
    func testThatItRejectsACall_Group(){
        // given
        let conversationId = UUID()
        let userId = UUID()
        let conversationIdRef = conversationId.transportString().cString(using: .utf8)
        let userIdRef = userId.transportString().cString(using: .utf8)
        let context = Unmanaged.passUnretained(self.sut).toOpaque()
        
        WireSyncEngine.incomingCallHandler(conversationId: conversationIdRef, messageTime: 0, userId: userIdRef, isVideoCall: 0, shouldRing: 1, contextRef: context)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // expect
        expectation(forNotification: WireCallCenterCallStateNotification.notificationName.rawValue, object: nil) { wrappedNote in
            guard let note = wrappedNote.userInfo?[WireCallCenterCallStateNotification.userInfoKey] as? WireCallCenterCallStateNotification else { return false }
            XCTAssertEqual(note.conversationId, conversationId)
            XCTAssertEqual(note.userId, userId)
            XCTAssertEqual(note.callState, .incoming(video: false, shouldRing: false))
            return true
        }
        
        // when
        sut.rejectCall(conversationId: conversationId, isGroup: true)
        WireSyncEngine.closedCallHandler(reason: WCALL_REASON_STILL_ONGOING, conversationId: conversationIdRef, messageTime: 0, userId: userIdRef, contextRef: context)

        // then
        XCTAssert(waitForCustomExpectations(withTimeout: 0.5))
        XCTAssertTrue(sut.didCallRejectCall)
    }
    
    func testThatItRejectsACall_1on1(){
        // given
        let conversationId = UUID()
        let userId = UUID()
        let conversationIdRef = conversationId.transportString().cString(using: .utf8)
        let userIdRef = userId.transportString().cString(using: .utf8)
        let context = Unmanaged.passUnretained(self.sut).toOpaque()
        
        WireSyncEngine.incomingCallHandler(conversationId: conversationIdRef, messageTime: 0, userId: userIdRef, isVideoCall: 0, shouldRing: 1, contextRef: context)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // expect
        expectation(forNotification: WireCallCenterCallStateNotification.notificationName.rawValue, object: nil) { wrappedNote in
            guard let note = wrappedNote.userInfo?[WireCallCenterCallStateNotification.userInfoKey] as? WireCallCenterCallStateNotification else { return false }
            XCTAssertEqual(note.conversationId, conversationId)
            XCTAssertEqual(note.userId, userId)
            XCTAssertEqual(note.callState, .incoming(video: false, shouldRing: false))
            return true
        }
        
        // when
        sut.rejectCall(conversationId: conversationId, isGroup: false)
        WireSyncEngine.closedCallHandler(reason: WCALL_REASON_STILL_ONGOING, conversationId: conversationIdRef, messageTime: 0, userId: userIdRef, contextRef: context)

        // then
        XCTAssert(waitForCustomExpectations(withTimeout: 0.5))
        XCTAssertTrue(sut.didCallRejectCall)
    }
    
    func testThatItAnswersACall(){
        checkThatItPostsNotification(expectedCallState: .answered, expectedUserId: selfUserID) { (conversationIdRef, _, _) in
            let conversationId = UUID(cString: conversationIdRef)!
            
            // when
            _ = sut.answerCall(conversationId: conversationId, isGroup: true)
            
            // then
            XCTAssertTrue(sut.didCallAnswerCall)
        }
    }
    
    func testThatItStartsACall(){
        checkThatItPostsNotification(expectedCallState: .outgoing, expectedUserId: selfUserID) { (conversationIdRef, _, _) in
            let conversationId = UUID(cString: conversationIdRef)!
            
            // when
            _ = sut.startCall(conversationId: conversationId, video: false, isGroup: true)
            
            // then
            XCTAssertTrue(sut.didCallStartCall)
        }
    }
    
    func testThatItSetsTheCallStartTimeBeforePostingTheNotification(){
        // given
        let conversationId = UUID()
        let userId = UUID()
        let conversationIdRef = conversationId.transportString().cString(using: .utf8)
        let userIdRef = userId.transportString().cString(using: .utf8)
        let context = Unmanaged.passUnretained(self.sut).toOpaque()
        XCTAssertNil(sut.establishedDate)
        
        // expect
        expectation(forNotification: WireCallCenterCallStateNotification.notificationName.rawValue, object: nil) { wrappedNote in
            XCTAssertNotNil(self.sut.establishedDate)
            return true
        }
        
        // when
        WireSyncEngine.establishedCallHandler(conversationId: conversationIdRef, userId: userIdRef, contextRef: context)
        
        // then
        XCTAssert(waitForCustomExpectations(withTimeout: 0.5))
    
    }
    
    func testThatItBuffersEventsUntilAVSIsReady(){
        // given
        let conversationId = UUID()
        let userId = UUID()
        let clientId = "foo"
        let context = Unmanaged.passUnretained(self.sut).toOpaque()
        let data = self.verySmallJPEGData()
        
        // when
        sut.received(data: data, currentTimestamp: Date(), serverTimestamp: Date(), conversationId: conversationId, userId: userId, clientId: clientId)
        XCTAssertEqual((sut.avsWrapper as! MockAVSWrapper).receivedCallEvents.count, 0)
        
        // and when
        WireSyncEngine.readyHandler(version: 2, contextRef: context)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertEqual((sut.avsWrapper as! MockAVSWrapper).receivedCallEvents.count, 1)
        if let event = (sut.avsWrapper as! MockAVSWrapper).receivedCallEvents.last {
            XCTAssertEqual(event.conversationId, conversationId)
            XCTAssertEqual(event.userId, userId)
            XCTAssertEqual(event.clientId, clientId)
            XCTAssertEqual(event.data, data)
        }
    }
    
}



// MARK - Ignoring Calls

extension WireCallCenterV3Tests {
    
    func testThatItWhenIgnoringACallItWillSetsTheCallStateToIncomingInactive(){
        // given
        let conversationId = UUID()
        
        // when
        sut.mockAVSCallState = .incoming(video: false, shouldRing: true)
        sut.rejectCall(conversationId: conversationId, isGroup: true)
        
        // then
        XCTAssertEqual(sut.callState(conversationId: conversationId), .incoming(video: false, shouldRing: false))
    }
    
    func testThatItWhenRejectingAOneOnOneCallItDoesNotSetTheCallStateToIncomingInactive(){
        // given
        let conversationId = UUID()
        
        // when
        sut.mockAVSCallState = .incoming(video: false, shouldRing: true)
        sut.rejectCall(conversationId: conversationId, isGroup: false)
        
        // then
        XCTAssertNotEqual(sut.callState(conversationId: conversationId), .incoming(video: false, shouldRing: true))
    }
    
    func testThatItWhenClosingAGroupCallItWillSetsTheCallStateToIncomingInactive(){
        // given
        let conversationId = UUID()
        
        // when
        sut.mockAVSCallState = .incoming(video: false, shouldRing: true)
        sut.closeCall(conversationId: conversationId, isGroup: true)
        
        // then
        XCTAssertEqual(sut.callState(conversationId: conversationId), .incoming(video: false, shouldRing: false))
    }
    
    func testThatItWhenClosingAOneOnOneCallItDoesNotSetTheCallStateToIncomingInactive(){
        // given
        let conversationId = UUID()
        
        // when
        sut.mockAVSCallState = .incoming(video: false, shouldRing: true)
        sut.closeCall(conversationId: conversationId, isGroup: false)
        
        // then
        XCTAssertNotEqual(sut.callState(conversationId: conversationId), .incoming(video: false, shouldRing: false))
    }
    
    func testCallStates_noIgnoredConversation(){
        // given
        let conversationId = UUID()

        // when
        sut.mockAVSCallState = .incoming(video: true, shouldRing: true)
        XCTAssertEqual(sut.callState(conversationId: conversationId), sut.mockAVSCallState)
        
        // when
        sut.mockAVSCallState = .outgoing
        XCTAssertEqual(sut.callState(conversationId: conversationId), sut.mockAVSCallState)
        
        // when
        sut.mockAVSCallState = .terminating(reason: .canceled)
        XCTAssertEqual(sut.callState(conversationId: conversationId), sut.mockAVSCallState)
        
        // when
        sut.mockAVSCallState = .established
        XCTAssertEqual(sut.callState(conversationId: conversationId), sut.mockAVSCallState)
        
        // when
        sut.mockAVSCallState = .answered
        XCTAssertEqual(sut.callState(conversationId: conversationId), sut.mockAVSCallState)
        
        // when
        sut.mockAVSCallState = .none
        XCTAssertEqual(sut.callState(conversationId: conversationId), sut.mockAVSCallState)
    }
    
    func testCallStates_ignoredConversation(){
        // given
        let conversationId = UUID()
        sut.rejectCall(conversationId: conversationId, isGroup: false)
        
        // when
        sut.mockAVSCallState = .incoming(video: true, shouldRing: true)
        XCTAssertNotEqual(sut.callState(conversationId: conversationId), sut.mockAVSCallState)
        XCTAssertEqual(sut.callState(conversationId: conversationId), .incoming(video: true, shouldRing: false))

        // when
        sut.mockAVSCallState = .outgoing
        XCTAssertEqual(sut.callState(conversationId: conversationId), sut.mockAVSCallState)
        
        // when
        sut.mockAVSCallState = .terminating(reason: .canceled)
        XCTAssertEqual(sut.callState(conversationId: conversationId), sut.mockAVSCallState)
        
        // when
        sut.mockAVSCallState = .established
        XCTAssertNotEqual(sut.callState(conversationId: conversationId), sut.mockAVSCallState)
        XCTAssertEqual(sut.callState(conversationId: conversationId), .incoming(video: false, shouldRing: false))

        // when
        sut.mockAVSCallState = .answered
        XCTAssertEqual(sut.callState(conversationId: conversationId), sut.mockAVSCallState)
        
        // when
        sut.mockAVSCallState = .none
        XCTAssertEqual(sut.callState(conversationId: conversationId), sut.mockAVSCallState)
    }

}


// MARK - Participants
extension WireCallCenterV3Tests {

    func testThatItCreatesAParticipantSnapshotForAnIncomingCall(){
        // given
        let conversationId = UUID()
        let userId = UUID()
        let conversationIdRef = conversationId.transportString().cString(using: .utf8)
        let userIdRef = userId.transportString().cString(using: .utf8)
        let context = Unmanaged.passUnretained(self.sut).toOpaque()

        // when
        WireSyncEngine.incomingCallHandler(conversationId: conversationIdRef, messageTime: 0, userId: userIdRef, isVideoCall: 0, shouldRing: 1, contextRef: context)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertEqual(sut.callParticipants(conversationId: conversationId), [userId])
    }
    
    func callBackMemberHandler(conversationIdRef: UnsafePointer<Int8>?, userId: UUID, audioEstablished: Bool, context: UnsafeMutableRawPointer?) {
        sut.mockMembers = [CallMember(userId: userId, audioEstablished: audioEstablished)]
        WireSyncEngine.groupMemberHandler(conversationIdRef: conversationIdRef, contextRef: context)
    }
    
    func testThatItUpdatesTheParticipantsWhenGroupHandlerIsCalled(){
        // given
        let conversationId = UUID()
        let userId = UUID()
        let conversationIdRef = conversationId.transportString().cString(using: .utf8)
        let context = Unmanaged.passUnretained(self.sut).toOpaque()

        // when
        callBackMemberHandler(conversationIdRef: conversationIdRef, userId: userId, audioEstablished: false, context: context)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertEqual(sut.callParticipants(conversationId: conversationId), [userId])
    }
    
    func testThatItUpdatesTheStateForParticipant(){
        // given
        let conversationId = UUID()
        let userId = UUID()
        let conversationIdRef = conversationId.transportString().cString(using: .utf8)
        let userIdRef = userId.transportString().cString(using: .utf8)
        let context = Unmanaged.passUnretained(self.sut).toOpaque()

        // when
        WireSyncEngine.incomingCallHandler(conversationId: conversationIdRef, messageTime: 0, userId: userIdRef, isVideoCall: 0, shouldRing: 1, contextRef: context)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        let connectingState = sut.connectionState(forUserWith: userId, in: conversationId)
        XCTAssertEqual(connectingState, .connecting)
        
        // when
        callBackMemberHandler(conversationIdRef: conversationIdRef, userId: userId, audioEstablished: true, context: context)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        let connectedState = sut.connectionState(forUserWith: userId, in: conversationId)
        XCTAssertEqual(connectedState, .connected)
    }
}
