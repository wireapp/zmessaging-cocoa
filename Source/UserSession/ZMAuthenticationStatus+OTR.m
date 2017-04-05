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


#import "ZMAuthenticationStatus+OTR.h"
#import <WireSyncEngine/WireSyncEngine-Swift.h>
#import "ZMOperationLoop.h"
#import "ZMAuthenticationStatus_Internal.h"
#import "ZMUserSessionAuthenticationNotification.h"

NSString *const ZMPersistedClientIdKey = @"PersistedClientId";

@implementation ZMAuthenticationStatus (OTR)

- (BOOL)needsToRegisterClient;
{
    NSString *clientId = [self.moc persistentStoreMetadataForKey:ZMPersistedClientIdKey];
    return clientId == nil;
}

- (void)didRegisterClient:(UserClient *)client
{
    [self.moc setPersistentStoreMetadata:client.remoteIdentifier forKey:ZMPersistedClientIdKey];
    [self didCompleteLogin];
}

- (void)didFailToRegisterClient:(NSError *)error
{
    //we should not reset login state for client registration errors
    if (error.code != ZMUserSessionNeedsCredentialsToRegisterClient && error.code != ZMUserSessionCanNotRegisterMoreClients) {
        [self resetLoginAndRegistrationStatus];
    }
    [ZMUserSessionAuthenticationNotification notifyAuthenticationDidFail:error];
}

- (void)prepareForClientRegistrationWithCredentials:(ZMCredentials *)credentials;
{
    [UserClient insertNewObjectInManagedObjectContext:self.moc];
    [self.moc saveOrRollback];
    self.loginCredentials = credentials;
}

@end
