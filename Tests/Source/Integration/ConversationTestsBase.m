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


#import "ConversationTestsBase.h"


@implementation ConversationTestsBase

- (void)setUp{
    [super setUp];
    [self setupGroupConversationWithOnlyConnectedParticipants];
    self.receivedConversationWindowChangeNotifications = [NSMutableArray array];
}

- (void)tearDown
{
    self.receivedConversationWindowChangeNotifications = nil;
    [self.syncMOC performGroupedBlockAndWait:^{
        [self.syncMOC zm_teardownMessageObfuscationTimer];
    }];
    XCTAssert([self waitForAllGroupsToBeEmptyWithTimeout: 0.5]);
    
    [self.uiMOC zm_teardownMessageDeletionTimer];
    XCTAssert([self waitForAllGroupsToBeEmptyWithTimeout: 0.5]);
    
    [super tearDown];
}

- (void)setupGroupConversationWithOnlyConnectedParticipants
{
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        self.groupConversationWithOnlyConnected = [session insertGroupConversationWithSelfUser:self.selfUser
                                                                                    otherUsers:@[self.user1, self.user2]];
        self.groupConversationWithOnlyConnected.creator = self.selfUser;
        [self storeRemoteIDForObject:self.groupConversationWithOnlyConnected];
        [self.groupConversationWithOnlyConnected changeNameByUser:self.selfUser name:@"Group conversation with only connected participants"];
        [self setDate:[NSDate dateWithTimeInterval:1000 sinceDate:self.groupConversation.lastEventTime] forAllEventsInMockConversation:self.groupConversationWithOnlyConnected];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatItSendsANotificationInConversation:(MockConversation *)mockConversation
                                    ignoreLastRead:(BOOL)ignoreLastRead
                        onRemoteMessageCreatedWith:(void(^)())createMessage
                                            verify:(void(^)(ZMConversation *))verifyConversation
{
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    
    ZMConversation *conversation = [self conversationForMockConversation:mockConversation];
    
    // Make sure this relationship is not a fault:
    for (id obj in conversation.messages) {
        (void) obj;
    }
    
    // when
    ConversationChangeObserver *observer = [[ConversationChangeObserver alloc] initWithConversation:conversation];
    [observer clearNotifications];
    
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> * __unused session) {
        createMessage(session);
    }];
    
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(observer.notifications.count, 1u);
    
    ConversationChangeInfo *note = observer.notifications.lastObject;
    XCTAssertNotNil(note);
    XCTAssertTrue(note.messagesChanged);
    XCTAssertFalse(note.participantsChanged);
    XCTAssertFalse(note.nameChanged);
    XCTAssertTrue(note.lastModifiedDateChanged);
    if(!ignoreLastRead) {
        XCTAssertTrue(note.unreadCountChanged);
    }
    XCTAssertFalse(note.connectionStateChanged);
    
    verifyConversation(conversation);
    [observer tearDown];
}

- (void)testThatItSendsANotificationInConversation:(MockConversation *)mockConversation
                        onRemoteMessageCreatedWith:(void(^)())createMessage
                                verifyWithObserver:(void(^)(ZMConversation *, ConversationChangeObserver *))verifyConversation;
{
    [self testThatItSendsANotificationInConversation:mockConversation
                                     afterLoginBlock:nil
                          onRemoteMessageCreatedWith:createMessage
                                  verifyWithObserver:verifyConversation];
}

- (void)testThatItSendsANotificationInConversation:(MockConversation *)mockConversation
                                   afterLoginBlock:(void(^)())afterLoginBlock
                        onRemoteMessageCreatedWith:(void(^)())createMessage
                                verifyWithObserver:(void(^)(ZMConversation *, ConversationChangeObserver *))verifyConversation;
{
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    afterLoginBlock();
    WaitForAllGroupsToBeEmpty(0.5);
    ZMConversation *conversation = [self conversationForMockConversation:mockConversation];
    
    // Make sure this relationship is not a fault:
    for (id obj in conversation.messages) {
        (void) obj;
    }
    
    // when
    ConversationChangeObserver *observer = [[ConversationChangeObserver alloc] initWithConversation:conversation];
    [observer clearNotifications];
    
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> * __unused session) {
        createMessage(session);
    }];
    
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    verifyConversation(conversation, observer);
    [observer tearDown];
}

- (BOOL)conversation:(ZMConversation *)conversation hasMessagesWithNonces:(NSArray *)nonces
{
    BOOL hasAllMessages = YES;
    for (NSUUID *nonce in nonces) {
        BOOL hasMessageWithNonce = [conversation.messages.array containsObjectMatchingWithBlock:^BOOL(ZMMessage *msg) {
            return [msg.nonce isEqual:nonce];
        }];
        hasAllMessages &= hasMessageWithNonce;
    }
    return hasAllMessages;
}

- (void)testThatItAppendsMessageToConversation:(MockConversation *)mockConversation
                                     withBlock:(NSArray *(^)(MockTransportSession<MockTransportSessionObjectCreation> *session))appendMessages
                                        verify:(void(^)(ZMConversation *))verifyConversation
{
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    
    ZMConversation *conversation = [self conversationForMockConversation:mockConversation];
    
    // Make sure this relationship is not a fault:
    for (id obj in conversation.messages) {
        (void) obj;
    }
    
    // when
    ConversationChangeObserver *observer = [[ConversationChangeObserver alloc] initWithConversation:conversation];
    [observer clearNotifications];
    
    __block NSArray *messsagesNonces;
    
    // expect
    XCTestExpectation *exp = [self expectationWithDescription:@"All messages received"];
    observer.notificationCallback = (ObserverCallback) ^(ConversationChangeInfo * __unused note) {
        BOOL hasAllMessages = [self conversation:conversation hasMessagesWithNonces:messsagesNonces];
        if (hasAllMessages) {
            [exp fulfill];
        }
    };
    
    // when
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> * session) {
        messsagesNonces = appendMessages(session);
    }];
    XCTAssert([self waitForCustomExpectationsWithTimeout:0.5]);
    
    // then
    verifyConversation(conversation);
    [observer tearDown];
    
}

- (MockConversationWindowObserver *)windowObserverAfterLogginInAndInsertingMessagesInMockConversation:(MockConversation *)mockConversation;
{
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    WaitForEverythingToBeDone();
    ZMConversation *conversation = [self conversationForMockConversation:mockConversation];
    
    const int MESSAGES = 10;
    const NSUInteger WINDOW_SIZE = 5;
    NSMutableArray *insertedMessages = [NSMutableArray array];
    for(int i = 0; i < MESSAGES; ++i)
    {
        [self.userSession performChanges:^{ // I save multiple times so that it is inserted in the mocktransportsession in the order I expect
            NSString *text = [NSString stringWithFormat:@"Message %d", i+1];
            [conversation appendMessageWithText:text];
        }];
        WaitForAllGroupsToBeEmpty(0.5);
    }
    
    [conversation setVisibleWindowFromMessage:insertedMessages.firstObject toMessage:insertedMessages.lastObject];
    MockConversationWindowObserver *observer = [[MockConversationWindowObserver alloc] initWithConversation:conversation size:WINDOW_SIZE];
    
    return observer;
}

@end

