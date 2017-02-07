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
import ZMCDataModel
import Intents
@testable import zmessaging

@available(iOS 10.0, *)
class MockCallKitProvider: NSObject, CallKitProviderType {



    required init(configuration: CXProviderConfiguration) {
        
    }
    
    public var timesSetDelegateCalled: Int = 0
    func setDelegate(_ delegate: CXProviderDelegate?, queue: DispatchQueue?) {
        timesSetDelegateCalled += 1
    }
    
    public var timesReportNewIncomingCallCalled: Int = 0
    func reportNewIncomingCall(with UUID: UUID, update: CXCallUpdate, completion: @escaping (Error?) -> Void) {
        timesReportNewIncomingCallCalled += 1
    }
    
    public var timesReportCallUpdatedCalled: Int = 0
    public func reportCall(with UUID: UUID, updated update: CXCallUpdate) {
        timesReportCallUpdatedCalled += 1
    }
    
    public var timesReportCallEndedAtCalled: Int = 0
    public var lastEndedReason: UInt = 0
    public func reportCall(with UUID: UUID, endedAt dateEnded: Date?, reason endedReason: UInt) {
        timesReportCallEndedAtCalled += 1
        lastEndedReason = endedReason
    }
    
    public var timesReportOutgoingCallConnectedAtCalled: Int = 0
    func reportOutgoingCall(with UUID: UUID, connectedAt dateConnected: Date?) {
        timesReportOutgoingCallConnectedAtCalled += 1
    }
    
    public var timesReportOutgoingCallStartedConnectingCalled: Int = 0
    func reportOutgoingCall(with UUID: UUID, startedConnectingAt dateStartedConnecting: Date?) {
        timesReportOutgoingCallStartedConnectingCalled += 1
    }
}

@available(iOS 10.0, *)
class MockCallKitCallController: NSObject, CallKitCallController {
    public var callObserver: CXCallObserver? {
        return nil
    }
    
    public var timesRequestTransactionCalled: Int = 0
    public var requestedTransaction: CXTransaction? = .none
    
    
    @available(iOS 10.0, *)
    public func request(_ transaction: CXTransaction, completion: @escaping (Error?) -> Void) {
        timesRequestTransactionCalled = timesRequestTransactionCalled + 1
        requestedTransaction = transaction
        completion(.none)
    }
}

@available(iOS 10.0, *)
class ZMCallKitDelegateTest: MessagingTest {
    var sut: ZMCallKitDelegate!
    var callKitProvider: MockCallKitProvider!
    var callKitController: MockCallKitCallController!
    var mockWireCallCenterV3 : WireCallCenterV3Mock!
    
    func otherUser(moc: NSManagedObjectContext) -> ZMUser {
        let otherUser = ZMUser(context: moc)
        otherUser.remoteIdentifier = UUID()
        otherUser.name = "Other Test User"
        otherUser.emailAddress = "other@user.com"
        
        return otherUser
    }
    
    func createOneOnOneConversation(user: ZMUser) {
        let oneToOne = ZMConversation.insertNewObject(in: self.uiMOC)
        oneToOne.conversationType = .oneOnOne
        oneToOne.remoteIdentifier = UUID()
        
        let connection = ZMConnection.insertNewObject(in: self.uiMOC)
        connection.status = .accepted
        connection.conversation = oneToOne
        connection.to = user
    }
    
    func conversation(type: ZMConversationType = .oneOnOne, moc: NSManagedObjectContext? = .none) -> ZMConversation {
        let moc = moc ?? self.uiMOC
        let conversation = ZMConversation(context: moc)
        conversation.remoteIdentifier = UUID()
        conversation.conversationType = type
        conversation.isSelfAnActiveMember = true
        
        if type == .group {
            conversation.addParticipant(self.otherUser(moc: moc))
        }
        
        return conversation
    }
    
    override func setUp() {
        super.setUp()
        ZMUserSession.useCallKit = true
        
        let selfUser = ZMUser.selfUser(in: self.uiMOC)
        selfUser.emailAddress = "self@user.mail"
        selfUser.remoteIdentifier = UUID()
        
        let configuration = ZMCallKitDelegate.providerConfiguration()
        self.callKitProvider = MockCallKitProvider(configuration: configuration)
        self.callKitController = MockCallKitCallController()
        self.mockWireCallCenterV3 = WireCallCenterV3Mock(userId: selfUser.remoteIdentifier!, clientId: "123", registerObservers: false)
        self.mockWireCallCenterV3.overridenCallingProtocol = .version2
        
        self.sut = ZMCallKitDelegate(callKitProvider: self.callKitProvider,
                                     callController: self.callKitController,
                                     onDemandFlowManager: nil,
                                     userSession: self.mockUserSession,
                                     mediaManager: nil)
        
        ZMCallKitDelegateTestsMocking.mockUserSession(self.mockUserSession, callKitDelegate: self.sut)
    }
    
    override func tearDown() {
        ZMUserSession.useCallKit = false
        self.sut = nil
        self.mockWireCallCenterV3 = nil
        
        super.tearDown()
    }
    
    // Public API - provider configuration
    func testThatItReturnsTheProviderConfiguration() {
        // when
        let configuration = ZMCallKitDelegate.providerConfiguration()
        
        // then
        XCTAssertEqual(configuration.supportsVideo, true)
        XCTAssertEqual(configuration.localizedName, "zmessaging Test Host")
        XCTAssertTrue(configuration.supportedHandleTypes.contains(.generic))
    }
    
    func testThatItReturnsDefaultRingSound() {
        // when
        let configuration = ZMCallKitDelegate.providerConfiguration()
        
        // then
        XCTAssertEqual(configuration.ringtoneSound, "ringing_from_them_long.caf")
    }
    
    func testThatItReturnsCustomRingSound() {
        defer {
            UserDefaults.standard.removeObject(forKey: "ZMCallSoundName")
        }
        let customSoundName = "harp"
        // given
        UserDefaults.standard.setValue(customSoundName, forKey: "ZMCallSoundName")
        // when
        let configuration = ZMCallKitDelegate.providerConfiguration()
        
        // then
        XCTAssertEqual(configuration.ringtoneSound, customSoundName + ".m4a")
    }
    
    // Public API - outgoing calls
    func testThatItReportsTheStartCallRequest() {
        // given
        let user = otherUser(moc: self.uiMOC)
        createOneOnOneConversation(user: user)
        let conversation = user.oneToOneConversation!
        
        // when
        self.sut.requestStartCall(in: conversation, videoCall: false)
        
        // then
        XCTAssertEqual(self.callKitProvider.timesReportCallUpdatedCalled, 1)
        XCTAssertEqual(self.callKitController.timesRequestTransactionCalled, 1)
        XCTAssertTrue(self.callKitController.requestedTransaction!.actions.first! is CXStartCallAction)
        let action = self.callKitController.requestedTransaction!.actions.first! as! CXStartCallAction

        XCTAssertEqual(action.callUUID, conversation.remoteIdentifier)
        XCTAssertEqual(action.handle.type, .emailAddress)
        XCTAssertEqual(action.handle.value, user.emailAddress)
    }
    
    func testThatItReportsTheStartCallRequest_groupConversation() {
        // given
        let conversation = self.conversation(type: .group)
        
        // when
        self.sut.requestStartCall(in: conversation, videoCall: false)
        
        // then
        XCTAssertEqual(self.callKitProvider.timesReportCallUpdatedCalled, 1)
        XCTAssertEqual(self.callKitController.timesRequestTransactionCalled, 1)
        XCTAssertTrue(self.callKitController.requestedTransaction!.actions.first! is CXStartCallAction)
        
        let action = self.callKitController.requestedTransaction!.actions.first! as! CXStartCallAction
        XCTAssertEqual(action.callUUID, conversation.remoteIdentifier)
        XCTAssertEqual(action.handle.type, .generic)
        XCTAssertEqual(action.handle.value, conversation.remoteIdentifier?.transportString())
        XCTAssertFalse(action.isVideo)
    }
    
    func testThatItReportsTheStartCallRequest_Video() {
        // given
        let otherUser = self.otherUser(moc: self.uiMOC)
        createOneOnOneConversation(user: otherUser)
        let conversation = otherUser.oneToOneConversation!
        self.uiMOC.saveOrRollback()
        
        // when
        self.sut.requestStartCall(in: conversation, videoCall: true)
        
        // then
        XCTAssertEqual(self.callKitController.timesRequestTransactionCalled, 1)
        XCTAssertTrue(self.callKitController.requestedTransaction!.actions.first! is CXStartCallAction)
        let action = self.callKitController.requestedTransaction!.actions.first! as! CXStartCallAction
        
        XCTAssertEqual(action.callUUID, conversation.remoteIdentifier)
        XCTAssertEqual(action.handle.type, .emailAddress)
        XCTAssertEqual(action.handle.value, otherUser.emailAddress)
        XCTAssertTrue(action.isVideo)
    }
    
    // Public API - report end on outgoing call
    
    func testThatItReportsTheEndOfCall() {
        // given
        let conversation = self.conversation(type: .oneOnOne)
        
        // when
        self.sut.requestEndCall(in: conversation)
        
        // then
        XCTAssertEqual(self.callKitController.timesRequestTransactionCalled, 1)
        XCTAssertTrue(self.callKitController.requestedTransaction!.actions.first! is CXEndCallAction)
        
        let action = self.callKitController.requestedTransaction!.actions.first! as! CXEndCallAction
        XCTAssertEqual(action.callUUID, conversation.remoteIdentifier)
    }
    
    func testThatItReportsTheEndOfCall_groupConversation() {
        // given
        let conversation = self.conversation(type: .group)
        
        // when
        self.sut.requestEndCall(in: conversation)
        
        // then
        XCTAssertEqual(self.callKitController.timesRequestTransactionCalled, 1)
        XCTAssertTrue(self.callKitController.requestedTransaction!.actions.first! is CXEndCallAction)
        
        let action = self.callKitController.requestedTransaction!.actions.first! as! CXEndCallAction
        XCTAssertEqual(action.callUUID, conversation.remoteIdentifier)
    }
    
    // Public API - activity & intents
    
    func userActivityFor(contacts: [INPerson]?, isVideo: Bool = false) -> NSUserActivity {

        let intent: INIntent
        
        if isVideo {
            intent = INStartVideoCallIntent(contacts: contacts)
        }
        else {
            intent = INStartAudioCallIntent(contacts: contacts)
        }
            
        let interaction = INInteraction(intent: intent, response: .none)
        
        let activity = NSUserActivity(activityType: "voip")
        activity.setValue(interaction, forKey: "interaction")
        return activity
    }
    
    func testThatItStartsCallForUserKnownByEmail() {
        // given
        let otherUser = self.otherUser(moc: self.uiMOC)
        otherUser.emailAddress = "testThatItStartsCallForUserKnownByEmail@email.com"
        createOneOnOneConversation(user: otherUser)
        
        let handle = INPersonHandle(value: otherUser.emailAddress!, type: .emailAddress)
        let person = INPerson(personHandle: handle, nameComponents: .none, displayName: .none, image: .none, contactIdentifier: .none, customIdentifier: .none)
        
        let activity = self.userActivityFor(contacts: [person])
       
        // when
        self.sut.`continue`(activity)
        
        // then
        XCTAssertEqual(self.callKitController.timesRequestTransactionCalled, 1)
        XCTAssertTrue(self.callKitController.requestedTransaction!.actions.first! is CXStartCallAction)
        
        let action = self.callKitController.requestedTransaction!.actions.first! as! CXStartCallAction
        XCTAssertEqual(action.callUUID, otherUser.oneToOneConversation.remoteIdentifier)
        XCTAssertFalse(action.isVideo)
    }
    
    func testThatItStartsCallForUserKnownByPhone() {
        // given
        let otherUser = self.otherUser(moc: self.uiMOC)
        otherUser.emailAddress = nil
        otherUser.phoneNumber = "+123456789"
        createOneOnOneConversation(user: otherUser)
        
        let handle = INPersonHandle(value: otherUser.phoneNumber!, type: .phoneNumber)
        let person = INPerson(personHandle: handle, nameComponents: .none, displayName: .none, image: .none, contactIdentifier: .none, customIdentifier: .none)
        
        let activity = self.userActivityFor(contacts: [person])
        
        // when
        self.sut.`continue`(activity)
        
        // then
        XCTAssertEqual(self.callKitController.timesRequestTransactionCalled, 1)
        XCTAssertTrue(self.callKitController.requestedTransaction!.actions.first! is CXStartCallAction)
        
        let action = self.callKitController.requestedTransaction!.actions.first! as! CXStartCallAction
        XCTAssertEqual(action.callUUID, otherUser.oneToOneConversation.remoteIdentifier)
        XCTAssertFalse(action.isVideo)
    }
    
    func testThatItStartsCallForUserKnownByPhone_Video() {
        // given
        let otherUser = self.otherUser(moc: self.uiMOC)
        otherUser.emailAddress = nil
        otherUser.phoneNumber = "+123456789"
        createOneOnOneConversation(user: otherUser)
        
        let handle = INPersonHandle(value: otherUser.phoneNumber!, type: .phoneNumber)
        let person = INPerson(personHandle: handle, nameComponents: .none, displayName: .none, image: .none, contactIdentifier: .none, customIdentifier: .none)
        
        let activity = self.userActivityFor(contacts: [person], isVideo: true)
        
        // when
        self.sut.`continue`(activity)
        
        // then
        XCTAssertEqual(self.callKitController.timesRequestTransactionCalled, 1)
        XCTAssertTrue(self.callKitController.requestedTransaction!.actions.first! is CXStartCallAction)
        
        let action = self.callKitController.requestedTransaction!.actions.first! as! CXStartCallAction
        XCTAssertEqual(action.callUUID, otherUser.oneToOneConversation.remoteIdentifier)
        XCTAssertTrue(action.isVideo)
    }
    
    func testThatItStartsCallForGroup() {
        // given
        let conversation = self.conversation(type: .group)
        
        let handle = INPersonHandle(value: conversation.remoteIdentifier!.transportString(), type: .unknown)
        let person = INPerson(personHandle: handle, nameComponents: .none, displayName: .none, image: .none, contactIdentifier: .none, customIdentifier: .none)
        
        let activity = self.userActivityFor(contacts: [person])
        
        // when
        self.sut.`continue`(activity)
        
        // then
        XCTAssertEqual(self.callKitController.timesRequestTransactionCalled, 1)
        XCTAssertTrue(self.callKitController.requestedTransaction!.actions.first! is CXStartCallAction)
        
        let action = self.callKitController.requestedTransaction!.actions.first! as! CXStartCallAction
        XCTAssertEqual(action.callUUID, conversation.remoteIdentifier)
        XCTAssertFalse(action.isVideo)
    }
    
    func testThatItIgnoresUnknownActivity() {
        // given
        let activity = NSUserActivity(activityType: "random-handoff")
        
        // when
        self.sut.`continue`(activity)
        
        // then
        XCTAssertEqual(self.callKitController.timesRequestTransactionCalled, 0)
    }
    
    func testThatItIgnoresActivityWitoutContacts() {
        // given
        let activity = self.userActivityFor(contacts: [], isVideo: false)
        
        // when
        self.sut.`continue`(activity)
        
        // then
        XCTAssertEqual(self.callKitController.timesRequestTransactionCalled, 0)
    }
    
    func testThatItIgnoresActivityWithManyContacts() {
        // given

        let handle1 = INPersonHandle(value: "+987654321", type: .phoneNumber)
        let person1 = INPerson(personHandle: handle1, nameComponents: .none, displayName: .none, image: .none, contactIdentifier: .none, customIdentifier: .none)

        let handle2 = INPersonHandle(value: "+987654300", type: .phoneNumber)
        let person2 = INPerson(personHandle: handle2, nameComponents: .none, displayName: .none, image: .none, contactIdentifier: .none, customIdentifier: .none)

        let activity = self.userActivityFor(contacts: [person1, person2], isVideo: false)
        
        // when
        self.sut.`continue`(activity)
        
        // then
        XCTAssertEqual(self.callKitController.timesRequestTransactionCalled, 0)
    }
    
    func testThatItIgnoresActivityWithContactUnknown() {
        // given
        let otherUser = self.otherUser(moc: self.uiMOC)
        otherUser.emailAddress = nil
        otherUser.phoneNumber = "+123456789"
        createOneOnOneConversation(user: otherUser)
        
        let handle = INPersonHandle(value: "+987654321", type: .phoneNumber)
        let person = INPerson(personHandle: handle, nameComponents: .none, displayName: .none, image: .none, contactIdentifier: .none, customIdentifier: .none)
        
        let activity = self.userActivityFor(contacts: [person], isVideo: false)
        
        // when
        performIgnoringZMLogError {
            self.sut.`continue`(activity)
        }
        
        // then
        XCTAssertEqual(self.callKitController.timesRequestTransactionCalled, 0)
    }
    
    // Observer API V2 - report incoming call
    
    func testThatItIgnoresMutedConversations() {
        // FIXME update when design decision is taken
    }
    
    func testThatItReportNewIncomingCall_v2_Incoming() {
        // given
        let conversation = self.conversation()
        let mutableCallParticipants = conversation.mutableOrderedSetValue(forKey: ZMConversationCallParticipantsKey)
        mutableCallParticipants.add(self.otherUser(moc: self.uiMOC))
        
        // when
        self.sut.callCenterDidChange(voiceChannelState: .incomingCall, conversation: conversation)
        
        // then
        XCTAssertEqual(self.callKitProvider.timesReportNewIncomingCallCalled, 1)
        XCTAssertEqual(self.callKitProvider.timesReportOutgoingCallConnectedAtCalled, 0)
        XCTAssertEqual(self.callKitProvider.timesReportOutgoingCallStartedConnectingCalled, 0)
        XCTAssertEqual(self.callKitProvider.timesReportCallEndedAtCalled, 0)
    }
    
    func testThatItStoresConnectedConversation_v2_Answered() {
        // given
        let conversation = self.conversation()
        
        // when
        self.sut.callCenterDidChange(voiceChannelState: .selfIsJoiningActiveChannel, conversation: conversation)
        
        // then
        XCTAssertEqual(self.sut.connectedCallConversation, conversation)
        XCTAssertEqual(self.callKitProvider.timesReportOutgoingCallStartedConnectingCalled, 0)
        XCTAssertEqual(self.callKitProvider.timesReportOutgoingCallConnectedAtCalled, 0)
        XCTAssertEqual(self.callKitProvider.timesReportNewIncomingCallCalled, 0)
        XCTAssertEqual(self.callKitProvider.timesReportCallEndedAtCalled, 0)
    }
    
    func testThatItReportOutgoingCallConnectedAt_v2_Established() {
        // given
        let conversation = self.conversation()
        
        // when
        self.sut.callCenterDidChange(voiceChannelState: .selfConnectedToActiveChannel, conversation: conversation)
        
        // then
        XCTAssertEqual(self.callKitProvider.timesReportOutgoingCallConnectedAtCalled, 1)
        XCTAssertEqual(self.callKitProvider.timesReportOutgoingCallStartedConnectingCalled, 0)
        XCTAssertEqual(self.callKitProvider.timesReportNewIncomingCallCalled, 0)
        XCTAssertEqual(self.callKitProvider.timesReportCallEndedAtCalled, 0)
    }
    
    func testThatItReportOutgoingCallStartedConnecting_v2_OutgoingInGroupConversation() {
        // given
        let conversation = self.conversation(type: .group)
        
        // when
        self.sut.callCenterDidChange(voiceChannelState: .outgoingCall, conversation: conversation)
        
        // then
        XCTAssertEqual(self.callKitProvider.timesReportNewIncomingCallCalled, 0)
        XCTAssertEqual(self.callKitProvider.timesReportOutgoingCallConnectedAtCalled, 0)
        XCTAssertEqual(self.callKitProvider.timesReportOutgoingCallStartedConnectingCalled, 1)
        XCTAssertEqual(self.callKitProvider.timesReportCallEndedAtCalled, 0)
    }
    
    func testThatItReportNewIncomingCall_v2_IncomingInGroupConversation() {
        // given
        let conversation = self.conversation(type: .group)
        let mutableCallParticipants = conversation.mutableOrderedSetValue(forKey: ZMConversationCallParticipantsKey)
        mutableCallParticipants.add(self.otherUser(moc: self.uiMOC))
        
        // when
        self.sut.callCenterDidChange(voiceChannelState: .incomingCall, conversation: conversation)
        
        // then
        XCTAssertEqual(self.callKitProvider.timesReportNewIncomingCallCalled, 1)
        XCTAssertEqual(self.callKitProvider.timesReportOutgoingCallConnectedAtCalled, 0)
        XCTAssertEqual(self.callKitProvider.timesReportOutgoingCallStartedConnectingCalled, 0)
        XCTAssertEqual(self.callKitProvider.timesReportCallEndedAtCalled, 0)
    }
    
    // Observer API V2 - report end of call
    
    func testThatItReportCallEndedAt_v2_answered() {
        // given
        let conversation = self.conversation(type: .group)
        sut.connectedCallConversation = conversation
        
        // when
        sut.callCenterDidChange(voiceChannelState: .noActiveUsers, conversation: conversation)
        
        // then
        XCTAssertEqual(self.callKitProvider.timesReportCallEndedAtCalled, 1)
        XCTAssertEqual(self.callKitProvider.lastEndedReason, UInt(CXCallEndedReason.remoteEnded.rawValue))
    }
    
    func testThatItReportCallEndedAt_v2_unanswered() {
        // given
        let conversation = self.conversation(type: .group)
        
        // when
        sut.callCenterDidChange(voiceChannelState: .noActiveUsers, conversation: conversation)
        
        // then
        XCTAssertEqual(self.callKitProvider.timesReportCallEndedAtCalled, 1)
        XCTAssertEqual(self.callKitProvider.lastEndedReason, UInt(CXCallEndedReason.unanswered.rawValue))
    }
    
    // Observer API V3
    
    func testThatItReportNewIncomingCall_v3_Incoming() {
        // given
        let conversation = self.conversation()
        let otherUser = self.otherUser(moc: self.uiMOC)
        
        // when
        sut.callCenterDidChange(callState: .incoming(video: false), conversationId: conversation.remoteIdentifier!, userId: otherUser.remoteIdentifier!)
        
        // then
        XCTAssertEqual(self.callKitProvider.timesReportNewIncomingCallCalled, 1)
        XCTAssertEqual(self.callKitProvider.timesReportOutgoingCallConnectedAtCalled, 0)
        XCTAssertEqual(self.callKitProvider.timesReportOutgoingCallStartedConnectingCalled, 0)
        XCTAssertEqual(self.callKitProvider.timesReportCallEndedAtCalled, 0)
    }
    
    func testThatItReportOutgoingCallStartedConnecting_v3_Answered() {
        // given
        let conversation = self.conversation()
        let otherUser = self.otherUser(moc: self.uiMOC)
        
        // when
        sut.callCenterDidChange(callState: .answered, conversationId: conversation.remoteIdentifier!, userId: otherUser.remoteIdentifier!)
        
        // then
        XCTAssertEqual(self.callKitProvider.timesReportNewIncomingCallCalled, 0)
        XCTAssertEqual(self.callKitProvider.timesReportOutgoingCallConnectedAtCalled, 0)
        XCTAssertEqual(self.callKitProvider.timesReportOutgoingCallStartedConnectingCalled, 1)
        XCTAssertEqual(self.callKitProvider.timesReportCallEndedAtCalled, 0)
    }
    
    func testThatItReportOutgoingCallStartedConnecting_v3_Established() {
        // given
        let conversation = self.conversation()
        let otherUser = self.otherUser(moc: self.uiMOC)
        
        // when
        sut.callCenterDidChange(callState: .established, conversationId: conversation.remoteIdentifier!, userId: otherUser.remoteIdentifier!)
        
        // then
        XCTAssertEqual(self.callKitProvider.timesReportNewIncomingCallCalled, 0)
        XCTAssertEqual(self.callKitProvider.timesReportOutgoingCallConnectedAtCalled, 1)
        XCTAssertEqual(self.callKitProvider.timesReportOutgoingCallStartedConnectingCalled, 0)
        XCTAssertEqual(self.callKitProvider.timesReportCallEndedAtCalled, 0)
    }
    
    func testThatItReportCallEndedAt_v3_Terminating_normal() {
        // given
        let conversation = self.conversation()
        let otherUser = self.otherUser(moc: self.uiMOC)
        
        // when
        sut.callCenterDidChange(callState: .terminating(reason: .normal), conversationId: conversation.remoteIdentifier!, userId: otherUser.remoteIdentifier!)
        
        // then
        XCTAssertEqual(self.callKitProvider.timesReportNewIncomingCallCalled, 0)
        XCTAssertEqual(self.callKitProvider.timesReportOutgoingCallConnectedAtCalled, 0)
        XCTAssertEqual(self.callKitProvider.timesReportOutgoingCallStartedConnectingCalled, 0)
        XCTAssertEqual(self.callKitProvider.timesReportCallEndedAtCalled, 1)
        XCTAssertEqual(self.callKitProvider.lastEndedReason, UInt(CXCallEndedReason.remoteEnded.rawValue))
    }
    
    func testThatItReportCallEndedAt_v3_Terminating_lostMedia() {
        // given
        let conversation = self.conversation()
        let otherUser = self.otherUser(moc: self.uiMOC)
        
        // when
        sut.callCenterDidChange(callState: .terminating(reason: .lostMedia), conversationId: conversation.remoteIdentifier!, userId: otherUser.remoteIdentifier!)
        
        // then
        XCTAssertEqual(self.callKitProvider.lastEndedReason, UInt(CXCallEndedReason.failed.rawValue))
    }
    
    func testThatItReportCallEndedAt_v3_Terminating_timeout() {
        // given
        let conversation = self.conversation()
        let otherUser = self.otherUser(moc: self.uiMOC)
        
        // when
        sut.callCenterDidChange(callState: .terminating(reason: .timeout), conversationId: conversation.remoteIdentifier!, userId: otherUser.remoteIdentifier!)
        
        // then
        XCTAssertEqual(self.callKitProvider.lastEndedReason, UInt(CXCallEndedReason.unanswered.rawValue))
    }
    
    func testThatItReportCallEndedAt_v3_Terminating_answeredElsewhere() {
        // given
        let conversation = self.conversation()
        let otherUser = self.otherUser(moc: self.uiMOC)
        
        // when
        sut.callCenterDidChange(callState: .terminating(reason: .anweredElsewhere), conversationId: conversation.remoteIdentifier!, userId: otherUser.remoteIdentifier!)
        
        // then
        XCTAssertEqual(self.callKitProvider.lastEndedReason, UInt(CXCallEndedReason.answeredElsewhere.rawValue))
    }
    
    func testThatItDoesntReportCallEndedAt_v3_Terminating_normalSelf() {
        // given
        let conversation = self.conversation()
        let selfUser = ZMUser.selfUser(in: self.uiMOC)
        
        // when
        sut.callCenterDidChange(callState: .terminating(reason: .normal), conversationId: conversation.remoteIdentifier!, userId: selfUser.remoteIdentifier!)
        
        // then
        XCTAssertEqual(self.callKitProvider.timesReportCallEndedAtCalled, 0)
    }
    
}
