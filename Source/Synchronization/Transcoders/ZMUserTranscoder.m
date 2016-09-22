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


@import ZMCSystem;
@import ZMUtilities;
@import ZMTransport;
@import ZMCDataModel;

#import "ZMUserTranscoder+Internal.h"
#import "ZMSyncStrategy.h"

static NSString *UsersPath = @"/users";
NSUInteger const ZMUserTranscoderNumberOfUUIDsPerRequest = 1600 / 25; // UUID as string is 24 + 1 for the comma


@interface ZMUserTranscoder ()

@property (nonatomic) ZMRemoteIdentifierObjectSync *remoteIDObjectSync;

@end



@interface ZMUserTranscoder (ZMRemoteIdentifierObjectSync) <ZMRemoteIdentifierObjectTranscoder>
@end



@implementation ZMUserTranscoder

- (instancetype)initWithManagedObjectContext:(NSManagedObjectContext *)moc
{
    self = [super initWithManagedObjectContext:moc];
    if (self) {
        self.remoteIDObjectSync = [[ZMRemoteIdentifierObjectSync alloc] initWithTranscoder:self managedObjectContext:self.managedObjectContext];
    }
    return self;
}

- (void)setNeedsSlowSync
{
    NSArray *users = [self fetchConnectedUsersInContext:self.managedObjectContext];
    NSMutableSet *userIds = [NSMutableSet set];
    for (ZMUser *user in users) {
        if (user.remoteIdentifier) {
            [userIds addObject:user.remoteIdentifier];
        }
    }
    
    
    // also self
    ZMUser *selfUser = [ZMUser selfUserInContext:self.managedObjectContext];
    if (selfUser.remoteIdentifier != nil) {
        [userIds addObject:selfUser.remoteIdentifier];
    }
    
    [self.remoteIDObjectSync addRemoteIdentifiersThatNeedDownload:userIds];
}

- (NSArray *)contextChangeTrackers
{
    return @[self];
}

- (NSArray *)requestGenerators;
{
    return @[self.remoteIDObjectSync];
}

- (BOOL)isSlowSyncDone
{
    return self.remoteIDObjectSync.isDone;
}

- (NSFetchRequest *)fetchRequestForTrackedObjects
{
    return [ZMUser sortedFetchRequestWithPredicate:[self predicateForUsersExcludingSelfAndThoseBeingDownloadedInContext:self.managedObjectContext]];
}

- (void)addTrackedObjects:(NSSet *)objects
{
    NSSet *incompleteRemoteIdentifiers = [objects mapWithBlock:^id(ZMUser * user) {
        return user.remoteIdentifier;
    }];
    if (0 < incompleteRemoteIdentifiers.count) {
        [self.remoteIDObjectSync addRemoteIdentifiersThatNeedDownload:incompleteRemoteIdentifiers];
    }
}

- (void)objectsDidChange:(NSSet *)object
{
    NSSet *users = [object filteredSetUsingPredicate:[NSPredicate predicateWithFormat:@"self isKindOfClass:%@", ZMUser.class]];
    NSSet *incompleteUsers = [users filteredSetUsingPredicate:[self predicateForUsersExcludingSelfAndThoseBeingDownloadedInContext:self.managedObjectContext]];
    NSSet *incompleteRemoteIdentifiers = [incompleteUsers mapWithBlock:^id(ZMUser * user) {
        return user.remoteIdentifier;
    }];
    if (0 < incompleteRemoteIdentifiers.count) {
        [self.remoteIDObjectSync addRemoteIdentifiersThatNeedDownload:incompleteRemoteIdentifiers];
    }
}

- (void)updateUsersFromPayload:(NSArray *)userPayload expectedRemoteIdentifiers:(NSSet *)expectedRemoteIdentifiers;
{
    NSMutableSet *usersToReset = [expectedRemoteIdentifiers mutableCopy];
    for (NSDictionary *userData in userPayload) {
        NSUUID *uuid = [userData[@"id"] UUID];
        ZMUser *actualUser = [ZMUser userWithRemoteID:uuid createIfNeeded:NO inContext:self.managedObjectContext];
        [actualUser updateWithTransportData:userData authoritative:YES];
        [usersToReset removeObject:uuid];
    }
    
    // are there any remaining expected users that I did not find in the payload?
    for(NSUUID *uuid in usersToReset) {
        ZMUser *actualUser = [ZMUser userWithRemoteID:uuid createIfNeeded:NO inContext:self.managedObjectContext];
        actualUser.needsToBeUpdatedFromBackend = NO;
    }
}

- (void)processEvents:(NSArray<ZMUpdateEvent *> *)events
           liveEvents:(BOOL)liveEvents
       prefetchResult:(__unused ZMFetchRequestBatchResult *)prefetchResult;
{
    if(!liveEvents) {
        return;
    }
    
    for(ZMUpdateEvent *event in events) {
        [self processUpdateEvent:event];
    }
}

- (void)processUpdateEvent:(ZMUpdateEvent *)event;
{
// expected type
//    @{
//      @"type" : @"user.update",
//      @"user" : @{
//              @"id" : "4324324234234234234234234234",
//              @"name" : @"Mario"
//              }
//      };
    if(event.type != ZMUpdateEventUserUpdate) {
        return;
    }
    
    NSDictionary *userData = [event.payload dictionaryForKey:@"user"];
    if(userData == nil) {
        ZMLogError(@"User update event missing user: %@", event.payload);
        return;
    }
    
    NSUUID *userId = [userData uuidForKey:@"id"];
    if(userId == nil) {
        ZMLogError(@"User update event missing id: %@", userData);
        return;
    }
    
    ZMUser *user = [ZMUser userWithRemoteID:userId createIfNeeded:YES inContext:self.managedObjectContext];
    [user updateWithTransportData:userData authoritative:NO];
    
    return;
}

- (NSArray *)fetchConnectedUsersInContext:(NSManagedObjectContext *)context
{
    NSFetchRequest *req = [ZMConnection sortedFetchRequest];
    NSArray *connections = [context executeFetchRequestOrAssert:req];
    
    NSMutableArray *connectedUsers = [NSMutableArray array];
    for(ZMConnection *connection in connections) {
        [connectedUsers addObject:connection.to];
    }
    return connectedUsers;
}

- (NSPredicate *)predicateForUsersExcludingSelfAndThoseBeingDownloadedInContext:(NSManagedObjectContext *)context
{
    NSSet *remoteIDsInProgress = self.remoteIDObjectSync.remoteIdentifiersThatWillBeDownloaded;
    NSMutableArray *remoteIDsInProgressData = [[remoteIDsInProgress.allObjects mapWithBlock:^id(NSUUID * ID) {
        return [ID data];
    }] mutableCopy];
    
    NSPredicate *isIncompletePredicate = [ZMUser predicateForNeedingToBeUpdatedFromBackend];
    ZMUser *selfUser = [ZMUser selfUserInContext:context];
    if (selfUser.remoteIdentifier != nil) {
        [remoteIDsInProgressData addObject:selfUser.remoteIdentifier.data];
    }
    
    NSPredicate *noRemoteIdPredicate = [NSPredicate predicateWithFormat:@"remoteIdentifier_data != nil"];
    NSPredicate *excludePredicate = [NSPredicate predicateWithFormat:@"NOT remoteIdentifier_data IN %@", remoteIDsInProgressData];
    NSPredicate *p1 = [NSCompoundPredicate andPredicateWithSubpredicates:@[isIncompletePredicate, excludePredicate, noRemoteIdPredicate]];
    return p1;
}


+ (ZMTransportRequest *)requestForRemoteIdentifiers:(NSArray *)remoteIdentifiers
{
    if(remoteIdentifiers.count == 0) {
        return nil;
    }

    NSMutableString *path = [UsersPath mutableCopy];
    [path appendString:@"?ids="];
    
    [path appendString:[[remoteIdentifiers mapWithBlock:^id(NSUUID *uuid) {
        return uuid.transportString;
    }] componentsJoinedByString:@","]];
    
    ZMTransportRequest *request = [ZMTransportRequest requestGetFromPath:path];
    return request;
}

@end



@implementation ZMUserTranscoder (ZMRemoteIdentifierObjectSync)

- (void)didReceiveResponse:(ZMTransportResponse *)response remoteIdentifierObjectSync:(ZMRemoteIdentifierObjectSync *)sync forRemoteIdentifiers:(NSSet *)remoteIdentifiers;
{
    NOT_USED(sync);
    NOT_USED(remoteIdentifiers);
    
    switch(response.result) {
        case ZMTransportResponseStatusSuccess:
        {
            NSArray *userPayload = [response.payload asArray];
            if (userPayload != nil) {
                [self updateUsersFromPayload:userPayload expectedRemoteIdentifiers:remoteIdentifiers];
            }
            break;
        }
        case ZMTransportResponseStatusPermanentError:
        {
            [self updateUsersFromPayload:nil expectedRemoteIdentifiers:remoteIdentifiers];
            break;
        }
        case ZMTransportResponseStatusTemporaryError:
        case ZMTransportResponseStatusExpired:
        case ZMTransportResponseStatusTryAgainLater:
            break;
    }
}

- (NSUInteger)maximumRemoteIdentifiersPerRequestForObjectSync:(ZMRemoteIdentifierObjectSync *)sync;
{
    NOT_USED(sync);
    
    return ZMUserTranscoderNumberOfUUIDsPerRequest;
}

- (ZMTransportRequest *)requestForObjectSync:(ZMRemoteIdentifierObjectSync *)sync remoteIdentifiers:(NSSet *)identifiers;
{
    NOT_USED(sync);
    
    ZMTransportRequest *request = [self.class requestForRemoteIdentifiers:identifiers.allObjects];
    return request;
}

@end
