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


@import WireSystem;

#import <WireSyncEngine/ZMUserSession.h>

@class ZMCompleteRegistrationUser;
@protocol ZMRegistrationObserverToken;
@protocol ZMRegistrationObserver;

@interface ZMUserSession (Registration)

/// Whether the user completed the registration on this device
@property (nonatomic, readonly) BOOL registeredOnThisDevice;

/// Register a user
- (void)registerSelfUser:(ZMCompleteRegistrationUser *)registrationUser;

/// Request a phone verification code for registration or self profile update
- (void)requestPhoneVerificationCodeForRegistration:(NSString *)phoneNumber;

/// Verify phone number with code for registration
- (void)verifyPhoneNumberForRegistration:(NSString *)phoneNumber verificationCode:(NSString *)verificationCode;

/// Resend verification email for currently registered user. To be used only during email-based registration
- (void)resendRegistrationVerificationEmail;

/// Stop attempting to log in automatically with a timer while waiting for the email validation
- (void)cancelWaitForEmailVerification;

/// Stop attempting to validate the phone number. Does nothing
- (void)cancelWaitForPhoneVerification;

- (id<ZMRegistrationObserverToken>)addRegistrationObserver:(id<ZMRegistrationObserver>)observer ZM_MUST_USE_RETURN;
- (void)removeRegistrationObserverForToken:(id<ZMRegistrationObserverToken>)token;

@end



@protocol ZMRegistrationObserver <NSObject>
@optional

/// Invoked when the registration failed
- (void)registrationDidFail:(NSError *)error;

/// Requesting the phone verification code failed (e.g. invalid number?) even before sending SMS
- (void)phoneVerificationCodeRequestDidFail:(NSError *)error;

/// Requesting the phone verification code succeded
- (void)phoneVerificationCodeRequestDidSucceed;

/// Invoked when any kind of phone verification was completed with the right code
- (void)phoneVerificationDidSucceed;

/// Invoked when any kind of phone verification failed because of wrong code/phone combination
- (void)phoneVerificationDidFail:(NSError *)error;

/// Email was correctly registered and validated
- (void)emailVerificationDidSucceed;

/// Email was already registered to another user
- (void)emailVerificationDidFail:(NSError *)error;

@end
