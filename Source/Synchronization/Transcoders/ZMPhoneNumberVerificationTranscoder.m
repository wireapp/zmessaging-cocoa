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
@import WireUtilities;
@import WireTransport;

#import <WireSyncEngine/WireSyncEngine-Swift.h>

#import "ZMPhoneNumberVerificationTranscoder.h"
#import "ZMAuthenticationStatus.h"
#import "ZMCredentials+Internal.h"
#import "ZMUserSessionRegistrationNotification.h"
#import "NSError+ZMUserSessionInternal.h"
#import "ZMUserSessionRegistrationNotification.h"

@interface ZMPhoneNumberVerificationTranscoder() <ZMSingleRequestTranscoder>

@property (nonatomic) ZMSingleRequestSync *codeRequestSync;
@property (nonatomic) ZMSingleRequestSync *codeVerificationSync;
@property (nonatomic, weak) id<ZMSGroupQueue> groupQueue;
@property (nonatomic, weak) ZMAuthenticationStatus *authenticationStatus;

@end

@implementation ZMPhoneNumberVerificationTranscoder

- (instancetype)initWithGroupQueue:(id<ZMSGroupQueue>)groupQueue authenticationStatus:(ZMAuthenticationStatus *)authenticationStatus;
{
    self = [super init];
    if (self) {
        self.groupQueue = groupQueue;
        self.codeRequestSync = [[ZMSingleRequestSync alloc] initWithSingleRequestTranscoder:self groupQueue:groupQueue];
        [self.codeRequestSync readyForNextRequest];
        self.codeVerificationSync = [[ZMSingleRequestSync alloc] initWithSingleRequestTranscoder:self groupQueue:groupQueue];
        self.authenticationStatus = authenticationStatus;
    }
    return self;
}

- (ZMTransportRequest *)nextRequest
{
    ZMAuthenticationPhase currentAuthPhase  = self.authenticationStatus.currentPhase;

    if (currentAuthPhase == ZMAuthenticationPhaseRequestPhoneVerificationCodeForRegistration) {
        [self.codeRequestSync readyForNextRequestIfNotBusy];
        return [self.codeRequestSync nextRequest];
    }
    if (currentAuthPhase == ZMAuthenticationPhaseVerifyPhoneForRegistration) {
        [self.codeVerificationSync readyForNextRequestIfNotBusy];
        return [self.codeVerificationSync nextRequest];
    }
    return nil;
}

- (void)verifyPhoneNumber
{
    [self.codeVerificationSync readyForNextRequest];
}

- (void)resetVerificationState
{
    [self.codeRequestSync resetCompletionState];
    [self.codeVerificationSync resetCompletionState];
    [self.codeRequestSync readyForNextRequest];
    [self.codeVerificationSync readyForNextRequest];
}

- (BOOL)isVerificationCodeRequestIsNotSent;
{
    ZMSingleRequestProgress status = self.codeRequestSync.status;
    return status == ZMSingleRequestIdle;
}

- (BOOL)isVerificationCodeRequestCompleted;
{
    ZMSingleRequestProgress status = self.codeRequestSync.status;
    return status == ZMSingleRequestCompleted;
}

- (BOOL)isPhoneNumberActivationRequestIsNotSent;
{
    ZMSingleRequestProgress status = self.codeVerificationSync.status;
    return status == ZMSingleRequestIdle;
}

#pragma mark - ZMSingleRequestTranscoder

- (ZMTransportRequest *)requestForSingleRequestSync:(ZMSingleRequestSync *)sync;
{
    ZMAuthenticationStatus * authenticationStatus = self.authenticationStatus;
    NSDictionary *payload;
    NSString *path;
    if (sync == self.codeRequestSync) {
        path = @"/activate/send";
        payload = @{@"phone": authenticationStatus.registrationPhoneNumberThatNeedsAValidationCode,
                    @"locale": [NSLocale formattedLocaleIdentifier]};
    }
    else {
        path = @"/activate";
        payload = @{@"phone": authenticationStatus.registrationPhoneValidationCredentials.phoneNumber,
                    @"code": authenticationStatus.registrationPhoneValidationCredentials.phoneNumberVerificationCode,
                    @"dryrun": @(YES)};
    }
    ZMTransportRequest *request = [[ZMTransportRequest alloc] initWithPath:path method:ZMMethodPOST payload:payload authentication:ZMTransportRequestAuthNone];
    return request;
}

- (void)didReceiveResponse:(ZMTransportResponse *)response forSingleRequest:(ZMSingleRequestSync *)sync;
{
    ZMAuthenticationStatus * authenticationStatus = self.authenticationStatus;
    
    if (sync == self.codeRequestSync) {
        if (response.result == ZMTransportResponseStatusPermanentError) {
            NSError *error = {
                [NSError phoneNumberIsAlreadyRegisteredErrorWithResponse:response] ?:
                [NSError invalidPhoneNumberErrorWithReponse:response] ?:
                [NSError userSessionErrorWithErrorCode:ZMUserSessionUnknownError userInfo:nil]
            };
            [authenticationStatus didFailRequestForPhoneRegistrationCode:error];
        }
        else {
            [authenticationStatus didCompleteRequestForPhoneRegistrationCodeSuccessfully];
        }
    }
    else if (sync == self.codeVerificationSync) {
        
        if (response.result == ZMTransportResponseStatusSuccess) {
            [authenticationStatus didCompletePhoneVerificationSuccessfully];
        }
        else {
            NSError *error = {
                [NSError invalidPhoneVerificationCodeErrorWithResponse:response] ?:
                [NSError userSessionErrorWithErrorCode:ZMUserSessionUnknownError userInfo:nil]
            };
            [authenticationStatus didFailPhoneVerificationForRegistration:error];
        }
    }
}


@end
