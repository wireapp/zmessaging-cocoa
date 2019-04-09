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


@import WireTesting;
@import WireDataModel;

#import "ConversationTestsBase.h"
#import "NotificationObservers.h"
#import "WireSyncEngine_iOS_Tests-Swift.h"

@interface ConversationTests_MessageEditing : ConversationTestsBase

@end



@implementation ConversationTests_MessageEditing

#pragma mark - Sending

- (void)testThatItSendsOutARequestToEditAMessage
{
    // given
    XCTAssert([self login]);
    ZMConversation *conversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    
    __block ZMMessage *message;
    [self.userSession performChanges:^{
        message = (id)[conversation appendMessageWithText:@"Foo"];
    }];
    NSUUID *messageNonce = message.nonce;
    WaitForAllGroupsToBeEmpty(0.5);
    
    NSUInteger messageCount = conversation.allMessages.count;
    [self.mockTransportSession resetReceivedRequests];
    
    // when
    [self.userSession performChanges:^{
        [message.textMessageData editText:@"Bar" mentions:@[] fetchLinkPreview:NO];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(conversation.allMessages.count, messageCount);
    XCTAssertEqualObjects(conversation.lastMessage, message);
    XCTAssertEqualObjects(message.textMessageData.messageText, @"Bar");
    XCTAssertNotEqualObjects(message.nonce, messageNonce);

    XCTAssertEqual(self.mockTransportSession.receivedRequests.count, 1u);
    ZMTransportRequest *request = self.mockTransportSession.receivedRequests.lastObject;
    NSString *expectedPath = [NSString stringWithFormat:@"/conversations/%@/otr/messages", conversation.remoteIdentifier.transportString];
    XCTAssertEqualObjects(request.path, expectedPath);
    XCTAssertEqual(request.method, ZMMethodPOST);
}

- (void)testThatItCanEditAnEditedMessage
{
    // given
    XCTAssert([self login]);
    ZMConversation *conversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    
    __block ZMMessage *message;
    [self.userSession performChanges:^{
        message = (id)[conversation appendMessageWithText:@"Foo"];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    [self.userSession performChanges:^{
        [message.textMessageData editText:@"Bar" mentions:@[] fetchLinkPreview:NO];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    NSUInteger messageCount = conversation.allMessages.count;
    [self.mockTransportSession resetReceivedRequests];
    
    // when
    [self.userSession performChanges:^{
        [message.textMessageData editText:@"FooBar" mentions:@[] fetchLinkPreview:NO];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(conversation.allMessages.count, messageCount);
    XCTAssertEqualObjects(conversation.lastMessage, message);
    XCTAssertEqualObjects(message.textMessageData.messageText, @"FooBar");
    
    XCTAssertEqual(self.mockTransportSession.receivedRequests.count, 1u);
    ZMTransportRequest *request = self.mockTransportSession.receivedRequests.lastObject;
    NSString *expectedPath = [NSString stringWithFormat:@"/conversations/%@/otr/messages", conversation.remoteIdentifier.transportString];
    XCTAssertEqualObjects(request.path, expectedPath);
    XCTAssertEqual(request.method, ZMMethodPOST);
}

- (void)testThatItKeepsTheContentWhenMessageSendingFailsButOverwritesTheNonce
{
    // given
    XCTAssert([self login]);
    ZMConversation *conversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    
    __block ZMMessage *message;
    [self.userSession performChanges:^{
        message = (id)[conversation appendMessageWithText:@"Foo"];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    NSUUID *originalNonce = message.nonce;
    
    [self.mockTransportSession resetReceivedRequests];
    self.mockTransportSession.responseGeneratorBlock = ^ZMTransportResponse *(ZMTransportRequest *request){
        if ([request.path isEqualToString:[NSString stringWithFormat:@"/conversations/%@/otr/messages", conversation.remoteIdentifier.transportString]]) {
            return ResponseGenerator.ResponseNotCompleted;
        }
        return nil;
    };
    
    // when
    [self.userSession performChanges:^{
        [message.textMessageData editText:@"Bar" mentions:@[] fetchLinkPreview:NO];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    [self.mockTransportSession expireAllBlockedRequests];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqualObjects(conversation.lastMessage, message);
    XCTAssertEqualObjects(message.textMessageData.messageText, @"Bar");
    XCTAssertEqualObjects(message.nonce, originalNonce);
}

- (void)testThatWhenResendingAFailedEditItSentWithANewNonce
{
    // given
    XCTAssert([self login]);
    ZMConversation *conversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    
    __block ZMMessage *message;
    [self.userSession performChanges:^{
        message = (id)[conversation appendMessageWithText:@"Foo"];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    NSUUID *originalNonce = message.nonce;
    
    [self.mockTransportSession resetReceivedRequests];
    self.mockTransportSession.responseGeneratorBlock = ^ZMTransportResponse *(ZMTransportRequest *request){
        if ([request.path isEqualToString:[NSString stringWithFormat:@"/conversations/%@/otr/messages", conversation.remoteIdentifier.transportString]]) {
            return ResponseGenerator.ResponseNotCompleted;
        }
        return nil;
    };
    
    [self.userSession performChanges:^{
        [message.textMessageData editText:@"Bar" mentions:@[] fetchLinkPreview:NO];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    [self.mockTransportSession expireAllBlockedRequests];
    WaitForAllGroupsToBeEmpty(0.5);
    self.mockTransportSession.responseGeneratorBlock = nil;
    
    // when
    [self.userSession performChanges:^{
        [message resend];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    // The new edit message has a new nonce and the same text
    XCTAssertEqualObjects(message.textMessageData.messageText, @"Bar");
    XCTAssertNotEqualObjects(message.nonce, originalNonce);
}


#pragma mark - Receiving

- (void)testThatItProcessesEditingMessages
{
    // given
    XCTAssert([self login]);
    ZMConversation *conversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    NSUInteger messageCount = conversation.allMessages.count;
    
    MockUserClient *fromClient = self.user1.clients.anyObject;
    MockUserClient *toClient = self.selfUser.clients.anyObject;
    ZMGenericMessage *textMessage = [ZMGenericMessage messageWithContent:[ZMText textWith:@"Foo" mentions:@[] linkPreviews:@[] replyingTo:nil] nonce:NSUUID.createUUID];
    
    [self.mockTransportSession performRemoteChanges:^(id ZM_UNUSED session) {
        [self.selfToUser1Conversation encryptAndInsertDataFromClient:fromClient toClient:toClient data:textMessage.data];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    XCTAssertEqual(conversation.allMessages.count, messageCount+1);
    ZMClientMessage *receivedMessage = (ZMClientMessage *)conversation.lastMessage;
    XCTAssertEqualObjects(receivedMessage.textMessageData.messageText, @"Foo");
    NSUUID *messageNonce = receivedMessage.nonce;
    
    // when
    ZMGenericMessage *editMessage = [ZMGenericMessage messageWithContent:[ZMMessageEdit editWith:[ZMText textWith:@"Bar" mentions:@[] linkPreviews:@[] replyingTo:nil] replacingMessageId:messageNonce] nonce:NSUUID.createUUID];
    [self.mockTransportSession performRemoteChanges:^(id ZM_UNUSED session) {
        [self.selfToUser1Conversation encryptAndInsertDataFromClient:fromClient toClient:toClient data:editMessage.data];
    }];
    WaitForAllGroupsToBeEmpty(0.5);

    // then
    XCTAssertEqual(conversation.allMessages.count, messageCount+1);
    ZMClientMessage *editedMessage = (ZMClientMessage *)conversation.lastMessage;
    XCTAssertEqualObjects(editedMessage.textMessageData.messageText, @"Bar");
}

- (void)testThatItSendsOutNotificationAboutUpdatedMessages
{
    // given
    XCTAssert([self login]);
    ZMConversation *conversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    
    MockUserClient *fromClient = self.user1.clients.anyObject;
    MockUserClient *toClient = self.selfUser.clients.anyObject;
    ZMGenericMessage *textMessage = [ZMGenericMessage messageWithContent:[ZMText textWith:@"Foo" mentions:@[] linkPreviews:@[] replyingTo:nil] nonce:NSUUID.createUUID];
    
    [self.mockTransportSession performRemoteChanges:^(id ZM_UNUSED session) {
        [self.selfToUser1Conversation encryptAndInsertDataFromClient:fromClient toClient:toClient data:textMessage.data];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    ZMClientMessage *receivedMessage = (ZMClientMessage *)conversation.lastMessage;
    NSUUID *messageNonce = receivedMessage.nonce;
    
    ConversationChangeObserver *observer = [[ConversationChangeObserver alloc] initWithConversation:conversation];
    
    [receivedMessage.managedObjectContext processPendingChanges];
    NSDate *lastModifiedDate = conversation.lastModifiedDate;
    
    // when
    ZMGenericMessage *editMessage = [ZMGenericMessage messageWithContent:[ZMMessageEdit editWith:[ZMText textWith:@"Bar" mentions:@[] linkPreviews:@[] replyingTo:nil] replacingMessageId:messageNonce] nonce:NSUUID.createUUID];
    __block MockEvent *editEvent;
    [self.mockTransportSession performRemoteChanges:^(id ZM_UNUSED session) {
        editEvent = [self.selfToUser1Conversation encryptAndInsertDataFromClient:fromClient toClient:toClient data:editMessage.data];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqualObjects(conversation.lastModifiedDate, lastModifiedDate);
    XCTAssertNotEqualObjects(conversation.lastModifiedDate, editEvent.time);
    
    XCTAssertEqual(observer.notifications.count, 1u);
    ConversationChangeInfo *convInfo =  observer.notifications.firstObject;
    XCTAssertTrue(convInfo.messagesChanged);
    XCTAssertFalse(convInfo.participantsChanged);
    XCTAssertFalse(convInfo.nameChanged);
    XCTAssertFalse(convInfo.unreadCountChanged);
    XCTAssertFalse(convInfo.lastModifiedDateChanged);
    XCTAssertFalse(convInfo.connectionStateChanged);
    XCTAssertFalse(convInfo.mutedMessageTypesChanged);
    XCTAssertFalse(convInfo.conversationListIndicatorChanged);
    XCTAssertFalse(convInfo.clearedChanged);
    XCTAssertFalse(convInfo.securityLevelChanged);
}


@end
