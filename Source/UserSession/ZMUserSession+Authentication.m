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
#import <WireSyncEngine/WireSyncEngine-Swift.h>

static NSString *ZMLogTag ZM_UNUSED = @"Authentication";

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

- (void)deleteUserKeychainItems;
{
    [self.transportSession.cookieStorage deleteKeychainItems];
}

- (void)closeAndDeleteCookie:(BOOL)deleteCookie
{
    [[NSUserDefaults standardUserDefaults] synchronize];
    [[NSUserDefaults sharedUserDefaults] synchronize];

    if (deleteCookie) {
        [self deleteUserKeychainItems];
    }

    NSManagedObjectContext *refUIMoc = self.managedObjectContext;
    NSManagedObjectContext *refSyncMOC = self.syncManagedObjectContext;

    [refUIMoc performGroupedBlockAndWait:^{}];
    [refSyncMOC performGroupedBlockAndWait:^{}];

    [self tearDown];

    [refUIMoc performGroupedBlockAndWait:^{}];
    [refSyncMOC performGroupedBlockAndWait:^{}];

    refUIMoc = nil;
    refSyncMOC = nil;
}

@end
