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


@import Foundation;


typedef NS_ENUM(NSUInteger, ZMUserSessionErrorCode) {
    ZMUserSessionNoError = 0,
    /// ???
    ZMUserSessionUnkownError = 1,
    /// Credentials are needed to authenticate
    ZMUserSessionNeedsCredentials = 2,
    /// The credentials provided are not valid
    ZMUserSessionInvalidCredentials = 3,
    /// The account is still pending validation
    ZMUserSessionAccountIsPendingActivation = 4,
    /// Network error in communicating with the backend
    ZMUserSessionNetworkError = 5,
    /// The email used in the registration is already in use
    ZMUserSessionEmailIsAlreadyRegistered = 6,
    /// The phone number used in the registration is already in use
    ZMUserSessionPhoneNumberIsAlreadyRegistered = 7,
    /// The phone number used in the registration is not a valid phone number
    ZMUserSessionInvalidPhoneNumber = 8,
    /// The email used in the registration is not a valid email
    ZMUserSessionInvalidEmail = 9,
    /// The phone number verification code inserted is not valid
    ZMUserSessionInvalidPhoneNumberVerificationCode = 10,
    /// The registration failed, but we don't know why
    ZMUserSessionRegistrationDidFailWithUnknownError = 11,
    /// There is already a recent request to get the activation code for registration/login
    ZMUserSessionCodeRequestIsAlreadyPending = 12,
    /// The user account does not have a password, and a password
    /// is needed to register a new client.
    ZMUserSessionNeedsPasswordToRegisterClient = 13,
    /// The user account does not have an email, and an email
    /// is needed to register a new client
    /// Not supported by the backend any more. The error is generated locally.
    ZMUserSessionNeedsToRegisterEmailToRegisterClient = 14,
    /// Too many clients have been registered for this user,
    /// one needs to be deleted before registering a new one
    ZMUserSessionCanNotRegisterMoreClients = 15,
    /// The invitation code provided during registration is invalid
    ZMUserSessionInvalidInvitationCode = 16,
    /// The user account was deleted
    ZMUserSessionAccountDeleted = 17,
    /// The current usert client was deleted remotely
    ZMUserSessionClientDeletedRemotely = 18,
    /// The last user identity (email or phone number) cannot be removed.
    ZMUserSessionLastUserIdentityCantBeDeleted = 19,
    /// Access token expired and could not be renewed
    ZMUserSessionAccessTokenExpired = 20,
    /// The user requested to add an additional account
    ZMUserSessionAddAccountRequested = 21,
    /// The user account is suspended and may not be logged in
    ZMUserSessionAccountSuspended = 22
};

FOUNDATION_EXPORT NSString * const ZMUserSessionErrorDomain;

FOUNDATION_EXPORT NSString * const ZMClientsKey;

FOUNDATION_EXPORT NSString * const ZMPhoneCredentialKey;
FOUNDATION_EXPORT NSString * const ZMEmailCredentialKey;

@interface NSError (ZMUserSession)

/// Will return @c ZMUserSessionNoError if the receiver is not a user session error.
@property (nonatomic, readonly) ZMUserSessionErrorCode userSessionErrorCode;

@end
