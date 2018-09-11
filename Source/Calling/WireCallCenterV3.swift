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

//    case rejectedElsewhere
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


// MARK - Call center transport

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

internal func mediaStoppedChangeHandler(conversationIdRef: UnsafePointer<Int8>?, contextRef: UnsafeMutableRawPointer?) {
    guard let contextRef = contextRef, let conversationId = UUID(cString: conversationIdRef) else { return }
    
    let callCenter = Unmanaged<WireCallCenterV3>.fromOpaque(contextRef).takeUnretainedValue()
    
    callCenter.uiMOC?.performGroupedBlock {
        callCenter.handleCallState(callState: .mediaStopped, conversationId: conversationId, userId: nil)
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

    let handler: @convention(c) (Int32, UnsafeMutableRawPointer) -> Void = { _, _ in

    }
    
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
        case .terminating(reason: .stillOngoing):
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

extension WireCallCenterV3 {

    private func handleEvent(_ description: String, _ handlerBlock: @escaping () -> Void) {
        guard let context = self.uiMOC else {
            zmLog.error("Cannot handle event '\(description)' because the UI context is not available.")
            return
        }

        context.performGroupedBlock {
            handlerBlock()
        }
    }

    private func handleEventInContext(_ description: String, _ handlerBlock: @escaping (NSManagedObjectContext) -> Void) {
        guard let context = self.uiMOC else {
            zmLog.error("Cannot handle event '\(description)' because the UI context is not available.")
            return
        }

        context.performGroupedBlock {
            handlerBlock(context)
        }
    }

    /// Handles incoming calls.
    func handleIncomingCall(conversationId: UUID, messageTime: Date, userId: UUID, isVideoCall: Bool, shouldRing: Bool) {
        handleEvent("incoming-call") {
            let callState : CallState = .incoming(video: isVideoCall, shouldRing: shouldRing, degraded: self.isDegraded(conversationId: conversationId))
            self.handleCallState(callState: callState, conversationId: conversationId, userId: userId, messageTime: messageTime)
        }
    }

    /// Handles missed calls.
    func handleMissedCall(conversationId: UUID, messageTime: Date, userId: UUID, isVideoCall: Bool) {
        handleEvent("missed-call") {
            self.missed(conversationId: conversationId, userId: userId, timestamp: messageTime, isVideoCall: isVideoCall)
        }
    }

    /// Handles answered calls.
    func handleAnsweredCall(conversationId: UUID) {
        handleEvent("answered-call") {
            self.handleCallState(callState: .answered(degraded: self.isDegraded(conversationId: conversationId)),
                                 conversationId: conversationId, userId: nil)
        }
    }

    /// Handles when data channel gets established.
    func handleDataChannelEstablishement(conversationId: UUID, userId: UUID) {
        handleEvent("data-channel-established") {
            self.handleCallState(callState: .establishedDataChannel, conversationId: conversationId, userId: userId)
        }
    }

    /// Handles established calls.
    func handleEstablishedCall(conversationId: UUID, userId: UUID) {
        handleEvent("established-call") {
            self.handleCallState(callState: .established, conversationId: conversationId, userId: userId)
        }
    }

    /**
     * Handles ended calls
     * If the user answers on the different device, we receive a `WCALL_REASON_ANSWERED_ELSEWHERE` followed by a
     * `WCALL_REASON_NORMAL` once the call ends.
     *
     * If the user leaves an ongoing group conversation or an incoming group call times out, we receive a
     * `WCALL_REASON_STILL_ONGOING` followed by a `WCALL_REASON_NORMAL` once the call ends.
     *
     * If messageTime is set to 0, the event wasn't caused by a message therefore we don't have a serverTimestamp.
     */

    func handleCallEnd(reason: CallClosedReason, conversationId: UUID, messageTime: Date?, userId: UUID) {
        handleEvent("closed-call") {
            self.handleCallState(callState: .terminating(reason: reason), conversationId: conversationId, userId: userId, messageTime: messageTime)
        }
    }

    /// Handles call metrics.
    func handleCallMetrics(conversationId: UUID, metrics: String) {
        do {
            let metricsData = Data(metrics.utf8)
            guard let attributes = try JSONSerialization.jsonObject(with: metricsData, options: .mutableContainers) as? [String: NSObject] else { return }
            analytics?.tagEvent("calling.avs_metrics_ended_call", attributes: attributes)
        } catch {
            zmLog.error("Unable to parse call metrics JSON: \(error)")
        }
    }

    /// Handle requests for refreshing the calling configuration.
    func handleCallConfigRefreshRequest() {
        handleEvent("request-call-config") {
            self.requestCallConfig()
        }
    }

    /// Handles sending call messages
    internal func handleCallMessageRequest(token: WireCallMessageToken,
                                           conversationId: UUID,
                                           senderUserId: UUID,
                                           senderClientId: String,
                                           data: Data)
    {
        handleEvent("send-call-message") {
            self.send(token: token,
                      conversationId: conversationId,
                      userId: senderUserId,
                      clientId: senderClientId,
                      data: data,
                      dataLength: data.count)
        }
    }

    /// Called when AVS is ready.
    func setCallReady(version: Int32) {
        zmLog.debug("wcall intialized with protocol version: \(version)")
        handleEvent("call-ready") {
            self.isReady = true
        }
    }

    /// Handles other users joining / leaving / connecting.
    func handleGroupMemberChange(conversationId: UUID) {
        handleEvent("group-member-change") {
            let members = self.avsWrapper.members(in: conversationId)
            self.callParticipantsChanged(conversationId: conversationId, participants: members)
        }
    }

    /// Handles video state changes.
    func handleVideoStateChange(userId: UUID, newState: VideoState) {
        handleEvent("video-state-change") {
            self.nonIdleCalls.forEach {
                self.callParticipantVideostateChanged(conversationId: $0.key, userId: userId, videoState: newState)
            }
        }
    }

    /// Handles audio CBR mode enabling.
    func handleConstantBitRateChange(enabled: Bool) {
        handleEventInContext("cbr-change") {
            if let establishedCall = self.callSnapshots.first(where: { $0.value.callState == .established || $0.value.callState == .establishedDataChannel }) {
                self.callSnapshots[establishedCall.key] = establishedCall.value.updateConstantBitrate(enabled)
                WireCallCenterCBRNotification(enabled: enabled).post(in: $0.notificationContext)
            }
        }
    }

}

