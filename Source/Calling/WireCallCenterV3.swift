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

private extension String {
    
    init?(cString: UnsafePointer<Int8>?) {
        if let cString = cString {
            self.init(cString: cString)
        } else {
            return nil
        }
    }
    
}

private extension UUID {
    
    init?(uuidString: String?) {
        if let uuidString = uuidString {
            self.init(uuidString: uuidString)
        } else {
            return nil
        }
    }
}

private class Box<T : Any> {
    var value : T
    
    init(value: T) {
        self.value = value
    }
}

public enum CallClosedReason : Int32 {
    /// Ongoing call was closed by remote
    case normal
    /// Ongoing call was closed by self
    case normalSelf
    /// Call was closed because of internal error in AVS
    case internalError
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
        default:
            self = .unknown
        }
    }
}

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
        case WCALL_STATE_TERMINATING:
            self = .terminating(reason: .unknown)
        default:
            self = .none // FIXME check with AVS when WCALL_STATE_UNKNOWN can happen
        }
    }
}

public typealias WireCallCenterObserverToken = NSObjectProtocol

struct WireCallCenterV3VideoNotification {
    
    static let notificationName = Notification.Name("WireCallCenterVideoNotification")
    static let userInfoKey = notificationName.rawValue
    
    let receivedVideoState : ReceivedVideoState
    
    init(receivedVideoState: ReceivedVideoState) {
        self.receivedVideoState = receivedVideoState
    }
    
    func post() {
        NotificationCenter.default.post(name: WireCallCenterV3VideoNotification.notificationName,
                                        object: nil,
                                        userInfo: [WireCallCenterV3VideoNotification.userInfoKey : self])
    }
}

/// MARK - Call state observer

public protocol WireCallCenterCallStateObserver : class {
    
    func callCenterDidChange(callState: CallState, conversationId: UUID, userId: UUID?)
    
}

struct WireCallCenterCallStateNotification {
    
    static let notificationName = Notification.Name("WireCallCenterNotification")
    static let userInfoKey = notificationName.rawValue
    
    let callState : CallState
    let conversationId : UUID
    let userId : UUID?
    
    func post() {
        NotificationCenter.default.post(name: WireCallCenterCallStateNotification.notificationName,
                                        object: nil,
                                        userInfo: [WireCallCenterCallStateNotification.userInfoKey : self])
    }
}

/// MARK - Missed call observer

public protocol WireCallCenterMissedCallObserver : class {
    
    func callCenterMissedCall(conversationId: UUID, userId: UUID, timestamp: Date, video: Bool)
    
}

struct WireCallCenterMissedCallNotification {
    
    static let notificationName = Notification.Name("WireCallCenterNotification")
    static let userInfoKey = notificationName.rawValue
    
    let conversationId : UUID
    let userId : UUID
    let timestamp: Date
    let video: Bool
    
    func post() {
        NotificationCenter.default.post(name: WireCallCenterMissedCallNotification.notificationName,
                                        object: nil,
                                        userInfo: [WireCallCenterMissedCallNotification.userInfoKey : self])
    }
}

/// MARK - Call center transport

@objc
public protocol WireCallCenterTransport: class {
    
    func send(data: Data, conversationId: UUID, userId: UUID, completionHandler: @escaping ((_ status: Int) -> Void))
    
}

private typealias WireCallMessageToken = UnsafeMutableRawPointer

/** 
 * WireCallCenter is used for making wire calls and observing their state. There can only be one instance of the WireCallCenter. You should instantiate WireCallCenter once a keep a strong reference to it, other consumers can access this instance via the `activeInstance` property.
 * Thread safety: WireCallCenter instance methods should only be called from the main thread, class method can be called from any thread.
 */
@objc public class WireCallCenterV3 : NSObject {
    
    private let zmLog = ZMSLog(tag: "calling")
    
    private let userId : UUID
    
    /// activeInstance - Currenly active instance of the WireCallCenter.
    public private(set) static weak var activeInstance : WireCallCenterV3?
    
    /// establishedDate - Date of when the call was established (Participants can talk to each other). This property is only valid when the call state is .established.
    public private(set) var establishedDate : Date?
    
    public weak var transport : WireCallCenterTransport? = nil
    
    public private(set) var callingProtocol : CallingProtocol = .version2
    
    deinit {
        wcall_close()
    }
    
    public required init(userId: UUID, clientId: String, registerObservers : Bool = true) {
        self.userId = userId
        
        super.init()
        
        if WireCallCenterV3.activeInstance != nil {
            fatal("Only one WireCallCenter can be instantiated")
        }
        
        if (registerObservers) {
            
            let observer = Unmanaged.passUnretained(self).toOpaque()
            
            let resultValue = wcall_init(
                userId.transportString(),
                clientId,
                { (version, context) in
                    if let context = context {
                        let selfReference = Unmanaged<WireCallCenterV3>.fromOpaque(context).takeUnretainedValue()
                        
                        if let callingProtocol = CallingProtocol(rawValue: Int(version)) {
                            selfReference.callingProtocol = callingProtocol
                        } else {
                            selfReference.zmLog.error("wcall initialized with unknown protocol version: \(version)")
                        }
                    }
                },
                { (token, conversationId, userId, clientId, data, dataLength, context) in
                    guard let token = token, let context = context, let conversationId = conversationId, let userId = userId, let clientId = clientId, let data = data else {
                        return EINVAL // invalid argument
                    }
                    
                    let selfReference = Unmanaged<WireCallCenterV3>.fromOpaque(context).takeUnretainedValue()
                    
                    return selfReference.send(token: token,
                                              conversationId: String.init(cString: conversationId),
                                              userId: String(cString: userId),
                                              clientId: String(cString: clientId),
                                              data: data,
                                              dataLength: dataLength)
                },
                { (conversationId, userId, isVideoCall, context) -> Void in
                    guard let context = context, let conversationId = conversationId, let userId = userId else {
                        return
                    }
                    
                    let selfReference = Unmanaged<WireCallCenterV3>.fromOpaque(context).takeUnretainedValue()
                    
                    selfReference.incoming(conversationId: String(cString: conversationId),
                                           userId: String(cString: userId),
                                           isVideoCall: isVideoCall != 0)
                },
                { (conversationId, messageTime, userId, isVideoCall, context) in
                    guard let context = context, let conversationId = conversationId, let userId = userId else {
                        return
                    }
                    
                    let selfReference = Unmanaged<WireCallCenterV3>.fromOpaque(context).takeUnretainedValue()
                    let timestamp = Date(timeIntervalSince1970: TimeInterval(messageTime))
                    
                    selfReference.missed(conversationId: String(cString: conversationId),
                                         userId: String(cString: userId),
                                         timestamp: timestamp,
                                         isVideoCall: isVideoCall != 0)
                },
                { (conversationId, userId, context) in
                    guard let context = context, let conversationId = conversationId, let userId = userId else {
                        return
                    }
                    
                    let selfReference = Unmanaged<WireCallCenterV3>.fromOpaque(context).takeUnretainedValue()
                    
                    selfReference.established(conversationId: String(cString: conversationId),
                                              userId: String(cString: userId))
                },
                { (reason, conversationId, userId, metrics, context) in
                    guard let context = context, let conversationId = conversationId else {
                        return
                    }
                    
                    let selfReference = Unmanaged<WireCallCenterV3>.fromOpaque(context).takeUnretainedValue()
                    
                    selfReference.closed(conversationId: String(cString: conversationId),
                                         userId: String(cString: userId),
                                         reason: CallClosedReason(reason: reason))
                },
                observer)
            
            if resultValue != 0 {
                fatal("Failed to initialise WireCallCenter")
            }
            
            wcall_set_video_state_handler({ (state, _) in
                guard let state = ReceivedVideoState(rawValue: UInt(state)) else { return }
                
                DispatchQueue.main.async {
                    WireCallCenterV3VideoNotification(receivedVideoState: state).post()
                }
            })
        }
        
        WireCallCenterV3.activeInstance = self
    }
    
    private func send(token: WireCallMessageToken, conversationId: String, userId: String, clientId: String, data: UnsafePointer<UInt8>, dataLength: Int) -> Int32 {
        
        let bytes = UnsafeBufferPointer<UInt8>(start: data, count: dataLength)
        let transformedData = Data(buffer: bytes)
        
        transport?.send(data: transformedData, conversationId: UUID(uuidString: conversationId)!, userId: UUID(uuidString: userId)!, completionHandler: { status in
            wcall_resp(Int32(status), "", token)
        })
        
        return 0
    }
    
    private func incoming(conversationId: String, userId: String, isVideoCall: Bool) {
        zmLog.debug("incoming call")
        
        DispatchQueue.main.async {
            WireCallCenterCallStateNotification(callState: .incoming(video: isVideoCall), conversationId: UUID(uuidString: conversationId)!, userId: UUID(uuidString: userId)!).post()
        }
    }
    
    private func missed(conversationId: String, userId: String, timestamp: Date, isVideoCall: Bool) {
        zmLog.debug("missed call")
        
        DispatchQueue.main.async {
            WireCallCenterMissedCallNotification(conversationId: UUID(uuidString: conversationId)!, userId: UUID(uuidString: userId)!, timestamp: timestamp, video: isVideoCall).post()
        }
    }
    
    private func established(conversationId: String, userId: String) {
        zmLog.debug("established call")
        
        if wcall_is_video_call(conversationId) == 1 {
            wcall_set_video_send_active(conversationId, 1)
        }
        
        DispatchQueue.main.async {
            self.establishedDate = Date()
            
            WireCallCenterCallStateNotification(callState: .established, conversationId: UUID(uuidString: conversationId)!, userId: UUID(uuidString: userId)!).post()
        }
    }
    
    private func closed(conversationId: String, userId: String?, reason: CallClosedReason) {
        zmLog.debug("closed call, reason = \(reason)")
        
        DispatchQueue.main.async {
            WireCallCenterCallStateNotification(callState: .terminating(reason: reason), conversationId: UUID(uuidString: conversationId)!, userId: UUID(uuidString: userId)).post()
        }
    }
    
    public func received(data: Data, currentTimestamp: Date, serverTimestamp: Date, conversationId: UUID, userId: UUID, clientId: String) {
        data.withUnsafeBytes { (bytes: UnsafePointer<UInt8>) in
            let currentTime = UInt32(currentTimestamp.timeIntervalSince1970)
            let serverTime = UInt32(serverTimestamp.timeIntervalSince1970)
            
            wcall_recv_msg(bytes, data.count, currentTime, serverTime, conversationId.transportString(), userId.transportString(), clientId)
        }
    }
    
    // MARK - Observer
    
    /// Register observer of the call center call state. This will inform you when there's an incoming call etc.
    /// Returns a token which needs to unregistered with `removeObserver(token:)` to stop observing.
    public class func addCallStateObserver(observer: WireCallCenterCallStateObserver) -> WireCallCenterObserverToken  {
        return NotificationCenter.default.addObserver(forName: WireCallCenterCallStateNotification.notificationName, object: nil, queue: .main) { [weak observer] (note) in
            if let note = note.userInfo?[WireCallCenterCallStateNotification.userInfoKey] as? WireCallCenterCallStateNotification {
                observer?.callCenterDidChange(callState: note.callState, conversationId: note.conversationId, userId: note.userId)
            }
        }
    }
    
    /// Register observer of missed calls.
    /// Returns a token which needs to unregistered with `removeObserver(token:)` to stop observing.
    public class func addMissedCallObserver(observer: WireCallCenterMissedCallObserver) -> WireCallCenterObserverToken  {
        return NotificationCenter.default.addObserver(forName: WireCallCenterMissedCallNotification.notificationName, object: nil, queue: .main) { [weak observer] (note) in
            if let note = note.userInfo?[WireCallCenterMissedCallNotification.userInfoKey] as? WireCallCenterMissedCallNotification {
                observer?.callCenterMissedCall(conversationId: note.conversationId, userId: note.userId, timestamp: note.timestamp, video: note.video)
            }
        }
    }
    
    /// Register observer of the video state. This will inform you when the remote caller starts, stops sending video.
    /// Returns a token which needs to unregistered with `removeObserver(token:)` to stop observing.
    public class func addReceivedVideoObserver(observer: ReceivedVideoObserver) -> WireCallCenterObserverToken {
        return NotificationCenter.default.addObserver(forName: WireCallCenterV3VideoNotification.notificationName, object: nil, queue: .main) { [weak observer] (note) in
            if let note = note.userInfo?[WireCallCenterV3VideoNotification.userInfoKey] as? WireCallCenterV3VideoNotification {
                observer?.callCenterDidChange(receivedVideoState: note.receivedVideoState)
            }
        }
    }
    
    public class func removeObserver(token: WireCallCenterObserverToken) {
        NotificationCenter.default.removeObserver(token)
    }
    
    // MARK - Call state methods
    
    @objc(answerCallForConversationID:)
    public func answerCall(conversationId: UUID) -> Bool {
        let answered =  wcall_answer(conversationId.transportString()) == 0
        
        if answered {
            WireCallCenterCallStateNotification(callState: .answered, conversationId: conversationId, userId: self.userId).post()
        }
        
        return answered
    }
    
    @objc(startCallForConversationID:video:)
    public func startCall(conversationId: UUID, video: Bool) -> Bool {
        let started = wcall_start(conversationId.transportString(), video ? 1 : 0) == 0
        
        if started {
            WireCallCenterCallStateNotification(callState: .outgoing, conversationId: conversationId, userId: userId).post()
        }
        
        return started
    }
    
    @objc(closeCallForConversationID:)
    public func closeCall(conversationId: UUID) {
        let started = callState(conversationId: conversationId) == .established
        wcall_end(conversationId.transportString())
        WireCallCenterCallStateNotification(callState: .terminating(reason: started ? .normalSelf : .canceled), conversationId: conversationId, userId: userId).post()
    }
    
    @objc(toogleVideoForConversationID:isActive:)
    public func toogleVideo(conversationID: UUID, active: Bool) {
        wcall_set_video_send_active(conversationID.transportString(), active ? 1 : 0)
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
 
    public func callState(conversationId: UUID) -> CallState {
        return CallState(wcallState: wcall_get_state(conversationId.transportString()))
    }
}
