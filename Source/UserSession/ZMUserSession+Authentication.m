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


@import ZMUtilities;
@import ZMCDataModel;

#import "ZMUserSession+Authentication.h"
#import "ZMUserSession+Internal.h"
#import "ZMTracing.h"
//#import "ZMOperationLoop.h"
#import "NSError+ZMUserSessionInternal.h"
#import "ZMCredentials.h"
#import "ZMUserSessionAuthenticationNotification.h"
#import "ZMPushToken.h"

static char* const ZMLogTag ZM_UNUSED = "Authentication";
static NSString *const HasHistoryKey = @"hasHistory";

@implementation ZMUserSession (Authentication)

- (void)checkIfLoggedInWithCallback:(void (^)(BOOL))callback
{
    if (callback) {
        [self.syncManagedObjectContext performGroupedBlock:^{
            BOOL result = [self isLoggedIn];
            [self.managedObjectContext performGroupedBlock:^{
                callback(result);
            }];
        }];
    }
}

- (BOOL)needsToRegisterClient
{
    return self.clientRegistrationStatus.currentPhase != ZMClientRegistrationPhaseRegistered;
}

- (void)loginWithCredentials:(ZMCredentials *)loginCredentials
{
    ZMTraceAuthUserSessionLogin(loginCredentials.email, loginCredentials.password.length > 0 ? 1 : 0);
    
    [self.syncManagedObjectContext performGroupedBlock:^{
        if (self.isLoggedIn) {
            ZMLogDebug(@"User session has a cookie in loginWithEmail, no need to log in");
            [ZMUserSessionAuthenticationNotification notifyAuthenticationDidSucceed];
            [ZMRequestAvailableNotification notifyNewRequestsAvailable:self];
            return;
        }
        else if (   (loginCredentials.email.length == 0 || loginCredentials.password.length == 0)
                 && (loginCredentials.phoneNumber.length == 0 || loginCredentials.phoneNumberVerificationCode.length == 0))
        {
            ZMLogDebug(@"Email or password is empty.");
            [ZMUserSessionAuthenticationNotification notifyAuthenticationDidFail:[NSError userSessionErrorWithErrorCode:ZMUserSessionNeedsCredentials userInfo:nil]];
            return;
        }
        else {
            ZMLogDebug(@"Setting credentials for %@", loginCredentials.email);
            [self.authenticationStatus prepareForLoginWithCredentials:loginCredentials]; 
            if (self.needsToRegisterClient) {
                [self.clientRegistrationStatus prepareForClientRegistration];
            }
            else {
                [self start];
            }
        }
    }];
    
    [ZMRequestAvailableNotification notifyNewRequestsAvailable:self];
}

- (BOOL)hadHistoryAtLastLogin
{
    return self.accountStatus.hadHistoryBeforeLogin;
}

- (BOOL)requestPhoneVerificationCodeForLogin:(NSString *)phoneNumber
{
    if(![ZMPhoneNumberValidator validateValue:&phoneNumber error:nil]) {
        return NO;
    }
    [self.syncManagedObjectContext performGroupedBlock:^{
        [self.authenticationStatus prepareForRequestingPhoneVerificationCodeForLogin:phoneNumber];
        [ZMRequestAvailableNotification notifyNewRequestsAvailable:self];
    }];
    return YES;
}

+ (void)deleteAllKeychainItems;
{
    [ZMPersistentCookieStorage deleteAllKeychainItems];
}

+ (void)resetStateAndExit;
{
    dispatch_async(dispatch_get_global_queue(0, 0), ^{
        dispatch_semaphore_t sem = dispatch_semaphore_create(0);
        
        // Park the main thread, so we don't do any more work:
        dispatch_async(dispatch_get_main_queue(), ^{
            dispatch_semaphore_signal(sem);
            while (YES) {
                [NSThread sleepForTimeInterval:0.1];
            }
        });
        
        while (dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER) != 0) {
            ;
        }
        
        [self deleteAllKeychainItems];
        [NSManagedObjectContext setClearPersistentStoreOnStart:YES];
        
        [[NSUserDefaults standardUserDefaults] synchronize];
        [[NSUserDefaults sharedUserDefaults] synchronize];
        [NSThread sleepForTimeInterval:0.1];
        
        exit(0);
    });
}

+ (void)deleteCacheOnRelaunch;
{
    [NSManagedObjectContext setClearPersistentStoreOnStart:YES];
}

- (id<ZMAuthenticationObserverToken>)addAuthenticationObserver:(id<ZMAuthenticationObserver>)observer
{
    ZM_WEAK(observer);
    return (id<ZMAuthenticationObserverToken>)[ZMUserSessionAuthenticationNotification addObserverWithBlock:^(ZMUserSessionAuthenticationNotification *note) {
        ZM_STRONG(observer);
        switch(note.type) {
            case ZMAuthenticationNotificationLoginCodeRequestDidFail:
                if ([observer respondsToSelector:@selector(loginCodeRequestDidFail:)]) {
                    [observer loginCodeRequestDidFail:note.error];
                }
                break;
            case ZMAuthenticationNotificationAuthenticationDidSuceeded:
                if ([observer respondsToSelector:@selector(authenticationDidSucceed)]) {
                    [observer authenticationDidSucceed];
                }
                break;
            case ZMAuthenticationNotificationAuthenticationDidFail:
            {
                NSError *forwardedError = nil;
                if (note.error.code == ZMUserSessionCanNotRegisterMoreClients) {
                    NSMutableDictionary *errorUserInfo = [NSMutableDictionary dictionary];
                    
                    NSArray *clientIds = note.error.userInfo[ZMClientsKey];
                    NSArray *clientsObjects = [clientIds mapWithBlock:^id(NSManagedObjectID *objId) {
                        return [self.managedObjectContext existingObjectWithID:objId error:NULL];
                    }];
                    
                    errorUserInfo[ZMClientsKey] = clientsObjects;
                    
                    forwardedError = [NSError errorWithDomain:note.error.domain code:note.error.code userInfo:errorUserInfo];
                }
                else {
                    forwardedError = note.error;
                }
                if ([observer respondsToSelector:@selector(authenticationDidFail:)]) {
                    [observer authenticationDidFail:forwardedError];
                }
            }
                break;
            case ZMAuthenticationNotificationLoginCodeRequestDidSucceed:
                if([observer respondsToSelector:@selector(loginCodeRequestDidSucceed)]) {
                    [observer loginCodeRequestDidSucceed];
                }
                break;
        }
    }];
}

- (void)removeAuthenticationObserverForToken:(id<ZMAuthenticationObserverToken>)observerToken
{
    [ZMUserSessionAuthenticationNotification removeObserver:observerToken];
}

@end
