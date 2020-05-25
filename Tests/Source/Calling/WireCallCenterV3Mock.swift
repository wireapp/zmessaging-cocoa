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

@objcMembers
public class MockAVSWrapper : AVSWrapperType {
    public var muted: Bool = false
    
    public var startCallArguments: (uuid: UUID, callType: AVSCallType, conversationType: AVSConversationType, useCBR: Bool)?
    public var answerCallArguments: (uuid: UUID, callType: AVSCallType, useCBR: Bool)?
    public var setVideoStateArguments: (uuid: UUID, videoState: VideoState)?
    public var didCallEndCall = false
    public var didCallRejectCall = false
    public var didCallClose = false
    public var answerCallShouldFail = false
    public var startCallShouldFail = false
    public var didUpdateCallConfig = false
    public var callError: CallError?
    public var hasOngoingCall = false
    public var mockMembers : [AVSCallMember] = []
    
    var receivedCallEvents : [CallEvent] = []
    
    public required init(userId: UUID, clientId: String, observer: UnsafeMutableRawPointer?) {
        // do nothing
    }
    
    public func startCall(conversationId: UUID, callType: AVSCallType, conversationType: AVSConversationType, useCBR: Bool) -> Bool {
        startCallArguments = (conversationId, callType, conversationType, useCBR)
        return !startCallShouldFail
    }
    
    public func answerCall(conversationId: UUID, callType: AVSCallType, useCBR: Bool) -> Bool {
        answerCallArguments = (conversationId, callType, useCBR)
        return !answerCallShouldFail
    }
    
    public func endCall(conversationId: UUID) {
        didCallEndCall = true
    }
    
    public func rejectCall(conversationId: UUID) {
        didCallRejectCall = true
    }
    
    public func close(){
        didCallClose = true
    }
    

    public func setVideoState(conversationId: UUID, videoState: VideoState) {
        setVideoStateArguments = (conversationId, videoState)
    }
    
    public func received(callEvent: CallEvent) -> CallError? {
        receivedCallEvents.append(callEvent)
        return callError
    }
    
    public func handleResponse(httpStatus: Int, reason: String, context: WireCallMessageToken) {
        // do nothing
    }

    public func handleSFTResponse(data: Data?, context: WireCallMessageToken) {
        // do nothing
    }
    
    public func update(callConfig: String?, httpStatusCode: Int) {
        didUpdateCallConfig = true
    }
}

public class WireCallCenterV3IntegrationMock : WireCallCenterV3 {
    
    public let mockAVSWrapper : MockAVSWrapper
    
    public required init(userId: UUID, clientId: String, avsWrapper: AVSWrapperType? = nil, uiMOC: NSManagedObjectContext, flowManager: FlowManagerType, analytics: AnalyticsType? = nil, transport: WireCallCenterTransport, configuration: WireCallCenterConfiguration = .init()) {
        mockAVSWrapper = MockAVSWrapper(userId: userId, clientId: clientId, observer: nil)
        super.init(userId: userId, clientId: clientId, avsWrapper: mockAVSWrapper, uiMOC: uiMOC, flowManager: flowManager, transport: transport, configuration: configuration)
    }
    
}

@objcMembers
public class WireCallCenterV3Mock: WireCallCenterV3 {
    
    public let mockAVSWrapper: MockAVSWrapper

    var mockMembers : [AVSCallMember] {
        get {
            return mockAVSWrapper.mockMembers
        }
        set {
            mockAVSWrapper.mockMembers = newValue
        }
    }

    // MARK: Initialization

    public required init(userId: UUID, clientId: String, avsWrapper: AVSWrapperType? = nil, uiMOC: NSManagedObjectContext, flowManager: FlowManagerType, analytics: AnalyticsType? = nil, transport: WireCallCenterTransport, configuration: WireCallCenterConfiguration = .init()) {
        mockAVSWrapper = MockAVSWrapper(userId: userId, clientId: clientId, observer: nil)
        super.init(userId: userId, clientId: clientId, avsWrapper: mockAVSWrapper, uiMOC: uiMOC, flowManager: flowManager, transport: transport, configuration: configuration)
    }

    // MARK: AVS Integration

    public var startCallShouldFail : Bool = false {
        didSet{
            (avsWrapper as! MockAVSWrapper).startCallShouldFail = startCallShouldFail
        }
    }
    public var answerCallShouldFail : Bool = false {
        didSet{
            (avsWrapper as! MockAVSWrapper).answerCallShouldFail = answerCallShouldFail
        }
    }

    public var didCallStartCall : Bool {
        return (avsWrapper as! MockAVSWrapper).startCallArguments != nil
    }
    
    public var didCallAnswerCall : Bool {
        return (avsWrapper as! MockAVSWrapper).answerCallArguments != nil
    }
    
    public var didCallRejectCall : Bool {
        return (avsWrapper as! MockAVSWrapper).didCallRejectCall
    }

    // MARK: Mock Call State

    func setMockCallState(_ state: CallState, conversationId: UUID, callerId: UUID, isVideo: Bool) {
        clearSnapshot(conversationId: conversationId)
        createSnapshot(callState: state, members: [], callStarter: callerId, video: isVideo, for: conversationId)
    }

    func removeMockActiveCalls() {
        activeCalls.keys.forEach(clearSnapshot)
    }

    func update(callState : CallState, conversationId: UUID, callerId: UUID, isVideo: Bool) {
        setMockCallState(callState, conversationId: conversationId, callerId: callerId, isVideo: isVideo)
        WireCallCenterCallStateNotification(context: uiMOC!, callState: callState, conversationId: conversationId, callerId: callerId, messageTime: nil, previousCallState: nil).post(in: uiMOC!.notificationContext)
    }

}

