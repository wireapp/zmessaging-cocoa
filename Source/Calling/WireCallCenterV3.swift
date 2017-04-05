/*
 * Wire
 * Copyright (C) 2016 Wire Swiss GmbH
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program. If not, see <http://www.gnu.org/licenses/>.
 */

import Foundation
import avs


private class Box<T : Any> {
    var value : T
    
    init(value: T) {
        self.value = value
    }
}

public enum CallClosedReason : Int32 {
    /// Ongoing call was closed by remote or self user
    case normal
    /// Call was closed because of internal error in AVS
    case internalError
    /// Call was closed due to a input/output error (couldn't access microphone)
    case inputOutputError
    /// Outgoing call timed out
    case timeout
    /// Ongoing call lost media and was closed
    case lostMedia
    /// Incoming call was canceled by remote
    case canceled
    /// Incoming call was answered on another device
    case anweredElsewhere
    /// Call was closed for an unknown reason. This is most likely a bug.
    case unknown
    
    init(reason: Int32) {
        switch reason {
        case WCALL_REASON_NORMAL:
            self = .normal
        case WCALL_REASON_CANCELED:
            self = .canceled
        case WCALL_REASON_ANSWERED_ELSEWHERE:
            self = .anweredElsewhere
        case WCALL_REASON_TIMEOUT:
            self = .timeout
        case WCALL_REASON_LOST_MEDIA:
            self = .lostMedia
        case WCALL_REASON_ERROR:
            self = .internalError
        case WCALL_REASON_IO_ERROR:
            self = .inputOutputError
        default:
            self = .unknown
        }
    }
}

private let zmLog = ZMSLog(tag: "calling")

public enum CallState : Equatable {
    
    /// There's no call
    case none
    /// Outgoing call is pending
    case outgoing
    /// Incoming call is pending
    case incoming(video: Bool)
    /// Call is answered
    case answered
    /// Call is established (media is flowing)
    case established
    /// Call in process of being terminated
    case terminating(reason: CallClosedReason)
    /// Unknown call state
    case unknown
    
    public static func ==(lhs: CallState, rhs: CallState) -> Bool {
        switch (lhs, rhs) {
        case (.none, .none):
            fallthrough
        case (.outgoing, .outgoing):
            fallthrough
        case (.incoming, .incoming):
            fallthrough
        case (.answered, .answered):
            fallthrough
        case (.established, .established):
            fallthrough
        case (.terminating, .terminating):
            fallthrough
        case (.unknown, .unknown):
            return true
        default:
            return false
        }
    }
    
    init(wcallState: Int32) {
        switch wcallState {
        case WCALL_STATE_NONE:
            self = .none
        case WCALL_STATE_INCOMING:
            self = .incoming(video: false)
        case WCALL_STATE_OUTGOING:
            self = .outgoing
        case WCALL_STATE_ANSWERED:
            self = .answered
        case WCALL_STATE_MEDIA_ESTAB:
            self = .established
        case WCALL_STATE_TERM_LOCAL: fallthrough
        case WCALL_STATE_TERM_REMOTE:
            self = .terminating(reason: .unknown)
        default:
            self = .none // FIXME check with AVS when WCALL_STATE_UNKNOWN can happen
        }
    }
    
    func postNotificationOnMain(conversationID: UUID, userID: UUID?, uiMOC: NSManagedObjectContext, completion: ((Void) -> Void)? = nil){
        uiMOC.performGroupedBlock {
            WireCallCenterCallStateNotification(callState: self,
                                                conversationId: conversationID,
                                                userId: userID).post()
            completion?()
        }
    }
    
    func logState(){
        switch self {
        case .answered:
            zmLog.debug("answered call")
        case .established:
            zmLog.debug("established call")
        case .outgoing:
            zmLog.debug("outgoing call")
        case .incoming(video: let isVideo):
            zmLog.debug("incoming call with isVideo \(isVideo)")
        case .terminating(reason: let reason):
            zmLog.debug("terminating call reason: \(reason)")
        case .none:
            zmLog.debug("no call")
        case .unknown:
            zmLog.debug("unknown call state")
        }
    }
}


private extension String {
    
    init?(cString: UnsafePointer<Int8>?) {
        if let cString = cString {
            self.init(cString: cString)
        } else {
            return nil
        }
    }
    
}

public extension UUID {
    
    init?(cString: UnsafePointer<Int8>?) {
        guard let aString = String(cString: cString) else { return nil }
        self.init(uuidString: aString)
    }
}


/// MARK - C convention functions

/// Handles incoming calls
/// In order to be passed to C, this function needs to be global
internal func IncomingCallHandler(conversationId: UnsafePointer<Int8>?, userId: UnsafePointer<Int8>?, isVideoCall: Int32, contextRef: UnsafeMutableRawPointer?)
{
    guard let contextRef = contextRef, let convID = UUID(cString: conversationId), let userID = UUID(cString: userId) else { return }
    let callCenter = Unmanaged<WireCallCenterV3>.fromOpaque(contextRef).takeUnretainedValue()
    callCenter.handleCallState(callState: .incoming(video: isVideoCall != 0), conversationId: convID, userId: userID)
}

/// Handles missed calls
/// In order to be passed to C, this function needs to be global
internal func MissedCallHandler(conversationId: UnsafePointer<Int8>?, messageTime: UInt32, userId: UnsafePointer<Int8>?, isVideoCall: Int32, contextRef: UnsafeMutableRawPointer?)
{
    guard let contextRef = contextRef, let convID = UUID(cString: conversationId), let userID = UUID(cString: userId) else { return }
    let callCenter = Unmanaged<WireCallCenterV3>.fromOpaque(contextRef).takeUnretainedValue()
    callCenter.missed(conversationId: convID,
                      userId: userID,
                      timestamp: Date(timeIntervalSince1970: TimeInterval(messageTime)),
                      isVideoCall: (isVideoCall != 0))
}

/// Handles answered calls
/// In order to be passed to C, this function needs to be global
internal func AnsweredCallHandler(conversationId: UnsafePointer<Int8>?, contextRef: UnsafeMutableRawPointer?){
    guard let contextRef = contextRef, let convID = UUID(cString: conversationId) else { return }
    let callCenter = Unmanaged<WireCallCenterV3>.fromOpaque(contextRef).takeUnretainedValue()
    callCenter.handleCallState(callState: .answered, conversationId: convID, userId: nil)
}

/// Handles established calls
/// In order to be passed to C, this function needs to be global
internal func EstablishedCallHandler(conversationId: UnsafePointer<Int8>?, userId: UnsafePointer<Int8>?,contextRef: UnsafeMutableRawPointer?)
{
    guard let contextRef = contextRef, let convID = UUID(cString: conversationId), let userID = UUID(cString: userId) else { return }
    if wcall_is_video_call(convID.transportString()) == 1 {
        wcall_set_video_send_active(userID.transportString(), 1)
    }
    let callCenter = Unmanaged<WireCallCenterV3>.fromOpaque(contextRef).takeUnretainedValue()
    callCenter.handleCallState(callState: .established, conversationId: convID, userId: userID)
}

/// Handles ended calls
/// In order to be passed to C, this function needs to be global
internal func ClosedCallHandler(reason:Int32, conversationId: UnsafePointer<Int8>?, userId: UnsafePointer<Int8>?, metrics:UnsafePointer<Int8>?, contextRef: UnsafeMutableRawPointer?)
{
    guard let contextRef = contextRef, let convID = UUID(cString: conversationId) else { return }
    let userID = UUID(cString: userId)
    
    let callCenter = Unmanaged<WireCallCenterV3>.fromOpaque(contextRef).takeUnretainedValue()
    callCenter.handleCallState(callState: .terminating(reason: CallClosedReason(reason: reason)), conversationId: convID, userId: userID)
}

/// Handles sending call messages
/// In order to be passed to C, this function needs to be global
internal func SendCallHandler(token: UnsafeMutableRawPointer?, conversationId: UnsafePointer<Int8>?, userId: UnsafePointer<Int8>?, clientId: UnsafePointer<Int8>?, data: UnsafePointer<UInt8>?, dataLength: Int, contextRef: UnsafeMutableRawPointer?) -> Int32
{
    guard let token = token, let contextRef = contextRef, let conversationId = UUID(cString: conversationId), let userId = UUID(cString: userId), let clientId = String(cString: clientId), let data = data else {
        return EINVAL // invalid argument
    }
    
    let callCenter = Unmanaged<WireCallCenterV3>.fromOpaque(contextRef).takeUnretainedValue()
    return callCenter.send(token: token,
                           conversationId: conversationId,
                           userId: userId,
                           clientId: clientId,
                           data: data,
                           dataLength: dataLength)
}

/// Sets the calling protocol when AVS is ready
/// In order to be passed to C, this function needs to be global
internal func ReadyHandler(version: Int32, contextRef: UnsafeMutableRawPointer?)
{
    guard let contextRef = contextRef else { return }
    
    if let callingProtocol = CallingProtocol(rawValue: Int(version)) {
        let callCenter = Unmanaged<WireCallCenterV3>.fromOpaque(contextRef).takeUnretainedValue()
        callCenter.callingProtocol = callingProtocol
    } else {
        zmLog.error("wcall initialized with unknown protocol version: \(version)")
    }
}


/// MARK - Call center transport

@objc
public protocol WireCallCenterTransport: class {
    func send(data: Data, conversationId: UUID, userId: UUID, completionHandler: @escaping ((_ status: Int) -> Void))
}

private typealias WireCallMessageToken = UnsafeMutableRawPointer



/// MARK - WireCallCenterV3

/**
 * WireCallCenter is used for making wire calls and observing their state. There can only be one instance of the WireCallCenter. You should instantiate WireCallCenter once a keep a strong reference to it, other consumers can access this instance via the `activeInstance` property.
 * Thread safety: WireCallCenter instance methods should only be called from the main thread, class method can be called from any thread.
 */
@objc public class WireCallCenterV3 : NSObject {
    
    /// The selfUser remoteIdentifier
    fileprivate let selfUserId : UUID

    @objc public static let cbrNotificationName = WireCallCenterCBRCallNotification.notificationName

    
    /// activeInstance - Currenly active instance of the WireCallCenter.
    public private(set) static weak var activeInstance : WireCallCenterV3?
    
    /// establishedDate - Date of when the call was established (Participants can talk to each other). This property is only valid when the call state is .established.
    public private(set) var establishedDate : Date?
    
    public weak var transport : WireCallCenterTransport? = nil
    
    public fileprivate(set) var callingProtocol : CallingProtocol = .version2
    
    var avsWrapper : AVSWrapperType!
    weak var uiMOC : NSManagedObjectContext!
    
    public var useAudioConstantBitRate: Bool = false {
        didSet {
            wcall_enable_audio_cbr(useAudioConstantBitRate ? 1 : 0)
        }
    }
    
    deinit {
        avsWrapper.close()
    }
    
    public required init(userId: UUID, clientId: String, avsWrapper: AVSWrapperType? = nil, uiMOC: NSManagedObjectContext) {
        self.selfUserId = userId
        self.uiMOC = uiMOC
        super.init()
        
        if WireCallCenterV3.activeInstance != nil {
            fatal("Only one WireCallCenter can be instantiated")
        }
        
        let observer = Unmanaged.passUnretained(self).toOpaque()
        self.avsWrapper = avsWrapper ?? AVSWrapper(userId: userId, clientId: clientId, observer: observer)
    
        WireCallCenterV3.activeInstance = self
    }
    
    fileprivate func send(token: WireCallMessageToken, conversationId: UUID, userId: UUID, clientId: String, data: UnsafePointer<UInt8>, dataLength: Int) -> Int32 {
        
        let bytes = UnsafeBufferPointer<UInt8>(start: data, count: dataLength)
        let transformedData = Data(buffer: bytes)
        
        transport?.send(data: transformedData, conversationId: conversationId, userId: userId, completionHandler: { status in
            wcall_resp(Int32(status), "", token)
        })
        
        let currentState = callState(conversationId: conversationId)
        if let uiMOC = uiMOC {
            currentState.postNotificationOnMain(conversationID: conversationId, userID: userId, uiMOC: uiMOC)
        }

        return 0
    }
    
    fileprivate func handleCallState(callState: CallState, conversationId: UUID, userId: UUID?) {
        callState.logState()
        guard let uiMOC = uiMOC else { return }

        switch callState {
        case .established:
            callState.postNotificationOnMain(conversationID: conversationId, userID: userId, uiMOC: uiMOC){
                self.establishedDate = Date()
            }
        default:
            callState.postNotificationOnMain(conversationID: conversationId, userID: userId, uiMOC: uiMOC)
        }
    }

    
    fileprivate func missed(conversationId: UUID, userId: UUID, timestamp: Date, isVideoCall: Bool) {
        zmLog.debug("missed call")
        
        uiMOC?.performGroupedBlock {
            WireCallCenterMissedCallNotification(conversationId: conversationId, userId:userId, timestamp: timestamp, video: isVideoCall).post()
        }
    }
    
    public func received(data: Data, currentTimestamp: Date, serverTimestamp: Date, conversationId: UUID, userId: UUID, clientId: String) {
        avsWrapper.received(data: data, currentTimestamp: currentTimestamp, serverTimestamp: serverTimestamp, conversationId: conversationId, userId: userId, clientId: clientId)
    }


    
    // MARK - Call state methods

    @objc(answerCallForConversationID:)
    public func answerCall(conversationId: UUID) -> Bool {
        let answered = avsWrapper.answerCall(conversationId: conversationId)
        if answered {
            WireCallCenterCallStateNotification(callState: .answered, conversationId: conversationId, userId: self.selfUserId).post()
        }
        return answered
    }
    
    @objc(startCallForConversationID:video:)
    public func startCall(conversationId: UUID, video: Bool) -> Bool {
        let started = avsWrapper.startCall(conversationId: conversationId, video: video)
        if started {
            WireCallCenterCallStateNotification(callState: .outgoing, conversationId: conversationId, userId: selfUserId).post()
        }
        return started
    }
    
    @objc(closeCallForConversationID:)
    public func closeCall(conversationId: UUID) {
        avsWrapper.endCall(conversationId: conversationId)
    }
    
    @objc(rejectCallForConversationID:)
    public func rejectCall(conversationId: UUID) {
        avsWrapper.rejectCall(conversationId: conversationId)

        WireCallCenterCallStateNotification(callState: .terminating(reason: .canceled),
                                                conversationId: conversationId,
                                                userId: selfUserId).post()
    }
    
    @objc(toogleVideoForConversationID:isActive:)
    public func toogleVideo(conversationID: UUID, active: Bool) {
        avsWrapper.toggleVideo(conversationID: conversationID, active: active)
    }
    
    @objc(isVideoCallForConversationID:)
    public class func isVideoCall(conversationId: UUID) -> Bool {
        return wcall_is_video_call(conversationId.transportString()) == 1 ? true : false
    }
    
    /// nonIdleCalls maps all non idle conversations to their corresponding call state
    public class var nonIdleCalls : [UUID : CallState] {
        
        typealias CallStateDictionary = [UUID : CallState]
        
        let box = Box<CallStateDictionary>(value: [:])
        let pointer = Unmanaged<Box<CallStateDictionary>>.passUnretained(box).toOpaque()
        
        wcall_iterate_state({ (conversationId, state, pointer) in
            guard let conversationId = conversationId, let pointer = pointer else { return }
            guard let uuid = UUID(uuidString: String(cString: conversationId)) else { return }
            
            let box = Unmanaged<Box<CallStateDictionary>>.fromOpaque(pointer).takeUnretainedValue()
            box.value[uuid] = CallState(wcallState: state)
        }, pointer)
        
        return box.value
    }
    
    /// Gets the current callState from AVS
    /// If the group call was ignored or left, it return .incoming where shouldRing is set to false
    public func callState(conversationId: UUID) -> CallState {
        return avsWrapper.getCallState(conversationId: conversationId)
    }

}
