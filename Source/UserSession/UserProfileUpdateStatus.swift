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

/// Number of autogenerated names to try as handles
private let alternativeAutogeneratedNames = 4

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
    
    /// suggested handles to check for availability
    fileprivate(set) var suggestedHandlesToCheck : [String]?
    
    /// best handle suggestion found so far
    fileprivate(set) public var bestHandleSuggestion : String?
    
    let managedObjectContext : NSManagedObjectContext
    
    /// Callback invoked when there is a new request to send
    let newRequestCallback : ()->()
    
    public init(managedObjectContext: NSManagedObjectContext) {
        self.managedObjectContext = managedObjectContext
        self.newRequestCallback = { _ in RequestAvailableNotification.notifyNewRequestsAvailable(nil) }
    }

}

// MARK: - User profile protocol
extension UserProfileUpdateStatus : UserProfile {
    
    public var lastSuggestedHandle: String? {
        return self.bestHandleSuggestion
    }
    
    public func requestPhoneVerificationCode(phoneNumber: String) {
        self.managedObjectContext.performGroupedBlock {
            self.phoneNumberForWhichCodeIsRequested = phoneNumber
            self.newRequestCallback()
        }
    }
    
    public func requestPhoneNumberChange(credentials: ZMPhoneCredentials) {
        self.managedObjectContext.performGroupedBlock {
            self.phoneNumberToSet = credentials
            self.newRequestCallback()
        }

    }
    
    public func requestSettingEmailAndPassword(credentials: ZMEmailCredentials) throws {
        guard let email = credentials.email, let password = credentials.password else {
            throw UserProfileUpdateError.missingArgument
        }
        
        
        let selfUser = ZMUser.selfUser(in: self.managedObjectContext)
        guard selfUser.emailAddress == nil else {
            self.managedObjectContext.performGroupedBlock {
                self.emailToSet = nil
                self.passwordToSet = nil
            }
            throw UserProfileUpdateError.emailAlreadySet
        }

        self.managedObjectContext.performGroupedBlock {
            self.lastEmailAndPassword = credentials
            
            self.emailToSet = email
            self.passwordToSet = password
            
            self.newRequestCallback()
        }
    }
    
    public func cancelSettingEmailAndPassword() {
        self.managedObjectContext.performGroupedBlock {
            self.lastEmailAndPassword = nil
            self.emailToSet = nil
            self.passwordToSet = nil
            self.newRequestCallback()
        }
    }
    
    public func requestCheckHandleAvailability(handle: String) {
        self.managedObjectContext.performGroupedBlock {
            self.handleToCheck = handle
            self.newRequestCallback()
        }
    }
    
    public func requestSettingHandle(handle: String) {
        self.managedObjectContext.performGroupedBlock {
            self.handleToSet = handle
            self.newRequestCallback()
        }
    }
    
    public func cancelSettingHandle() {
        self.managedObjectContext.performGroupedBlock {
            self.handleToSet = nil
        }
    }
    
    public func suggestHandles() {
        self.managedObjectContext.performGroupedBlock {
            guard self.suggestedHandlesToCheck == nil else {
                // already searching
                return
            }
            
            if let bestHandle = self.bestHandleSuggestion {
                self.suggestedHandlesToCheck = [bestHandle]
            } else {
                let name = ZMUser.selfUser(in: self.managedObjectContext).name
                self.suggestedHandlesToCheck = RandomHandleGenerator.generatePossibleHandles(displayName: name ?? "",
                                                                                             alternativeNames: alternativeAutogeneratedNames)
            }
            self.newRequestCallback()
        }
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
    
    /// Invoked when a good handle suggestion is found
    func didFindHandleSuggestion(handle: String) {
        self.bestHandleSuggestion = handle
        self.suggestedHandlesToCheck = nil
        UserProfileUpdateNotification.post(type: .didFindHandleSuggestion(handle: handle))
    }
    
    /// Invoked when all potential suggested handles were not available
    func didNotFindAvailableHandleSuggestion() {
        if ZMUser.selfUser(in: self.managedObjectContext).handle != nil {
            // it has handle, no need to keep suggesting
            self.suggestedHandlesToCheck = nil
        } else {
            let name = ZMUser.selfUser(in: self.managedObjectContext).name
            self.suggestedHandlesToCheck = RandomHandleGenerator.generatePossibleHandles(displayName: name ?? "",
                                                                                     alternativeNames: alternativeAutogeneratedNames)
        }
    }
    
    /// Invoked when failed to fetch handle suggestion
    func didFailToFindHandleSuggestion() {
        self.suggestedHandlesToCheck = nil
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
        return self.handleToSet != nil
    }
    
    /// Whether we are currently looking for a valid suggestion for a handle
    public var currentlyGeneratingHandleSuggestion : Bool {
        return ZMUser.selfUser(in: self.managedObjectContext).handle == nil && self.suggestedHandlesToCheck != nil
    }
}

// MARK: - Helpers

/// Errors
@objc public enum UserProfileUpdateError: Int, Error {
    case missingArgument
    case emailAlreadySet
}

