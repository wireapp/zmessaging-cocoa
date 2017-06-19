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

/// Inserts a calling system message for V3 calls
final class CallSystemMessageGenerator: NSObject {
    
    var callerByConversation = [ZMConversation: ZMUser]()
    var startDateByConversation = [ZMConversation: Date]()
    var connectDateByConversation = [ZMConversation: Date]()

    public func appendSystemMessageIfNeeded(callState: CallState, conversation: ZMConversation, user: ZMUser?, timeStamp: Date?) -> ZMSystemMessage?{
        var systemMessage : ZMSystemMessage? = nil

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
            systemMessage = appendCallEndedSystemMessage(reason: reason, conversation: conversation, timeStamp: timeStamp)
        case .none, .unknown, .answered:
            break
        }
        return systemMessage
    }

    private func appendCallEndedSystemMessage(reason: CallClosedReason, conversation: ZMConversation, timeStamp: Date?) -> ZMSystemMessage? {
        
        var systemMessage : ZMSystemMessage? = nil
        if let caller = callerByConversation[conversation], let connectDate = connectDateByConversation[conversation] {
            let duration = -connectDate.timeIntervalSinceNow
            log.info("Appending performed call message: \(duration), \(caller.displayName), \"\(conversation.displayName)\"")
            systemMessage =  conversation.appendPerformedCallMessage(with: duration, caller: caller)
        }
        else if let caller = callerByConversation[conversation] {
            if let startDate = startDateByConversation[conversation] {
                log.info("Appending performed call message: \(startDate), \(caller.displayName), \"\(conversation.displayName)\"")
                systemMessage =  conversation.appendPerformedCallMessage(with: 0, caller: caller)
            } else {
                log.info("Appending missed call message: \(caller.displayName), \"\(conversation.displayName)\"")
                systemMessage = conversation.appendMissedCallMessage(fromUser: caller, at: timeStamp ?? Date())
            }
        } else {
            log.info("Call ended but no call info present in order to insert system message")
        }
        
        callerByConversation[conversation] = nil
        startDateByConversation[conversation] = nil
        connectDateByConversation[conversation] = nil
        return systemMessage
    }
    
}
