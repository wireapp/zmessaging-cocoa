//
// Wire
// Copyright (C) 2018 Wire Swiss GmbH
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
import avs

private let zmLog = ZMSLog(tag: "calling")

// MARK: Conversation Changes

extension WireCallCenterV3 : ZMConversationObserver {

    public func conversationDidChange(_ changeInfo: ConversationChangeInfo) {
        handleSecurityLevelChange(changeInfo)
        handleActiveParticipantsChange(changeInfo)
    }

    private func handleSecurityLevelChange(_ changeInfo: ConversationChangeInfo) {
        guard
            changeInfo.securityLevelChanged,
            let conversationId = changeInfo.conversation.remoteIdentifier,
            let previousSnapshot = callSnapshots[conversationId]
        else {
            return
        }

        if changeInfo.conversation.securityLevel == .secureWithIgnored, isActive(conversationId: conversationId) {
            // If an active call degrades we end it immediately
            return closeCall(conversationId: conversationId, reason: .securityDegraded)
        }

        let updatedCallState = previousSnapshot.callState.update(withSecurityLevel: changeInfo.conversation.securityLevel)

        if updatedCallState != previousSnapshot.callState {
            callSnapshots[conversationId] = previousSnapshot.update(with: updatedCallState)

            if let context = uiMOC, let callerId = initiatorForCall(conversationId: conversationId) {
                let notification = WireCallCenterCallStateNotification(context: context,
                                                                       callState: updatedCallState,
                                                                       conversationId: conversationId,
                                                                       callerId: callerId,
                                                                       messageTime: Date(),
                                                                       previousCallState: previousSnapshot.callState)
                notification.post(in: context.notificationContext)
            }
        }
    }

    private func handleActiveParticipantsChange(_ changeInfo: ConversationChangeInfo) {
        guard
            changeInfo.activeParticipantsChanged,
            let conversationId = changeInfo.conversation.remoteIdentifier,
            let completion = clientsRequestCompletionsByConversationId[conversationId]
        else {
            return
        }

        handleClientsRequest(conversationId: conversationId, completion: completion)
    }

}

// MARK: - AVS Callbacks

extension WireCallCenterV3 {

    private func handleEvent(_ description: String, _ handlerBlock: @escaping () -> Void) {
        zmLog.debug("Handle AVS event: \(description)")
        
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
    func handleIncomingCall(conversationId: UUID, messageTime: Date, client: AVSClient, isVideoCall: Bool, shouldRing: Bool, conversationType: AVSConversationType) {
        handleEvent("incoming-call") {
            let isDegraded = self.isDegraded(conversationId: conversationId)
            let callState = CallState.incoming(video: isVideoCall, shouldRing: shouldRing, degraded: isDegraded)
            let members = [AVSCallMember(client: client)]
            let isConferenceCall = conversationType == .conference

            self.createSnapshot(callState: callState, members: members, callStarter: client.userId, video: isVideoCall, for: conversationId, isConferenceCall: isConferenceCall)
            self.handle(callState: callState, conversationId: conversationId)
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
            let callState = CallState.answered(degraded: self.isDegraded(conversationId: conversationId))
            self.handle(callState: callState, conversationId: conversationId)
        }
    }

    /// Handles when data channel gets established.
    func handleDataChannelEstablishement(conversationId: UUID) {
        handleEvent("data-channel-established") {
            // Ignore if data channel was established after audio
            if self.callState(conversationId: conversationId) != .established {
                self.handle(callState: .establishedDataChannel, conversationId: conversationId)
            }
        }
    }

    /// Handles established calls.
    func handleEstablishedCall(conversationId: UUID) {
        handleEvent("established-call") {
            // WORKAROUND: the call established handler is called once for every participant in a
            // group call. Until that's no longer the case we must take care to only set establishedDate once.
            if self.callState(conversationId: conversationId) != .established {
                self.establishedDate = Date()
            }

            if self.videoState(conversationId: conversationId) == .started {
                self.avsWrapper.setVideoState(conversationId: conversationId, videoState: .started)
            }

            self.handle(callState: .established, conversationId: conversationId)
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
            self.handle(callState: .terminating(reason: reason), conversationId: conversationId, messageTime: messageTime)
        }
    }

    /// Handles call metrics.
    func handleCallMetrics(conversationId: UUID, metrics: String) {
        do {
            let metricsData = Data(metrics.utf8)
            let jsonObject = try JSONSerialization.jsonObject(with: metricsData, options: .mutableContainers)
            guard let attributes = jsonObject as? [String: NSObject] else { return }
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
                                           targets: AVSClientList?,
                                           data: Data) {

        handleEventInContext("send-call-message") { managedObjectContext in
            let selfUser = ZMUser.selfUser(in: managedObjectContext)

            guard
                selfUser.remoteIdentifier == senderUserId,
                selfUser.selfClient()?.remoteIdentifier == senderClientId
            else {
                zmLog.warn("Received request to send calling message from non self user and/or client")
                return
            }

            self.send(
                token: token,
                conversationId: conversationId,
                targets: targets,
                data: data,
                dataLength: data.count
            )
        }
    }

    /// Called when AVS is ready.
    func setCallReady(version: Int32) {
        zmLog.debug("wcall intialized with protocol version: \(version)")
        handleEvent("call-ready") {
            self.isReady = true
        }
    }
    
    func handleParticipantChange(conversationId: UUID, data: String) {
        handleEvent("participant-change") {
            guard let data = data.data(using: .utf8) else {
                zmLog.safePublic("Invalid participant change data")
                return
            }

            // Example of `data`
            //  {
            //      "convid": "df371578-65cf-4f07-9f49-c72a49877ae7",
            //      "members": [
            //          {
            //              "userid": "3f49da1d-0d52-4696-9ef3-0dd181383e8a",
            //              "clientid": "24cc758f602fb1f4",
            //              "aestab": 1,
            //              "vrecv": 0,
            //              "muted": 0 // 0 = false, 1 = true
            //          }
            //      ]
            //}

            do {
                let change = try JSONDecoder().decode(AVSParticipantsChange.self, from: data)
                let members = change.members.map(AVSCallMember.init)
                self.callParticipantsChanged(conversationId: change.convid, participants: members)
            } catch {
                zmLog.safePublic("Cannot decode participant change JSON")
            }
        }
    }

    /// Handles audio CBR mode enabling.
    func handleConstantBitRateChange(enabled: Bool) {
        handleEventInContext("cbr-change") {
            let firstEstablishedCall = self.callSnapshots.first {
                $0.value.callState == .established || $0.value.callState == .establishedDataChannel
            }

            if let establishedCall = firstEstablishedCall {
                self.callSnapshots[establishedCall.key] = establishedCall.value.updateConstantBitrate(enabled)
                WireCallCenterCBRNotification(enabled: enabled).post(in: $0.notificationContext)
            }
        }
    }

    /// Stopped when the media stream of a call was ended.
    func handleMediaStopped(conversationId: UUID) {
        handleEvent("media-stopped") {
            self.handle(callState: .mediaStopped, conversationId: conversationId)
        }
    }

    /// Handles network quality change
    func handleNetworkQualityChange(conversationId: UUID, client: AVSClient, quality: NetworkQuality) {
        handleEventInContext("network-quality-change") {
            self.callParticipantNetworkQualityChanged(conversationId: conversationId, client: client, quality: quality)

            if let call = self.callSnapshots[conversationId] {
                self.callSnapshots[conversationId] = call.updateNetworkQuality(quality)
                let notification = WireCallCenterNetworkQualityNotification(conversationId: conversationId,
                                                                            userId: client.userId,
                                                                            clientId: client.clientId,
                                                                            networkQuality: quality)
                notification.post(in: $0.notificationContext)
            }
        }
    }
    
    func handleMuteChange(muted: Bool) {
        handleEventInContext("mute-change") {
            WireCallCenterMutedNotification(muted: muted).post(in: $0.notificationContext)
        }
    }

    func handleClientsRequest(conversationId: UUID, completion: @escaping (_ clients: String) -> Void) {
        handleEventInContext("request-clients") { context in
            self.transport?.requestClientsList(conversationId: conversationId) { clients in

                guard let json = AVSClientList(clients: clients).json else {
                    zmLog.error("Could not encode client list to JSON")
                    return
                }

                completion(json)
            }
        }
    }

    func handleSFTCallMessageRequest(token: WireCallMessageToken, url: String, data: Data) {
        handleEvent("send-sft-call-message") {
            self.sendSFT(token: token, url: url, data: data)
        }
    }
    
    func handleActiveSpeakersChange(conversationId: UUID, data: String) {
        handleEventInContext("active-speakers-change") {
            guard let data = data.data(using: .utf8) else {
                zmLog.safePublic("Invalid active speakers data")
                return
            }
            
            // Example of `data`
            //  {
            //      "audio_levels": [
            //          {
            //              "userid": "3f49da1d-0d52-4696-9ef3-0dd181383e8a",
            //              "clientid": "24cc758f602fb1f4",
            //              "audio_level": 100,
            //              "audio_level_now": 100
            //          }
            //      ]
            //}
            
            do {
                let change = try JSONDecoder().decode(AVSActiveSpeakersChange.self, from: data)
                if let call = self.callSnapshots[conversationId] {
                    self.callSnapshots[conversationId] = call.updateActiveSpeakers(change.activeSpeakers)
                    WireCallCenterActiveSpeakersNotification().post(in: $0.notificationContext)
                }
            }
            catch {
                zmLog.safePublic("Cannot decode active speakers change JSON")
            }
        }
    }
}

private extension Set where Element == ZMUser {

    var avsClients: Set<AVSClient> {
        return reduce(Set<AVSClient>()) { result, user in
            return result.union(user.clients.compactMap(AVSClient.init))
        }
    }
}

