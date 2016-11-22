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


/// Tracks the status of request to update the user profile
@objc public class UserProfileUpdateStatus : NSObject {

    /// phone credentials to update
    fileprivate var synchingPhoneCredentials : SyncToBackendPhase<ZMPhoneCredentials> = .idle
    
    /// email and password to update
    fileprivate var synchingEmailAndPassword : (email: SyncToBackendPhase<ZMEmailCredentials>,
        password: SyncToBackendPhase<String>) = (.idle, .idle)
    
    /// phone number to validate
    fileprivate var synchingPhoneNumberForValidationCode : SyncToBackendPhase<String> = .idle
    
    /// last set password and email
    fileprivate var lastEmailAndPassword : ZMEmailCredentials?
    
    let managedObjectContext : NSManagedObjectContext
    
    /// Callback invoked when there is a new request to send
    let newRequestCallback : ()->()
    
    public init(managedObjectContext: NSManagedObjectContext) {
        self.managedObjectContext = managedObjectContext
        self.newRequestCallback = { _ in RequestAvailableNotification.notifyNewRequestsAvailable(nil) }
    }
}

// MARK: - Request changes
extension UserProfileUpdateStatus {
    
    /// Requests phone number verification. Once this is called,
    /// the user is expected to receive a PIN code on her phone
    /// and call `requestPhoneNumberChange` with that PIN
    public func requestPhoneVerificationCode(phoneNumber: String) {
        self.synchingPhoneNumberForValidationCode = .needToSync(phoneNumber)
        self.newRequestCallback()

    }
    
    /// Requests phone number changed, with a PIN received earlier
    public func requestPhoneNumberChange(credentials: ZMPhoneCredentials) {
        self.synchingPhoneCredentials = .needToSync(credentials)
        self.newRequestCallback()

    }
    
    /// Requests to set an email and password, for a user that does not have either. 
    /// Once this is called, we expect the user to eventually verify the email externally.
    /// - throws: if the email was already set, or if empty credentials are passed
    public func requestSettingEmailAndPassword(credentials: ZMEmailCredentials) throws {
        guard credentials.email != nil, let password = credentials.password else {
            throw UserProfileUpdateError.missingArgument
        }
        
        self.lastEmailAndPassword = credentials
        
        let selfUser = ZMUser.selfUser(in: self.managedObjectContext)
        guard selfUser.emailAddress == nil else {
            self.synchingEmailAndPassword = (.idle, .idle)
            throw UserProfileUpdateError.emailAlreadySet
        }
        
        self.synchingEmailAndPassword = (.needToSync(credentials), .needToSync(password))
        
        self.newRequestCallback()
    }
    
    /// Cancel setting email and password
    public func cancelSettingEmailAndPassword() {
        self.lastEmailAndPassword = nil
        self.synchingEmailAndPassword = (.idle, .idle)
        self.newRequestCallback()

    }
    
}

// MARK: - Update status
extension UserProfileUpdateStatus {

    /// Invoked when requested a phone verification code successfully
    func didRequestPhoneVerificationCodeSuccessfully() {
        self.synchingPhoneNumberForValidationCode = .idle
        UserProfileUpdateNotification.notifyPhoneNumberVerificationCodeRequestDidSucceed()
    }
    
    /// Invoked when failed to request a verification code
    func didFailPhoneVerificationCodeRequest(error: Error) {
        self.synchingPhoneNumberForValidationCode = .idle
        UserProfileUpdateNotification.notifyPhoneNumberVerificationCodeRequestDidFailWithError(error: error)
    }
    
    /// Invoked when changing the phone number succeeded
    func didChangePhoneSuccesfully() {
        self.synchingPhoneCredentials = .idle
    }
    
    /// Invoked when changing the phone number failed
    func didFailChangingPhone(error: Error) {
        self.synchingPhoneCredentials = .idle
        UserProfileUpdateNotification.notifyPhoneNumberChangeDidFail(error: error)
    }
    
    /// Invoked when the request to set password succedeed
    func didUpdatePasswordSuccessfully() {
        self.synchingEmailAndPassword.password = .idle
    }
    
    /// Invoked when the request to set password failed
    func didFailPasswordUpdate() {
        self.lastEmailAndPassword = nil
        self.synchingEmailAndPassword = (.idle, .idle)
        UserProfileUpdateNotification.notifyPasswordUpdateDidFail()
    }
    
    /// Invoked when the request to change email was sent successfully
    func didUpdateEmailSuccessfully() {
        self.synchingEmailAndPassword.email = .idle
        UserProfileUpdateNotification.notifyDidSendEmailVerification()
    }
    
    func didFailEmailUpdate(error: Error) {
        self.lastEmailAndPassword = nil
        self.synchingEmailAndPassword = (.idle, .idle)
        UserProfileUpdateNotification.notifyEmailUpdateDidFail(error: error)
    }
}

// MARK: - Data
extension UserProfileUpdateStatus : ZMCredentialProvider {
    
    /// The email to set on the backend
    var emailValueToSet : String? {
        guard !self.currentlySettingPassword else {
            return nil
        }
        
        return self.synchingEmailAndPassword.email.value?.email
    }
    
    /// The password to set on the backend
    var passwordValueToSet : String? {
        return self.synchingEmailAndPassword.password.value
    }
    
    /// The phone number for which to request a validation code
    var phoneNumberForWhichCodeIsRequested : String? {
        return self.synchingPhoneNumberForValidationCode.value
    }
    
    /// The phone number for which to request a validation code
    var phoneNumberToSet : ZMPhoneCredentials? {
        return self.synchingPhoneCredentials.value
    }
    
    public func emailCredentials() -> ZMEmailCredentials? {
        guard !self.currentlySettingEmail && !self.currentlySettingPassword else {
            return nil
        }
        return self.lastEmailAndPassword
    }
    
    public func credentialsMayBeCleared() {
        self.lastEmailAndPassword = nil
    }
}

// MARK: - External status
extension UserProfileUpdateStatus {
    
    /// Whether the current user has an email set in the profile
    private var selfUserHasEmail : Bool {
        let selfUser = ZMUser.selfUser(in: self.managedObjectContext)
        return selfUser.emailAddress != nil && selfUser.emailAddress != ""
    }
    
    /// Whether the current user has a phone number set in the profile
    private var selfUserHasPhoneNumber : Bool {
        let selfUser = ZMUser.selfUser(in: self.managedObjectContext)
        return selfUser.phoneNumber != nil && selfUser.phoneNumber != ""
    }
    
    /// Whether we are currently setting the email.
    /// If the app starts and this is set, the app is waiting for the user to confirm her email
    public var currentlySettingEmail : Bool {
        
        guard !self.selfUserHasEmail else {
            return false
        }
        
        return !self.synchingEmailAndPassword.email.isIdle && self.synchingEmailAndPassword.password.isIdle
    }
    
    /// Whether we are currently setting the password.
    public var currentlySettingPassword : Bool {
        
        guard !self.selfUserHasEmail else {
            return false
        }
        
        return !self.synchingEmailAndPassword.password.isIdle
    }
    
    /// Whether we are currently requesting a PIN to update the phone
    public var currentlyRequestingPhoneVerificationCode : Bool {
        
        return !self.synchingPhoneNumberForValidationCode.isIdle
    }
    
    
    /// Whether we are currently requesting a change of phone number
    public var currentlySettingPhone : Bool {
        
        guard !self.selfUserHasPhoneNumber else {
            return false
        }
        
        return !self.synchingPhoneCredentials.isIdle
    }
}

// MARK: - Helpers

/// Tracks the state of synchronizing something to the backend
enum SyncToBackendPhase<T> {
    case idle
    case needToSync(T)
    case synchronizing(T)
    
    var isIdle : Bool {
        switch self {
        case .idle:
            return true
        default:
            return false
        }
    }
    
    var value : T? {
        switch self {
        case .idle:
            return nil
        case .needToSync(let t):
            return t
        case .synchronizing(let t):
            return t
        }
    }
}


/// Errors
@objc public enum UserProfileUpdateError: Int, Error {
    case missingArgument
    case emailAlreadySet
}

