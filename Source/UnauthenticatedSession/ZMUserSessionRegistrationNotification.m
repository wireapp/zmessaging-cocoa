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

#import "ZMUserSessionRegistrationNotification.h"

static NSString * const UserSessionRegistrationNotificationName = @"ZMUserSessionRegistrationNotification";
static NSString * const VerificationEmailResendRequestNotificationName = @"ZMVerificationEmailResendRequest";

@interface ZMUserSessionRegistrationNotification()

@end

@implementation ZMUserSessionRegistrationNotification

- (instancetype)init
{
    return [super initWithName:UserSessionRegistrationNotificationName object:nil];
}

+ (void)notifyRegistrationDidFail:(NSError *)error
{
    NSCParameterAssert(error);
    ZMUserSessionRegistrationNotification *note = [ZMUserSessionRegistrationNotification new];
    note.error = error;
    note.type = ZMRegistrationNotificationRegistrationDidFail;
    [[NSNotificationCenter defaultCenter] postNotification:note];
}

+ (void)notifyPhoneNumberVerificationDidFail:(NSError *)error
{
    NSCParameterAssert(error);
    ZMUserSessionRegistrationNotification *note = [ZMUserSessionRegistrationNotification new];
    note.error = error;
    note.type = ZMRegistrationNotificationPhoneNumberVerificationDidFail;
    [[NSNotificationCenter defaultCenter] postNotification:note];
}

+ (void)notifyPhoneNumberVerificationCodeRequestDidFail:(NSError *)error
{
    NSCParameterAssert(error);
    ZMUserSessionRegistrationNotification *note = [ZMUserSessionRegistrationNotification new];
    note.error = error;
    note.type = ZMRegistrationNotificationPhoneNumberVerificationCodeRequestDidFail;
    [[NSNotificationCenter defaultCenter] postNotification:note];
}

+ (void)notifyPhoneNumberVerificationCodeRequestDidSucceed;
{
    ZMUserSessionRegistrationNotification *note = [ZMUserSessionRegistrationNotification new];
    note.type = ZMRegistrationNotificationPhoneNumberVerificationCodeRequestDidSucceed;
    [[NSNotificationCenter defaultCenter] postNotification:note];
}

+ (void)notifyEmailVerificationDidSucceed
{
    ZMUserSessionRegistrationNotification *note = [ZMUserSessionRegistrationNotification new];
    note.type = ZMRegistrationNotificationEmailVerificationDidSucceed;
    [[NSNotificationCenter defaultCenter] postNotification:note];
}

+ (void)notifyPhoneNumberVerificationDidSucceed
{
    ZMUserSessionRegistrationNotification *note = [ZMUserSessionRegistrationNotification new];
    note.type = ZMRegistrationNotificationPhoneNumberVerificationDidSucceed;
    [[NSNotificationCenter defaultCenter] postNotification:note];
}

+ (id<ZMRegistrationObserverToken>)addObserverWithBlock:(void(^)(ZMUserSessionRegistrationNotification *))block
{
    return (id<ZMRegistrationObserverToken>)[[NSNotificationCenter defaultCenter] addObserverForName:UserSessionRegistrationNotificationName object:nil queue:[NSOperationQueue currentQueue] usingBlock:^(NSNotification *note) {
        block((ZMUserSessionRegistrationNotification *)note);
    }];
}

+ (void)removeObserver:(id<ZMRegistrationObserverToken>)token
{
    [[NSNotificationCenter defaultCenter] removeObserver:token];
}

@end



@implementation ZMUserSessionRegistrationNotification (ResendVerificationEmail)

+ (void)resendValidationForRegistrationEmail;
{
    [[NSNotificationCenter defaultCenter] postNotificationName:VerificationEmailResendRequestNotificationName object:nil];
}

+ (id)addObserverForRequestForVerificationEmail:(id<ZMRequestVerificationEmailObserver>)observer ZM_MUST_USE_RETURN;
{
    ZM_WEAK(observer);
    return [[NSNotificationCenter defaultCenter] addObserverForName:VerificationEmailResendRequestNotificationName object:nil queue:[NSOperationQueue currentQueue] usingBlock:^(NSNotification * __unused note) {
        ZM_STRONG(observer);
        [observer didReceiveRequestToResendValidationEmail];
        
    }];
}

+ (void)removeObserverForRequestForVerificationEmail:(id)token;
{
    [[NSNotificationCenter defaultCenter] removeObserver:token];
}

@end


