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
@import WireRequestStrategy;

#import <WireSyncEngine/WireSyncEngine-Swift.h>

#import "ZMLoginCodeRequestTranscoder.h"
#import "ZMAuthenticationStatus.h"
#import "ZMAuthenticationStatus.h"
#import "ZMCredentials.h"
#import "ZMUserSessionAuthenticationNotification.h"
#import "NSError+ZMUserSessionInternal.h"

@interface ZMLoginCodeRequestTranscoder() <ZMSingleRequestTranscoder>

@property (nonatomic, weak) ZMAuthenticationStatus *authenticationStatus;
@property (nonatomic) ZMSingleRequestSync *codeRequestSync;

@end

@implementation ZMLoginCodeRequestTranscoder

- (instancetype)initWithManagedObjectContext:(NSManagedObjectContext *)moc applicationStatusDirectory:(ZMApplicationStatusDirectory *)applicationStatusDirectory
{
    self = [super initWithManagedObjectContext:moc applicationStatus:applicationStatusDirectory];
    if (self != nil) {
        self.authenticationStatus = applicationStatusDirectory.authenticationStatus;
        self.codeRequestSync = [[ZMSingleRequestSync alloc] initWithSingleRequestTranscoder:self managedObjectContext:moc];
        [self.codeRequestSync readyForNextRequest];
    }
    return self;
}

- (ZMStrategyConfigurationOption)configuration
{
    return ZMStrategyConfigurationOptionAllowsRequestsWhileUnauthenticated;
}

- (ZMTransportRequest *)nextRequestIfAllowed
{
    if (self.authenticationStatus.currentPhase == ZMAuthenticationPhaseRequestPhoneVerificationCodeForLogin) {
        [self.codeRequestSync readyForNextRequestIfNotBusy];
        return [self.codeRequestSync nextRequest];
    }
    return nil;
}

#pragma mark - ZMSingleRequestTranscoder

- (ZMTransportRequest *)requestForSingleRequestSync:(__unused ZMSingleRequestSync *)sync;
{
    ZMTransportRequest *request = [[ZMTransportRequest alloc] initWithPath:@"/login/send"
                                                                    method:ZMMethodPOST
                                                                   payload:@{@"phone": self.authenticationStatus.loginPhoneNumberThatNeedsAValidationCode}
                                                            authentication:ZMTransportRequestAuthNone];
    return request;
}

- (void)didReceiveResponse:(ZMTransportResponse *)response forSingleRequest:(__unused ZMSingleRequestSync *)sync
{
    ZMAuthenticationStatus *authStatus  = self.authenticationStatus;
    if(response.result == ZMTransportResponseStatusSuccess) {
        [authStatus didCompleteRequestForLoginCodeSuccessfully];
    }
    else {
        NSError *error = {
            [NSError pendingLoginErrorWithResponse:response] ?:
            [NSError unauthorizedErrorWithResponse:response] ?:
            [NSError invalidPhoneNumberErrorWithReponse:response] ?:
            [NSError userSessionErrorWithErrorCode:ZMUserSessionUnkownError userInfo:nil]
        };

        [authStatus didFailRequestForLoginCode:error];
    }
}

@end
