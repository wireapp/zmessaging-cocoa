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

#import "ZMUserIDsForSearchDirectoryTable.h"

@interface ZMSearchUserAndAssetID ()

@property (nonatomic) ZMSearchUser *searchUser;
@property (nonatomic) NSUUID *assetID;
@property (nonatomic, readonly) NSUUID *userIDIfThereIsNoAssetID;

@end



@implementation ZMSearchUserAndAssetID

- (instancetype)initWithSearchUser:(ZMSearchUser *)searchUser;
{
    return [self initWithSearchUser:searchUser assetID:nil];
}

- (instancetype)initWithSearchUser:(ZMSearchUser *)searchUser assetID:(NSUUID *)assetID {
    self = [super init];
    if(self) {
        self.searchUser = searchUser;
        self.assetID = assetID;
    }
    return self;
}

- (NSUUID *)userID
{
    return self.searchUser.remoteIdentifier;
}

- (NSUUID *)userIDIfThereIsNoAssetID {
    return (self.assetID == nil) ? self.searchUser.remoteIdentifier : nil;
}

- (BOOL)isEqual:(id)object
{
    if( ! [object isKindOfClass:ZMSearchUserAndAssetID.class]) {
        return NO;
    }
    ZMSearchUserAndAssetID *other = object;
    
    return ((self.searchUser == other.searchUser || [self.userID isEqual:other.userID]) &&
            (self.assetID == other.assetID || [self.assetID isEqual:other.assetID]));
}

- (NSString *)description
{
    return [NSString stringWithFormat:@"<%@: %p> \"%@\" %@ -> asset %@",
            self.class, self,
            self.searchUser.name, self.searchUser.remoteIdentifier.UUIDString ?: @"[]",
            self.assetID.UUIDString ?: @"[]"];
}

- (NSUInteger)hash
{
    return self.userID.hash ^ self.assetID.hash;
}

@end




@interface ZMUserIDsForSearchDirectoryTable ()

@property (nonatomic, readonly) NSMutableDictionary *entries;
@property (nonatomic, readonly) dispatch_queue_t isolation;

@end


@implementation ZMUserIDsForSearchDirectoryTable

- (instancetype)init
{
    self = [super init];
    if(self) {
        _entries = [NSMutableDictionary dictionary];
        _isolation = dispatch_queue_create("ZMUserIDsForSearchDirectoryTable.isolation", DISPATCH_QUEUE_CONCURRENT);
    }
    return self;
}

- (NSSet *)allUserIDs
{
    NSMutableSet *allUsersIDs = [NSMutableSet set];
    dispatch_sync(self.isolation, ^{
        for (NSSet *set in self.entries.objectEnumerator) {
            [allUsersIDs unionSet:[set mapWithBlock:^id(ZMSearchUserAndAssetID *userOrAsset) {
                return userOrAsset.userIDIfThereIsNoAssetID;
            }]];
        }
    });
    return allUsersIDs;
}

- (NSSet *)allAssetIDs
{
    NSMutableSet *allAssetIDs = [NSMutableSet set];
    dispatch_sync(self.isolation, ^{
        for (NSSet *set in self.entries.objectEnumerator) {
            [allAssetIDs unionSet:[set mapWithBlock:^id(ZMSearchUserAndAssetID *userOrAsset) {
                return userOrAsset.assetID == nil ? nil : userOrAsset;
            }]];
        }
    });
    return allAssetIDs;
}

- (void)setSearchUsers:(NSSet *)searchUsers forSearchDirectory:(id<ZMSearchResultStore>)directory
{
    dispatch_barrier_async(self.isolation, ^{
        NSValue *valueNoReference = [NSValue valueWithNonretainedObject:directory];
        NSSet *previousEntries = [self.entries objectForKey:valueNoReference];
        NSMutableDictionary *userIDtoPreviousEntries = [NSMutableDictionary dictionary];
        for(ZMSearchUserAndAssetID *userAsset in previousEntries) {
            userIDtoPreviousEntries[userAsset.userID] = userAsset;
        }
        
        NSSet *allPairs = [searchUsers mapWithBlock:^id(ZMSearchUser *searchUser) {
            ZMSearchUserAndAssetID *previousEntry = userIDtoPreviousEntries[searchUser.remoteIdentifier];
            if( ! previousEntry ) {
                return [[ZMSearchUserAndAssetID alloc] initWithSearchUser:searchUser];
            }
            return previousEntry;
        }];
        [self.entries setObject:[allPairs mutableCopy] forKey:valueNoReference];
    });
}

- (void)replaceUserIDToDownload:(NSUUID *)userID withAssetIDToDownload:(NSUUID *)assetID
{
    dispatch_barrier_async(self.isolation, ^{
        for(NSMutableSet *entry in self.entries.objectEnumerator) {
            for(ZMSearchUserAndAssetID *userAssetID in entry) {
                if([userAssetID.userID isEqual:userID]) {
                    userAssetID.assetID = assetID;
                }
            }
        }
    });
}

- (void)removeAllEntriesWithUserIDs:(NSSet *)userIDs;
{
    dispatch_barrier_async(self.isolation, ^{
        for(id key in self.entries.keyEnumerator) {
            
            NSMutableSet *entry = [self.entries objectForKey:key];
            NSMutableSet *newSet = [NSMutableSet set];
            for(ZMSearchUserAndAssetID *userAssetID in entry) {
                if( ! [userIDs containsObject:userAssetID.userID]) {
                    [newSet addObject:userAssetID];
                }
            }
            
            [entry setSet:newSet];
        }
    });
}

- (void)removeSearchDirectory:(ZMSearchDirectory *)directory;
{
    dispatch_barrier_async(self.isolation, ^{
        NSValue *valueNoReference = [NSValue valueWithNonretainedObject:directory];
        [self.entries removeObjectForKey:valueNoReference];
    });
}

- (void)clear
{
    dispatch_barrier_async(self.isolation, ^{
        [self.entries removeAllObjects];
    });
}

- (NSString *)debugDescription
{
    return [NSString stringWithFormat:@"<%@ %p>: %@", self.class, self, self.entries];
}

@end

