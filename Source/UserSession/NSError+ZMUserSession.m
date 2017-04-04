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


@import WireTransport;

#import "NSError+ZMUserSession.h"


NSString * const ZMUserSessionErrorDomain = @"ZMUserSession";
NSString * const ZMClientsKey = @"clients";

static NSString *LocalizedDescriptionStringFromZMUserSessionErrorCode(ZMUserSessionErrorCode code)
{
    struct TypeMap {
        NSUInteger code;
        CFStringRef name;
    } const TypeMapping[] = {
        { ZMUserSessionNoError, CFSTR("User session no error") },
        { ZMUserSessionUnkownError, CFSTR("User session unkown error") },
        { ZMUserSessionNeedsCredentials, CFSTR("User session needs credentials") },
        { ZMUserSessionInvalidCredentials, CFSTR("User session invalid credentials") },
        { ZMUserSessionAccountIsPendingActivation, CFSTR("User session account is pending activation") },
        { ZMUserSessionNetworkError, CFSTR("User session network error") },
        { ZMUserSessionEmailIsAlreadyRegistered, CFSTR("User session email is already registered") },
        { ZMUserSessionRegistrationDidFailWithUnknownError, CFSTR("User session registration did fail with unknown error") },
    };
    
    for (size_t i = 0; i < (sizeof(TypeMapping)/sizeof(*TypeMapping)); ++i) {
        if (TypeMapping[i].code == code) {
            return (__bridge NSString *) TypeMapping[i].name;
        }
    }
    return nil;
}


@implementation NSError (ZMUserSession)

- (ZMUserSessionErrorCode)userSessionErrorCode
{
    if (! [self.domain isEqualToString:ZMUserSessionErrorDomain]) {
        return ZMUserSessionNoError;
    } else {
        return (ZMUserSessionErrorCode) self.code;
    }
}

@end



@implementation NSError (ZMUserSessionInteral)

+ (instancetype)userSessionErrorWithErrorCode:(ZMUserSessionErrorCode)code userInfo:(NSDictionary *)userInfo
{
    NSMutableDictionary *newUserInfo = [NSMutableDictionary dictionaryWithDictionary:userInfo];
    NSString *description = LocalizedDescriptionStringFromZMUserSessionErrorCode(code);
    if (description != nil) {
        newUserInfo[NSLocalizedDescriptionKey] = description;
    }
    return [NSError errorWithDomain:ZMUserSessionErrorDomain code:code userInfo:newUserInfo];
}

+ (instancetype)pendingLoginErrorWithResponse:(ZMTransportResponse *)response
{
    if (response.HTTPStatus == 403 && [[response payloadLabel] isEqualToString:@"pending-login"]) {
        return [NSError userSessionErrorWithErrorCode:ZMUserSessionCodeRequestIsAlreadyPending userInfo:nil];
    }
    return nil;
}

+ (instancetype)unauthorizedErrorWithResponse:(ZMTransportResponse *)response
{
    if (response.HTTPStatus == 403 && [[response payloadLabel] isEqualToString:@"unauthorized"]) {
        return [NSError userSessionErrorWithErrorCode:ZMUserSessionInvalidPhoneNumber userInfo:nil];
    }
    return nil;
}

+ (instancetype)invalidPhoneVerificationCodeErrorWithResponse:(ZMTransportResponse *)response
{
    if (response.HTTPStatus == 404 && [[response payloadLabel] isEqualToString:@"invalid-code"]) {
        return [NSError userSessionErrorWithErrorCode:ZMUserSessionInvalidPhoneNumberVerificationCode userInfo:nil];
    }
    return nil;
}

+ (instancetype)invalidPhoneNumberErrorWithReponse:(ZMTransportResponse *)response
{
    if (response.HTTPStatus == 400 && ([[response payloadLabel] isEqualToString:@"invalid-phone"] || [[response payloadLabel] isEqualToString:@"bad-request"])) {
        return [NSError userSessionErrorWithErrorCode:ZMUserSessionInvalidPhoneNumber userInfo:nil];
    }
    return nil;
}

+ (instancetype)phoneNumberIsAlreadyRegisteredErrorWithResponse:(ZMTransportResponse *)response
{
    if (response.HTTPStatus == 409) {
        return [NSError userSessionErrorWithErrorCode:ZMUserSessionPhoneNumberIsAlreadyRegistered userInfo:nil];
    }
    return nil;
}

+ (instancetype)invalidEmailWithResponse:(ZMTransportResponse *)response
{
    if (response.HTTPStatus == 400 && [[response payloadLabel] isEqualToString:@"invalid-email"]) {
        return [NSError userSessionErrorWithErrorCode:ZMUserSessionInvalidEmail userInfo:nil];
    }
    return nil;
}

+ (instancetype)keyExistsErrorWithResponse:(ZMTransportResponse *)response
{
    if (response.HTTPStatus == 409 && [[response payloadLabel] isEqualToString:@"key-exists"]) {
        return [NSError userSessionErrorWithErrorCode:ZMUserSessionEmailIsAlreadyRegistered userInfo:nil];
    }
    return nil;
}

+ (instancetype)invalidInvitationCodeWithResponse:(ZMTransportResponse *)response
{
    if (response.HTTPStatus == 400 && [[response payloadLabel] isEqualToString:@"invalid-invitation-code"]) {
        return [NSError userSessionErrorWithErrorCode:ZMUserSessionInvalidInvitationCode userInfo:nil];
    }
    return nil;
}

+ (instancetype)lastUserIdentityCantBeRemovedWithResponse:(ZMTransportResponse *)response
{
    if (response.HTTPStatus == 403 && [[response payloadLabel] isEqualToString:@"last-identity"]) {
        return [NSError userSessionErrorWithErrorCode:ZMUserSessionLastUserIdentityCantBeDeleted userInfo:nil];
    }
    return nil;
}

@end
