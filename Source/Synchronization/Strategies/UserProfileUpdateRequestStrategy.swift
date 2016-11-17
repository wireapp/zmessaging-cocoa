//
//  UserProfileUpdateRequestStrategy.swift
//  zmessaging-cocoa
//
//  Created by Marco Conti on 15/11/16.
//  Copyright © 2016 Zeta Project Gmbh. All rights reserved.
//

import Foundation

@objc public class UserProfileRequestStrategy : NSObject {
    
    let managedObjectContext : NSManagedObjectContext
    
    let userProfileUpdateStatus : UserProfileUpdateStatus
    
    let clientRegistrationStatus : ZMClientRegistrationStatus
    
    let authenticationStatus : AuthenticationStatusProvider
    
    public init(managedObjectContext: NSManagedObjectContext,
                userProfileUpdateStatus: UserProfileUpdateStatus,
                clientRegistrationStatus: ZMClientRegistrationStatus,
                authenticationStatus: AuthenticationStatusProvider) {
        self.managedObjectContext = managedObjectContext
        self.userProfileUpdateStatus = userProfileUpdateStatus
        self.authenticationStatus = authenticationStatus
        self.clientRegistrationStatus = clientRegistrationStatus
    }
}

extension UserProfileRequestStrategy : RequestStrategy {
    
    @objc public func nextRequest() -> ZMTransportRequest? {
        // TODO MARCO
        
        // TODO MARCO
        // for setting email and password, the check is done even when non authenticated. Same for phone login? Need to check.

        return nil
    }
}

/*
 
 @interface ZMUserProfileUpdateTranscoder() <ZMSingleRequestTranscoder, ZMRequestGenerator>
 
 @property (nonatomic) ZMSingleRequestSync *phoneCodeRequestSync;
 @property (nonatomic) ZMSingleRequestSync *phoneVerificationSync;
 @property (nonatomic) ZMSingleRequestSync *passwordUpdateSync;
 @property (nonatomic) ZMSingleRequestSync *emailUpdateSync;
 
 @property (nonatomic, weak) UserProfileUpdateStatus *userProfileUpdateStatus;
 
 @end
 
 @implementation ZMUserProfileUpdateTranscoder
 
 - (instancetype)initWithManagedObjectContext:(NSManagedObjectContext * __unused)moc
 {
 RequireString(NO, "Do not use this init");
 return nil;
 }
 
 - (instancetype)initWithManagedObjectContext:(NSManagedObjectContext *)moc userProfileUpdateStatus:(UserProfileUpdateStatus *)userProfileUpdateStatus
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
 UserProfileUpdateStatus *strongStatus = self.userProfileUpdateStatus;
 
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
 UserProfileUpdateStatus *strongStatus = self.userProfileUpdateStatus;
 
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
 UserProfileUpdateStatus *strongStatus = self.userProfileUpdateStatus;
 
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
 */
