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
import WireCall

enum CallClosedReason : Int32 {
    case normal
    case internalError
    case timeout
    case lostMedia
}

enum CallState : Int32 {
    /// There's no call
    case none
    /// Outgoing call is pending
    case outgoing
    /// Incoming call is pending
    case incoming
    /// Established call
    case established
    /// Call in process of being terminated
    case terminating
    /// Unknown call state
    case unknown
}

typealias CallToken = OpaquePointer

enum WireCallCenterNotificationType {
    case incoming
    case established
    case closed
}

class WireCallCenterNotification : ZMNotification {
    
    static let notificationName = Notification.Name("WireCallCenterNotification")
    
    let type : WireCallCenterNotificationType
    let conversationId : NSUUID
    let userId : NSUUID
    let token : CallToken
    var callClosedReason : CallClosedReason?
    
    init(type: WireCallCenterNotificationType, token: CallToken, conversationId: NSUUID, userId: NSUUID) {
        self.type = type
        self.token = token
        self.conversationId = conversationId
        self.userId = userId
        
        super.init(name: WireCallCenterNotification.notificationName.rawValue, object: nil)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}

protocol WireCallCenterObserver {
    
    func establishedCall(token: CallToken, conversationId: NSUUID, userId: NSUUID)
    func incomingCall(token: CallToken, conversationId: NSUUID, userId: NSUUID)
    func closedCall(token: CallToken, conversationId: NSUUID, userId: NSUUID, reason: CallClosedReason)
    
}

protocol WireCallCenterTransport {
    
    func send(data: Data, conversation: NSUUID, userId: NSUUID)
    
    
    
}

class WireCallCenter {
    
    var transport : WireCallCenterTransport?
    
    init(userId: String, clientId: String) {
        
        let observer = Unmanaged.passUnretained(self).toOpaque()
        
        wcall_init(userId,
                   clientId,
                   { (conversationId, userId, clientId, data, dataLength, context) in
                    if let context = context, let conversationId = conversationId, let userId = userId, let clientId = clientId, let data = data {
                        let selfReference = Unmanaged<WireCallCenter>.fromOpaque(context).takeRetainedValue()
                        
                        return selfReference.send(conversationId: String.init(cString: conversationId),
                                                  userId: String.init(cString: userId),
                                                  clientId: String.init(cString: clientId),
                                                  data: data,
                                                  dataLength: dataLength)
                    }
                    
                    return 0
                    },
                   { (conversationId, userId, callToken, context) in
                    if let context = context, let conversationId = conversationId, let userId = userId  {
                        let selfReference = Unmanaged<WireCallCenter>.fromOpaque(context).takeRetainedValue()
                        
                        selfReference.incoming(conversationId: String.init(cString: conversationId),
                                               userId: String.init(cString: userId),
                                               callToken: callToken)
                    }
                    },
                   { (conversationId, userId, callToken, context) in
                    if let context = context, let conversationId = conversationId, let userId = userId  {
                        let selfReference = Unmanaged<WireCallCenter>.fromOpaque(context).takeRetainedValue()
                        
                        selfReference.established(conversationId: String.init(cString: conversationId),
                                                  userId: String.init(cString: userId),
                                                  callToken: callToken)
                    }
                    },
                   { (reason, conversationId, userId, callToken, context) in
                    if let context = context, let conversationId = conversationId, let userId = userId  {
                        let selfReference = Unmanaged<WireCallCenter>.fromOpaque(context).takeRetainedValue()
                        
                        selfReference.closed(conversationId: String.init(cString: conversationId),
                                             userId: String.init(cString: userId),
                                             callToken: callToken,
                                             reason: CallClosedReason(rawValue: reason) ?? .internalError)
                    }
                    },
                   observer)
        
    }
    
    private func send(conversationId: String, userId: String, clientId: String, data: UnsafePointer<UInt8>, dataLength: Int) -> Int32 {
        
        let bytes = UnsafeBufferPointer<UInt8>(start: data, count: dataLength)
        let data = Data(buffer: bytes)
        
        transport?.send(data: data, conversation: NSUUID(uuidString: conversationId)!, userId: NSUUID(uuidString: userId)!)
        
        return 0
    }
    
    private func incoming(conversationId: String, userId: String, callToken: CallToken?) {
        let note = WireCallCenterNotification(type: .incoming, token: callToken!, conversationId: NSUUID(uuidString: conversationId)!, userId: NSUUID(uuidString: userId)!)
        NotificationCenter.default.post(note as Notification)
    }
    
    private func established(conversationId: String, userId: String, callToken: CallToken?) {
        let note = WireCallCenterNotification(type: .established, token: callToken!, conversationId: NSUUID(uuidString: conversationId)!, userId: NSUUID(uuidString: userId)!)
        NotificationCenter.default.post(note as Notification)
    }
    
    private func closed(conversationId: String, userId: String, callToken: CallToken?, reason: CallClosedReason) {
        let note = WireCallCenterNotification(type: .closed, token: callToken!, conversationId: NSUUID(uuidString: conversationId)!, userId: NSUUID(uuidString: userId)!)
        note.callClosedReason = reason
        NotificationCenter.default.post(note as Notification)
    }
    
    // TODO find a better place for this method
    func received(data: Data, currentTimestamp: Date, serverTimestamp: Date, conversationId: NSUUID, userId: NSUUID, clientId: NSUUID) {
        data.withUnsafeBytes { (bytes: UnsafePointer<UInt8>) in
            let currentTime = UInt32(currentTimestamp.timeIntervalSince1970)
            let serverTime = UInt32(serverTimestamp.timeIntervalSince1970)
            
            wcall_recv_msg(bytes, data.count, currentTime, serverTime, conversationId.transportString(), userId.transportString(), clientId.transportString())
        }
    }
    
    // MARK - observer
    
    func addObserver(observer: WireCallCenterObserver) {
        NotificationCenter.default.addObserver(forName: WireCallCenterNotification.notificationName, object: observer, queue: nil) { (note) in
            if let note = (note as NSNotification) as? WireCallCenterNotification {
                switch (note.type) {
                case .established:
                    observer.establishedCall(token: note.token, conversationId: note.conversationId, userId: note.userId)
                case .incoming:
                    observer.incomingCall(token: note.token, conversationId: note.conversationId, userId: note.userId)
                case .closed:
                    observer.closedCall(token: note.token, conversationId: note.conversationId, userId: note.userId, reason: note.callClosedReason ?? .internalError)
                }
            }
        }
    }
    
    func removeObserver(observer: WireCallCenterObserver) {
        NotificationCenter.default.removeObserver(observer)
    }
    
    // MARK - Call state methods
    
    class func answerCall(conversationId: String) {
        wcall_answer(conversationId)
    }
    
    class func startCall(conversationId: String) -> CallToken? {
        return wcall_start(conversationId)
    }
    
    class func closeCall(conversationId: String) {
        wcall_end_inconv(conversationId)
    }
    
    class func closeCall(token: CallToken) {
        wcall_end(token)
    }
    
    class func callState(conversationId: String) -> CallState {
        return CallState(rawValue: wcall_get_state_inconv(conversationId)) ?? .unknown
    }
    
    class func callState(token: CallToken) -> CallState {
        return CallState(rawValue: wcall_get_state(token)) ?? .unknown
    }
}
