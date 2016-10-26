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
@import ZMCMockTransport;
@import ZMCDataModel;

#import "IntegrationTestBase.h"
#import "ZMUserSession+Internal.h"
#import "ConversationTestsBase.h"


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

    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    WaitForEverythingToBeDone();

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
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    ZMConversation *conversation = [self conversationForMockConversation:self.groupConversation];
    
    // when
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        NOT_USED(session);
        ZMGenericMessage *message = [ZMGenericMessage messageWithText:messageText nonce:NSUUID.createUUID.transportString expiresAfter:nil];
        [self.groupConversation encryptAndInsertDataFromClient:self.user1.clients.anyObject toClient:self.selfUser.clients.anyObject data:message.data];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    id<ZMConversationMessage> lastMessage = conversation.messages.lastObject;
    XCTAssertEqualObjects(lastMessage.textMessageData.messageText, messageText);
}

- (ZMConversation *)setUpStateAndConversation {
    
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    WaitForEverythingToBeDone();
    
    
    ZMConversation *groupConversation = [self conversationForMockConversation:self.groupConversation];
    XCTAssertNotNil(groupConversation);
    
    return groupConversation;
}


- (void)testThatItDoesNotSyncTheLastReadOfMessagesThatHaveNotBeenDeliveredYet
{
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeCompleteWithTimeout:0.6]);
    WaitForAllGroupsToBeEmpty(0.5);

    __block NSUInteger count = 0;
    dispatch_block_t insertMessage  = ^{
        NSString *text = [NSString stringWithFormat:@"text %lu", count];
        ZMGenericMessage *message = [ZMGenericMessage messageWithText:text nonce:NSUUID.createUUID.transportString expiresAfter:nil];
        [self.groupConversation encryptAndInsertDataFromClient:self.user1.clients.anyObject toClient:self.selfUser.clients.anyObject data:message.data];
    };
    
    [self.mockTransportSession performRemoteChanges:^(ZM_UNUSED id session) {
        for (int i = 0; i < 4; i++) {
            insertMessage();
        }
        [self spinMainQueueWithTimeout:1.0];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    ZMConversation *conversation =  [self conversationForMockConversation:self.groupConversation];
    NSString *convIDString = conversation.remoteIdentifier.transportString;
    
    NSDate *pastDate = [[NSDate date] dateByAddingTimeInterval:-100];
    XCTAssertEqual(conversation.messages.count, 6u);
    
    self.mockTransportSession.responseGeneratorBlock = ^ZMTransportResponse *(ZMTransportRequest *request){
        if ([request.path containsString:@"messages"] && request.method == ZMMethodPOST) {
            if ([request.path containsString:convIDString]) {
                return [ZMTransportResponse responseWithTransportSessionError:[NSError requestExpiredError]];
            }
        }
        return nil;
    };
    
    // when
    ZMMessage *previousMessage =  conversation.messages.lastObject;
    
    __block ZMMessage *message;
    [self.userSession performChanges:^{
        message = (id)[conversation appendMessageWithText:@"test"];
        [message setServerTimestamp:pastDate];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    [self.mockTransportSession performRemoteChanges:^(ZM_UNUSED id session) {
        insertMessage();
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    XCTAssertEqualObjects(message.serverTimestamp, pastDate);
    XCTAssertEqual(message.deliveryState, ZMDeliveryStateFailedToSend);
    
    [self.userSession performChanges:^{
        [conversation setVisibleWindowFromMessage:nil toMessage:message];
    }];
    WaitForAllGroupsToBeEmpty(0.5);

    // then
    XCTAssertNotNil(conversation.lastReadServerTimeStamp);
    XCTAssertNotEqualWithAccuracy([conversation.lastReadServerTimeStamp timeIntervalSince1970], [message.serverTimestamp timeIntervalSince1970], 0.5);
    XCTAssertEqualWithAccuracy([conversation.lastReadServerTimeStamp timeIntervalSince1970], [previousMessage.serverTimestamp timeIntervalSince1970], 0.5);
}

- (void)testThatItSetsTheLastReadWhenInsertingAnImage
{
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    WaitForEverythingToBeDone();

    [self prefetchRemoteClientByInsertingMessageInConversation:self.groupConversation];
    
    ZMConversation *conversation =  [self conversationForMockConversation:self.groupConversation];
    
    XCTAssertEqual(conversation.messages.count, 3u);
    id<ZMConversationMessage> originalMessage = [conversation.messages lastObject];
    XCTAssertEqualWithAccuracy([conversation.lastReadServerTimeStamp timeIntervalSince1970], [originalMessage.serverTimestamp timeIntervalSince1970], 0.1);
    [self spinMainQueueWithTimeout:0.5]; // if the tests run too fast the new message would otherwise have the same timestamp
    
    // when
    __block ZMMessage *message;
    [self.userSession performChanges:^{
        message = (id)[conversation appendMessageWithImageData:self.verySmallJPEGData];
    }];
    WaitForEverythingToBeDone();
    
    // then
    XCTAssertNotNil(conversation.lastReadServerTimeStamp);
    XCTAssertNotEqualWithAccuracy([conversation.lastReadServerTimeStamp timeIntervalSince1970], [originalMessage.serverTimestamp timeIntervalSince1970], 0.1);
    XCTAssertEqualWithAccuracy([conversation.lastReadServerTimeStamp timeIntervalSince1970], [message.serverTimestamp timeIntervalSince1970], 0.1);

}

- (void)testThatItSetsTheLastReadWhenInsertingAText
{
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    WaitForAllGroupsToBeEmpty(0.5);
    
    ZMConversation *conversation =  [self conversationForMockConversation:self.groupConversation];
    NSString *convIDString = conversation.remoteIdentifier.transportString;
    
    NSDate *pastDate = [[NSDate date] dateByAddingTimeInterval:-100];
    XCTAssertEqual(conversation.messages.count, 2u);
    XCTAssertNil(conversation.lastReadServerTimeStamp);
    
    self.mockTransportSession.responseGeneratorBlock = ^ZMTransportResponse *(ZMTransportRequest *request){
        if ([request.path containsString:@"assets"] && request.method == ZMMethodPOST && [request.path containsString:convIDString]) {
            // set the date to a previous date to make sure we see if the serverTimeStamp changes
            [self.userSession performChanges:^{
                [conversation.messages.lastObject setServerTimestamp:pastDate];
            }];
            return nil;
        }
        return nil;
    };
    
    // when
    __block ZMMessage *message;
    [self.userSession performChanges:^{
        message = (id)[conversation appendMessageWithText:@"oh hallo"];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertNotNil(conversation.lastReadServerTimeStamp);
    XCTAssertNotEqualWithAccuracy([conversation.lastReadServerTimeStamp timeIntervalSince1970], [pastDate timeIntervalSince1970], 1.0);
}

- (void)testThatItSetsTheLastReadWhenInsertingAKnock
{
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeCompleteWithTimeout:0.6]);
    WaitForAllGroupsToBeEmpty(0.5);
    
    ZMConversation *conversation =  [self conversationForMockConversation:self.groupConversation];
    NSString *convIDString = conversation.remoteIdentifier.transportString;
    
    NSDate *pastDate = [[NSDate date] dateByAddingTimeInterval:-100];
    XCTAssertEqual(conversation.messages.count, 2u);
    XCTAssertNil(conversation.lastReadServerTimeStamp);
    
    self.mockTransportSession.responseGeneratorBlock = ^ZMTransportResponse *(ZMTransportRequest *request){
        if ([request.path containsString:@"assets"] && request.method == ZMMethodPOST && [request.path containsString:convIDString]) {
            // set the date to a previous date to make sure we see if the serverTimeStamp changes
            [self.userSession performChanges:^{
                [conversation.messages.lastObject setServerTimestamp:pastDate];
            }];
            return nil;
        }
        return nil;
    };
    
    // when
    __block ZMMessage *message;
    [self.userSession performChanges:^{
        message = (id)[conversation appendKnock];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertNotNil(conversation.lastReadServerTimeStamp);
    XCTAssertNotEqualWithAccuracy([conversation.lastReadServerTimeStamp timeIntervalSince1970], [pastDate timeIntervalSince1970], 1.0);
}

- (void)testThatItSetsTheLastReadWhenInsertingAMessageWithURL
{
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeCompleteWithTimeout:0.6]);
    WaitForAllGroupsToBeEmpty(0.5);
    
    ZMConversation *conversation =  [self conversationForMockConversation:self.groupConversation];
    NSDate *pastDate = [NSDate dateWithTimeIntervalSince1970:12333333];
    XCTAssertEqual(conversation.messages.count, 2u);
    XCTAssertNil(conversation.lastReadServerTimeStamp);
    
    // when
    __block ZMMessage *message;
    [self.userSession performChanges:^{
        NSURL *imageFileURL = [self fileURLForResource:@"1900x1500" extension:@"jpg"];
        message = (id)[conversation appendMessageWithImageAtURL:imageFileURL];
    }];
    WaitForAllGroupsToBeEmpty(5);
    
    [self.userSession performChanges:^{
        [conversation.messages.lastObject setServerTimestamp:pastDate];
    }];
    WaitForAllGroupsToBeEmpty(5);
    
    // then
    XCTAssertNotNil(conversation.lastReadServerTimeStamp);
    XCTAssertNotEqualWithAccuracy([conversation.lastReadServerTimeStamp timeIntervalSince1970], [pastDate timeIntervalSince1970], 1.0);
}

- (void)testThatItAppendsClientMessages
{
    NSString *expectedText1 = @"The sky above the port was the color of ";
    NSString *expectedText2 = @"television, tuned to a dead channel.";
    
    NSUUID *nonce1 = [NSUUID createUUID];
    NSUUID *nonce2 = [NSUUID createUUID];
    
    ZMGenericMessage *genericMessage1 = [ZMGenericMessage messageWithText:expectedText1 nonce:nonce1.transportString expiresAfter:nil];
    ZMGenericMessage *genericMessage2 = [ZMGenericMessage messageWithText:expectedText2 nonce:nonce2.transportString expiresAfter:nil];
    
    [self testThatItAppendsMessageToConversation:self.groupConversation
                                       withBlock:^NSArray *(id __unused session){
                                           [self.groupConversation insertClientMessageFromUser:self.user2 data:genericMessage1.data];
                                           [self spinMainQueueWithTimeout:0.2];
                                           [self.groupConversation insertClientMessageFromUser:self.user3 data:genericMessage2.data];
                                           return @[nonce1, nonce2];
                                       } verify:^(ZMConversation *conversation) {
                                           ZMClientMessage *msg1 = conversation.messages[conversation.messages.count - 2];
                                           XCTAssertEqualObjects(msg1.nonce, nonce1);
                                           XCTAssertEqualObjects(msg1.genericMessage.text.content, expectedText1);
                                           
                                           ZMClientMessage *msg2 = conversation.messages[conversation.messages.count - 1];
                                           XCTAssertEqualObjects(msg2.nonce, nonce2);
                                           XCTAssertEqualObjects(msg2.genericMessage.text.content, expectedText2);
                                       }];
}


- (MockPushEvent *)lastEventForConversation:(MockConversation *)conversation inReceivedEvents:(NSArray *)receivedEvents
{
    __block MockPushEvent *event;
    [receivedEvents enumerateObjectsWithOptions:NSEnumerationReverse usingBlock:^(MockPushEvent *anEvent, NSUInteger idx, BOOL *stop){
        NOT_USED(idx);
        if ([anEvent.payload[@"conversation"] isEqualToString:conversation.identifier]) {
            *stop = YES;
            event = anEvent;
        }
    }];
    return event;
}


- (void)testThatMessageIsSentIfNoPreviousPendingMessagesInConversation
{
    //given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
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
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    WaitForAllGroupsToBeEmpty(0.5);
    
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
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
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
    self.mockTransportSession.responseGeneratorBlock = ^ZMTransportResponse *(ZMTransportRequest *request) {
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
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    WaitForAllGroupsToBeEmpty(0.5);
    
    ZMConversation *conversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    XCTAssertNotNil(conversation);
    [self.mockTransportSession resetReceivedRequests];
    
    //when
    //there is previous pending message
    
    //we block first request from finishing and check that no other requests are comming in
    __block ZMTransportRequest *firstRequest;
    XCTestExpectation *firstRequestRecievedExpectation = [self expectationWithDescription:@"Recieved request to add first message"];
    self.mockTransportSession.responseGeneratorBlock = ^ZMTransportResponse *(ZMTransportRequest *request) {
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
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
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
                              ZMGenericMessage *message = [ZMGenericMessage messageWithText:expectedText nonce:nonce.transportString expiresAfter:nil];
                              [self.groupConversation encryptAndInsertDataFromClient:self.user2.clients.anyObject toClient:self.selfUser.clients.anyObject data:message.data];
                          } verify:^(ZMConversation *conversation) {
                              ZMMessage *msg = conversation.messages[conversation.messages.count - 1];
                              XCTAssertEqualObjects(msg.textMessageData.messageText, expectedText);
                          }];
}

- (void)testThatItSendsANotificationWhenRecievingAClientMessageThroughThePushChannel
{
    NSString *expectedText = @"The sky above the port was the color of ";
    ZMGenericMessage *message = [ZMGenericMessage messageWithText:expectedText nonce:[NSUUID createUUID].transportString expiresAfter:nil];
    
    [self testThatItSendsANotificationInConversation:self.groupConversation
                                      ignoreLastRead:NO
                          onRemoteMessageCreatedWith:^{
                              [self.groupConversation insertClientMessageFromUser:self.user2 data:message.data];
                          } verify:^(ZMConversation *conversation) {
                              ZMClientMessage *msg = conversation.messages[conversation.messages.count - 1];
                              XCTAssertEqualObjects(msg.genericMessage.text.content, expectedText);
                          }];
}

- (void)testThatInsertedConversationsArePropagatedToTheUIContext;
{
    // given
    ZMConversationList *list = [ZMConversationList conversationsInUserSession:self.userSession];
    XCTAssertEqual(list.count, 0u);
    
    ConversationListChangeObserver *observer = [[ConversationListChangeObserver alloc] initWithConversationList:list];
    
    // when
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    
    // assert
    XCTAssertEqual(list.count, 4u);
    [observer tearDown];
}

- (void)testThatSystemEventsAreAddedToAConversationWhenTheyAreGeneratedRemotely
{
    // given
    NSString *newName = @"Shiny new name";
    
    
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    WaitForEverythingToBeDone();
    
    ZMConversation *groupConversation = [self conversationForMockConversation:self.groupConversation];
    XCTAssertNotNil(groupConversation);
    XCTAssertNotEqual(groupConversation.displayName, newName);
    
    // make a copy of the current ones (since it's a relationship, it seems that [set copy] just doesn't work)
    NSOrderedSet *previousMessages = [groupConversation.messages mutableCopy];
    
    // when
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        [self.groupConversation changeNameByUser:session.selfUser name:newName];
        [self spinMainQueueWithTimeout:0.2];
        [self.groupConversation addUsersByUser:session.selfUser addedUsers:@[self.user4]];
    }];
    WaitForEverythingToBeDone();
    
    // then
    NSMutableOrderedSet *extraMessages = [groupConversation.messages mutableCopy];
    [extraMessages minusOrderedSet:previousMessages];
    
    XCTAssertEqual(extraMessages.count, 2u);
    XCTAssertEqual([extraMessages[0] systemMessageType], ZMSystemMessageTypeConversationNameChanged);
    XCTAssertEqual([extraMessages[1] systemMessageType], ZMSystemMessageTypeParticipantsAdded);
    
    ZMUser *user4 = [self userForMockUser:self.user4];
    XCTAssertEqualObjects([extraMessages[1] users],  [NSSet setWithArray:@[user4]]);
    XCTAssertTrue([groupConversation.activeParticipants containsObject:user4]);
}

- (void)testThatSystemMessageIsAddedIfClientWasInactiveAndCantFetchAnyNotifications
{
    // given
    self.registeredOnThisDevice = YES;
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    WaitForEverythingToBeDone();
    ZMConversation *groupConversation = [self conversationForMockConversation:self.groupConversation];
    NSUInteger initialMessageCount = groupConversation.messages.count;

    NSUUID *firstMessageNonce = NSUUID.createUUID;
    [self.mockTransportSession performRemoteChanges:^(id<MockTransportSessionObjectCreation> session __unused) {
        ZMGenericMessage *message = [ZMGenericMessage messageWithText:@"Message Text" nonce:firstMessageNonce.transportString expiresAfter:nil];
        [self.groupConversation encryptAndInsertDataFromClient:self.user1.clients.anyObject toClient:self.selfUser.clients.anyObject data:message.data];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    NSSet *previousMessagesIDs = [groupConversation.messages.set mapWithBlock:^NSManagedObjectID *(ZMManagedObject *managedObject) {
        return managedObject.objectID;
    }];
    XCTAssertNotNil(groupConversation);
    
    // when
    self.mockTransportSession.responseGeneratorBlock = ^ZMTransportResponse *(ZMTransportRequest *request) {
        if ([request.path containsString:@"/notifications"]) {
            return [ZMTransportResponse responseWithPayload:nil HTTPStatus:404 transportSessionError:nil];
        }
        return nil;
    };
    
    [self recreateUserSessionAndWipeCache:NO];
    WaitForAllGroupsToBeEmpty(0.5);
    
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    WaitForAllGroupsToBeEmpty(0.5);
    
    NSPredicate *objectIDPredicate = [NSPredicate predicateWithFormat:@"! (%@ CONTAINS objectID)", previousMessagesIDs];
    ZMConversation *conversation = [self conversationForMockConversation:self.groupConversation];
    NSOrderedSet <ZMMessage *>*allMessages = conversation.messages;
    NSUInteger addedMessageCount = [conversation.messages filteredOrderedSetUsingPredicate:objectIDPredicate].count;
    
    // then
    XCTAssertEqual(allMessages.count - initialMessageCount, 2lu);
    XCTAssertEqualObjects(allMessages[initialMessageCount].nonce.transportString, firstMessageNonce.transportString);
    XCTAssertEqual([allMessages.firstObject.serverTimestamp compare:allMessages.lastObject.serverTimestamp], NSOrderedAscending);
    XCTAssertEqual([(ZMSystemMessage *)allMessages.lastObject systemMessageType], ZMSystemMessageTypePotentialGap);
    XCTAssertEqual(addedMessageCount, 1lu); // One system message should have been added
}

- (void)testThatSystemMessageIsAddedIfClientWasInactiveAndCantFetchAllNotifications
{
    // given
    self.registeredOnThisDevice = YES;
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    WaitForEverythingToBeDone();
    ZMConversation *groupConversation = [self conversationForMockConversation:self.groupConversation];
    NSUInteger initialMessageCount = groupConversation.messages.count;
    
    NSUUID *firstMessageNonce = NSUUID.createUUID;
    [self.mockTransportSession performRemoteChanges:^(id<MockTransportSessionObjectCreation> session __unused) {
        ZMGenericMessage *message = [ZMGenericMessage messageWithText:@"Message Text" nonce:firstMessageNonce.transportString expiresAfter:nil];
        [self.groupConversation encryptAndInsertDataFromClient:self.user1.clients.anyObject toClient:self.selfUser.clients.anyObject data:message.data];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    NSSet *previousMessagesIDs = [groupConversation.messages.set mapWithBlock:^NSManagedObjectID *(ZMManagedObject *managedObject) {
        return managedObject.objectID;
    }];
    XCTAssertNotNil(groupConversation);
    
    NSUUID *payloadNotificationID = NSUUID.createUUID;
    NSUUID *lastMessageNonce = NSUUID.createUUID;
    NSDate *messageTimeStamp = [[NSDate date] dateByAddingTimeInterval:1000];
    MockUserClient *fromClient = self.user2.clients.anyObject, *toClient = self.selfUser.clients.anyObject;
    
    ZMGenericMessage *message = [ZMGenericMessage messageWithText:@"this should be inserted after the system message"
                                                            nonce:lastMessageNonce.transportString expiresAfter:nil];
    NSData *encryptedData = [MockUserClient encryptedDataFromClient:fromClient toClient:toClient data:message.data];
    
    // when
    NSDictionary *payload = @{
                              @"notifications" :@[ @{
                                                       @"id" : payloadNotificationID.transportString,
                                                       @"payload" : @[
                                                               @{
                                                                   @"conversation": groupConversation.remoteIdentifier.transportString,
                                                                   @"type": @"conversation.otr-message-add",
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
    
    self.mockTransportSession.responseGeneratorBlock = ^ZMTransportResponse *(ZMTransportRequest *request) {
        if ([request.path hasPrefix:@"/notifications?"]) {
            return [ZMTransportResponse responseWithPayload:payload HTTPStatus:404 transportSessionError:nil];
        }
        return nil;
    };
    
    [self recreateUserSessionAndWipeCache:NO];
    WaitForAllGroupsToBeEmpty(0.5);
    
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    WaitForAllGroupsToBeEmpty(0.5);
    
    NSPredicate *objectIDPredicate = [NSPredicate predicateWithFormat:@"! (%@ CONTAINS objectID)", previousMessagesIDs];
    ZMConversation *conversation = [self conversationForMockConversation:self.groupConversation];
    NSOrderedSet <ZMMessage *>*allMessages = conversation.messages;
    NSOrderedSet <ZMMessage *>*addedMessages = [conversation.messages filteredOrderedSetUsingPredicate:objectIDPredicate];
    XCTAssertNotNil(addedMessages);
    
    // then
    XCTAssertEqual(allMessages.count - initialMessageCount, 3lu);
    XCTAssertEqualObjects(allMessages[initialMessageCount].nonce.transportString, firstMessageNonce.transportString);
    
    XCTAssertEqual(addedMessages.count, 2lu); // One Text and one system message should have been added
    XCTAssertEqual([addedMessages.firstObject.serverTimestamp compare:addedMessages.lastObject.serverTimestamp], NSOrderedAscending);
    XCTAssertEqual([(ZMSystemMessage *)addedMessages.firstObject systemMessageType], ZMSystemMessageTypePotentialGap);
    XCTAssertEqualObjects(addedMessages.lastObject.nonce.transportString, lastMessageNonce.transportString);
}

- (void)performRemoteChangesNotInNotificationStream:(void(^)(id<MockTransportSessionObjectCreation> session))changes
{
    // when
    [self recreateUserSessionAndWipeCache:NO];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // to avoid the client fetching the changes before they are cleared, we "block" requests to /notifications
    self.mockTransportSession.responseGeneratorBlock = ^ZMTransportResponse *(ZMTransportRequest *request) {
        if ([request.path containsString:@"notifications"]) {
            return [ZMTransportResponse responseWithPayload:@{@"notifications" : @[]} HTTPStatus:404 transportSessionError:nil];
        }
        return nil;
    };
    
    [self.mockTransportSession performRemoteChanges:^(id<MockTransportSessionObjectCreation> session __unused) {
        [session simulatePushChannelClosed];
        changes(session);
    }];
    [self.mockTransportSession performRemoteChanges:^(id<MockTransportSessionObjectCreation> session __unused) {
        [session clearNotifications];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    self.mockTransportSession.responseGeneratorBlock = nil;
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatPotentialGapSystemMessageContainsAddedAndRemovedUsers
{
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    WaitForEverythingToBeDone();
    
    [self.userSession performChanges:^{
        [self.groupConversation removeUsersByUser:self.user2 removedUser:self.user3];
    }];
    WaitForAllGroupsToBeEmpty(0.5);

    NSUUID *firstMessageNonce = NSUUID.createUUID;
    [self.mockTransportSession performRemoteChanges:^(id<MockTransportSessionObjectCreation> session __unused) {
        ZMGenericMessage *message = [ZMGenericMessage messageWithText:@"Message Text" nonce:firstMessageNonce.transportString expiresAfter:nil];
        [self.groupConversation encryptAndInsertDataFromClient:self.user1.clients.anyObject toClient:self.selfUser.clients.anyObject data:message.data];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // when
    [self performRemoteChangesNotInNotificationStream:^(id<MockTransportSessionObjectCreation> session __unused) {
        [self.groupConversation removeUsersByUser:self.user2 removedUser:self.user1];
        [self.groupConversation addUsersByUser:self.user2 addedUsers:@[self.user4]];
    }];
    
    ZMConversation *conversation = [self conversationForMockConversation:self.groupConversation];
    ZMSystemMessage *systemMessage = [conversation.messages lastObject];
    
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
    self.registeredOnThisDevice = YES;
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    WaitForEverythingToBeDone();
    ZMConversation *conversation = [self conversationForMockConversation:self.groupConversation];
    NSUInteger initialMessageCount = conversation.messages.count;
    
    NSUUID *firstMessageNonce = NSUUID.createUUID;
    [self.mockTransportSession performRemoteChanges:^(id<MockTransportSessionObjectCreation> session __unused) {
        ZMGenericMessage *message = [ZMGenericMessage messageWithText:@"Message Text" nonce:firstMessageNonce.transportString expiresAfter:nil];
        [self.groupConversation encryptAndInsertDataFromClient:self.user1.clients.anyObject toClient:self.selfUser.clients.anyObject data:message.data];
    }];
    
    WaitForAllGroupsToBeEmpty(0.5);
    XCTAssertEqual(conversation.messages.count - initialMessageCount, 1lu);
    
    // when
    [self performRemoteChangesNotInNotificationStream:^(id<MockTransportSessionObjectCreation> session __unused) {
        [self.groupConversation removeUsersByUser:self.user2 removedUser:self.user1];
        [self.groupConversation addUsersByUser:self.user2 addedUsers:@[self.user4]];
    }];
    
    conversation = [self conversationForMockConversation:self.groupConversation];
    NSOrderedSet<ZMMessage *> *allMessages = conversation.messages;
    ZMSystemMessage *systemMessage = (ZMSystemMessage *)allMessages.lastObject;
    
    // then
    XCTAssertEqual(conversation.messages.count - initialMessageCount, 2lu);
    XCTAssertEqual(systemMessage.users.count, 4lu);
    XCTAssertFalse(systemMessage.needsUpdatingUsers);
    
    // when
    [self performRemoteChangesNotInNotificationStream:^(id<MockTransportSessionObjectCreation> session __unused) {
        [self.groupConversation removeUsersByUser:self.user2 removedUser:self.user3];
        [self.groupConversation addUsersByUser:self.user2 addedUsers:@[self.user1, self.user5]];
    }];
    
    conversation = [self conversationForMockConversation:self.groupConversation];
    ZMSystemMessage *secondSystemMessage = (ZMSystemMessage *)conversation.messages.lastObject;
    
    NSSet <ZMUser *>*addedUsers = [NSSet setWithObjects:[self userForMockUser:self.user4], [self userForMockUser:self.user5], nil];
    NSSet <ZMUser *>*initialUsers = [NSSet setWithObjects:[self userForMockUser:self.selfUser],
                                     [self userForMockUser:self.user3],
                                     [self userForMockUser:self.user2],
                                     [self userForMockUser:self.user1], nil];
    ZMUser *removedUser = [self userForMockUser:self.user3];
    
    // then
    XCTAssertEqual(conversation.messages.count - initialMessageCount, 2lu);
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
    self.registeredOnThisDevice = YES;
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    WaitForEverythingToBeDone();
    ZMConversation *conversation = [self conversationForMockConversation:self.groupConversation];
    NSUInteger initialMessageCount = conversation.messages.count;
    
    NSUUID *firstMessageNonce = NSUUID.createUUID;
    [self.mockTransportSession performRemoteChanges:^(id<MockTransportSessionObjectCreation> session __unused) {
        ZMGenericMessage *message = [ZMGenericMessage messageWithText:@"Hello" nonce:firstMessageNonce.transportString expiresAfter:nil];
        [self.groupConversation encryptAndInsertDataFromClient:self.user1.clients.anyObject toClient:self.selfUser.clients.anyObject data:message.data];
    }];
    
    WaitForAllGroupsToBeEmpty(0.5);
    XCTAssertEqual(conversation.messages.count - initialMessageCount, 1lu);
    
    // when
    // add new user to conversation
    __block MockUser *newMockUser;
    [self performRemoteChangesNotInNotificationStream:^(id<MockTransportSessionObjectCreation> session __unused) {
        newMockUser = [session insertUserWithName:@"Bruno"];
        [self storeRemoteIDForObject:newMockUser];
        [self.groupConversation addUsersByUser:self.user2 addedUsers:@[newMockUser]];
    }];
    
    conversation = [self conversationForMockConversation:self.groupConversation];
    NSOrderedSet<ZMMessage *> *allMessages = conversation.messages;
    ZMSystemMessage *systemMessage = (ZMSystemMessage *)allMessages.lastObject;
    
    ZMUser *addedUser = systemMessage.addedUsers.anyObject;
    
    // then after fetching it should contain the full users
    XCTAssertEqual(conversation.messages.count - initialMessageCount, 2lu);
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
    
    
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    WaitForEverythingToBeDone();
    
    ZMConversation *groupConversation = [self conversationForMockConversation:self.groupConversation];
    XCTAssertNotNil(groupConversation);
    XCTAssertNotEqual(groupConversation.displayName, newName1);
    
    // make a copy of the current ones (since it's a relationship, it seems that [set copy] just doesn't work)
    NSOrderedSet *previousMessages = [groupConversation.messages mutableCopy];
    
    // when
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        [self.groupConversation changeNameByUser:session.selfUser name:newName1];
    }];
    WaitForEverythingToBeDone();
    
    
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        [self.groupConversation changeNameByUser:session.selfUser name:newName2];
    }];
    WaitForEverythingToBeDone();
    
    // then
    NSMutableOrderedSet *extraMessages = [groupConversation.messages mutableCopy];
    [extraMessages minusOrderedSet:previousMessages];
    
    XCTAssertEqual(extraMessages.count, 2u);
    XCTAssertEqual([extraMessages[0] systemMessageType], ZMSystemMessageTypeConversationNameChanged);
    XCTAssertEqual([extraMessages[1] systemMessageType], ZMSystemMessageTypeConversationNameChanged);
    
    XCTAssertEqualObjects([(ZMTextMessage *)extraMessages[0] text],  newName1);
    XCTAssertEqualObjects([(ZMTextMessage *)extraMessages[1] text],  newName2);
}


- (void)testThatItExpiresAMessage
{
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    WaitForEverythingToBeDone();
    
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
    WaitForEverythingToBeDone();
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
    
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    WaitForEverythingToBeDone();
    
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
    
    WaitForEverythingToBeDone();
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
    WaitForEverythingToBeDone();
    XCTAssertFalse(message.isExpired);
    XCTAssertNotEqual(message.deliveryState, ZMDeliveryStateFailedToSend);
    
    
    // finally
    [ZMMessage resetDefaultExpirationTime];
}


- (void)testThatWhenResendingAMessageChangesTheStateToPending
{
    
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    WaitForEverythingToBeDone();
    
    ZMConversation *groupConversation = [self conversationForMockConversation:self.groupConversation];
    XCTAssertNotNil(groupConversation);
    
    
    self.mockTransportSession.doNotRespondToRequests = YES;
    [ZMMessage setDefaultExpirationTime:0.1]; //We don't want to wait 60 seconds
    __block ZMMessage *message;
    [self.userSession performChanges:^{
        message = (id)[groupConversation appendMessageWithText:@"lalala"];
    }];
    XCTAssertTrue([groupConversation.managedObjectContext saveOrRollback]);
    
    WaitForEverythingToBeDone();
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
    WaitForEverythingToBeDoneWithTimeout(0.5);
    [ZMMessage resetDefaultExpirationTime];
}



- (void)testThatIfWeExpireAMessageButStillGetAResponseThatWeUseIt
{
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    WaitForEverythingToBeDone();
    
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
    WaitForEverythingToBeDone();
    
    
    //then
    XCTAssertEqual(message.deliveryState, ZMDeliveryStateSent);
    
    // finally
    [ZMMessage resetDefaultExpirationTime];
}


- (void)testThatWhenResendingAMessageWeOnlyGetANotificationForStateChangingToPending
{
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    WaitForEverythingToBeDone();
    
    ZMConversation *groupConversation = [self conversationForMockConversation:self.groupConversation];
    XCTAssertNotNil(groupConversation);
    
    
    self.mockTransportSession.doNotRespondToRequests = YES;
    [ZMMessage setDefaultExpirationTime:0.1]; //We don't want to wait 60 seconds
    
    __block ZMMessage *message;
    [self.userSession performChanges:^{
        message = (id)[groupConversation appendMessageWithText:@"lalala"];
    }];
    XCTAssertTrue([groupConversation.managedObjectContext saveOrRollback]);
    
    WaitForEverythingToBeDone();
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
    WaitForEverythingToBeDoneWithTimeout(0.5);
    [ZMMessage resetDefaultExpirationTime];
    [observer tearDown];
}


- (void)testThatItResendsMessages
{
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    WaitForEverythingToBeDone();
    
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
    
    WaitForEverythingToBeDone();
    
    [self.userSession performChanges:^{
        [message resend];
    }];
    
    WaitForEverythingToBeDone();
    
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
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    WaitForEverythingToBeDone();
    
    ZMConversation *groupConversation = [self conversationForMockConversation:self.groupConversation];
    XCTAssertNotNil(groupConversation);
    
    __block ZMMessage *message;
    __block NSUUID *messageNonce;
    [self.userSession performChanges:^{
        message = (id)[groupConversation appendMessageWithText:@"lalala"];
        messageNonce = message.nonce;
    }];
    XCTAssertTrue([groupConversation.managedObjectContext saveOrRollback]);
    WaitForEverythingToBeDone();
    
    //when
    [self.userSession performChanges:^{
        [ZMMessage hideMessage:message];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    message = [ZMMessage fetchMessageWithNonce:messageNonce forConversation:groupConversation inManagedObjectContext:self.uiMOC];
    XCTAssertNil(message);
}


- (void)testThatItSyncsWhenAMessageHideIsRemotelyAppended;
{
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    WaitForEverythingToBeDone();
    
    ZMConversation *groupConversation = [self conversationForMockConversation:self.groupConversation];
    XCTAssertNotNil(groupConversation);
    
    __block ZMMessage *message;
    __block NSUUID *messageNonce;
    [self.userSession performChanges:^{
        message = (id)[groupConversation appendMessageWithText:@"lalala"];
        messageNonce = message.nonce;
    }];
    XCTAssertTrue([groupConversation.managedObjectContext saveOrRollback]);
    WaitForEverythingToBeDone();
    
    //when
    [self remotelyAppendSelfConversationWithZMMessageHideForMessageID:messageNonce.transportString conversationID:groupConversation.remoteIdentifier.transportString];
    WaitForAllGroupsToBeEmpty(0.5);
    
    message = [ZMMessage fetchMessageWithNonce:messageNonce forConversation:groupConversation inManagedObjectContext:self.uiMOC];
    XCTAssertNil(message);
}

@end

