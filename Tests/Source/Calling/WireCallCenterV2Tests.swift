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
import WireTesting


private class CallStateRecorder : WireCallCenterV2CallStateObserver {
    
    var callStates : [VoiceChannelV2State] = []
    
    fileprivate func callCenterDidChange(voiceChannelState: VoiceChannelV2State, conversation: ZMConversation) {
        callStates.append(voiceChannelState)
    }
    
}


private class ReceivedVideoRecorder : ReceivedVideoObserver {
    
    var receivedVideoStates : [ReceivedVideoState] = []
    
    fileprivate func callCenterDidChange(receivedVideoState: ReceivedVideoState) {
        receivedVideoStates.append(receivedVideoState)
    }
    
}

private class VoiceGainRecorder : VoiceGainObserver {
    
    var voiceGainChanges : [(ZMUser, Float)] = []
    
    fileprivate func voiceGainDidChange(forParticipant participant: ZMUser, volume: Float) {
        voiceGainChanges.append((participant, volume))
    }
    
}

private class MutableAVSVideoStateChangeInfo : AVSVideoStateChangeInfo {

    var mutableReason : AVSFlowManagerVideoReason = .FLOWMANAGER_VIDEO_NORMAL
    var mutableState : AVSFlowManagerVideoReceiveState = .FLOWMANAGER_VIDEO_RECEIVE_STOPPED
    
    fileprivate override var reason: AVSFlowManagerVideoReason {
        return mutableReason
    }
    
    fileprivate override var state: AVSFlowManagerVideoReceiveState {
        return mutableState
    }
    
}

class WireCallCenterV2Tests : MessagingTest {
    
    private var conversation : ZMConversation!
    private var user1 : ZMUser!
    private var user2 : ZMUser!
    private var token : WireCallCenterObserverToken?
    private var sut : WireCallCenterV2 {
        return uiMOC.wireCallCenterV2
    }
    
    override func setUp() {
        super.setUp()
        
        user1 = ZMUser.insertNewObject(in: self.uiMOC)
        user1.name = "User 1"
        user1.remoteIdentifier = UUID()
        
        user2 = ZMUser.insertNewObject(in: self.uiMOC)
        user2.name = "User 2"
        user2.remoteIdentifier = UUID()
        
        conversation = ZMConversation.insertNewObject(in: self.uiMOC)
        conversation.conversationType = .oneOnOne
        conversation.remoteIdentifier = UUID()
        conversation.internalAddParticipants(Set<ZMUser>(arrayLiteral: user1), isAuthoritative: true)
        
        ZMUserSession.callingProtocolStrategy = .version2
        self.uiMOC.saveOrRollback()
        
        // make sure sut is initialized
        _ = sut

    }

    override func tearDown() {
        uiMOC.userInfo[NSManagedObjectContext.WireCallCenterV2Key] = nil
        ZMUserSession.callingProtocolStrategy = .negotiate
        if let token = token {
            WireCallCenterV2.removeObserver(token: token)
        }
        super.tearDown()
    }
    
    private func notifyCallStateChange(in conversations: [ZMConversation]) {
        sut.callStateDidChange(conversations: Set(conversations))
    }
    
    // MARK - call state observer
    func testThatInstanceDoesNotHaveRetainCycles() {
        weak var callCenter = uiMOC.wireCallCenterV2
        uiMOC.userInfo[NSManagedObjectContext.WireCallCenterV2Key] = nil
        XCTAssertNil(callCenter)
    }
    
    func testThatConversationCallStateChangeTriggerCallStateChange() {
        // given
        conversation.callDeviceIsActive = true
        let observer = CallStateRecorder()
        token = WireCallCenterV2.addVoiceChannelStateObserver(observer: observer, context: uiMOC)
        
        // when
        notifyCallStateChange(in: [conversation])
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertEqual(observer.callStates, [.outgoingCall])
    }
    
    func testThatCallParticipantChangeTriggerCallStateChange() {
        // given
        let observer = CallStateRecorder()
        token = WireCallCenterV2.addVoiceChannelStateObserver(observer: observer, context: uiMOC)
        
        // when
        conversation.voiceChannelRouter?.v2.addCallParticipant(user1)
        uiMOC.saveOrRollback()
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertEqual(observer.callStates, [.incomingCall])
    }
    
    func testThatRepeatedCallParticipantChangesDoesntTriggerCallStateChange() {
        // given
        let observer = CallStateRecorder()
        token = WireCallCenterV2.addVoiceChannelStateObserver(observer: observer, context: uiMOC)
        
        // when
        conversation.voiceChannelRouter?.v2.addCallParticipant(user1)
        uiMOC.saveOrRollback()
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        conversation.voiceChannelRouter?.v2.addCallParticipant(user2)
        uiMOC.saveOrRollback()
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertEqual(observer.callStates, [.incomingCall])
    }
    
    // MARK - voice channel participant observer
    
    func testThatInsertedCallParticipantTriggerParticipantChange() {
        // given
        let observer = VoiceChannelParticipantTestObserver()
        token = WireCallCenterV2.addVoiceChannelParticipantObserver(observer: observer, forConversation: conversation, context: uiMOC)
        
        // when
        conversation.voiceChannelRouter?.v2.addCallParticipant(user1)
        uiMOC.saveOrRollback()
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertEqual(observer.changes.first!.insertedIndexes, IndexSet(integer: 0))
    }
    
    func testThatRemovedCallParticipantTriggerParticipantChange() {
        // given
        let observer = VoiceChannelParticipantTestObserver()
        token = WireCallCenterV2.addVoiceChannelParticipantObserver(observer: observer, forConversation: conversation, context: uiMOC)
        
        // when
        conversation.voiceChannelRouter?.v2.addCallParticipant(user1)
        uiMOC.saveOrRollback()
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        conversation.voiceChannelRouter?.v2.removeCallParticipant(user1)
        uiMOC.saveOrRollback()
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertEqual(observer.changes.first!.insertedIndexes, IndexSet(integer: 0))
        XCTAssertEqual(observer.changes.last!.deletedIndexes, IndexSet(integer: 0))
    }
    
    func testThatAddingActiveFlowParticipantTriggerParticpantChange() {
        // given
        let observer = VoiceChannelParticipantTestObserver()
        token = WireCallCenterV2.addVoiceChannelParticipantObserver(observer: observer, forConversation: conversation, context: uiMOC)
        
        // when
        conversation.voiceChannelRouter?.v2.addCallParticipant(user1)
        uiMOC.saveOrRollback()
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        conversation.activeFlowParticipants = NSOrderedSet(array: [user1])
        notifyCallStateChange(in: [conversation])
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertEqual(observer.changes.first!.insertedIndexes, IndexSet(integer: 0))
        XCTAssertEqual(observer.changes.last!.updatedIndexes, IndexSet(integer: 0))
    }
    
    // MARK - Received video observer
    
    func testThatOtherActiveVideoCallParticipantsTriggerReceivedVideoStarted() {
        // given
        let observer = ReceivedVideoRecorder()
        token = WireCallCenterV2.addReceivedVideoObserver(observer: observer, forConversation: conversation, context: uiMOC)
        
        // when
        conversation.isFlowActive = true
        conversation.otherActiveVideoCallParticipants = Set([user1])
        notifyCallStateChange(in: [conversation])
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertEqual(observer.receivedVideoStates, [.started])
    }
    
    func testThatOtherActiveVideoCallParticipantsRemovalTriggerReceivedVideoStopped() {
        // given
        let observer = ReceivedVideoRecorder()
        token = WireCallCenterV2.addReceivedVideoObserver(observer: observer, forConversation: conversation, context: uiMOC)
        
        // when
        conversation.isFlowActive = true
        conversation.otherActiveVideoCallParticipants = Set([user1])
        notifyCallStateChange(in: [conversation])
        
        conversation.otherActiveVideoCallParticipants = Set()
        notifyCallStateChange(in: [conversation])
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertEqual(observer.receivedVideoStates, [.started, .stopped])
    }
    
    func testThatFlowManagerUpdateTriggerReceivedVideoBadConnection() {
        // given
        let observer = ReceivedVideoRecorder()
        token = WireCallCenterV2.addReceivedVideoObserver(observer: observer, forConversation: conversation, context: uiMOC)
        
        // when
        conversation.isFlowActive = true
        conversation.otherActiveVideoCallParticipants = Set([user1])
        notifyCallStateChange(in: [conversation])
        
        let videoStateChangeInfo = MutableAVSVideoStateChangeInfo()
        videoStateChangeInfo.mutableReason = .FLOWMANAGER_VIDEO_BAD_CONNECTION
        videoStateChangeInfo.mutableState = .FLOWMANAGER_VIDEO_RECEIVE_STOPPED
        NotificationCenter.default.post(name: NSNotification.Name(rawValue: FlowManagerVideoReceiveStateNotification), object: videoStateChangeInfo)
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertEqual(observer.receivedVideoStates, [.started, .badConnection])
    }
    
    func testThatFlowManagerUpdateTriggerReceivedVideoBadStopped() {
        // given
        let observer = ReceivedVideoRecorder()
        token = WireCallCenterV2.addReceivedVideoObserver(observer: observer, forConversation: conversation, context: uiMOC)
        
        // when
        conversation.isFlowActive = true
        conversation.otherActiveVideoCallParticipants = Set([user1])
        notifyCallStateChange(in: [conversation])
        
        let videoStateChangeInfo = MutableAVSVideoStateChangeInfo()
        videoStateChangeInfo.mutableReason = .FLOWMANAGER_VIDEO_NORMAL
        videoStateChangeInfo.mutableState = .FLOWMANAGER_VIDEO_RECEIVE_STOPPED
        NotificationCenter.default.post(name: NSNotification.Name(rawValue: FlowManagerVideoReceiveStateNotification), object: videoStateChangeInfo)
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        XCTAssertEqual(observer.receivedVideoStates, [.started, .stopped])
    }
    
    // MARK - voice gain observer
    
    func testThatVoiceGainNotificationsTriggerVoiceGainChanges() {
        // given
        let observer =  VoiceGainRecorder()
        token = WireCallCenterV2.addVoiceGainObserver(observer: observer, forConversation: conversation, context: uiMOC)
        
        // when
        VoiceGainNotification(volume: 0.5, conversationId: conversation.remoteIdentifier!, userId: user1.remoteIdentifier!).post()
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        
        // then
        let (participant, volume) = observer.voiceGainChanges.first!
        XCTAssertEqual(participant, user1)
        XCTAssertEqual(volume, 0.5)
    }
    
}
