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


@import ZMTransport;
@import ZMUtilities;
@import ZMCDataModel;

#include "ZMAuthenticationStatus.h"
#include "ZMTracing.h"
#include "ZMCredentials+Internal.h"
#include "NSError+ZMUserSession.h"
#include "NSError+ZMUserSessionInternal.h"
#include "ZMUserSessionRegistrationNotification.h"
#include "ZMUserSessionAuthenticationNotification.h"

#import "ZMAuthenticationStatus_Internal.h"


static NSString * const AuthenticationCenterDataChangeNotificationName = @"ZMAuthenticationStatusDataChangeNotificationName";
NSString * const RegisteredOnThisDeviceKey = @"ZMRegisteredOnThisDevice";

static NSString* ZMLogTag ZM_UNUSED = @"Authentication";


@implementation ZMAuthenticationStatus

- (instancetype)initWithManagedObjectContext:(NSManagedObjectContext *)moc cookie:(ZMCookie *)cookie;
{
    self = [super init];
    if(self) {
        self.moc = moc;
        self.cookie = cookie;
        self.isWaitingForLogin = !self.isLoggedIn;
    }
    return self;
}

- (ZMCredentials *)loginCredentials
{
    return self.internalLoginCredentials;
}

- (NSString *)cookieLabel
{
    return self.cookie.label;
}

- (void)setCookieLabel:(NSString *)label
{
    self.cookie.label = label;
}

- (void)resetLoginAndRegistrationStatus
{
    self.registrationPhoneNumberThatNeedsAValidationCode = nil;
    self.loginPhoneNumberThatNeedsAValidationCode = nil;

    self.internalLoginCredentials = nil;
    self.registrationPhoneValidationCredentials = nil;
    self.registrationUser = nil;

    self.isWaitingForEmailVerification = NO;
    
    self.duplicateRegistrationEmail = NO;
    self.duplicateRegistrationPhoneNumber = NO;
}

- (void)setRegistrationUser:(ZMCompleteRegistrationUser *)registrationUser
{
    if(self.internalRegistrationUser != registrationUser) {
        self.internalRegistrationUser = registrationUser;
        if (self.internalRegistrationUser.emailAddress != nil) {
            [ZMPersistentCookieStorage setCookiesPolicy:NSHTTPCookieAcceptPolicyNever];
        }
        else {
            [ZMPersistentCookieStorage setCookiesPolicy:NSHTTPCookieAcceptPolicyAlways];
        }
        [[NSNotificationCenter defaultCenter] postNotificationName:AuthenticationCenterDataChangeNotificationName object:self];
    }
}

- (void)setRegisteredOnThisDevice:(BOOL)registeredOnThisDevice
{
    [self.moc setPersistentStoreMetadata:@(registeredOnThisDevice) forKey:RegisteredOnThisDeviceKey];
}

- (BOOL)registeredOnThisDevice
{
    return ((NSNumber *)[self.moc persistentStoreMetadataForKey:RegisteredOnThisDeviceKey]).boolValue;
}

- (ZMCompleteRegistrationUser *)registrationUser
{
    return self.internalRegistrationUser;
}

- (void)setLoginCredentials:(ZMCredentials *)credentials
{
    if(credentials == nil) {
        ZMTraceAuthCredentialsDeleted();
    }
    else {
        ZMTraceAuthCredentialsSet();
    }
    if(credentials != self.internalLoginCredentials) {
        self.internalLoginCredentials = credentials;
        [ZMPersistentCookieStorage setCookiesPolicy:NSHTTPCookieAcceptPolicyAlways];
        [[NSNotificationCenter defaultCenter] postNotificationName:AuthenticationCenterDataChangeNotificationName object:self];
    }
}

- (void)addAuthenticationCenterObserver:(id<ZMAuthenticationStatusObserver>)observer;
{
    ZM_ALLOW_MISSING_SELECTOR
    ([[NSNotificationCenter defaultCenter] addObserver:observer selector:@selector(didChangeAuthenticationData) name:AuthenticationCenterDataChangeNotificationName object:nil]);
}

- (void)removeAuthenticationCenterObserver:(id<ZMAuthenticationStatusObserver>)observer;
{
    [[NSNotificationCenter defaultCenter] removeObserver:observer];
}

- (ZMAuthenticationPhase)currentPhase
{
    if(self.isLoggedIn) {
        return ZMAuthenticationPhaseAuthenticated;
    }
    if(self.isWaitingForEmailVerification) {
        return ZMAuthenticationPhaseWaitingForEmailVerification;
    }
    if(self.registrationUser.emailAddress != nil) {
        return ZMAuthenticationPhaseRegisterWithEmail;
    }
    if(self.registrationUser.phoneVerificationCode != nil || self.registrationUser.invitationCode != nil) {
        return ZMAuthenticationPhaseRegisterWithPhone;
    }
    if(self.internalLoginCredentials.credentialWithEmail && self.isWaitingForLogin) {
        return ZMAuthenticationPhaseLoginWithEmail;
    }
    if(self.internalLoginCredentials.credentialWithPhone && self.isWaitingForLogin) {
        return ZMAuthenticationPhaseLoginWithPhone;
    }
    if(self.registrationPhoneNumberThatNeedsAValidationCode != nil) {
        return ZMAuthenticationPhaseRequestPhoneVerificationCodeForRegistration;
    }
    if(self.loginPhoneNumberThatNeedsAValidationCode != nil) {
        return ZMAuthenticationPhaseRequestPhoneVerificationCodeForLogin;
    }
    if(self.registrationPhoneValidationCredentials != nil) {
        return ZMAuthenticationPhaseVerifyPhoneForRegistration;
    }
    return ZMAuthenticationPhaseUnauthenticated;
}

- (BOOL)needsCredentialsToLogin
{
    return !self.isLoggedIn && self.loginCredentials == nil;
}

- (BOOL)isLoggedIn
{
    return self.hasCookie;
}

- (BOOL)hasCookie;
{
    NSData *cookie = [self.cookie data];
    return cookie != nil;
}

- (void)prepareForLoginWithCredentials:(ZMCredentials *)credentials
{
    ZMLogDebug(@"%@", NSStringFromSelector(_cmd));
    [self setRegisteredOnThisDevice:NO];
    BOOL wasDuplicated = self.duplicateRegistrationPhoneNumber;
    [self resetLoginAndRegistrationStatus];
    if(wasDuplicated && credentials.credentialWithPhone) {
        self.duplicateRegistrationPhoneNumber = YES;
    }
    self.loginCredentials = credentials;
    self.isWaitingForLogin = YES;
    ZMLogDebug(@"current phase: %lu", (unsigned long)self.currentPhase);
}

- (void)prepareForRegistrationOfUser:(ZMCompleteRegistrationUser *)user
{
    ZMLogDebug(@"%@", NSStringFromSelector(_cmd));
    self.cookie.data = nil;
    self.isWaitingForLogin = YES;
    [self resetLoginAndRegistrationStatus];
    self.registrationUser = user;
}

- (void)prepareForRequestingPhoneVerificationCodeForRegistration:(NSString *)phone
{
    ZMLogDebug(@"%@", NSStringFromSelector(_cmd));
    [self resetLoginAndRegistrationStatus];
    [ZMPhoneNumberValidator validateValue:&phone error:nil];
    self.registrationPhoneNumberThatNeedsAValidationCode = phone;
    ZMLogDebug(@"current phase: %lu", (unsigned long)self.currentPhase);
}

- (void)prepareForRequestingPhoneVerificationCodeForLogin:(NSString *)phone;
{
    ZMLogDebug(@"%@", NSStringFromSelector(_cmd));
    [self resetLoginAndRegistrationStatus];
    [ZMPhoneNumberValidator validateValue:&phone error:nil];
    self.loginPhoneNumberThatNeedsAValidationCode = phone;
    ZMLogDebug(@"current phase: %lu", (unsigned long)self.currentPhase);
}

- (void)prepareForRegistrationPhoneVerificationWithCredentials:(ZMPhoneCredentials *)phoneCredentials
{
    ZMLogDebug(@"%@", NSStringFromSelector(_cmd));
    // if it was duplicated phone, do login instead
    BOOL wasDuplicated = self.duplicateRegistrationPhoneNumber;
    [self resetLoginAndRegistrationStatus];

    self.duplicateRegistrationPhoneNumber = wasDuplicated;
    if(wasDuplicated) {
        self.loginCredentials = phoneCredentials;
    }
    else {
        self.registrationPhoneValidationCredentials = phoneCredentials;
    }
    ZMLogDebug(@"current phase: %lu", (unsigned long)self.currentPhase);
}

- (void)didFailRequestForPhoneRegistrationCode:(NSError *)error
{
    ZMLogDebug(@"%@", NSStringFromSelector(_cmd));
    if(error.code == ZMUserSessionPhoneNumberIsAlreadyRegistered) {
        self.duplicateRegistrationPhoneNumber = YES;
        self.loginPhoneNumberThatNeedsAValidationCode = self.registrationPhoneNumberThatNeedsAValidationCode;
        self.registrationPhoneNumberThatNeedsAValidationCode = nil;
        ZMLogDebug(@"current phase: %lu", (unsigned long)self.currentPhase);
        return;
    }
    
    [self resetLoginAndRegistrationStatus];
    [ZMUserSessionRegistrationNotification notifyPhoneNumberVerificationCodeRequestDidFail:error];
    ZMLogDebug(@"current phase: %lu", (unsigned long)self.currentPhase);
}

- (void)didCompleteRegistrationSuccessfully
{
    ZMLogDebug(@"%@", NSStringFromSelector(_cmd));
    [self setRegisteredOnThisDevice:YES];
    
    if(self.currentPhase == ZMAuthenticationPhaseRegisterWithEmail) {
        ZMCredentials *credentials = [ZMEmailCredentials credentialsWithEmail:self.registrationUser.emailAddress password:self.registrationUser.password];
        //we need to set credentials first cause that will trigger notification and check for current state but we need to know that we are going from email registration to login attempts
        self.loginCredentials = credentials;
        self.registrationUser = nil;
        [ZMUserSessionRegistrationNotification notifyEmailVerificationDidSucceed];
    }
    ZMLogDebug(@"current phase: %lu", (unsigned long)self.currentPhase);
}

- (void)didFailRegistrationWithDuplicatedEmail {
    ZMLogDebug(@"%@", NSStringFromSelector(_cmd));
    self.duplicateRegistrationEmail = YES;
    ZMCredentials *credentials = [ZMEmailCredentials credentialsWithEmail:self.registrationUser.emailAddress password:self.registrationUser.password];
    self.registrationUser = nil;
    self.loginCredentials = credentials;
    ZMLogDebug(@"current phase: %lu", (unsigned long)self.currentPhase);
}

- (void)didFailRegistrationForOtherReasons:(NSError *)error;
{
    ZMLogDebug(@"%@", NSStringFromSelector(_cmd));
    [self resetLoginAndRegistrationStatus];
    [ZMUserSessionRegistrationNotification notifyRegistrationDidFail:error];
}

- (void)didTimeoutLoginForCredentials:(ZMCredentials *)credentials
{
    ZMLogDebug(@"%@", NSStringFromSelector(_cmd));
    if((self.currentPhase == ZMAuthenticationPhaseLoginWithEmail || self.currentPhase == ZMAuthenticationPhaseLoginWithPhone)
       && self.loginCredentials == credentials)
    {
        self.loginCredentials = nil;
        [ZMUserSessionAuthenticationNotification notifyAuthenticationDidFail:[NSError userSessionErrorWithErrorCode:ZMUserSessionNetworkError userInfo:nil]];
    }
    ZMLogDebug(@"current phase: %lu", (unsigned long)self.currentPhase);
}

- (void)didCompletePhoneVerificationSuccessfully
{
    ZMLogDebug(@"%@", NSStringFromSelector(_cmd));
    [self resetLoginAndRegistrationStatus];
    [ZMUserSessionRegistrationNotification notifyPhoneNumberVerificationDidSucceed];
    ZMLogDebug(@"current phase: %lu", (unsigned long)self.currentPhase);
}

- (void)didFailPhoneVerificationForRegistration:(NSError *)error
{
    ZMLogDebug(@"%@", NSStringFromSelector(_cmd));
    [self resetLoginAndRegistrationStatus];
    [ZMUserSessionRegistrationNotification notifyPhoneNumberVerificationDidFail:error];
    ZMLogDebug(@"current phase: %lu", (unsigned long)self.currentPhase);
}

- (void)loginSucceed
{
    ZMLogDebug(@"%@", NSStringFromSelector(_cmd));
    if (self.isWaitingForLogin) {
        self.isWaitingForLogin = NO;
    }
    ZMLogDebug(@"current phase: %lu", (unsigned long)self.currentPhase);
}

- (void)didFailLoginWithPhone:(BOOL)invalidCredentials
{
    ZMLogDebug(@"%@ invalid credentials: %d", NSStringFromSelector(_cmd), invalidCredentials);
    BOOL isDuplicated = self.duplicateRegistrationPhoneNumber;
    [self resetLoginAndRegistrationStatus];
    
    if(isDuplicated) {
        NSError *error = [NSError userSessionErrorWithErrorCode:ZMUserSessionPhoneNumberIsAlreadyRegistered userInfo:nil];
        
        [ZMUserSessionRegistrationNotification notifyRegistrationDidFail:error];
    }
    else {
        NSError *error = [NSError userSessionErrorWithErrorCode:(invalidCredentials ? ZMUserSessionInvalidCredentials : ZMUserSessionUnkownError) userInfo:nil];

        [ZMUserSessionAuthenticationNotification notifyAuthenticationDidFail:error];
    }
    ZMLogDebug(@"current phase: %lu", (unsigned long)self.currentPhase);
}

- (void)didFailLoginWithEmail:(BOOL)invalidCredentials
{
    ZMLogDebug(@"%@ invalid credentials: %d", NSStringFromSelector(_cmd), invalidCredentials);
    if(self.duplicateRegistrationEmail) {
        [ZMUserSessionRegistrationNotification notifyRegistrationDidFail:[NSError userSessionErrorWithErrorCode:ZMUserSessionEmailIsAlreadyRegistered userInfo:@{}]];
    }
    else {
        NSError *error = [NSError userSessionErrorWithErrorCode:(invalidCredentials ? ZMUserSessionInvalidCredentials : ZMUserSessionUnkownError) userInfo:nil];
        [ZMUserSessionAuthenticationNotification notifyAuthenticationDidFail:error];
    }
    [self resetLoginAndRegistrationStatus];
    ZMLogDebug(@"current phase: %lu", (unsigned long)self.currentPhase);
}

- (void)didFailLoginWithEmailBecausePendingValidation
{
    ZMLogDebug(@"%@", NSStringFromSelector(_cmd));
    self.isWaitingForEmailVerification = YES;
    NSError *error = [NSError userSessionErrorWithErrorCode:ZMUserSessionAccountIsPendingActivation userInfo:nil];
    [ZMUserSessionAuthenticationNotification notifyAuthenticationDidFail:error];
    ZMLogDebug(@"current phase: %lu", (unsigned long)self.currentPhase);
}

- (void)cancelWaitingForEmailVerification
{
    ZMLogDebug(@"%@", NSStringFromSelector(_cmd));
    [self resetLoginAndRegistrationStatus];
    ZMLogDebug(@"current phase: %lu", (unsigned long)self.currentPhase);
}

- (void)didCompleteRequestForPhoneRegistrationCodeSuccessfully;
{
    ZMLogDebug(@"%@", NSStringFromSelector(_cmd));
    self.registrationPhoneNumberThatNeedsAValidationCode = nil;
    [ZMUserSessionRegistrationNotification notifyPhoneNumberVerificationCodeRequestDidSucceed];
    ZMLogDebug(@"current phase: %lu", (unsigned long)self.currentPhase);
}

- (void)setAuthenticationCookieData:(NSData *)data;
{
    ZMLogDebug(@"Setting cookie data: %@", data != nil ? @"Nil" : @"Not nil");
    self.cookie.data = data;
    ZMLogDebug(@"current phase: %lu", (unsigned long)self.currentPhase);
}

- (void)didCompleteRequestForLoginCodeSuccessfully
{
    ZMLogDebug(@"%@", NSStringFromSelector(_cmd));
    [ZMUserSessionAuthenticationNotification notifyLoginCodeRequestDidSucceed];
    self.loginPhoneNumberThatNeedsAValidationCode = nil;
    ZMLogDebug(@"current phase: %lu", (unsigned long)self.currentPhase);
}

- (void)didFailRequestForLoginCode:(NSError *)error;
{
    ZMLogDebug(@"%@", NSStringFromSelector(_cmd));
    self.loginPhoneNumberThatNeedsAValidationCode = nil;
    [ZMUserSessionAuthenticationNotification notifyLoginCodeRequestDidFail:error];
    ZMLogDebug(@"current phase: %lu", (unsigned long)self.currentPhase);
}

@end


@implementation ZMAuthenticationStatus (CredentialProvider)

- (void)credentialsMayBeCleared
{
    if (self.currentPhase == ZMAuthenticationPhaseAuthenticated) {
        [self resetLoginAndRegistrationStatus];
    }
}

- (ZMEmailCredentials *)emailCredentials
{
    if (self.loginCredentials.credentialWithEmail) {
        return [ZMEmailCredentials credentialsWithEmail:self.loginCredentials.email
                                               password:self.loginCredentials.password];
    }
    return nil;
}

@end

