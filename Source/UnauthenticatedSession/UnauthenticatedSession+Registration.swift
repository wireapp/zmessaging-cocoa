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

@objc
protocol RegistrationObserver {
    
    /// Invoked when the registration failed
    func registrationDidFail(error: Error)
    
    /// Requesting the phone verification code failed (e.g. invalid number?) even before sending SMS
    func phoneVerificationCodeRequestDidFail(error: Error)
    
    /// Requesting the phone verification code succeded
    func phoneVerificationCodeRequestDidSucceed()
    
    /// Invoked when any kind of phone verification was completed with the right code
    func phoneVerificationDidSucceed()
    
    /// Invoked when any kind of phone verification failed because of wrong code/phone combination
    func phoneVerificationDidFail(error: Error)
    
    /// Email was correctly registered and validated
    func emailVerificationDidSucceed()
    
    /// Email was already registered to another user
    func emailVerificationDidFail(error: Error)
    
}

extension UnauthenticatedSession {
    
    @objc(registerUser:)
    public func register(user : ZMCompleteRegistrationUser) {
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
            ZMUserSessionRegistrationNotification.notifyRegistrationDidFail(NSError.userSessionErrorWith(.needsCredentials, userInfo: nil))
            return
        }
        
        authenticationStatus.prepareForRegistration(of: user)
        RequestAvailableNotification.notifyNewRequestsAvailable(nil)
    }
    
    @objc
    public func requestPhoneVerificationCodeForRegistration(_ phoneNumber: String) {
        authenticationStatus.prepareForRequestingPhoneVerificationCode(forRegistration: phoneNumber)
        RequestAvailableNotification.notifyNewRequestsAvailable(nil)
    }
    
    @objc
    public func verifyPhoneNumberForRegistration(_ phoneNumber: String, verificationCode: String) {
        let credentials = ZMPhoneCredentials(phoneNumber: phoneNumber, verificationCode: verificationCode)
        authenticationStatus.prepareForRegistrationPhoneVerification(with: credentials)
        RequestAvailableNotification.notifyNewRequestsAvailable(nil)
    }
    
    @objc
    public func resendRegistrationVerificationEmail() {
        ZMUserSessionRegistrationNotification.resendValidationForRegistrationEmail()
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
    public func addRegistrationObserver(_ observer: ZMRegistrationObserver) -> ZMRegistrationObserverToken {
        return ZMUserSessionRegistrationNotification.addObserver { (note) in
            
            guard let note = note else { return }
            
            switch (note.type) {
            case ZMUserSessionRegistrationNotificationType.registrationNotificationEmailVerificationDidFail:
                if observer.responds(to: #selector(observer.emailVerificationDidFail(_:))) {
                    observer.emailVerificationDidFail!(note.error)
                }
            case ZMUserSessionRegistrationNotificationType.registrationNotificationEmailVerificationDidSucceed:
                if observer.responds(to: #selector(observer.emailVerificationDidSucceed)) {
                    observer.emailVerificationDidSucceed!()
                }
            case ZMUserSessionRegistrationNotificationType.registrationNotificationPhoneNumberVerificationDidFail:
                if observer.responds(to: #selector(observer.phoneVerificationDidFail(_:))) {
                    observer.phoneVerificationDidFail!(note.error)
                }
            case ZMUserSessionRegistrationNotificationType.registrationNotificationPhoneNumberVerificationCodeRequestDidFail:
                if observer.responds(to: #selector(observer.phoneVerificationCodeRequestDidFail(_:))) {
                    observer.phoneVerificationCodeRequestDidFail!(note.error)
                }
            case ZMUserSessionRegistrationNotificationType.registrationNotificationPhoneNumberVerificationDidSucceed:
                if observer.responds(to: #selector(observer.phoneVerificationDidSucceed)) {
                    observer.phoneVerificationDidSucceed!()
                }
            case ZMUserSessionRegistrationNotificationType.registrationNotificationRegistrationDidFail:
                if observer.responds(to: #selector(observer.registrationDidFail(_:))) {
                    observer.registrationDidFail!(note.error)
                }
            case ZMUserSessionRegistrationNotificationType.registrationNotificationPhoneNumberVerificationCodeRequestDidSucceed:
                if observer.responds(to: #selector(observer.phoneVerificationCodeRequestDidSucceed)) {
                    observer.phoneVerificationCodeRequestDidSucceed!()
                }
            }
            
        }
    }
    
    @objc
    public func removeRegistrationObserver(_ token: ZMRegistrationObserverToken) {
        ZMUserSessionRegistrationNotification.removeObserver(token)
    }
}
