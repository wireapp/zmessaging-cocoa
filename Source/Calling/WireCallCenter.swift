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

struct WireCallCenterNotification {
    
    static let notificationName = Notification.Name("WireCallCenterNotification")
    static let userInfoKey = notificationName.rawValue
    
    let callState : CallState
    let conversationId : UUID
    let userId : UUID
    var callClosedReason : CallClosedReason?
    
    init(callState: CallState, conversationId: UUID, userId: UUID, callClosedReason: CallClosedReason? = nil) {
        self.callState = callState
        self.conversationId = conversationId
        self.userId = userId
        self.callClosedReason = callClosedReason
    }
    
    func post() {
        NotificationCenter.default.post(name: WireCallCenterNotification.notificationName, object: nil, userInfo: [WireCallCenterNotification.userInfoKey : self])
    }
}

public typealias WireCallCenterObserverToken = NSObjectProtocol

public protocol WireCallCenterObserver {
    
    func callCenterDidChange(callState: CallState, conversationId: UUID, userId: UUID, callCloseReason: CallClosedReason?)
}

@objc public protocol WireCallCenterTransport: class {
    
    func send(data: Data, conversationId: NSUUID, userId: NSUUID, completionHandler:((_ status: Int) -> Void))
    
}

public typealias MessageToken = UnsafeMutableRawPointer

@objc public class WireCallCenter : NSObject {
    
    public var transport : WireCallCenterTransport? = nil
    
    public init(userId: String, clientId: String) {
        
        super.init()
        
        let observer = Unmanaged.passUnretained(self).toOpaque()
        
        let resultValue = wcall_init(
            (userId as NSString).utf8String,
            (clientId as NSString).utf8String,
            { (version, context) in
                if let context = context {
                    _ = Unmanaged<WireCallCenter>.fromOpaque(context).takeUnretainedValue()
                    
                    
                }
            },
            { (token, conversationId, userId, clientId, data, dataLength, context) in
                print("JCVDay: sending")
                if let token = token, let context = context, let conversationId = conversationId, let userId = userId, let clientId = clientId, let data = data {
                    let selfReference = Unmanaged<WireCallCenter>.fromOpaque(context).takeUnretainedValue()
                    
                    return selfReference.send(token: token,
                        conversationId: String.init(cString: conversationId),
                                              userId: String.init(cString: userId),
                                              clientId: String.init(cString: clientId),
                                              data: data,
                                              dataLength: dataLength)
                }
                
                return -1
            },
            { (conversationId, userId, context) -> Void in
                print("JCVDay: incoming")
                if let context = context, let conversationId = conversationId, let userId = userId  {
                    let selfReference = Unmanaged<WireCallCenter>.fromOpaque(context).takeUnretainedValue()
                    
                    selfReference.incoming(conversationId: String.init(cString: conversationId),
                                           userId: String.init(cString: userId))
                }
            },
            {(conversationId, userId, context) in
                print("JCVDay: establishing")
                if let context = context, let conversationId = conversationId, let userId = userId  {
                    let selfReference = Unmanaged<WireCallCenter>.fromOpaque(context).takeUnretainedValue()
                    
                    selfReference.established(conversationId: String.init(cString: conversationId),
                                              userId: String.init(cString: userId))
                }
            },
            { (reason, conversationId, userId, metrics, context) in
                print("JCVDay: closing")
                if let context = context, let conversationId = conversationId, let userId = userId  {
                    let selfReference = Unmanaged<WireCallCenter>.fromOpaque(context).takeUnretainedValue()
                    
                    selfReference.closed(conversationId: String.init(cString: conversationId),
                                         userId: String.init(cString: userId),
                                         reason: CallClosedReason(rawValue: reason) ?? .internalError)
                }
            },
            observer)
        
        if resultValue != 0 {
            fatal("Failed to initialise calling v3")
        }
        
    }
    
    private func send(token: MessageToken, conversationId: String, userId: String, clientId: String, data: UnsafePointer<UInt8>, dataLength: Int) -> Int32 {
        
        let bytes = UnsafeBufferPointer<UInt8>(start: data, count: dataLength)
        let transformedData = Data(buffer: bytes)
        
        transport?.send(data: transformedData, conversationId: NSUUID(uuidString: conversationId)!, userId: NSUUID(uuidString: userId)!, completionHandler: { status in
            wcall_resp(Int32(status), "", token)
        })
        
        return 0
    }
    
    private func incoming(conversationId: String, userId: String) {
        
        // JACOB
        if (wcall_answer(conversationId) != 0) {
            fatal("peux pas repooooooondre")
        }
        return
        
        WireCallCenterNotification(callState: .incoming, conversationId: UUID(uuidString: conversationId)!, userId: UUID(uuidString: userId)!).post()
    }
    
    private func established(conversationId: String, userId: String) {
        WireCallCenterNotification(callState: .established, conversationId: UUID(uuidString: conversationId)!, userId: UUID(uuidString: userId)!).post()
    }
    
    private func closed(conversationId: String, userId: String, reason: CallClosedReason) {
        WireCallCenterNotification(callState: .terminating, conversationId: UUID(uuidString: conversationId)!, userId: UUID(uuidString: userId)!, callClosedReason: reason).post()
    }
    
    // TODO find a better place for this method
    public func received(data: Data, currentTimestamp: Date, serverTimestamp: Date, conversationId: UUID, userId: UUID, clientId: String) {
        data.withUnsafeBytes { (bytes: UnsafePointer<UInt8>) in
            let currentTime = UInt32(currentTimestamp.timeIntervalSince1970)
            let serverTime = UInt32(serverTimestamp.timeIntervalSince1970)
            
            wcall_recv_msg(bytes, data.count, currentTime, serverTime, conversationId.transportString(), userId.transportString(), clientId)
        }
    }
    
    // MARK - observer
    
    public class func addObserver(observer: WireCallCenterObserver) -> WireCallCenterObserverToken  {
        return NotificationCenter.default.addObserver(forName: WireCallCenterNotification.notificationName, object: nil, queue: nil) { (note) in
            if let note = note.userInfo?[WireCallCenterNotification.userInfoKey] as? WireCallCenterNotification {
                observer.callCenterDidChange(callState: note.callState, conversationId: note.conversationId, userId: note.userId, callCloseReason: note.callClosedReason)
            }
        }
    }
    
    public class func removeObserver(token: WireCallCenterObserverToken) {
        NotificationCenter.default.removeObserver(token)
    }
    
    // MARK - Call state methods
    
    @objc(answerCallForConversationID:)
    public class func answerCall(conversationId: UUID) -> Bool {
        return wcall_answer(conversationId.transportString()) == 0
    }
    
    @objc(startCallForConversationID:)
    public class func startCall(conversationId: UUID) -> Bool {
        return wcall_start(conversationId.transportString()) == 0
    }
    
    @objc(closeCallForConversationID:)
    public class func closeCall(conversationId: UUID) {
        wcall_end(conversationId.transportString())
    }
    
    @objc(toogleVideoForConversationID:isActive:)
    public class func toogleVideo(conversationID: UUID, active: Bool) {
        wcall_set_video_send_active(conversationID.transportString(), active ? 1 : 0)
    }
 
    @objc(callStateForConversationID:)
    public class func callState(conversationId: UUID) -> CallState {
        return CallState(rawValue: wcall_get_state(conversationId.transportString())) ?? .unknown
    }
}
