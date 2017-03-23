//
// Wire
// Copyright (C) 2017 Wire Swiss GmbH
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


private let log = ZMSLog(tag: "Calling System Message")


@objc public final class SystemMessageCallObserver: NSObject, VoiceChannelStateObserver {

    var token: NSObjectProtocol?
    var callerByConversation = [ZMConversation: ZMUser]()
    var startDateByConversation = [ZMConversation: Date]()
    var connectDateByConversation = [ZMConversation: Date]()

    public init(userSession: ZMUserSession) {
        super.init()
        token = VoiceChannelRouter.addStateObserver(self, userSession: userSession)
    }

    public func callCenterDidChange(voiceChannelState: VoiceChannelV2State, conversation: ZMConversation, callingProtocol: CallingProtocol) {
        switch voiceChannelState {
        case .outgoingCall, .outgoingCallDegraded:
            log.info("Setting call start date for \(conversation.displayName)")
            startDateByConversation[conversation] = Date()
            fallthrough
        case .incomingCall, .incomingCallDegraded:
            let caller = conversation.callingUser()
            log.info("Adding \(caller?.displayName ?? "") as caller in \"\(conversation.displayName)\"")
            callerByConversation[conversation] = conversation.callingUser()
        case .selfConnectedToActiveChannel:
            if nil == callerByConversation[conversation] { log.info("No caller present when setting call start date") }
            log.info("Setting call connect date for \(conversation.displayName)")
            connectDateByConversation[conversation] = Date()
        default: break
        }
    }

    public func callCenterDidEndCall(reason: VoiceChannelV2CallEndReason, conversation: ZMConversation, callingProtocol: CallingProtocol) {
        if let caller = callerByConversation[conversation], let connectDate = connectDateByConversation[conversation] {
            let duration = -connectDate.timeIntervalSinceNow
            log.info("Appending performed call message: \(duration), \(caller.displayName), \"\(conversation.displayName)\"")
            conversation.appendPerformedCallMessage(with: duration, caller: caller)
        }
        else if let caller = callerByConversation[conversation], let startDate = startDateByConversation[conversation] {
            log.info("Appending performed call message: \(startDate), \(caller.displayName), \"\(conversation.displayName)\"")
            conversation.appendPerformedCallMessage(with: 0, caller: caller)
        } else {
            log.info("Call ended but no call info present in order to insert system message")
        }

        callerByConversation[conversation] = nil
        startDateByConversation[conversation] = nil
        connectDateByConversation[conversation] = nil
    }

    public func callCenterDidFailToJoinVoiceChannel(error: Error?, conversation: ZMConversation) {
        // no-op
    }

}


private extension ZMConversation {

    func callingUser() -> ZMUser? {
        guard let selfUser = managedObjectContext.map(ZMUser.selfUser) else { return nil }
        guard let voiceChannel = voiceChannel else { return nil }

        switch voiceChannel.state {
        case .outgoingCall, .outgoingCallDegraded, .outgoingCallInactive:
            return selfUser
        case .incomingCall, .incomingCallDegraded, .incomingCallInactive:
            return outgoingCallingUser(selfUser)
        default: return nil
        }
    }

    private func outgoingCallingUser(_ selfUser: ZMUser) -> ZMUser? {
        return voiceChannel?.participants.flatMap {
            $0 as? ZMUser
        }.first {
            $0 != selfUser
        }
    }

}
