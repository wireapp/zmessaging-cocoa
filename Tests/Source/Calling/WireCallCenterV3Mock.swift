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

class MockAVSWrapper : AVSWrapperType {
    
    var mockCallState: CallState = .none
    var didCallStartCall = false
    var didCallAnswerCall = false
    var didCallEndCall = false
    var didCallRejectCall = false
    var didCallClose = false
    var answerCallShouldFail : Bool = false
    var startCallShouldFail : Bool = false
    var mockIsVideoCall : Bool = false
    var hasOngoingCall: Bool = false
    var mockMembers : [CallMember] = []
    
    func members(in conversationId: UUID) -> [CallMember] {
        return mockMembers
    }

    var receivedCallEvents : [CallEvent] = []
    
    required init(userId: UUID, clientId: String, observer: UnsafeMutableRawPointer?) {
        // do nothing
    }
    
    func callState(conversationId: UUID) -> CallState {
        return mockCallState
    }
    

    func startCall(conversationId: UUID, video: Bool, isGroup: Bool) -> Bool {
        didCallStartCall = true
        return !startCallShouldFail
    }
    
    
    func answerCall(conversationId: UUID, isGroup: Bool) -> Bool {
        didCallAnswerCall = true
        return !answerCallShouldFail
    }
    
    func endCall(conversationId: UUID, isGroup: Bool) {
        didCallEndCall = true
    }
    
    func rejectCall(conversationId: UUID, isGroup: Bool) {
        didCallRejectCall = true
    }
    
    func close(){
        didCallClose = true
    }
    
    func toggleVideo(conversationID: UUID, active: Bool) {
        //
    }
    
    func received(callEvent: CallEvent) {
        receivedCallEvents.append(callEvent)
    }
    
    func isVideoCall(conversationId: UUID) -> Bool {
        return mockIsVideoCall
    }
    
    func setVideoSendActive(userId: UUID, active: Bool) {
        // do nothing
    }
    
    func enableAudioCbr(shouldUseCbr: Bool) {
        // do nothing
    }
    
    func handleResponse(httpStatus: Int, reason: String, context: WireCallMessageToken) {
        // do nothing
    }
}

public class WireCallCenterV3Mock : WireCallCenterV3 {
    
    
    var mockMembers : [CallMember] {
        set {
            (avsWrapper as! MockAVSWrapper).mockMembers = newValue
        } get {
            return (avsWrapper as! MockAVSWrapper).mockMembers
        }
    }
    
    public var mockAVSCallState : CallState = .none {
        didSet {
            (avsWrapper as! MockAVSWrapper).mockCallState = mockAVSCallState
        }
    }
    
    public var mockIsVideoCall : Bool = false {
        didSet {
            (avsWrapper as! MockAVSWrapper).mockIsVideoCall = mockIsVideoCall
        }
    }

    public var overridenCallingProtocol : CallingProtocol = .version2
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
        return (avsWrapper as! MockAVSWrapper).didCallStartCall
    }
    
    public var didCallAnswerCall : Bool {
        return (avsWrapper as! MockAVSWrapper).didCallAnswerCall
    }
    public var didCallRejectCall : Bool {
        return (avsWrapper as! MockAVSWrapper).didCallRejectCall
    }
    
    public override var callingProtocol: CallingProtocol {
        return overridenCallingProtocol
    }
    
    public required init(userId: UUID, clientId: String, avsWrapper: AVSWrapperType? = nil, uiMOC: NSManagedObjectContext) {
        super.init(userId: userId, clientId: clientId, avsWrapper: MockAVSWrapper(userId: userId, clientId: clientId, observer: nil), uiMOC: uiMOC)
    }

    public func update(callState : CallState, conversationId: UUID, userId: UUID? = nil) {
        self.mockAVSCallState = callState
        WireCallCenterCallStateNotification(callState: callState, conversationId: conversationId, userId: userId, messageTime: nil).post()
    }

    var mockInitiator : ZMUser?
    
    override public func initiatorForCall(conversationId: UUID) -> UUID? {
        return mockInitiator?.remoteIdentifier ?? super.initiatorForCall(conversationId: conversationId)
    }
}
