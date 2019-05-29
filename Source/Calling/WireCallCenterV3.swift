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

private let zmLog = ZMSLog(tag: "calling")

/**
 * WireCallCenter is used for making Wire calls and observing their state. There can only be one instance of the
 * WireCallCenter.
 *
 * Thread safety: WireCallCenter instance methods should only be called from the main thread, class method can be
 * called from any thread.
 */
@objc public class WireCallCenterV3: NSObject {

    /// The maximum number of participants for a video call.
    let videoParticipantsLimit = 4

    // MARK: - Properties

    /// The selfUser remoteIdentifier
    let selfUserId : UUID

    /// The object that controls media flow.
    let flowManager: FlowManagerType

    /// The object to use to record stats about the call.
    let analytics: AnalyticsType?

    /// The bridge to use to communicate with and receive events from AVS.
    var avsWrapper: AVSWrapperType!

    /// The Core Data context to use to coordinate events.
    weak var uiMOC: NSManagedObjectContext?

    /// The object that performs network requests when the call center requests them.
    weak var transport : WireCallCenterTransport? = nil

    // MARK: - Calling State

    /**
     * The date when the call was established (Participants can talk to each other).
     * - note: This property is only valid when the call state is `.established`.
     */

    var establishedDate : Date?

    /**
     * Whether we use constant bit rate for calls.
     * - note: Changing this property after the call has started has no effect.
     */

    var useConstantBitRateAudio: Bool = false

    /// The snaphot of the call state for each non-idle conversation.
    var callSnapshots : [UUID : CallSnapshot] = [:]

    /// Used to collect incoming events (e.g. from fetching the notification stream) until AVS is ready to process them.
    var bufferedEvents : [(event: CallEvent, completionHandler: () -> Void)]  = []
    
    /// Set to true once AVS calls the ReadyHandler. Setting it to `true` forwards all previously buffered events to AVS.
    var isReady : Bool = false {
        didSet {
            if isReady {
                bufferedEvents.forEach { (item: (event: CallEvent, completionHandler: () -> Void)) in
                    let (event, completionHandler) = item
                    handleCallEvent(event, completionHandler: completionHandler)
                }
                bufferedEvents = []
            }
        }
    }

    // MARK: - Initialization
    
    deinit {
        avsWrapper.close()
    }

    /**
     * Creates a call center with the required details.
     * - parameter userId: The identifier of the current signed-in user.
     * - parameter clientId: The identifier of the current client on the user's account.
     * - parameter avsWrapper: The bridge to use to communicate with and receive events from AVS.
     * If you don't specify one, a default object will be created. Defaults to `nil`.
     * - parameter uiMOC: The Core Data context to use to coordinate events.
     * - parameter flowManager: The object that controls media flow.
     * - parameter analytics: The object to use to record stats about the call. Defaults to `nil`.
     * - parameter transport: The object that performs network requests when the call center requests them.
     */
    
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

}

// MARK: - Snapshots

extension WireCallCenterV3 {

    /// Removes the participantSnapshot and remove the conversation from the list of ignored conversations.
    func clearSnapshot(conversationId: UUID) {
        callSnapshots.removeValue(forKey: conversationId)
    }

    /**
     * Creates a snapshot for the specified call and adds it to the `callSnapshots` array.
     * - parameter callState:
     * - parameter members: The current members of the call.
     * - parameters callStarter: The ID of the user that started the call.
     * - parameter video: Whether the call is a video call.
     * - parameter conversationId: The identifier of the conversation that hosts the call.
     */

    func createSnapshot(callState : CallState, members: [AVSCallMember], callStarter: UUID?, video: Bool, for conversationId: UUID) {
        guard
            let moc = uiMOC,
            let conversation = ZMConversation(remoteID: conversationId, createIfNeeded: false, in: moc)
        else {
            return
        }

        let callParticipants = CallParticipantsSnapshot(conversationId: conversationId, members: members, callCenter: self)
        let token = ConversationChangeInfo.add(observer: self, for: conversation)
        let group = conversation.conversationType == .group

        callSnapshots[conversationId] = CallSnapshot(
            callParticipants: callParticipants,
            callState: callState,
            callStarter: callStarter ?? selfUserId,
            isVideo: video,
            isGroup: group,
            isConstantBitRate: false,
            videoState: video ? .started : .stopped,
            networkQuality: .normal,
            conversationObserverToken: token
        )
    }

}

// MARK: - State Helpers

extension WireCallCenterV3 {

    /// All non idle conversations and their corresponding call state.
    public var nonIdleCalls : [UUID: CallState] {
        return callSnapshots.mapValues( { $0.callState })
    }

    /// The list of conversation with established calls.
    public var activeCalls: [UUID: CallState] {
        return nonIdleCalls.filter { _, callState in
            switch callState {
            case .established, .establishedDataChannel:
                return true
            default:
                return false
            }
        }
    }

    /**
     * Checks the state of video calling in the conversation.
     * - parameter conversationId: The identifier of the conversation to check the state of.
     * - returns: Whether the conversation hosts a video call.
     */

    @objc(isVideoCallForConversationID:)
    public func isVideoCall(conversationId: UUID) -> Bool {
        return callSnapshots[conversationId]?.isVideo ?? false
    }

    /**
     * Checks the call bitrate type used in the conversation.
     * - parameter conversationId: The identifier of the conversation to check the state of.
     * - returns: Whether the call is being made with a constant bitrate.
     */

    @objc(isConstantBitRateInConversationID:)
    public func isContantBitRate(conversationId: UUID) -> Bool {
        return callSnapshots[conversationId]?.isConstantBitRate ?? false
    }

    /**
     * Determines the video state of the specified user in the conversation.
     * - parameter conversationId: The identifier of the conversation to check the state of.
     * - returns: The video-sending state of the user inside conversation.
     */

    public func videoState(conversationId: UUID) -> VideoState {
        return callSnapshots[conversationId]?.videoState ?? .stopped
    }

    /**
     * Determines the call state of the conversation.
     * - parameter conversationId: The identifier of the conversation to check the state of.
     * - returns: The state of calling of conversation, if any.
     */

    public func callState(conversationId: UUID) -> CallState {
        return callSnapshots[conversationId]?.callState ?? .none
    }

    /**
     * Determines the call state of the conversation.
     * - parameter conversationId: The identifier of the conversation to check the state of.
     * - returns: Whether there is an active call in the conversation.
     */

    public func isActive(conversationId: UUID) -> Bool {
        switch callState(conversationId: conversationId) {
        case .established, .establishedDataChannel:
            return true
        default:
            return false
        }
    }

    /**
     * Determines the degradation of the conversation.
     * - parameter conversationId: The identifier of the conversation to check the state of.
     * - returns: Whether the conversation has degraded security.
     */

    public func isDegraded(conversationId: UUID) -> Bool {
        let conversation = ZMConversation(remoteID: conversationId, createIfNeeded: false, in: uiMOC!)
        let degraded = conversation?.securityLevel == .secureWithIgnored
        return degraded
    }

    /// Returns conversations with active calls.
    public func activeCallConversations(in userSession: ZMUserSession) -> [ZMConversation] {
        let conversations = nonIdleCalls.compactMap { (key: UUID, value: CallState) -> ZMConversation? in
            switch value {
            case .establishedDataChannel, .established, .answered, .outgoing:
                return ZMConversation(remoteID: key, createIfNeeded: false, in: userSession.managedObjectContext)
            default:
                return nil
            }
        }

        return conversations
    }

    /// Returns conversations with a non idle call state.
    public func nonIdleCallConversations(in userSession: ZMUserSession) -> [ZMConversation] {
        let conversations = nonIdleCalls.compactMap { (key: UUID, value: CallState) -> ZMConversation? in
            return ZMConversation(remoteID: key, createIfNeeded: false, in: userSession.managedObjectContext)
        }

        return conversations
    }

    public func networkQuality(conversationId: UUID) -> NetworkQuality {
        return callSnapshots[conversationId]?.networkQuality ?? .normal
    }

}

// MARK: - Call Participants

extension WireCallCenterV3 {

    /// Returns the callParticipants currently in the conversation
    func callParticipants(conversationId: UUID) -> [UUID] {
        return callSnapshots[conversationId]?.callParticipants.members.map { $0.remoteId } ?? []
    }

    /// Returns the remote identifier of the user that initiated the call.
    func initiatorForCall(conversationId: UUID) -> UUID? {
        return callSnapshots[conversationId]?.callStarter
    }

    /// Call this method when the callParticipants changed and avs calls the handler `wcall_group_changed_h`
    func callParticipantsChanged(conversationId: UUID, participants: [AVSCallMember]) {
        callSnapshots[conversationId]?.callParticipants.callParticipantsChanged(participants: participants)
    }

    /// Call this method when the video state of a participant changes and avs calls the `wcall_video_state_change_h`.
    func callParticipantVideoStateChanged(conversationId: UUID, userId: UUID, videoState: VideoState) {
        callSnapshots[conversationId]?.callParticipants.callParticpantVideoStateChanged(userId: userId, videoState: videoState)
    }

    /// Call this method when the client established an audio connection with another user, and avs calls the `wcall_estab_h`.
    func callParticipantAudioEstablished(conversationId: UUID, userId: UUID) {
        callSnapshots[conversationId]?.callParticipants.callParticpantAudioEstablished(userId: userId)
    }

    /// Returns the state for a call participant.
    public func state(forUser userId: UUID, in conversationId: UUID) -> CallParticipantState {
        return callSnapshots[conversationId]?.callParticipants.callParticipantState(forUser: userId) ?? .unconnected
    }

}

// MARK: - Actions

extension WireCallCenterV3 {

    /**
     * Answers an incoming call in the given conversation.
     * - parameter conversation: The conversation hosting the incoming call.
     * - parameter video: Whether to join the call with video.
     */

    @objc(answerCallForConversationID:video:)
    public func answerCall(conversation: ZMConversation, video: Bool) -> Bool {
        guard let conversationId = conversation.remoteIdentifier else { return false }
        
        endAllCalls(exluding: conversationId)
        
        let callType: AVSCallType = conversation.activeParticipants.count > videoParticipantsLimit ? .audioOnly : .normal
        
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

    /**
     * Starts a call in the given conversation.
     * - parameter conversation: The conversation to start the call.
     * - parameter video: Whether to start the call as a video call.
     */
    
    @objc(startCallForConversationID:video:)
    public func startCall(conversation: ZMConversation, video: Bool) -> Bool {
        guard let conversationId = conversation.remoteIdentifier else { return false }
        
        endAllCalls(exluding: conversationId)
        clearSnapshot(conversationId: conversationId) // make sure we don't have an old state for this conversation
        
        let conversationType: AVSConversationType = conversation.conversationType == .group ? .group : .oneToOne
        let callType: AVSCallType
        if conversation.activeParticipants.count > videoParticipantsLimit {
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

    /**
     * Closes the call in the specified conversation.
     * - parameter conversationId: The ID of the conversation where the call should be ended.
     * - parameter reason: The reason why the call should be ended. The default is `.normal` (user action).
     */

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

    /**
     * Rejects an incoming call in the conversation.
     * - parameter conversationId: The ID of the conversation where the incoming call is hosted.
     */
    
    @objc(rejectCallForConversationID:)
    public func rejectCall(conversationId: UUID) {
        avsWrapper.rejectCall(conversationId: conversationId)
        
        if let previousSnapshot = callSnapshots[conversationId] {
            let callState : CallState = .incoming(video: previousSnapshot.isVideo, shouldRing: false, degraded: isDegraded(conversationId: conversationId))
            callSnapshots[conversationId] = previousSnapshot.update(with: callState)
        }
    }

    /**
     * Ends all the calls. You can specify the identifier of a conversation where the call shouldn't be ended.
     * - parameter excluding: If you need to terminate all calls except one, pass the identifier of the conversation
     * that hosts the call to keep alive. If you pass `nil`, all calls will be ended. Defaults to `nil`.
     */
    
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

    /**
     * Enables or disables video for a call.
     * - parameter conversationId: The identifier of the conversation where the video call is hosted.
     * - parameter videoState: The new video state for the self user.
     */
    
    public func setVideoState(conversationId: UUID, videoState: VideoState) {
        guard videoState != .badConnection else { return }
        
        if let snapshot = callSnapshots[conversationId] {
            callSnapshots[conversationId] = snapshot.updateVideoState(videoState)
        }
        
        avsWrapper.setVideoState(conversationId: conversationId, videoState: videoState)
    }

    /**
     * Sets the capture device type to use for video.
     * - parameter captureDevice: The device type to use to capture video for the call.
     * - parameter conversationId: The identifier of the conversation where the video call is hosted.
     */

    public func setVideoCaptureDevice(_ captureDevice: CaptureDevice, for conversationId: UUID) {
        flowManager.setVideoCaptureDevice(captureDevice, for: conversationId)
    }

}

// MARK: - AVS Integration

extension WireCallCenterV3 {

    /// Sends a call OTR message when requested by AVS through `wcall_send_h`.
    func send(token: WireCallMessageToken, conversationId: UUID, userId: UUID, clientId: String, data: Data, dataLength: Int) {
        transport?.send(data: data, conversationId: conversationId, userId: userId, completionHandler: { [weak self] status in
            self?.avsWrapper.handleResponse(httpStatus: status, reason: "", context: token)
        })
    }

    /// Sends the config request when requested by AVS through `wcall_config_req_h`.
    func requestCallConfig() {
        zmLog.debug("\(self): requestCallConfig(), transport = \(String(describing: transport))")
        transport?.requestCallConfig(completionHandler: { [weak self] (config, httpStatusCode) in
            guard let `self` = self else { return }
            zmLog.debug("\(self): self.avsWrapper.update with \(String(describing: config))")
            self.avsWrapper.update(callConfig: config, httpStatusCode: httpStatusCode)
        })
    }

    /// Tags a call as missing when requested by AVS through `wcall_missed_h`.
    func missed(conversationId: UUID, userId: UUID, timestamp: Date, isVideoCall: Bool) {
        zmLog.debug("missed call")

        if let context = uiMOC {
            WireCallCenterMissedCallNotification(context: context, conversationId: conversationId, callerId: userId, timestamp: timestamp, video: isVideoCall).post(in: context.notificationContext)
        }
    }

    /// Handles incoming OTR calling messages, and transmist them to AVS when it is ready to process events, or adds it to the `bufferedEvents`.
    /// - parameter callEvent: calling event to process.
    /// - parameter completionHandler: called after the call event has been processed (this will for example wait for AVS to signal that it's ready).
    func processCallEvent(_ callEvent: CallEvent, completionHandler: @escaping () -> Void) {
    
        if isReady {
            handleCallEvent(callEvent, completionHandler: completionHandler)
        } else {
            bufferedEvents.append((callEvent, completionHandler))
        }
    }
    
    fileprivate func handleCallEvent(_ callEvent: CallEvent, completionHandler: @escaping () -> Void) {
        
        let result = avsWrapper.received(callEvent: callEvent)
        
        if let context = uiMOC, let error = result {
            WireCallCenterCallErrorNotification(context: context, error: error).post(in: context.notificationContext)
        }
        
        completionHandler()
    }

    /**
     * Handles a change in calling state.
     * - parameter conversationId: The ID of the conversation where the calling state has changed.
     * - parameter userId: The identifier of the user that caused the event.
     * - parameter messageTime: The timestamp of the event.
     */

    func handleCallState(callState: CallState, conversationId: UUID, userId: UUID?, messageTime: Date? = nil) {
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

}
