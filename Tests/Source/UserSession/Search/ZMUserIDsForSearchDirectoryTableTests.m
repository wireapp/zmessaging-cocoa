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

#import "MessagingTest.h"
#import "ZMSearchDirectory+Internal.h"
#import "ZMUserSession+Internal.h"

@interface ZMUserIDsForSearchDirectoryTableTests: MessagingTest

@property (nonatomic) SearchDirectoryUserIDTable *sut;

@end

@implementation ZMUserIDsForSearchDirectoryTableTests

- (void)setUp {
    
    [super setUp];
    self.sut = [[SearchDirectoryUserIDTable alloc] init];
    
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
    NSSet *retrievedSet = [self.sut allUserIds];
    XCTAssertEqual(retrievedSet.count, 0u);
}

@end

