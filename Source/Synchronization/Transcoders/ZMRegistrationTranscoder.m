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


@import WireUtilities;
@import WireTransport;
@import WireDataModel;

#import <WireSyncEngine/WireSyncEngine-Swift.h>

#import "ZMRegistrationTranscoder.h"
#import "ZMAuthenticationStatus.h"
#import "ZMCredentials.h"
#import "ZMUserSessionRegistrationNotification.h"
#import "NSError+ZMUserSessionInternal.h"

@interface  ZMRegistrationTranscoder ()

@property (nonatomic, readonly) ZMSingleRequestSync *registrationSync;
@property (nonatomic, weak) ZMAuthenticationStatus * authenticationStatus;

@end

@interface  ZMRegistrationTranscoder (SingleRequestTranscoder) <ZMSingleRequestTranscoder>
@end

@interface  ZMRegistrationTranscoder (AuthenticationStatusObserver) <ZMAuthenticationStatusObserver>
@end

@implementation ZMRegistrationTranscoder

- (instancetype)initWithManagedObjectContext:(NSManagedObjectContext *)moc applicationStatusDirectory:(ZMApplicationStatusDirectory *)applicationStatusDirectory
{
    self = [super initWithManagedObjectContext:moc applicationStatus:applicationStatusDirectory];
    
    if (self != nil) {
        _registrationSync = [ZMSingleRequestSync syncWithSingleRequestTranscoder:self managedObjectContext:self.managedObjectContext];
        self.authenticationStatus = applicationStatusDirectory.authenticationStatus;
        [applicationStatusDirectory.authenticationStatus addAuthenticationCenterObserver:self];
    }
    return self;
}

- (ZMStrategyConfigurationOption)configuration
{
    return ZMStrategyConfigurationOptionAllowsRequestsWhileUnauthenticated;
}

 - (ZMTransportRequest *)nextRequestIfAllowed
{
    if (self.isInRegistrationPhase) {
        return self.registrationSync.nextRequest;
    } else {
        return nil;
    }
}

- (void)processEvents:(NSArray<ZMUpdateEvent *> __unused *)events
           liveEvents:(BOOL __unused)liveEvents
       prefetchResult:(__unused ZMFetchRequestBatchResult *)prefetchResult;
{
    // no op
}

- (NSArray *)contextChangeTrackers
{
    return [NSArray array];
}

- (void)resetRegistrationState;
{
    [self.registrationSync resetCompletionState];
    [self.registrationSync readyForNextRequest];
}

- (BOOL)isInRegistrationPhase
{
    ZMAuthenticationPhase authenticationPhase = self.authenticationStatus.currentPhase;
    return authenticationPhase == ZMAuthenticationPhaseRegisterWithEmail || authenticationPhase == ZMAuthenticationPhaseRegisterWithPhone;
}

@end


@implementation ZMRegistrationTranscoder (SingleRequestTranscoder)

- (ZMTransportRequest *)requestForSingleRequestSync:(ZMSingleRequestSync *)sync;
{
    ZMAuthenticationStatus *authStatus  = self.authenticationStatus;

    VerifyReturnNil(sync == self.registrationSync);
    
    NSString *password = authStatus.registrationUser.password;
    NSString *phone = authStatus.registrationUser.phoneNumber;
    NSString *phoneCode = authStatus.registrationUser.phoneVerificationCode;
    NSString *email = authStatus.registrationUser.emailAddress;
    NSString *name = authStatus.registrationUser.name;
    NSString *invitationCode = authStatus.registrationUser.invitationCode;
    NSString *cookieLabel = authStatus.cookieLabel;
    
    ZMAccentColor accentColor = authStatus.registrationUser.accentColorValue;
    
    NSMutableDictionary *payload = [@{
                                     @"name" : name ?: [NSNull null],
                                     @"accent_id" : @(accentColor),
                                     } mutableCopy];
    
    if(email != nil && password != nil) {
        payload[@"email"] = email;
        payload[@"password"] = password;
    } else if(phone != nil && (phoneCode != nil || invitationCode != nil)) {
        payload[@"phone"] = phone;
        payload[@"phone_code"] = phoneCode;
    }
    payload[@"locale"] = [NSLocale formattedLocaleIdentifier];
    
    if (invitationCode != nil) {
        payload[@"invitation_code"] = invitationCode;
    }
    if (cookieLabel != nil) {
        payload[@"label"] = cookieLabel;
    }
    
    //for phone number we will have another end point or different payload
    ZMTransportRequest *request = [[ZMTransportRequest alloc] initWithPath:@"/register" method:ZMMethodPOST payload:payload authentication:ZMTransportRequestAuthNone];
    return request;
}

- (void)didReceiveResponse:(ZMTransportResponse *)response forSingleRequest:(ZMSingleRequestSync *)sync
{
    NOT_USED(sync);
    if (response.result == ZMTransportResponseStatusSuccess) {
        ZMUser *user = [ZMUser selfUserInContext:self.managedObjectContext];
        [user updateWithTransportData:[response.payload asDictionary] authoritative:YES];
        // I want to unset the user ID until we log in
        user.remoteIdentifier = nil;
        [self.authenticationStatus didCompleteRegistrationSuccessfully];
    }
    else if (response.result == ZMTransportResponseStatusPermanentError) {
        //if email is duplicated backed return 400 and json with key-exists label
        ZMAuthenticationStatus * authenticationStatus = self.authenticationStatus;
        
        if([[response payloadLabel] isEqualToString:@"key-exists"]) {
            [authenticationStatus didFailRegistrationWithDuplicatedEmail];
        }
        else {
            NSError *error = {
                [NSError invalidEmailWithResponse:response] ?:
                [NSError invalidPhoneNumberErrorWithReponse:response] ?:
                [NSError invalidInvitationCodeWithResponse:response] ?:
                [NSError userSessionErrorWithErrorCode:ZMUserSessionUnkownError userInfo:nil]
            };
            [authenticationStatus didFailRegistrationForOtherReasons:error];
        }
    }
}

@end


@implementation ZMRegistrationTranscoder (AuthenticationStatusObserver)

- (void)didChangeAuthenticationData
{
    if (self.isInRegistrationPhase) {
        [self resetRegistrationState];
    }
}

@end
