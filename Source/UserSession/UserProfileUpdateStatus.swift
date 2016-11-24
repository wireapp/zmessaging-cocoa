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
    fileprivate(set) var phoneNumberToSet : ZMPhoneCredentials?
    
    /// email to set
    fileprivate(set) var emailToSet : String?
    
    /// password to set
    fileprivate(set) var passwordToSet: String?
    
    /// phone number to validate
    fileprivate(set) var phoneNumberForWhichCodeIsRequested : String?
    
    /// handle to check for availability
    fileprivate(set) var handleToCheck : String?
    
    /// handle to check
    fileprivate(set) var handleToSet : String?
    
    /// last set password and email
    fileprivate(set) var lastEmailAndPassword : ZMEmailCredentials?
    
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
        self.phoneNumberForWhichCodeIsRequested = phoneNumber
        self.newRequestCallback()

    }
    
    /// Requests phone number changed, with a PIN received earlier
    public func requestPhoneNumberChange(credentials: ZMPhoneCredentials) {
        self.phoneNumberToSet = credentials
        self.newRequestCallback()

    }
    
    /// Requests to set an email and password, for a user that does not have either. 
    /// Once this is called, we expect the user to eventually verify the email externally.
    /// - throws: if the email was already set, or if empty credentials are passed
    public func requestSettingEmailAndPassword(credentials: ZMEmailCredentials) throws {
        guard let email = credentials.email, let password = credentials.password else {
            throw UserProfileUpdateError.missingArgument
        }
        
        self.lastEmailAndPassword = credentials
        
        let selfUser = ZMUser.selfUser(in: self.managedObjectContext)
        guard selfUser.emailAddress == nil else {
            self.emailToSet = nil
            self.passwordToSet = nil
            throw UserProfileUpdateError.emailAlreadySet
        }
        
        self.emailToSet = email
        self.passwordToSet = password
        
        self.newRequestCallback()
    }
    
    /// Cancel setting email and password
    public func cancelSettingEmailAndPassword() {
        self.lastEmailAndPassword = nil
        self.emailToSet = nil
        self.passwordToSet = nil
        self.newRequestCallback()

    }
    
    /// Requests a check of availability for a handle
    public func requestCheckHandleAvailability(handle: String) {
        self.handleToCheck = handle
        self.newRequestCallback()
    }
    
    /// Requests setting the handle
    public func requestSettingHandle(handle: String) {
        self.handleToSet = handle
        self.newRequestCallback()
    }
    
    /// Cancels setting the handle
    public func cancelSettingHandle() {
        self.handleToSet = nil
    }
}

// MARK: - Update status
extension UserProfileUpdateStatus {

    /// Invoked when requested a phone verification code successfully
    func didRequestPhoneVerificationCodeSuccessfully() {
        self.phoneNumberForWhichCodeIsRequested = nil
        UserProfileUpdateNotification.post(type: .phoneNumberVerificationCodeRequestDidSucceed)
    }
    
    /// Invoked when failed to request a verification code
    func didFailPhoneVerificationCodeRequest(error: Error) {
        self.phoneNumberForWhichCodeIsRequested = nil
        UserProfileUpdateNotification.post(type: .phoneNumberVerificationCodeRequestDidFail(error: error))
    }
    
    /// Invoked when changing the phone number succeeded
    func didChangePhoneSuccesfully() {
        self.phoneNumberToSet = nil
    }
    
    /// Invoked when changing the phone number failed
    func didFailChangingPhone(error: Error) {
        self.phoneNumberToSet = nil
        UserProfileUpdateNotification.post(type: .phoneNumberChangeDidFail(error: error))
    }
    
    /// Invoked when the request to set password succedeed
    func didUpdatePasswordSuccessfully() {
        self.passwordToSet = nil
    }
    
    /// Invoked when the request to set password failed
    func didFailPasswordUpdate() {
        self.lastEmailAndPassword = nil
        self.emailToSet = nil
        self.passwordToSet = nil
        UserProfileUpdateNotification.post(type: .passwordUpdateDidFail)
    }
    
    /// Invoked when the request to change email was sent successfully
    func didUpdateEmailSuccessfully() {
        self.emailToSet = nil
        UserProfileUpdateNotification.post(type: .emailDidSendVerification)
    }
    
    /// Invoked when the request to change email failed
    func didFailEmailUpdate(error: Error) {
        self.lastEmailAndPassword = nil
        self.emailToSet = nil
        self.passwordToSet = nil
        UserProfileUpdateNotification.post(type: .emailUpdateDidFail(error: error))
    }
    
    /// Invoked when the request to fetch a handle returned not found
    func didNotFindHandle(handle: String) {
        if self.handleToCheck == handle {
            self.handleToCheck = nil
        }
        UserProfileUpdateNotification.post(type: .didCheckAvailabilityOfHandle(handle: handle, available: true))
    }
    
    /// Invoked when the request to fetch a handle returned successfully
    func didFetchHandle(handle: String) {
        if self.handleToCheck == handle {
            self.handleToCheck = nil
        }
        UserProfileUpdateNotification.post(type: .didCheckAvailabilityOfHandle(handle: handle, available: false))
    }
    
    /// Invoked when the request to fetch a handle failed with
    /// an error that is not "not found"
    func didFailRequestToFetchHandle(handle: String) {
        if self.handleToCheck == handle {
            self.handleToCheck = nil
        }
        UserProfileUpdateNotification.post(type: .didFailToCheckAvailabilityOfHandle(handle: handle))
    }
    
    /// Invoked when the handle was succesfully set
    func didSetHandle() {
        if let handle = self.handleToSet {
            ZMUser.selfUser(in: self.managedObjectContext).setHandle(handle)
        }
        self.handleToSet = nil
        UserProfileUpdateNotification.post(type: .didSetHandle)

    }
    
    /// Invoked when the handle was not set because of a generic error
    func didFailToSetHandle() {
        self.handleToSet = nil
        UserProfileUpdateNotification.post(type: .didFailToSetHandle)
    }
    
    /// Invoked when the handle was not set because it was already existing
    func didFailToSetAlreadyExistingHandle() {
        self.handleToSet = nil
        UserProfileUpdateNotification.post(type: .didFailToSetHandleBecauseExisting)
    }
    
}

// MARK: - Data
extension UserProfileUpdateStatus : ZMCredentialProvider {
    
    /// The email credentials being set
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
        return self.emailToSet != nil && self.passwordToSet == nil
    }
    
    /// Whether we are currently setting the password.
    public var currentlySettingPassword : Bool {
        
        guard !self.selfUserHasEmail else {
            return false
        }
        return self.passwordToSet != nil
    }
    
    /// Whether we are currently requesting a PIN to update the phone
    public var currentlyRequestingPhoneVerificationCode : Bool {
        return self.phoneNumberForWhichCodeIsRequested != nil
    }
    
    
    /// Whether we are currently requesting a change of phone number
    public var currentlySettingPhone : Bool {
        guard !self.selfUserHasPhoneNumber else {
            return false
        }
        
        return self.phoneNumberToSet != nil
    }
    
    /// Whether we are currently waiting to check for availability of a handle
    public var currentlyCheckingHandleAvailability : Bool {
        return self.handleToCheck != nil
    }
    
    /// Whether we are currently requesting a change of handle
    public var currentlySettingHandle : Bool {
        return handleToSet != nil
    }
}

// MARK: - Helpers

/// Errors
@objc public enum UserProfileUpdateError: Int, Error {
    case missingArgument
    case emailAlreadySet
}

