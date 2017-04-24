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
    
    func selfIgnoreCall(){
        userSession.performChanges{
            self.conversationUnderTest.voiceChannelRouter?.v3.ignore()
        }
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout:0.5))
    }
    
    func otherStartCall(user: ZMUser, isVideoCall: Bool = false, shouldRing: Bool = true) {
        (WireCallCenterV3.activeInstance as! WireCallCenterV3Mock).mockAVSCallState = .incoming(video: isVideoCall, shouldRing: shouldRing)

        let userIdRef = user.remoteIdentifier!.transportString().cString(using: .utf8)
        WireSyncEngine.incomingCallHandler(conversationId: conversationIdRef, userId: userIdRef, isVideoCall: isVideoCall ? 1 : 0, shouldRing: shouldRing ? 1 : 0, contextRef: wireCallCenterRef)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
    }
    
    func otherJoinCall(user: ZMUser) {
        (WireCallCenterV3.activeInstance as! WireCallCenterV3Mock).mockAVSCallState = .answered

        if useGroupConversation {
            participantsChanged(members: [(user: user, establishedFlow: false)])
        } else {
            WireSyncEngine.answeredCallHandler(conversationId: conversationIdRef, contextRef: wireCallCenterRef)
            XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        }
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
        WireSyncEngine.establishedCallHandler(conversationId: conversationIdRef, userId: userIdRef, contextRef: wireCallCenterRef)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
    }
    
    func participantsChanged(members: [(user: ZMUser, establishedFlow: Bool)]) {
        let mappedMembers = members.map{CallMember(userId: $0.user.remoteIdentifier!, audioEstablished: $0.establishedFlow)}
        (WireCallCenterV3.activeInstance as! WireCallCenterV3Mock).mockMembers = mappedMembers

        WireSyncEngine.groupMemberHandler(conversationIdRef: conversationIdRef, contextRef: wireCallCenterRef)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
    }

    func closeCall(user: ZMUser, reason: CallClosedReason) {
        (WireCallCenterV3.activeInstance as! WireCallCenterV3Mock).mockAVSCallState = .none

        let userIdRef = user.remoteIdentifier!.transportString().cString(using: .utf8)
        WireSyncEngine.closedCallHandler(reason: reason.rawValue, conversationId: conversationIdRef, userId: userIdRef, contextRef: wireCallCenterRef)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
    }
    
    func simulateMissedCall(user: ZMUser) {
        otherStartCall(user: user)

        let userIdRef = user.remoteIdentifier!.transportString().cString(using: .utf8)
        WireSyncEngine.missedCallHandler(conversationId: conversationIdRef, messageTime: UInt32(Date().timeIntervalSince1970), userId: userIdRef, isVideoCall: 0, contextRef: wireCallCenterRef)
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
    
    func testJoiningAndLeavingAnVoiceChannel_Group_2ParticipantsLeft(){
        // given
        XCTAssertTrue(logInAndWaitForSyncToBeComplete());
        useGroupConversation = true
        stateObserver.observe(conversation: conversationUnderTest, context: uiMOC)
        
        // when
        selfJoinCall(isStart: true)
        
        // then
        XCTAssertEqual(stateObserver.changes.count, 1)
        stateObserver.checkLastNotificationHasCallState(.outgoingCall)
        
        // when
        (WireCallCenterV3.activeInstance as! WireCallCenterV3Mock).mockAVSCallState = .answered
        participantsChanged(members: [(user: conversationUnderTest.otherActiveParticipants.firstObject as! ZMUser, establishedFlow: false),
                                      (user: conversationUnderTest.otherActiveParticipants.lastObject as! ZMUser, establishedFlow: false)])
        stateObserver.changes = []

        // when
        selfDropCall()
        
        // then
        XCTAssertEqual(stateObserver.changes.count, 1)
        stateObserver.checkLastNotificationHasCallState(.incomingCallInactive)

        // and when
        closeCall(user: self.localSelfUser, reason: .canceled)

        XCTAssertEqual(stateObserver.changes.count, 2)
        stateObserver.checkLastNotificationHasCallState(.noActiveUsers)
    }
    
    func testJoiningAndLeavingAnEmptyVoiceChannel_Group(){
        // given
        XCTAssertTrue(logInAndWaitForSyncToBeComplete());
        useGroupConversation = true
        stateObserver.observe(conversation: conversationUnderTest, context: uiMOC)
        
        // when
        selfJoinCall(isStart: true)
        
        // then
        XCTAssertEqual(stateObserver.changes.count, 1)
        stateObserver.checkLastNotificationHasCallState(.outgoingCall)
        stateObserver.changes = []
        
        // when
        selfDropCall()
        
        // then
        XCTAssertEqual(stateObserver.changes.count, 0)
        
        // and when
        closeCall(user: self.localSelfUser, reason: .canceled)
        
        XCTAssertEqual(stateObserver.changes.count, 1)
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
    
    func testThatItSendsOutAllExpectedNotificationsWhenSelfUserCalls_Group() {
        
        // no active users -> self is calling -> self connected to active channel -> no active users
        
        // given
        XCTAssertTrue(logInAndWaitForSyncToBeComplete())
        useGroupConversation = true
        
        stateObserver.observe(conversation: conversationUnderTest, context: uiMOC)
        participantObserver.observe(conversation: conversationUnderTest, context: uiMOC)
        
        // (1) self calling & backend acknowledges
        //
        // when
        selfJoinCall(isStart: true)
        
        // then
        XCTAssertEqual(stateObserver.changes.count, 1)
        stateObserver.checkLastNotificationHasCallState(.outgoingCall)
        XCTAssertEqual(participantObserver.changes.count, 0)
        
        // (2) other party joins
        //
        // when
        let otherUser = conversationUnderTest.otherActiveParticipants.firstObject as! ZMUser
        participantsChanged(members: [(user: otherUser, establishedFlow: false)])
        
        // then
        XCTAssertEqual(participantObserver.changes.count, 0)
        
        // (3) flow aquired
        //
        // when
        participantsChanged(members: [(user: otherUser, establishedFlow: true)])
        
        // then
        XCTAssertEqual(participantObserver.changes.count, 1)
        if let partInfo =  participantObserver.changes.last {
            XCTAssertEqual(partInfo.insertedIndexes, [])
            XCTAssertEqual(partInfo.updatedIndexes, [0])
            XCTAssertEqual(partInfo.deletedIndexes, [])
            XCTAssertEqual(partInfo.movedIndexPairs, [])
        }
        
        // (4) self user leaves
        //
        // when
        selfDropCall()
        closeCall(user: self.localSelfUser, reason: .canceled)
        
        // then
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

    func testThatItSendsOutAllExpectedNotificationsWhenOtherUserCalls_Group() {
        // given
        XCTAssertTrue(logInAndWaitForSyncToBeComplete())
        useGroupConversation = true
        stateObserver.observe(conversation: conversationUnderTest, context: uiMOC)
        participantObserver.observe(conversation: conversationUnderTest, context: uiMOC)
        
        let user = conversationUnderTest.otherActiveParticipants.firstObject as! ZMUser
        
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
        
        participantObserver.changes.removeAll()
        
        // (3) flow aquired
        // when
        participantsChanged(members: [(user: user, establishedFlow: true)])
        establishedFlow(user: localSelfUser)

        // then
        XCTAssertEqual(stateObserver.changes.count, 3)
        stateObserver.checkLastNotificationHasCallState(.selfConnectedToActiveChannel)
        XCTAssertEqual(participantObserver.changes.count, 1) // we notify that user connected
        
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
        selfIgnoreCall()
        
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
    

    func testThatItFiresAConversationChangeNotificationWhenAGroupCallIsDeclined() {
        // given
        XCTAssertTrue(logInAndWaitForSyncToBeComplete())
        useGroupConversation = true
        
        let user = conversationUnderTest.otherActiveParticipants.firstObject as! ZMUser
        let convObserver = ConversationChangeObserver(conversation: conversationUnderTest)

        // (1) Other user calls
        // when
        otherStartCall(user: user)

        // then
        XCTAssertEqual(conversationUnderTest.conversationListIndicator, .none)
        
        // (2) Self ignores call
        // and when
        selfIgnoreCall()
        
        // then
        XCTAssertEqual(convObserver!.notifications.count, 2)
        if let change = convObserver!.notifications.lastObject as? ConversationChangeInfo {
            XCTAssertTrue(change.conversationListIndicatorChanged)
        }
        XCTAssertEqual(conversationUnderTest.conversationListIndicator, .inactiveCall)
        
        // (2) Other user ends call
        // and when
        closeCall(user: user, reason: .canceled)
        
        // then
        XCTAssertEqual(convObserver!.notifications.count, 3)
        if let change = convObserver!.notifications.lastObject as? ConversationChangeInfo {
            XCTAssertTrue(change.conversationListIndicatorChanged)
        }
        XCTAssertEqual(conversationUnderTest.conversationListIndicator, .none)
    }

    func testThatItFiresAConversationChangeNotificationWhenAGroupCallIsJoined() {
        // given
        XCTAssertTrue(logInAndWaitForSyncToBeComplete())
        useGroupConversation = true
        
        let localUser1 = conversationUnderTest.otherActiveParticipants.firstObject as! ZMUser
        let localUser2 = conversationUnderTest.otherActiveParticipants.lastObject as! ZMUser
        let convObserver = ConversationChangeObserver(conversation: conversationUnderTest)
        
        // (1) Other user calls
        // when
        otherStartCall(user: localUser1)
        
        // then
        XCTAssertEqual(conversationUnderTest.conversationListIndicator, .none)
        
        // (2) Self joins the call
        // and when
        selfJoinCall(isStart: false)

        // second user joins        
        participantsChanged(members: [(user: localUser1, establishedFlow: false),
                                      (user: localUser2, establishedFlow: false)])

        // then
        XCTAssertEqual(convObserver!.notifications.count, 2)
        if let change = convObserver!.notifications.lastObject as? ConversationChangeInfo {
            XCTAssertTrue(change.conversationListIndicatorChanged)
        }
        XCTAssertEqual(conversationUnderTest.conversationListIndicator, .activeCall)
        
        // (3) selfUser user ends call
        // and when
        selfDropCall()
        
        // then
        XCTAssertEqual(convObserver!.notifications.count, 3)
        if let change = convObserver!.notifications.lastObject as? ConversationChangeInfo {
            XCTAssertTrue(change.conversationListIndicatorChanged)
        }
        XCTAssertEqual(conversationUnderTest.conversationListIndicator, .inactiveCall)
        
        // (4) other user ends call
        // and when
        closeCall(user: localUser1, reason: .canceled)
        
        // then
        XCTAssertEqual(convObserver!.notifications.count, 4)
        if let change = convObserver!.notifications.lastObject as? ConversationChangeInfo {
            XCTAssertTrue(change.conversationListIndicatorChanged)
        }
        XCTAssertEqual(conversationUnderTest.conversationListIndicator, .none)
    }
    
    func testThatItCanIgnoreACallAndReinitiateNewCallWhenCallEnded(){
        // given
        XCTAssertTrue(logInAndWaitForSyncToBeComplete())
        useGroupConversation = true
        let user = conversationUnderTest.otherActiveParticipants.firstObject as! ZMUser
        
        // Other user calls
        otherStartCall(user: user)
        
        // Self ignores call
        selfIgnoreCall()
        
        // Other user ends call
        closeCall(user: user, reason: .canceled)
        XCTAssertEqual(conversationUnderTest.voiceChannel?.state, .noActiveUsers)

        // SelfUser calls
        // when
        selfJoinCall(isStart: true)
        
        // then
        XCTAssertEqual(conversationUnderTest.voiceChannel?.state, .outgoingCall)
    }
    
    func testThatItCanIgnoreACallAndSeeNewCallWhenCallEnded(){
        // given
        XCTAssertTrue(logInAndWaitForSyncToBeComplete())
        useGroupConversation = true
        let user = conversationUnderTest.otherActiveParticipants.firstObject as! ZMUser
        
        // Other user calls
        otherStartCall(user: user)
        
        // Self ignores call
        selfIgnoreCall()
        
        // Other user ends call
        closeCall(user: user, reason: .canceled)
        XCTAssertEqual(conversationUnderTest.voiceChannel?.state, .noActiveUsers)
        
        // Other user calls
        // when
        otherStartCall(user: user)
        
        // then
        XCTAssertEqual(conversationUnderTest.voiceChannel?.state, .incomingCall)
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
    
    func testThatItCreatesAPerformedCallSystemMessageWhenTheCallIsEnded() {
        
        // given
        XCTAssertTrue(logInAndWaitForSyncToBeComplete())
        fetchAllClients()
        let user = conversationUnderTest.connectedUser!
        let messageCount = conversationUnderTest.messages.count;
    
        // when
        otherStartCall(user: user)
        selfJoinCall(isStart: false)
        establishedFlow(user: user)
        closeCall(user: user, reason: .canceled)
        
        // we receive a performed call systemMessage
        XCTAssertEqual(conversationUnderTest.messages.count, messageCount+1)
        guard let systemMessage = conversationUnderTest.messages.lastObject as? ZMSystemMessage
            else {
                return XCTFail("Did not insert a system message")
        }
        
        XCTAssertNotNil(systemMessage.systemMessageData);
        XCTAssertEqual(systemMessage.systemMessageData?.systemMessageType, ZMSystemMessageType.performedCall);
    }
    
    func testThatThePerformedCallSystemMessageUnarchivesTheConversation() {
        // given
        XCTAssertTrue(logInAndWaitForSyncToBeComplete())
        fetchAllClients()
        let user = conversationUnderTest.connectedUser!
        
        self.userSession.performChanges {
            self.conversationUnderTest.isArchived = true
        }
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        XCTAssertTrue(conversationUnderTest.isArchived)
        let messageCount = conversationUnderTest.messages.count;

        // when
        otherStartCall(user: user)
        selfJoinCall(isStart: false)
        establishedFlow(user: user)
        closeCall(user: user, reason: .canceled)
        
        // the conversation is unarchived
        XCTAssertEqual(conversationUnderTest.messages.count, messageCount+1)
        XCTAssertFalse(conversationUnderTest.isArchived)
    }
    
}

