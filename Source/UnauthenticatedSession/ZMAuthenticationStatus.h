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
@import CoreData;

#import "NSError+ZMUserSession.h"
#import "ZMUserSession+Authentication.h"
#import "ZMClientRegistrationStatus+Internal.h"

@class ZMCompleteRegistrationUser;
@class ZMCredentials;
@class ZMEmailCredentials;
@class ZMPhoneCredentials;
@class ZMPersistentCookieStorage;
@class ZMClientRegistrationStatus;

FOUNDATION_EXPORT NSString * const RegisteredOnThisDeviceKey;
FOUNDATION_EXPORT NSTimeInterval DebugLoginFailureTimerOverride;

/// Invoked when the credentials are changed
@protocol ZMAuthenticationStatusObserver <NSObject>
- (void)didChangeAuthenticationData;
@end


typedef NS_ENUM(NSUInteger, ZMAuthenticationPhase) {
    ZMAuthenticationPhaseUnauthenticated = 0,
    ZMAuthenticationPhaseLoginWithPhone,
    ZMAuthenticationPhaseLoginWithEmail,
    ZMAuthenticationPhaseRequestPhoneVerificationCodeForRegistration,
    ZMAuthenticationPhaseRequestPhoneVerificationCodeForLogin,
    ZMAuthenticationPhaseVerifyPhoneForRegistration,
    ZMAuthenticationPhaseRegisterWithEmail,
    ZMAuthenticationPhaseRegisterWithPhone,
    ZMAuthenticationPhaseWaitingForEmailVerification,
    ZMAuthenticationPhaseAuthenticated
};

@interface ZMAuthenticationStatus : NSObject

@property (nonatomic, readonly, copy) NSString *registrationPhoneNumberThatNeedsAValidationCode;
@property (nonatomic, readonly, copy) NSString *loginPhoneNumberThatNeedsAValidationCode;

@property (nonatomic, readonly) ZMCredentials *loginCredentials;
@property (nonatomic, readonly) ZMPhoneCredentials *registrationPhoneValidationCredentials;
@property (nonatomic, readonly) ZMCompleteRegistrationUser *registrationUser;

@property (nonatomic, readonly) BOOL completedRegistration;
@property (nonatomic, readonly) BOOL needsCredentialsToLogin;

@property (nonatomic, readonly) ZMAuthenticationPhase currentPhase;
@property (nonatomic) NSData *profileImageData;

@property (nonatomic) NSData *authenticationCookieData;

- (instancetype)initWithGroupQueue:(id<ZMSGroupQueue>)groupQueue;

- (void)addAuthenticationCenterObserver:(id<ZMAuthenticationStatusObserver>)observer;
- (void)removeAuthenticationCenterObserver:(id<ZMAuthenticationStatusObserver>)observer;

- (void)prepareForRegistrationOfUser:(ZMCompleteRegistrationUser *)user;
- (void)prepareForLoginWithCredentials:(ZMCredentials *)credentials;
- (void)cancelWaitingForEmailVerification;
- (void)prepareForRequestingPhoneVerificationCodeForRegistration:(NSString *)phone;
- (void)prepareForRequestingPhoneVerificationCodeForLogin:(NSString *)phone;
- (void)prepareForRegistrationPhoneVerificationWithCredentials:(ZMPhoneCredentials *)phoneCredentials;


- (void)didCompleteRegistrationSuccessfully;
- (void)didFailRegistrationWithDuplicatedEmail;
- (void)didFailRegistrationForOtherReasons:(NSError *)error;

- (void)didCompleteRequestForPhoneRegistrationCodeSuccessfully;
- (void)didFailRequestForPhoneRegistrationCode:(NSError *)error;

- (void)didCompleteRequestForLoginCodeSuccessfully;
- (void)didFailRequestForLoginCode:(NSError *)error;

- (void)didCompletePhoneVerificationSuccessfully;
- (void)didFailPhoneVerificationForRegistration:(NSError *)error;


- (void)loginSucceed; // called just after recieveing successful login response
- (void)didFailLoginWithPhone:(BOOL)invalidCredentials;
- (void)didFailLoginWithEmailBecausePendingValidation;
- (void)didFailLoginWithEmail:(BOOL)invalidCredentials;
- (void)didTimeoutLoginForCredentials:(ZMCredentials *)credentials;

@end

@interface ZMAuthenticationStatus (CredentialProvider) <ZMCredentialProvider>

- (void)credentialsMayBeCleared;

@end


@interface NSManagedObjectContext (Registration)

@property (nonatomic) BOOL registeredOnThisDevice;
- (NSString *)legacyCookieLabel;

@end

