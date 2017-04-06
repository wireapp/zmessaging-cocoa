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
        
        // then
        XCTAssert(waitForCustomExpectations(withTimeout: 0.5))
    }
    
    func testThatTheIncomingCallHandlerPostsTheRightNotification_IsVideo(){
        checkThatItPostsNotification(expectedCallState: .incoming(video: true)) { (conversationIdRef, userIdRef, context) in
            WireSyncEngine.IncomingCallHandler(conversationId: conversationIdRef,
                                userId: userIdRef,
                                isVideoCall: 1,
                                contextRef: context)
        }
    }
    
    func testThatTheIncomingCallHandlerPostsTheRightNotification(){
        checkThatItPostsNotification(expectedCallState: .incoming(video: false)) { (conversationIdRef, userIdRef, context) in
            WireSyncEngine.IncomingCallHandler(conversationId: conversationIdRef,
                                userId: userIdRef,
                                isVideoCall: 0,
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
        WireSyncEngine.MissedCallHandler(conversationId: conversationIdRef, messageTime: UInt32(timestamp.timeIntervalSince1970), userId: userIdRef, isVideoCall: 0, contextRef: context)
        
        // then
        XCTAssert(waitForCustomExpectations(withTimeout: 0.5))
    }
    
    func testThatTheAnsweredCallHandlerPostsTheRightNotification(){
        checkThatItPostsNotification(expectedCallState: .answered, userIsNil: true) { (conversationIdRef, userIdRef, context) in
            WireSyncEngine.AnsweredCallHandler(conversationId: conversationIdRef, contextRef: context)
        }
    }
    
    func testThatTheEstablishedHandlerPostsTheRightNotification(){
        checkThatItPostsNotification(expectedCallState: .established) { (conversationIdRef, userIdRef, context) in
            WireSyncEngine.EstablishedCallHandler(conversationId: conversationIdRef, userId: userIdRef, contextRef: context)
        }
    }
    
    func testThatTheEstablishedHandlerSetsTheStartTime(){
        // given
        XCTAssertNil(sut.establishedDate)

        // when
        checkThatItPostsNotification(expectedCallState: .established) { (conversationIdRef, userIdRef, context) in
            WireSyncEngine.EstablishedCallHandler(conversationId: conversationIdRef, userId: userIdRef, contextRef: context)
        }
        
        // then
        XCTAssertNotNil(sut.establishedDate)
    }
    
    func testThatTheClosedCallHandlerPostsTheRightNotification(){
        checkThatItPostsNotification(expectedCallState: .terminating(reason: .canceled)) { (conversationIdRef, userIdRef, context) in
            WireSyncEngine.ClosedCallHandler(reason: WCALL_REASON_CANCELED, conversationId: conversationIdRef, userId: userIdRef, metrics: nil, contextRef: context)
        }
    }

    
    func testThatItRejectsACall_1on1(){
        // given
        let conversationId = UUID()
        let userId = UUID()
        let conversationIdRef = conversationId.transportString().cString(using: .utf8)
        let userIdRef = userId.transportString().cString(using: .utf8)
        let context = Unmanaged.passUnretained(self.sut).toOpaque()
        
        WireSyncEngine.IncomingCallHandler(conversationId: conversationIdRef, userId: userIdRef, isVideoCall: 0, contextRef: context)
        
        // expect
        expectation(forNotification: WireCallCenterCallStateNotification.notificationName.rawValue, object: nil) { wrappedNote in
            guard let note = wrappedNote.userInfo?[WireCallCenterCallStateNotification.userInfoKey] as? WireCallCenterCallStateNotification else { return false }
            XCTAssertEqual(note.conversationId, conversationId)
            XCTAssertEqual(note.userId, self.selfUserID)
            XCTAssertEqual(note.callState, .terminating(reason: .canceled))
            return true
        }
        
        // when
        sut.rejectCall(conversationId: conversationId)
        
        // then
        XCTAssert(waitForCustomExpectations(withTimeout: 0.5))
        XCTAssertTrue(sut.didCallRejectCall)
    }
    
    func testThatItAnswersACall(){
        checkThatItPostsNotification(expectedCallState: .answered, expectedUserId: selfUserID) { (conversationIdRef, _, _) in
            let conversationId = UUID(cString: conversationIdRef)!
            
            // when
            _ = sut.answerCall(conversationId: conversationId)
            
            // then
            XCTAssertTrue(sut.didCallAnswerCall)
        }
    }
    
    func testThatItStartsACall(){
        checkThatItPostsNotification(expectedCallState: .outgoing, expectedUserId: selfUserID) { (conversationIdRef, _, _) in
            let conversationId = UUID(cString: conversationIdRef)!
            
            // when
            _ = sut.startCall(conversationId: conversationId, video: false)
            
            // then
            XCTAssertTrue(sut.didCallStartCall)
        }
    }
    
}


