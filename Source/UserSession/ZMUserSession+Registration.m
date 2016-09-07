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
@import ZMCSystem;
@import ZMCDataModel;
@import WireRequestStrategy;

#import "ZMUserSession+Internal.h"
#import "ZMUserSession+Registration.h"
#import "ZMUserSession+Authentication.h"
#import "NSError+ZMUserSessionInternal.h"
#import "ZMUserSessionRegistrationNotification.h"
#import "ZMCredentials.h"
#import "ZMUserSessionRegistrationNotification.h"

@implementation ZMUser (ZMRegistrationUser)

- (void)updateFromRegistrationUser:(ZMCompleteRegistrationUser *)registrationUser {
    self.name = registrationUser.name;
    if(registrationUser.originalProfileImageData != nil) {
        self.originalProfileImageData = registrationUser.originalProfileImageData;
    }
    self.phoneNumber = registrationUser.phoneNumber;
    self.emailAddress = registrationUser.emailAddress;
    self.accentColorValue = registrationUser.accentColorValue;
}

@end


@implementation ZMUserSession (Registration)

- (BOOL)registeredOnThisDevice {
    return self.authenticationStatus.registeredOnThisDevice;
}

- (void)registerSelfUser:(ZMCompleteRegistrationUser * __unused)registrationUser
{
    NSString *password = registrationUser.password;
    NSString *phoneNumber = registrationUser.phoneNumber;
    NSString *phoneVerificationCode = registrationUser.phoneVerificationCode;
    NSString *invitationCode = registrationUser.invitationCode;
        
    if (phoneNumber == nil && (password == nil || ! [ZMUser validatePassword:&password error:NULL])) {
        [ZMUserSessionRegistrationNotification notifyRegistrationDidFail:[NSError userSessionErrorWithErrorCode:ZMUserSessionNeedsCredentials userInfo:nil]];
        return;
    }
    if (invitationCode == nil && phoneNumber != nil && ![ZMUser validatePhoneVerificationCode:&phoneVerificationCode error:NULL]) {
        [ZMUserSessionRegistrationNotification notifyRegistrationDidFail:[NSError userSessionErrorWithErrorCode:ZMUserSessionNeedsCredentials userInfo:nil]];
    }
    if (phoneNumber != nil && (![ZMUser validatePhoneNumber:&phoneNumber error:NULL])) {
        [ZMUserSessionRegistrationNotification notifyRegistrationDidFail:[NSError userSessionErrorWithErrorCode:ZMUserSessionNeedsCredentials userInfo:nil]];
        return;
    }
    
    ZMUser *selfUser = [ZMUser selfUserInContext:self.managedObjectContext];
    [selfUser updateFromRegistrationUser:registrationUser];
    [self.managedObjectContext saveOrRollback];
    
    [self.syncManagedObjectContext performGroupedBlock:^{
        [self.authenticationStatus prepareForRegistrationOfUser:registrationUser];
        
        [ZMRequestAvailableNotification notifyNewRequestsAvailable:self];
    }];
}

- (void)cancelWaitForEmailVerification {
    [self.syncManagedObjectContext performGroupedBlock:^{
        [self.authenticationStatus cancelWaitingForEmailVerification];
    }];
}

- (void)cancelWaitForPhoneVerification {
    //no op
}

- (void)requestPhoneVerificationCodeForRegistration:(NSString *)phoneNumber
{
    [self.syncManagedObjectContext performGroupedBlock:^{
        [self.authenticationStatus prepareForRequestingPhoneVerificationCodeForRegistration:phoneNumber];
        [ZMRequestAvailableNotification notifyNewRequestsAvailable:self];
    }];
}

- (void)verifyPhoneNumberForRegistration:(NSString *)phoneNumber verificationCode:(NSString *)verificationCode
{
    [self.syncManagedObjectContext performGroupedBlock:^{
        [self.authenticationStatus prepareForRegistrationPhoneVerificationWithCredentials:[ZMPhoneCredentials credentialsWithPhoneNumber:phoneNumber verificationCode:verificationCode]];
        [ZMRequestAvailableNotification notifyNewRequestsAvailable:self];
    }];
}

- (void)resendRegistrationVerificationEmail
{
    [ZMUserSessionRegistrationNotification resendValidationForRegistrationEmail];
}

- (id<ZMRegistrationObserverToken>)addRegistrationObserver:(id<ZMRegistrationObserver>)observer
{
    ZM_WEAK(observer);
    return [ZMUserSessionRegistrationNotification addObserverWithBlock:^(ZMUserSessionRegistrationNotification *note) {
        ZM_STRONG(observer);
        switch (note.type) {
            case ZMRegistrationNotificationEmailVerificationDidFail:
                if ([observer respondsToSelector:@selector(emailVerificationDidFail:)]) {
                    [observer emailVerificationDidFail:note.error];
                }
                break;
            case ZMRegistrationNotificationEmailVerificationDidSucceed:
                if ([observer respondsToSelector:@selector(emailVerificationDidSucceed)]) {
                    [observer emailVerificationDidSucceed];
                }
                break;
            case ZMRegistrationNotificationPhoneNumberVerificationDidFail:
                if ([observer respondsToSelector:@selector(phoneVerificationDidFail:)]) {
                    [observer phoneVerificationDidFail:note.error];
                }
                break;
            case ZMRegistrationNotificationPhoneNumberVerificationCodeRequestDidFail:
                if ([observer respondsToSelector:@selector(phoneVerificationCodeRequestDidFail:)]) {
                    [observer phoneVerificationCodeRequestDidFail:note.error];
                }
                break;
            case ZMRegistrationNotificationPhoneNumberVerificationDidSucceed:
                if ([observer respondsToSelector:@selector(phoneVerificationDidSucceed)]) {
                    [observer phoneVerificationDidSucceed];
                }
                break;
            case ZMRegistrationNotificationRegistrationDidFail:
                if ([observer respondsToSelector:@selector(registrationDidFail:)]) {
                    [observer registrationDidFail:note.error];
                }
                break;
            case ZMRegistrationNotificationPhoneNumberVerificationCodeRequestDidSucceed:
                if ([observer respondsToSelector:@selector(phoneVerificationCodeRequestDidSucceed)]) {
                    [observer phoneVerificationCodeRequestDidSucceed];
                }
        }
    }];
}

- (void)removeRegistrationObserverForToken:(id<ZMRegistrationObserverToken>)token
{
    [ZMUserSessionRegistrationNotification removeObserver:token];
}

@end
