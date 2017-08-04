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

@objc public protocol ZMAuthenticationObserver: NSObjectProtocol {
    /// Invoked when requesting a login code for the phone failed
    @objc optional func loginCodeRequestDidFail(_ error: Error)
    
    /// Invoked when requesting a login code succeded
    @objc optional func loginCodeRequestDidSucceed()
    
    /// Invoked when the authentication failed, or when the cookie was revoked
    @objc optional func authenticationDidFail(_ error: Error)
    
    /// Invoked when the authentication succeeded and the user now has a valid 
    @objc optional func authenticationDidSucceed()

    @objc optional func clientRegistrationDidSucceed()

    @objc optional func didDetectSelfClientDeletion()
}

extension ZMUserSessionAuthenticationNotification {
    @objc(addObserver:) public static func addObserver(_ observer: ZMAuthenticationObserver) -> ZMAuthenticationObserverToken {
        return addObserver { [weak observer] in
            let error = $0.error
            switch $0.type {
            case .authenticationNotificationLoginCodeRequestDidFail:
                observer?.loginCodeRequestDidFail?(error!)
            case .authenticationNotificationLoginCodeRequestDidSucceed:
                observer?.loginCodeRequestDidSucceed?()
            case .authenticationNotificationAuthenticationDidFail:
                observer?.authenticationDidFail?(error!)
            case .authenticationNotificationAuthenticationDidSuceeded:
                observer?.authenticationDidSucceed?()
            case .authenticationNotificationDidRegisterClient:
                observer?.clientRegistrationDidSucceed?()
            case .authenticationNotificationDidDetectSelfClientDeletion:
                observer?.didDetectSelfClientDeletion?()
            }
        }
    }
}
