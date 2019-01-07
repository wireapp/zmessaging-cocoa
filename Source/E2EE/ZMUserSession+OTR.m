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
@import WireRequestStrategy;

#import "ZMUserSession+OTR.h"
#import "ZMUserSession+Internal.h"
#import "ZMCredentials.h"
#import <WireSyncEngine/WireSyncEngine-Swift.h>
#import "ZMUserSession+OTR.h"


@implementation ZMUserSession (OTR)

- (void)fetchAllClients
{
    [self.syncManagedObjectContext performGroupedBlock:^{
        [self.clientUpdateStatus needsToFetchClientsWithAndVerifySelfClient:YES];
        [ZMRequestAvailableNotification notifyNewRequestsAvailable:self];
    }];
}


- (void)deleteClient:(UserClient *)client withCredentials:(ZMEmailCredentials *)emailCredentials
{
    [client markForDeletion];
    [[client managedObjectContext] saveOrRollback];
    
    [self.syncManagedObjectContext performGroupedBlock:^{
        [self.clientUpdateStatus deleteClientsWithCredentials:emailCredentials];
        [ZMRequestAvailableNotification notifyNewRequestsAvailable:self];
    }];
}

- (id)addClientUpdateObserver:(id<ZMClientUpdateObserver>)observer;
{
    ZM_WEAK(observer);
    
    return [ZMClientUpdateNotification addOserverWithContext:self.managedObjectContext block:^(enum ZMClientUpdateNotificationType type, NSArray<NSManagedObjectID *> *clientObjectIDs, NSError *error) {
        ZM_STRONG(observer);
        [self.managedObjectContext performGroupedBlock:^{
            switch (type) {
                case ZMClientUpdateNotificationTypeFetchCompleted:
                    if ([observer respondsToSelector:@selector(finishedFetchingClients:)]) {
                        NSArray *uiClients = @[];
                        if (clientObjectIDs.count > 0) {
                            uiClients = [clientObjectIDs mapWithBlock:^id(NSManagedObjectID *objID) {
                                return [self.managedObjectContext objectWithID:objID];
                            }];
                        }
                        [observer finishedFetchingClients:uiClients];
                    }
                    break;
                case ZMClientUpdateNotificationTypeFetchFailed:
                    if ([observer respondsToSelector:@selector(failedToFetchClientsWithError:)]) {
                        [observer failedToFetchClientsWithError:error];
                    }
                    break;
                case ZMClientUpdateNotificationTypeDeletionCompleted:
                    if ([observer respondsToSelector:@selector(finishedDeletingClients:)]) {
                        NSArray *uiClients = @[];
                        if (clientObjectIDs.count > 0) {
                            uiClients = [clientObjectIDs mapWithBlock:^id(NSManagedObjectID *objID) {
                                return [self.managedObjectContext objectWithID:objID];
                            }];
                        }
                        [observer finishedDeletingClients:uiClients];
                    }
                    break;
                case ZMClientUpdateNotificationTypeDeletionFailed:
                    if ([observer respondsToSelector:@selector(failedToDeleteClientsWithError:)]) {
                        [observer failedToDeleteClientsWithError:error];
                    }
                    break;
            }
        }];

    }];
}



@end
