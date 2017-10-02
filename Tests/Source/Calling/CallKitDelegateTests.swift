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
import WireDataModel
import Intents
import CallKit
import OCMock

@testable import WireSyncEngine

@available(iOS 10.0, *)
class MockCallKitProvider: CXProvider {

    public var timesSetDelegateCalled: Int = 0
    override func setDelegate(_ delegate: CXProviderDelegate?, queue: DispatchQueue?) {
        timesSetDelegateCalled += 1
    }
    
    public var timesReportNewIncomingCallCalled: Int = 0
    public override func reportNewIncomingCall(with UUID: UUID, update: CXCallUpdate, completion: @escaping (Error?) -> Void) {
        timesReportNewIncomingCallCalled += 1
    }
    
    public var timesReportCallUpdatedCalled: Int = 0
    public override func reportCall(with UUID: UUID, updated update: CXCallUpdate) {
        timesReportCallUpdatedCalled += 1
    }
    
    public var timesReportCallEndedAtCalled: Int = 0
    public var lastEndedReason: CXCallEndedReason = .answeredElsewhere
    override func reportCall(with UUID: UUID, endedAt dateEnded: Date?, reason endedReason: CXCallEndedReason) {
        timesReportCallEndedAtCalled += 1
        lastEndedReason = endedReason
    }
    
    public var timesReportOutgoingCallConnectedAtCalled: Int = 0
    override func reportOutgoingCall(with UUID: UUID, connectedAt dateConnected: Date?) {
        timesReportOutgoingCallConnectedAtCalled += 1
    }
    
    public var timesReportOutgoingCallStartedConnectingCalled: Int = 0
    override func reportOutgoingCall(with UUID: UUID, startedConnectingAt dateStartedConnecting: Date?) {
        timesReportOutgoingCallStartedConnectingCalled += 1
    }
    
    public var isInvalidated : Bool = false
    override func invalidate() {
        isInvalidated = true
    }

}

@available(iOS 10.0, *)
class MockCallObserver : CXCallObserver {
    
    public var mockCalls : [CXCall] = []
    
    override var calls: [CXCall] {
        return mockCalls
    }
    
}

@available(iOS 10.0, *)
class MockCallKitCallController: CXCallController {
    
    public override var callObserver: CXCallObserver {
        return mockCallObserver
    }
    
    public var mockTransactionErrorCode : CXErrorCodeRequestTransactionError?
    public var mockErrorCount : Int = 0
    public var timesRequestTransactionCalled: Int = 0
    public var requestedTransactions: [CXTransaction] = []
    public let mockCallObserver = MockCallObserver()
    
    public override func request(_ transaction: CXTransaction, completion: @escaping (Error?) -> Void) {
        timesRequestTransactionCalled = timesRequestTransactionCalled + 1
        requestedTransactions.append(transaction)
        if mockErrorCount >= 1 {
            mockErrorCount = mockErrorCount-1
            completion(mockTransactionErrorCode)
        } else {
            completion(.none)
        }
    }
}

@available(iOS 10.0, *)
class MockCallAnswerAction : CXAnswerCallAction {
    
    var isFulfilled : Bool = false
    var hasFailed : Bool = false
    
    override func fulfill(withDateConnected dateConnected: Date) {
        isFulfilled = true
    }
    
    override func fail() {
        hasFailed = true
    }
    
}

@available(iOS 10.0, *)
class MockStartCallAction : CXStartCallAction {
    
    var isFulfilled : Bool = false
    var hasFailed : Bool = false
    
    override func fulfill() {
        isFulfilled = true
    }
    
    override func fail() {
        hasFailed = true
    }
    
}

@available(iOS 10.0, *)
class MockProvider : CXProvider {
    
    var isConnected : Bool = false
    var hasStartedConnecting = false
    
    
    convenience init(foo: Bool) {
        self.init(configuration: CXProviderConfiguration(localizedName: "test"))
    }
    
    override func reportOutgoingCall(with UUID: UUID, startedConnectingAt dateStartedConnecting: Date?) {
        hasStartedConnecting = true
    }
    
    override func reportOutgoingCall(with UUID: UUID, connectedAt dateConnected: Date?) {
        isConnected = true
    }
    
}

@available(iOS 10.0, *)
class CallKitDelegateTest: MessagingTest {
    var sut: CallKitDelegate!
    var callKitProvider: MockCallKitProvider!
    var callKitController: MockCallKitCallController!
    var mockWireCallCenterV3 : WireCallCenterV3Mock!
    
    func otherUser(moc: NSManagedObjectContext) -> ZMUser {
        let otherUser = ZMUser(context: moc)
        otherUser.remoteIdentifier = UUID()
        otherUser.name = "Other Test User"
        
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
        
        let selfUser = ZMUser.selfUser(in: self.uiMOC)
        selfUser.remoteIdentifier = UUID()
        
        let flowManager = FlowManagerMock()
        let configuration = CallKitDelegate.providerConfiguration
        self.callKitProvider = MockCallKitProvider(configuration: configuration)
        self.callKitController = MockCallKitCallController()
        self.mockWireCallCenterV3 = WireCallCenterV3Mock(userId: selfUser.remoteIdentifier!, clientId: "123", uiMOC: uiMOC, flowManager: flowManager, transport: WireCallCenterTransportMock())
        
        self.sut = CallKitDelegate(provider: self.callKitProvider,
                                   callController: self.callKitController,
                                   userSession: self.mockUserSession,
                                   flowManager: flowManager,
                                   mediaManager: nil)
        
        mockUserSession.callKitDelegate = sut
        CallKitDelegateTestsMocking.mockUserSession(self.mockUserSession, callKitDelegate: self.sut)
        
        self.uiMOC.zm_callCenter = mockWireCallCenterV3
    }
    
    override func tearDown() {
        self.sut = nil
        self.mockWireCallCenterV3 = nil
        
        super.tearDown()
    }
    
    // Public API - provider configuration
    func testThatItReturnsTheProviderConfiguration() {
        // when
        let configuration = CallKitDelegate.providerConfiguration
        
        // then
        XCTAssertEqual(configuration.supportsVideo, true)
        XCTAssertEqual(configuration.localizedName, "WireSyncEngine Test Host")
        XCTAssertTrue(configuration.supportedHandleTypes.contains(.generic))
    }
    
    func testThatItReturnsDefaultRingSound() {
        // when
        let configuration = CallKitDelegate.providerConfiguration
        
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
        let configuration = CallKitDelegate.providerConfiguration
        
        // then
        XCTAssertEqual(configuration.ringtoneSound, customSoundName + ".m4a")
    }
    
    func testThatItInvalidatesTheProviderOnDeinit() {
        // given
        sut = CallKitDelegate(provider: self.callKitProvider,
                              callController: self.callKitController,
                              userSession: self.mockUserSession,
                              flowManager: FlowManagerMock(),
                              mediaManager: nil)
        
        // when
        sut = nil
        
        // then
        XCTAssertTrue(callKitProvider.isInvalidated)
    }
    
    // Public API - outgoing calls
    func testThatItReportsTheStartCallRequest() {
        // given
        let user = otherUser(moc: self.uiMOC)
        createOneOnOneConversation(user: user)
        let conversation = user.oneToOneConversation!
        
        // when
        self.sut.requestJoinCall(in: conversation, video: false)
        
        // then
        XCTAssertEqual(self.callKitProvider.timesReportCallUpdatedCalled, 0)
        XCTAssertEqual(self.callKitController.timesRequestTransactionCalled, 1)
        XCTAssertTrue(self.callKitController.requestedTransactions.first!.actions.first! is CXStartCallAction)
        let action = self.callKitController.requestedTransactions.first!.actions.first! as! CXStartCallAction

        XCTAssertEqual(action.callUUID, conversation.remoteIdentifier)
        XCTAssertEqual(action.handle.type, .generic)
        XCTAssertEqual(action.handle.value, conversation.remoteIdentifier?.transportString())
    }
    
    func testThatItReportsTheStartCallRequest_groupConversation() {
        // given
        let conversation = self.conversation(type: .group)
        
        // when
        self.sut.requestJoinCall(in: conversation, video: false)
        
        // then
        XCTAssertEqual(self.callKitProvider.timesReportCallUpdatedCalled, 0)
        XCTAssertEqual(self.callKitController.timesRequestTransactionCalled, 1)
        XCTAssertTrue(self.callKitController.requestedTransactions.first!.actions.first! is CXStartCallAction)
        
        let action = self.callKitController.requestedTransactions.first!.actions.first! as! CXStartCallAction
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
        self.sut.requestJoinCall(in: conversation, video: true)
        
        // then
        XCTAssertEqual(self.callKitController.timesRequestTransactionCalled, 1)
        XCTAssertTrue(self.callKitController.requestedTransactions.first!.actions.first! is CXStartCallAction)
        let action = self.callKitController.requestedTransactions.first!.actions.first! as! CXStartCallAction
        
        XCTAssertEqual(action.callUUID, conversation.remoteIdentifier)
        XCTAssertEqual(action.handle.type, .generic)
        XCTAssertEqual(action.handle.value, conversation.remoteIdentifier?.transportString())
        XCTAssertTrue(action.isVideo)
    }
    
    func testThatItReportsTheStartCallRequest_CallAlreadyExists() {
        // given
        let otherUser = self.otherUser(moc: self.uiMOC)
        createOneOnOneConversation(user: otherUser)
        let conversation = otherUser.oneToOneConversation!
        self.uiMOC.saveOrRollback()
        
        self.callKitController.mockErrorCount = 1
        let error = NSError(domain: CXErrorDomainRequestTransaction, code: CXErrorCodeRequestTransactionError.Code.callUUIDAlreadyExists.rawValue, userInfo: nil)
        self.callKitController.mockTransactionErrorCode = CXErrorCodeRequestTransactionError(_nsError: error)
        
        // when
        self.sut.requestJoinCall(in: conversation, video: true)
        
        // then
        XCTAssertEqual(self.callKitController.timesRequestTransactionCalled, 2)
        XCTAssertTrue(self.callKitController.requestedTransactions.first!.actions.first! is CXStartCallAction)
        XCTAssertTrue(self.callKitController.requestedTransactions.last!.actions.first! is CXAnswerCallAction)

        let action = self.callKitController.requestedTransactions.last!.actions.last! as! CXAnswerCallAction
        XCTAssertEqual(action.callUUID, conversation.remoteIdentifier)
    }
    
    func testThatItReportsTheAnswerCallRequest_IfThereExistingIncomingCall() {
        // given
        let otherUser = self.otherUser(moc: self.uiMOC)
        createOneOnOneConversation(user: otherUser)
        let conversation = otherUser.oneToOneConversation!
        self.uiMOC.saveOrRollback()
        
        let call = CallKitDelegateTestsMocking.mockCall(with: conversation.remoteIdentifier!, outgoing: false)
        self.callKitController.mockCallObserver.mockCalls = [call]
        
        mockWireCallCenterV3.mockCallState = .incoming(video: true, shouldRing: true, degraded: false)
        
        // when
        self.sut.requestJoinCall(in: conversation, video: true)
        
        // then
        XCTAssertEqual(self.callKitController.timesRequestTransactionCalled, 1)
        
        let action = self.callKitController.requestedTransactions.last!.actions.last! as! CXAnswerCallAction
        XCTAssertEqual(action.callUUID, conversation.remoteIdentifier)
        
        // teardown
        CallKitDelegateTestsMocking.stopMock(call)
    }
    
    // Actions - answer / start call
    
    /* Disabled for now, pending furter investigation
    func testThatCallAnswerActionIsFulfilledWhenCallIsEstablished() {
        // given
        let provider = MockProvider(foo: true)
        let conversation = self.conversation(type: .oneOnOne)
        let action = MockCallAnswerAction(call: conversation.remoteIdentifier!)
        
        // when
        self.sut.provider(provider, perform: action)
        mockWireCallCenterV3.update(callState: .established, conversationId: conversation.remoteIdentifier!)
        
        // then
        XCTAssertTrue(action.isFulfilled)
    }
    
    func testThatCallAnswerActionFailWhenCallCantBeJoined() {
        // given
        let provider = MockProvider(foo: true)
        let conversation = self.conversation(type: .oneOnOne)
        let action = MockCallAnswerAction(call: conversation.remoteIdentifier!)
        
        // when
        self.sut.provider(provider, perform: action)
        NotificationCenter.default.post(name: NSNotification.Name.ZMConversationVoiceChannelJoinFailed, object: conversation.remoteIdentifier!)
        
        // then
        XCTAssertTrue(action.hasFailed)
    }
     */
    
    func testThatStartCallActionIsFulfilledWhenCallIsJoined() {
        // given
        let provider = MockProvider(foo: true)
        let conversation = self.conversation(type: .oneOnOne)
        let action = MockStartCallAction(call: conversation.remoteIdentifier!, handle: CXHandle(type: CXHandle.HandleType.generic, value: conversation.remoteIdentifier!.transportString()))
        
        // when
        self.sut.provider(provider, perform: action)
        
        // then
        XCTAssertTrue(action.isFulfilled)
    }
    
    func testThatStartCallActionFailWhenCallCantBeStarted() {
        // given
        let provider = MockProvider(foo: true)
        let conversation = self.conversation(type: .oneOnOne)
        let action = MockStartCallAction(call: conversation.remoteIdentifier!, handle: CXHandle(type: CXHandle.HandleType.generic, value: conversation.remoteIdentifier!.transportString()))
        mockWireCallCenterV3.startCallShouldFail = true
        
        // when
        self.sut.provider(provider, perform: action)
        
        // then
        XCTAssertTrue(action.hasFailed)
    }
        
    func testThatStartCallActionUpdatesWhenTheCallHasStartedConnecting() {
        // given
        let provider = MockProvider(foo: true)
        let conversation = self.conversation(type: .oneOnOne)
        let action = MockStartCallAction(call: conversation.remoteIdentifier!, handle: CXHandle(type: CXHandle.HandleType.generic, value: conversation.remoteIdentifier!.transportString()))
        
        // when
        self.sut.provider(provider, perform: action)
        mockWireCallCenterV3.update(callState: .answered(degraded: false), conversationId: conversation.remoteIdentifier!)
        
        // then
        XCTAssertTrue(provider.hasStartedConnecting)
    }
    
    func testThatStartCallActionUpdatesWhenTheCallHasConnected() {
        // given
        let provider = MockProvider(foo: true)
        let conversation = self.conversation(type: .oneOnOne)
        let action = MockStartCallAction(call: conversation.remoteIdentifier!, handle: CXHandle(type: CXHandle.HandleType.generic, value: conversation.remoteIdentifier!.transportString()))
        
        // when
        self.sut.provider(provider, perform: action)
        mockWireCallCenterV3.update(callState: .established, conversationId: conversation.remoteIdentifier!)
        
        // then
        XCTAssertTrue(provider.isConnected)
    }
    
    // Public API - report end on outgoing call
    
    func testThatItReportsTheEndOfCall() {
        // given
        let conversation = self.conversation(type: .oneOnOne)
        
        // when
        self.sut.requestEndCall(in: conversation)
        
        // then
        XCTAssertEqual(self.callKitController.timesRequestTransactionCalled, 1)
        XCTAssertTrue(self.callKitController.requestedTransactions.first!.actions.first! is CXEndCallAction)
        
        let action = self.callKitController.requestedTransactions.first!.actions.first! as! CXEndCallAction
        XCTAssertEqual(action.callUUID, conversation.remoteIdentifier)
    }
    
    func testThatItReportsTheEndOfCall_groupConversation() {
        // given
        let conversation = self.conversation(type: .group)
        
        // when
        self.sut.requestEndCall(in: conversation)
        
        // then
        XCTAssertEqual(self.callKitController.timesRequestTransactionCalled, 1)
        XCTAssertTrue(self.callKitController.requestedTransactions.first!.actions.first! is CXEndCallAction)
        
        let action = self.callKitController.requestedTransactions.first!.actions.first! as! CXEndCallAction
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
    
    func testThatItStartsCallForGroup() {
        // given
        let conversation = self.conversation(type: .group)
        let identifier = conversation.remoteIdentifier!.transportString()
        let handle = INPersonHandle(value: identifier, type: .unknown)
        let person = INPerson(personHandle: handle, nameComponents: .none, displayName: .none, image: .none, contactIdentifier: .none, customIdentifier: identifier)
        
        let activity = self.userActivityFor(contacts: [person])
        
        // when
        _ = sut.continueUserActivity(activity)
        
        // then
        XCTAssertEqual(self.callKitController.timesRequestTransactionCalled, 1)
        XCTAssertTrue(self.callKitController.requestedTransactions.first!.actions.first! is CXStartCallAction)
        
        let action = self.callKitController.requestedTransactions.first!.actions.first! as! CXStartCallAction
        XCTAssertEqual(action.callUUID, conversation.remoteIdentifier)
        XCTAssertFalse(action.isVideo)
    }
    
    func testThatItIgnoresUnknownActivity() {
        // given
        let activity = NSUserActivity(activityType: "random-handoff")
        
        // when
        _ = sut.continueUserActivity(activity)
        
        // then
        XCTAssertEqual(self.callKitController.timesRequestTransactionCalled, 0)
    }
    
    func testThatItIgnoresActivityWitoutContacts() {
        // given
        let activity = self.userActivityFor(contacts: [], isVideo: false)
        
        // when
        _ = sut.continueUserActivity(activity)
        
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
        _ = sut.continueUserActivity(activity)
        
        // then
        XCTAssertEqual(self.callKitController.timesRequestTransactionCalled, 0)
    }
    
    func testThatItIgnoresActivityWithContactUnknown() {
        // given
        let otherUser = self.otherUser(moc: self.uiMOC)
        createOneOnOneConversation(user: otherUser)
        
        let handle = INPersonHandle(value: "+987654321", type: .phoneNumber)
        let person = INPerson(personHandle: handle, nameComponents: .none, displayName: .none, image: .none, contactIdentifier: .none, customIdentifier: .none)
        
        let activity = self.userActivityFor(contacts: [person], isVideo: false)
        
        // when
        performIgnoringZMLogError {
            _ = self.sut.continueUserActivity(activity)
        }
        
        // then
        XCTAssertEqual(self.callKitController.timesRequestTransactionCalled, 0)
    }
    
    // Observer API V3
    
    func testThatItReportNewIncomingCall_v3_Incoming() {
        // given
        let conversation = self.conversation()
        let otherUser = self.otherUser(moc: self.uiMOC)
        
        // when
        sut.callCenterDidChange(callState: .incoming(video: false, shouldRing: true, degraded: false), conversation: conversation, user: otherUser, timeStamp: nil)
        
        // then
        XCTAssertEqual(self.callKitProvider.timesReportNewIncomingCallCalled, 1)
        XCTAssertEqual(self.callKitProvider.timesReportOutgoingCallConnectedAtCalled, 0)
        XCTAssertEqual(self.callKitProvider.timesReportOutgoingCallStartedConnectingCalled, 0)
        XCTAssertEqual(self.callKitProvider.timesReportCallEndedAtCalled, 0)
    }
    
    func testThatItIgnoresNewIncomingCall_v3_Incoming_Silenced() {
        // given
        let conversation = self.conversation()
        conversation.isSilenced = true
        let otherUser = self.otherUser(moc: self.uiMOC)
        
        // when
        sut.callCenterDidChange(callState: .incoming(video: false, shouldRing: true, degraded: false), conversation: conversation, user: otherUser, timeStamp: nil)
        
        // then
        XCTAssertEqual(self.callKitProvider.timesReportNewIncomingCallCalled, 0)
        XCTAssertEqual(self.callKitProvider.timesReportOutgoingCallConnectedAtCalled, 0)
        XCTAssertEqual(self.callKitProvider.timesReportOutgoingCallStartedConnectingCalled, 0)
        XCTAssertEqual(self.callKitProvider.timesReportCallEndedAtCalled, 0)
    }
    
    func testThatItReportCallEndedAt_v3_Terminating_normal() {
        // given
        let conversation = self.conversation()
        let otherUser = self.otherUser(moc: self.uiMOC)
        
        // when
        sut.callCenterDidChange(callState: .terminating(reason: .normal), conversation: conversation, user: otherUser, timeStamp: nil)
        
        // then
        XCTAssertEqual(self.callKitProvider.timesReportNewIncomingCallCalled, 0)
        XCTAssertEqual(self.callKitProvider.timesReportOutgoingCallConnectedAtCalled, 0)
        XCTAssertEqual(self.callKitProvider.timesReportOutgoingCallStartedConnectingCalled, 0)
        XCTAssertEqual(self.callKitProvider.timesReportCallEndedAtCalled, 1)
        XCTAssertEqual(self.callKitProvider.lastEndedReason, .remoteEnded)
    }
    
    func testThatItReportCallEndedAt_v3_Terminating_lostMedia() {
        // given
        let conversation = self.conversation()
        let otherUser = self.otherUser(moc: self.uiMOC)
        
        // when
        sut.callCenterDidChange(callState: .terminating(reason: .lostMedia), conversation: conversation, user: otherUser, timeStamp: nil)
        
        // then
        XCTAssertEqual(self.callKitProvider.lastEndedReason, .failed)
    }
    
    func testThatItReportCallEndedAt_v3_Terminating_timeout() {
        // given
        let conversation = self.conversation()
        let otherUser = self.otherUser(moc: self.uiMOC)
        
        // when
        sut.callCenterDidChange(callState: .terminating(reason: .timeout), conversation: conversation, user: otherUser, timeStamp: nil)
        
        // then
        XCTAssertEqual(self.callKitProvider.lastEndedReason, .unanswered)
    }
    
    func testThatItReportCallEndedAt_v3_Terminating_answeredElsewhere() {
        // given
        let conversation = self.conversation()
        let otherUser = self.otherUser(moc: self.uiMOC)
        
        // when
        sut.callCenterDidChange(callState: .terminating(reason: .anweredElsewhere), conversation: conversation, user: otherUser, timeStamp: nil)
        
        // then
        XCTAssertEqual(self.callKitProvider.lastEndedReason, .answeredElsewhere)
    }
    
    func testThatItDoesntReportCallEndedAt_v3_Terminating_normalSelf() {
        // given
        let conversation = self.conversation()
        let selfUser = ZMUser.selfUser(in: self.uiMOC)
        
        // when
        sut.callCenterDidChange(callState: .terminating(reason: .normal), conversation: conversation, user: selfUser, timeStamp: nil)
        
        // then
        XCTAssertEqual(self.callKitProvider.timesReportCallEndedAtCalled, 0)
    }
    
}
