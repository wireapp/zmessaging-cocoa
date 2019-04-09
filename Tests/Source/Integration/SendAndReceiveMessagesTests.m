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


@import WireTransport;
@import WireMockTransport;
@import WireDataModel;

#import "ZMUserSession+Internal.h"
#import "ConversationTestsBase.h"
#import "WireSyncEngine_iOS_Tests-Swift.h"


@interface TestConversationObserver : NSObject <ZMConversationObserver>

@property (nonatomic) NSMutableArray* conversationChangeNotifications;

@end




@implementation TestConversationObserver

-(instancetype)init
{
    self = [super init];
    if(self) {
        self.conversationChangeNotifications = [NSMutableArray array];
    }
    return self;
}

- (void)conversationDidChange:(ConversationChangeInfo *)note;
{
    [self.conversationChangeNotifications addObject:note];
}

@end



@interface SendAndReceiveMessagesTests : ConversationTestsBase
@end




@implementation SendAndReceiveMessagesTests

- (NSString *)uniqueText
{
    return [NSString stringWithFormat:@"This is a test for %@: %@", self.name, NSUUID.createUUID.transportString];
}

- (void)testThatAfterSendingALongMessageAllMessagesGetSentAndReceived
{
    // given
    NSString *firstMessageText = [[@"BEGIN\n" stringByPaddingToLength:2000 withString:@"A" startingAtIndex:0] stringByAppendingString:@"\nEND"];
    NSString *secondMessageText = @"other message";

    XCTAssert([self login]);

    ZMConversation *groupConversation = [self conversationForMockConversation:self.groupConversation];
    XCTAssertNotNil(groupConversation);
    [self prefetchRemoteClientByInsertingMessageInConversation:self.groupConversation];

    [self.mockTransportSession resetReceivedRequests];

    // when
    __block id<ZMConversationMessage> firstMessage, secondMessage;
    [self.userSession performChanges:^{
        firstMessage = [groupConversation appendMessageWithText:firstMessageText];
        secondMessage = [groupConversation appendMessageWithText:secondMessageText];
    }];

    WaitForAllGroupsToBeEmpty(0.5);
    XCTAssertEqual(firstMessage.deliveryState, ZMDeliveryStateSent);
    XCTAssertEqual(secondMessage.deliveryState, ZMDeliveryStateSent);

    NSUInteger otrResponseCount = 0;
    NSString *otrConversationPath = [NSString stringWithFormat:@"/conversations/%@/otr/messages", self.groupConversation.identifier];

    for (ZMTransportRequest *request in self.mockTransportSession.receivedRequests) {
        if (request.method == ZMMethodPOST && [request.path isEqualToString:otrConversationPath]) {
            otrResponseCount++;
        }
    }

    // then
    XCTAssertEqual(otrResponseCount, 2lu);
    XCTAssertEqualObjects(firstMessage.textMessageData.messageText, firstMessageText);
    XCTAssertEqualObjects(secondMessage.textMessageData.messageText, secondMessageText);
}

- (void)testThatWeReceiveAMessageSentRemotely
{
    // given
    NSString *messageText = [self uniqueText];
    XCTAssert([self login]);
    ZMConversation *conversation = [self conversationForMockConversation:self.groupConversation];
    
    // when
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        NOT_USED(session);
        ZMGenericMessage *message = [ZMGenericMessage messageWithContent:[ZMText textWith:messageText mentions:@[] linkPreviews:@[] replyingTo:nil] nonce:NSUUID.createUUID];
        [self.groupConversation encryptAndInsertDataFromClient:self.user1.clients.anyObject toClient:self.selfUser.clients.anyObject data:message.data];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    id<ZMConversationMessage> lastMessage = conversation.lastMessage;
    XCTAssertEqualObjects(lastMessage.textMessageData.messageText, messageText);
}

- (ZMConversation *)setUpStateAndConversation {
    
    XCTAssert([self login]);
    WaitForAllGroupsToBeEmpty(0.1);
    
    
    ZMConversation *groupConversation = [self conversationForMockConversation:self.groupConversation];
    XCTAssertNotNil(groupConversation);
    
    return groupConversation;
}


- (void)testThatItDoesNotSyncTheLastReadOfMessagesThatHaveNotBeenDeliveredYet
{
    // given
    XCTAssert([self login]);

    __block NSUInteger count = 0;
    dispatch_block_t insertMessage  = ^{
        NSString *text = [NSString stringWithFormat:@"text %lu", count];
        ZMGenericMessage *message = [ZMGenericMessage messageWithContent:[ZMText textWith:text mentions:@[] linkPreviews:@[] replyingTo:nil] nonce:NSUUID.createUUID];
        [self.groupConversation encryptAndInsertDataFromClient:self.user1.clients.anyObject toClient:self.selfUser.clients.anyObject data:message.data];
    };
    
    [self.mockTransportSession performRemoteChanges:^(ZM_UNUSED id session) {
        for (int i = 0; i < 4; i++) {
            insertMessage();
        }
    }];

    WaitForAllGroupsToBeEmpty(0.1);
    
    ZMConversation *conversation =  [self conversationForMockConversation:self.groupConversation];
    NSString *convIDString = conversation.remoteIdentifier.transportString;
    
    XCTAssertEqual(conversation.allMessages.count, 6u);
    
    self.mockTransportSession.responseGeneratorBlock = ^ZMTransportResponse *(ZMTransportRequest *request){
        if ([request.path containsString:@"messages"] && request.method == ZMMethodPOST) {
            if ([request.path containsString:convIDString]) {
                return [ZMTransportResponse responseWithTransportSessionError:[NSError requestExpiredError]];
            }
        }
        return nil;
    };
    
    // when
    ZMMessage *previousMessage =  conversation.lastMessage;
    
    __block ZMMessage *failedToSendMessage;
    [self.userSession performChanges:^{
        failedToSendMessage = (id)[conversation appendMessageWithText:@"test"];
    }];
    WaitForAllGroupsToBeEmpty(0.1);
    
    XCTAssertEqual(failedToSendMessage.deliveryState, ZMDeliveryStateFailedToSend);
    
    [conversation markMessagesAsReadUntil:failedToSendMessage];
    WaitForAllGroupsToBeEmpty(0.1);

    // then
    XCTAssertNotNil(conversation.lastReadServerTimeStamp);
    XCTAssertNotEqualWithAccuracy([conversation.lastReadServerTimeStamp timeIntervalSince1970], [failedToSendMessage.serverTimestamp timeIntervalSince1970], 0.01);
    XCTAssertEqualWithAccuracy([conversation.lastReadServerTimeStamp timeIntervalSince1970], [previousMessage.serverTimestamp timeIntervalSince1970], 0.01);
}

- (void)testThatItSetsTheLastReadWhenInsertingAnImage
{
    // given
    XCTAssert([self login]);
    [self prefetchRemoteClientByInsertingMessageInConversation:self.groupConversation];
    
    ZMConversation *conversation =  [self conversationForMockConversation:self.groupConversation];
    
    XCTAssertEqual(conversation.allMessages.count, 3u);
    id<ZMConversationMessage> originalMessage = conversation.lastMessage;
    XCTAssertEqualWithAccuracy([conversation.lastReadServerTimeStamp timeIntervalSince1970], [originalMessage.serverTimestamp timeIntervalSince1970], 0.1);
    [self spinMainQueueWithTimeout:0.5]; // if the tests run too fast the new message would otherwise have the same timestamp
    
    // when
    __block ZMMessage *message;
    [self.userSession performChanges:^{
        message = (id)[conversation appendMessageWithImageData:self.verySmallJPEGData];
    }];
    WaitForAllGroupsToBeEmpty(0.1);
    
    // then
    XCTAssertNotNil(conversation.lastReadServerTimeStamp);
    XCTAssertNotEqualWithAccuracy([conversation.lastReadServerTimeStamp timeIntervalSince1970], [originalMessage.serverTimestamp timeIntervalSince1970], 0.1);
    XCTAssertEqualWithAccuracy([conversation.lastReadServerTimeStamp timeIntervalSince1970], [message.serverTimestamp timeIntervalSince1970], 0.1);

}

- (void)testThatItSetsTheLastReadWhenInsertingAText
{
    // given
    XCTAssertTrue([self login]);
    ZMConversation *conversation = [self conversationForMockConversation:self.groupConversation];
    
    // when
    __block ZMMessage *message;
    [self.userSession performChanges:^{
        message = (id)[conversation appendMessageWithText:@"oh hallo"];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqualObjects(conversation.lastReadServerTimeStamp, message.serverTimestamp);
}

- (void)testThatItSetsTheLastReadWhenInsertingAKnock
{
    // given
    XCTAssertTrue([self login]);
    ZMConversation *conversation = [self conversationForMockConversation:self.groupConversation];
    
    // when
    __block ZMMessage *message;
    [self.userSession performChanges:^{
        message = (id)[conversation appendKnock];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqualObjects(conversation.lastReadServerTimeStamp, message.serverTimestamp);
}

- (void)testThatItAppendsClientMessages
{
    NSString *expectedText1 = @"The sky above the port was the color of ";
    NSString *expectedText2 = @"television, tuned to a dead channel.";
    
    NSUUID *nonce1 = [NSUUID createUUID];
    NSUUID *nonce2 = [NSUUID createUUID];
    
    ZMGenericMessage *genericMessage1 = [ZMGenericMessage messageWithContent:[ZMText textWith:expectedText1 mentions:@[] linkPreviews:@[] replyingTo:nil] nonce:nonce1];
    ZMGenericMessage *genericMessage2 = [ZMGenericMessage messageWithContent:[ZMText textWith:expectedText2 mentions:@[] linkPreviews:@[] replyingTo:nil] nonce:nonce2];
    
    [self testThatItAppendsMessageToConversation:self.groupConversation
                                       withBlock:^NSArray *(id __unused session){
                                           [self.groupConversation insertClientMessageFromUser:self.user2 data:genericMessage1.data];
                                           [self spinMainQueueWithTimeout:0.2];
                                           [self.groupConversation insertClientMessageFromUser:self.user3 data:genericMessage2.data];
                                           return @[nonce1, nonce2];
                                       } verify:^(ZMConversation *conversation) {
                                           ZMClientMessage *msg1 = (ZMClientMessage *)[conversation lastMessagesWithLimit:50][1];
                                           XCTAssertEqualObjects(msg1.nonce, nonce1, @"msg1 timestamp %f", msg1.serverTimestamp.timeIntervalSince1970);
                                           XCTAssertEqualObjects(msg1.genericMessage.text.content, expectedText1);
                                           
                                           ZMClientMessage *msg2 = (ZMClientMessage *)[conversation lastMessagesWithLimit:50][0];
                                           XCTAssertEqualObjects(msg2.nonce, nonce2, @"msg2 timestamp %f", msg2.serverTimestamp.timeIntervalSince1970);
                                           XCTAssertEqualObjects(msg2.genericMessage.text.content, expectedText2);
                                       }];
}


- (MockPushEvent *)lastEventForConversation:(MockConversation *)conversation inReceivedEvents:(NSArray *)receivedEvents
{
    __block MockPushEvent *event;
    [receivedEvents enumerateObjectsWithOptions:NSEnumerationReverse usingBlock:^(MockPushEvent *anEvent, NSUInteger idx, BOOL *stop){
        NOT_USED(idx);
        if ([anEvent.payload.asDictionary[@"conversation"] isEqualToString:conversation.identifier]) {
            *stop = YES;
            event = anEvent;
        }
    }];
    return event;
}


- (void)testThatMessageIsSentIfNoPreviousPendingMessagesInConversation
{
    //given
    XCTAssert([self login]);
    WaitForAllGroupsToBeEmpty(0.5);
    
    ZMConversation *conversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    XCTAssertNotNil(conversation);
    
    [self prefetchRemoteClientByInsertingMessageInConversation:self.selfToUser1Conversation];
    
    //when
    // no pending pessages in conversation
    __block id<ZMConversationMessage> message;
    [self.userSession performChanges:^{
        message = (id)[conversation appendMessageWithText:@"bar"];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    //then
    MockPushEvent *lastEvent = [self lastEventForConversation:self.selfToUser1Conversation inReceivedEvents:self.mockTransportSession.updateEvents];
    XCTAssertNotNil(lastEvent);
}

- (void)testThatAMessageIsSentAfterAnImage
{
    //given
    XCTAssert([self login]);
    ZMConversation *conversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    XCTAssertNotNil(conversation);
    
    __block ZMMessage *imageMessage;
    [self.userSession performChanges:^{
        imageMessage = (id)[conversation appendMessageWithImageData:[self verySmallJPEGData]];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    //when
    __block ZMMessage *textMessage;
    [self.userSession performChanges:^{
        textMessage = (id)[conversation appendMessageWithText:@"lalala"];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    
    //then
    XCTAssertEqual(imageMessage.deliveryState, ZMDeliveryStateSent);
    XCTAssertEqual(textMessage.deliveryState, ZMDeliveryStateSent);
}

- (void)testThatNextMessageIsSentAfterPreviousMessageInConversationIsDelivered
{
    // given
    XCTAssert([self login]);
    WaitForAllGroupsToBeEmpty(0.5);
    
    ZMConversation *conversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    XCTAssertNotNil(conversation);
    [self prefetchRemoteClientByInsertingMessageInConversation:self.selfToUser1Conversation];
    [self.mockTransportSession resetReceivedRequests];
    
    NSString *conversationID = self.selfToUser1Conversation.identifier;
    NSString *conversationMessagePath = [NSString stringWithFormat:@"/conversations/%@/otr/messages", conversationID];
    
    //when
    //there is previous pending message
    
    //we block first request from finishing and check that no other requests are coming in
    __block ZMTransportRequest *firstRequest;
    ZM_WEAK(self);
    self.mockTransportSession.responseGeneratorBlock = ^ZMTransportResponse *(ZMTransportRequest *request) {
        ZM_STRONG(self);
        //we should not receieve another request until we finish this one
        if(![request.path isEqualToString:conversationMessagePath]) {
            return nil;
        }
        XCTAssertNil(firstRequest);
        firstRequest = request;
        return ResponseGenerator.ResponseNotCompleted;
    };
    __block id<ZMConversationMessage> message;
    __block id<ZMConversationMessage> secondMessage;
    [self.userSession performChanges:^{
        message = (id)[conversation appendMessageWithText:@"foo1"];
        [self spinMainQueueWithTimeout:0.5];
        secondMessage = (id)[conversation appendMessageWithText:@"foo2"];
    }];
    
    XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0.5f]);
    WaitForAllGroupsToBeEmpty(0.5f);
    
    //then
    NSArray *conversationMessageRequests = [self.mockTransportSession.receivedRequests filterWithBlock:^BOOL(ZMTransportRequest *req) {
        return [req.path isEqualToString:conversationMessagePath] && req != firstRequest;
    }];
    XCTAssertEqual(conversationMessageRequests.count, 0u);
    
    //when
    //finally finish request
    self.mockTransportSession.responseGeneratorBlock = nil;
    [self.mockTransportSession completePreviouslySuspendendRequest:firstRequest];
    WaitForAllGroupsToBeEmpty(0.5f);
    
    //then
    //we check that the second message is delivered
    NSArray *laterConversationMessageRequests = [self.mockTransportSession.receivedRequests filterWithBlock:^BOOL(ZMTransportRequest *req) {
        return [req.path isEqualToString:conversationMessagePath] && req != firstRequest;
    }];
    XCTAssertEqual(laterConversationMessageRequests.count, 1u);
}

- (void)testThatNextClientMessageIsSentAfterPreviousMessageInConversationIsDelivered
{
    //given
    XCTAssert([self login]);
    WaitForAllGroupsToBeEmpty(0.5);
    
    ZMConversation *conversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    XCTAssertNotNil(conversation);
    [self.mockTransportSession resetReceivedRequests];
    
    //when
    //there is previous pending message
    
    //we block first request from finishing and check that no other requests are comming in
    __block ZMTransportRequest *firstRequest;
    XCTestExpectation *firstRequestRecievedExpectation = [self expectationWithDescription:@"Recieved request to add first message"];

    ZM_WEAK(self);
    self.mockTransportSession.responseGeneratorBlock = ^ZMTransportResponse *(ZMTransportRequest *request) {
        ZM_STRONG(self);
        //we should not recieve another request until we finish this one
        if ([request.path containsString:@"otr/messages"]) {
            XCTAssertNil(firstRequest);
            firstRequest = request;
            [firstRequestRecievedExpectation fulfill];
        }
        return ResponseGenerator.ResponseNotCompleted;
    };
    __block ZMMessage *message;
    __block ZMMessage *secondMessage;
    
    [self.userSession performChanges:^{
        message = (id)[conversation appendMessageWithText:@"foo1"];
        [self spinMainQueueWithTimeout:0.1];
        secondMessage = (id)[conversation appendMessageWithText:@"foo2"];
    }];
    
    XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0.5f]);
    WaitForAllGroupsToBeEmpty(0.5f);
    
    //then
    ZMTransportRequest *lastRequest = [[self.mockTransportSession receivedRequests] lastObject];
    XCTAssertEqualObjects(lastRequest, firstRequest);
    
    //when
    //finally finish request
    self.mockTransportSession.responseGeneratorBlock = nil;
    [self.mockTransportSession completePreviouslySuspendendRequest:firstRequest];
    
    WaitForAllGroupsToBeEmpty(0.5f);
    
    //then
    XCTAssertEqual(secondMessage.deliveryState, ZMDeliveryStateSent);
    XCTAssertEqual(message.deliveryState, ZMDeliveryStateSent);
}

- (void)testThatItSendsMessagesFromDifferentConversationsInParallel
{
    //given
    XCTAssert([self login]);
    WaitForAllGroupsToBeEmpty(0.5);
    
    ZMConversation *conversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    XCTAssertNotNil(conversation);
    
    ZMConversation *anotherConversation = [self conversationForMockConversation:self.selfToUser2Conversation];
    XCTAssertNotNil(anotherConversation);
    
    //we block first request from finishing and check that no other requests are comming in
    __block NSInteger recievedRequests = 0;
    XCTestExpectation *expectation = [self expectationWithDescription:@"Recieved requests for both messages"];
    self.mockTransportSession.responseGeneratorBlock = ^ZMTransportResponse *(__unused ZMTransportRequest *request) {
        //we should not recieve another request untill we finish this one
        if ([request.path.lastPathComponent containsString:@"messages"]) {
            recievedRequests++;
        }
        if (recievedRequests == 2) {
            [expectation fulfill];
        }
        return ResponseGenerator.ResponseNotCompleted;
    };
    
    //when
    __block ZMMessage *message;
    __block ZMMessage *secondMessage;
    [self.userSession performChanges:^{
        message = (id)[conversation appendMessageWithText:@"lalala"];
        secondMessage = (id)[anotherConversation appendMessageWithText:@"lalala"];
    }];
    
    //expect
    XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0.5f]);
}

- (void)testThatItSendsANotificationWhenRecievingATextMessageThroughThePushChannel
{
    NSString *expectedText = @"The sky above the port was the color of ";
    NSUUID *nonce = [NSUUID createUUID];
    
    [self testThatItSendsANotificationInConversation:self.groupConversation
                                      ignoreLastRead:NO
                          onRemoteMessageCreatedWith:^{
                              ZMGenericMessage *message = [ZMGenericMessage messageWithContent:[ZMText textWith:expectedText mentions:@[] linkPreviews:@[] replyingTo:nil] nonce:nonce];
                              [self.groupConversation encryptAndInsertDataFromClient:self.user2.clients.anyObject toClient:self.selfUser.clients.anyObject data:message.data];
                          } verify:^(ZMConversation *conversation) {
                              ZMMessage *msg = conversation.lastMessage;
                              XCTAssertEqualObjects(msg.textMessageData.messageText, expectedText);
                          }];
}

- (void)testThatItSendsANotificationWhenRecievingAClientMessageThroughThePushChannel
{
    NSString *expectedText = @"The sky above the port was the color of ";
    ZMGenericMessage *message = [ZMGenericMessage messageWithContent:[ZMText textWith:expectedText mentions:@[] linkPreviews:@[] replyingTo:nil] nonce:NSUUID.createUUID];
    
    [self testThatItSendsANotificationInConversation:self.groupConversation
                                      ignoreLastRead:NO
                          onRemoteMessageCreatedWith:^{
                              [self.groupConversation insertClientMessageFromUser:self.user2 data:message.data];
                          } verify:^(ZMConversation *conversation) {
                              ZMClientMessage *msg = (ZMClientMessage *)conversation.lastMessage;
                              XCTAssertEqualObjects(msg.genericMessage.text.content, expectedText);
                          }];
}

- (void)testThatSystemEventsAreAddedToAConversationWhenTheyAreGeneratedRemotely
{
    // given
    NSString *newName = @"Shiny new name";
    
    
    XCTAssert([self login]);
    WaitForAllGroupsToBeEmpty(0.1);
    
    ZMConversation *groupConversation = [self conversationForMockConversation:self.groupConversation];
    XCTAssertNotNil(groupConversation);
    XCTAssertNotEqual(groupConversation.displayName, newName);
    
    // when
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        [self.groupConversation changeNameByUser:session.selfUser name:newName];
        [self spinMainQueueWithTimeout:0.2];
        [self.groupConversation addUsersByUser:session.selfUser addedUsers:@[self.user4]];
    }];
    WaitForAllGroupsToBeEmpty(0.1);
    
    // then
    NSArray<ZMMessage *> *lastMessages = [groupConversation lastMessagesWithLimit:50];
    
    XCTAssertEqual([(ZMSystemMessage *)lastMessages[1] systemMessageType], ZMSystemMessageTypeConversationNameChanged);
    XCTAssertEqual([(ZMSystemMessage *)lastMessages[0] systemMessageType], ZMSystemMessageTypeParticipantsAdded);
    
    ZMUser *user4 = [self userForMockUser:self.user4];
    XCTAssertEqualObjects([(ZMSystemMessage *)lastMessages[0] users],  [NSSet setWithArray:@[user4]]);
    XCTAssertTrue([groupConversation.activeParticipants containsObject:user4]);
}

- (void)enforceSlowSyncWithNotificationPayload:(NSDictionary *)notificationPayload
{
    ZM_WEAK(self);
    self.mockTransportSession.responseGeneratorBlock = ^ZMTransportResponse *(ZMTransportRequest *request) {
        ZM_STRONG(self);
        if ([request.path containsString:@"/notifications/last"]) {
            return nil;
        } else if ([request.path containsString:@"/notifications"]) {
            self.mockTransportSession.responseGeneratorBlock = nil;
            return [ZMTransportResponse responseWithPayload:notificationPayload HTTPStatus:404 transportSessionError:nil];
        }
        return nil;
    };
}

- (void)testThatSystemMessageIsAddedIfClientWasInactiveAndCantFetchAnyNotifications
{
    // given
    XCTAssert([self login]);
    ZMConversation *groupConversation = [self conversationForMockConversation:self.groupConversation];

    NSUUID *firstMessageNonce = NSUUID.createUUID;
    [self.mockTransportSession performRemoteChanges:^(id<MockTransportSessionObjectCreation> session __unused) {
        ZMGenericMessage *message = [ZMGenericMessage messageWithContent:[ZMText textWith:@"Message Text" mentions:@[] linkPreviews:@[] replyingTo:nil] nonce:firstMessageNonce];
        [self.groupConversation encryptAndInsertDataFromClient:self.user1.clients.anyObject toClient:self.selfUser.clients.anyObject data:message.data];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // when
    [self enforceSlowSyncWithNotificationPayload:nil];
    [self recreateSessionManager];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual([(ZMSystemMessage *)groupConversation.lastMessage systemMessageType], ZMSystemMessageTypePotentialGap);
}

- (void)testThatSystemMessageIsAddedIfClientWasInactiveAndCantFetchAllNotifications
{
    // given
    XCTAssert([self login]);

    ZMConversation *groupConversation = [self conversationForMockConversation:self.groupConversation];
    
    NSUUID *firstMessageNonce = NSUUID.createUUID;
    [self.mockTransportSession performRemoteChanges:^(id<MockTransportSessionObjectCreation> session __unused) {
        ZMGenericMessage *message = [ZMGenericMessage messageWithContent:[ZMText textWith:@"Message Text" mentions:@[] linkPreviews:@[] replyingTo:nil] nonce:firstMessageNonce];
        [self.groupConversation encryptAndInsertDataFromClient:self.user1.clients.anyObject toClient:self.selfUser.clients.anyObject data:message.data];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    NSUUID *payloadNotificationID = NSUUID.createUUID;
    NSUUID *lastMessageNonce = NSUUID.createUUID;
    NSDate *messageTimeStamp = [[NSDate date] dateByAddingTimeInterval:1000];
    MockUserClient *fromClient = self.user2.clients.anyObject, *toClient = self.selfUser.clients.anyObject;
    
    ZMGenericMessage *message = [ZMGenericMessage messageWithContent:[ZMText textWith:@"this should be inserted after the system message"
                                                                             mentions:@[]
                                                                         linkPreviews:@[]
                                                                           replyingTo:nil]
                                                               nonce:lastMessageNonce];
    NSData *encryptedData = [MockUserClient encryptedWithData:message.data from:fromClient to:toClient];
    
    // when
    NSDictionary *payload = @{
                              @"notifications" :@[ @{
                                                       @"id" : payloadNotificationID.transportString,
                                                       @"payload" : @[
                                                               @{
                                                                   @"conversation": groupConversation.remoteIdentifier.transportString,
                                                                   @"type": @"conversation.otr-message-add",
                                                                   @"from": fromClient.user.identifier,
                                                                   // We use a later date to simulate the time between the last message
                                                                   @"time": messageTimeStamp.transportString,
                                                                   @"data": @{
                                                                           @"recipient": toClient.identifier,
                                                                           @"sender": fromClient.identifier,
                                                                           @"text": encryptedData.base64String
                                                                           }
                                                                   },
                                                               ]
                                                       }]
                              };
    [self enforceSlowSyncWithNotificationPayload:payload];
    [self recreateSessionManager];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    NSArray<ZMMessage *> *lastMessages = [groupConversation lastMessagesWithLimit:50];
    XCTAssertEqual([(ZMSystemMessage *)lastMessages[1] systemMessageType], ZMSystemMessageTypePotentialGap);
    XCTAssertEqualObjects([[(ZMSystemMessage *)lastMessages[0] nonce] transportString], lastMessageNonce.transportString);
}

- (void)performRemoteChangesNotInNotificationStream:(void(^)(id<MockTransportSessionObjectCreation> session))changes
{
    // when
    [self destroySessionManager];
    
    [self.mockTransportSession performRemoteChanges:^(id<MockTransportSessionObjectCreation> session __unused) {
        [session simulatePushChannelClosed];
        changes(session);
    }];

    [self.mockTransportSession performRemoteChanges:^(id<MockTransportSessionObjectCreation> session __unused) {
        [session clearNotifications];
    }];

    WaitForAllGroupsToBeEmpty(0.1);

    [self enforceSlowSyncWithNotificationPayload:@{@"notifications" : @[]}];
    [self createSessionManager];

    WaitForAllGroupsToBeEmpty(0.1);

    self.mockTransportSession.responseGeneratorBlock = nil;
}

- (void)testThatPotentialGapSystemMessageContainsAddedAndRemovedUsers
{
    // given
    XCTAssert([self login]);
    
    [self.userSession performChanges:^{
        [self.groupConversation removeUsersByUser:self.user2 removedUser:self.user3];
    }];
    WaitForAllGroupsToBeEmpty(0.5);

    NSUUID *firstMessageNonce = NSUUID.createUUID;
    [self.mockTransportSession performRemoteChanges:^(id<MockTransportSessionObjectCreation> session __unused) {
        ZMGenericMessage *message = [ZMGenericMessage messageWithContent:[ZMText textWith:@"Message Text" mentions:@[] linkPreviews:@[] replyingTo:nil] nonce:firstMessageNonce];
        [self.groupConversation encryptAndInsertDataFromClient:self.user1.clients.anyObject toClient:self.selfUser.clients.anyObject data:message.data];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // when
    [self performRemoteChangesNotInNotificationStream:^(id<MockTransportSessionObjectCreation> session __unused) {
        [self.groupConversation removeUsersByUser:self.user2 removedUser:self.user1];
        [self.groupConversation addUsersByUser:self.user2 addedUsers:@[self.user4]];
    }];
    
    ZMConversation *conversation = [self conversationForMockConversation:self.groupConversation];
    ZMSystemMessage *systemMessage = (ZMSystemMessage *)conversation.lastMessage;
    
    ZMUser *addedUser = [self userForMockUser:self.user4];
    ZMUser *removedUser = [self userForMockUser:self.user1];
    
    // then
    XCTAssertEqual(conversation.activeParticipants.count, 3lu);
    XCTAssertEqual(systemMessage.users.count, 3lu);
    XCTAssertEqual(systemMessage.addedUsers.count, 1lu);
    XCTAssertEqual(systemMessage.removedUsers.count, 1u);
    XCTAssertEqualObjects([systemMessage.addedUsers.anyObject objectID], addedUser.objectID);
    XCTAssertEqualObjects([systemMessage.removedUsers.anyObject objectID], removedUser.objectID);
    XCTAssertEqual(systemMessage.systemMessageType, ZMSystemMessageTypePotentialGap);
    XCTAssertFalse(systemMessage.needsUpdatingUsers);
}

- (void)testThatPreviousPotentialGapSystemMessageGetsDeletedAndNewOneUpdatesWithOldUsers
{
    // given
    XCTAssert([self login]);
    ZMConversation *conversation = [self conversationForMockConversation:self.groupConversation];
    XCTAssertNotNil(conversation);
    
    NSUUID *firstMessageNonce = NSUUID.createUUID;
    [self.mockTransportSession performRemoteChanges:^(id<MockTransportSessionObjectCreation> session __unused) {
        ZMGenericMessage *message = [ZMGenericMessage messageWithContent:[ZMText textWith:@"Message Text" mentions:@[] linkPreviews:@[] replyingTo:nil] nonce:firstMessageNonce];
        [self.groupConversation encryptAndInsertDataFromClient:self.user1.clients.anyObject toClient:self.selfUser.clients.anyObject data:message.data];
    }];
    
    WaitForAllGroupsToBeEmpty(0.1);
    
    // when
    [self performRemoteChangesNotInNotificationStream:^(id<MockTransportSessionObjectCreation> session __unused) {
        [self.groupConversation removeUsersByUser:self.user2 removedUser:self.user1];
        [self.groupConversation addUsersByUser:self.user2 addedUsers:@[self.user4]];
    }];
    
    ZMSystemMessage *systemMessage = (ZMSystemMessage *)conversation.lastMessage;
    
    // then
    XCTAssertEqual(systemMessage.users.count, 4lu);
    XCTAssertFalse(systemMessage.needsUpdatingUsers);
    
    // when
    WaitForAllGroupsToBeEmpty(0.1);
    [self performRemoteChangesNotInNotificationStream:^(id<MockTransportSessionObjectCreation> session __unused) {
        [self.groupConversation removeUsersByUser:self.user2 removedUser:self.user3];
        [self.groupConversation addUsersByUser:self.user2 addedUsers:@[self.user1, self.user5]];
    }];
    
    ZMSystemMessage *secondSystemMessage = (ZMSystemMessage *)conversation.lastMessage;
    XCTAssertNotEqualObjects(systemMessage, secondSystemMessage);
    
    NSSet <ZMUser *>*addedUsers = [NSSet setWithObjects:[self userForMockUser:self.user4], [self userForMockUser:self.user5], nil];
    NSSet <ZMUser *>*initialUsers = [NSSet setWithObjects:[self userForMockUser:self.selfUser],
                                     [self userForMockUser:self.user3],
                                     [self userForMockUser:self.user2],
                                     [self userForMockUser:self.user1], nil];
    ZMUser *removedUser = [self userForMockUser:self.user3];
    
    // then
    XCTAssertEqual(conversation.activeParticipants.count, 5lu);
    XCTAssertEqualObjects(secondSystemMessage.users, initialUsers);
    XCTAssertEqual(secondSystemMessage.addedUsers.count, 2lu);
    XCTAssertEqual(secondSystemMessage.removedUsers.count, 1lu);
    XCTAssertEqualObjects(secondSystemMessage.addedUsers, addedUsers);
    XCTAssertEqualObjects(secondSystemMessage.removedUsers.anyObject.objectID, removedUser.objectID);
    XCTAssertEqual(secondSystemMessage.systemMessageType, ZMSystemMessageTypePotentialGap);
    XCTAssertFalse(secondSystemMessage.needsUpdatingUsers);
}

- (void)testThatPotentialGapSystemMessageGetsUpdatedWithAddedUserWhenUserNameIsFetched
{
    // given
    XCTAssert([self login]);
    ZMConversation *conversation = [self conversationForMockConversation:self.groupConversation];
    
    NSUUID *firstMessageNonce = NSUUID.createUUID;
    [self.mockTransportSession performRemoteChanges:^(id<MockTransportSessionObjectCreation> session __unused) {
        ZMGenericMessage *message = [ZMGenericMessage messageWithContent:[ZMText textWith:@"Hello" mentions:@[] linkPreviews:@[] replyingTo:nil] nonce:firstMessageNonce];
        [self.groupConversation encryptAndInsertDataFromClient:self.user1.clients.anyObject toClient:self.selfUser.clients.anyObject data:message.data];
    }];
    
    WaitForAllGroupsToBeEmpty(0.5);
    
    // when
    // add new user to conversation
    __block MockUser *newMockUser;
    ZM_WEAK(self);
    [self performRemoteChangesNotInNotificationStream:^(id<MockTransportSessionObjectCreation> session __unused) {
        ZM_STRONG(self);
        newMockUser = [session insertUserWithName:@"Bruno"];
        [self.groupConversation addUsersByUser:self.user2 addedUsers:@[newMockUser]];
    }];
    
    conversation = [self conversationForMockConversation:self.groupConversation];
    ZMSystemMessage *systemMessage = (ZMSystemMessage *)conversation.lastMessage;
    
    ZMUser *addedUser = systemMessage.addedUsers.anyObject;
    
    // then after fetching it should contain the full users
    XCTAssertEqual(systemMessage.users.count, 4lu);
    XCTAssertEqual(systemMessage.removedUsers.count, 0lu);
    XCTAssertEqual(systemMessage.addedUsers.count, 1lu);
    XCTAssertNotNil(addedUser);
    XCTAssertEqualObjects(addedUser.name, @"Bruno");
    XCTAssertFalse(systemMessage.needsUpdatingUsers);
}

- (void)testThatConversationNameChangedSystemMessagesContainTheConversationTitle
{
    // given
    NSString *newName1 = @"Shiny new name";
    NSString *newName2 = @"Even shinier new name";
    
    XCTAssert([self login]);
    
    ZMConversation *groupConversation = [self conversationForMockConversation:self.groupConversation];
    XCTAssertNotEqual(groupConversation.displayName, newName1);
    
    // when
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        [self.groupConversation changeNameByUser:session.selfUser name:newName1];
    }];
    WaitForAllGroupsToBeEmpty(0.1);
    
    
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        [self.groupConversation changeNameByUser:session.selfUser name:newName2];
    }];
    WaitForAllGroupsToBeEmpty(0.1);
    
    // then
    NSArray<ZMMessage *> *lastMessages = [groupConversation lastMessagesWithLimit:50];
    XCTAssertEqual([(ZMSystemMessage *)lastMessages[1] systemMessageType], ZMSystemMessageTypeConversationNameChanged);
    XCTAssertEqual([(ZMSystemMessage *)lastMessages[0] systemMessageType], ZMSystemMessageTypeConversationNameChanged);
    
    XCTAssertEqualObjects([(ZMSystemMessage *)lastMessages[1] text],  newName1);
    XCTAssertEqualObjects([(ZMSystemMessage *)lastMessages[0] text],  newName2);
}


- (void)testThatItExpiresAMessage
{
    // given
    XCTAssert([self login]);
    
    ZMConversation *groupConversation = [self conversationForMockConversation:self.groupConversation];
    XCTAssertNotNil(groupConversation);
    
    self.mockTransportSession.doNotRespondToRequests = YES;
    [ZMMessage setDefaultExpirationTime:0.1]; //We don't want to wait 60 seconds
    __block ZMMessage *message;
    [self.userSession performChanges:^{
        message = (id)[groupConversation appendMessageWithText:@"lalala"];
    }];
    XCTAssertTrue([groupConversation.managedObjectContext saveOrRollback]);
    
    // when
    WaitForAllGroupsToBeEmpty(0.1);
    XCTAssertTrue([self waitOnMainLoopUntilBlock:^BOOL{
        return message.isExpired;
    } timeout:0.5]);
    
    
    //then
    XCTAssertTrue(message.isExpired);
    XCTAssertEqual(message.deliveryState, ZMDeliveryStateFailedToSend);
    
    
    // finally
    [ZMMessage resetDefaultExpirationTime];
}


- (void)testThatItResendsAMessage
{
    // given
    XCTAssert([self login]);
    
    ZMConversation *groupConversation = [self conversationForMockConversation:self.groupConversation];
    XCTAssertNotNil(groupConversation);
    [self prefetchRemoteClientByInsertingMessageInConversation:self.groupConversation];
    
    
    self.mockTransportSession.doNotRespondToRequests = YES;
    [ZMMessage setDefaultExpirationTime:0.1]; //We don't want to wait 60 seconds
    __block ZMMessage *message;
    [self.userSession performChanges:^{
        message = (id)[groupConversation appendMessageWithText:@"lalala"];
    }];
    XCTAssertTrue([groupConversation.managedObjectContext saveOrRollback]);
    
    WaitForAllGroupsToBeEmpty(0.1);
    XCTAssertTrue([self waitOnMainLoopUntilBlock:^BOOL{
        return message.isExpired;
    } timeout:0.5]);
    
    XCTAssertTrue(message.isExpired);
    XCTAssertEqual(message.deliveryState, ZMDeliveryStateFailedToSend);

    // when
    self.mockTransportSession.doNotRespondToRequests = NO;
    [self.userSession performChanges:^{
        [message resend];
    }];

    // then
    WaitForAllGroupsToBeEmpty(0.1);
    XCTAssertFalse(message.isExpired);
    XCTAssertNotEqual(message.deliveryState, ZMDeliveryStateFailedToSend);

    // finally
    [ZMMessage resetDefaultExpirationTime];
}

- (void)testThatWhenResendingAMessageChangesTheStateToPending
{
    // given
    XCTAssert([self login]);
    
    ZMConversation *groupConversation = [self conversationForMockConversation:self.groupConversation];
    XCTAssertNotNil(groupConversation);
    
    self.mockTransportSession.doNotRespondToRequests = YES;
    [ZMMessage setDefaultExpirationTime:0.1]; //We don't want to wait 60 seconds
    __block ZMMessage *message;
    [self.userSession performChanges:^{
        message = (id)[groupConversation appendMessageWithText:@"lalala"];
    }];
    XCTAssertTrue([groupConversation.managedObjectContext saveOrRollback]);
    
    WaitForAllGroupsToBeEmpty(0.1);
    XCTAssertTrue([self waitOnMainLoopUntilBlock:^BOOL{
        return message.isExpired;
    } timeout:0.5]);
    
    XCTAssertTrue(message.isExpired);
    XCTAssertEqual(message.deliveryState, ZMDeliveryStateFailedToSend);
    
    // when
    self.mockTransportSession.doNotRespondToRequests = YES;
    [ZMMessage setDefaultExpirationTime:0.3];
    [self.userSession performChanges:^{
        [message resend];
    }];
    
    // then
    XCTAssertFalse(message.isExpired);
    XCTAssertEqual(message.deliveryState, ZMDeliveryStatePending);

    // finally
    WaitForAllGroupsToBeEmpty(0.1);
    [ZMMessage resetDefaultExpirationTime];
}

- (void)testThatIfWeExpireAMessageButStillGetAResponseThatWeUseIt
{
    // given
    XCTAssert([self login]);
    
    ZMConversation *groupConversation = [self conversationForMockConversation:self.groupConversation];
    XCTAssertNotNil(groupConversation);
    [self prefetchRemoteClientByInsertingMessageInConversation:self.groupConversation];
    [self.mockTransportSession resetReceivedRequests];
    
    self.mockTransportSession.doNotRespondToRequests = NO;
    [ZMMessage setDefaultExpirationTime:0.1]; //We don't want to wait 60 seconds
    __block id<ZMConversationMessage> message;
    [self.userSession performChanges:^{
        message = [groupConversation appendMessageWithText:@"lalala"];
    }];
    XCTAssertTrue([groupConversation.managedObjectContext saveOrRollback]);
    
    // when
    WaitForAllGroupsToBeEmpty(0.1);

    //then
    XCTAssertEqual(message.deliveryState, ZMDeliveryStateSent);
    
    // finally
    [ZMMessage resetDefaultExpirationTime];
}

- (void)testThatWhenResendingAMessageWeOnlyGetANotificationForStateChangingToPending
{
    // given
    XCTAssert([self login]);
    
    ZMConversation *groupConversation = [self conversationForMockConversation:self.groupConversation];
    XCTAssertNotNil(groupConversation);
    
    self.mockTransportSession.doNotRespondToRequests = YES;
    [ZMMessage setDefaultExpirationTime:0.1]; //We don't want to wait 60 seconds
    
    __block ZMMessage *message;
    [self.userSession performChanges:^{
        message = (id)[groupConversation appendMessageWithText:@"lalala"];
    }];
    XCTAssertTrue([groupConversation.managedObjectContext saveOrRollback]);
    
    WaitForAllGroupsToBeEmpty(0.1);
    XCTAssertTrue([self waitOnMainLoopUntilBlock:^BOOL{
        return message.isExpired;
    } timeout:0.5]);
    
    XCTAssertTrue(message.isExpired);
    XCTAssertEqual(message.deliveryState, ZMDeliveryStateFailedToSend);
    
    MessageChangeObserver *observer = [[MessageChangeObserver alloc] initWithMessage:message];
    
    // when
    self.mockTransportSession.doNotRespondToRequests = YES;
    [ZMMessage setDefaultExpirationTime:0.3];
    
    [self.userSession performChanges:^{
        [message resend];
    }];

    // then
    XCTAssertEqual(observer.notifications.count, 1u);
    if (observer.notifications.count > 0 ) {
        MessageChangeInfo *note = observer.notifications.firstObject;
        XCTAssertTrue(note.deliveryStateChanged);
        XCTAssertFalse(note.imageChanged);
        XCTAssertFalse(note.senderChanged);
        
        XCTAssertEqual(message.deliveryState, ZMDeliveryStatePending);
    }
    
    // finally
    WaitForAllGroupsToBeEmpty(0.1);
    [ZMMessage resetDefaultExpirationTime];
}

- (void)testThatItResendsMessages
{
    // given
    XCTAssert([self login]);
    
    ZMConversation *groupConversation = [self conversationForMockConversation:self.groupConversation];
    XCTAssertNotNil(groupConversation);
    
    self.mockTransportSession.doNotRespondToRequests = YES;
    [ZMMessage setDefaultExpirationTime:0.2]; //We don't want to wait 60 seconds
    
    __block id<ZMConversationMessage> message;
    [self.userSession performChanges:^{
        message = [groupConversation appendMessageWithText:@"lalala"];
    }];
    XCTAssertTrue([groupConversation.managedObjectContext saveOrRollback]);
    
    XCTAssertTrue([self waitOnMainLoopUntilBlock:^BOOL{
        return message.deliveryState == ZMDeliveryStateFailedToSend;
    } timeout:0.5]);
    
    // when
    self.mockTransportSession.doNotRespondToRequests = NO;
    [ZMMessage setDefaultExpirationTime:60];
    WaitForAllGroupsToBeEmpty(0.1);
    
    [self.userSession performChanges:^{
        [message resend];
    }];
    
    WaitForAllGroupsToBeEmpty(0.1);
    
    // then
    XCTAssertTrue([self waitOnMainLoopUntilBlock:^BOOL{
        return message.deliveryState == ZMDeliveryStateSent;
    } timeout:0.5]);
    
    // finally
    [ZMMessage resetDefaultExpirationTime];
}

#pragma mark - Hiding messages

- (void)testThatItHidesAMessageWhenAskedTo
{
    // given
    XCTAssert([self login]);
    
    ZMConversation *groupConversation = [self conversationForMockConversation:self.groupConversation];
    XCTAssertNotNil(groupConversation);
    
    __block ZMMessage *message;
    __block NSUUID *messageNonce;
    [self.userSession performChanges:^{
        message = (id)[groupConversation appendMessageWithText:@"lalala"];
        messageNonce = message.nonce;
    }];
    XCTAssertTrue([groupConversation.managedObjectContext saveOrRollback]);
    WaitForAllGroupsToBeEmpty(0.1);
    
    //when
    [self.userSession performChanges:^{
        [ZMMessage hideMessage:message];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    message = [ZMMessage fetchMessageWithNonce:messageNonce forConversation:groupConversation inManagedObjectContext:self.userSession.managedObjectContext];
    XCTAssertNil(message);
}

- (void)testThatItSyncsWhenAMessageHideIsRemotelyAppended;
{
    // given
    XCTAssert([self login]);
    
    ZMConversation *groupConversation = [self conversationForMockConversation:self.groupConversation];
    XCTAssertNotNil(groupConversation);
    
    __block ZMMessage *message;
    __block NSUUID *messageNonce;
    [self.userSession performChanges:^{
        message = (id)[groupConversation appendMessageWithText:@"lalala"];
        messageNonce = message.nonce;
    }];
    XCTAssertTrue([groupConversation.managedObjectContext saveOrRollback]);
    WaitForAllGroupsToBeEmpty(0.1);
    XCTAssertNotNil(message);
    
    //when
    ZMGenericMessage *genericMessage = [ZMGenericMessage messageWithContent:[ZMMessageHide hideWithConversationId:groupConversation.remoteIdentifier messageId:messageNonce] nonce:NSUUID.createUUID];

    // when
    [self.mockTransportSession performRemoteChanges:^(id session) {
        NOT_USED(session);
        [self.selfConversation insertClientMessageFromUser:self.selfUser data:genericMessage.data];
    }];

    WaitForAllGroupsToBeEmpty(0.1);
    
    message = [ZMMessage fetchMessageWithNonce:messageNonce forConversation:groupConversation inManagedObjectContext:self.userSession.managedObjectContext];
    XCTAssertNil(message);
}

@end
