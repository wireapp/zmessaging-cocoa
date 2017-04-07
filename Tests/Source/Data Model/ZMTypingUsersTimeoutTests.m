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


#import "ZMTypingUsersTimeout.h"
#import "MessagingTest.h"


@interface ZMTypingUsersTimeoutTests : MessagingTest

@property (nonatomic) ZMTypingUsersTimeout *sut;
@property (nonatomic) ZMConversation *conversationA;
@property (nonatomic) ZMConversation *conversationB;
@property (nonatomic) ZMUser *userA;
@property (nonatomic) ZMUser *userB;

@end



@implementation ZMTypingUsersTimeoutTests

- (void)setUp
{
    [super setUp];

    self.sut = [[ZMTypingUsersTimeout alloc] init];
    self.conversationA = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    self.conversationB = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    self.userA = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    self.userB = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    
    XCTAssert([self.uiMOC saveOrRollback]);
}

- (void)tearDown
{
    self.sut = nil;
    self.conversationA = nil;
    self.conversationB = nil;
    self.userA = nil;
    self.userB = nil;

    [super tearDown];
}

- (void)testThatItDoesNotContainUsersThatWeNotAdded;
{
    XCTAssertFalse([self.sut containsUser:self.userA conversation:self.conversationA]);
    XCTAssertFalse([self.sut containsUser:self.userB conversation:self.conversationB]);
}

- (void)testThatItCanAddAUser
{
    // when
    [self.sut addUser:self.userA conversation:self.conversationA withTimeout:[NSDate date]];
    
    // then
    XCTAssertTrue([self.sut containsUser:self.userA conversation:self.conversationA]);
}

- (void)testThatItCanRemoveAUser;
{
    // given
    [self.sut addUser:self.userA conversation:self.conversationA withTimeout:[NSDate date]];
    [self.sut addUser:self.userB conversation:self.conversationA withTimeout:[NSDate date]];
    
    // when
    [self.sut removeUser:self.userA conversation:self.conversationA];
    
    // then
    XCTAssertFalse([self.sut containsUser:self.userA conversation:self.conversationA]);
    XCTAssertTrue([self.sut containsUser:self.userB conversation:self.conversationA]);
}

- (void)testThatFirstTimeoutIsNilIfTimeoutsIsEmpty
{
    XCTAssertNil(self.sut.firstTimeout);
}

- (void)testThatFirstTimeOutIsNilForUsersAddedAndRemovedAgain
{
    // given
    [self.sut addUser:self.userA conversation:self.conversationA withTimeout:[NSDate date]];

    // when
    [self.sut removeUser:self.userA conversation:self.conversationA];
    
    // then
    XCTAssertNil(self.sut.firstTimeout);
}

- (void)testThatItReturnsTheTimeoutWhenAUserIsAdded;
{
    // given
    NSDate *timeout = [NSDate date];
    
    // when
    [self.sut addUser:self.userA conversation:self.conversationA withTimeout:timeout];
    
    // then
    XCTAssertEqual(self.sut.firstTimeout, timeout);
}

- (void)testThatItReturnsTheEarliestTimeoutWhenMultipleAreAdded;
{
    // given
    NSDate *timeout1 = [NSDate date];
    NSDate *timeout2 = [timeout1 dateByAddingTimeInterval:10];
    NSDate *timeout3 = [timeout1 dateByAddingTimeInterval:20];
    
    // when
    [self.sut addUser:self.userA conversation:self.conversationA withTimeout:timeout1];
    [self.sut addUser:self.userA conversation:self.conversationB withTimeout:timeout2];
    [self.sut addUser:self.userB conversation:self.conversationA withTimeout:timeout3];
    
    // then
    XCTAssertEqual(self.sut.firstTimeout, timeout1);
}

- (void)testThatItReturnsTheLastSetTimeoutWhenAddedMultipleTimesForTheSameUserAndConversation
{
    // given
    NSDate *timeout1 = [NSDate date];
    NSDate *timeout2 = [timeout1 dateByAddingTimeInterval:10];
    NSDate *timeout3 = [timeout1 dateByAddingTimeInterval:20];
    
    // when
    [self.sut addUser:self.userA conversation:self.conversationA withTimeout:timeout1];
    [self.sut addUser:self.userA conversation:self.conversationA withTimeout:timeout2];
    [self.sut addUser:self.userA conversation:self.conversationA withTimeout:timeout3];
    
    // then
    XCTAssertEqual(self.sut.firstTimeout, timeout3);
}

- (void)testThatItReturnsTheCurrentlyTypingUserIDs;
{
    // given
    [self.sut addUser:self.userA conversation:self.conversationA withTimeout:[NSDate date]];
    [self.sut addUser:self.userB conversation:self.conversationA withTimeout:[NSDate date]];
    
    // when
    NSSet *result = [self.sut userIDsInConversation:self.conversationA];
    NSSet *expected = [NSSet setWithObjects:self.userA.objectID, self.userB.objectID, nil];
    
    // then
    XCTAssertEqualObjects(result, expected);
}

- (void)testThatItReturnsAnEmptySetWhenNoUsersAreTyping;
{
    NSSet *result = [self.sut userIDsInConversation:self.conversationA];
    
    // then
    XCTAssertEqualObjects(result, [NSSet set]);
}

- (void)testThatItReturnsAnEmptySetWhenPruningAndNothingWasAdded;
{
    XCTAssertEqualObjects([self.sut pruneConversationsThatHaveTimedOutAfter:[NSDate dateWithTimeIntervalSinceNow:-10]], [NSSet set]);
}

- (void)testThatItReturnsAnEmptySetWhenPruningAndNothingHasExpired;
{
    // given
    NSDate *timeout = [NSDate dateWithTimeIntervalSinceNow:10];
    [self.sut addUser:self.userA conversation:self.conversationA withTimeout:timeout];
    
    // when
    XCTAssertEqualObjects([self.sut pruneConversationsThatHaveTimedOutAfter:[NSDate date]], [NSSet set]);
}

- (void)testThatItReturnsAPrunedConversation;
{
    // given
    NSDate *timeout1 = [NSDate dateWithTimeIntervalSinceNow:10];
    NSDate *timeout2 = [NSDate dateWithTimeIntervalSinceNow:20];
    [self.sut addUser:self.userA conversation:self.conversationA withTimeout:timeout1];
    
    // when
    NSSet *expected = [NSSet setWithObject:self.conversationA.objectID];
    XCTAssertEqualObjects([self.sut pruneConversationsThatHaveTimedOutAfter:timeout2], expected);
}

- (void)testThatItReturnsMultiplePrunedConversations;
{
    // given
    NSDate *timeout1 = [NSDate dateWithTimeIntervalSinceNow:10];
    NSDate *timeout2 = [NSDate dateWithTimeIntervalSinceNow:20];
    [self.sut addUser:self.userA conversation:self.conversationA withTimeout:timeout1];
    [self.sut addUser:self.userB conversation:self.conversationB withTimeout:timeout1];
    
    // when
    NSSet *expected = [NSSet setWithObjects:self.conversationA.objectID, self.conversationB.objectID, nil];
    XCTAssertEqualObjects([self.sut pruneConversationsThatHaveTimedOutAfter:timeout2], expected);
}

- (void)testThatItRemovesUsersWhenPruning;
{
    // given
    NSDate *timeout1 = [NSDate dateWithTimeIntervalSinceNow:10];
    NSDate *timeout2 = [NSDate dateWithTimeIntervalSinceNow:15];
    NSDate *timeout3 = [NSDate dateWithTimeIntervalSinceNow:20];
    [self.sut addUser:self.userA conversation:self.conversationA withTimeout:timeout1];
    [self.sut addUser:self.userB conversation:self.conversationA withTimeout:timeout3];
    
    // when
    [self.sut pruneConversationsThatHaveTimedOutAfter:timeout2];
    
    // then
    XCTAssertFalse([self.sut containsUser:self.userA conversation:self.conversationA]);
    XCTAssertTrue([self.sut containsUser:self.userB conversation:self.conversationA]);
    XCTAssertEqualObjects([self.sut userIDsInConversation:self.conversationA], [NSSet setWithObject:self.userB.objectID]);
}

@end
