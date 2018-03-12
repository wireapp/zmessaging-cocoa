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

@objc protocol RegistrationObserver {
    
    /// Invoked when the registration failed
    @objc optional func registrationDidFail(error: Error)
    
    /// Requesting the phone verification code failed (e.g. invalid number?) even before sending SMS
    @objc optional func phoneVerificationCodeRequestDidFail(error: Error)
    
    /// Requesting the phone verification code succeded
    @objc optional func phoneVerificationCodeRequestDidSucceed()
    
    /// Invoked when any kind of phone verification was completed with the right code
    @objc optional func phoneVerificationDidSucceed()
    
    /// Invoked when any kind of phone verification failed because of wrong code/phone combination
    @objc optional func phoneVerificationDidFail(error: Error)
    
    /// Email was correctly registered and validated
    @objc optional func emailVerificationDidSucceed()
    
    /// Email was already registered to another user
    @objc optional func emailVerificationDidFail(error: Error)
    
}

extension UnauthenticatedSession {
    
    @objc(registerUser:)
    public func register(user: ZMCompleteRegistrationUser) {
        let password = user.password
        let phoneNumber = user.phoneNumber
        let phoneVerificationCode = user.phoneVerificationCode
        let invitationCode = user.invitationCode
        
        do {
            if phoneNumber == nil {
                var password = password as NSString?
                try ZMUser.validatePassword(&password)
            }
            else if (invitationCode != nil && phoneNumber != nil) {
                var phoneVerificationCode = phoneVerificationCode as NSString?
                try ZMUser.validatePhoneVerificationCode(&phoneVerificationCode)
            }
            else if (phoneNumber != nil) {
                var phoneNumber = phoneNumber as NSString?
                try ZMUser.validatePhoneNumber(&phoneNumber)
            }
        } catch {
            ZMUserSessionRegistrationNotification.notifyRegistrationDidFail(NSError(code: .needsCredentials, userInfo: nil), context: authenticationStatus)
            return
        }

        authenticationErrorIfNotReachable {
            self.authenticationStatus.prepareForRegistration(of: user)
            RequestAvailableNotification.notifyNewRequestsAvailable(nil)
        }
    }
    
    @objc
    public func requestPhoneVerificationCodeForRegistration(_ phoneNumber: String) {
        authenticationErrorIfNotReachable {
            self.authenticationStatus.prepareForRequestingPhoneVerificationCode(forRegistration: phoneNumber)
            RequestAvailableNotification.notifyNewRequestsAvailable(nil)
        }
    }
    
    @objc
    public func verifyPhoneNumberForRegistration(_ phoneNumber: String, verificationCode: String) {
        let credentials = ZMPhoneCredentials(phoneNumber: phoneNumber, verificationCode: verificationCode)
        authenticationStatus.prepareForRegistrationPhoneVerification(with: credentials)
        RequestAvailableNotification.notifyNewRequestsAvailable(nil)
    }
    
    @objc
    public func resendRegistrationVerificationEmail() {
        ZMUserSessionRegistrationNotification.resendValidationForRegistrationEmail(inContext: authenticationStatus)
    }
    
    @objc
    public func cancelWaitForEmailVerification() {
        authenticationStatus.cancelWaitingForEmailVerification()
    }
    
    @objc
    public func cancelWaitForPhoneVerification() {
        // no-op
    }
    
    @objc(setProfileImage:)
    public func setProfileImage(imageData: Data) {
        authenticationStatus.profileImageData = imageData
        delegate?.session(session: self, updatedProfileImage: imageData)
    }
    
}

extension UnauthenticatedSession {
    
    @objc
    public func addRegistrationObserver(_ observer: ZMRegistrationObserver) -> Any {
        return ZMUserSessionRegistrationNotification.addObserver(in: self) { [weak observer] (eventType, error) in
            switch eventType {
            case .registrationNotificationEmailVerificationDidFail:
                observer?.emailVerificationDidFail?(error)
            case .registrationNotificationEmailVerificationDidSucceed:
                observer?.emailVerificationDidSucceed?()
            case .registrationNotificationPhoneNumberVerificationDidFail:
                observer?.phoneVerificationDidFail?(error)
            case .registrationNotificationPhoneNumberVerificationCodeRequestDidFail:
                observer?.phoneVerificationCodeRequestDidFail?(error)
            case .registrationNotificationPhoneNumberVerificationDidSucceed:
                observer?.phoneVerificationDidSucceed?()
            case .registrationNotificationRegistrationDidFail:
                observer?.registrationDidFail?(error)
            case .registrationNotificationPhoneNumberVerificationCodeRequestDidSucceed:
                observer?.phoneVerificationCodeRequestDidSucceed?()
            }
        }
    }
    
}
