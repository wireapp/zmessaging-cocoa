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

@import ZMTransport;
@import zmessaging;
@import ZMCDataModel;

#import "MessagingTest.h"
#import "ZMIncompleteConversationsCache.h"
#import "ZMTimingTests.h"
#import "ZMOperationLoop.h"
#import "ZMChangeTrackerBootstrap+Testing.h"

@interface ZMIncompleteConversationsCacheTests : MessagingTest

@property (nonatomic) ZMIncompleteConversationsCache<ZMContextChangeTracker> *sut;
@property (nonatomic) NSUInteger newRequestNotifications;
@property (nonatomic, strong) void (^notificationValidationBlock)();

@property (nonatomic) OCMockObject *operationLoopMock;
@end

@implementation ZMIncompleteConversationsCacheTests

- (void)setUp
{
    [super setUp];
    self.operationLoopMock = [OCMockObject mockForClass:ZMOperationLoop.class];
    [[[[self.operationLoopMock stub] classMethod] andCall:@selector(didReceiveNewRequestNotification:)  onObject:self] notifyNewRequestsAvailable:OCMOCK_ANY];
}

- (void)setUpIncompleteConversationCache
{
    [self.sut tearDown];
    self.sut = (id)[[ZMIncompleteConversationsCache alloc] initWithContext:self.syncMOC];
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)tearDown
{
    WaitForAllGroupsToBeEmpty(0.5);
    [self.operationLoopMock stopMocking];
    self.operationLoopMock = nil;
    
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self.sut tearDown];
    self.sut = nil;
    self.newRequestNotifications = 0;
    self.notificationValidationBlock = nil;
    [super tearDown];
}

- (void)didReceiveNewRequestNotification:(id<NSObject>)sender;
{
    NOT_USED(sender);
    self.newRequestNotifications += 1;
    if (self.notificationValidationBlock) {
        self.notificationValidationBlock();
    }
}

- (ZMConversation *)createCompleteConversationOnSyncMoc
{
    return [self createCompleteConversationOnSyncMocWithLatestEventIDMajor:30];
}

- (ZMConversation *)createCompleteConversationOnSyncMocWithLatestEventIDMajor:(NSUInteger)major;
{
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
    uint64_t minor = 3;
    conversation.lastEventID = [ZMEventID eventIDWithMajor:major minor:minor];
    conversation.lastReadEventID = [ZMEventID eventIDWithMajor:major/2 minor:12];
    ZMEventIDRange *range = [[ZMEventIDRange alloc] initWithEventIDs:@[[ZMEventID eventIDWithMajor:1 minor:3], [ZMEventID eventIDWithMajor:major minor:minor]]];
    [conversation addEventRangeToDownloadedEvents:range];
    [self.syncMOC saveOrRollback];
    return conversation;
}

- (ZMConversation *)createIncompleteConversationOnSyncMoc
{
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
    conversation.conversationType = ZMConversationTypeGroup;
    conversation.lastEventID = [ZMEventID eventIDWithMajor:300 minor:3];
    [self.syncMOC saveOrRollback];
    return conversation;
}

- (ZMConversation *)createIncompleteConversationWithNoGapsInWindowOnSyncMocButAtTheBegining
{
    const uint64_t maxDownloadedEventID = 200;
    const uint64_t lastEventID = maxDownloadedEventID + 10;
    ZMConversation *conversation = [self createCompleteConversationOnSyncMocWithLatestEventIDMajor:maxDownloadedEventID];
    [conversation addEventToDownloadedEvents:[ZMEventID eventIDWithMajor:lastEventID minor:12] timeStamp:nil]; // this is beyond maxEventID so will make it incomplete
    
    ZMMessage *msg1 = [ZMTextMessage insertNewObjectInManagedObjectContext:self.syncMOC];
    msg1.eventID = [ZMEventID eventIDWithMajor:1 minor:2];
    ZMMessage *msg2 = [ZMTextMessage insertNewObjectInManagedObjectContext:self.syncMOC];
    msg2.eventID = [ZMEventID eventIDWithMajor:maxDownloadedEventID-1 minor:2]; // this is less than maxEventID so it will make the window complete
    
    [conversation setVisibleWindowFromMessage:msg1 toMessage:msg2];
    [self.syncMOC saveOrRollback];
    return conversation;
}

- (ZMConversation *)createIncompleteConversationWithNoGapsInWindowOnSyncMoc
{
    const uint64_t lastEventID = 200;
    ZMConversation *conversation = [self createCompleteConversationOnSyncMocWithLatestEventIDMajor:lastEventID];
    
    ZMMessage *msg1 = [ZMTextMessage insertNewObjectInManagedObjectContext:self.syncMOC];
    msg1.eventID = [ZMEventID eventIDWithMajor:1 minor:2];
    ZMMessage *msg2 = [ZMTextMessage insertNewObjectInManagedObjectContext:self.syncMOC];
    msg2.eventID = [ZMEventID eventIDWithMajor:lastEventID minor:2]; // this is less than maxEventID so it will make the window complete
    
    [conversation setVisibleWindowFromMessage:msg1 toMessage:msg2];
    [self.syncMOC saveOrRollback];
    return conversation;
}

- (ZMConversation *)createIncompleteconversationWithGapsInWindowOnSyncMoc
{
    const uint64_t maxDownloadedEventID = 200;
    ZMEventID *lastEventID = [ZMEventID eventIDWithMajor:maxDownloadedEventID+10 minor:10];
    NSDate *lastServerTime = [NSDate date];
    ZMConversation *conversation = [self createCompleteConversationOnSyncMocWithLatestEventIDMajor:maxDownloadedEventID];
    conversation.lastEventID = lastEventID;
    conversation.lastServerTimeStamp = lastServerTime;
    [conversation addEventToDownloadedEvents:[ZMEventID eventIDWithMajor:maxDownloadedEventID minor:12] timeStamp:nil]; // this is beyond maxEventID so will make it incomplete
    
    ZMMessage *msg1 = [ZMTextMessage insertNewObjectInManagedObjectContext:self.syncMOC];
    msg1.eventID = [ZMEventID eventIDWithMajor:1 minor:2];
    msg1.serverTimestamp = [lastServerTime dateByAddingTimeInterval:-100];
    msg1.visibleInConversation = conversation;
    ZMMessage *msg2 = [ZMTextMessage insertNewObjectInManagedObjectContext:self.syncMOC];
    msg2.eventID = lastEventID; // this is greater than maxEventID so it will make the window complete
    msg2.serverTimestamp = lastServerTime;
    msg2.visibleInConversation = conversation;
    
    [conversation setVisibleWindowFromMessage:msg1 toMessage:msg2];
    [self.syncMOC saveOrRollback];
    return conversation;
}

- (void)completeConversationGaps:(ZMConversation *)conversation
{
    ZMEventIDRange *range = [[ZMEventIDRange alloc] initWithEventIDs:@[[ZMEventID eventIDWithMajor:1 minor:0], conversation.lastEventID]];
    [conversation addEventRangeToDownloadedEvents:range];
}

- (ZMEventIDRange *)increaseWindowToHaveAGapOnConversationAndReturnGapForConversation:(ZMConversation *)conversation;
{
    ZMEventID *previousLastEvent = conversation.lastEventID;
    [conversation addEventRangeToDownloadedEvents:[[ZMEventIDRange alloc] initWithEventIDs:@[[ZMEventID eventIDWithMajor:1 minor:2], previousLastEvent]]];
    ZMEventID *newLastEvent = [ZMEventID eventIDWithMajor:conversation.lastEventID.major + 10 minor:2];
    conversation.lastEventID = newLastEvent;
    
    ZMMessage *msg1 = [ZMTextMessage insertNewObjectInManagedObjectContext:self.syncMOC];
    msg1.eventID = [ZMEventID eventIDWithMajor:1 minor:2];
    ZMMessage *msg2 = [ZMTextMessage insertNewObjectInManagedObjectContext:self.syncMOC];
    msg2.eventID = newLastEvent;
    [conversation setVisibleWindowFromMessage:msg1 toMessage:msg2];
    return [[ZMEventIDRange alloc] initWithEventIDs:@[previousLastEvent, newLastEvent]];
}

- (void)increaseWindowAndAddDownloadedEventsSoThatThereIsNoGap:(ZMConversation *)conversation;
{
    ZMEventID *lastMessageInWindow = [ZMEventID eventIDWithMajor:conversation.lastEventID.major minor:2];
    ZMEventID *lastMessageInConversation = [ZMEventID eventIDWithMajor:lastMessageInWindow.major+20 minor:2];
    conversation.lastEventID = lastMessageInConversation;
    
    ZMEventIDRange *range = [[ZMEventIDRange alloc] initWithEventIDs:@[[ZMEventID eventIDWithMajor:1 minor:0], lastMessageInWindow]];
    [conversation addEventRangeToDownloadedEvents:range];
    
    ZMMessage *msg1 = [ZMTextMessage insertNewObjectInManagedObjectContext:self.syncMOC];
    msg1.eventID = [ZMEventID eventIDWithMajor:1 minor:2];
    ZMMessage *msg2 = [ZMTextMessage insertNewObjectInManagedObjectContext:self.syncMOC];
    msg2.eventID = lastMessageInWindow;
    [conversation setVisibleWindowFromMessage:msg1 toMessage:msg2];
}

- (void)increaseWindowAndAddDownloadedEventsToLastEventIDSoThatThereIsNoGap:(ZMConversation *)conversation;
{
    ZMEventID *firstMessageDownloaded = [ZMEventID eventIDWithMajor:conversation.lastEventID.major minor:2];

    ZMEventID *lastMessageInConversation = [ZMEventID eventIDWithMajor:conversation.lastEventID.major + 100 minor:2];
    conversation.lastEventID = lastMessageInConversation;
    
    ZMEventID *firstMessageInWindow =[ZMEventID eventIDWithMajor:conversation.lastEventID.major - 20 minor:2];
    ZMEventID *lastMessageInWindow = [ZMEventID eventIDWithMajor:conversation.lastEventID.major minor:2];
    
    
    ZMEventIDRange *range = [[ZMEventIDRange alloc] initWithEventIDs:@[firstMessageDownloaded, lastMessageInWindow]];
    [conversation addEventRangeToDownloadedEvents:range];
    conversation.lastReadEventID = lastMessageInConversation;
    
    ZMMessage *msg1 = [ZMTextMessage insertNewObjectInManagedObjectContext:self.syncMOC];
    msg1.eventID = firstMessageInWindow;
    ZMMessage *msg2 = [ZMTextMessage insertNewObjectInManagedObjectContext:self.syncMOC];
    msg2.eventID = lastMessageInWindow;
    [conversation setVisibleWindowFromMessage:msg1 toMessage:msg2];
}

/// Do not call this on the syncMoc if the sut is on the sync moc!
- (void)postNotificationToLoadConversation:(NSManagedObjectID *)conversationObjectID
{
    ZMConversation *conversation = (ZMConversation *)[self.uiMOC objectWithID:conversationObjectID];
    [[NSNotificationCenter defaultCenter] postNotificationName:ZMConversationRequestToLoadConversationEventsNotification object:conversation];
}

- (void)postNotificationForWindowDidChangeInConversation:(ZMConversation *)conversation newUpperBound:(NSUInteger)upperbound newLowerBound:(NSUInteger)lowerbound
{
    NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
    userInfo[ZMVisibleWindowUpperKey] = [ZMEventID eventIDWithMajor:upperbound minor:3];
    userInfo[ZMVisibleWindowLowerKey] = [ZMEventID eventIDWithMajor:lowerbound minor:3];;
    [[NSNotificationCenter defaultCenter] postNotificationName:ZMConversationDidChangeVisibleWindowNotification object:conversation userInfo:userInfo];
}

- (void)testThatItReturnsTheCorrectFetchRequest
{
    // given
    [self setUpIncompleteConversationCache];
    
    // when
    NSFetchRequest *fetchRequest = [self.sut fetchRequestForTrackedObjects];
    
    // then
    NSFetchRequest *expected = [ZMConversation sortedFetchRequest];
    XCTAssertEqualObjects(fetchRequest, expected);
}

- (void)testThatContainsIncompleteNonWhitelistedConversationsWhenCreated
{
    // given
    __block ZMConversation *conversation1;
    __block ZMConversation *conversation2;
    [self.syncMOC performGroupedBlockAndWait:^{
        conversation1 = [self createIncompleteConversationOnSyncMoc];
        conversation2 = [self createIncompleteConversationOnSyncMoc];
    }];
    
    // when
    [self setUpIncompleteConversationCache];
    [ZMChangeTrackerBootstrap bootStrapChangeTrackers:@[self.sut] onContext:self.syncMOC];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    [self.syncMOC performGroupedBlockAndWait:^{
        NSSet *incompleteConversations = self.sut.incompleteNonWhitelistedConversations.set;
        NSSet *expectedSet = [NSSet setWithObjects:conversation1, conversation2, nil];
        XCTAssertEqualObjects(incompleteConversations, expectedSet);
    }];
}

- (void)testThatItDoesNotContainAnyCompleteConversationsWhenItIsCreated
{
    // given
    [self.syncMOC performGroupedBlockAndWait:^{
        id conversation = [self createCompleteConversationOnSyncMoc];
        [self.sut objectsDidChange:[NSSet setWithObject:conversation]];
    }];
    // when
    [self setUpIncompleteConversationCache];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    [self.syncMOC performGroupedBlockAndWait:^{
        NSOrderedSet *incompleteNonWhitelistedConversations = self.sut.incompleteNonWhitelistedConversations;
        XCTAssertEqual(0u, incompleteNonWhitelistedConversations.count);
        NSOrderedSet *incompleteWhitelistedConversations = self.sut.incompleteWhitelistedConversations;
        XCTAssertEqual(0u, incompleteWhitelistedConversations.count);
    }];
}

- (void)testThatItAddsANewIncompleteConversation
{
    // given
    [self setUpIncompleteConversationCache];
    [self.syncMOC performGroupedBlockAndWait:^{
        
        ZMConversation *conversation = [self createIncompleteConversationOnSyncMoc];
        [self.sut objectsDidChange:[NSSet setWithObject:conversation]];
        
        // then
        NSOrderedSet *incompleteNonWhitelistedConversations = self.sut.incompleteNonWhitelistedConversations;
        XCTAssertEqual(1u, incompleteNonWhitelistedConversations.count);
        XCTAssertEqualObjects(incompleteNonWhitelistedConversations.firstObject, conversation);
        
        NSOrderedSet *incompleteWhitelistedConversations = self.sut.incompleteWhitelistedConversations;
        XCTAssertEqual(0u, incompleteWhitelistedConversations.count);
    }];
}


- (void)testThatItAddANewIncompleteAndWhitelistedConversation
{
    // given
    [self setUpIncompleteConversationCache];
    __block NSManagedObjectID *conversationID;
    [self.syncMOC performGroupedBlockAndWait:^{
        
        ZMConversation *conversation = [self createIncompleteConversationOnSyncMoc];
        [self.sut objectsDidChange:[NSSet setWithObject:conversation]];
        conversationID = conversation.objectID;
    }];
    
    // when
    [self postNotificationToLoadConversation:conversationID];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    [self.syncMOC performGroupedBlockAndWait:^{
        NSOrderedSet *incompleteWhitelistedConversations = self.sut.incompleteWhitelistedConversations;
        XCTAssertEqual(1u, incompleteWhitelistedConversations.count);
        XCTAssertEqualObjects([(ZMConversation *)incompleteWhitelistedConversations.firstObject objectID],conversationID);
    }];
}

- (void)testThatItAddsAWhitelistedConversationWhenTheConversationIsModifiedAndItHasAGapInTheWindow
{
    // given
    [self setUpIncompleteConversationCache];
    __block NSManagedObjectID *conversationID;
    [self.syncMOC performGroupedBlockAndWait:^{
        
        ZMConversation *conversation = [self createIncompleteconversationWithGapsInWindowOnSyncMoc];
        conversationID = conversation.objectID;
    }];
    
    // when
    [self postNotificationToLoadConversation:conversationID];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    [self.syncMOC performGroupedBlockAndWait:^{
        NSOrderedSet *incompleteConversations = self.sut.incompleteWhitelistedConversations;
        XCTAssertEqual(1u, incompleteConversations.count);
        XCTAssertEqualObjects([(ZMConversation *)incompleteConversations.firstObject objectID],conversationID);
    }];
}


- (void)testThatItDoesNotAddAWhitelistedConversationWhenItIsModifiedAndItHasNoGapInTheWindow
{
    // given
    [self setUpIncompleteConversationCache];
    __block NSManagedObjectID *conversationID;
    [self.syncMOC performGroupedBlockAndWait:^{
        
        ZMConversation *conversation = [self createIncompleteConversationWithNoGapsInWindowOnSyncMoc];
        conversationID = conversation.objectID;
     }];
    
    // when
    [self postNotificationToLoadConversation:conversationID];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    [self.syncMOC performGroupedBlockAndWait:^{
        NSOrderedSet *incompleteConversations = self.sut.incompleteWhitelistedConversations;
        XCTAssertEqual(0u, incompleteConversations.count);
    }];
}

- (void)testThatItNotifiesThatRequestIsDoneWhenRemovesAWhitelistedConversationWhenItIsModifiedToHaveNoGap
{
    //given
    [self setUpIncompleteConversationCache];
    __block ZMConversation *syncMocConversation;
    [self.syncMOC performGroupedBlockAndWait:^{
        
        syncMocConversation = [self createIncompleteconversationWithGapsInWindowOnSyncMoc];
    }];
    [self postNotificationToLoadConversation:syncMocConversation.objectID];
    WaitForAllGroupsToBeEmpty(0.5);
    
    XCTestExpectation *notificationExpectation = [self expectationWithDescription:@"done fetching messages"];

    [[NSNotificationCenter defaultCenter] addObserverForName:ZMConversationDidFinishFetchingMessages
                                                      object:nil
                                                       queue:[NSOperationQueue currentQueue]
                                                  usingBlock:^(NSNotification * _Nonnull note ZM_UNUSED) {
                                                      [notificationExpectation fulfill];
                                                  }];
    
    // when
    [self.syncMOC performGroupedBlockAndWait:^{
        
        [self completeConversationGaps:syncMocConversation];
        [self.sut objectsDidChange:[NSSet setWithObject:syncMocConversation]];
    }];
    
    // then
    XCTAssert([self waitForCustomExpectationsWithTimeout:0.5]);
}

- (void)testThatItNotifiesThatRequestWillStartWhenAddingWhitelisted
{
    // given
    [self setUpIncompleteConversationCache];
    __block ZMConversation *conversation;
    [self.syncMOC performGroupedBlockAndWait:^{
        
        conversation = [self createIncompleteConversationWithNoGapsInWindowOnSyncMoc];
        [self.sut objectsDidChange:[NSSet setWithObject:conversation]];
    }];
    
    [self postNotificationToLoadConversation:conversation.objectID];
    WaitForAllGroupsToBeEmpty(0.5);
    
    XCTestExpectation *notificationExpectation = [self expectationWithDescription:@"will start request"];
    
    [[NSNotificationCenter defaultCenter] addObserverForName:ZMConversationWillStartFetchingMessages
                                                      object:nil
                                                       queue:[NSOperationQueue currentQueue]
                                                  usingBlock:^(NSNotification * _Nonnull note ZM_UNUSED) {
                                                      [notificationExpectation fulfill];
                                                  }];
    
    // when
    [self.syncMOC performGroupedBlockAndWait:^{
        XCTAssertEqual(0u, self.sut.incompleteWhitelistedConversations.count); // sanity check
        [self increaseWindowToHaveAGapOnConversationAndReturnGapForConversation:conversation];
    }];
    
    XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0.5]);
    
}

- (void)testThatItNotifiesRequestDonwWhenTheWindowIsModifiedAndItHasNoGap
{
    // given
    [self setUpIncompleteConversationCache];
    __block ZMConversation *conversation;
    [self.syncMOC performGroupedBlockAndWait:^{
        
        conversation = [self createIncompleteconversationWithGapsInWindowOnSyncMoc];
        [self.sut objectsDidChange:[NSSet setWithObject:conversation]];
        // - sanity check
        XCTAssertEqual(0u, self.sut.incompleteWhitelistedConversations.count);
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    XCTestExpectation *notificationExpectation = [self expectationWithDescription:@"will start request"];
    [[NSNotificationCenter defaultCenter] addObserverForName:ZMConversationDidFinishFetchingMessages
                                                      object:nil
                                                       queue:[NSOperationQueue currentQueue]
                                                  usingBlock:^(NSNotification * _Nonnull note ZM_UNUSED) {
                                                      [notificationExpectation fulfill];
                                                  }];
    
    
    // when
    [self.syncMOC performGroupedBlockAndWait:^{
        [self increaseWindowAndAddDownloadedEventsToLastEventIDSoThatThereIsNoGap:conversation];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    [self.syncMOC performGroupedBlockAndWait:^{
        XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0.5]);
    }];
}


- (void)testThatItDoesNotRemoveAConversationWhenTheConversationIsModifiedAndStillHasGaps
{
    // given
    [self setUpIncompleteConversationCache];
    __block ZMConversation *conversation;
    [self.syncMOC performGroupedBlockAndWait:^{
        
        conversation = [self createIncompleteconversationWithGapsInWindowOnSyncMoc];
        [self.sut objectsDidChange:[NSSet setWithObject:conversation]];
    }];
    [self postNotificationToLoadConversation:conversation.objectID];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // when
    [self.sut objectsDidChange:[NSSet setWithObject:conversation]];
    
    // then
    [self.syncMOC performGroupedBlockAndWait:^{
        XCTAssertEqual(1u, self.sut.incompleteWhitelistedConversations.count);
        XCTAssertEqualObjects(self.sut.incompleteWhitelistedConversations.lastObject, conversation);
    }];
}

- (void)testThatItAddsAConversationWhenTheWindowIsModifiedAndItHasAGap
{
    // given
    [self setUpIncompleteConversationCache];
    __block ZMConversation *conversation;
    [self.syncMOC performGroupedBlockAndWait:^{
        
        conversation = [self createIncompleteConversationWithNoGapsInWindowOnSyncMoc];
        [self.sut objectsDidChange:[NSSet setWithObject:conversation]];
    }];
    
    [self postNotificationToLoadConversation:conversation.objectID];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // when
    [self.syncMOC performGroupedBlockAndWait:^{
        XCTAssertEqual(0u, self.sut.incompleteWhitelistedConversations.count); // sanity check
        [self increaseWindowToHaveAGapOnConversationAndReturnGapForConversation:conversation];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    [self.syncMOC performGroupedBlockAndWait:^{
        XCTAssertEqual(1u, self.sut.incompleteWhitelistedConversations.count);
        XCTAssertEqual(conversation.objectID, [self.sut.incompleteWhitelistedConversations.lastObject objectID]);
        XCTAssertTrue(self.newRequestNotifications >= 1);
    }];
}

- (void)testThatItNotifiesOfANewRequestWhenTheWindowIsModifiedAndItHasAGap
{
    // given
    [self setUpIncompleteConversationCache];
    __block ZMConversation *conversation;
    [self.syncMOC performGroupedBlockAndWait:^{
        
        conversation = [self createIncompleteConversationWithNoGapsInWindowOnSyncMoc];
        [self.sut objectsDidChange:[NSSet setWithObject:conversation]];
    }];
    
    [self postNotificationToLoadConversation:conversation.objectID];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // when
    self.newRequestNotifications = 0;
    [self.syncMOC performGroupedBlockAndWait:^{
        XCTAssertEqual(0u, self.sut.incompleteWhitelistedConversations.count); // sanity check
        [self increaseWindowToHaveAGapOnConversationAndReturnGapForConversation:conversation];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(self.newRequestNotifications, 1u);
}

- (void)testThatConversationIsNotWhitelistedWhenTheWindowIsModifiedToNilAndTheConversationIsComplete
{
    // given
    [self setUpIncompleteConversationCache];
    __block ZMConversation *conversation;
    [self.syncMOC performGroupedBlockAndWait:^{
        
        conversation = [self createCompleteConversationOnSyncMoc];
        [self.sut objectsDidChange:[NSSet setWithObject:conversation]];
        // - sanity check
        XCTAssertEqual(0u, self.sut.incompleteWhitelistedConversations.count);
    }];
    
    // when
    [self.syncMOC performGroupedBlockAndWait:^{
        [conversation setVisibleWindowFromMessage:nil toMessage:nil];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    [self.syncMOC performGroupedBlockAndWait:^{
        XCTAssertEqual(0u, self.sut.incompleteWhitelistedConversations.count);
        XCTAssertEqual(0u, self.sut.incompleteNonWhitelistedConversations.count);
    }];
}


- (void)testThatConversationIsNotWhitelistedWhenTheWindowIsModifiedToNil
{
    // given
    [self setUpIncompleteConversationCache];
    __block ZMConversation *conversation;
    [self.syncMOC performGroupedBlockAndWait:^{
        
        conversation = [self createIncompleteConversationOnSyncMoc];
        [self.sut objectsDidChange:[NSSet setWithObject:conversation]];
        // - sanity check
        XCTAssertEqual(0u, self.sut.incompleteWhitelistedConversations.count);
    }];
    
    // when
    [self.syncMOC performGroupedBlockAndWait:^{
        [conversation setVisibleWindowFromMessage:nil toMessage:nil];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    [self.syncMOC performGroupedBlockAndWait:^{
        XCTAssertEqual(0u, self.sut.incompleteWhitelistedConversations.count);
        XCTAssertEqual(1u, self.sut.incompleteNonWhitelistedConversations.count);
    }];
}

- (void)testThatTheObjectsStoredInTheCacheWhenSettingTheWindowAreFromTheSyncContext
{
    // given
    [self setUpIncompleteConversationCache];
    __block ZMConversation *conversation;
    [self.syncMOC performGroupedBlockAndWait:^{
        
        conversation = [self createIncompleteConversationWithNoGapsInWindowOnSyncMoc];
        [self.sut objectsDidChange:[NSSet setWithObject:conversation]];
    }];
    
    [self postNotificationToLoadConversation:conversation.objectID];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // when
    [self.syncMOC performGroupedBlockAndWait:^{
        XCTAssertEqual(0u, self.sut.incompleteWhitelistedConversations.count); // sanity check
        [self increaseWindowToHaveAGapOnConversationAndReturnGapForConversation:conversation];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    [self.syncMOC performGroupedBlockAndWait:^{
        XCTAssertEqual(1u, self.sut.incompleteWhitelistedConversations.count);
        XCTAssertEqual(conversation.managedObjectContext, [(ZMConversation *)self.sut.incompleteWhitelistedConversations.firstObject managedObjectContext]);
    }];
}

- (void)testThatConversationsAreAddedToNonWhitelistBeforeTheNotificationIsSent
{
    // given
    [self setUpIncompleteConversationCache];
    __block ZMConversation *conversation;
    [self.syncMOC performGroupedBlockAndWait:^{
        
        conversation = [self createIncompleteConversationOnSyncMoc];
        [self.sut objectsDidChange:[NSSet setWithObject:conversation]];

        XCTAssertEqual(1u, self.sut.incompleteNonWhitelistedConversations.count);
        XCTAssertEqualObjects(conversation.objectID, [self.sut.incompleteNonWhitelistedConversations.lastObject objectID]);
        
        ZM_WEAK(self);
        self.notificationValidationBlock = ^{
            ZM_STRONG(self);
            XCTAssertEqual(1u, self.sut.incompleteWhitelistedConversations.count);
            XCTAssertEqualObjects(conversation.objectID, [self.sut.incompleteWhitelistedConversations.lastObject objectID]);
        };
    }];
    
    // when
    [self postNotificationToLoadConversation:conversation.objectID];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    [self.syncMOC performGroupedBlockAndWait:^{
        XCTAssertTrue(self.newRequestNotifications >= 1);
        [self.syncMOC deleteObject:conversation];
        [self.syncMOC saveOrRollback];
    }];
}

- (void)testThatConversationsAreAddedBecauseOfWindowIncreaseBeforeTheNotificationIsSent
{
    // given
    [self setUpIncompleteConversationCache];
    __block ZMConversation *conversation;
    [self.syncMOC performGroupedBlockAndWait:^{
        
        conversation = [self createIncompleteConversationOnSyncMoc];
        [self.sut objectsDidChange:[NSSet setWithObject:conversation]];
        // - sanity check
        XCTAssertEqual(0u, self.sut.incompleteWhitelistedConversations.count);
        XCTAssertEqual(1u, self.sut.incompleteNonWhitelistedConversations.count);
        
        ZM_WEAK(self);
        self.notificationValidationBlock = ^{
            ZM_STRONG(self);
            XCTAssertEqual(1u, self.sut.incompleteWhitelistedConversations.count);
            XCTAssertEqual(conversation.objectID, [self.sut.incompleteWhitelistedConversations.lastObject objectID]);
        };
    }];
    
    [self.syncMOC performGroupedBlockAndWait:^{
        [self increaseWindowToHaveAGapOnConversationAndReturnGapForConversation:conversation];
    }];
    WaitForAllGroupsToBeEmpty(0.5);

    
    [self postNotificationToLoadConversation:conversation.objectID];
    WaitForAllGroupsToBeEmpty(0.5);

    // when
    
    // then
    [self.syncMOC performGroupedBlockAndWait:^{
        XCTAssertTrue(self.newRequestNotifications >= 1);
    }];
}

- (void)testThatItReturnsANilGapForAConversationThatIsNotInTheCache
{

    // given
    [self setUpIncompleteConversationCache];
    [self.syncMOC performGroupedBlockAndWait:^{
        
        ZMConversation *conversation = [self createCompleteConversationOnSyncMoc];
        
        // when
        ZMEventIDRange *gap = [self.sut gapForConversation:conversation];
        
        // then
        XCTAssertNil(gap);
    }];
}

- (void)testThatItReturnsTheGapForAConversation
{
    // given
    __block ZMConversation *conversation;
    __block ZMEventIDRange *givenGap;
    [self setUpIncompleteConversationCache];
    
    [self.syncMOC performGroupedBlockAndWait:^{
        
        ZMEventID *lastEvent = [ZMEventID eventIDWithMajor:1000 minor:4];
        conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        conversation.lastEventID = lastEvent;
        
        NSArray *downloadedGapArray = @[@[[ZMEventID eventIDWithMajor:1 minor:0], [ZMEventID eventIDWithMajor:250 minor:0]],
                                        @[[ZMEventID eventIDWithMajor:350 minor:0], [ZMEventID eventIDWithMajor:550 minor:0]],
                                        @[[ZMEventID eventIDWithMajor:800 minor:0], lastEvent]];
        
        for (NSArray *eventIDs in downloadedGapArray) {
            [conversation addEventRangeToDownloadedEvents:[[ZMEventIDRange alloc] initWithEventIDs:eventIDs]];
        }
        givenGap = [[ZMEventIDRange alloc] initWithEventIDs:@[[ZMEventID eventIDWithMajor:550 minor:0], [ZMEventID eventIDWithMajor:800 minor:0]]];
        
        [self.sut objectsDidChange:[NSSet setWithObject:conversation]];
        
        // when
        ZMEventIDRange *gap = [self.sut gapForConversation:conversation];
        
        // then
        XCTAssertNotNil(gap);
        XCTAssertEqualObjects(givenGap, gap);
        
        // and given
        [conversation addEventRangeToDownloadedEvents:gap];
        givenGap = [[ZMEventIDRange alloc] initWithEventIDs:@[[ZMEventID eventIDWithMajor:250 minor:0],[ZMEventID eventIDWithMajor:350 minor:0]]];
        
        // when
        gap = [self.sut gapForConversation:conversation];
        
        XCTAssertNotNil(gap);
        XCTAssertEqualObjects(givenGap, gap);
    }];
}


- (void)testThat_whitelistTopConversationsIfIncomplete_PicksTheTopConversationsToSync
{
    // given
    [self setUpIncompleteConversationCache];
    const NSUInteger ExpectedTopConversations = 5;
    const NSUInteger ConversationsToCreate = ExpectedTopConversations*3;
    NSMutableArray *expectedPriorityConversations = [NSMutableArray array];
    [self.syncMOC performGroupedBlockAndWait:^{
        
        NSMutableArray *allConversations = [NSMutableArray array];
        NSDate *lastModifiedDate = [NSDate dateWithTimeIntervalSince1970:123333];
        for(NSUInteger i = 0; i < ConversationsToCreate; ++i) {
            ZMConversation *conversation = [self createIncompleteConversationOnSyncMoc];
            // "promote" one conversation every two to be a high priority
            if(i % 2 == 0 && expectedPriorityConversations.count < ExpectedTopConversations) {
                lastModifiedDate = [lastModifiedDate dateByAddingTimeInterval:100];
                conversation.lastModifiedDate = lastModifiedDate;
                [expectedPriorityConversations insertObject:conversation atIndex:0];
            }
            [allConversations addObject:conversation];
        }
        [self.sut objectsDidChange:[NSSet setWithArray:allConversations]];
    
        // when
        [self.sut whitelistTopConversationsIfIncomplete];
    }];
    
    // then
    [self.syncMOC performGroupedBlockAndWait:^{
        NSOrderedSet *incompleteWhitelistedConversations = self.sut.incompleteWhitelistedConversations;
        XCTAssertEqual(ExpectedTopConversations, incompleteWhitelistedConversations.count);
        XCTAssertEqualObjects(expectedPriorityConversations, self.sut.incompleteWhitelistedConversations.array);
    }];
}

- (void)testThatItAddsAConversationThatIsCurrentlyViewedToBeSyncedFirst_AndRemovesThePreviouslyWhitelisted
{
    // given
    [self setUpIncompleteConversationCache];
    __block ZMConversation *conversation1;
    __block ZMConversation *conversation2;
    [self.syncMOC performGroupedBlockAndWait:^{
        conversation1 = [self createIncompleteconversationWithGapsInWindowOnSyncMoc];
        conversation2 = [self createIncompleteconversationWithGapsInWindowOnSyncMoc];
        [self.sut objectsDidChange:[NSSet setWithObjects:conversation1, conversation2, nil]];
    }];
    
    // when
    [self postNotificationToLoadConversation:conversation1.objectID];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    [self.syncMOC performGroupedBlockAndWait:^{
        NSOrderedSet *incompleteWhitelistedConversations = self.sut.incompleteWhitelistedConversations;
        XCTAssertEqual(1u, incompleteWhitelistedConversations.count);
        XCTAssertEqualObjects(incompleteWhitelistedConversations.firstObject,conversation1);
    }];
    
    // and when
    [self postNotificationToLoadConversation:conversation2.objectID];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    [self.syncMOC performGroupedBlockAndWait:^{
        NSOrderedSet *incompleteWhitelistedConversations = self.sut.incompleteWhitelistedConversations;
        XCTAssertEqual(1u, incompleteWhitelistedConversations.count);
        XCTAssertEqualObjects(incompleteWhitelistedConversations.firstObject,conversation2);
    }];
}

- (void)testThatItReturnsTheProperGapSizeWhenUsingAWindow
{
    // given
    [self setUpIncompleteConversationCache];
    __block ZMConversation *conversation;
    __block ZMEventIDRange *expectedRange;
    [self.syncMOC performGroupedBlockAndWait:^{
        conversation = [self createCompleteConversationOnSyncMoc];

        // when
        expectedRange = [self increaseWindowToHaveAGapOnConversationAndReturnGapForConversation:conversation];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMEventIDRange *gap = [self.sut gapForConversation:conversation];
        XCTAssertEqualObjects(gap, expectedRange);
    }];
}

- (void)testThatIt_whitelistTopConversationsIfIncomplete_WhitelistsOnlyNonArchivedAndNonBlockedConversations
{
    // given
    [self setUpIncompleteConversationCache];
    __block ZMConversation *conversation1;
    __block ZMConversation *archivedConversation;
    __block ZMConversation *blockedUserConversation;
    
    [self.syncMOC performGroupedBlockAndWait:^{
        
        conversation1 = [self createIncompleteConversationOnSyncMoc];
        archivedConversation = [self createIncompleteConversationOnSyncMoc];
        archivedConversation.isArchived = YES;
        blockedUserConversation = [self createIncompleteConversationOnSyncMoc];
        blockedUserConversation.conversationType = ZMConversationTypeOneOnOne;
        ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        ZMConnection *connection = [ZMConnection insertNewObjectInManagedObjectContext:self.syncMOC];
        connection.to = user;
        connection.conversation = blockedUserConversation;
        connection.status = ZMConnectionStatusBlocked;
        
        [self.sut objectsDidChange:[NSSet setWithObjects:conversation1, archivedConversation, blockedUserConversation, nil]];
        
        // when
        [self.sut whitelistTopConversationsIfIncomplete];
    }];
    // then
    [self.syncMOC performGroupedBlockAndWait:^{
        NSOrderedSet *incompleteWhitelistedConversations = self.sut.incompleteWhitelistedConversations;
        XCTAssertEqual(1u, incompleteWhitelistedConversations.count);
        XCTAssertEqualObjects(conversation1, self.sut.incompleteWhitelistedConversations.firstObject);
    }];
}
- (void)testThatItDoesNotRequestEventsPriorToClearedEventID
{
    // given
    [self setUpIncompleteConversationCache];
    __block ZMConversation *conversation;
    [self.syncMOC performGroupedBlockAndWait:^{
        conversation = [self createIncompleteconversationWithGapsInWindowOnSyncMoc];
        XCTAssertNotNil([self.sut gapForConversation:conversation]);
        
        // when
        [conversation clearMessageHistory];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMEventIDRange *gap = [self.sut gapForConversation:conversation];
        XCTAssertNil(gap);
    }];
    
}



@end

