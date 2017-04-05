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

#import "ZMClientUpdateNotification.h"
#import <WireSyncEngine/WireSyncEngine-Swift.h>

static NSString *const ClientUpdateNotificationName = @"ClientUpdateNotification";


@interface ZMClientUpdateNotification ()
@end

@implementation ZMClientUpdateNotification

- (instancetype)init
{
    return [super initWithName:ClientUpdateNotificationName object:nil];
}


+ (void)notifyFetchingClientsCompletedWithUserClients:(NSArray<UserClient*> *)userClients {
    NSArray *clientIDs = [userClients mapWithBlock:^id(UserClient *client) {
        return client.objectID;
    }];
    ZMClientUpdateNotification *note = [ZMClientUpdateNotification new];
    note.clientObjectIDs = clientIDs;
    note.type = ZMClientUpdateNotificationTypeFetchCompleted;
    [[NSNotificationCenter defaultCenter] postNotification:note];
}

+ (void)notifyFetchingClientsDidFail:(NSError*)error
{
    ZMClientUpdateNotification *note = [ZMClientUpdateNotification new];
    note.type = ZMClientUpdateNotificationTypeFetchFailed;
    note.error = error;
    [[NSNotificationCenter defaultCenter] postNotification:note];
}

+ (void)notifyDeletionCompleted:(NSArray<UserClient *> *)remainingClients
{
    NSArray *clientIDs = [remainingClients mapWithBlock:^id(UserClient *client) {
        return client.objectID;
    }];
    ZMClientUpdateNotification *note = [ZMClientUpdateNotification new];
    note.type = ZMClientUpdateNotificationTypeDeletionCompleted;
    note.clientObjectIDs = clientIDs;
    [[NSNotificationCenter defaultCenter] postNotification:note];
}

+ (void)notifyDeletionFailed:(NSError*)error
{
    ZMClientUpdateNotification *note = [ZMClientUpdateNotification new];
    note.type = ZMClientUpdateNotificationTypeDeletionFailed;
    note.error = error;
    [[NSNotificationCenter defaultCenter] postNotification:note];
}

+ (id<ZMClientUpdateObserverToken>)addObserverWithBlock:(void (^)(ZMClientUpdateNotification *))block
{
    NSCParameterAssert(block);
    return (id<ZMClientUpdateObserverToken>)[[NSNotificationCenter defaultCenter] addObserverForName:ClientUpdateNotificationName object:nil queue:[NSOperationQueue currentQueue] usingBlock:^(NSNotification *note) {
        block((ZMClientUpdateNotification *)note);
    }];
}

+ (void)removeObserver:(id<ZMClientUpdateObserverToken>)token
{
    [[NSNotificationCenter defaultCenter] removeObserver:token name:ClientUpdateNotificationName object:nil];
}

@end
