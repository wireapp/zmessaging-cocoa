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

#import "ZMTyping.h"
#import "ZMTypingUsers.h"
#import "WireSyncEngine_iOS_Tests-Swift.h"


@interface IsTypingTests : IntegrationTest <ZMTypingChangeObserver>

@property (nonatomic) NSTimeInterval oldTimeout;
@property (nonatomic) NSMutableArray<TypingChange *> *notifications;

@end


@implementation IsTypingTests

- (void)setUp
{
    self.oldTimeout = ZMTypingDefaultTimeout;
    ZMTypingDefaultTimeout = 2;
    
    [super setUp];
    
    [self createSelfUserAndConversation];
    [self createExtraUsersAndConversations];
    
    self.notifications = [NSMutableArray array];
}

- (void)tearDown
{
    ZMTypingDefaultTimeout = self.oldTimeout;
    [super tearDown];
}

- (void)typingDidChangeWithConversation:(ZMConversation *)conversation typingUsers:(NSSet<ZMUser *> *)typingUsers
{
    [self.notifications addObject:[[TypingChange alloc] initWithConversation:conversation typingUsers:typingUsers]];
}

- (void)testThatItSendsTypingNotifications;
{
    XCTAssertTrue([self login]);
    
    ZMConversation *conversation = [self conversationForMockConversation:self.groupConversation];
    ZMUser *user1 = [self userForMockUser:self.user1];
    id token = [conversation addTypingObserver:self];
    
    XCTAssertEqual(conversation.typingUsers.count, 0u);
    
    [self.mockTransportSession sendIsTypingEventForConversation:self.groupConversation user:self.user1 started:YES];
    WaitForAllGroupsToBeEmpty(0.5);
    
    XCTAssertEqual(self.notifications.count, 1u);
    TypingChange *note = self.notifications.firstObject;
    XCTAssertEqual(note.conversation, conversation);
    XCTAssertEqual(note.typingUsers.count, 1u);
    XCTAssertEqual(note.typingUsers.anyObject, user1);
    XCTAssertEqual(conversation.typingUsers.count, 1u);
    XCTAssertEqual(conversation.typingUsers.anyObject, user1);
    
    token = nil;
}
    
- (void)testThatItSendsTypingNotificationsForConversation;
{
    XCTAssertTrue([self login]);
    
    ZMConversation *conversation = [self conversationForMockConversation:self.groupConversation];
    ZMConversation *otherConversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    id token = [otherConversation addTypingObserver:self];
    
    XCTAssertEqual(conversation.typingUsers.count, 0u);
    
    [self.mockTransportSession sendIsTypingEventForConversation:self.groupConversation user:self.user1 started:YES];
    WaitForAllGroupsToBeEmpty(0.5);
    
    XCTAssertEqual(self.notifications.count, 0u);
    
    token = nil;
}
    
- (void)testThatItTypingStatusTimesOut;
{
    XCTAssertTrue([self login]);
    
    ZMConversation *conversation = [self conversationForMockConversation:self.groupConversation];
    id token = [conversation addTypingObserver:self];
    
    XCTAssertEqual(conversation.typingUsers.count, 0u);
    
    [self.mockTransportSession sendIsTypingEventForConversation:self.groupConversation user:self.user1 started:YES];
    WaitForAllGroupsToBeEmpty(0.5);
    
    XCTAssertEqual(self.notifications.count, 1u);
    [self.notifications removeAllObjects];
    
    [self spinMainQueueWithTimeout:ZMTypingDefaultTimeout + 1];
    
    XCTAssertEqual(self.notifications.count, 1u);
    TypingChange *note = self.notifications.firstObject;
    XCTAssertEqual(note.conversation, conversation);
    XCTAssertEqual(note.typingUsers.count, 0u);
    XCTAssertEqual(conversation.typingUsers.count, 0u);
    
    token = nil;
}

- (void)testThatItResetsIsTypingWhenATypingUserSendsAMessage
{
    // given
    XCTAssertTrue([self login]);
    
    ZMConversation *conversation = [self conversationForMockConversation:self.groupConversation];
    id token = [conversation addTypingObserver:self];
    
    XCTAssertEqual(conversation.typingUsers.count, 0u);
    
    // when  
    [self.mockTransportSession sendIsTypingEventForConversation:self.groupConversation user:self.user1 started:YES];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(self.notifications.count, 1u);
    XCTAssertEqual(conversation.typingUsers.count, 1u);
    [self.notifications removeAllObjects];
    
    // when
    [self.mockTransportSession performRemoteChanges:^(ZM_UNUSED id session) {
        ZMGenericMessage *message = [ZMGenericMessage messageWithContent:[ZMText textWith:@"text text" mentions:@[] linkPreviews:@[]] nonce:NSUUID.createUUID];
        [self.groupConversation encryptAndInsertDataFromClient:self.user1.clients.anyObject toClient:self.selfUser.clients.anyObject data:message.data];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(conversation.typingUsers.count, 0u);
    
    token = nil;
}

- (void)testThatIt_DoesNot_ResetIsTypingWhenA_DifferentUser_ThanTheTypingUserSendsAMessage
{
    // given
    XCTAssertTrue([self login]);
    
    ZMConversation *conversation = [self conversationForMockConversation:self.groupConversation];
    id token = [conversation addTypingObserver:self];
    
    XCTAssertEqual(conversation.typingUsers.count, 0u);
    
    // when
    [self.mockTransportSession sendIsTypingEventForConversation:self.groupConversation user:self.user2 started:YES];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(self.notifications.count, 1u);
    XCTAssertEqual(conversation.typingUsers.count, 1u);
    [self.notifications removeAllObjects];
    
    // when
    [self.mockTransportSession performRemoteChanges:^(ZM_UNUSED id session) {
        ZMGenericMessage *message = [ZMGenericMessage messageWithContent:[ZMText textWith:@"text text" mentions:@[] linkPreviews:@[]] nonce:NSUUID.createUUID];
        [self.groupConversation encryptAndInsertDataFromClient:self.user1.clients.anyObject toClient:self.selfUser.clients.anyObject data:message.data];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(conversation.typingUsers.count, 1u);
    token = nil;
}

@end
