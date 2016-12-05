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

/*
@import ZMTransport;
@import ZMCDataModel;

#import "NSError+ZMUserSessionInternal.h"

static NSString *const UserProfileNotificationName =  @"ZMUUserProfileNotificationName";
static NSString *const EmailToUpdateKey = @"ZMEmailToUpdate";
static NSString *const ProfilePhoneNumberThatNeedsAValidationCodeKey = @"ZMProfilePhoneNumberThatNeedsAValidationCode";



@interface ZMUserProfileUpdateStatus ()

@property (nonatomic) ZMPhoneCredentials *phoneCredentialsToUpdate;
@property (nonatomic) ZMEmailCredentials *emailCredentialsToUpdate;
@property (nonatomic) NSString *emailToUpdate;
@property (nonatomic) NSString *passwordToUpdate;
@property (nonatomic) NSString *profilePhoneNumberThatNeedsAValidationCode;
@property (nonatomic) NSManagedObjectContext *moc;

@property (nonatomic) BOOL emailIsVerified;
@property (nonatomic) BOOL passwordIsVerified;

@end

@implementation ZMUserProfileUpdateStatus

- (instancetype)initWithManagedObjectContext:(NSManagedObjectContext *)managedObjectContext
{
    self = [super init];
    if(self) {
        self.moc = managedObjectContext;
    }
    return self;
}


- (void)reset
{
    self.phoneCredentialsToUpdate = nil;
    self.emailToUpdate = nil;
    self.passwordToUpdate = nil;
    self.profilePhoneNumberThatNeedsAValidationCode = nil;
}

- (void)resetEmailCredentials
{
    self.emailIsVerified = NO;
    self.passwordIsVerified = NO;
    self.emailCredentialsToUpdate = nil;
}

- (void)setEmailToUpdate:(NSString *)emailToUpdate
{
    [self.moc setPersistentStoreMetadata:emailToUpdate forKey:EmailToUpdateKey];
}

- (NSString *)emailToUpdate
{
    return [self.moc persistentStoreMetadataForKey:EmailToUpdateKey];
}

- (void)setProfilePhoneNumberThatNeedsAValidationCode:(NSString *)profilePhoneNumberThatNeedsAValidationCode
{
    [self.moc setPersistentStoreMetadata:profilePhoneNumberThatNeedsAValidationCode forKey:ProfilePhoneNumberThatNeedsAValidationCodeKey];

}

- (NSString *)profilePhoneNumberThatNeedsAValidationCode
{
    return [self.moc persistentStoreMetadataForKey:ProfilePhoneNumberThatNeedsAValidationCodeKey];
}

- (void)prepareForEmailAndPasswordChangeWithCredentials:(ZMEmailCredentials *)emailCredentials
{
    [self reset];
    self.emailCredentialsToUpdate = emailCredentials;
    
    self.emailToUpdate = emailCredentials.email;
    self.passwordToUpdate = emailCredentials.password;
}

- (void)prepareForPhoneChangeWithCredentials:(ZMPhoneCredentials *)phoneCredentials
{
    [self reset];
    self.phoneCredentialsToUpdate = phoneCredentials;
}

- (void)prepareForRequestingPhoneVerificationCodeForRegistration:(NSString *)phone
{
    [self reset];
    [ZMPhoneNumberValidator validateValue:&phone error:nil];
    self.profilePhoneNumberThatNeedsAValidationCode = phone;
}

- (ZMUserProfileUpdatePhases)currentPhase
{
    if(self.profilePhoneNumberThatNeedsAValidationCode != nil) {
        return ZMUserProfilePhaseRequestPhoneVerificationCode;
    }
    if(self.phoneCredentialsToUpdate != nil) {
        return ZMUserProfilePhaseChangePhone;
    }
    if(self.passwordToUpdate != nil) {
        return ZMUserProfilePhaseChangePassword;
    }
    if(self.emailToUpdate != nil) {
        return ZMUserProfilePhaseChangeEmail;
    }
    return ZMUserProfilePhaseIdle;
}

- (void)didRequestPhoneVerificationCodeSuccessfully;
{
    [self reset];
    [ZMUserProfileUpdateNotification notifyPhoneNumberVerificationCodeRequestDidSucceed];
}

- (void)didFailPhoneVerificationCodeRequestWithError:(NSError *)error;
{
    [self reset];
    [ZMUserProfileUpdateNotification notifyPhoneNumberVerificationCodeRequestDidFailWithError:error];
}

- (void)didVerifyPhoneSuccessfully;
{
    [self reset];
}

- (void)didFailPhoneVerification:(NSError *)error;
{
    [self reset];
    [ZMUserProfileUpdateNotification notifyPhoneNumberVerificationDidFail:error];

}

- (void)didUpdatePasswordSuccessfully;
{
    self.passwordToUpdate = nil;
    self.passwordIsVerified = YES;
}

- (void)didFailPasswordUpdate;
{
    [self reset];
    [ZMUserProfileUpdateNotification notifyPasswordUpdateDidFail];
}

- (void)didUpdateEmailSuccessfully;
{
    self.emailIsVerified = YES;
    [self reset];
    [ZMUserProfileUpdateNotification notifyDidSendEmailVerification];
}

- (void)didFailEmailUpdate:(NSError *)error;
{
    [self reset];
    [ZMUserProfileUpdateNotification notifyEmailUpdateDidFail:error];

}

@end




@implementation ZMUserProfileUpdateStatus (CredentialProvider)

- (ZMEmailCredentials *)emailCredentials
{
    if (self.emailIsVerified && self.passwordIsVerified) {
        return self.emailCredentialsToUpdate;
    }
    return nil;
}

- (void)credentialsMayBeCleared
{
    [self resetEmailCredentials];
}

@end




@interface ZMUserProfileUpdateNotification()

@property (nonatomic) ZMUserProfileUpdateNotificationType type;
@property (nonatomic) NSError *error;

@end

@implementation ZMUserProfileUpdateNotification

- (instancetype)init
{
    return [super initWithName:UserProfileNotificationName object:nil];
}

+ (void)notifyDidSendEmailVerification;
{
    ZMUserProfileUpdateNotification *note = [[ZMUserProfileUpdateNotification alloc] init];
    note.type = ZMUserProfileNotificationEmailDidSendVerification;
    [[NSNotificationCenter defaultCenter] postNotification:note];
}

+ (void)notifyEmailUpdateDidFail:(NSError *)error
{
    ZMUserProfileUpdateNotification *note = [[ZMUserProfileUpdateNotification alloc] init];
    note.type = ZMUserProfileNotificationEmailUpdateDidFail;
    note.error = error;
    [[NSNotificationCenter defaultCenter] postNotification:note];
}

+ (void)notifyPasswordUpdateDidFail
{
    ZMUserProfileUpdateNotification *note = [[ZMUserProfileUpdateNotification alloc] init];
    note.type = ZMUserProfileNotificationPasswordUpdateDidFail;
    [[NSNotificationCenter defaultCenter] postNotification:note];
    
}

+ (void)notifyPhoneNumberVerificationCodeRequestDidFailWithError:(NSError *)error
{
    ZMUserProfileUpdateNotification *note = [[ZMUserProfileUpdateNotification alloc] init];
    note.type = ZMUserProfileNotificationPhoneNumberVerificationCodeRequestDidFail;
    note.error = error;
    [[NSNotificationCenter defaultCenter] postNotification:note];

}

+ (void)notifyPhoneNumberVerificationCodeRequestDidSucceed
{
    ZMUserProfileUpdateNotification *note = [[ZMUserProfileUpdateNotification alloc] init];
    note.type = ZMUserProfileNotificationPhoneNumberVerificationCodeRequestDidSucceed;
    [[NSNotificationCenter defaultCenter] postNotification:note];
}

+ (void)notifyPhoneNumberVerificationDidFail:(NSError *)error
{
    ZMUserProfileUpdateNotification *note = [[ZMUserProfileUpdateNotification alloc] init];
    note.type = ZMUserProfileNotificationPhoneNumberVerificationDidFail;
    note.error = error;
    [[NSNotificationCenter defaultCenter] postNotification:note];
}

+ (id<ZMUserProfileUpdateNotificationObserverToken>)addObserverWithBlock:(void(^)(ZMUserProfileUpdateNotification *))block
{
    NSCParameterAssert(block);
    return (id<ZMUserProfileUpdateNotificationObserverToken>)[[NSNotificationCenter defaultCenter] addObserverForName:UserProfileNotificationName object:nil queue:[NSOperationQueue currentQueue] usingBlock:^(NSNotification *note) {
        block((ZMUserProfileUpdateNotification *)note);
    }];
}

+ (void)removeObserver:(id<ZMUserProfileUpdateNotificationObserverToken>)token
{
    [[NSNotificationCenter defaultCenter] removeObserver:token name:UserProfileNotificationName object:nil];
}

@end

*/
