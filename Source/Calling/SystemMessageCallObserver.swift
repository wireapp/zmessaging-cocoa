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


/// Inserts system messages for calls with Version2
/// Registers as an observer to the callState and updates it's internal state when the callState changes
/// Remove when retiring V2 Calling
@objc public final class SystemMessageCallObserverV2: NSObject, VoiceChannelStateObserver {

    var token: NSObjectProtocol?
    var callerByConversation = [ZMConversation: ZMUser]()
    var startDateByConversation = [ZMConversation: Date]()
    var connectDateByConversation = [ZMConversation: Date]()

    public convenience init(userSession: ZMUserSession) {
        self.init(managedObjectContext: userSession.managedObjectContext!)
    }
    
    internal init(managedObjectContext: NSManagedObjectContext) {
        super.init()
        token =  WireCallCenter.addVoiceChannelStateObserver(observer: self, context: managedObjectContext)
    }

    public func callCenterDidChange(voiceChannelState: VoiceChannelV2State, conversation: ZMConversation, callingProtocol: CallingProtocol) {
        guard callingProtocol == .version2 else { return }
        
        switch voiceChannelState {
        case .outgoingCall, .outgoingCallDegraded:
            log.info("Setting call start date for \(conversation.displayName)")
            startDateByConversation[conversation] = Date()
            fallthrough
        case .incomingCall, .incomingCallDegraded, .incomingCallInactive:
            let caller = conversation.callingUser(voiceChannelState: voiceChannelState)
            log.info("Adding \(caller?.displayName ?? "") as caller in \"\(conversation.displayName)\"")
            callerByConversation[conversation] = caller
        case .selfConnectedToActiveChannel:
            if nil == callerByConversation[conversation] { log.info("No caller present when setting call start date") }
            log.info("Setting call connect date for \(conversation.displayName)")
            connectDateByConversation[conversation] = Date()
        default: break
        }
    }

    public func callCenterDidEndCall(reason: VoiceChannelV2CallEndReason, conversation: ZMConversation, callingProtocol: CallingProtocol) {
        guard callingProtocol == .version2 else { return }

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


/// Inserts a calling system message for V3 calls
final class CallSystemMessageGenerator: NSObject {
    
    var callerByConversation = [ZMConversation: ZMUser]()
    var startDateByConversation = [ZMConversation: Date]()
    var connectDateByConversation = [ZMConversation: Date]()

    public func callCenterDidChange(callState: CallState, conversation: ZMConversation, user: ZMUser?, timeStamp: Date?) {
        switch callState {
        case .outgoing:
            log.info("Setting call start date for \(conversation.displayName)")
            startDateByConversation[conversation] = Date()
            fallthrough
        case .incoming:
            log.info("Adding \(user?.displayName ?? "") as caller in \"\(conversation.displayName)\"")
            callerByConversation[conversation] = user
        case .established:
            if nil == callerByConversation[conversation] { log.info("No caller present when setting call start date") }
            log.info("Setting call connect date for \(conversation.displayName)")
            connectDateByConversation[conversation] = Date()
        case .terminating(reason: let reason):
            callCenterDidEndCall(reason: reason, conversation: conversation, timeStamp: timeStamp)
        case .none, .unknown, .answered:
            break
        }
    }

    private func callCenterDidEndCall(reason: CallClosedReason, conversation: ZMConversation, timeStamp: Date?) {
        if let caller = callerByConversation[conversation], let connectDate = connectDateByConversation[conversation] {
            let duration = -connectDate.timeIntervalSinceNow
            log.info("Appending performed call message: \(duration), \(caller.displayName), \"\(conversation.displayName)\"")
            conversation.appendPerformedCallMessage(with: duration, caller: caller)
        }
        else if let caller = callerByConversation[conversation] {
            if let startDate = startDateByConversation[conversation] {
                log.info("Appending performed call message: \(startDate), \(caller.displayName), \"\(conversation.displayName)\"")
                conversation.appendPerformedCallMessage(with: 0, caller: caller)
            } else {
                log.info("Appending missed call message: \(caller.displayName), \"\(conversation.displayName)\"")
                conversation.appendMissedCallMessage(fromUser: caller, at: timeStamp ?? Date())
            }
        } else {
            log.info("Call ended but no call info present in order to insert system message")
        }
        
        callerByConversation[conversation] = nil
        startDateByConversation[conversation] = nil
        connectDateByConversation[conversation] = nil
    }
    
}



private extension ZMConversation {

    /// Remove when retiring version V2
    func callingUser(voiceChannelState: VoiceChannelV2State) -> ZMUser? {
        guard let selfUser = managedObjectContext.map(ZMUser.selfUser) else { return nil }
        
        switch voiceChannelState {
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
