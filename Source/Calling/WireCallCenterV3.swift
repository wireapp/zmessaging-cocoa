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
    /// Incoming call was canceled by remote
    case canceled
    /// Incoming call was answered on another device
    case anweredElsewhere
    /// Outgoing call timed out
    case timeout
    /// Ongoing call lost media and was closed
    case lostMedia
    /// Call was closed because of internal error in AVS
    case internalError
    /// Call was closed due to a input/output error (couldn't access microphone)
    case inputOutputError
    /// Call left by the selfUser but continues until everyone else leaves or AVS closes it
    case stillOngoing
    /// Call was dropped due to the security level degrading
    case securityDegraded
    /// Call was closed for an unknown reason. This is most likely a bug.
    case unknown
    
    init(wcall_reason: Int32) {
        switch wcall_reason {
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
        case WCALL_REASON_STILL_ONGOING:
            self = .stillOngoing
        default:
            self = .unknown
        }
    }
    
    var wcall_reason : Int32 {
        switch self {
        case .normal:
            return WCALL_REASON_NORMAL
        case .canceled:
            return WCALL_REASON_CANCELED
        case .anweredElsewhere:
            return WCALL_REASON_ANSWERED_ELSEWHERE
        case .timeout:
            return WCALL_REASON_TIMEOUT
        case .lostMedia:
            return WCALL_REASON_LOST_MEDIA
        case .internalError:
            return WCALL_REASON_ERROR
        case .inputOutputError:
            return WCALL_REASON_IO_ERROR
        case .stillOngoing:
            return WCALL_REASON_STILL_ONGOING
        case .securityDegraded:
            return WCALL_REASON_ERROR
        case .unknown:
            return WCALL_REASON_ERROR
        }
    }
}

private let zmLog = ZMSLog(tag: "calling")

public enum CallParticipantState : Equatable {
    
    // Participant is not in the call
    case unconnected
    // Participant is in the process of connecting to the call
    case connecting
    /// Participant is connected to call and audio is flowing
    case connected(videoState: VideoState)
    
    public static func ==(lhs: CallParticipantState, rhs: CallParticipantState) -> Bool {
        switch (lhs, rhs) {
        case (.connecting, .connecting):
            fallthrough
        case (.unconnected, .unconnected):
            return true
        case (.connected(videoState: let lvideoState), .connected(videoState: let rvideoState)):
            return lvideoState == rvideoState
        default:
            return false
        }
    }
}

public enum CallState : Equatable {
    
    /// There's no call
    case none
    /// Outgoing call is pending
    case outgoing(degraded: Bool)
    /// Incoming call is pending
    case incoming(video: Bool, shouldRing: Bool, degraded: Bool)
    /// Call is answered
    case answered(degraded: Bool)
    /// Call is established (data is flowing)
    case establishedDataChannel
    /// Call is established (media is flowing)
    case established
    /// Call in process of being terminated
    case terminating(reason: CallClosedReason)
    /// Unknown call state
    case unknown
    
    public static func ==(lhs: CallState, rhs: CallState) -> Bool {
        switch (lhs, rhs) {
        case (.outgoing(degraded: let lDegraded), .outgoing(degraded: let rDegraded)):
            return lDegraded == rDegraded
        case (.answered(degraded: let lDegraded), .answered(degraded: let rDegraded)):
            return lDegraded == rDegraded
        case (.none, .none):
            fallthrough
        case (.establishedDataChannel, .establishedDataChannel):
            fallthrough
        case (.established, .established):
            fallthrough
        case (.terminating, .terminating):
            fallthrough
        case (.unknown, .unknown):
            return true
        case (.incoming(video: let lVideo, shouldRing: let lShouldRing, degraded: let lDegraded), .incoming(video: let rVideo, shouldRing: let rShouldRing, degraded: let rDegraded)):
            return lVideo == rVideo && lShouldRing == rShouldRing && lDegraded == rDegraded
        default:
            return false
        }
    }
    
    init(wcallState: Int32) {
        switch wcallState {
        case WCALL_STATE_NONE:
            self = .none
        case WCALL_STATE_INCOMING:
            self = .incoming(video: false, shouldRing: true, degraded: false)
        case WCALL_STATE_OUTGOING:
            self = .outgoing(degraded: false)
        case WCALL_STATE_ANSWERED:
            self = .answered(degraded: false)
        case WCALL_STATE_MEDIA_ESTAB:
            self = .established
        case WCALL_STATE_TERM_LOCAL: fallthrough
        case WCALL_STATE_TERM_REMOTE:
            self = .terminating(reason: .unknown)
        default:
            self = .none // FIXME check with AVS when WCALL_STATE_UNKNOWN can happen
        }
    }
    
    func logState(){
        switch self {
        case .answered(degraded: let degraded):
            zmLog.debug("answered call, degraded: \(degraded)")
        case .incoming(video: let isVideo, shouldRing: let shouldRing, degraded: let degraded):
            zmLog.debug("incoming call, isVideo: \(isVideo), shouldRing: \(shouldRing), degraded: \(degraded)")
        case .establishedDataChannel:
            zmLog.debug("established data channel")
        case .established:
            zmLog.debug("established call")
        case .outgoing(degraded: let degraded):
            zmLog.debug("outgoing call, , degraded: \(degraded)")
        case .terminating(reason: let reason):
            zmLog.debug("terminating call reason: \(reason)")
        case .none:
            zmLog.debug("no call")
        case .unknown:
            zmLog.debug("unknown call state")
        }
    }
    
    func update(withSecurityLevel securityLevel: ZMConversationSecurityLevel) -> CallState {
        
        let degraded = securityLevel == .secureWithIgnored
        
        switch self {
        case .incoming(video: let video, shouldRing: let shouldRing, degraded: _):
            return .incoming(video: video, shouldRing: shouldRing, degraded: degraded)
        case .outgoing:
            return .outgoing(degraded: degraded)
        case .answered:
            return .answered(degraded: degraded)
        default:
            return self
        }
    }
}

private struct CallSnapshot {
    let callParticipants: CallParticipantsSnapshot
    let callState: CallState
    let callStarter: UUID
    let isVideo: Bool
    let isGroup: Bool
    let isConstantBitRate: Bool
    let videoState: VideoState
    var conversationObserverToken : NSObjectProtocol?
    
    public func update(with callState: CallState) -> CallSnapshot {
        return CallSnapshot(callParticipants: callParticipants,
                            callState: callState,
                            callStarter: callStarter,
                            isVideo: isVideo,
                            isGroup: isGroup,
                            isConstantBitRate: isConstantBitRate,
                            videoState: videoState,
                            conversationObserverToken: conversationObserverToken)
    }
    
    public func updateConstantBitrate(_ enabled: Bool) -> CallSnapshot {
        return CallSnapshot(callParticipants: callParticipants,
                            callState: callState,
                            callStarter: callStarter,
                            isVideo: isVideo,
                            isGroup: isGroup,
                            isConstantBitRate: enabled,
                            videoState: videoState,
                            conversationObserverToken: conversationObserverToken)
    }
    
    public func updateVideoState(_ videoState: VideoState) -> CallSnapshot {
        return CallSnapshot(callParticipants: callParticipants,
                            callState: callState,
                            callStarter: callStarter,
                            isVideo: isVideo,
                            isGroup: isGroup,
                            isConstantBitRate: isConstantBitRate,
                            videoState: videoState,
                            conversationObserverToken: conversationObserverToken)
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

internal extension AVSCallMember {
    
    var callParticipantState: CallParticipantState {
        if audioEstablished {
            return .connected(videoState: videoState)
        } else {
            return .connecting
        }
    }
    
}


// MARK: - C convention functions

/// Handles incoming calls
/// In order to be passed to C, this function needs to be global

internal func incomingCallHandler(conversationId: UnsafePointer<Int8>?, messageTime: UInt32, userId: UnsafePointer<Int8>?, isVideoCall: Int32, shouldRing: Int32, contextRef: UnsafeMutableRawPointer?)
{
    guard let contextRef = contextRef, let convID = UUID(cString: conversationId), let userID = UUID(cString: userId) else { return }
    let callCenter = Unmanaged<WireCallCenterV3>.fromOpaque(contextRef).takeUnretainedValue()
    
    callCenter.uiMOC?.performGroupedBlock {
        let callState : CallState = .incoming(video: isVideoCall != 0, shouldRing: shouldRing != 0, degraded: callCenter.isDegraded(conversationId: convID))
        callCenter.handleCallState(callState: callState, conversationId: convID, userId: userID, messageTime: Date(timeIntervalSince1970: TimeInterval(messageTime)))
    }
}

/// Handles missed calls
/// In order to be passed to C, this function needs to be global
internal func missedCallHandler(conversationId: UnsafePointer<Int8>?, messageTime: UInt32, userId: UnsafePointer<Int8>?, isVideoCall: Int32, contextRef: UnsafeMutableRawPointer?)
{
    guard let contextRef = contextRef, let convID = UUID(cString: conversationId), let userID = UUID(cString: userId) else { return }
    let callCenter = Unmanaged<WireCallCenterV3>.fromOpaque(contextRef).takeUnretainedValue()
    
    callCenter.uiMOC?.performGroupedBlock {
        callCenter.missed(conversationId: convID,
                          userId: userID,
                          timestamp: Date(timeIntervalSince1970: TimeInterval(messageTime)),
                          isVideoCall: (isVideoCall != 0))
    }
}

/// Handles answered calls
/// In order to be passed to C, this function needs to be global
internal func answeredCallHandler(conversationId: UnsafePointer<Int8>?, contextRef: UnsafeMutableRawPointer?){
    guard let contextRef = contextRef, let convID = UUID(cString: conversationId) else { return }
    let callCenter = Unmanaged<WireCallCenterV3>.fromOpaque(contextRef).takeUnretainedValue()
    
    callCenter.uiMOC?.performGroupedBlock {
        callCenter.handleCallState(callState: .answered(degraded: callCenter.isDegraded(conversationId: convID)), conversationId: convID, userId: nil)
    }
}

/// Handles when data channel gets established
/// In order to be passed to C, this function needs to be global
internal func dataChannelEstablishedHandler(conversationId: UnsafePointer<Int8>?, userId: UnsafePointer<Int8>?,contextRef: UnsafeMutableRawPointer?) {
    guard let contextRef = contextRef, let convID = UUID(cString: conversationId), let userID = UUID(cString: userId) else { return }
    
    let callCenter = Unmanaged<WireCallCenterV3>.fromOpaque(contextRef).takeUnretainedValue()
    
    callCenter.uiMOC?.performGroupedBlock {
        callCenter.handleCallState(callState: .establishedDataChannel, conversationId: convID, userId: userID)
    }
}

/// Handles established calls
/// In order to be passed to C, this function needs to be global
internal func establishedCallHandler(conversationId: UnsafePointer<Int8>?, userId: UnsafePointer<Int8>?,contextRef: UnsafeMutableRawPointer?)
{
    guard let contextRef = contextRef, let convID = UUID(cString: conversationId), let userID = UUID(cString: userId) else { return }
    
    let callCenter = Unmanaged<WireCallCenterV3>.fromOpaque(contextRef).takeUnretainedValue()
    
    callCenter.uiMOC?.performGroupedBlock {
        callCenter.handleCallState(callState: .established, conversationId: convID, userId: userID)
    }
}

/// Handles ended calls
/// If the user answers on the different device, we receive a `WCALL_REASON_ANSWERED_ELSEWHERE` followed by a `WCALL_REASON_NORMAL` once the call ends
/// If the user leaves an ongoing group conversation or an incoming group call times out, we receive a `WCALL_REASON_STILL_ONGOING` followed by a `WCALL_REASON_NORMAL` once the call ends
/// If messageTime is set to 0, the event wasn't caused by a message therefore we don't have a serverTimestamp.
internal func closedCallHandler(reason:Int32, conversationId: UnsafePointer<Int8>?, messageTime: UInt32, userId: UnsafePointer<Int8>?, contextRef: UnsafeMutableRawPointer?)
{
    guard let contextRef = contextRef, let convID = UUID(cString: conversationId) else { return }
    let userID = UUID(cString: userId)
    
    let callCenter = Unmanaged<WireCallCenterV3>.fromOpaque(contextRef).takeUnretainedValue()
    callCenter.uiMOC?.performGroupedBlock {
        let time = (messageTime == 0) ? nil : Date(timeIntervalSince1970: TimeInterval(messageTime))
        callCenter.handleCallState(callState: .terminating(reason: CallClosedReason(wcall_reason: reason)), conversationId: convID, userId: userID, messageTime: time)
    }
}

/// Handles call metrics
internal func callMetricsHandler(conversationId: UnsafePointer<Int8>?, metrics: UnsafePointer<Int8>?, contextRef:UnsafeMutableRawPointer?) {
    do {
        guard let jsonData = String(cString: metrics)?.data(using: .utf8), let contextRef = contextRef else { return }
        guard let attributes = try JSONSerialization.jsonObject(with: jsonData, options: .mutableContainers) as? [String: NSObject] else { return }
        let callCenter = Unmanaged<WireCallCenterV3>.fromOpaque(contextRef).takeUnretainedValue()
        callCenter.analytics?.tagEvent("calling.avs_metrics_ended_call", attributes: attributes)
    } catch {
        zmLog.error("Unable to parse call metrics JSON: \(error)")
    }
}

/// Handle requests for refreshing the calling configuration
internal func requestCallConfigHandler(handle : UnsafeMutableRawPointer?, contextRef: UnsafeMutableRawPointer?) -> Int32 {
    zmLog.debug("AVS: requestCallConfigHandler \(String(describing: handle)) \(String(describing: contextRef))")
    guard let contextRef = contextRef else { return EPROTO }
    
    let callCenter = Unmanaged<WireCallCenterV3>.fromOpaque(contextRef).takeUnretainedValue()
    
    callCenter.uiMOC?.performGroupedBlock {
        callCenter.requestCallConfig()
    }
    
    return 0
}

/// Handles sending call messages
/// In order to be passed to C, this function needs to be global
internal func sendCallMessageHandler(token: UnsafeMutableRawPointer?,
                                     conversationId: UnsafePointer<Int8>?,
                                     senderUserId: UnsafePointer<Int8>?,
                                     senderClientId: UnsafePointer<Int8>?,
                                     destinationUserId: UnsafePointer<Int8>?,
                                     destinationClientId: UnsafePointer<Int8>?,
                                     data: UnsafePointer<UInt8>?,
                                     dataLength: Int,
                                     transient : Int32,
                                     contextRef: UnsafeMutableRawPointer?) -> Int32
{
    guard let token = token, let contextRef = contextRef, let conversationId = UUID(cString: conversationId), let userId = UUID(cString: senderUserId), let clientId = String(cString: senderClientId), let data = data else {
        return EINVAL // invalid argument
    }
    
    let callCenter = Unmanaged<WireCallCenterV3>.fromOpaque(contextRef).takeUnretainedValue()
    let bytes = UnsafeBufferPointer<UInt8>(start: data, count: dataLength)
    let transformedData = Data(buffer: bytes)

    callCenter.uiMOC?.performGroupedBlock {
        callCenter.send(token: token,
                        conversationId: conversationId,
                        userId: userId,
                        clientId: clientId,
                        data: transformedData,
                        dataLength: dataLength)
    }
    
    return 0
}

/// Called when AVS is ready
/// In order to be passed to C, this function needs to be global
internal func readyHandler(version: Int32, contextRef: UnsafeMutableRawPointer?)
{
    guard let contextRef = contextRef else { return }
    
    zmLog.debug("wcall intialized with protocol version: \(Int(version))")
    
    let callCenter = Unmanaged<WireCallCenterV3>.fromOpaque(contextRef).takeUnretainedValue()
    
    callCenter.uiMOC?.performGroupedBlock {
        callCenter.isReady = true
    }
}

/// Handles other users joining / leaving / connecting
/// In order to be passed to C, this function needs to be global
internal func groupMemberHandler(conversationIdRef: UnsafePointer<Int8>?, contextRef: UnsafeMutableRawPointer?)
{
    guard let contextRef = contextRef, let convID = UUID(cString: conversationIdRef) else { return }
    
    let callCenter = Unmanaged<WireCallCenterV3>.fromOpaque(contextRef).takeUnretainedValue()
    let members = callCenter.avsWrapper.members(in: convID)
    callCenter.uiMOC?.performGroupedBlock {
        callCenter.callParticipantsChanged(conversationId: convID, participants: members)
    }
}

/// Handles video state changes
/// In order to be passed to C, this function needs to be global
internal func videoStateChangeHandler(userId: UnsafePointer<Int8>?, state: Int32, contextRef: UnsafeMutableRawPointer?) {
    guard let contextRef = contextRef else { return }
    
    let callCenter = Unmanaged<WireCallCenterV3>.fromOpaque(contextRef).takeUnretainedValue()
    
    if let context = callCenter.uiMOC,
       let userId = UUID(cString: userId),
       let videoState = VideoState(rawValue: state) {
        context.performGroupedBlock {
            callCenter.nonIdleCalls.forEach({ (key, value) in
                callCenter.callParticipantVideostateChanged(conversationId: key, userId: userId, videoState: videoState)
            })
        }
    } else {
        zmLog.error("Couldn't send video state change notification")
    }
}

/// Handles audio CBR mode enabling
/// In order to be passed to C, this function needs to be global
internal func constantBitRateChangeHandler(userId: UnsafePointer<Int8>?, enabled: Int32, contextRef: UnsafeMutableRawPointer?) {
    guard let contextRef = contextRef else { return }
    
    let callCenter = Unmanaged<WireCallCenterV3>.fromOpaque(contextRef).takeUnretainedValue()
    
    if let context = callCenter.uiMOC {
        context.performGroupedBlock {
            let enabled = enabled == 1 ? true : false
            
            if let establishedCall = callCenter.callSnapshots.first(where: { $0.value.callState == .established || $0.value.callState == .establishedDataChannel }) {
                callCenter.callSnapshots[establishedCall.key] = establishedCall.value.updateConstantBitrate(enabled)
                WireCallCenterCBRNotification(enabled: enabled).post(in: context.notificationContext)
            }
        }
    } else {
        zmLog.error("Couldn't send CBR notification")
    }
}

/// MARK - Call center transport
public typealias CallConfigRequestCompletion = (String?, Int) -> Void

@objc
public protocol WireCallCenterTransport: class {
    func send(data: Data, conversationId: UUID, userId: UUID, completionHandler: @escaping ((_ status: Int) -> Void))
    func requestCallConfig(completionHandler: @escaping CallConfigRequestCompletion)
}

public typealias WireCallMessageToken = UnsafeMutableRawPointer


public struct CallEvent {
    let data: Data
    let currentTimestamp: Date
    let serverTimestamp: Date
    let conversationId: UUID
    let userId: UUID
    let clientId: String
}

// MARK: - WireCallCenterV3

/**
 * WireCallCenter is used for making wire calls and observing their state. There can only be one instance of the WireCallCenter. 
 * Thread safety: WireCallCenter instance methods should only be called from the main thread, class method can be called from any thread.
 */
@objc public class WireCallCenterV3 : NSObject {
    
    /// The selfUser remoteIdentifier
    fileprivate let selfUserId : UUID

    /// establishedDate - Date of when the call was established (Participants can talk to each other). This property is only valid when the call state is .established.
    public private(set) var establishedDate : Date?
    
    fileprivate weak var transport : WireCallCenterTransport? = nil
    
    /// Used to collect incoming events (e.g. from fetching the notification stream) until AVS is ready to process them
    var bufferedEvents : [CallEvent]  = []
    
    /// Set to true once AVS calls the ReadyHandler. Setting it to true forwards all previously buffered events to AVS
    fileprivate var isReady : Bool = false {
        didSet {
            if isReady {
                bufferedEvents.forEach{ avsWrapper.received(callEvent: $0) }
                bufferedEvents = []
            }
        }
    }
    
    /// We keep a snaphot of the call state for each none idle conversation
    fileprivate var callSnapshots : [UUID : CallSnapshot] = [:]
    
    /// Removes the participantSnapshot and remove the conversation from the list of ignored conversations
    fileprivate func clearSnapshot(conversationId: UUID) {
        callSnapshots.removeValue(forKey: conversationId)
    }
    
    internal func createSnapshot(callState : CallState, members: [AVSCallMember], callStarter: UUID?, video: Bool, for conversationId: UUID) {
        guard let moc = uiMOC,
              let conversation = ZMConversation(remoteID: conversationId, createIfNeeded: false, in: moc)
        else { return }
        
        let callParticipants = CallParticipantsSnapshot(conversationId: conversationId, members: members, callCenter: self)
        let token = ConversationChangeInfo.add(observer: self, for: conversation)
        let group = conversation.conversationType == .group
        callSnapshots[conversationId] = CallSnapshot(callParticipants: callParticipants,
                                                     callState: callState,
                                                     callStarter: callStarter ?? selfUserId,
                                                     isVideo: video,
                                                     isGroup: group,
                                                     isConstantBitRate: false,
                                                     videoState: video ? .started : .stopped,
                                                     conversationObserverToken: token)
    }
    
    public var useConstantBitRateAudio: Bool = false
    
    var avsWrapper : AVSWrapperType!
    weak var uiMOC : NSManagedObjectContext?
    let analytics: AnalyticsType?
    let flowManager : FlowManagerType
    let audioOnlyParticipantLimit = 4
    
    deinit {
        avsWrapper.close()
    }
    
    public required init(userId: UUID, clientId: String, avsWrapper: AVSWrapperType? = nil, uiMOC: NSManagedObjectContext, flowManager: FlowManagerType, analytics: AnalyticsType? = nil, transport: WireCallCenterTransport) {
        self.selfUserId = userId
        self.uiMOC = uiMOC
        self.flowManager = flowManager
        self.analytics = analytics
        self.transport = transport
        
        super.init()
        
        let observer = Unmanaged.passUnretained(self).toOpaque()
        self.avsWrapper = avsWrapper ?? AVSWrapper(userId: userId, clientId: clientId, observer: observer)
    }
    
    fileprivate func send(token: WireCallMessageToken, conversationId: UUID, userId: UUID, clientId: String, data: Data, dataLength: Int) {
        transport?.send(data: data, conversationId: conversationId, userId: userId, completionHandler: { [weak self] status in
            guard let `self` = self else { return }
            
            self.avsWrapper.handleResponse(httpStatus: status, reason: "", context: token)
        })
    }
    
    fileprivate func requestCallConfig() {
        zmLog.debug("\(self): requestCallConfig(), transport = \(String(describing: transport))")
        transport?.requestCallConfig(completionHandler: { [weak self] (config, httpStatusCode) in
            guard let `self` = self else { return }
            zmLog.debug("\(self): self.avsWrapper.update with \(String(describing: config))")
            self.avsWrapper.update(callConfig: config, httpStatusCode: httpStatusCode)
        })
    }
    
    fileprivate func handleCallState(callState: CallState, conversationId: UUID, userId: UUID?, messageTime: Date? = nil) {
        callState.logState()
        var callState = callState
        
        switch callState {
        case .incoming(video: let video, shouldRing: _, degraded: _):
            createSnapshot(callState: callState, members: [AVSCallMember(userId: userId!)], callStarter: userId, video: video, for: conversationId)
        case .established:
            // WORKAROUND: the call established handler will is called once for every participant in a
            // group call. Until that's no longer the case we must take care to only set establishedDate once.
            if self.callState(conversationId: conversationId) != .established {
                establishedDate = Date()
            }
            
            if let userId = userId {
                callParticipantAudioEstablished(conversationId: conversationId, userId: userId)
            }
            
            if videoState(conversationId: conversationId) == .started {
                avsWrapper.setVideoState(conversationId: conversationId, videoState: .started)
            }
        case .establishedDataChannel:
            if self.callState(conversationId: conversationId) == .established {
                return // Ignore if data channel was established after audio
            }
        case .terminating(reason: let reason) where reason == .stillOngoing:
            callState = .incoming(video: false, shouldRing: false, degraded: isDegraded(conversationId: conversationId))
        default:
            break
        }
        
        let callerId = initiatorForCall(conversationId: conversationId)
        
        let previousCallState = callSnapshots[conversationId]?.callState
        
        if case .terminating = callState {
            clearSnapshot(conversationId: conversationId)
        } else if let previousSnapshot = callSnapshots[conversationId] {
            callSnapshots[conversationId] = previousSnapshot.update(with: callState)
        }
        
        if let context = uiMOC, let callerId = callerId  {
            WireCallCenterCallStateNotification(context: context, callState: callState, conversationId: conversationId, callerId: callerId, messageTime: messageTime, previousCallState:previousCallState).post(in: context.notificationContext)
        }
    }
    
    fileprivate func missed(conversationId: UUID, userId: UUID, timestamp: Date, isVideoCall: Bool) {
        zmLog.debug("missed call")
        
        if let context = uiMOC {
            WireCallCenterMissedCallNotification(context: context, conversationId: conversationId, callerId: userId, timestamp: timestamp, video: isVideoCall).post(in: context.notificationContext)
        }
    }
    
    public func received(data: Data, currentTimestamp: Date, serverTimestamp: Date, conversationId: UUID, userId: UUID, clientId: String) {
        let callEvent = CallEvent(data: data, currentTimestamp: currentTimestamp, serverTimestamp: serverTimestamp, conversationId: conversationId, userId: userId, clientId: clientId)
        
        if isReady {
            avsWrapper.received(callEvent: callEvent)
        } else {
            bufferedEvents.append(callEvent)
        }
    }
    
    // MARK: - Call state methods


    @objc(answerCallForConversationID:video:)
    public func answerCall(conversation: ZMConversation, video: Bool) -> Bool {
        guard let conversationId = conversation.remoteIdentifier else { return false }
        
        endAllCalls(exluding: conversationId)
        
        let callType: AVSCallType = conversation.activeParticipants.count > audioOnlyParticipantLimit ? .audioOnly : .normal
        
        if !video {
            setVideoState(conversationId: conversationId, videoState: VideoState.stopped)
        }
        let answered = avsWrapper.answerCall(conversationId: conversationId, callType: callType, useCBR: useConstantBitRateAudio)
        if answered {
            let callState : CallState = .answered(degraded: isDegraded(conversationId: conversationId))
            
            let previousSnapshot = callSnapshots[conversationId]
            
            if previousSnapshot != nil {
                callSnapshots[conversationId] = previousSnapshot!.update(with: callState)
            }
            
            if let context = uiMOC, let callerId = initiatorForCall(conversationId: conversationId) {
                WireCallCenterCallStateNotification(context: context, callState: callState, conversationId: conversationId, callerId: callerId, messageTime:nil, previousCallState: previousSnapshot?.callState).post(in: context.notificationContext)
            }
        }
        
        return answered
    }
    
    @objc(startCallForConversationID:video:)
    public func startCall(conversation: ZMConversation, video: Bool) -> Bool {
        guard let conversationId = conversation.remoteIdentifier else { return false }
        
        endAllCalls(exluding: conversationId)
        clearSnapshot(conversationId: conversationId) // make sure we don't have an old state for this conversation
        
        let conversationType: AVSConversationType = conversation.conversationType == .group ? .group : .oneToOne
        let callType: AVSCallType
        if conversation.activeParticipants.count > audioOnlyParticipantLimit {
            callType = .audioOnly
        } else {
            callType = video ? .video : .normal
        }
        
        let started = avsWrapper.startCall(conversationId: conversationId, callType: callType, conversationType: conversationType, useCBR: useConstantBitRateAudio)
        if started {
            let callState: CallState = .outgoing(degraded: isDegraded(conversationId: conversationId))
            
            let members: [AVSCallMember] = {
                guard let user = conversation.connectedUser, conversation.conversationType == .oneOnOne else { return [] }
                return [AVSCallMember(userId: user.remoteIdentifier)]
            }()

            let previousCallState = callSnapshots[conversationId]?.callState
            createSnapshot(callState: callState, members: members, callStarter: selfUserId, video: video, for: conversationId)
            
            if let context = uiMOC {
                WireCallCenterCallStateNotification(context: context, callState: callState, conversationId: conversationId, callerId: selfUserId, messageTime: nil, previousCallState: previousCallState).post(in: context.notificationContext)
            }
        }
        return started
    }
    
    public func closeCall(conversationId: UUID, reason: CallClosedReason = .normal) {
        avsWrapper.endCall(conversationId: conversationId)
        if let previousSnapshot = callSnapshots[conversationId] {
            if previousSnapshot.isGroup {
                let callState : CallState = .incoming(video: previousSnapshot.isVideo, shouldRing: false, degraded: isDegraded(conversationId: conversationId))
                callSnapshots[conversationId] = previousSnapshot.update(with: callState)
            } else {
                callSnapshots[conversationId] = previousSnapshot.update(with: .terminating(reason: reason))
            }
        }
    }
    
    @objc(rejectCallForConversationID:)
    public func rejectCall(conversationId: UUID) {
        avsWrapper.rejectCall(conversationId: conversationId)
        
        if let previousSnapshot = callSnapshots[conversationId] {
            let callState : CallState = .incoming(video: previousSnapshot.isVideo, shouldRing: false, degraded: isDegraded(conversationId: conversationId))
            callSnapshots[conversationId] = previousSnapshot.update(with: callState)
        }
    }
    
    public func endAllCalls(exluding: UUID? = nil) {
        nonIdleCalls.forEach { (key: UUID, callState: CallState) in
            guard exluding == nil || key != exluding else { return }
            
            switch callState {
            case .incoming:
                rejectCall(conversationId: key)
            default:
                closeCall(conversationId: key)
            }
        }
    }
    
    public func setVideoState(conversationId: UUID, videoState: VideoState) {
        guard videoState != .badConnection else { return }
        
        if let snapshot = callSnapshots[conversationId] {
            callSnapshots[conversationId] = snapshot.updateVideoState(videoState)
        }
        
        avsWrapper.setVideoState(conversationId: conversationId, videoState: videoState)
    }
    
    @objc(isVideoCallForConversationID:)
    public func isVideoCall(conversationId: UUID) -> Bool {
        return callSnapshots[conversationId]?.isVideo ?? false
    }
    
    @objc(isConstantBitRateInConversationID:)
    public func isContantBitRate(conversationId: UUID) -> Bool {
        return callSnapshots[conversationId]?.isConstantBitRate ?? false
    }
    
    public func videoState(conversationId: UUID) -> VideoState {
        return callSnapshots[conversationId]?.videoState ?? .stopped
    }
    
    fileprivate func isActive(conversationId: UUID) -> Bool {
        switch callState(conversationId: conversationId) {
        case .established, .establishedDataChannel:
            return true
        default:
            return false
        }
    }
    
    fileprivate func isDegraded(conversationId: UUID) -> Bool {
        let conversation = ZMConversation(remoteID: conversationId, createIfNeeded: false, in: uiMOC!)
        let degraded = conversation?.securityLevel == .secureWithIgnored
        return degraded
    }
    
    public func setVideoCaptureDevice(_ captureDevice: CaptureDevice, for conversationId: UUID) {
        flowManager.setVideoCaptureDevice(captureDevice, for: conversationId)
    }
    
    /// nonIdleCalls maps all non idle conversations to their corresponding call state
    public var nonIdleCalls : [UUID : CallState] {
        
        var callStates : [UUID : CallState] = [:]
        
        for (conversationId, snapshot) in callSnapshots {
            callStates[conversationId] = snapshot.callState
        }
        
        return callStates
    }
    
    public var activeCalls: [UUID: CallState] {
        return nonIdleCalls.filter({ key, callState in
            switch callState {
            case .established, .establishedDataChannel:
                return true
            default:
                return false
            }
        })
    }
    
    /// Returns conversations with active calls
    public func activeCallConversations(in userSession: ZMUserSession) -> [ZMConversation] {
        let conversations = nonIdleCalls.compactMap { (key: UUID, value: CallState) -> ZMConversation? in
            if value == CallState.established {
                return ZMConversation(remoteID: key, createIfNeeded: false, in: userSession.managedObjectContext)
            } else {
                return nil
            }
        }
        
        return conversations
    }
    
    // Returns conversations with a non idle call state
    public func nonIdleCallConversations(in userSession: ZMUserSession) -> [ZMConversation] {
        let conversations = nonIdleCalls.compactMap { (key: UUID, value: CallState) -> ZMConversation? in
            return ZMConversation(remoteID: key, createIfNeeded: false, in: userSession.managedObjectContext)
        }
        
        return conversations
    }
    
    /// Gets the current callState from AVS
    /// If the group call was ignored or left, it return .incoming where shouldRing is set to false
    public func callState(conversationId: UUID) -> CallState {
        return callSnapshots[conversationId]?.callState ?? .none
    }
    
    // MARK: - Call Participants

    /// Returns the callParticipants currently in the conversation
    func callParticipants(conversationId: UUID) -> [UUID] {
        return callSnapshots[conversationId]?.callParticipants.members.map { $0.remoteId } ?? []
    }
    
    func initiatorForCall(conversationId: UUID) -> UUID? {
        return callSnapshots[conversationId]?.callStarter
    }
    
    /// Call this method when the callParticipants changed and avs calls the handler `wcall_group_changed_h`
    func callParticipantsChanged(conversationId: UUID, participants: [AVSCallMember]) {
        callSnapshots[conversationId]?.callParticipants.callParticipantsChanged(participants: participants)
    }
    
    func callParticipantVideostateChanged(conversationId: UUID, userId: UUID, videoState: VideoState) {
        callSnapshots[conversationId]?.callParticipants.callParticpantVideoStateChanged(userId: userId, videoState: videoState)
    }
    
    func callParticipantAudioEstablished(conversationId: UUID, userId: UUID) {
        callSnapshots[conversationId]?.callParticipants.callParticpantAudioEstablished(userId: userId)
    }
    
    /// Returns the state for a call participant.
    public func state(forUser userId: UUID, in conversationId: UUID) -> CallParticipantState {
        return callSnapshots[conversationId]?.callParticipants.callParticipantState(forUser: userId) ?? .unconnected
    }

}

extension WireCallCenterV3 : ZMConversationObserver {
    
    public func conversationDidChange(_ changeInfo: ConversationChangeInfo) {
        guard
            changeInfo.securityLevelChanged,
            let conversationId = changeInfo.conversation.remoteIdentifier,
            let previousSnapshot = callSnapshots[conversationId]
        else { return }
        
        if changeInfo.conversation.securityLevel == .secureWithIgnored, isActive(conversationId: conversationId) {
            // If an active call degrades we end it immediately
            return closeCall(conversationId: conversationId, reason: .securityDegraded)
        }
        
        let updatedCallState = previousSnapshot.callState.update(withSecurityLevel: changeInfo.conversation.securityLevel)
        
        if updatedCallState != previousSnapshot.callState {
            callSnapshots[conversationId] = previousSnapshot.update(with: updatedCallState)
            
            if let context = uiMOC, let callerId = initiatorForCall(conversationId: conversationId) {
                WireCallCenterCallStateNotification(context: context, callState: updatedCallState, conversationId: conversationId, callerId: callerId, messageTime: Date(), previousCallState: previousSnapshot.callState).post(in: context.notificationContext)
            }
        }
    }
    
}
