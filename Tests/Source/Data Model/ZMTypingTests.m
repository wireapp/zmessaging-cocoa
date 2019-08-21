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
#import "ZMTyping.h"
#import "WireSyncEngine_iOS_Tests-Swift.h"


@interface ZMTypingTests : MessagingTest <ZMTypingChangeObserver>

@property (nonatomic) ZMTyping *sut;
@property (nonatomic) id typingObserverToken;
@property (nonatomic) NSMutableArray<TypingChange *> *receivedNotifications;
@property (nonatomic) ZMConversation *conversationA;
@property (nonatomic) ZMUser *userA;
@property (nonatomic) ZMUser *userB;
@property (nonatomic) ZMUser *userAonUI;
@property (nonatomic) ZMUser *userBonUI;

@end



@implementation ZMTypingTests

- (void)setUp
{
    [super setUp];
    self.sut = [[ZMTyping alloc] initWithUserInterfaceManagedObjectContext:self.uiMOC syncManagedObjectContext:self.syncMOC];
    [self resetNotifications];
    
    [self.syncMOC performGroupedBlockAndWait:^{
        self.conversationA = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        self.userA = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        self.userB = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];

        XCTAssert([self.syncMOC saveOrRollback]);

    }];

    ZMConversation *uiConversation = (id) [self.uiMOC objectWithID:self.conversationA.objectID];
    self.typingObserverToken = [uiConversation addTypingObserver:self];

    self.userAonUI = (id) [self.uiMOC objectWithID:self.userA.objectID];
    self.userBonUI = (id) [self.uiMOC objectWithID:self.userB.objectID];
}

- (void)tearDown
{
    self.typingObserverToken = nil;
    [self.sut tearDown];
    self.sut = nil;
    self.conversationA = nil;
    self.userA = nil;
    self.userB = nil;
    self.receivedNotifications = nil;
    [super tearDown];
}

- (void)resetNotifications
{
    self.receivedNotifications = [NSMutableArray array];
}

- (void)typingDidChangeWithConversation:(ZMConversation *)conversation typingUsers:(NSSet<ZMUser *> *)typingUsers
{
    [self.receivedNotifications addObject:[[TypingChange alloc] initWithConversation:conversation typingUsers:typingUsers]];
}

- (ZMConversation *)createConversationWithUser:(ZMUser *)user
{
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    conversation.conversationType = ZMConversationTypeGroup;
    [conversation internalAddParticipants:@[user]];
    return conversation;
}


- (ZMUser *)createUser
{
    return [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
}


- (void)testThatTimeoutIsInitializedWithDefault
{
    XCTAssertEqual(self.sut.timeout, ZMTypingDefaultTimeout);
}

- (void)testThatItSendsOutANotificationWhenAUsersStartsTyping;
{
    // when
    [self.syncMOC performGroupedBlockAndWait:^{
        [self.sut setIsTyping:YES forUser:self.userA inConversation:self.conversationA];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(self.receivedNotifications.count, 1u);
    TypingChange *note = self.receivedNotifications.firstObject;
    XCTAssertEqualObjects(note.conversation.objectID, self.conversationA.objectID);
    XCTAssertEqualObjects(note.typingUsers, [NSSet setWithObject:self.userAonUI]);
}

- (void)testThatItDoesNotSendOutANotificationWhenTheUsersIsAlreadyTyping;
{
    // given
    [self.syncMOC performGroupedBlockAndWait:^{
        [self.sut setIsTyping:YES forUser:self.userA inConversation:self.conversationA];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    [self.receivedNotifications removeAllObjects];

    // when
    [self.syncMOC performGroupedBlockAndWait:^{
        [self.sut setIsTyping:YES forUser:self.userA inConversation:self.conversationA];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(self.receivedNotifications.count, 0u);
}

- (void)testThatItSendsOutANotificationWhenAUsersStopsTyping;
{
    // given
    [self.syncMOC performGroupedBlockAndWait:^{
        [self.sut setIsTyping:YES forUser:self.userA inConversation:self.conversationA];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    [self.receivedNotifications removeAllObjects];
    
    // when
    [self.syncMOC performGroupedBlockAndWait:^{
        [self.sut setIsTyping:NO forUser:self.userA inConversation:self.conversationA];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(self.receivedNotifications.count, 1u);
    TypingChange *note = self.receivedNotifications.firstObject;
    XCTAssertEqualObjects(note.conversation.objectID, self.conversationA.objectID);
    XCTAssertEqualObjects(note.typingUsers, [NSSet set]);
}

- (void)testThatItSendsOutANotificationWhenAUsersTimesOut;
{
    // given
    NSTimeInterval const timeout = 0.1;
    self.sut.timeout = timeout;
    
    [self.syncMOC performGroupedBlockAndWait:^{
        [self.sut setIsTyping:YES forUser:self.userA inConversation:self.conversationA];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    [self.receivedNotifications removeAllObjects];

    // when
    [self spinMainQueueWithTimeout:timeout + 0.2];
    
    // then
    XCTAssertEqual(self.receivedNotifications.count, 1u);
    TypingChange *note = self.receivedNotifications.firstObject;
    XCTAssertEqualObjects(note.conversation.objectID, self.conversationA.objectID);
    XCTAssertEqualObjects(note.typingUsers, [NSSet set]);
}

- (void)testThatItDoesNotSendsOutANotificationWhenTheUserTypesAgainWithinTheTimeout
{
    // given
    NSTimeInterval const timeout = 0.5;
    self.sut.timeout = timeout;
    
    [self.syncMOC performGroupedBlockAndWait:^{
        [self.sut setIsTyping:YES forUser:self.userA inConversation:self.conversationA];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    [self.receivedNotifications removeAllObjects];
    
    [self spinMainQueueWithTimeout:timeout * 0.5]; // 1/2 the timeout interval
    
    // when (user types again)
    [self.syncMOC performGroupedBlockAndWait:^{
        [self.sut setIsTyping:YES forUser:self.userA inConversation:self.conversationA];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    [self spinMainQueueWithTimeout:timeout * 0.5];
    
    // then
    XCTAssertEqual(self.receivedNotifications.count, 0u);
}

- (void)testThatItSendsOutANotificationsAgainWhenAUsersTimesOutInARow;
{
    // given
    NSTimeInterval const timeout = 0.1;
    self.sut.timeout = timeout;
    
    [self.syncMOC performGroupedBlockAndWait:^{
        [self.sut setIsTyping:YES forUser:self.userA inConversation:self.conversationA];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    [self.receivedNotifications removeAllObjects];
    
    [self spinMainQueueWithTimeout:timeout * 0.5]; // 1/2 of the timeout

    [self.syncMOC performGroupedBlockAndWait:^{
        [self.sut setIsTyping:YES forUser:self.userB inConversation:self.conversationA];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    [self.receivedNotifications removeAllObjects];
    
    // when (1)
    [self spinMainQueueWithTimeout:timeout * 0.6];
    
    // then (1)
    XCTAssertEqual(self.receivedNotifications.count, 1u);
    TypingChange *note = self.receivedNotifications.firstObject;
    [self.receivedNotifications removeAllObjects];
    XCTAssertEqualObjects(note.conversation.objectID, self.conversationA.objectID);
    XCTAssertEqualObjects(note.typingUsers, [NSSet setWithObject:self.userBonUI]);
    
    // when (2)
    [self spinMainQueueWithTimeout:timeout * 0.6];
    
    // then (1)
    XCTAssertEqual(self.receivedNotifications.count, 1u);
    note = self.receivedNotifications.firstObject;
    XCTAssertEqualObjects(note.conversation.objectID, self.conversationA.objectID);
    XCTAssertEqualObjects(note.typingUsers, [NSSet set]);
}

@end
