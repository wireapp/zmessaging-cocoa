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
@import WireSystem;

#import <WireDataModel/ZMNotifications+Internal.h>

@protocol ZMRegistrationObserverToken
@end

typedef NS_ENUM(NSUInteger, ZMUserSessionRegistrationNotificationType) {
    ZMRegistrationNotificationEmailVerificationDidSucceed,
    ZMRegistrationNotificationEmailVerificationDidFail,
    ZMRegistrationNotificationPhoneNumberVerificationDidSucceed,
    ZMRegistrationNotificationPhoneNumberVerificationDidFail,
    ZMRegistrationNotificationPhoneNumberVerificationCodeRequestDidFail,
    ZMRegistrationNotificationPhoneNumberVerificationCodeRequestDidSucceed,
    ZMRegistrationNotificationRegistrationDidFail
};

@interface ZMUserSessionRegistrationNotification : ZMNotification

@property (nonatomic) NSError *error;
@property (nonatomic) ZMUserSessionRegistrationNotificationType type;

/// Notifies all @c ZMAuthenticationObserver that the authentication failed
+ (void)notifyRegistrationDidFail:(NSError *)error;
+ (void)notifyPhoneNumberVerificationDidFail:(NSError *)error;
+ (void)notifyPhoneNumberVerificationCodeRequestDidFail:(NSError *)error;

+ (void)notifyEmailVerificationDidSucceed;
+ (void)notifyPhoneNumberVerificationDidSucceed;
+ (void)notifyPhoneNumberVerificationCodeRequestDidSucceed;

+ (id<ZMRegistrationObserverToken>)addObserverWithBlock:(void(^)(ZMUserSessionRegistrationNotification *))block ZM_MUST_USE_RETURN;
+ (void)removeObserver:(id<ZMRegistrationObserverToken>)token;

@end



@protocol ZMRequestVerificationEmailObserver
- (void)didReceiveRequestToResendValidationEmail;
@end

@protocol ZMRequestVerificationEmailObserverToken
@end


@interface ZMUserSessionRegistrationNotification (VerificationEmail)

+ (void)resendValidationForRegistrationEmail;
+ (id<ZMRequestVerificationEmailObserverToken>)addObserverForRequestForVerificationEmail:(id<ZMRequestVerificationEmailObserver>)observer ZM_MUST_USE_RETURN;
+ (void)removeObserverForRequestForVerificationEmail:(id<ZMRequestVerificationEmailObserverToken>)token;

@end

