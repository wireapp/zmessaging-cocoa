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

extension ZMAuthenticationStatus : NotificationContext { } // Mark ZMAuthenticationStatus as valid notification context

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

    /// Invoked when we have provided correct credentials and have an opportunity to import backup
    @objc optional func authenticationReadyToImportBackup(existingAccount: Bool)

    /// A company login code did become availble. This means that the user clicked an SSO link with a valid code.
    @objc optional func companyLoginCodeDidBecomeAvailable(_ code: UUID)
}

private enum PreLoginAuthenticationEvent {
    
    case authenticationDidFail(error: NSError)
    case authenticationReadyToImportBackup(existingAccount: Bool)
    case authenticationDidSucceed
    case loginCodeRequestDidFail(NSError)
    case loginCodeRequestDidSucceed
    case companyLoginCodeDidBecomeAvailable(UUID)
}

@objc public class PreLoginAuthenticationNotification : NSObject {
    
    fileprivate static let authenticationEventNotification = Notification.Name(rawValue: "ZMAuthenticationEventNotification")
    
    private static let authenticationEventKey = "authenticationEvent"
    
    fileprivate static func notify(of event: PreLoginAuthenticationEvent, context: ZMAuthenticationStatus, user: ZMUser? = nil) {
        let userInfo: [String: Any] = [
            self.authenticationEventKey: event
            ]
        NotificationInContext(name: self.authenticationEventNotification,
                              context: context,
                              userInfo: userInfo).post()
    }
    
    public static func register(_ observer: PreLoginAuthenticationObserver, context: ZMAuthenticationStatus) -> Any {
        return NotificationInContext.addObserver(name: self.authenticationEventNotification,
                                                 context: context)
        {
            [weak observer] note in
            guard let event = note.userInfo[self.authenticationEventKey] as? PreLoginAuthenticationEvent,
                let observer = observer else { return }
            
            switch event {
            case .loginCodeRequestDidFail(let error):
                observer.loginCodeRequestDidFail?(error)
            case .authenticationReadyToImportBackup(let existingAccount):
                observer.authenticationReadyToImportBackup?(existingAccount: existingAccount)
            case .loginCodeRequestDidSucceed:
                observer.loginCodeRequestDidSucceed?()
            case .authenticationDidFail(let error):
                observer.authenticationDidFail?(error)
            case .authenticationDidSucceed:
                observer.authenticationDidSucceed?()
            case .companyLoginCodeDidBecomeAvailable(let code):
                observer.companyLoginCodeDidBecomeAvailable?(code)
            }
        }
    }
    
    @objc(registerObserver:forUnauthenticatedSession:)
    public static func register(_ observer: PreLoginAuthenticationObserver, for unauthenticatedSession: UnauthenticatedSession?) -> Any {
        if unauthenticatedSession == nil {
            return NSObject()
        }
        
        return self.register(observer, context: unauthenticatedSession!.authenticationStatus)
    }
}

// Obj-c friendly methods
public extension ZMAuthenticationStatus {
    
    @objc
    func notifyAuthenticationDidFail(_ error: NSError) {
        PreLoginAuthenticationNotification.notify(of: .authenticationDidFail(error: error), context: self)
    }

    @objc
    func notifyAuthenticationReadyToImportBackup(existingAccount: Bool) {
        PreLoginAuthenticationNotification.notify(of: .authenticationReadyToImportBackup(existingAccount: existingAccount), context: self)
    }
    
    @objc
    func notifyAuthenticationDidSucceed() {
        PreLoginAuthenticationNotification.notify(of: .authenticationDidSucceed, context: self)
    }
    
    @objc
    func notifyLoginCodeRequestDidFail(_ error: NSError) {
        PreLoginAuthenticationNotification.notify(of: .loginCodeRequestDidFail(error), context: self)
    }
    
    @objc
    func notifyLoginCodeRequestDidSucceed() {
        PreLoginAuthenticationNotification.notify(of: .loginCodeRequestDidSucceed, context: self)
    }

    @objc
    func notifyCompanyLoginCodeDidBecomeAvailable(_ code: UUID) {
        PreLoginAuthenticationNotification.notify(of: .companyLoginCodeDidBecomeAvailable(code), context: self)
    }
}

extension ZMUser {

    @objc public var loginCredentials: LoginCredentials {
        return LoginCredentials(emailAddress: self.emailAddress,
                                phoneNumber: self.phoneNumber,
                                hasPassword: self.emailAddress != nil,
                                usesCompanyLogin: self.usesCompanyLogin)
    }

}


extension LoginCredentials {

    /// This will be used to set user info on the NSError
    @objc public var dictionaryRepresentation: [String: Any] {
        var userInfo: [String: Any] = [:]
        userInfo[ZMUserLoginCredentialsKey] = self
        userInfo[ZMUserHasPasswordKey] = hasPassword
        userInfo[ZMUserUsesCompanyLoginCredentialKey] = usesCompanyLogin

        if let emailAddress = emailAddress, !emailAddress.isEmpty {
            userInfo[ZMEmailCredentialKey] = emailAddress
        }

        if let phoneNumber = phoneNumber, !phoneNumber.isEmpty {
            userInfo[ZMPhoneCredentialKey] = phoneNumber
        }

        return userInfo
    }

}
