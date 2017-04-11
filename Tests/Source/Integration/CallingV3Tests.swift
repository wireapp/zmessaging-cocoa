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
import WireDataModel
@testable import WireSyncEngine

struct V2CallStateChange {
    let conversation : ZMConversation
    let state : VoiceChannelV2State
}

class VoiceChannelStateTestObserver : VoiceChannelStateObserver {

    var changes : [V2CallStateChange] = []
    var token : WireCallCenterObserverToken?
    
    func observe(conversation: ZMConversation, context: NSManagedObjectContext) {
        token = WireCallCenter.addVoiceChannelStateObserver(observer: self, context: context)
    }

    func callCenterDidEndCall(reason: VoiceChannelV2CallEndReason, conversation: ZMConversation, callingProtocol: CallingProtocol) {
        //
    }
    
    func callCenterDidFailToJoinVoiceChannel(error: Error?, conversation: ZMConversation) {
        //
    }
    
    func callCenterDidChange(voiceChannelState: VoiceChannelV2State, conversation: ZMConversation, callingProtocol: CallingProtocol) {
        changes.append(V2CallStateChange(conversation: conversation, state: voiceChannelState))
    }
    
    func checkLastNotificationHasCallState(_ callState: VoiceChannelV2State, line: UInt = #line, file : StaticString = #file) {
        guard let change = changes.last else {
            return XCTFail("Did not receive a notification", file: file, line: line)
        }
        XCTAssertEqual(change.state.rawValue, callState.rawValue, file: file, line: line)
    }
}

class VoiceChannelParticipantTestObserver : VoiceChannelParticipantObserver {
    
    var changes : [VoiceChannelParticipantNotification] = []
    var token : WireCallCenterObserverToken?
    
    func observe(conversation: ZMConversation, context: NSManagedObjectContext) {
        token = WireCallCenter.addVoiceChannelParticipantObserver(observer: self, forConversation: conversation, context: context)
    }
    
    func voiceChannelParticipantsDidChange(_ changeInfo: VoiceChannelParticipantNotification) {
        changes.append(changeInfo)
    }
}

class CallingV3Tests : IntegrationTestBase {
    
    var stateObserver : VoiceChannelStateTestObserver!
    var participantObserver : VoiceChannelParticipantTestObserver!
    
    override func setUp() {
        super.setUp()
        stateObserver = VoiceChannelStateTestObserver()
        participantObserver = VoiceChannelParticipantTestObserver()
    }
    
    override func tearDown() {
        stateObserver = nil
        super.tearDown()
    }
    
    func selfJoinCall(isStart: Bool) {
        userSession.enqueueChanges {
            _ = self.conversationUnderTest.voiceChannelRouter?.v3.join(video: false)
            if isStart {
                (WireCallCenterV3.activeInstance as! WireCallCenterV3Mock).mockAVSCallState = .outgoing
            } else {
                (WireCallCenterV3.activeInstance as! WireCallCenterV3Mock).mockAVSCallState = .answered
            }
        }
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
    }
    
    func selfDropCall(){
        (WireCallCenterV3.activeInstance as! WireCallCenterV3Mock).mockAVSCallState = .terminating(reason: .canceled)

        userSession.enqueueChanges {
            self.conversationUnderTest.voiceChannelRouter?.v3.leave()
        }
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
    }
    
    func otherStartCall(user: ZMUser, isVideoCall: Bool = false, shouldRing: Bool = true) {
        (WireCallCenterV3.activeInstance as! WireCallCenterV3Mock).mockAVSCallState = .incoming(video: isVideoCall)

        let userIdRef = user.remoteIdentifier!.transportString().cString(using: .utf8)
        WireSyncEngine.IncomingCallHandler(conversationId: conversationIdRef, userId: userIdRef, isVideoCall: isVideoCall ? 1 : 0, contextRef: wireCallCenterRef)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
    }
    
    func otherJoinCall(user: ZMUser) {
        (WireCallCenterV3.activeInstance as! WireCallCenterV3Mock).mockAVSCallState = .answered
        WireSyncEngine.AnsweredCallHandler(conversationId: conversationIdRef, contextRef: wireCallCenterRef)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
    }
    
    private var wireCallCenterRef : UnsafeMutableRawPointer? {
        return Unmanaged<WireCallCenterV3>.passUnretained(WireCallCenterV3.activeInstance!).toOpaque()
    }
    
    private var conversationIdRef : [CChar]? {
        return conversationUnderTest.remoteIdentifier!.transportString().cString(using: .utf8)
    }
    
    func establishedFlow(user: ZMUser){
        (WireCallCenterV3.activeInstance as! WireCallCenterV3Mock).mockAVSCallState = .established

        let userIdRef = user.remoteIdentifier!.transportString().cString(using: .utf8)
        WireSyncEngine.EstablishedCallHandler(conversationId: conversationIdRef, userId: userIdRef, contextRef: wireCallCenterRef)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
    }

    func closeCall(user: ZMUser, reason: CallClosedReason) {
        (WireCallCenterV3.activeInstance as! WireCallCenterV3Mock).mockAVSCallState = .none

        let userIdRef = user.remoteIdentifier!.transportString().cString(using: .utf8)
        WireSyncEngine.ClosedCallHandler(reason: reason.rawValue, conversationId: conversationIdRef, userId: userIdRef, metrics: nil, contextRef: wireCallCenterRef)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
    }
    
    func simulateMissedCall(user: ZMUser) {
        otherStartCall(user: user)

        let userIdRef = user.remoteIdentifier!.transportString().cString(using: .utf8)
        WireSyncEngine.MissedCallHandler(conversationId: conversationIdRef, messageTime: UInt32(Date().timeIntervalSince1970), userId: userIdRef, isVideoCall: 0, contextRef: wireCallCenterRef)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
    }
    
    var useGroupConversation : Bool = false
    var mockConversationUnderTest : MockConversation {
        return useGroupConversation ? groupConversation : selfToUser2Conversation
    }
    
    var conversationUnderTest : ZMConversation {
        return conversation(for: mockConversationUnderTest)
    }
    
    var localSelfUser : ZMUser {
        return user(for: selfUser)
    }
    
    func testJoiningAndLeavingAnEmptyVoiceChannel_OneOnOne(){
        // given
        XCTAssertTrue(logInAndWaitForSyncToBeComplete());
        stateObserver.observe(conversation: conversationUnderTest, context: uiMOC)

        // when
        selfJoinCall(isStart: true)
        
        // then
        XCTAssertEqual(stateObserver.changes.count, 1)
        stateObserver.checkLastNotificationHasCallState(.outgoingCall)
        
        // when
        selfDropCall()
        closeCall(user: self.localSelfUser, reason: .canceled)
        
        // then
        XCTAssertEqual(stateObserver.changes.count, 2)
        stateObserver.checkLastNotificationHasCallState(.noActiveUsers)
    }
    
    func testThatItSendsOutAllExpectedNotificationsWhenSelfUserCalls_OneOnOne() {
    
        // given
        XCTAssertTrue(logInAndWaitForSyncToBeComplete())
        stateObserver.observe(conversation: conversationUnderTest, context: uiMOC)

        // (1) self calling & backend acknowledges
        //
        // when
        selfJoinCall(isStart: true)
        
        // then
        XCTAssertEqual(stateObserver.changes.count, 1)
        stateObserver.checkLastNotificationHasCallState(.outgoingCall)
        
        // (2) other party joins
        //
        // when
        let user = conversationUnderTest.connectedUser!
        otherJoinCall(user: user)
        
        // then
        XCTAssertEqual(stateObserver.changes.count, 2)
        stateObserver.checkLastNotificationHasCallState(.selfIsJoiningActiveChannel)

        // (3) flow aquired
        //
        // when
        establishedFlow(user: user)
        
        // then
        XCTAssertEqual(stateObserver.changes.count, 3)
        stateObserver.checkLastNotificationHasCallState(.selfConnectedToActiveChannel)
        
        // (4) self user leaves
        //
        // when
        selfDropCall()
        closeCall(user: self.localSelfUser, reason: .canceled)
        
        // then
        XCTAssertEqual(stateObserver.changes.count, 4)
        stateObserver.checkLastNotificationHasCallState(.noActiveUsers)
    }
    
    
    func testThatItSendsOutAllExpectedNotificationsWhenOtherUserCalls_OneOnOne() {
        // given
        XCTAssertTrue(logInAndWaitForSyncToBeComplete())
        stateObserver.observe(conversation: conversationUnderTest, context: uiMOC)

        let user = conversationUnderTest.connectedUser!

        // (1) other user joins
        // when
        otherStartCall(user: user)
        
        // then
        XCTAssertEqual(stateObserver.changes.count, 1)
        stateObserver.checkLastNotificationHasCallState(.incomingCall)
        
        // (2) we join
        // when
        selfJoinCall(isStart: false)
        
        // then
        XCTAssertEqual(stateObserver.changes.count, 2)
        stateObserver.checkLastNotificationHasCallState(.selfIsJoiningActiveChannel)
        
        // (3) flow aquired
        // when
        establishedFlow(user: localSelfUser)
        
        // then
        XCTAssertEqual(stateObserver.changes.count, 3)
        stateObserver.checkLastNotificationHasCallState(.selfConnectedToActiveChannel)
        
        // (4) the other user leaves
        // when
        closeCall(user: user, reason: .canceled)
        
        // then
        XCTAssertEqual(stateObserver.changes.count, 4)
        stateObserver.checkLastNotificationHasCallState(.noActiveUsers)
    }

    func testThatItSendsANotificationWhenWeIgnoreACall() {
        // given
        XCTAssertTrue(logInAndWaitForSyncToBeComplete())
        stateObserver.observe(conversation: conversationUnderTest, context: uiMOC)
        let user = conversationUnderTest.connectedUser!

        // (1) other user joins
        // when
        otherStartCall(user: user)
        
        // then
        XCTAssertEqual(stateObserver.changes.count, 1)
        stateObserver.checkLastNotificationHasCallState(.incomingCall)
        
        // (2) we ignore
        // when
        userSession.performChanges{
            self.conversationUnderTest.voiceChannelRouter?.v3.ignore()
        }
        XCTAssert(waitForCustomExpectations(withTimeout: 0.5))
        
        // then
        XCTAssertEqual(stateObserver.changes.count, 2)
        stateObserver.checkLastNotificationHasCallState(.noActiveUsers)
    }
    
    func testThatItSendsANotificationIfIgnoringACallAndImmediatelyAcceptingIt() {
        
        // given
        XCTAssertTrue(logInAndWaitForSyncToBeComplete())
        stateObserver.observe(conversation: conversationUnderTest, context: uiMOC)
        let user = conversationUnderTest.connectedUser!

        // (1) other user joins and we ignore
        // when
        otherStartCall(user: user)

        userSession.performChanges{
            self.conversationUnderTest.voiceChannelRouter?.v3.ignore()
        }
        XCTAssert(waitForCustomExpectations(withTimeout: 0.5))
        
        // then
        XCTAssertEqual(stateObserver.changes.count, 2)
        stateObserver.checkLastNotificationHasCallState(.noActiveUsers)

        // (2) we join
        // when
        selfJoinCall(isStart: false)
        
        // then
        XCTAssertEqual(stateObserver.changes.count, 3)
        stateObserver.checkLastNotificationHasCallState(.selfIsJoiningActiveChannel)
    }
    
    
}


// MARK - SystemMessages
extension CallingV3Tests {
    
    func fetchAllClients(){
        userSession.performChanges {
            self.conversationUnderTest.appendMessage(withText: "foo") // make sure we have all clients
        }
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        spinMainQueue(withTimeout: 1.5)
    }

    func testThatItCreatesASystemMessageWhenWeMissedACall(){
        
        // given
        XCTAssertTrue(logInAndWaitForSyncToBeComplete())
        let user = conversationUnderTest.connectedUser!
        fetchAllClients()

        let messageCount = conversationUnderTest.messages.count;
        
        // expect
        expectation(forNotification: WireSyncEngine.WireCallCenterMissedCallNotification.notificationName.rawValue, object: nil)

        // when
        simulateMissedCall(user: user)
        XCTAssert(waitForCustomExpectations(withTimeout: 0.5))
        
        // then
        // we receive a systemMessage that we missed a call
        XCTAssertEqual(conversationUnderTest.messages.count, messageCount+1)
        guard let systemMessage = conversationUnderTest.messages.lastObject as? ZMSystemMessage
        else {
            return XCTFail("Did not insert a system message")
        }
        
        XCTAssertNotNil(systemMessage.systemMessageData);
        XCTAssertEqual(systemMessage.systemMessageData?.systemMessageType, ZMSystemMessageType.missedCall);
    }
    
    func testThatTheMissedCallSystemMessageUnarchivesTheConversation(){
        // given
        XCTAssertTrue(logInAndWaitForSyncToBeComplete())
        fetchAllClients()

        self.userSession.performChanges {
            self.conversationUnderTest.isArchived = true
        }
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))

        let user = conversationUnderTest.connectedUser!
        let messageCount = conversationUnderTest.messages.count;

        // expect
        expectation(forNotification: WireSyncEngine.WireCallCenterMissedCallNotification.notificationName.rawValue, object: nil)
        
        // when
        simulateMissedCall(user: user)
        XCTAssert(waitForCustomExpectations(withTimeout: 0.5))
        
        // then
        XCTAssertEqual(conversationUnderTest.messages.count, messageCount+1)
        XCTAssertFalse(conversationUnderTest.isArchived)
    }
    
    func testThatItDoesNotCreateASystemMessageWhenTheCallIsEndedWithoutBeingMissed() {
        
        // given
        XCTAssertTrue(logInAndWaitForSyncToBeComplete())
        fetchAllClients()
        let user = conversationUnderTest.connectedUser!
        let messageCount = conversationUnderTest.messages.count;
    
        // when
        otherStartCall(user: user)
        closeCall(user: user, reason: .canceled)
        
        // we DO NOT receive a systemMessage
        XCTAssertEqual(conversationUnderTest.messages.count, messageCount)
    }
}

