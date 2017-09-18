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
import WireDataModel

// MARK: - Observer
@objc public protocol PreLoginAuthenticationObserver: NSObjectProtocol {
    
    /// Invoked when requesting a login code for the phone failed
    @objc optional func loginCodeRequestDidFail(_ error: NSError)
    
    /// Invoked when requesting a login code succeded
    @objc optional func loginCodeRequestDidSucceed()
    
    /// Invoked when the authentication failed, or when the cookie was revoked
    @objc optional func authenticationDidFail(_ error: NSError)
    
    /// Invoked when the authentication succeeded and the user now has a valid
    @objc optional func authenticationDidSucceed()

}

private enum PreLoginAuthenticationEvent {
    
    case authenticationDidFail(error: NSError, credentials: [String:String]?)
    case authenticationDidSuceeded
    case loginCodeRequestDidFail(NSError)
    case loginCodeRequestDidSucceed
}

struct PreLoginAuthenticationNotification {
    
    fileprivate static let authenticationEventNotification = Notification.Name(rawValue: "ZMAuthenticationEventNotification")
    
    private static let authenticationEventKey = "authenticationEvent"
    private static let credentialsEventKey = "credentials"
    
    static func notify(of event: PreLoginAuthenticationEvent, context: ZMAuthenticationStatus, user: ZMUSer? = nil) {
        let userInfo: [String: Any] = [
            self.authenticationEventKey: event,
            self.credentialsEventKey: user.flatMap { $0.credentialsUserInfo }
            ]
        NotificationInContext(name: self.authenticationEventNotification,
                              context: context,
                              userInfo: userInfo).post()
    }
    
    public static func register(_ observer: PreLoginAuthenticationObserver, context: ZMAuthenticationStatus, queue: GenericAsyncQueue) -> Any {
        return NotificationInContext.addObserver(name: self.authenticationEventNotification,
                                                 context: context)
        {
            [weak observer] note in
            guard let event = note.userInfo[self.authenticationEventKey] as? PreLoginAuthenticationEvent,
                let observer = observer else { return }
            let userCredentials = note.userInfo[self.credentialsEventKey]
            
            queue.performAsync {
                switch event {
                case .loginCodeRequestDidFail(let error):
                    observer?.loginCodeRequestDidFail?(error)
                case .loginCodeRequestDidSucceed:
                    observer?.loginCodeRequestDidSucceed?()
                case .authenticationDidFail(let error):
                    observer?.authenticationDidFail?(error)
                case .authenticationDidSuceeded:
                    observer?.authenticationDidSucceed?()
                }
            }
        }
    }
}

// Obj-c friendly methods
extension ZMAuthenticationStatus {
    
    @objc public func notifyAuthenticationDidFail(error: NSError) { // both
        AuthenticationNotification.notify(of: .authenticationDidFail(error), context: self)
    }
    
    @objc public func notifyAuthenticationDidSucceed() { // unauthenticated
        AuthenticationNotification.notify(of: .authenticationDidSucceed, context: self)
    }
    
    @objc public func notifyLoginCodeRequestDidFail(error: NSError) { // unauthenticated
        AuthenticationNotification.notify(of: .loginCodeRequestDidFail(error), context: self)
    }
    
    @objc public func notifyLoginCodeRequestDidSucceed(error: NSError) { // unauthenticated
        AuthenticationNotification.notify(of: .loginCodeRequestDidSuceed, context: self)
    }
}


extension ZMUser {
    
    /// This will be used to set user info on the NSError
    @objc
    public var credentialsUserInfo : Dictionary<String, String> {
        
        var userInfo : [String : String] = [:]
        
        if let emailAddress = emailAddress, !emailAddress.isEmpty {
            userInfo[ZMEmailCredentialKey] = emailAddress
        }
        
        if let phoneNumber = phoneNumber, !phoneNumber.isEmpty {
            userInfo[ZMPhoneCredentialKey] = phoneNumber
        }
        
        return userInfo
    }
    
}
