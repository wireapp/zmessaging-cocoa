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

@import WireDataModel;

#import "ZMSearchDirectory.h"


@interface ZMSearchResult ()

@property (nonatomic) NSMutableArray *mutableUsersInContacts;
@property (nonatomic) NSMutableArray *mutableUsersInDirectory;
@property (nonatomic) NSMutableArray *mutableGroupConversations;

@end




@implementation ZMSearchResult

- (instancetype)init
{
    self = [super init];
    if (self) {
        self.mutableUsersInContacts = [NSMutableArray array];
        self.mutableUsersInDirectory = [NSMutableArray array];
        self.mutableGroupConversations = [NSMutableArray array];
    }
    return self;
}

- (instancetype)initWithUsersInContacts:(NSArray<ZMSearchUser *> *)usersInContacts
                       usersInDirectory:(NSArray<ZMSearchUser *> *)usersInDirectory
                     groupConversations:(NSArray<ZMConversation *> *)groupConversations;
{
    self = [super init];
    if (self) {
        self.mutableUsersInContacts = [usersInContacts mutableCopy];
        self.mutableUsersInDirectory = [usersInDirectory mutableCopy];
        self.mutableGroupConversations = [groupConversations mutableCopy];
    }
    return self;
}

- (void)addUsersInContacts:(NSArray *)objects;
{
    [self.mutableUsersInContacts addObjectsFromArray:objects];
}

- (void)addUsersInDirectory:(NSArray *)objects;
{
    [self.mutableUsersInDirectory addObjectsFromArray:objects];
}

- (void)addGroupConversations:(NSArray *)objects;
{
    [self.mutableGroupConversations addObjectsFromArray:objects];
}

- (NSArray *)usersInContacts
{
    return self.mutableUsersInContacts;
}

- (NSArray *)usersInDirectory
{
    return self.mutableUsersInDirectory;
}

- (NSMutableArray *)groupConversations
{
    return self.mutableGroupConversations;
}

- (instancetype)copyByRemovingUsersWithRemoteIdentifier:(NSUUID *)remoteIdentifier;
{
    ZMSearchResult *copy = [[self.class alloc] init];
    [copy.mutableUsersInContacts addObjectsFromArray:self.usersInContacts];
    [copy.mutableUsersInDirectory addObjectsFromArray:self.usersInDirectory];
    [copy.mutableGroupConversations addObjectsFromArray:self.groupConversations];
    
    if (remoteIdentifier != nil) {
        NSPredicate *p = [NSPredicate predicateWithBlock:^BOOL(ZMSearchUser *user, NSDictionary * __unused bindings) {
            NSUUID *userID = user.remoteIdentifier;
            return !((userID == remoteIdentifier) || [userID isEqual:remoteIdentifier]);
        }];
        [copy.mutableUsersInContacts filterUsingPredicate:p];
        [copy.mutableUsersInDirectory filterUsingPredicate:p];
    }
    return copy;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<%@: %p> (Contacts: %@, Directory: %@, Conversations: %@)", self.class, self, self.usersInContacts, self.usersInDirectory, self.groupConversations];
}

- (BOOL)isEqual:(id)object;
{
    if (! [object isKindOfClass:ZMSearchResult.class]) {
        return NO;
    }
    ZMSearchResult *other = object;
    return (((self.usersInContacts == other.usersInContacts) || [self.usersInContacts isEqual:other.usersInContacts]) &&
            ((self.usersInDirectory == other.usersInDirectory) || [self.usersInDirectory isEqual:other.usersInDirectory]) &&
            ((self.groupConversations == other.groupConversations) || [self.groupConversations isEqual:other.groupConversations]));
}

- (NSUInteger)hash;
{
    return ((self.usersInContacts.hash * 1) ^ (self.usersInDirectory.hash * 7) ^ (self.groupConversations.hash * 53));
}

@end
