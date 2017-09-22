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
    /// Call left by the selfUser but continues until everyone else leaves or AVS closes it
    case stillOngoing
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
        case WCALL_REASON_STILL_ONGOING:
            self = .stillOngoing
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
    case incoming(video: Bool, shouldRing: Bool)
    /// Call is answered
    case answered
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
        case (.none, .none):
            fallthrough
        case (.outgoing, .outgoing):
            fallthrough
        case (.answered, .answered):
            fallthrough
        case (.established, .established):
            fallthrough
        case (.terminating, .terminating):
            fallthrough
        case (.unknown, .unknown):
            return true
        case (.incoming(video: let lVideo, shouldRing: let lShouldRing), .incoming(video: let rVideo, shouldRing: let rShouldRing)):
            return lVideo == rVideo && lShouldRing == rShouldRing
        default:
            return false
        }
    }
    
    init(wcallState: Int32) {
        switch wcallState {
        case WCALL_STATE_NONE:
            self = .none
        case WCALL_STATE_INCOMING:
            self = .incoming(video: false, shouldRing: true)
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
    
    func logState(){
        switch self {
        case .answered:
            zmLog.debug("answered call")
        case .incoming(video: let isVideo, shouldRing: let shouldRing):
            zmLog.debug("incoming call, isVideo: \(isVideo), shouldRing: \(shouldRing)")
        case .establishedDataChannel:
            zmLog.debug("established data channel")
        case .established:
            zmLog.debug("established call")
        case .outgoing:
            zmLog.debug("outgoing call")
        case .terminating(reason: let reason):
            zmLog.debug("terminating call reason: \(reason)")
        case .none:
            zmLog.debug("no call")
        case .unknown:
            zmLog.debug("unknown call state")
        }
    }
}

public struct CallMember : Hashable {

    let remoteId : UUID
    let audioEstablished : Bool
    
    init?(wcallMember: wcall_member) {
        guard let remoteId = UUID(cString:wcallMember.userid) else { return nil }
        self.remoteId = remoteId
        audioEstablished = (wcallMember.audio_estab != 0)
    }
    
    init(userId : UUID, audioEstablished: Bool) {
        self.remoteId = userId
        self.audioEstablished = audioEstablished
    }
    
    public var hashValue: Int {
        return remoteId.hashValue
    }
    
    public static func ==(lhs: CallMember, rhs: CallMember) -> Bool {
        return lhs.remoteId == rhs.remoteId
    }
}

private struct CallSnapshot {
    let callState : CallState
    let isVideo : Bool
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

internal func incomingCallHandler(conversationId: UnsafePointer<Int8>?, messageTime: UInt32, userId: UnsafePointer<Int8>?, isVideoCall: Int32, shouldRing: Int32, contextRef: UnsafeMutableRawPointer?)
{
    guard let contextRef = contextRef, let convID = UUID(cString: conversationId), let userID = UUID(cString: userId) else { return }
    let callCenter = Unmanaged<WireCallCenterV3>.fromOpaque(contextRef).takeUnretainedValue()
    
    callCenter.uiMOC?.performGroupedBlock {
        callCenter.handleCallState(callState: .incoming(video: isVideoCall != 0, shouldRing: shouldRing != 0), conversationId: convID, userId: userID, messageTime: Date(timeIntervalSince1970: TimeInterval(messageTime)))
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
        callCenter.handleCallState(callState: .answered, conversationId: convID, userId: nil)
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
        callCenter.handleCallState(callState: .terminating(reason: CallClosedReason(reason: reason)), conversationId: convID, userId: userID, messageTime: time)
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

/// Sets the calling protocol when AVS is ready
/// In order to be passed to C, this function needs to be global
internal func readyHandler(version: Int32, contextRef: UnsafeMutableRawPointer?)
{
    guard let contextRef = contextRef else { return }
    
    if let callingProtocol = CallingProtocol(rawValue: Int(version)) {
        let callCenter = Unmanaged<WireCallCenterV3>.fromOpaque(contextRef).takeUnretainedValue()
        
        callCenter.uiMOC?.performGroupedBlock {
            callCenter.callingProtocol = callingProtocol
            callCenter.isReady = true
        }
    } else {
        zmLog.error("wcall initialized with unknown protocol version: \(version)")
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

/// MARK - WireCallCenterV3

/**
 * WireCallCenter is used for making wire calls and observing their state. There can only be one instance of the WireCallCenter. 
 * Thread safety: WireCallCenter instance methods should only be called from the main thread, class method can be called from any thread.
 */
@objc public class WireCallCenterV3 : NSObject {
    
    /// The selfUser remoteIdentifier
    fileprivate let selfUserId : UUID

    @objc public static let cbrNotificationName = WireCallCenterCBRCallNotification.notificationName

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
    
    public fileprivate(set) var callingProtocol : CallingProtocol = .version3
    
    /// We keep a snapshot of all participants so that we can notify the UI when a user is connected or when the stereo sorting changes
    fileprivate var participantSnapshots : [UUID : VoiceChannelParticipantV3Snapshot] = [:]
    
    /// We keep a snaphot of the call state for each none idle conversation
    fileprivate var callSnapshots : [UUID : CallSnapshot] = [:]
    
    /// Removes the participantSnapshot and remove the conversation from the list of ignored conversations
    fileprivate func clearSnapshot(conversationId: UUID) {
        callSnapshots.removeValue(forKey: conversationId)
        participantSnapshots.removeValue(forKey: conversationId)
    }
    
    var avsWrapper : AVSWrapperType!
    weak var uiMOC : NSManagedObjectContext?
    let analytics: AnalyticsType?
    let flowManager : FlowManagerType
    
    public var useAudioConstantBitRate: Bool = false {
        didSet {
            avsWrapper.enableAudioCbr(shouldUseCbr: useAudioConstantBitRate)
        }
    }
    
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
        var userId = userId
        
        switch callState {
        case .established:
            establishedDate = Date()
            
            if isVideoCall(conversationId: conversationId) {
                avsWrapper.setVideoSendActive(userId: conversationId, active: true)
            }
        case .establishedDataChannel:
            if self.callState(conversationId: conversationId) == .established {
                return // Ignore if data channel was established after audio
            }
        case .terminating(reason: let reason):
            if reason == .stillOngoing {
                callState = .incoming(video: false, shouldRing: false)
                userId = initiatorForCall(conversationId: conversationId) ?? selfUserId
            }
        default:
            break
        }
        
        updateSnapshots(forCallSate: callState, conversationId: conversationId, userId: userId)
        WireCallCenterCallStateNotification(callState: callState, conversationId: conversationId, userId: userId, messageTime: messageTime).post()
    }
    
    fileprivate func updateSnapshots(forCallSate callState: CallState, conversationId: UUID, userId: UUID?) {
        
        switch callState {
        case .incoming(video: let video, shouldRing: _):
            callSnapshots[conversationId] = CallSnapshot(callState: callState, isVideo: video)
            
            participantSnapshots[conversationId] = VoiceChannelParticipantV3Snapshot(conversationId: conversationId,
                                                                                     selfUserID: selfUserId,
                                                                                     members: [CallMember(userId: userId!, audioEstablished: false)],
                                                                                     initiator: userId,
                                                                                     callCenter: self)
        case .terminating:
            clearSnapshot(conversationId: conversationId)
            
        default:
            if let previousSnapshot = callSnapshots[conversationId] {
                callSnapshots[conversationId] = CallSnapshot(callState: callState, isVideo: previousSnapshot.isVideo)
            }
        }
        
    }
    
    fileprivate func missed(conversationId: UUID, userId: UUID, timestamp: Date, isVideoCall: Bool) {
        zmLog.debug("missed call")
        
        WireCallCenterMissedCallNotification(conversationId: conversationId, userId:userId, timestamp: timestamp, video: isVideoCall).post()
    }
    
    public func received(data: Data, currentTimestamp: Date, serverTimestamp: Date, conversationId: UUID, userId: UUID, clientId: String) {
        let callEvent = CallEvent(data: data, currentTimestamp: currentTimestamp, serverTimestamp: serverTimestamp, conversationId: conversationId, userId: userId, clientId: clientId)
        
        if isReady {
            avsWrapper.received(callEvent: callEvent)
        } else {
            bufferedEvents.append(callEvent)
        }
    }
    
    // MARK - Call state methods


    @objc(answerCallForConversationID:)
    public func answerCall(conversationId: UUID) -> Bool {
        let answered = avsWrapper.answerCall(conversationId: conversationId)
        if answered {
            if let previousSnapshot = callSnapshots[conversationId] {
                callSnapshots[conversationId] = CallSnapshot(callState: .answered, isVideo: previousSnapshot.isVideo)
            }
            
            WireCallCenterCallStateNotification(callState: .answered, conversationId: conversationId, userId: self.selfUserId, messageTime:nil).post()
        }
        return answered
    }
    

    @objc(startCallForConversationID:video:isGroup:)
    public func startCall(conversationId: UUID, video: Bool, isGroup: Bool) -> Bool {
        clearSnapshot(conversationId: conversationId) // make sure we don't have an old state for this conversation
        
        let started = avsWrapper.startCall(conversationId: conversationId, video: video, isGroup: isGroup)
        if started {
            callSnapshots[conversationId] = CallSnapshot(callState: .outgoing, isVideo: video)
            WireCallCenterCallStateNotification(callState: .outgoing, conversationId: conversationId, userId: selfUserId, messageTime:nil).post()
        }
        return started
    }
    

    @objc(closeCallForConversationID:isGroup:)
    public func closeCall(conversationId: UUID, isGroup: Bool) {
        avsWrapper.endCall(conversationId: conversationId)
        if isGroup, let previousSnapshot = callSnapshots[conversationId] { // TODO move isGroup into CallSnapshot
            callSnapshots[conversationId] = CallSnapshot(callState: .incoming(video: previousSnapshot.isVideo, shouldRing: false), isVideo: previousSnapshot.isVideo)
        }
    }
    
    @objc(rejectCallForConversationID:)
    public func rejectCall(conversationId: UUID) {
        avsWrapper.rejectCall(conversationId: conversationId)
        
        if let previousSnapshot = callSnapshots[conversationId] {
            callSnapshots[conversationId] = CallSnapshot(callState: .incoming(video: previousSnapshot.isVideo, shouldRing: false), isVideo: previousSnapshot.isVideo)
        }
    }
    
    @objc(toogleVideoForConversationID:isActive:)
    public func toogleVideo(conversationID: UUID, active: Bool) {
        avsWrapper.toggleVideo(conversationID: conversationID, active: active)
    }
    
    @objc(isVideoCallForConversationID:)
    public func isVideoCall(conversationId: UUID) -> Bool {
        return callSnapshots[conversationId]?.isVideo ?? false
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
    
    /// Gets the current callState from AVS
    /// If the group call was ignored or left, it return .incoming where shouldRing is set to false
    public func callState(conversationId: UUID) -> CallState {
        return callSnapshots[conversationId]?.callState ?? .none
    }
    
    // MARK - WireCallCenterV3 - Call Participants

    /// Returns the callParticipants currently in the conversation
    func callParticipants(conversationId: UUID) -> [UUID] {
        return participantSnapshots[conversationId]?.members.map{ $0.remoteId } ?? []
    }
    
    func initiatorForCall(conversationId: UUID) -> UUID? {
        let snapshot = participantSnapshots[conversationId]
        return snapshot?.initiator
    }
    
    /// Call this method when the callParticipants changed and avs calls the handler `wcall_group_changed_h`
    func callParticipantsChanged(conversationId: UUID, participants: [CallMember]) {
        if let snapshot = participantSnapshots[conversationId] {
            snapshot.callParticipantsChanged(newParticipants: participants)
        } else if participants.count > 0 {
            participantSnapshots[conversationId] = VoiceChannelParticipantV3Snapshot(conversationId: conversationId,
                                                                                     selfUserID: selfUserId,
                                                                                     members: participants,
                                                                                     callCenter: self)
        }
    }
    
    /// Returns the connectionState of a user in a conversation
    /// We keep a snapshot of the callParticipants and activeFlowParticipants
    /// If the user is contained in the callParticipants and in the activeFlowParticipants, he is connected
    /// If the user is only contained in the callParticipants, he is connecting
    /// Otherwise he is notConnected
    public func connectionState(forUserWith userId: UUID, in conversationId: UUID) -> VoiceChannelV2ConnectionState {
        return participantSnapshots[conversationId]?.connectionState(forUserWith:userId) ?? .invalid
    }

}
