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
@import ZMCDataModel;

#import "ZMUserProfileUpdateTranscoder.h"
#import "ZMAuthenticationStatus.h"
#import "ZMCredentials+Internal.h"
#import "ZMUserSessionRegistrationNotification.h"
#import "NSError+ZMUserSessionInternal.h"
#import "ZMUserSessionRegistrationNotification.h"
#import "ZMUserProfileUpdateStatus.h"

@interface ZMUserProfileUpdateTranscoder() <ZMSingleRequestTranscoder, ZMRequestGenerator>

@property (nonatomic) ZMSingleRequestSync *phoneCodeRequestSync;
@property (nonatomic) ZMSingleRequestSync *phoneVerificationSync;
@property (nonatomic) ZMSingleRequestSync *passwordUpdateSync;
@property (nonatomic) ZMSingleRequestSync *emailUpdateSync;

@property (nonatomic, weak) ZMUserProfileUpdateStatus *userProfileUpdateStatus;

@end

@implementation ZMUserProfileUpdateTranscoder

- (instancetype)initWithManagedObjectContext:(NSManagedObjectContext * __unused)moc
{
    RequireString(NO, "Do not use this init");
    return nil;
}

- (instancetype)initWithManagedObjectContext:(NSManagedObjectContext *)moc userProfileUpdateStatus:(ZMUserProfileUpdateStatus *)userProfileUpdateStatus
{
    self = [super initWithManagedObjectContext:moc];
    if(self) {
        self.userProfileUpdateStatus = userProfileUpdateStatus;
        
        self.phoneCodeRequestSync = [[ZMSingleRequestSync alloc] initWithSingleRequestTranscoder:self managedObjectContext:moc];
        self.phoneVerificationSync = [[ZMSingleRequestSync alloc] initWithSingleRequestTranscoder:self managedObjectContext:moc];
        self.passwordUpdateSync = [[ZMSingleRequestSync alloc] initWithSingleRequestTranscoder:self managedObjectContext:moc];
        self.emailUpdateSync = [[ZMSingleRequestSync alloc] initWithSingleRequestTranscoder:self managedObjectContext:moc];
    }
    return self;
}

- (ZMTransportRequest *)requestForSingleRequestSync:(ZMSingleRequestSync *)sync
{
    ZMUserProfileUpdateStatus *strongStatus = self.userProfileUpdateStatus;
    
    if(sync == self.phoneCodeRequestSync)
    {
        return [ZMTransportRequest requestWithPath:@"/self/phone" method:ZMMethodPUT payload:@{@"phone":strongStatus.profilePhoneNumberThatNeedsAValidationCode}];
    }
    
    if(sync == self.phoneVerificationSync)
    {
        return [ZMTransportRequest requestWithPath:@"/activate"
                                            method:ZMMethodPOST
                                           payload:@{
                                                     @"phone":strongStatus.phoneCredentialsToUpdate.phoneNumber,
                                                     @"code":strongStatus.phoneCredentialsToUpdate.phoneNumberVerificationCode,
                                                     @"dryrun":@(NO)
                                                     }];
    }
    
    if(sync == self.passwordUpdateSync)
    {
        NSString *password = strongStatus.passwordToUpdate;
        return [ZMTransportRequest requestWithPath:@"/self/password" method:ZMMethodPUT payload:@{@"new_password":password}];
    }
    
    if(sync == self.emailUpdateSync)
    {
        return [ZMTransportRequest requestWithPath:@"/self/email" method:ZMMethodPUT payload:@{@"email":strongStatus.emailToUpdate}];
    }
    
    return nil;
}

- (BOOL)isSlowSyncDone
{
    return YES;
}

- (void)setNeedsSlowSync
{

}

- (NSArray *)contextChangeTrackers
{
    return @[];
}

- (NSArray *)requestGenerators
{
    return @[self];
}

- (ZMTransportRequest *)nextRequest
{
    ZMUserProfileUpdateStatus *strongStatus = self.userProfileUpdateStatus;

    if(strongStatus.phoneCredentialsToUpdate != nil) {
        [self.phoneVerificationSync readyForNextRequestIfNotBusy];
        return [self.phoneVerificationSync nextRequest];
    }
    
    if(strongStatus.profilePhoneNumberThatNeedsAValidationCode != nil) {
        [self.phoneCodeRequestSync readyForNextRequestIfNotBusy];
        return [self.phoneCodeRequestSync nextRequest];
    }
    
    if(strongStatus.passwordToUpdate != nil) {
        [self.passwordUpdateSync readyForNextRequestIfNotBusy];
        return [self.passwordUpdateSync nextRequest];
    }
    
    if(strongStatus.emailToUpdate != nil) {
        [self.emailUpdateSync readyForNextRequestIfNotBusy];
        return [self.emailUpdateSync nextRequest];
    }
    
    return nil;
}

- (void)processEvents:(NSArray<ZMUpdateEvent *> __unused *)events
           liveEvents:(BOOL __unused)liveEvents
       prefetchResult:(__unused ZMFetchRequestBatchResult *)prefetchResult;
{
    // no-op
}

- (void)didReceiveResponse:(ZMTransportResponse *)response forSingleRequest:(ZMSingleRequestSync *)sync
{
    ZMUserProfileUpdateStatus *strongStatus = self.userProfileUpdateStatus;

    if(sync == self.phoneVerificationSync) {
        if(response.result == ZMTransportResponseStatusSuccess) {
            [strongStatus didVerifyPhoneSuccessfully];
        }
        else {
            [strongStatus didFailPhoneVerification:[NSError userSessionErrorWithErrorCode:ZMUserSessionUnkownError userInfo:nil]];
        }
    }
    else if(sync == self.phoneCodeRequestSync) {
        if(response.result == ZMTransportResponseStatusSuccess) {
            [strongStatus didRequestPhoneVerificationCodeSuccessfully];
        }
        else {
            NSError *error = {
                [NSError phoneNumberIsAlreadyRegisteredErrorWithResponse:response] ?:
                [NSError invalidPhoneNumberErrorWithReponse:response] ?:
                [NSError userSessionErrorWithErrorCode:ZMUserSessionUnkownError userInfo:nil]
            };
            [strongStatus didFailPhoneVerificationCodeRequestWithError:error];
        }
    }
    else if(sync == self.passwordUpdateSync) {
        
        if(response.result == ZMTransportResponseStatusSuccess) {
            [strongStatus didUpdatePasswordSuccessfully];
        }
        else if(response.HTTPStatus == 403 && [[response payloadLabel] isEqualToString:@"invalid-credentials"]) {
            // if the credentials are invalid, we assume that there was a previous password. We decide to ignore this case because there's nothing we can do
            // and since we don't allow to change the password on the client (only to set it once), this will only be fired in some edge cases
            [strongStatus didUpdatePasswordSuccessfully];
        }
        else {
            [strongStatus didFailPasswordUpdate];
        }
    }
    else if(sync == self.emailUpdateSync) {
        if(response.result == ZMTransportResponseStatusSuccess) {
            [strongStatus didUpdateEmailSuccessfully];
        }
        else {
            NSError *error = {
                [NSError invalidEmailWithResponse:response] ?:
                [NSError emailIsAlreadyRegisteredErrorWithResponse:response] ?:
                [NSError userSessionErrorWithErrorCode:ZMUserSessionUnkownError userInfo:nil]
            };
            [strongStatus didFailEmailUpdate:error];
        }
    }
}

@end
