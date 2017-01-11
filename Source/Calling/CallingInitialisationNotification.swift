//
// Wire
// Copyright (C) 2016 Wire Swiss GmbH
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

let VoiceChannelV2VideoCallErrorDomain = "VoiceChannelV2VideoCallErrorDomain"

@objc
public enum VoiceChannelV2ErrorCode : UInt {
    case ongoingGSMCall
    case switchToAudioNotAllowed
    case switchToVideoNotAllowed
    case noFlowManager
    case noMedia
    case videoCallingNotSupported
    case videoNotActive
}


private class CallingInitialisationObserverTokenImpl : CallingInitialisationObserverToken {
    var observerToken : AnyObject
    init(observerToken: AnyObject) {
        self.observerToken = observerToken
    }
}

open class VoiceChannelV2Error: NSError {
    
    init(errorCode: VoiceChannelV2ErrorCode) {
        super.init(domain: VoiceChannelV2VideoCallErrorDomain, code: Int(errorCode.rawValue), userInfo: VoiceChannelV2Error.userInfoForErrorCode(errorCode))
    }
    
    static func userInfoForErrorCode(_ errorCode: VoiceChannelV2ErrorCode) -> [String: String] {
        switch errorCode {
        case .ongoingGSMCall:
            return [NSLocalizedDescriptionKey: "Cannot get flow manager"]
        case .switchToAudioNotAllowed:
            return [NSLocalizedDescriptionKey: "Swtich to audio is not allowed"]
        case .switchToVideoNotAllowed:
            return [NSLocalizedDescriptionKey: "Switch to video is not allowed"]
        case .noFlowManager:
            return [NSLocalizedDescriptionKey: "Cannot get flow manager"]
        case .noMedia:
            return [NSLocalizedDescriptionKey: "Too early: media is not established yet"]
        case .videoCallingNotSupported:
            return [NSLocalizedDescriptionKey: "Video cannot be sent to this conversation"]
        case .videoNotActive:
            return [NSLocalizedDescriptionKey: "Video is not currently active"]
        }
    }
    
    required public init?(coder aDecoder: NSCoder) {
        fatal("init(coder:) has not been implemented")
    }
    
    open static func noFlowManagerError() -> VoiceChannelV2Error {
        return VoiceChannelV2Error(errorCode: VoiceChannelV2ErrorCode.noFlowManager)
    }
    
    open static func noMediaError() -> VoiceChannelV2Error {
        return VoiceChannelV2Error(errorCode: VoiceChannelV2ErrorCode.noMedia)
    }
    
    open static func videoCallNotSupportedError() -> VoiceChannelV2Error {
        return VoiceChannelV2Error(errorCode: VoiceChannelV2ErrorCode.videoCallingNotSupported)
    }
    
    open static func switchToVideoNotAllowedError() -> VoiceChannelV2Error {
        return VoiceChannelV2Error(errorCode: VoiceChannelV2ErrorCode.switchToVideoNotAllowed)
    }
    
    open static func switchToAudioNotAllowedError() -> VoiceChannelV2Error {
        return VoiceChannelV2Error(errorCode: VoiceChannelV2ErrorCode.switchToAudioNotAllowed)
    }
    
    open static func ongoingGSMCallError() -> VoiceChannelV2Error {
        return VoiceChannelV2Error(errorCode: VoiceChannelV2ErrorCode.ongoingGSMCall)
    }
    
    open static func videoNotActiveError() -> VoiceChannelV2Error {
        return VoiceChannelV2Error(errorCode: VoiceChannelV2ErrorCode.videoNotActive)
    }
}




public class CallingInitialisationNotification : NSObject  {
    
    public let error : NSError
    internal let errorCode : VoiceChannelV2ErrorCode
    
    public static let Name = "CallingInitialisationNotification"
    
    init(error: NSError, errorCode: VoiceChannelV2ErrorCode) {
        self.error = error
        self.errorCode = errorCode
    }
    
    public static func notifyCallingFailedWithErrorCode(_ errorCode: VoiceChannelV2ErrorCode) {
        let note = CallingInitialisationNotification(error: VoiceChannelV2Error(errorCode: errorCode), errorCode:errorCode)
        NotificationCenter.default.post(name: Notification.Name(rawValue: self.Name), object:note)
    }
    
    @objc public static func addObserverWithBlock(_ block: @escaping (CallingInitialisationNotification) -> Void) -> CallingInitialisationObserverToken {
        let internalToken = NotificationCenter.default.addObserver(forName: Notification.Name(rawValue: self.Name), object: nil, queue: OperationQueue.current) { (note: Notification) in
            if let object = note.object as? CallingInitialisationNotification {
                block(object)
            }
        }
        
        return (CallingInitialisationObserverTokenImpl(observerToken: internalToken)) as CallingInitialisationObserverToken
    }
    
    public static func removeObserver(_ observer: CallingInitialisationObserverToken) {
        let internalObserver = observer as! CallingInitialisationObserverTokenImpl
        NotificationCenter.default.removeObserver(internalObserver.observerToken, name: NSNotification.Name(rawValue: self.Name), object: nil)
    }
    

}
