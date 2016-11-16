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

public enum CallClosedReason : Int32 {
    case normal
    case internalError
    case timeout
    case lostMedia
}

@objc(AVSCallState)
public enum CallState : Int32 {
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
    var callClosedReason : CallClosedReason?
    
    init(type: WireCallCenterNotificationType, conversationId: NSUUID, userId: NSUUID) {
        self.type = type
        self.conversationId = conversationId
        self.userId = userId
        
        super.init(name: WireCallCenterNotification.notificationName.rawValue, object: nil)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}

protocol WireCallCenterObserver {
    
    func establishedCall(conversationId: NSUUID, userId: NSUUID)
    func incomingCall(conversationId: NSUUID, userId: NSUUID)
    func closedCall(conversationId: NSUUID, userId: NSUUID, reason: CallClosedReason)
    
}

@objc public protocol WireCallCenterTransport: class {
    
    func send(data: Data, conversationId: NSUUID, userId: NSUUID)
    
}

@objc public class WireCallCenter : NSObject {
    
    public weak var transport : WireCallCenterTransport? = nil
    
    public init(userId: String, clientId: String) {
        
        super.init()
        
        let observer = Unmanaged.passUnretained(self).toOpaque()
        
        wcall_init(
            userId,
            clientId,
            { (version, context) in
                if let context = context {
                    _ = Unmanaged<WireCallCenter>.fromOpaque(context).takeRetainedValue()
                    
                    
                }
            },
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
            { (conversationId, userId, context) -> Void in
                if let context = context, let conversationId = conversationId, let userId = userId  {
                    let selfReference = Unmanaged<WireCallCenter>.fromOpaque(context).takeRetainedValue()
                    
                    selfReference.incoming(conversationId: String.init(cString: conversationId),
                                           userId: String.init(cString: userId))
                }
            },
            {(conversationId, userId, context) in
                if let context = context, let conversationId = conversationId, let userId = userId  {
                    let selfReference = Unmanaged<WireCallCenter>.fromOpaque(context).takeRetainedValue()
                    
                    selfReference.established(conversationId: String.init(cString: conversationId),
                                              userId: String.init(cString: userId))
                }
            },
            { (reason, conversationId, userId, metrics, context) in
                if let context = context, let conversationId = conversationId, let userId = userId  {
                    let selfReference = Unmanaged<WireCallCenter>.fromOpaque(context).takeRetainedValue()
                    
                    selfReference.closed(conversationId: String.init(cString: conversationId),
                                         userId: String.init(cString: userId),
                                         reason: CallClosedReason(rawValue: reason) ?? .internalError)
                }
            },
            observer)
        
    }
    
    private func send(conversationId: String, userId: String, clientId: String, data: UnsafePointer<UInt8>, dataLength: Int) -> Int32 {
        
        let bytes = UnsafeBufferPointer<UInt8>(start: data, count: dataLength)
        let data = Data(buffer: bytes)
        
        transport?.send(data: data, conversationId: NSUUID(uuidString: conversationId)!, userId: NSUUID(uuidString: userId)!)
        
        return 0
    }
    
    private func incoming(conversationId: String, userId: String) {
        let note = WireCallCenterNotification(type: .incoming, conversationId: NSUUID(uuidString: conversationId)!, userId: NSUUID(uuidString: userId)!)
        NotificationCenter.default.post(note as Notification)
    }
    
    private func established(conversationId: String, userId: String) {
        let note = WireCallCenterNotification(type: .established, conversationId: NSUUID(uuidString: conversationId)!, userId: NSUUID(uuidString: userId)!)
        NotificationCenter.default.post(note as Notification)
    }
    
    private func closed(conversationId: String, userId: String, reason: CallClosedReason) {
        let note = WireCallCenterNotification(type: .closed, conversationId: NSUUID(uuidString: conversationId)!, userId: NSUUID(uuidString: userId)!)
        
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
                    observer.establishedCall(conversationId: note.conversationId, userId: note.userId)
                case .incoming:
                    observer.incomingCall(conversationId: note.conversationId, userId: note.userId)
                case .closed:
                    observer.closedCall(conversationId: note.conversationId, userId: note.userId, reason: note.callClosedReason ?? .internalError)
                }
            }
        }
    }
    
    func removeObserver(observer: WireCallCenterObserver) {
        NotificationCenter.default.removeObserver(observer)
    }
    
    // MARK - Call state methods
    
    @objc(answerCallForConversationID:)
    public class func answerCall(conversationId: String) -> Bool {
        return wcall_answer(conversationId) == 0
    }
    
    @objc(startCallForConversationID:)
    public class func startCall(conversationId: String) -> Bool {
        return wcall_start(conversationId) == 0
    }
    
    @objc(closeCallForConversationID:)
    public class func closeCall(conversationId: String) {
        wcall_end(conversationId)
    }
    
    @objc(toogleVideoForConversationID:isActive:)
    public class func toogleVideo(conversationID: String, active: Bool) {
        wcall_set_video_send_active(conversationID, active ? 1 : 0)
    }
 
    @objc(callStateForConversationID:)
    public class func callState(conversationId: String) -> CallState {
        return CallState(rawValue: wcall_get_state(conversationId)) ?? .unknown
    }
}
