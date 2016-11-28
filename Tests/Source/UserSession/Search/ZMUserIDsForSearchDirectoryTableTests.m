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


@import ZMCDataModel;

#import "MessagingTest.h"
#import "ZMSearchDirectory+Internal.h"
#import "ZMUserIDsForSearchDirectoryTable.h"
#import "ZMUserSession+Internal.h"

@interface ZMUserIDsForSearchDirectoryTableTests: MessagingTest

@property (nonatomic) ZMUserIDsForSearchDirectoryTable *sut;

@end

@implementation ZMUserIDsForSearchDirectoryTableTests

- (void)setUp {
    
    [super setUp];
    self.sut = [[ZMUserIDsForSearchDirectoryTable alloc] init];
    
}

- (void)tearDown {

    self.sut = nil;
    [super tearDown];
    
}

- (ZMSearchDirectory *)createSearchDirectory
{
    // we never use any of the directory's properties, so it doesn't matter what I return as long as it's unique
    return (id) [NSUUID createUUID];
}

- (ZMSearchUser *)createSearchUser
{
    return [[ZMSearchUser alloc] initWithName:@"foo"
                                       handle:@"foo"
                                  accentColor:ZMAccentColorBrightOrange
                                     remoteID:[NSUUID createUUID]
                                         user:nil
                     syncManagedObjectContext:self.syncMOC
                       uiManagedObjectContext:self.uiMOC];

}

- (NSSet *)userIDsFromSearchUserSet:(NSSet *)searchUsers
{
    return [searchUsers mapWithBlock:^id(ZMSearchUser *user) {
        return user.remoteIdentifier;
    }];

}

- (void)testThatItRetrievesAllUserIDs
{
    // given
    ZMSearchDirectory *directory1 = [self createSearchDirectory];
    NSMutableSet *users1 = [NSMutableSet setWithObjects:[self createSearchUser], [self createSearchUser], nil];
    ZMSearchDirectory *directory2 = [self createSearchDirectory];
    NSMutableSet *users2 = [NSMutableSet setWithObjects:[self createSearchUser], [self createSearchUser], nil];
    
    // when
    [self.sut setSearchUsers:users1 forSearchDirectory:directory1];
    [self.sut setSearchUsers:users2 forSearchDirectory:directory2];
    
    // then
    NSMutableSet *expectedSearchUsers = [users1 mutableCopy];
    [expectedSearchUsers unionSet:users2];
    
    NSSet *retrievedSet = [self.sut allUserIDs];
    XCTAssertEqualObjects(retrievedSet, [self userIDsFromSearchUserSet:expectedSearchUsers]);
    
}

- (void)testThatWhenAddingIDsForASearchResultTheyAreCopied
{
    // given
    ZMSearchDirectory *directory = [self createSearchDirectory];
    NSMutableSet *userIDs = [NSMutableSet setWithObjects:[self createSearchUser], [self createSearchUser], nil];
    NSSet *expectedSet = [userIDs copy];
    
    // when
    [self.sut setSearchUsers:userIDs forSearchDirectory:directory];
    WaitForAllGroupsToBeEmpty(0.5);
    [userIDs removeAllObjects]; // this will check that it does a copy when inserting. It if is not copied, this will delete all IDs
    
    // then
    NSSet *retrievedSet = [self.sut allUserIDs];
    XCTAssertEqualObjects(retrievedSet, [self userIDsFromSearchUserSet:expectedSet]);
}


- (void)testThatWhenAddingIDsForASearchResultItIsDiscardedWhenTheSearchDirectoryIsReleased
{
    // given
    @autoreleasepool {
        
        id mockTable = [OCMockObject mockForClass:ZMSearchDirectory.class];
        [[[[mockTable stub] andReturn:self.sut] classMethod] userIDsMissingProfileImage];
        
        id mockUserSession = [OCMockObject mockForClass:ZMUserSession.class];
        [[[mockUserSession stub] andReturn:self.syncMOC] syncManagedObjectContext];
        [[mockUserSession expect] storeURL];
        [[mockUserSession expect] managedObjectContext];

        ZMSearchDirectory *directory = [[ZMSearchDirectory alloc] initWithUserSession:mockUserSession];
        NSMutableSet *userIDs = [NSMutableSet setWithObjects:[self createSearchUser], [self createSearchUser], nil];
        
        // when
        [self.sut setSearchUsers:userIDs forSearchDirectory:directory];
        [directory tearDown];
        WaitForAllGroupsToBeEmpty(0.5);
        
        // after
        [mockTable stopMocking];
        [mockUserSession stopMocking];
    }
    
    // then
    NSSet *retrievedSet = [self.sut allUserIDs];
    XCTAssertEqual(retrievedSet.count, 0u);
}

- (void)testThatItReplacesUserIDsWithAssetIDs
{
    // given
    ZMSearchUser *user1 = [self createSearchUser];
    ZMSearchUser *user2 = [self createSearchUser];
    ZMSearchUser *user3 = [self createSearchUser];
    
    NSUUID *assetID1 = [NSUUID createUUID];
    NSUUID *assetID2 = [NSUUID createUUID];

    ZMSearchDirectory *directory = [self createSearchDirectory];
    NSMutableSet *userIDs = [NSMutableSet setWithObjects:user1, user2, user3, nil];
    [self.sut setSearchUsers:userIDs forSearchDirectory:directory];
    
    NSSet *expectedUserAssets = [NSSet setWithObjects:
                                [[ZMSearchUserAndAssetID alloc] initWithSearchUser:user1 assetID:assetID1],
                                [[ZMSearchUserAndAssetID alloc] initWithSearchUser:user2 assetID:assetID2],
                                nil];
    
    // when
    [self.sut replaceUserIDToDownload:user1.remoteIdentifier withAssetIDToDownload:assetID1];
    [self.sut replaceUserIDToDownload:user2.remoteIdentifier withAssetIDToDownload:assetID2];

    // then
    NSSet *retrievedUserIDs = [self.sut allUserIDs];
    NSSet *retrievedAssetIDs = [self.sut allAssetIDs];
    XCTAssertEqualObjects(retrievedUserIDs, [NSSet setWithObject:user3.remoteIdentifier]);
    XCTAssertEqualObjects(retrievedAssetIDs, expectedUserAssets);
}

- (void)testThatClearingRemovesAllItems
{
    // given
    ZMSearchUser *user1 = [self createSearchUser];
    ZMSearchUser *user2 = [self createSearchUser];
    
    NSUUID *assetID1 = [NSUUID createUUID];
    
    ZMSearchDirectory *directory = [self createSearchDirectory];
    NSMutableSet *userIDs = [NSMutableSet setWithObjects:user1, user2, nil];
    [self.sut setSearchUsers:userIDs forSearchDirectory:directory];
    
    [self.sut replaceUserIDToDownload:user1.remoteIdentifier withAssetIDToDownload:assetID1];
    
    // when
    [self.sut clear];
    
    // then
    XCTAssertEqual(self.sut.allAssetIDs.count, 0u);
    XCTAssertEqual(self.sut.allUserIDs.count, 0u);
}

- (void)testThatItRemovesEntriesWithUserIDs
{
    // given
    ZMSearchUser *user1 = [self createSearchUser];
    ZMSearchUser *user2 = [self createSearchUser];
    ZMSearchUser *user3 = [self createSearchUser];
    
    ZMSearchDirectory *directory = [self createSearchDirectory];
    NSMutableSet *userIDs = [NSMutableSet setWithObjects:user1, user2, user3, nil];
    [self.sut setSearchUsers:userIDs forSearchDirectory:directory];
    
    // when
    [self.sut removeAllEntriesWithUserIDs:[NSSet setWithObjects:user2.remoteIdentifier, user3.remoteIdentifier, nil]];
    
    // then
    XCTAssertEqual(self.sut.allUserIDs.count, 1u);
    XCTAssertEqual(self.sut.allUserIDs.anyObject, user1.remoteIdentifier);
}

- (void)testThatReAddingAUserIDDoesNotDeleteTheAssociatedAssetID
{
    // given
    ZMSearchUser *user1 = [self createSearchUser];
    ZMSearchUser *user2 = [self createSearchUser];
    
    NSUUID *assetID1 = [NSUUID createUUID];
    
    ZMSearchDirectory *directory = [self createSearchDirectory];
    NSMutableSet *userIDs = [NSMutableSet setWithObjects:user1, user2, nil];
    [self.sut setSearchUsers:userIDs forSearchDirectory:directory];
    
    [self.sut replaceUserIDToDownload:user1.remoteIdentifier withAssetIDToDownload:assetID1];
    
    // when
    [self.sut setSearchUsers:userIDs forSearchDirectory:directory];
    
    // then
    XCTAssertEqual(self.sut.allAssetIDs.count, 1u);
    XCTAssertEqual(self.sut.allUserIDs.count, 1u);

}

- (void)testThatItRemovesTheSearchDirectory
{
    // given
    ZMSearchUser *user1 = [self createSearchUser];
    ZMSearchUser *user2 = [self createSearchUser];
    
    ZMSearchDirectory *directory = [self createSearchDirectory];
    NSMutableSet *userIDs = [NSMutableSet setWithObjects:user1, user2, nil];
    [self.sut setSearchUsers:userIDs forSearchDirectory:directory];
    
    // when
    [self.sut removeSearchDirectory:directory];
    
    // then
    XCTAssertEqual(self.sut.allAssetIDs.count, 0u);
    XCTAssertEqual(self.sut.allUserIDs.count, 0u);
}

@end

