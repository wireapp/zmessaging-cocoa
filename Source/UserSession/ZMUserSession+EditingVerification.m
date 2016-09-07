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


@import ZMCDataModel;
#import "ZMUserSession+Internal.h"
#import "ZMUserSession+EditingVerification.h"
#import "ZMUserProfileUpdateStatus.h"

@implementation ZMUserSession (EditingVerification)

- (NSString *)currentlyUpdatingEmail
{
    ZMUser *selfUser = [ZMUser selfUserInUserSession:self];
    return (selfUser.emailAddress.length == 0) ? self.userProfileUpdateStatus.emailToUpdate : nil;
}

- (NSString *)currentlyUpdatingPhone
{
    ZMUser *selfUser = [ZMUser selfUserInUserSession:self];
    return (selfUser.phoneNumber == nil) ?
    (self.userProfileUpdateStatus.profilePhoneNumberThatNeedsAValidationCode ?: self.userProfileUpdateStatus.phoneCredentialsToUpdate.phoneNumber)
    : nil;
}

/// Send email verification and set the password when user changes/adds email to the existing profile
- (void)requestVerificationEmailForEmailUpdate:(ZMEmailCredentials *)credentials;
{
    [self.syncManagedObjectContext performGroupedBlock:^{
        [self.userProfileUpdateStatus prepareForEmailAndPasswordChangeWithCredentials:credentials];
        [ZMRequestAvailableNotification notifyNewRequestsAvailable:self];
    }];
}

/// Send email verification and set the password when user changes/adds email to the existing profile
- (void)requestVerificationCodeForPhoneNumberUpdate:(NSString *)phoneNumber {
    [self.syncManagedObjectContext performGroupedBlock:^{
        [self.userProfileUpdateStatus prepareForRequestingPhoneVerificationCodeForRegistration:phoneNumber];
        [ZMRequestAvailableNotification notifyNewRequestsAvailable:self];
    }];
}

/// Verify phone number for profile
- (void)verifyPhoneNumberForUpdate:(ZMPhoneCredentials *)credentials;
{
    [self.syncManagedObjectContext performGroupedBlock:^{
        [self.userProfileUpdateStatus prepareForPhoneChangeWithCredentials:credentials];
        [ZMRequestAvailableNotification notifyNewRequestsAvailable:self];
    }];
}

- (id<ZMUserEditingObserverToken>)addUserEditingObserver:(id<ZMUserEditingObserver>)observer {
    
    return (id)[ZMUserProfileUpdateNotification addObserverWithBlock:^(ZMUserProfileUpdateNotification *note) {
        switch(note.type) {
            case ZMUserProfileNotificationEmailUpdateDidFail:
                [observer emailUpdateDidFail:note.error];
                break;
            case ZMUserProfileNotificationPhoneNumberVerificationCodeRequestDidFail:
                [observer phoneNumberVerificationCodeRequestDidFail:note.error];
                break;
            case ZMUserProfileNotificationPhoneNumberVerificationDidFail:
                [observer phoneNumberVerificationDidFail:note.error];
                break;
            case ZMUserProfileNotificationPasswordUpdateDidFail:
                [observer passwordUpdateRequestDidFail];
                break;
            case ZMUserProfileNotificationPhoneNumberVerificationCodeRequestDidSucceed:
                [observer phoneNumberVerificationCodeRequestDidSucceed];
                break;
            case ZMUserProfileNotificationEmailDidSendVerification:
                [observer didSentVerificationEmail];
                break;
        }
    }];
}

- (void)removeUserEditingObserverForToken:(id<ZMUserEditingObserverToken>)observerToken {
    [ZMUserProfileUpdateNotification removeObserver:(id)observerToken];
}

@end