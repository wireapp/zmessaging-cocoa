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
#import "ZMUserSession.h"
#import "ZMSuggestionSearch.h"
#import "ZMSearchResult+Internal.h"



@interface ZMSuggestionSearchTests : MessagingTest

@property (nonatomic) NSArray *remoteIdentifiers;
@property (nonatomic) NSMutableDictionary *results;
@property (nonatomic) id mockCache;
@property (nonatomic) ZMSuggestionSearch *sut;
@property (nonatomic) ZMSearchToken token;

@end



@implementation ZMSuggestionSearchTests

- (void)setUp {
    [super setUp];
    (void)[[[[(id)self.mockUserSession stub] andReturn:self.uiMOC] managedObjectContext] dispatchGroup];
    self.mockCache = [OCMockObject niceMockForClass:[NSCache class]];
    
    [self verifyMockLater:self.mockCache];
    [self verifyMockLater:self.mockUserSession];
    self.sut = [[ZMSuggestionSearch alloc] initWithSearchContext:self.uiMOC userSession:self.mockUserSession resultCache:self.mockCache];
    
}

- (void)tearDown {
    self.mockCache = nil;
    [self.sut tearDown];
    [super tearDown];
}

- (void)testThatSuggestedContactRemoteIdentifiersReturnNilWhenItHasNeverBeenSet
{
    XCTAssertNil(self.uiMOC.suggestedUsersForUser);
    XCTAssertNil(self.uiMOC.commonConnectionsForUsers);
    XCTAssertNil(self.uiMOC.removedSuggestedContactRemoteIdentifiers);
}

- (void)testThatSuggestedUsersForUserReturnsEmptyArrayWhenSettingItWithAnEmptyArray
{
    // given
    NSOrderedSet *remoteIDs = [NSOrderedSet orderedSet];
    
    // when
    self.uiMOC.suggestedUsersForUser = remoteIDs;
    
    // then
    XCTAssertEqualObjects(self.uiMOC.suggestedUsersForUser, remoteIDs);
}

- (void)testThatRemovedSuggestedContactRemoteIdentifiersReturnsEmptyArrayWhenSettingItWithAnEmptyArray
{
    // given
    NSArray *remoteIDs = @[];
    
    // when
    self.uiMOC.removedSuggestedContactRemoteIdentifiers = remoteIDs;
    
    // then
    XCTAssertEqualObjects(self.uiMOC.removedSuggestedContactRemoteIdentifiers, @[]);
}

- (void)testThatManagedObjectContextSetsCommonConnectionsForUsers
{
    // given
    NSDictionary *remoteIDsMap = @{NSUUID.createUUID: [ZMSuggestedUserCommonConnections emptyEntry],
                                NSUUID.createUUID: [ZMSuggestedUserCommonConnections emptyEntry]};

    // when
    self.uiMOC.commonConnectionsForUsers = remoteIDsMap;
    
    // then
    [self assertDictionary:self.uiMOC.commonConnectionsForUsers isEqualToDictionary:remoteIDsMap name1:"suggestedUsersForUser" name2:"remoteIDsMap" failureRecorder:nil];
}

- (void)testThatManagedObjectContextSetsRemovedSuggestedContactRemoteIdentifiers
{
    // given
    NSArray *remoteIDs = @[NSUUID.createUUID, NSUUID.createUUID];
    
    // when
    self.uiMOC.removedSuggestedContactRemoteIdentifiers = remoteIDs;
    
    // then
    XCTAssertEqualObjects([self.uiMOC removedSuggestedContactRemoteIdentifiers], remoteIDs);
}

- (void)testThatItSendsOutANotificationWhenTheRemovedSuggestContactsRemoteIdentifiersChange;
{
    // given
    NSArray *remoteIDs = @[NSUUID.createUUID, NSUUID.createUUID];
    
    // expect
    [self expectationForNotification:ZMRemovedSuggestedContactRemoteIdentifiersDidChange object:nil handler:^BOOL(NSNotification *notification) {
        NOT_USED(notification);
        return (self.uiMOC.removedSuggestedContactRemoteIdentifiers.count == remoteIDs.count);
    }];
    
    // when
    self.uiMOC.removedSuggestedContactRemoteIdentifiers = remoteIDs;
    
    // then
    XCTAssert([self waitForCustomExpectationsWithTimeout:0.5]);
}

- (void)testThatReturnsTheSuggestionSearchToken
{
    // when
    ZMSearchToken token = [ZMSuggestionSearch suggestionSearchToken];
    
    // then
    XCTAssertEqualObjects(token, @"ZMSuggestedPeople");
}

- (void)testThatItReturnsCachedResultsIfPresent
{
    // given
    ZMSearchResult *result = [[ZMSearchResult alloc] init];
    
    // expect
    [(NSCache *)[[(id)self.mockCache expect] andReturnValue:OCMOCK_VALUE(result)] objectForKey:self.sut.token];

    // when
    __block ZMSearchResult *returnedResult;
    self.sut.resultHandler = ^(ZMSearchResult *searchResult) {
        returnedResult = searchResult;
    };
    
    [self.sut start];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(returnedResult, result);
}

- (ZMSearchUser *)createSearchUserWithName:(NSString *)name;
{
    return [[ZMSearchUser alloc] initWithName:name
                                       handle:@"foo"
                                  accentColor:ZMAccentColorSoftPink
                                     remoteID:[NSUUID createUUID]
                                         user:nil
                     syncManagedObjectContext:self.syncMOC
                       uiManagedObjectContext:self.uiMOC];

}

- (void)testThatItRemovesResultsFromTheCache;
{
    // given
    ZMSearchResult *result = [[ZMSearchResult alloc] init];
    ZMSearchUser *userA = [self createSearchUserWithName:@"A"];
    ZMSearchUser *userB = [self createSearchUserWithName:@"B"];
    ZMSearchUser *userC = [self createSearchUserWithName:@"C"];
    [result addUsersInDirectory:@[userA, userB, userC]];
    [(NSCache *) [[(id)self.mockCache stub] andReturnValue:OCMOCK_VALUE(result)] objectForKey:self.sut.token];
    
    // expect
    ZMSearchResult *expected = [[ZMSearchResult alloc] init];
    [expected addUsersInDirectory:@[userA, userC]];
    [(NSCache *) [(id)self.mockCache expect] setObject:expected forKey:self.sut.token];
    
    // when
    [self.sut removeSearchUser:userB];
    WaitForAllGroupsToBeEmpty(0.5);
    [self.mockCache verify];
}

- (void)testThatItRemovesResultsFromThePersistentStore;
{
    // given
    ZMSearchUser *userA = [self createSearchUserWithName:@"A"];
    ZMSearchUser *userB = [self createSearchUserWithName:@"B"];
    ZMSearchUser *userC = [self createSearchUserWithName:@"C"];
    
    NSArray *users = @[userA, userB, userC];
    
    self.uiMOC.suggestedUsersForUser = [NSOrderedSet orderedSetWithArray:[users valueForKey:@"remoteIdentifier"]];
    
    // when
    [self.sut removeSearchUser:userB];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    NSOrderedSet *expected = [NSOrderedSet orderedSetWithArray:@[userA.remoteIdentifier, userC.remoteIdentifier]];
    XCTAssertEqualObjects(self.uiMOC.suggestedUsersForUser, expected);
}

- (void)testThatItAddsRemovedResultsToThePersistentStoreMetadata;
{
    // given
    ZMSearchUser *userA = [self createSearchUserWithName:@"A"];
    ZMSearchUser *userB = [self createSearchUserWithName:@"B"];
    ZMSearchUser *userC = [self createSearchUserWithName:@"C"];

    // when
    [self.sut removeSearchUser:userB];
    [self.sut removeSearchUser:userC];
    WaitForAllGroupsToBeEmpty(0.5);
    
    XCTAssertFalse([self.uiMOC.removedSuggestedContactRemoteIdentifiers containsObject:userA.remoteIdentifier]);
    XCTAssertTrue([self.uiMOC.removedSuggestedContactRemoteIdentifiers containsObject:userB.remoteIdentifier]);
    XCTAssertTrue([self.uiMOC.removedSuggestedContactRemoteIdentifiers containsObject:userC.remoteIdentifier]);
    [self.syncMOC performGroupedBlockAndWait:^{
        XCTAssertFalse([self.syncMOC.removedSuggestedContactRemoteIdentifiers containsObject:userA.remoteIdentifier]);
        XCTAssertTrue([self.syncMOC.removedSuggestedContactRemoteIdentifiers containsObject:userB.remoteIdentifier]);
        XCTAssertTrue([self.syncMOC.removedSuggestedContactRemoteIdentifiers containsObject:userC.remoteIdentifier]);
    }];
}

@end
