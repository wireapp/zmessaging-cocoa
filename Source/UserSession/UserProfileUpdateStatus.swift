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
    fileprivate var phoneCredentialsToUpdate : SyncToBackendPhase<ZMPhoneCredentials> = .idle
    
    /// email and password to update
    fileprivate var emailPasswordToSet : (email: SyncToBackendPhase<ZMEmailCredentials>, password: SyncToBackendPhase<ZMEmailCredentials>) = (.idle, .idle)
    
    /// last set password and email
    fileprivate var lastEmailAndPassword : ZMEmailCredentials?
    
    /// phone number to validate
    fileprivate var profilePhoneNumberThatNeedsAValidationCode : SyncToBackendPhase<String> = .idle
    
    let managedObjectContext : NSManagedObjectContext
    
    /// Callback invoked when there is a new request to send
    let newRequestCallback : ()->()
    
    public init(managedObjectContext: NSManagedObjectContext, newRequestCallback: @escaping ()->()) {
        self.managedObjectContext = managedObjectContext
        self.newRequestCallback = newRequestCallback
    }
}

// MARK: - Request changes
extension UserProfileUpdateStatus {
    
    /// Requests phone number verification. Once this is called,
    /// the user is expected to receive a PIN code on her phone
    /// and call `requestPhoneNumberChange` with that PIN
    public func requestPhoneVerificationCode(phoneNumber: String) {
        // TODO MARCO
    }
    
    /// Requests phone number changed, with a PIN received earlier
    public func requestPhoneNumberChange(credentials: ZMPhoneCredentials) {
        // TODO MARCO
    }
    
    /// Requests to set an email and password, for a user that does not have either. 
    /// Once this is called, we expect the user to eventually verify the email externally.
    /// - throws: if the email was already set, or if empty credentials are passed
    public func requestSettingEmailAndPassword(credentials: ZMEmailCredentials) throws {
        guard credentials.email != nil, credentials.password != nil else {
            throw UserProfileUpdateError.missingArgument
        }
        
        self.lastEmailAndPassword = credentials
        
        let selfUser = ZMUser.selfUser(in: self.managedObjectContext)
        guard selfUser.emailAddress == nil else {
            self.emailPasswordToSet = (.idle, .idle)
            throw UserProfileUpdateError.emailAlreadySet
        }
        
        self.emailPasswordToSet = (.needToSync(credentials), .needToSync(credentials))
        // TODO MARCO
        
        self.newRequestCallback()
    }
    
    /// Cancel setting email and password
    public func cancelSettingEmailAndPassword() {
        self.lastEmailAndPassword = nil
        self.emailPasswordToSet = (.idle, .idle)
    }
    
}

// MARK: - Update status
extension UserProfileUpdateStatus {

    
    func didRequestPhoneVerificationCodeSuccessfully() {
        // TODO MARCO
    }
    
    func didFailPhoneVerificationCodeRequest(error: NSError) {
        // TODO MARCO
    }
    
    func didVerifyPhoneSuccessfully() {
        // TODO MARCO
    }
    func didFailPhoneVerification(error: NSError) {
        // TODO MARCO
    }
    
    /// Invoked when the request to set password succedeed
    func didUpdatePasswordSuccessfully() {
        self.emailPasswordToSet.password = .idle
    }
    
    /// Invoked when the request to set password failed
    func didFailPasswordUpdate() {
        // TODO MARCO
    }
    
    /// Invoked when the request to change email was sent successfully
    func didUpdateEmailSuccessfully() {
        self.emailPasswordToSet = (.idle, .idle)
    }
    
    func didFailEmailUpdate(error: NSError) {
        // TODO MARCO
    }
}

// MARK: - Data
extension UserProfileUpdateStatus : ZMCredentialProvider {
    
    public var emailValueToSet : String? {
        switch self.emailPasswordToSet {
        case (.idle, _):
            return nil
        case (_, .needToSync):
            return nil
        case (_, .synchronizing):
            return nil
        case (.needToSync(let credentials), _):
            return credentials.email
        case (.synchronizing(let credentials), _):
            return credentials.email
        default:
            return nil
        }
    }
    
    public var passwordValueToSet : String? {
        switch self.emailPasswordToSet {
        case (_, .idle):
            return nil
        case (.needToSync(let credentials), _):
            return credentials.password
        case (.synchronizing(let credentials), _):
            return credentials.password
        default:
            return nil
        }
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
    
    private var selfUserHasEmail : Bool {
        let selfUser = ZMUser.selfUser(in: self.managedObjectContext)
        return selfUser.emailAddress != nil && selfUser.emailAddress != ""
    }
    
    /// Whether we are currently setting the email.
    /// If the app starts and this is set, the app is waiting for the user to confirm her email
    public var currentlySettingEmail : Bool {
        
        guard !self.selfUserHasEmail else {
            return false
        }
        
        switch self.emailPasswordToSet {
        case (.idle, _):
            return false
        case (.needToSync, .idle):
            return true
        case (.synchronizing, .idle):
            return true
        default:
            return false
        }
    }
    
    /// Whether we are currently setting the password.
    public var currentlySettingPassword : Bool {
        
        guard !self.selfUserHasEmail else {
            return false
        }
        
        switch self.emailPasswordToSet {
        case (_, .idle):
            return false
        default:
            return true
        }
    }
    
    /// If the app stars and this is set, the app is waiting for the user to confirm her phone number
    public var currentlyUpdatingPhone : Bool {
        // TODO MARCO
//        ZMUser *selfUser = [ZMUser selfUserInUserSession:self];
//        return (selfUser.phoneNumber == nil) ?
//            (self.userProfileUpdateStatus.profilePhoneNumberThatNeedsAValidationCode ?: self.userProfileUpdateStatus.phoneCredentialsToUpdate.phoneNumber)
//            : nil;
        return false
    }
}

// MARK: - Helpers

/// Tracks the state of synchronizing something to the backend
enum SyncToBackendPhase<T> {
    case idle
    case needToSync(T)
    case synchronizing(T)
}


/// Errors
@objc public enum UserProfileUpdateError: Int, Error {
    case missingArgument
    case emailAlreadySet
}

/*
#pragma mark - Notifications

@protocol ZMUserProfileUpdateNotificationObserverToken;

typedef NS_ENUM(NSUInteger, ZMUserProfileUpdateNotificationType) {
    ZMUserProfileNotificationPasswordUpdateDidFail,
    ZMUserProfileNotificationEmailUpdateDidFail,
    ZMUserProfileNotificationEmailDidSendVerification,
    ZMUserProfileNotificationPhoneNumberVerificationCodeRequestDidFail,
    ZMUserProfileNotificationPhoneNumberVerificationCodeRequestDidSucceed,
    ZMUserProfileNotificationPhoneNumberVerificationDidFail
};

@interface ZMUserProfileUpdateNotification : ZMNotification

@property (nonatomic, readonly) ZMUserProfileUpdateNotificationType type;
@property (nonatomic, readonly) NSError *error;

+ (void)notifyPasswordUpdateDidFail;
+ (void)notifyEmailUpdateDidFail:(NSError *)error;
+ (void)notifyPhoneNumberVerificationCodeRequestDidFailWithError:(NSError *)error;
+ (void)notifyPhoneNumberVerificationCodeRequestDidSucceed;
+ (void)notifyDidSendEmailVerification;

+ (void)notifyPhoneNumberVerificationDidFail:(NSError *)error;

+ (id<ZMUserProfileUpdateNotificationObserverToken>)addObserverWithBlock:(void(^)(ZMUserProfileUpdateNotification *))block ZM_MUST_USE_RETURN;
+ (void)removeObserver:(id<ZMUserProfileUpdateNotificationObserverToken>)token;

@end
*/
