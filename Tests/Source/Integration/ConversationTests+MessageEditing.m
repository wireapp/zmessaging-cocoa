//
//  ConversationTests+MessageEditing.m
//  zmessaging-cocoa
//
//  Created by Sabine Geithner on 11/08/16.
//  Copyright © 2016 Zeta Project Gmbh. All rights reserved.
//

@import ZMTesting;
@import ZMCDataModel;

#import "ConversationTestsBase.h"
#import "NotificationObservers.h"

@interface ConversationTests_MessageEditing : ConversationTestsBase

@end



@implementation ConversationTests_MessageEditing

#pragma mark - Sending

- (void)testThatItSendsOutARequestToEditAMessage
{
    // given
    XCTAssert([self logInAndWaitForSyncToBeComplete]);
    ZMConversation *conversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    
    __block ZMMessage *message;
    [self.userSession performChanges:^{
        message = [conversation appendMessageWithText:@"Foo"];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    NSUInteger messageCount = conversation.messages.count;
    [self.mockTransportSession resetReceivedRequests];
    
    // when
    __block ZMMessage *editMessage;
    [self.userSession performChanges:^{
        editMessage = [ZMMessage edit:message newText:@"Bar"];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(conversation.messages.count, messageCount);
    XCTAssertEqualObjects(conversation.messages.lastObject, editMessage);
    XCTAssertEqualObjects(editMessage.textMessageData.messageText, @"Bar");
    XCTAssertNotEqualObjects(editMessage.nonce, message.nonce);

    XCTAssertEqual(self.mockTransportSession.receivedRequests.count, 1u);
    ZMTransportRequest *request = self.mockTransportSession.receivedRequests.lastObject;
    NSString *expectedPath = [NSString stringWithFormat:@"/conversations/%@/otr/messages", conversation.remoteIdentifier.transportString];
    XCTAssertEqualObjects(request.path, expectedPath);
    XCTAssertEqual(request.method, ZMMethodPOST);
}

- (void)testThatItCanEditAnEditedMessage
{
    // given
    XCTAssert([self logInAndWaitForSyncToBeComplete]);
    ZMConversation *conversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    
    __block ZMMessage *message;
    [self.userSession performChanges:^{
        message = [conversation appendMessageWithText:@"Foo"];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    __block ZMMessage *editMessage1;
    [self.userSession performChanges:^{
        editMessage1 = [ZMMessage edit:message newText:@"Bar"];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    NSUInteger messageCount = conversation.messages.count;
    [self.mockTransportSession resetReceivedRequests];
    
    // when
    __block ZMMessage *editMessage2;
    [self.userSession performChanges:^{
        editMessage2 = [ZMMessage edit:editMessage1 newText:@"FooBar"];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(conversation.messages.count, messageCount);
    XCTAssertEqualObjects(conversation.messages.lastObject, editMessage2);
    XCTAssertEqualObjects(editMessage2.textMessageData.messageText, @"FooBar");
    
    XCTAssertEqual(self.mockTransportSession.receivedRequests.count, 1u);
    ZMTransportRequest *request = self.mockTransportSession.receivedRequests.lastObject;
    NSString *expectedPath = [NSString stringWithFormat:@"/conversations/%@/otr/messages", conversation.remoteIdentifier.transportString];
    XCTAssertEqualObjects(request.path, expectedPath);
    XCTAssertEqual(request.method, ZMMethodPOST);
}

- (void)testThatItKeepsTheContentWhenMessageSendingFailsButOverwritesTheNonce
{
    // given
    XCTAssert([self logInAndWaitForSyncToBeComplete]);
    ZMConversation *conversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    
    __block ZMMessage *message;
    [self.userSession performChanges:^{
        message = [conversation appendMessageWithText:@"Foo"];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    NSUInteger messageCount = conversation.messages.count;
    NSUUID *originalNonce = message.nonce;
    
    [self.mockTransportSession resetReceivedRequests];
    self.mockTransportSession.responseGeneratorBlock = ^ZMTransportResponse *(ZMTransportRequest *request){
        if ([request.path isEqualToString:[NSString stringWithFormat:@"/conversations/%@/otr/messages", conversation.remoteIdentifier.transportString]]) {
            return ResponseGenerator.ResponseNotCompleted;
        }
        return nil;
    };
    
    // when
    __block ZMMessage *editMessage;
    [self.userSession performChanges:^{
        editMessage = [ZMMessage edit:message newText:@"Bar"];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    [self.mockTransportSession expireAllBlockedRequests];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(conversation.messages.count, messageCount);
    XCTAssertTrue(message.isZombieObject);

    XCTAssertEqualObjects(conversation.messages.lastObject, editMessage);
    XCTAssertEqualObjects(editMessage.textMessageData.messageText, @"Bar");
    XCTAssertEqualObjects(editMessage.nonce, originalNonce);
}

- (void)testThatWhenResendingAFailedEditMessageItInsertsANewOne
{
    // given
    XCTAssert([self logInAndWaitForSyncToBeComplete]);
    ZMConversation *conversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    
    __block ZMMessage *message;
    [self.userSession performChanges:^{
        message = [conversation appendMessageWithText:@"Foo"];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    NSUInteger messageCount = conversation.messages.count;
    NSUUID *originalNonce = message.nonce;
    
    [self.mockTransportSession resetReceivedRequests];
    self.mockTransportSession.responseGeneratorBlock = ^ZMTransportResponse *(ZMTransportRequest *request){
        if ([request.path isEqualToString:[NSString stringWithFormat:@"/conversations/%@/otr/messages", conversation.remoteIdentifier.transportString]]) {
            return ResponseGenerator.ResponseNotCompleted;
        }
        return nil;
    };
    
    __block ZMMessage *editMessage1;
    [self.userSession performChanges:^{
        editMessage1 = [ZMMessage edit:message newText:@"Bar"];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    [self.mockTransportSession expireAllBlockedRequests];
    WaitForAllGroupsToBeEmpty(0.5);
    self.mockTransportSession.responseGeneratorBlock = nil;
    
    // when
    [self.userSession performChanges:^{
        [editMessage1 resend];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(conversation.messages.count, messageCount);
    XCTAssertTrue(message.isZombieObject);
    
    ZMMessage *editMessage2 = conversation.messages.lastObject;
    XCTAssertNotEqual(editMessage1, editMessage2);
    
    // The failed edit message is hidden
    XCTAssertTrue(editMessage1.hasBeenDeleted);
    XCTAssertEqualObjects(editMessage1.nonce, originalNonce);

    // The new edit message has a new nonce and the same text
    XCTAssertEqualObjects(editMessage2.textMessageData.messageText, @"Bar");
    XCTAssertNotEqualObjects(editMessage2.nonce, originalNonce);
}


#pragma mark - Receiving

- (void)testThatItProcessesEditingMessages
{
    // given
    XCTAssert([self logInAndWaitForSyncToBeComplete]);
    ZMConversation *conversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    NSUInteger messageCount = conversation.messages.count;
    
    MockUserClient *fromClient = self.user1.clients.anyObject;
    MockUserClient *toClient = self.selfUser.clients.anyObject;
    ZMGenericMessage *textMessage = [ZMGenericMessage messageWithText:@"Foo" nonce:[NSUUID createUUID].transportString];
    
    [self.mockTransportSession performRemoteChanges:^(id ZM_UNUSED session) {
        [self.selfToUser1Conversation encryptAndInsertDataFromClient:fromClient toClient:toClient data:textMessage.data];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    XCTAssertEqual(conversation.messages.count, messageCount+1);
    ZMClientMessage *receivedMessage = conversation.messages.lastObject;
    XCTAssertEqualObjects(receivedMessage.textMessageData.messageText, @"Foo");
    NSUUID *messageNone = receivedMessage.nonce;
    
    // when
    ZMGenericMessage *editMessage = [ZMGenericMessage messageWithEditMessage:messageNone.transportString  newText:@"Bar" nonce:[NSUUID createUUID].transportString];
    [self.mockTransportSession performRemoteChanges:^(id ZM_UNUSED session) {
        [self.selfToUser1Conversation encryptAndInsertDataFromClient:fromClient toClient:toClient data:editMessage.data];
    }];
    WaitForAllGroupsToBeEmpty(0.5);

    // then
    XCTAssertEqual(conversation.messages.count, messageCount+1);
    ZMClientMessage *editedMessage = conversation.messages.lastObject;
    XCTAssertEqualObjects(editedMessage.textMessageData.messageText, @"Bar");
}

- (void)testThatItSendsOutNotificationAboutUpdatedMessages
{
    // given
    XCTAssert([self logInAndWaitForSyncToBeComplete]);
    ZMConversation *conversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    
    MockUserClient *fromClient = self.user1.clients.anyObject;
    MockUserClient *toClient = self.selfUser.clients.anyObject;
    ZMGenericMessage *textMessage = [ZMGenericMessage messageWithText:@"Foo" nonce:[NSUUID createUUID].transportString];
    
    [self.mockTransportSession performRemoteChanges:^(id ZM_UNUSED session) {
        [self.selfToUser1Conversation encryptAndInsertDataFromClient:fromClient toClient:toClient data:textMessage.data];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    ZMClientMessage *receivedMessage = conversation.messages.lastObject;
    NSUUID *messageNone = receivedMessage.nonce;
    
    id convToken = [conversation addConversationObserver:self.conversationChangeObserver];
    [self.conversationChangeObserver clearNotifications];
    
    ZMConversationMessageWindow *window = [conversation conversationWindowWithSize:10];
    MessageWindowChangeObserver *windowObserver = [[MessageWindowChangeObserver alloc] initWithMessageWindow:window];
    NSUInteger messageIndex = [window.messages indexOfObject:receivedMessage];
    XCTAssertEqual(messageIndex, 0u);
    NSDate *lastModifiedDate = conversation.lastModifiedDate;
    
    // when
    ZMGenericMessage *editMessage = [ZMGenericMessage messageWithEditMessage:messageNone.transportString newText:@"Bar" nonce:[NSUUID createUUID].transportString];
    __block MockEvent *editEvent;
    [self.mockTransportSession performRemoteChanges:^(id ZM_UNUSED session) {
        editEvent = [self.selfToUser1Conversation encryptAndInsertDataFromClient:fromClient toClient:toClient data:editMessage.data];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqualObjects(conversation.lastModifiedDate, lastModifiedDate);
    XCTAssertNotEqualObjects(conversation.lastModifiedDate, editEvent.time);

    ZMClientMessage *editedMessage = conversation.messages.lastObject;
    NSUInteger editedMessageIndex = [window.messages indexOfObject:editedMessage];
    XCTAssertEqual(editedMessageIndex, messageIndex);
    
    XCTAssertEqual(self.conversationChangeObserver.notifications.count, 1u);
    ConversationChangeInfo *convInfo =  self.conversationChangeObserver.notifications.firstObject;
    XCTAssertTrue(convInfo.messagesChanged);
    XCTAssertFalse(convInfo.participantsChanged);
    XCTAssertFalse(convInfo.nameChanged);
    XCTAssertFalse(convInfo.unreadCountChanged);
    XCTAssertFalse(convInfo.lastModifiedDateChanged);
    XCTAssertFalse(convInfo.connectionStateChanged);
    XCTAssertFalse(convInfo.isSilencedChanged);
    XCTAssertFalse(convInfo.conversationListIndicatorChanged);
    XCTAssertFalse(convInfo.voiceChannelStateChanged);
    XCTAssertFalse(convInfo.clearedChanged);
    XCTAssertFalse(convInfo.securityLevelChanged);

    XCTAssertEqual(windowObserver.notifications.count, 1u);
    MessageWindowChangeInfo *windowInfo = windowObserver.notifications.lastObject;
    XCTAssertEqualObjects(windowInfo.deletedIndexes, [NSIndexSet indexSetWithIndex:messageIndex]);
    XCTAssertEqualObjects(windowInfo.insertedIndexes, [NSIndexSet indexSetWithIndex:messageIndex]);
    XCTAssertEqualObjects(windowInfo.updatedIndexes, [NSIndexSet indexSet]);
    XCTAssertEqualObjects(windowInfo.movedIndexPairs, @[]);

    [ZMConversation removeConversationObserverForToken:convToken];
    [windowObserver tearDown];
}


@end
