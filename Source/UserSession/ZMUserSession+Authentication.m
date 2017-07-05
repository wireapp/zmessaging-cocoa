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
@import WireDataModel;

#import "ZMUserSession+Authentication.h"
#import "ZMUserSession+Internal.h"
#import "NSError+ZMUserSessionInternal.h"
#import "ZMCredentials.h"
#import "ZMUserSessionAuthenticationNotification.h"
#import "ZMPushToken.h"
#import <WireSyncEngine/WireSyncEngine-Swift.h>

static NSString *ZMLogTag ZM_UNUSED = @"Authentication";
static NSString *const HasHistoryKey = @"hasHistory";

@implementation ZMUserSession (Authentication)

- (void)setEmailCredentials:(ZMEmailCredentials *)emailCredentials
{
    self.clientRegistrationStatus.emailCredentials = emailCredentials;
}

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
    return true;
}

- (BOOL)hadHistoryAtLastLogin
{
    return self.accountStatus.hadHistoryBeforeLogin;
}

- (void)deleteUserKeychainItems;
{
    [self.transportSession.cookieStorage deleteUserKeychainItems];
}

- (void)resetStateAndExit;
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

@end
