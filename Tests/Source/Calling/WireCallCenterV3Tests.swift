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
import avs
@testable import WireSyncEngine

class WireCallCenterTransportMock : WireCallCenterTransport {
    
    var mockCallConfigResponse: (String, Int)?
    var mockClientsRequestResponse: [AVSClient]?
    
    
    func send(data: Data, conversationId: UUID, targets: [AVSClient]?, completionHandler: @escaping ((Int) -> Void)) {
        
    }

    func sendSFT(data: Data, url: URL, completionHandler: @escaping ((Result<Data>) -> Void)) {
        
    }
    
    func requestCallConfig(completionHandler: @escaping CallConfigRequestCompletion) {
        if let mockCallConfigResponse = mockCallConfigResponse {
            completionHandler(mockCallConfigResponse.0, mockCallConfigResponse.1)
        }
    }

    func requestClientsList(conversationId: UUID, completionHandler: @escaping ([AVSClient]) -> Void) {
        if let mockClientsRequestResponse = mockClientsRequestResponse {
            completionHandler(mockClientsRequestResponse)
        }
    }
    
}

class WireCallCenterV3Tests: MessagingTest {

    var flowManager : FlowManagerMock!
    var mockAVSWrapper : MockAVSWrapper!
    var sut : WireCallCenterV3!
    var otherUser: ZMUser!
    let otherUserID : UUID = UUID()
    let otherUserClientID = UUID().transportString()
    var selfUserID : UUID!
    var oneOnOneConversation: ZMConversation!
    var groupConversation: ZMConversation!
    var oneOnOneConversationID : UUID!
    var groupConversationID : UUID!
    var clientID: String!
    var mockTransport : WireCallCenterTransportMock!

    override func setUp() {
        super.setUp()
        
        let selfUser = ZMUser.selfUser(in: uiMOC)
        selfUser.remoteIdentifier = UUID.create()
        selfUserID = selfUser.remoteIdentifier!
        
        let otherUser = ZMUser.insertNewObject(in: uiMOC)
        otherUser.remoteIdentifier = otherUserID
        self.otherUser = otherUser
        
        let oneOnOneConversation = ZMConversation.insertNewObject(in: self.uiMOC)
        oneOnOneConversation.remoteIdentifier = UUID.create()
        oneOnOneConversation.conversationType = .oneOnOne
        oneOnOneConversationID = oneOnOneConversation.remoteIdentifier!
        self.oneOnOneConversation = oneOnOneConversation
        
        let groupConversation = ZMConversation.insertNewObject(in: self.uiMOC)
        groupConversation.remoteIdentifier = UUID.create()
        groupConversation.conversationType = .group
        groupConversation.addParticipantAndUpdateConversationState(user: selfUser, role: nil)
        groupConversationID = groupConversation.remoteIdentifier!
        self.groupConversation = groupConversation
        
        clientID = "foo"
        flowManager = FlowManagerMock()
        mockAVSWrapper = MockAVSWrapper(userId: selfUserID, clientId: clientID, observer: nil)
        mockTransport = WireCallCenterTransportMock()
        sut = WireCallCenterV3(userId: selfUserID, clientId: clientID, avsWrapper: mockAVSWrapper, uiMOC: uiMOC, flowManager: flowManager, transport: mockTransport, configuration: .init())

        try! uiMOC.save()
    }
    
    override func tearDown() {
        sut = nil
        flowManager = nil
        clientID = nil
        selfUserID = nil
        otherUser = nil
        oneOnOneConversation = nil
        oneOnOneConversationID = nil
        groupConversation = nil
        groupConversationID = nil
        mockTransport = nil
        mockAVSWrapper = nil

        super.tearDown()
    }
    
    func checkThatItPostsNotification(expectedCallState: CallState, expectedCallerId: UUID, expectedConversationId: UUID, line: UInt = #line, file : StaticString = #file, actionBlock: () -> Void) {
        // expect
        expectation(forNotification: WireCallCenterCallStateNotification.notificationName, object: nil) { wrappedNote in
            guard let note = wrappedNote.userInfo?[WireCallCenterCallStateNotification.userInfoKey] as? WireCallCenterCallStateNotification else { return false }
            XCTAssertEqual(note.conversationId, expectedConversationId, "conversationIds are not the same", file: file, line: line)
            XCTAssertEqual(note.callerId, expectedCallerId, "callerIds are not the same", file: file, line: line)
            XCTAssertEqual(note.callState, expectedCallState, "callStates are not the same", file: file, line: line)

            return true
        }
        
        // when
        actionBlock()
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssert(waitForCustomExpectations(withTimeout: 0.5))
    }
    
    func testThatTheIncomingCallHandlerPostsTheRightNotification_IsVideo() {
        checkThatItPostsNotification(expectedCallState: .incoming(video: true, shouldRing: false, degraded: false), expectedCallerId: otherUserID, expectedConversationId: oneOnOneConversationID) {
            sut.handleIncomingCall(conversationId: oneOnOneConversationID,
                                   messageTime: Date(),
                                   client: AVSClient(userId: otherUserID, clientId: otherUserClientID),
                                   isVideoCall: true,
                                   shouldRing: false,
                                   conversationType: .oneToOne)
        }
    }
    
    func testThatTheIncomingCallHandlerPostsTheRightNotification() {
        checkThatItPostsNotification(expectedCallState: .incoming(video: false, shouldRing: false, degraded: false), expectedCallerId: otherUserID, expectedConversationId: oneOnOneConversationID) {
            sut.handleIncomingCall(conversationId: oneOnOneConversationID,
                                   messageTime: Date(),
                                   client: AVSClient(userId: otherUserID, clientId: otherUserClientID),
                                   isVideoCall: false,
                                   shouldRing: false,
                                   conversationType: .oneToOne)
        }
    }
    
    func testThatTheIncomingCallHandlerPostsTheRightNotification_IsVideo_ShouldRing() {
        checkThatItPostsNotification(expectedCallState: .incoming(video: true, shouldRing: true, degraded: false), expectedCallerId: otherUserID, expectedConversationId: oneOnOneConversationID) {
            sut.handleIncomingCall(conversationId: oneOnOneConversationID,
                                   messageTime: Date(),
                                   client: AVSClient(userId: otherUserID, clientId: otherUserClientID),
                                   isVideoCall: true,
                                   shouldRing: true,
                                   conversationType: .oneToOne)
        }
    }
    
    func testThatTheIncomingCallHandlerPostsTheRightNotification_ShouldRing() {
        checkThatItPostsNotification(expectedCallState: .incoming(video: false, shouldRing: true, degraded: false), expectedCallerId: otherUserID, expectedConversationId: oneOnOneConversationID) {
            sut.handleIncomingCall(conversationId: oneOnOneConversationID,
                                   messageTime: Date(),
                                   client: AVSClient(userId: otherUserID, clientId: otherUserClientID),
                                   isVideoCall: false,
                                   shouldRing: true,
                                   conversationType: .oneToOne)
        }
    }
    
    
    func testThatTheMissedCallHandlerPostANotification() {
        // given
        let conversationId = UUID()
        let userId = UUID()
        let isVideo = false
        let timestamp = Date()
        
        // expect
        expectation(forNotification: WireCallCenterMissedCallNotification.notificationName, object: nil) { wrappedNote in
            guard let note = wrappedNote.userInfo?[WireCallCenterMissedCallNotification.userInfoKey] as? WireCallCenterMissedCallNotification else { return false }
            XCTAssertEqual(note.conversationId, conversationId)
            XCTAssertEqual(note.callerId, userId)
            XCTAssertEqual(note.timestamp.timeIntervalSince1970, timestamp.timeIntervalSince1970, accuracy: 1)
            XCTAssertEqual(note.video, isVideo)
            return true
        }
        
        // when
        sut.handleMissedCall(conversationId: conversationId, messageTime: timestamp, userId: userId, isVideoCall: false)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssert(waitForCustomExpectations(withTimeout: 0.5))
    }
    
    func testThatTheAnsweredCallHandlerPostsTheRightNotification() {
        // given
        sut.handleIncomingCall(conversationId: oneOnOneConversationID,
                               messageTime: Date(),
                               client: AVSClient(userId: otherUserID, clientId: otherUserClientID),
                               isVideoCall: false,
                               shouldRing: true,
                               conversationType: .oneToOne)

        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        checkThatItPostsNotification(expectedCallState: .answered(degraded: false), expectedCallerId: otherUserID, expectedConversationId: oneOnOneConversationID) {
            sut.handleAnsweredCall(conversationId: oneOnOneConversationID)
        }
    }
    
    func testThatTheEstablishedHandlerPostsTheRightNotification() {
        // given
        sut.handleIncomingCall(conversationId: oneOnOneConversationID,
                               messageTime: Date(),
                               client: AVSClient(userId: otherUserID, clientId: otherUserClientID),
                               isVideoCall: false,
                               shouldRing: true,
                               conversationType: .oneToOne)

        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        checkThatItPostsNotification(expectedCallState: .established, expectedCallerId: otherUserID, expectedConversationId: oneOnOneConversationID) {
            sut.handleEstablishedCall(conversationId: oneOnOneConversationID)
        }
    }
    
    func testThatTheEstablishedHandlerSetsTheStartTime() {
        // given
        sut.handleIncomingCall(conversationId: oneOnOneConversationID,
                               messageTime: Date(),
                               client: AVSClient(userId: otherUserID, clientId: otherUserClientID),
                               isVideoCall: false,
                               shouldRing: true,
                               conversationType: .oneToOne)

        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        XCTAssertNil(sut.establishedDate)
        
        // when
        checkThatItPostsNotification(expectedCallState: .established, expectedCallerId: otherUserID, expectedConversationId: oneOnOneConversationID) {
            sut.handleEstablishedCall(conversationId: oneOnOneConversationID)
        }
        
        // then
        XCTAssertNotNil(sut.establishedDate)
    }
    
    func testThatTheEstablishedHandlerDoesntSetTheStartTimeIfCallIsAlreadyEstablished() {
        // given
        sut.handleIncomingCall(conversationId: oneOnOneConversationID,
                               messageTime: Date(),
                               client: AVSClient(userId: otherUserID, clientId: otherUserClientID),
                               isVideoCall: false,
                               shouldRing: true,
                               conversationType: .oneToOne)

        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        XCTAssertNil(sut.establishedDate)
        
        // call is established
        sut.handleEstablishedCall(conversationId: oneOnOneConversationID)
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        XCTAssertNotNil(sut.establishedDate)
        let previousEstablishedDate = sut.establishedDate
        spinMainQueue(withTimeout: 0.1)
        
        // when
        sut.handleEstablishedCall(conversationId: oneOnOneConversationID)
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertEqual(sut.establishedDate, previousEstablishedDate)
    }
    
    func testThatTheClosedCallHandlerPostsTheRightNotification() {
        // given
        sut.handleIncomingCall(conversationId: oneOnOneConversationID,
                               messageTime: Date(),
                               client: AVSClient(userId: otherUserID, clientId: otherUserClientID),
                               isVideoCall: false,
                               shouldRing: true,
                               conversationType: .oneToOne)

        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        checkThatItPostsNotification(expectedCallState: .terminating(reason: .canceled), expectedCallerId: otherUserID, expectedConversationId: oneOnOneConversationID) {
            sut.handleCallEnd(reason: .canceled, conversationId: oneOnOneConversationID, messageTime: Date(), userId: otherUserID)
        }
    }
    
    func testThatTheMediaStopppedCallHandlerPostsTheRightNotification() {
        // given
        sut.handleIncomingCall(conversationId: oneOnOneConversationID,
                               messageTime: Date(),
                               client: AVSClient(userId: otherUserID, clientId: otherUserClientID),
                               isVideoCall: false,
                               shouldRing: true,
                               conversationType: .oneToOne)

        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        checkThatItPostsNotification(expectedCallState: .mediaStopped, expectedCallerId: otherUserID, expectedConversationId: oneOnOneConversationID) {
            self.sut.handleMediaStopped(conversationId: oneOnOneConversationID)
        }
    }
    
    func testThatOtherIncomingCallsAreRejectedWhenWeAnswerCall() {
        // given
        sut.handleIncomingCall(conversationId: oneOnOneConversationID,
                               messageTime: Date(),
                               client: AVSClient(userId: otherUserID, clientId: otherUserClientID),
                               isVideoCall: false,
                               shouldRing: true,
                               conversationType: .oneToOne)

        sut.handleIncomingCall(conversationId: groupConversationID,
                               messageTime: Date(),
                               client: AVSClient(userId: otherUserID, clientId: otherUserClientID),
                               isVideoCall: false,
                               shouldRing: true,
                               conversationType: .group)

        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // when
        XCTAssertTrue(sut.answerCall(conversation: oneOnOneConversation, video: false))
        
        // then
        XCTAssertTrue(mockAVSWrapper.didCallRejectCall)
    }
    
    func testThatOtherOutgoingCallsAreCanceledWhenWeAnswerCall() {
        // given
        XCTAssertTrue(sut.startCall(conversation: groupConversation, video: false))

        sut.handleIncomingCall(conversationId: oneOnOneConversationID,
                               messageTime: Date(),
                               client: AVSClient(userId: otherUserID, clientId: otherUserClientID),
                               isVideoCall: false,
                               shouldRing: true,
                               conversationType: .oneToOne)

        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // when
        XCTAssertTrue(sut.answerCall(conversation: oneOnOneConversation, video: false))
        
        // then
        XCTAssertTrue(mockAVSWrapper.didCallEndCall)
    }
    
    func testThatOtherIncomingCallsAreRejectedWhenWeStartCall() {
        // given
        sut.handleIncomingCall(conversationId: oneOnOneConversationID,
                               messageTime: Date(),
                               client: AVSClient(userId: otherUserID, clientId: otherUserClientID),
                               isVideoCall: false,
                               shouldRing: true,
                               conversationType: .oneToOne)

        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // when
        XCTAssertTrue(sut.startCall(conversation: groupConversation, video: false))
        
        // then
        XCTAssertTrue(mockAVSWrapper.didCallRejectCall)
    }
    
    func testThatItRejectsACall_Group() {
        // given
        sut.handleIncomingCall(conversationId: groupConversationID,
                               messageTime: Date(),
                               client: AVSClient(userId: otherUserID, clientId: otherUserClientID),
                               isVideoCall: false,
                               shouldRing: true,
                               conversationType: .group)

        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // expect
        expectation(forNotification: WireCallCenterCallStateNotification.notificationName, object: nil) { wrappedNote in
            guard let note = wrappedNote.userInfo?[WireCallCenterCallStateNotification.userInfoKey] as? WireCallCenterCallStateNotification else { return false }
            XCTAssertEqual(note.conversationId, self.groupConversationID)
            XCTAssertEqual(note.callerId, self.otherUserID)
            XCTAssertEqual(note.callState, .incoming(video: false, shouldRing: false, degraded: false))
            return true
        }
        
        // when
        sut.rejectCall(conversationId: oneOnOneConversationID)
        sut.handleCallEnd(reason: .stillOngoing, conversationId: groupConversationID, messageTime: Date(), userId: otherUserID)

        // then
        XCTAssert(waitForCustomExpectations(withTimeout: 0.5))
        XCTAssertTrue(mockAVSWrapper.didCallRejectCall)
    }
    
    func testThatItRejectsACall_1on1() {
        // given
        sut.handleIncomingCall(conversationId: oneOnOneConversationID,
                               messageTime: Date(),
                               client: AVSClient(userId: otherUserID, clientId: otherUserClientID),
                               isVideoCall: false,
                               shouldRing: true,
                               conversationType: .oneToOne)

        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // expect
        expectation(forNotification: WireCallCenterCallStateNotification.notificationName, object: nil) { wrappedNote in
            guard let note = wrappedNote.userInfo?[WireCallCenterCallStateNotification.userInfoKey] as? WireCallCenterCallStateNotification else { return false }
            XCTAssertEqual(note.conversationId, self.oneOnOneConversationID)
            XCTAssertEqual(note.callerId, self.otherUserID)
            XCTAssertEqual(note.callState, .incoming(video: false, shouldRing: false, degraded: false))
            return true
        }
        
        // when
        sut.rejectCall(conversationId: oneOnOneConversationID)
        sut.handleCallEnd(reason: .stillOngoing, conversationId: oneOnOneConversationID, messageTime: Date(), userId: otherUserID)

        // then
        XCTAssert(waitForCustomExpectations(withTimeout: 0.5))
        XCTAssertTrue(mockAVSWrapper.didCallRejectCall)
    }
    
    func testThatItAnswersACall_oneToOne() {
        // given
        sut.handleIncomingCall(conversationId: oneOnOneConversationID,
                               messageTime: Date(),
                               client: AVSClient(userId: otherUserID, clientId: otherUserClientID),
                               isVideoCall: false,
                               shouldRing: true,
                               conversationType: .oneToOne)

        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        checkThatItPostsNotification(expectedCallState: .answered(degraded: false), expectedCallerId: otherUserID, expectedConversationId: oneOnOneConversationID) {
            // when
            _ = sut.answerCall(conversation: oneOnOneConversation, video: false)
            
            // then
            XCTAssertEqual(mockAVSWrapper.answerCallArguments?.callType, AVSCallType.normal)
        }
    }
    
    func testThatItAnswersACall_largeGroup() {
        // given
        // Make sure group conversation has at least 5 participants (including self)
        for _ in 0..<4 {
            let user: ZMUser = ZMUser.insertNewObject(in: uiMOC)
            user.remoteIdentifier = UUID()
            groupConversation.addParticipantAndUpdateConversationState(user: user, role: nil)
        }

        sut.handleIncomingCall(conversationId: groupConversationID,
                               messageTime: Date(),
                               client: AVSClient(userId: otherUserID, clientId: otherUserClientID),
                               isVideoCall: false,
                               shouldRing: true,
                               conversationType: .group)

        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        checkThatItPostsNotification(expectedCallState: .answered(degraded: false), expectedCallerId: otherUserID, expectedConversationId: groupConversationID) {
            // when
            _ = sut.answerCall(conversation: groupConversation, video: false)
            
            // then
            XCTAssertEqual(mockAVSWrapper.answerCallArguments?.callType, AVSCallType.audioOnly)
        }
    }
    
    func testThatItAnswersACall_audioOnly() {
        // given
        sut.handleIncomingCall(conversationId: oneOnOneConversationID,
                               messageTime: Date(),
                               client: AVSClient(userId: otherUserID, clientId: otherUserClientID),
                               isVideoCall: true,
                               shouldRing: true,
                               conversationType: .oneToOne)

        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        checkThatItPostsNotification(expectedCallState: .answered(degraded: false), expectedCallerId: otherUserID, expectedConversationId: oneOnOneConversationID) {
            // when
            _ = sut.answerCall(conversation: oneOnOneConversation, video: false)
            
            // then
            XCTAssertEqual(mockAVSWrapper.answerCallArguments?.callType, AVSCallType.normal)
            XCTAssertEqual(mockAVSWrapper.setVideoStateArguments?.videoState, VideoState.stopped)
        }
    }
    
    func testThatItAnswersACall_withVideo() {
        // given
        sut.handleIncomingCall(conversationId: oneOnOneConversationID,
                               messageTime: Date(),
                               client: AVSClient(userId: otherUserID, clientId: otherUserClientID),
                               isVideoCall: true,
                               shouldRing: true,
                               conversationType: .oneToOne)

        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        checkThatItPostsNotification(expectedCallState: .answered(degraded: false), expectedCallerId: otherUserID, expectedConversationId: oneOnOneConversationID) {
            // when
            _ = sut.answerCall(conversation: oneOnOneConversation, video: true)
            
            // then
            XCTAssertEqual(mockAVSWrapper.answerCallArguments?.callType, AVSCallType.video)
            XCTAssertNil(mockAVSWrapper.setVideoStateArguments)
        }
    }
    
    func testThatItStartsACall_oneToOne(){
        checkThatItPostsNotification(expectedCallState: .outgoing(degraded: false), expectedCallerId: selfUserID, expectedConversationId: oneOnOneConversationID) {
            // when
            _ = sut.startCall(conversation: oneOnOneConversation, video: false)
            
            // then
            XCTAssertEqual(mockAVSWrapper.startCallArguments?.conversationType, AVSConversationType.oneToOne)
            XCTAssertEqual(mockAVSWrapper.startCallArguments?.callType, AVSCallType.normal)
        }
    }

    func testThatItStartsACall_smallGroup(){
        checkThatItPostsNotification(expectedCallState: .outgoing(degraded: false), expectedCallerId: selfUserID, expectedConversationId: groupConversationID) {
            // when
            _ = sut.startCall(conversation: groupConversation, video: false)
            
            // then
            XCTAssertEqual(mockAVSWrapper.startCallArguments?.conversationType, AVSConversationType.group)
            XCTAssertEqual(mockAVSWrapper.startCallArguments?.callType, AVSCallType.normal)
        }
    }
    
    func testThatItStartsACall_smallGroup_video(){
        checkThatItPostsNotification(expectedCallState: .outgoing(degraded: false), expectedCallerId: selfUserID, expectedConversationId: groupConversationID) {
            // when
            _ = sut.startCall(conversation: groupConversation, video: true)
            
            // then
            XCTAssertEqual(mockAVSWrapper.startCallArguments?.conversationType, AVSConversationType.group)
            XCTAssertEqual(mockAVSWrapper.startCallArguments?.callType, AVSCallType.video)
        }
    }
    
    func testThatItStartsACall_largeGroup() {
        
        // Make sure group conversation has at least 5 participants (including self)
        for _ in 0..<4 {
            let user: ZMUser = ZMUser.insertNewObject(in: uiMOC)
            user.remoteIdentifier = UUID()
            groupConversation.addParticipantAndUpdateConversationState(user: user, role: nil)
        }
        
        checkThatItPostsNotification(expectedCallState: .outgoing(degraded: false), expectedCallerId: selfUserID, expectedConversationId: groupConversationID) {
            // when
            _ = sut.startCall(conversation: groupConversation, video: true)
            
            // then
            XCTAssertEqual(mockAVSWrapper.startCallArguments?.conversationType, AVSConversationType.group)
            XCTAssertEqual(mockAVSWrapper.startCallArguments?.callType, AVSCallType.audioOnly)
        }
    }

    func testThatItStartsAConferenceCall() {
        sut.useConferenceCalling = true

        checkThatItPostsNotification(expectedCallState: .outgoing(degraded: false), expectedCallerId: selfUserID, expectedConversationId: groupConversationID) {
            // when
            _ = sut.startCall(conversation: groupConversation, video: false)

            // then
            XCTAssertEqual(mockAVSWrapper.startCallArguments?.conversationType, AVSConversationType.conference)
            XCTAssertEqual(mockAVSWrapper.startCallArguments?.callType, AVSCallType.normal)
        }
    }
    
    func testThatItSetsTheCallStartTimeBeforePostingTheNotification() {
        // given
        sut.handleIncomingCall(conversationId: oneOnOneConversationID,
                               messageTime: Date(),
                               client: AVSClient(userId: otherUserID, clientId: otherUserClientID),
                               isVideoCall: false,
                               shouldRing: true,
                               conversationType: .oneToOne)

        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        XCTAssertNil(sut.establishedDate)
        
        // expect
        expectation(forNotification: WireCallCenterCallStateNotification.notificationName, object: nil) { wrappedNote in
            XCTAssertNotNil(self.sut.establishedDate)
            return true
        }
        
        // when
        sut.handleEstablishedCall(conversationId: oneOnOneConversationID)

        // then
        XCTAssert(waitForCustomExpectations(withTimeout: 0.5))
    }
    
    func testThatItBuffersEventsUntilAVSIsReady() {
        // given
        let userId = UUID()
        let clientId = "foo"
        let data = self.verySmallJPEGData()
        let callEvent = CallEvent(data: data, currentTimestamp: Date(), serverTimestamp: Date(), conversationId: oneOnOneConversationID, userId: userId, clientId: clientId)
        
        // when
        sut.processCallEvent(callEvent, completionHandler: { })
        XCTAssertEqual((sut.avsWrapper as! MockAVSWrapper).receivedCallEvents.count, 0)
        
        // and when
        sut.setCallReady(version: 3)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertEqual((sut.avsWrapper as! MockAVSWrapper).receivedCallEvents.count, 1)
        if let event = (sut.avsWrapper as! MockAVSWrapper).receivedCallEvents.last {
            XCTAssertEqual(event.conversationId, oneOnOneConversationID)
            XCTAssertEqual(event.userId, userId)
            XCTAssertEqual(event.clientId, clientId)
            XCTAssertEqual(event.data, data)
        }
    }
    
    func testThatItCallProcessCallEventCompletionHandler() {
        // given
        let userId = UUID()
        let clientId = "foo"
        let data = self.verySmallJPEGData()
        let callEvent = CallEvent(data: data, currentTimestamp: Date(), serverTimestamp: Date(), conversationId: oneOnOneConversationID, userId: userId, clientId: clientId)
        sut.setCallReady(version: 3)
        
        // expect
        let calledCompletionHandler = expectation(description: "processCallEvent completion handler called")
        
        // when
        sut.processCallEvent(callEvent, completionHandler: { 
            calledCompletionHandler.fulfill()
        })
        
        // then
        XCTAssertTrue(waitForCustomExpectations(withTimeout: 0.5))
    }
    
    func testThatItCallProcessCallEventCompletionHandlerWhenEmptyingBuffer() {
        // given
        let userId = UUID()
        let clientId = "foo"
        let data = self.verySmallJPEGData()
        let callEvent = CallEvent(data: data, currentTimestamp: Date(), serverTimestamp: Date(), conversationId: oneOnOneConversationID, userId: userId, clientId: clientId)
        
        // expect
        let calledCompletionHandler = expectation(description: "processCallEvent completion handler called")
        
        // when
        sut.processCallEvent(callEvent, completionHandler: { 
            calledCompletionHandler.fulfill()
        })
        XCTAssertEqual((sut.avsWrapper as! MockAVSWrapper).receivedCallEvents.count, 0)
        
        // and when
        sut.setCallReady(version: 2)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertTrue(waitForCustomExpectations(withTimeout: 0.5))
    }
    
     
    func testThatTheReceivedCallHandlerPostsTheRightNotification_WithErrorUnknownProtocol() {
        
        let userId = UUID()
        let clientId = "foo"
        let data = self.verySmallJPEGData()
        let callEvent = CallEvent(data: data, currentTimestamp: Date(), serverTimestamp: Date(), conversationId: oneOnOneConversationID, userId: userId, clientId: clientId)
        sut.setCallReady(version: 3)
        
        // expect
        let calledCompletionHandler = expectation(description: "processCallEvent completion handler called")
        
        expectation(forNotification: WireCallCenterCallErrorNotification.notificationName, object: nil) { wrappedNote in
            guard let note = wrappedNote.userInfo?[WireCallCenterCallErrorNotification.userInfoKey] as? WireCallCenterCallErrorNotification else { return false }
            XCTAssertEqual(note.error, self.mockAVSWrapper.callError)
            XCTAssertEqual(note.conversationId, self.oneOnOneConversationID)
            return true
        }
        
        // when
        
        mockAVSWrapper.callError = .unknownProtocol
        
        sut.processCallEvent(callEvent, completionHandler: {
            calledCompletionHandler.fulfill()
        })
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertTrue(waitForCustomExpectations(withTimeout: 0.5))
    }
    
    func testThatTheReceivedCallHandlerDoesntPostNotifications_WithNoError() {
        
        let userId = UUID()
        let clientId = "foo"
        let data = self.verySmallJPEGData()
        let callEvent = CallEvent(data: data, currentTimestamp: Date(), serverTimestamp: Date(), conversationId: oneOnOneConversationID, userId: userId, clientId: clientId)
        sut.setCallReady(version: 3)
        
        // expect
        let calledCompletionHandler = expectation(description: "processCallEvent completion handler called")
        
        // when
        sut.processCallEvent(callEvent, completionHandler: {
            calledCompletionHandler.fulfill()
        })
        
        // then
        XCTAssertTrue(waitForCustomExpectations(withTimeout: 0.5))
    }
    

    func testThatActiveCallsOnlyIncludeExpectedCallStates() {
        // given
        let activeCallStates: [CallState] = [CallState.established,
                                             CallState.establishedDataChannel]

        let nonActiveCallStates: [CallState] = [CallState.incoming(video: false, shouldRing: false, degraded: false),
                                                CallState.outgoing(degraded: false),
                                                CallState.answered(degraded: false),
                                                CallState.terminating(reason: CallClosedReason.normal),
                                                CallState.none,
                                                CallState.unknown]

        // then
        for callState in nonActiveCallStates {
            sut.createSnapshot(callState: callState, members: [], callStarter: nil, video: false, for: groupConversation.remoteIdentifier!, isConferenceCall: false)
            XCTAssertEqual(sut.activeCalls.count, 0)
        }

        for callState in activeCallStates {
            sut.createSnapshot(callState: callState, members: [], callStarter: nil, video: false, for: groupConversation.remoteIdentifier!, isConferenceCall: false)
            XCTAssertEqual(sut.activeCalls.count, 1)
        }
    }
}

// MARK:- CBR
extension WireCallCenterV3Tests {
    
    func testThatCBRIsEnabledOnAudioCBRChangeHandler_whenCallIsEstablished() {
        // given
        sut.handleIncomingCall(conversationId: oneOnOneConversationID,
                               messageTime: Date(),
                               client: AVSClient(userId: otherUserID, clientId: otherUserClientID),
                               isVideoCall: false,
                               shouldRing: true,
                               conversationType: .oneToOne)

        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        sut.handleEstablishedCall(conversationId: oneOnOneConversationID)
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // when
        sut.handleConstantBitRateChange(enabled: true)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertTrue(sut.isContantBitRate(conversationId: oneOnOneConversationID))
    }
    
    func testThatCBRIsEnabledOnAudioCBRChangeHandler_whenDataChannelIsEstablished() {
        // given
        sut.handleIncomingCall(conversationId: oneOnOneConversationID,
                               messageTime: Date(),
                               client: AVSClient(userId: otherUserID, clientId: otherUserClientID),
                               isVideoCall: false,
                               shouldRing: true,
                               conversationType: .oneToOne)

        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        sut.handleDataChannelEstablishement(conversationId: oneOnOneConversationID)
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))

        // when
        sut.handleConstantBitRateChange(enabled: true)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))

        // then
        XCTAssertTrue(sut.isContantBitRate(conversationId: oneOnOneConversationID))
    }

    func testThatCBRIsDisabledOnAudioCBRChangeHandler() {
        // given
        sut.handleIncomingCall(conversationId: oneOnOneConversationID,
                               messageTime: Date(),
                               client: AVSClient(userId: otherUserID, clientId: otherUserClientID),
                               isVideoCall: false,
                               shouldRing: true,
                               conversationType: .oneToOne)

        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        sut.handleEstablishedCall(conversationId: oneOnOneConversationID)
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))

        sut.handleConstantBitRateChange(enabled: true)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        XCTAssertTrue(sut.isContantBitRate(conversationId: oneOnOneConversationID))

        // when
        sut.handleConstantBitRateChange(enabled: false)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))

        // then
        XCTAssertFalse(sut.isContantBitRate(conversationId: oneOnOneConversationID))
    }

    func testThatCBRIsNotEnabledOnAudioCBRChangeHandlerWhenCallIsNotEstablished() {
        // given
        sut.handleIncomingCall(conversationId: oneOnOneConversationID,
                               messageTime: Date(),
                               client: AVSClient(userId: otherUserID, clientId: otherUserClientID),
                               isVideoCall: false,
                               shouldRing: true,
                               conversationType: .oneToOne)

        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))

        // when
        sut.handleConstantBitRateChange(enabled: false)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))

        // then
        XCTAssertFalse(sut.isContantBitRate(conversationId: oneOnOneConversationID))
    }

    func testThatCBRIsNotEnabledAfterCallIsTerminated() {
        // given
        sut.handleIncomingCall(conversationId: oneOnOneConversationID,
                               messageTime: Date(),
                               client: AVSClient(userId: otherUserID, clientId: otherUserClientID),
                               isVideoCall: false,
                               shouldRing: true,
                               conversationType: .oneToOne)

        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        sut.handleEstablishedCall(conversationId: oneOnOneConversationID)
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))

        sut.handleConstantBitRateChange(enabled: true)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))

        // when
        sut.handleCallEnd(reason: .normal, conversationId: oneOnOneConversationID, messageTime: Date(), userId: otherUserID)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))

        // then
        XCTAssertFalse(sut.isContantBitRate(conversationId: oneOnOneConversationID))
    }
}

// MARK: - Network quality

extension WireCallCenterV3Tests {
    func testThatNetworkQualityIsNormalInitially() {
        // given
        sut.handleIncomingCall(conversationId: oneOnOneConversationID,
                               messageTime: Date(),
                               client: AVSClient(userId: otherUserID, clientId: otherUserClientID),
                               isVideoCall: false,
                               shouldRing: true,
                               conversationType: .oneToOne)

        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))

        // then
        XCTAssertEqual(sut.networkQuality(conversationId: oneOnOneConversationID), .normal)
    }

    func testThatNetworkQualityHandlerUpdatesTheQuality() {
        // given
        sut.handleIncomingCall(conversationId: oneOnOneConversationID,
                               messageTime: Date(),
                               client: AVSClient(userId: otherUserID, clientId: otherUserClientID),
                               isVideoCall: false,
                               shouldRing: true,
                               conversationType: .oneToOne)

        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        sut.handleEstablishedCall(conversationId: oneOnOneConversationID)
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        let quality = NetworkQuality.poor

        // when
        sut.handleNetworkQualityChange(conversationId: oneOnOneConversationID, client: AVSClient(userId: otherUserID, clientId: otherUserClientID), quality: quality)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))

        // then
        XCTAssertEqual(sut.networkQuality(conversationId: oneOnOneConversationID), quality)
    }
}

// Mark: - Muted state

extension WireCallCenterV3Tests {
    
    func testThatMutedStateHandlerUpdatesTheState() {
        class MuteObserver: MuteStateObserver {
            var muted: Bool? = nil
            func callCenterDidChange(muted: Bool) { self.muted = muted }
        }
        
        // given
        sut.handleIncomingCall(conversationId: oneOnOneConversationID,
                               messageTime: Date(),
                               client: AVSClient(userId: otherUserID, clientId: otherUserClientID),
                               isVideoCall: false,
                               shouldRing: true,
                               conversationType: .oneToOne)

        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        sut.handleEstablishedCall(conversationId: oneOnOneConversationID)
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        let observer = MuteObserver()
        let token = WireCallCenterV3.addMuteStateObserver(observer: observer, context: uiMOC)
        
        // when
        mockAVSWrapper.muted = true
        sut.handleMuteChange(muted: true)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        withExtendedLifetime(token) {
            XCTAssertEqual(true, observer.muted)
        }
    }
    
}

// MARK: - Ignoring Calls

extension WireCallCenterV3Tests {

    func testThatItWhenIgnoringACallItWillSetsTheCallStateToIncomingInactive() {
        // given
        sut.handleIncomingCall(conversationId: oneOnOneConversationID,
                               messageTime: Date(),
                               client: AVSClient(userId: otherUserID, clientId: otherUserClientID),
                               isVideoCall: false,
                               shouldRing: true,
                               conversationType: .oneToOne)

        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))

        // when
        sut.rejectCall(conversationId: oneOnOneConversationID)

        // then
        XCTAssertEqual(sut.callState(conversationId: oneOnOneConversationID), .incoming(video: false, shouldRing: false, degraded: false))
    }

    func testThatItWhenRejectingAOneOnOneCallItWilltSetTheCallStateToIncomingInactive() {
        // given
        sut.handleIncomingCall(conversationId: oneOnOneConversationID,
                               messageTime: Date(),
                               client: AVSClient(userId: otherUserID, clientId: otherUserClientID),
                               isVideoCall: false,
                               shouldRing: true,
                               conversationType: .oneToOne)

        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))

        // when
        sut.rejectCall(conversationId: oneOnOneConversationID)

        // then
        XCTAssertEqual(sut.callState(conversationId: oneOnOneConversationID), .incoming(video: false, shouldRing: false, degraded: false))
    }

    func testThatItWhenClosingAGroupCallItWillSetsTheCallStateToIncomingInactive() {
        // given
        sut.handleIncomingCall(conversationId: groupConversationID,
                               messageTime: Date(),
                               client: AVSClient(userId: otherUserID, clientId: otherUserClientID),
                               isVideoCall: false,
                               shouldRing: true,
                               conversationType: .group)

        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))

        // when
        sut.closeCall(conversationId: groupConversationID)

        // then
        XCTAssertEqual(sut.callState(conversationId: groupConversationID), .incoming(video: false, shouldRing: false, degraded: false))
    }

    func testThatItWhenClosingAOneOnOneCallItDoesNotSetTheCallStateToIncomingInactive() {
        // given
        sut.handleIncomingCall(conversationId: oneOnOneConversationID,
                               messageTime: Date(),
                               client: AVSClient(userId: otherUserID, clientId: otherUserClientID),
                               isVideoCall: false,
                               shouldRing: true,
                               conversationType: .oneToOne)

        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))

        // when
        sut.closeCall(conversationId: oneOnOneConversationID)

        // then
        XCTAssertNotEqual(sut.callState(conversationId: oneOnOneConversationID), .incoming(video: false, shouldRing: false, degraded: false))
    }

}

// MARK: - Participants

extension WireCallCenterV3Tests {

    func testThatItCreatesAParticipantSnapshotForAnIncomingCall() {
        // when
        sut.handleIncomingCall(conversationId: oneOnOneConversationID,
                               messageTime: Date(),
                               client: AVSClient(userId: otherUserID, clientId: otherUserClientID),
                               isVideoCall: false,
                               shouldRing: true,
                               conversationType: .oneToOne)

        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))

        // then
        let actual = sut.callParticipants(conversationId: oneOnOneConversationID)
        let expected = [CallParticipant(user: otherUser, clientId: otherUserClientID, state: .connecting)]
        XCTAssertEqual(actual, expected)
    }

    func callBackMemberHandler(conversationId: UUID, userId: UUID, clientId: String, audioEstablished: Bool) {
        let audioState = audioEstablished ? AudioState.established : .connecting
        let videoState = VideoState.stopped
        let microphoneState = MicrophoneState.unmuted
        let member = AVSParticipantsChange.Member(userid: userId, clientid: clientId, aestab: audioState, vrecv: videoState, muted: microphoneState)
        let change = AVSParticipantsChange(convid: conversationId, members: [member])
        
        let encoded = try! JSONEncoder().encode(change)
        let string = String(data: encoded, encoding: .utf8)!
        
        sut.handleParticipantChange(conversationId: conversationId, data: string)
    }
    
    func testThatItDoesNotIgnore_WhenGroupHandlerIsCalledForOneToOne() {
        // when
        _ = sut.startCall(conversation: oneOnOneConversation, video: false)
        callBackMemberHandler(conversationId: oneOnOneConversationID, userId: otherUserID, clientId: otherUserClientID, audioEstablished: false)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        let actual = sut.callParticipants(conversationId: oneOnOneConversationID)
        let expected = [CallParticipant(user: otherUser, clientId: otherUserClientID, state: .connecting)]
        XCTAssertEqual(actual, expected)
    }

    func testThatItUpdatesTheParticipantsWhenGroupHandlerIsCalled() {
        // when
        _ = sut.startCall(conversation: groupConversation, video: false)
        callBackMemberHandler(conversationId: groupConversationID, userId: otherUserID, clientId: otherUserClientID, audioEstablished: false)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))

        // then
        let actual = sut.callParticipants(conversationId: groupConversationID)
        let expected = [CallParticipant(user: otherUser, clientId: otherUserClientID, state: .connecting)]
        XCTAssertEqual(actual, expected)
    }

    func testThatItUpdatesTheStateForParticipant() {
        // when
        sut.handleIncomingCall(conversationId: groupConversationID,
                               messageTime: Date(),
                               client: AVSClient(userId: otherUserID, clientId: otherUserClientID),
                               isVideoCall: false,
                               shouldRing: true,
                               conversationType: .group)
        
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))

        // then
        var actual = sut.callParticipants(conversationId: groupConversationID)
        var expected = [CallParticipant(user: otherUser, clientId: otherUserClientID, state: .connecting)]
        XCTAssertEqual(actual, expected)

        // when
        callBackMemberHandler(conversationId: groupConversationID, userId: otherUserID, clientId: otherUserClientID, audioEstablished: true)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))

        // then
        actual = sut.callParticipants(conversationId: groupConversationID)
        expected = [CallParticipant(user: otherUser, clientId: otherUserClientID, state: .connected(videoState: .stopped, microphoneState: .unmuted))]
        XCTAssertEqual(actual, expected)
    }
}

// MARK: - Call Config

extension WireCallCenterV3Tests {
    
    func testThatCallConfigRequestsAreForwaredToTransportAndAVS() {
        // given
        mockTransport.mockCallConfigResponse = ("call_config", 200)
        
        // when
        sut.handleCallConfigRefreshRequest()
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertTrue(mockAVSWrapper.didUpdateCallConfig)
    }
    
}

// MARK: - Clients Request Handler

extension WireCallCenterV3Tests {

    func testThatClientsRequestHandlerSuccessfullyReturnsClientList() {
        // given
        let userId1 = UUID.create()
        let userId2 = UUID.create()

        mockTransport.mockClientsRequestResponse = [
            AVSClient(userId: userId1, clientId: "client1"),
            AVSClient(userId: userId1, clientId: "client2"),
            AVSClient(userId: userId2, clientId: "client1"),
            AVSClient(userId: userId2, clientId: "client2")
        ]

        // when
        sut.handleClientsRequest(conversationId: groupConversation.remoteIdentifier!) { json in
            do {
                // then
                let data = json.data(using: .utf8)!
                let clientList = try JSONDecoder().decode(WireSyncEngine.AVSClientList.self, from: data)

                let actual = Set(clientList.clients)
                let expected: Set<AVSClient> = [
                    AVSClient(userId: userId1, clientId: "client1"),
                    AVSClient(userId: userId1, clientId: "client2"),
                    AVSClient(userId: userId2, clientId: "client1"),
                    AVSClient(userId: userId2, clientId: "client2"),
                ]

                XCTAssertEqual(actual, expected)
            } catch {
                XCTFail()
            }
        }
    }

    private func createClients(for user: ZMUser, ids: String...) -> [UserClient] {
        return ids.map {
            let client = UserClient.insertNewObject(in: self.uiMOC)
            client.remoteIdentifier = $0
            client.user = user
            return client
        }
    }
}
