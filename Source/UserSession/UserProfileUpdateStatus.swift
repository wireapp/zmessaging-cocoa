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

/// Tracks the state of synchronizing something to the backend
enum SyncToBackendPhase<T> {
    case idle
    case needToSync(T)
    case synchronizing(T)
}


/// Tracks the status of request to update the user profile
@objc public class UserProfileUpdateStatus : NSObject {

    /// phone credentials to update
    var phoneCredentialsToUpdate : SyncToBackendPhase<ZMPhoneCredentials> = .idle
    
    /// email to update
    var emailSyncState : SyncToBackendPhase<String> = .idle
    
    /// password to update
    var passwordSyncState : SyncToBackendPhase<String> = .idle
    
    /// phone number to validate
    var profilePhoneNumberThatNeedsAValidationCode : SyncToBackendPhase<String> = .idle
    
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
        // TODO
    }
    
    /// Requests phone number changed, with a PIN received earlier
    public func requestPhoneNumberChange(credentials: ZMPhoneCredentials) {
        // TODO
    }
    
    /// Requests email validation to change email and password. Once this is called,
    /// we expect the user to eventually verify the email externally.
    public func requestEmailAndPasswordChange(credentials: ZMEmailCredentials) {
        // TODO
    }
    
}

// MARK: - Update status
extension UserProfileUpdateStatus {

    
    func didRequestPhoneVerificationCodeSuccessfully() {
        // TODO
    }
    
    func didFailPhoneVerificationCodeRequest(error: NSError) {
        // TODO
    }
    
    func didVerifyPhoneSuccessfully() {
        // TODO
    }
    func didFailPhoneVerification(error: NSError) {
        // TODO
    }
    
    func didUpdatePasswordSuccessfully() {
        // TODO
    }
    
    func didFailPasswordUpdate() {
        // TODO
    }
    
    func didUpdateEmailSuccessfully() {
        // TODO
    }
    
    func didFailEmailUpdate(error: NSError) {
        // TODO
    }
}

// MARK: - Credentials provider
extension UserProfileUpdateStatus : ZMCredentialProvider {
    
    public func emailCredentials() -> ZMEmailCredentials! {
        // TODO
        return nil
    }
    
    public func credentialsMayBeCleared() {
        // TODO
    }
}

// MARK: - External accessors
extension UserProfileUpdateStatus {
    
    /// If the app starts and this is set, the app is waiting for the user to confirm her email
    public var currentlyUpdatingEmail : Bool {
        // TODO
//        ZMUser *selfUser = [ZMUser selfUserInUserSession:self];
//        return (selfUser.emailAddress.length == 0) ? self.userProfileUpdateStatus.emailToUpdate : nil;
        return false
    }
    
    /// If the app stars and this is set, the app is waiting for the user to confirm her phone number
    public var currentlyUpdatingPhone : Bool {
        // TODO
//        ZMUser *selfUser = [ZMUser selfUserInUserSession:self];
//        return (selfUser.phoneNumber == nil) ?
//            (self.userProfileUpdateStatus.profilePhoneNumberThatNeedsAValidationCode ?: self.userProfileUpdateStatus.phoneCredentialsToUpdate.phoneNumber)
//            : nil;
        return false
    }
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
