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
#import "NotificationObservers.h"
#import <WireSyncEngine/WireSyncEngine-Swift.h>
#import "WireSyncEngine_iOS_Tests-Swift.h"

@import WireDataModel;
@import WireUtilities;
@import WireRequestStrategy;

@interface ConversationTestsOTR : ConversationTestsBase
@end

@implementation ConversationTestsOTR

- (void)testThatItAppendsOTRMessages
{    
    NSString *expectedText1 = @"The sky above the port was the color of ";
    NSString *expectedText2 = @"television, tuned to a dead channel.";
    
    NSUUID *nonce1 = [NSUUID createUUID];
    NSUUID *nonce2 = [NSUUID createUUID];
    
    ZMGenericMessage *genericMessage1 = [ZMGenericMessage messageWithContent:[ZMText textWith:expectedText1 mentions:@[] linkPreviews:@[]] nonce:nonce1];
    ZMGenericMessage *genericMessage2 = [ZMGenericMessage messageWithContent:[ZMText textWith:expectedText2 mentions:@[] linkPreviews:@[]] nonce:nonce2];
    
    [self testThatItAppendsMessageToConversation:self.groupConversation withBlock:^NSArray *(MockTransportSession<MockTransportSessionObjectCreation> * __unused session){
        
        MockUserClient *selfClient = self.selfUser.clients.anyObject;

        [self.groupConversation encryptAndInsertDataFromClient:self.user2.clients.anyObject toClient:selfClient data:genericMessage1.data];
        [self.groupConversation encryptAndInsertDataFromClient:self.user3.clients.anyObject toClient:selfClient data:genericMessage2.data];
        
        return @[nonce1, nonce2];
    } verify:^(ZMConversation *conversation) {
        //check that we successfully decrypted messages
        XCTAssert(conversation.messages.count > 0);
        if (conversation.messages.count < 2) {
            XCTFail(@"message count is too low");
        } else {
            ZMClientMessage *msg1 = conversation.messages[conversation.messages.count - 2];
            XCTAssertEqualObjects(msg1.nonce, nonce1);
            XCTAssertEqualObjects(msg1.genericMessage.text.content, expectedText1);
            
            ZMClientMessage *msg2 = conversation.messages[conversation.messages.count - 1];
            XCTAssertEqualObjects(msg2.nonce, nonce2);
            XCTAssertEqualObjects(msg2.genericMessage.text.content, expectedText2);
        }
        
    }];
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatItDeliversOTRMessageIfNoMissingClients
{
    //given
    XCTAssertTrue([self login]);
    
    NSString *messageText = @"Hey!";
    __block ZMClientMessage *message;
    ZMConversation *conversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    
    //this fetch the missing client
    [self.userSession performChanges:^{
        message = (id)[conversation appendText:@"Bonsoir, je voudrais un croissant" mentions:@[] fetchLinkPreview:YES nonce:[NSUUID createUUID]];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    
    // when
    [self.userSession performChanges:^{
        message = (id)[conversation appendText:messageText mentions:@[] fetchLinkPreview:YES nonce:[NSUUID createUUID]];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    MockEvent *lastEvent = self.selfToUser1Conversation.events.lastObject;
    XCTAssertEqual(lastEvent.eventType, ZMUpdateEventTypeConversationOtrMessageAdd);
    XCTAssertEqual(message.deliveryState, ZMDeliveryStateSent);
    
    ZMGenericMessage *genericMessage = (ZMGenericMessage *)[[[[ZMGenericMessageBuilder alloc] init] mergeFromData:lastEvent.decryptedOTRData] build];
    XCTAssertEqualObjects(genericMessage.text.content, messageText);
}

- (void)testThatItDeliversOTRAssetIfNoMissingClients
{
    __block ZMAssetClientMessage *message;
    
    XCTAssertTrue([self login]);
    
    ZMConversation *conversation = [self conversationForMockConversation:self.selfToUser1Conversation];

    // when
    [self.userSession performChanges:^{
        message = (id)[conversation appendImageFromData:[self verySmallJPEGData] nonce:[NSUUID createUUID]];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    MockPushEvent *lastEvent = self.mockTransportSession.updateEvents.lastObject;
    
    
    NSDictionary *lastEventPayload = lastEvent.payload.asDictionary;
    ZMUpdateEventType lastEventType = [MockEvent typeFromString:lastEventPayload[@"type"]];
    
    XCTAssertEqual(lastEventType, ZMUpdateEventTypeConversationOtrMessageAdd);
    XCTAssertEqual(message.deliveryState, ZMDeliveryStateSent);
    
    ZMUser *selfUser = [ZMUser selfUserInContext:self.userSession.syncManagedObjectContext];
    UserClient *selfClient = selfUser.selfClient;
    XCTAssertEqual(selfClient.missingClients.count, 0u);
    XCTAssertFalse([message hasLocalModificationsForKey:@"uploadState"]);
    XCTAssertEqual(message.uploadState, AssetUploadStateDone);
}

- (void)testThatItAsksForMissingClientsKeysWhenDeliveringOtrMessage
{
    NSString *messageText = @"Hey!";

    __block BOOL askedForPreKeys = NO;
    [self.mockTransportSession setResponseGeneratorBlock:^ ZMTransportResponse *(ZMTransportRequest *__unused request) {
        if ([request.path.pathComponents containsObject:@"prekeys"]) {
            askedForPreKeys = YES;
            return ResponseGenerator.ResponseNotCompleted;
        }
        return nil;
    }];

    XCTAssertTrue([self login]);
    
    ZMConversation *conversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    
    __block ZMMessage *message;
    // when
    [self.userSession performChanges:^{
        message = (id)[conversation appendText:messageText mentions:@[] fetchLinkPreview:YES nonce:[NSUUID createUUID]];
    }];
    
    WaitForAllGroupsToBeEmpty(0.5);
    
    MockPushEvent *lastEvent = self.mockTransportSession.updateEvents.lastObject;
    NSDictionary *lastEventPayload = lastEvent.payload.asDictionary;
    ZMUpdateEventType lastEventType = [MockEvent typeFromString:lastEventPayload[@"type"]];
    
    XCTAssertNotEqual(lastEventType, ZMUpdateEventTypeConversationOtrMessageAdd);
    XCTAssertEqual(message.deliveryState, ZMDeliveryStatePending);
    
    ZMUser *selfUser = [ZMUser selfUserInContext:self.userSession.syncManagedObjectContext];
    UserClient *selfClient = selfUser.selfClient;
    
    XCTAssertTrue(selfClient.missingClients.count > 0);
    XCTAssertTrue(askedForPreKeys);
}

- (void)testThatItSendsFailedOTRMessageAfterMissingClientsAreFetchedButSessionIsNotCreated
{
    // GIVEN
    XCTAssertTrue([self login]);
    
    //register other users clients
    ZMConversation *conversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    
    ZM_WEAK(self);
    [self.mockTransportSession setResponseGeneratorBlock:^ ZMTransportResponse *(ZMTransportRequest *__unused request) {
        ZM_STRONG(self);
        if ([request.path.pathComponents containsObject:@"prekeys"]) {
            return [ZMTransportResponse responseWithPayload:@{
                                                              self.user1.identifier: @{
                                                                      [(MockUserClient *)self.user1.clients.anyObject identifier]: @{
                                                                              @"id": @0,
                                                                              @"key": [@"invalid key" dataUsingEncoding:NSUTF8StringEncoding].base64String
                                                                              }
                                                                      }
                                                              } HTTPStatus:201 transportSessionError:nil];
        }
        return nil;
    }];
    
    // WHEN
    __block id <ZMConversationMessage> message;
    [self.mockTransportSession resetReceivedRequests];

    [self performIgnoringZMLogError:^{
        [self.userSession performChanges:^{
            message = [conversation appendMessageWithText:@"Hello World"];
        }];
        WaitForAllGroupsToBeEmpty(0.5);

    }];

    // THEN
    NSString *expectedPath = [NSString stringWithFormat:@"/conversations/%@/otr", conversation.remoteIdentifier.transportString];
    
    // then we expect it to receive a bomb message
    // when resending after fetching the (faulty) prekeys
    NSUInteger messagesReceived = 0;
    
    for (ZMTransportRequest *req in self.mockTransportSession.receivedRequests) {
        
        if (! [req.path hasPrefix:expectedPath]) {
            continue;
        }
        
        ZMNewOtrMessage *otrMessage = [ZMNewOtrMessage parseFromData:req.binaryData];
        XCTAssertNotNil(otrMessage);
        
        NSArray <ZMUserEntry *>* userEntries = otrMessage.recipients;
        ZMClientEntry *clientEntry = [userEntries.firstObject.clients firstObject];
        
        if ([clientEntry.text isEqualToData:[@"💣" dataUsingEncoding:NSUTF8StringEncoding]]) {
            messagesReceived++;
        }
    }
    
    XCTAssertEqual(messagesReceived, 1lu);
    XCTAssertEqual(message.deliveryState, ZMDeliveryStateSent);
}

- (void)testThatItDeliversOTRMessageAfterMissingClientsAreFetched
{
    NSString *messageText = @"Hey!";
    __block ZMClientMessage *message;
    
    XCTAssertTrue([self login]);
    
    ZMConversation *conversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    
    // when
    [self.userSession performChanges:^{
        message = (id)[conversation appendText:messageText mentions:@[] fetchLinkPreview:YES nonce:[NSUUID createUUID]];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    MockEvent *lastEvent = self.selfToUser1Conversation.events.lastObject;
    XCTAssertEqual(lastEvent.eventType, ZMUpdateEventTypeConversationOtrMessageAdd);
    XCTAssertEqual(message.deliveryState, ZMDeliveryStateSent);
    
    ZMGenericMessage *genericMessage = (ZMGenericMessage *)[[[[ZMGenericMessageBuilder alloc] init] mergeFromData:lastEvent.decryptedOTRData] build];
    XCTAssertEqualObjects(genericMessage.text.content, messageText);
}

- (void)testThatItDeliversOTRAssetAfterMissingClientsAreFetched
{
    // given
    XCTAssertTrue([self login]);
    
    ZMConversation *conversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    __block ZMAssetClientMessage *message;

    // when
    [self.userSession performChanges:^{
        message = (id)[conversation appendImageFromData:[self verySmallJPEGData] nonce:[NSUUID createUUID]];
    }];
    
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    MockPushEvent *lastEvent = self.mockTransportSession.updateEvents.lastObject;
    //check that recipient can read this message
    NSDictionary *lastEventPayload = lastEvent.payload.asDictionary;
    ZMUpdateEventType lastEventType = [MockEvent typeFromString:lastEventPayload[@"type"]];
    
    XCTAssertEqual(lastEventType, ZMUpdateEventTypeConversationOtrMessageAdd);
    XCTAssertEqual(message.deliveryState, ZMDeliveryStateSent);
    
    ZMUser *selfUser = [ZMUser selfUserInContext:self.userSession.syncManagedObjectContext];
    UserClient *selfClient = selfUser.selfClient;
    XCTAssertEqual(selfClient.missingClients.count, 0u);
}


- (void)testThatItResetsKeysIfClientUnknown
{
    // given
    XCTAssertTrue([self login]);
    
    ZM_WEAK(self);
    self.mockTransportSession.responseGeneratorBlock = ^ ZMTransportResponse *(ZMTransportRequest *__unused request) {
        ZM_STRONG(self);
        if ([request.path.pathComponents containsObject:@"assets"]) {
            self.mockTransportSession.responseGeneratorBlock = nil;
            return [ZMTransportResponse responseWithPayload:@{ @"label" : @"unknown-client"} HTTPStatus:403 transportSessionError:nil];
        }
        return nil;
    };
    
    ZMConversation *conversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    
    __block ZMAssetClientMessage *message;
    // when
    [self.userSession performChanges:^{
        message = (id)[conversation appendImageFromData:[self verySmallJPEGData] nonce:[NSUUID createUUID]];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    MockPushEvent *lastEvent = self.mockTransportSession.updateEvents.lastObject;
    NSDictionary *lastEventPayload = lastEvent.payload.asDictionary;
    ZMUpdateEventType lastEventType = [MockEvent typeFromString:lastEventPayload[@"type"]];
    
    XCTAssertNotEqual(lastEventType, ZMUpdateEventTypeConversationOtrMessageAdd);
    XCTAssertEqual(message.deliveryState, ZMDeliveryStatePending);
    
    XCTAssertFalse([message hasLocalModificationsForKey:@"uploadState"]);
    XCTAssertEqual(message.uploadState, AssetUploadStateUploadingFailed);
    
}

- (void)testThatItNotifiesIfThereAreNewRemoteClients
{
    // GIVEN
    XCTAssertTrue([self login]);
    
    ZMUser *selfUser = [ZMUser selfUserInContext:self.userSession.managedObjectContext];
    UserChangeObserver *observer = [[UserChangeObserver alloc] initWithUser:selfUser];
    ZMConversation *conversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    
    [self.mockTransportSession performRemoteChanges:^(id<MockTransportSessionObjectCreation> _Nonnull session) {
        [session registerClientForUser:self.selfUser label:@"iPad 12" type:@"permanent"];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // WHEN
    [self.userSession performChanges:^{
        [conversation appendImageFromData:[self verySmallJPEGData] nonce:[NSUUID createUUID]];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // THEN
    XCTAssertTrue([observer.notifications.firstObject clientsChanged]);
}

- (void)testThatItDeliversTwoOTRAssetMessages
{
    // given
    XCTAssertTrue([self login]);
    
    //register other users clients
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        for(int i = 0; i < 7; ++i) {
            MockUser *user = [session insertUserWithName:[NSString stringWithFormat:@"TestUser %d", i+1]];
            user.email = [NSString stringWithFormat:@"user%d@example.com", i+1];
            user.accentID = 4;
            [self.groupConversation addUsersByUser:user addedUsers:@[user]];
        }
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    ZMConversation *conversation = [self conversationForMockConversation:self.groupConversation];
    
    __block ZMMessage *imageMessage1;
    // when
    [self.userSession performChanges:^{
        imageMessage1 = (id)[conversation appendImageFromData:[self verySmallJPEGData] nonce:[NSUUID createUUID]];
    }];
    
    __block ZMMessage *textMessage;
    [self.userSession performChanges:^{
        textMessage = (id)[conversation appendText:@"foobar" mentions:@[] fetchLinkPreview:YES nonce:[NSUUID createUUID]];
    }];
    
    __block ZMMessage *imageMessage2;
    // and when
    [self.userSession performChanges:^{
        imageMessage2 = (id)[conversation appendImageFromData:[self verySmallJPEGData] nonce:[NSUUID createUUID]];
        
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    XCTAssertEqual(imageMessage1.deliveryState, ZMDeliveryStateSent);
    XCTAssertEqual(textMessage.deliveryState, ZMDeliveryStateSent);
    XCTAssertEqual(imageMessage2.deliveryState, ZMDeliveryStateSent);
}

- (void)testThatItSendsFailedSessionOTRAssetMessageAfterMissingClientsAreFetchedButSessionIsNotCreated
{
    // GIVEN
    XCTAssertTrue([self login]);
    
    ZMConversation *conversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    
    __block ZMAssetClientMessage *message;
    
    ZM_WEAK(self);
    [self.mockTransportSession setResponseGeneratorBlock:^ ZMTransportResponse *(ZMTransportRequest *__unused request) {
        ZM_STRONG(self);
        if ([request.path.pathComponents containsObject:@"prekeys"]) {
            return [ZMTransportResponse responseWithPayload:@{
                                                              self.user1.identifier: @{
                                                                      [(MockUserClient *)self.user1.clients.anyObject identifier]: @{
                                                                              @"id": @0,
                                                                              @"key": [@"invalid key" dataUsingEncoding:NSUTF8StringEncoding].base64String
                                                                              }
                                                                      }
                                                              } HTTPStatus:201 transportSessionError:nil];
        }
        return nil;
    }];

    // WHEN
    [self.mockTransportSession resetReceivedRequests];
    [self performIgnoringZMLogError:^{
        [self.userSession performChanges:^{
            message = (id)[conversation appendImageFromData:[self verySmallJPEGData] nonce:[NSUUID createUUID]];
        }];
        WaitForAllGroupsToBeEmpty(0.5);
    }];

    // THEN
    NSString *expectedPath = [NSString stringWithFormat:@"/conversations/%@/otr/messages", conversation.remoteIdentifier.transportString];
    
    // then we expect it to receive a bomb medium
    // when resending after fetching the (faulty) prekeys
    NSUInteger bombsReceived = 0;
    
    for (ZMTransportRequest *req in self.mockTransportSession.receivedRequests) {
        if (! [req.path hasPrefix:expectedPath] || nil == req.binaryData) {
            continue;
        }
        
        ZMOtrAssetMeta *otrMessage = [ZMOtrAssetMeta parseFromData:req.binaryData];
        XCTAssertNotNil(otrMessage);
        
        NSArray <ZMUserEntry *>* userEntries = otrMessage.recipients;
        ZMClientEntry *clientEntry = [userEntries.firstObject.clients firstObject];
        
        if ([clientEntry.text isEqualToData:[@"💣" dataUsingEncoding:NSUTF8StringEncoding]]) {
            bombsReceived++;
        }
    }

    XCTAssertEqual(bombsReceived, 1lu);
    XCTAssertEqual(message.deliveryState, ZMDeliveryStateSent);
}

- (void)testThatItOTRMessagesCanExpire
{
    // given
    XCTAssertTrue([self login]);
    
    NSTimeInterval defaultExpirationTime = [ZMMessage defaultExpirationTime];
    [ZMMessage setDefaultExpirationTime:0.3];

    self.mockTransportSession.doNotRespondToRequests = YES;
    
    ZMConversation *conversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    
    __block ZMClientMessage *message;
    
    // when
    [self.userSession performChanges:^{
        message = (id)[conversation appendText:@"I can't hear you, Claudy" mentions:@[] fetchLinkPreview:YES nonce:[NSUUID createUUID]];
    }];
    
    XCTAssertTrue([self waitOnMainLoopUntilBlock:^BOOL{
        return message.isExpired;
    } timeout:0.5]);
    
    // then
    XCTAssertEqual(message.deliveryState, ZMDeliveryStateFailedToSend);
    XCTAssertEqual(conversation.conversationListIndicator, ZMConversationListIndicatorExpiredMessage);

    [ZMMessage setDefaultExpirationTime:defaultExpirationTime];

}

- (void)testThatItOTRAssetCantExpire
{
    // given
    XCTAssertTrue([self login]);
    
    NSTimeInterval defaultExpirationTime = [ZMMessage defaultExpirationTime];
    [ZMMessage setDefaultExpirationTime:0.3];
    
    self.mockTransportSession.doNotRespondToRequests = YES;
    
    ZMConversation *conversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    
    __block ZMAssetClientMessage *message;
    
    // when
    [self.userSession performChanges:^{
        message = (id)[conversation appendImageFromData:[self verySmallJPEGData] nonce:[NSUUID createUUID]];
    }];
    
    [self spinMainQueueWithTimeout:0.5];
    
    // then
    XCTAssertFalse(message.isExpired);
    XCTAssertEqual(message.deliveryState, ZMDeliveryStatePending);

    [ZMMessage setDefaultExpirationTime:defaultExpirationTime];
    
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatItOTRMessagesCanBeResentAndItIsMovedToTheEndOfTheConversation
{
    // given
    XCTAssertTrue([self login]);
    
    NSTimeInterval defaultExpirationTime = [ZMMessage defaultExpirationTime];
    [ZMMessage setDefaultExpirationTime:0.3];

    self.mockTransportSession.doNotRespondToRequests = YES;
    
    ZMConversation *conversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    
    __block ZMClientMessage *message;
    
    // fail to send
    [self.userSession performChanges:^{
        message = (id)[conversation appendText:@"Where's everyone?" mentions:@[] fetchLinkPreview:YES nonce:[NSUUID createUUID]];
    }];
    
    XCTAssertTrue([self waitOnMainLoopUntilBlock:^BOOL{
        return message.isExpired;
    } timeout:0.5]);
    
    XCTAssertEqual(message.deliveryState, ZMDeliveryStateFailedToSend);
    [ZMMessage setDefaultExpirationTime:defaultExpirationTime];
    self.mockTransportSession.doNotRespondToRequests = NO;
    [NSThread sleepForTimeInterval:0.1]; // advance timestamp
    
    // when receiving a new message
    NSString *otherUserMessageText = @"Are you still there?";
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> __unused *session) {
        ZMGenericMessage *genericMessage = [ZMGenericMessage messageWithContent:[ZMText textWith:otherUserMessageText mentions:@[] linkPreviews:@[]] nonce:NSUUID.createUUID];
        [self.selfToUser1Conversation encryptAndInsertDataFromClient:self.user1.clients.anyObject toClient:self.selfUser.clients.anyObject data:genericMessage.data];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    id<ZMConversationMessage> lastMessage = conversation.messages.lastObject;
    XCTAssertEqualObjects(lastMessage.textMessageData.messageText, otherUserMessageText);
    
    // and when resending
    [self.userSession performChanges:^{
        [message resend];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(conversation.messages.lastObject, message);
    XCTAssertEqual(message.deliveryState, ZMDeliveryStateSent);
}

- (void)testThatItSendsANotificationWhenRecievingAOtrMessageThroughThePushChannel
{
    XCTAssertTrue([self login]);
    
    NSString *expectedText = @"The sky above the port was the color of ";
    ZMGenericMessage *message = [ZMGenericMessage messageWithContent:[ZMText textWith:expectedText mentions:@[] linkPreviews:@[]]  nonce:NSUUID.createUUID];
    

    MockConversation *mockConversation = self.groupConversation;
    ZMConversation *conversation = [self conversationForMockConversation:mockConversation];
    NSUInteger initialMessagesCount = conversation.messages.count;
    
    // Make sure this relationship is not a fault:
    for (id obj in conversation.messages) {
        (void) obj;
    }
    
    //    ZMUser *selfUser = [ZMUser selfUserInContext:self.syncMOC];
    MockUserClient *selfClient = [self.selfUser.clients anyObject];
    MockUserClient *senderClient = [self.user1.clients anyObject];
    
    // when
    ConversationChangeObserver *observer = [[ConversationChangeObserver alloc] initWithConversation:conversation];
    [observer clearNotifications];
    
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *__unused session) {
        [mockConversation encryptAndInsertDataFromClient:senderClient toClient:selfClient data:message.data];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(observer.notifications.count, 1u);
    
    ConversationChangeInfo *note = observer.notifications.firstObject;
    XCTAssertNotNil(note);
    XCTAssertTrue(note.messagesChanged);
    XCTAssertFalse(note.participantsChanged);
    XCTAssertFalse(note.nameChanged);
    XCTAssertTrue(note.lastModifiedDateChanged);
    XCTAssertFalse(note.connectionStateChanged);
    
    ZMClientMessage *msg = conversation.messages[initialMessagesCount];
    XCTAssertEqualObjects(msg.genericMessage.text.content, expectedText);
}

- (ZMGenericMessage *)remotelyInsertOTRImageIntoConversation:(MockConversation *)mockConversation imageFormat:(ZMImageFormat)format
{
    NSData *encryptedImageData;
    NSData *imageData = [self verySmallJPEGData];
    ZMGenericMessage *message = [self otrAssetGenericMessage:format imageData:imageData encryptedData:&encryptedImageData];
    
    MockUserClient *selfClient = [self.selfUser.clients anyObject];
    MockUserClient *senderClient = [self.user1.clients anyObject];
    
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        NSData *messageData = [MockUserClient encryptedWithData:message.data from:senderClient to:selfClient];
        NSUUID *assetId = [NSUUID createUUID];
        [session createAssetWithData:encryptedImageData identifier:assetId.transportString contentType:@"" forConversation:mockConversation.identifier];
        [mockConversation insertOTRAssetFromClient:senderClient toClient:selfClient metaData:messageData imageData:encryptedImageData assetId:assetId isInline:format == ZMImageFormatPreview];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    return message;
}

- (void)testThatItSendsANotificationWhenRecievingAOtrAssetMessageThroughThePushChannel:(ZMImageFormat)format
{
    XCTAssertTrue([self login]);
    
    MockConversation *mockConversation = self.groupConversation;
    ZMConversation *conversation = [self conversationForMockConversation:mockConversation];
    
    // Make sure this relationship is not a fault:
    for (id obj in conversation.messages) {
        (void) obj;
    }
    NSUInteger initialMessagesCount = conversation.messages.count;
    
    // when
    ConversationChangeObserver *observer = [[ConversationChangeObserver alloc] initWithConversation:conversation];
    [observer clearNotifications];
    ZMGenericMessage *assetMessage = [self remotelyInsertOTRImageIntoConversation:mockConversation imageFormat:format];
    
    // then
    XCTAssertEqual(observer.notifications.count, 1u);
    
    ConversationChangeInfo *note = observer.notifications.firstObject;
    XCTAssertNotNil(note);
    XCTAssertTrue(note.messagesChanged);
    XCTAssertFalse(note.participantsChanged);
    XCTAssertFalse(note.nameChanged);
    XCTAssertTrue(note.lastModifiedDateChanged);
    XCTAssertFalse(note.connectionStateChanged);
    
    ZMAssetClientMessage *msg = conversation.messages[initialMessagesCount];
    XCTAssertEqualObjects([msg.imageAssetStorage genericMessageFor:format], assetMessage);
}

- (void)testThatItSendsANotificationWhenRecievingAOtrMediumAssetMessageThroughThePushChannel
{
    [self testThatItSendsANotificationWhenRecievingAOtrAssetMessageThroughThePushChannel:ZMImageFormatMedium];
}

- (void)testThatItSendsANotificationWhenRecievingAOtrPreviewAssetMessageThroughThePushChannel
{
    [self testThatItSendsANotificationWhenRecievingAOtrAssetMessageThroughThePushChannel:ZMImageFormatPreview];
}

- (ZMGenericMessage *)otrAssetGenericMessage:(ZMImageFormat)format imageData:(NSData *)imageData encryptedData:(NSData **)encryptedData
{
    ZMIImageProperties *properties = [ZMIImageProperties imagePropertiesWithSize:[ZMImagePreprocessor sizeOfPrerotatedImageWithData:imageData] length:imageData.length mimeType:@"image/jpeg"];
    
    NSData *otrKey = [NSData randomEncryptionKey];
    *encryptedData = [imageData zmEncryptPrefixingPlainTextIVWithKey:otrKey];
    
    NSData *sha = [*encryptedData zmSHA256Digest];
    
    ZMImageAssetEncryptionKeys *keys = [[ZMImageAssetEncryptionKeys alloc] initWithOtrKey:otrKey sha256:sha];
    ZMGenericMessage *message = [ZMGenericMessage messageWithContent:[ZMImageAsset imageAssetWithMediumProperties:properties processedProperties:properties encryptionKeys:keys format:format] nonce:NSUUID.createUUID];

    return message;
}

- (void)testThatItUnarchivesAnArchivedConversationWhenReceivingAnEncryptedMessage {
    // given
    XCTAssertTrue([self login]);
    
    ZMConversation *conversation = [self conversationForMockConversation:self.groupConversation];
    [self.userSession performChanges:^{
        conversation.isArchived = YES;
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    XCTAssertTrue(conversation.isArchived);
    
    // when
    ZMGenericMessage *message = [ZMGenericMessage messageWithContent:[ZMText textWith:@"Foo bar" mentions:@[] linkPreviews:@[]] nonce:NSUUID.createUUID];
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> * __unused session) {
        [self.groupConversation encryptAndInsertDataFromClient:self.user1.clients.anyObject
                                                      toClient:self.selfUser.clients.anyObject
                                                          data:message.data];
    }];

    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertFalse(conversation.isArchived);
}

- (void)testThatItCreatesAnExternalMessageIfThePayloadIsToLargeAndAddsTheGenericMessageAsDataBlob
{
    // given
    NSMutableString *text = @"Very Long Text!".mutableCopy;
    while ([text dataUsingEncoding:NSUTF8StringEncoding].length < ZMClientMessageByteSizeExternalThreshold) {
        [text appendString:text];
    }
    
    XCTAssertTrue([self login]);
    
    //register other users clients
    ZMConversation *conversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    
    __block ZMClientMessage *message;
    // when
    [self.userSession performChanges:^{
        message = (id)[conversation appendText:text mentions:@[] fetchLinkPreview:YES nonce:NSUUID.createUUID];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    MockEvent *lastEvent = self.selfToUser1Conversation.events.lastObject;
    XCTAssertEqual(lastEvent.eventType, ZMUpdateEventTypeConversationOtrMessageAdd);
    XCTAssertEqual(message.deliveryState, ZMDeliveryStateSent);
    
    ZMGenericMessage *genericMessage = (ZMGenericMessage *)[[[[ZMGenericMessageBuilder alloc] init] mergeFromData:lastEvent.decryptedOTRData] build];
    XCTAssertNotNil(genericMessage);
}

- (void)testThatMessageWindowChangesWhenOTRAssetDataIsLoaded:(ZMImageFormat)format
{
    // given
    MockConversationWindowObserver *observer = [self windowObserverAfterLogginInAndInsertingMessagesInMockConversation:self.groupConversation];
    NSOrderedSet *initialMessageSet = observer.computedMessages;

    NSData *encryptedImageData;
    NSData *imageData = [self verySmallJPEGData];
    ZMGenericMessage *message = [self otrAssetGenericMessage:format imageData:imageData encryptedData:&encryptedImageData];
    
    MockConversation *conversation = self.groupConversation;
    ZMConversation *localGroupConversation = [self conversationForMockConversation:conversation];
    
    MockUserClient *selfClient = [self.selfUser.clients anyObject];
    MockUserClient *senderClient = [self.user1.clients anyObject];
    
    // when
    __block NSData *messageData;
    [self.mockTransportSession performRemoteChanges:^(id<MockTransportSessionObjectCreation> session){
        NSUUID *assetId = [NSUUID createUUID];
        messageData = [MockUserClient encryptedWithData:message.data from:senderClient to:selfClient];
        [conversation insertOTRAssetFromClient:senderClient toClient:selfClient metaData:messageData imageData:encryptedImageData assetId:assetId isInline:format == ZMImageFormatPreview];
        
        [session createAssetWithData:encryptedImageData identifier:assetId.transportString contentType:@"" forConversation:self.groupConversation.identifier];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    [self spinMainQueueWithTimeout:0.5];
    
    ZMMessage *observedMessage = localGroupConversation.messages.lastObject;
    MessageChangeObserver *messageObserver = [[MessageChangeObserver alloc] initWithMessage:observedMessage];
    XCTAssertTrue([observedMessage isKindOfClass:ZMAssetClientMessage.class]);
    
    [observedMessage.imageMessageData requestImageDownload];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(messageObserver.notifications.count, 1lu);
    
    NSOrderedSet *currentMessageSet = observer.computedMessages;
    NSOrderedSet *windowMessageSet = observer.window.messages;
    
    XCTAssertEqualObjects(currentMessageSet, windowMessageSet);
    
    for(NSUInteger i = 0; i < observer.window.size; ++ i) {
        if(i == 0) {
            ZMAssetClientMessage *windowMessage = currentMessageSet[i];
            XCTAssertEqualObjects([windowMessage.imageAssetStorage genericMessageFor:format], message);
            NSData *recievedImageData = [self.userSession.managedObjectContext.zm_fileAssetCache assetData:windowMessage format:format encrypted:NO];
            XCTAssertEqualObjects(recievedImageData, imageData);
        }
        else {
            XCTAssertEqual(currentMessageSet[i], initialMessageSet[i-1]);
        }
    }
}

- (void)testThatMessageWindowChangesWhenOTRAssetMediumIsLoaded
{
    // given
    MockConversationWindowObserver *observer = [self windowObserverAfterLogginInAndInsertingMessagesInMockConversation:self.groupConversation];
    NSOrderedSet *initialMessageSet = observer.computedMessages;
    
    NSData *encryptedImageData;
    NSData *imageData = [self verySmallJPEGData];
    ZMGenericMessage *message = [self otrAssetGenericMessage:ZMImageFormatMedium imageData:imageData encryptedData:&encryptedImageData];
    
    MockConversation *conversation = self.groupConversation;
    ZMConversation *localGroupConversation = [self conversationForMockConversation:conversation];
    
    MockUserClient *selfClient = [self.selfUser.clients anyObject];
    MockUserClient *senderClient = [self.user1.clients anyObject];
    
    // when
    __block NSData *messageData;
    [self.mockTransportSession performRemoteChanges:^(id<MockTransportSessionObjectCreation> session){
        NSUUID *assetId = [NSUUID createUUID];
        messageData = [MockUserClient encryptedWithData:message.data from:senderClient to:selfClient];
        [conversation insertOTRAssetFromClient:senderClient toClient:selfClient metaData:messageData imageData:encryptedImageData assetId:assetId isInline:NO];
        
        [session createAssetWithData:encryptedImageData identifier:assetId.transportString contentType:@"" forConversation:self.groupConversation.identifier];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    [self spinMainQueueWithTimeout:0.5];
    
    ZMMessage *observedMessage = localGroupConversation.messages.lastObject; // the last message is the "you are using a new device message"

    MessageChangeObserver *messageObserver = [[MessageChangeObserver alloc] initWithMessage:observedMessage];
    
    WaitForAllGroupsToBeEmpty(0.5);

    XCTAssertTrue([observedMessage isKindOfClass:ZMAssetClientMessage.class]);
    
    [self.userSession performChanges:^{
        [observedMessage.imageMessageData requestImageDownload];
    }];
    WaitForAllGroupsToBeEmpty(0.5);

    // then
    XCTAssertEqual(messageObserver.notifications.count, 1lu);
    
    NSOrderedSet *currentMessageSet = observer.computedMessages;
    NSOrderedSet *windowMessageSet = observer.window.messages;
    
    XCTAssertEqualObjects(currentMessageSet, windowMessageSet);
    
    for(NSUInteger i = 0; i < observer.window.size; ++ i) {
        if(i == 0) {
            ZMAssetClientMessage *windowMessage = currentMessageSet[i];
            XCTAssertEqualObjects([windowMessage.imageAssetStorage genericMessageFor:ZMImageFormatMedium], message);
            NSData *recievedImageData = [self.userSession.managedObjectContext.zm_fileAssetCache assetData:windowMessage format:ZMImageFormatMedium encrypted:NO];
            XCTAssertEqualObjects(recievedImageData, imageData);
        }
        else {
            XCTAssertEqual(currentMessageSet[i], initialMessageSet[i-1]);
        }
    }
}

- (void)testThatAssetMediumIsRedownloadedIfNoMessageDataIsStored
{
    // GIVEN
    XCTAssertTrue([self login]);

    NSData *encryptedImageData;
    NSData *imageData = [self verySmallJPEGData];
    ZMGenericMessage *message = [self otrAssetGenericMessage:ZMImageFormatMedium imageData:imageData encryptedData:&encryptedImageData];
    NSUUID *assetId = [NSUUID createUUID];
    
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> * __unused session) {
        
        MockUserClient *senderClient = self.user1.clients.anyObject;
        MockUserClient *toClient = self.selfUser.clients.anyObject;
        NSData *messageData = [MockUserClient encryptedWithData:message.data from:senderClient to:toClient];
        [self.groupConversation insertOTRAssetFromClient:senderClient toClient:toClient metaData:messageData imageData:encryptedImageData assetId:assetId isInline:NO];
        [session createAssetWithData:encryptedImageData identifier:assetId.transportString contentType:@"" forConversation:self.groupConversation.identifier];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    ZMConversation *conversation = [self conversationForMockConversation:self.groupConversation];
    ZMAssetClientMessage *imageMessageData = (ZMAssetClientMessage *)conversation.messages.lastObject;

    // WHEN
    // remove all stored data, like cache is cleared
    [self.userSession.managedObjectContext.zm_fileAssetCache deleteAssetData:imageMessageData format:ZMImageFormatMedium encrypted:YES];
    [self.userSession.managedObjectContext.zm_fileAssetCache deleteAssetData:imageMessageData format:ZMImageFormatMedium encrypted:NO];
    
    
    // THEN
    XCTAssertNil([[imageMessageData imageMessageData] imageData]);
    
    [self.userSession performChanges:^{
        [imageMessageData.imageMessageData requestImageDownload];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    XCTAssertNotNil([[imageMessageData imageMessageData] imageData]);
}

- (void)testThatAssetMediumIsRedownloadedIfNoDecryptedMessageDataIsStored
{
    // GIVEN
    XCTAssertTrue([self login]);
    
    NSData *encryptedImageData;
    NSData *imageData = [self verySmallJPEGData];
    ZMGenericMessage *message = [self otrAssetGenericMessage:ZMImageFormatMedium imageData:imageData encryptedData:&encryptedImageData];
    NSUUID *assetId = [NSUUID createUUID];
    
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> * __unused session) {
        MockUserClient *senderClient = self.user1.clients.anyObject;
        MockUserClient *toClient = self.selfUser.clients.anyObject;
        NSData *messageData = [MockUserClient encryptedWithData:message.data from:senderClient to:toClient];
        [self.groupConversation insertOTRAssetFromClient:senderClient toClient:toClient metaData:messageData imageData:encryptedImageData assetId:assetId isInline:NO];
        [session createAssetWithData:encryptedImageData identifier:assetId.transportString contentType:@"" forConversation:self.groupConversation.identifier];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    ZMConversation *conversation = [self conversationForMockConversation:self.groupConversation];
    ZMAssetClientMessage *imageMessageData = (ZMAssetClientMessage *)conversation.messages.lastObject;
    
    // WHEN
    // remove decrypted data, but keep encrypted, like we crashed during decryption
    [self.userSession.managedObjectContext.zm_fileAssetCache storeAssetData:imageMessageData format:ZMImageFormatMedium encrypted:YES data:encryptedImageData];
    [self.userSession.managedObjectContext.zm_fileAssetCache deleteAssetData:imageMessageData format:ZMImageFormatMedium encrypted:NO];
    
    // THEN
    XCTAssertNil([[imageMessageData imageMessageData] imageData]);
    [self.userSession performChanges:^{
        [imageMessageData.imageMessageData requestImageDownload];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    XCTAssertNotNil([[imageMessageData imageMessageData] imageData]);
}

@end


#pragma mark - Trust
@implementation ConversationTestsOTR (Trust)

- (void)makeConversationSecured:(ZMConversation *)conversation
{
    NSArray *allClients = [[conversation activeParticipants].array flattenWithBlock:^id(ZMUser *user) {
        return [user clients].allObjects;
    }];
    UserClient *selfClient = [ZMUser selfUserInUserSession:self.userSession].selfClient;
    
    [self.userSession performChanges:^{
        for (UserClient *client in allClients) {
            [selfClient trustClient:client];
        }
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    XCTAssertTrue(conversation.allUsersTrusted);
    XCTAssertEqual(conversation.securityLevel, ZMConversationSecurityLevelSecure);
}

- (void)makeConversationSecuredWithIgnored:(ZMConversation *)conversation
{
    ZMUser *selfUser = [self userForMockUser:self.selfUser];
    NSArray *allClients = [[conversation activeParticipants].array flattenWithBlock:^id(ZMUser *user) {
        return [user clients].allObjects;
    }];
    
    NSMutableSet *allClientsSet = [NSMutableSet setWithArray:allClients];
    [allClientsSet minusSet:[NSSet setWithObject:selfUser.selfClient]];
    
    [self.userSession performChanges:^{
        [selfUser.selfClient trustClients:allClientsSet];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    XCTAssertEqual(conversation.securityLevel, ZMConversationSecurityLevelSecure);
    
    [self.userSession performChanges:^{
        [selfUser.selfClient ignoreClients:allClientsSet];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    XCTAssertEqual(conversation.securityLevel, ZMConversationSecurityLevelSecureWithIgnored);
}

- (ZMClientMessage *)sendOtrMessageWithInitialSecurityLevel:(ZMConversationSecurityLevel)securityLevel
                                           numberOfMessages:(NSUInteger)numberOfMessages
                                     createAdditionalClient:(BOOL)createAdditionalClient
                            handleSecurityLevelNotification:(void(^)(ConversationChangeInfo *))handler
{
    return [self sendOtrMessageWithInitialSecurityLevel:securityLevel
                                       numberOfMessages:numberOfMessages
                                secureGroupConversation:NO
                                 createAdditionalClient:createAdditionalClient
                        handleSecurityLevelNotification:handler];
}

- (ZMClientMessage *)sendOtrMessageWithInitialSecurityLevel:(ZMConversationSecurityLevel)securityLevel
                                           numberOfMessages:(NSUInteger)numberOfMessages
                                    secureGroupConversation:(BOOL)secureGroupConversation
                                     createAdditionalClient:(BOOL)createAdditionalClient
                            handleSecurityLevelNotification:(void(^)(ConversationChangeInfo *))handler
{
    // login if needed
    if(!self.userSession.isLoggedIn) {
        XCTAssertTrue([self login]);
    }
    
    //register other users clients
    if([self userForMockUser:self.user1].clients.count == 0) {
        [self establishSessionWithMockUser:self.user1];
        WaitForAllGroupsToBeEmpty(0.5);
    }
    
    ZMConversation *conversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    
    // Setup security level
    [self setupInitialSecurityLevel:securityLevel inConversation:conversation];
    
    // make secondary group conversation trusted if needed
    if (secureGroupConversation) {
        ZMConversation *groupLocalConversation = [self conversationForMockConversation:self.groupConversationWithOnlyConnected];
        if(groupLocalConversation.securityLevel != ZMConversationSecurityLevelSecure) {
            for(MockUser* user in self.groupConversationWithOnlyConnected.activeUsers) {
                if(user != self.selfUser && user.clients.count == 0) {
                    [self establishSessionWithMockUser:user];
                    WaitForAllGroupsToBeEmpty(0.5);
                }
                XCTAssert(user.clients.count > 0);
            }
            [self.userSession.syncManagedObjectContext saveOrRollback];
            [self.userSession.managedObjectContext saveOrRollback];
            [self makeConversationSecured:groupLocalConversation];
        }
    }
    
    if (createAdditionalClient) {
        [self.mockTransportSession performRemoteChanges:^(id<MockTransportSessionObjectCreation> _Nonnull session) {
            [session registerClientForUser:self.user1 label:@"Wire for OSX" type:@"permanent"];
        }];
    }
    
    __block ConversationChangeObserver *observer;
    observer = [[ConversationChangeObserver alloc] initWithConversation:conversation];
    observer.notificationCallback = ^(NSObject *note) {
        ConversationChangeInfo *changeInfo = (ConversationChangeInfo *)note;
        if ([changeInfo securityLevelChanged]) {
            if (handler) {
                [self.userSession performChanges:^{
                    handler(changeInfo);
                }];
            }
        }
    };
    [observer clearNotifications];

    // when
    __block ZMClientMessage* message;
    [self.userSession performChanges:^{
        for (NSUInteger i = 0; i < numberOfMessages; i++) {
            message = (id)[conversation appendText:[NSString stringWithFormat:@"Hey %lu", conversation.messages.count] mentions:@[] fetchLinkPreview:YES nonce:[NSUUID createUUID]];
            [NSThread sleepForTimeInterval:0.1];
        }
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    return message;
}

- (void)testThatItChangesTheSecurityLevelIfMessageArrivesFromPreviouslyUnknownUntrustedParticipant
{
    XCTAssertTrue([self login]);
    
    // given
    
    // register other users clients
    [self establishSessionWithMockUser:self.user1];
    [self establishSessionWithMockUser:self.user2];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // make conversation secure
    ZMConversation *conversation = [self conversationForMockConversation:self.groupConversationWithOnlyConnected];
    [self makeConversationSecured:conversation];
    WaitForAllGroupsToBeEmpty(0.5);
    
    XCTAssertEqual(conversation.securityLevel, ZMConversationSecurityLevelSecure);
    
    // when
    
    // silently add user to conversation
    [self performRemoteChangesExludedFromNotificationStream:^(id<MockTransportSessionObjectCreation> session) {
        NOT_USED(session);
        [self.groupConversationWithOnlyConnected addUsersByUser:self.user1 addedUsers:@[self.user5]];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // send a message from silently added user
    [self.mockTransportSession performRemoteChanges:^(id<MockTransportSessionObjectCreation> session) {
        NOT_USED(session);
        MockUserClient *mockSelfClient = self.selfUser.clients.anyObject;
        MockUserClient *mockUser5Client = self.user5.clients.anyObject;
        ZMGenericMessage *message = [ZMGenericMessage messageWithContent:[ZMText textWith:@"Test 123" mentions:@[] linkPreviews:@[]] nonce:NSUUID.createUUID];
        NSData *messageData = [MockUserClient encryptedWithData:message.data from:mockUser5Client to:mockSelfClient];
        [self.groupConversationWithOnlyConnected insertOTRMessageFromClient:mockUser5Client toClient:mockSelfClient data:messageData];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    BOOL containsParticipantAddedMessage = NO;
    BOOL containsNewClientMessage = YES;
    for (ZMMessage *message in conversation.messages) {
        if ([message isKindOfClass:ZMSystemMessage.class] && [(ZMSystemMessage *)message systemMessageType] == ZMSystemMessageTypeParticipantsAdded) {
            switch ([(ZMSystemMessage *)message systemMessageType]) {
                case ZMSystemMessageTypeParticipantsAdded:
                    containsParticipantAddedMessage = YES;
                    break;
                case ZMSystemMessageTypeNewClient:
                    containsNewClientMessage = YES;
                    break;
                default:
                    break;
            }
            
        }
    }
    
    XCTAssertEqual(conversation.securityLevel, ZMConversationSecurityLevelSecureWithIgnored);
    XCTAssertTrue(containsParticipantAddedMessage);
    XCTAssertTrue(containsNewClientMessage);
}

- (void)testThatItChangesTheSecurityLevelIfUnconnectedUntrustedParticipantIsAdded
{
    XCTAssertTrue([self login]);
    
    // register other users clients
    [self establishSessionWithMockUser:self.user1];
    [self establishSessionWithMockUser:self.user2];
    WaitForAllGroupsToBeEmpty(0.5);
    
    ZMConversation *conversation = [self conversationForMockConversation:self.groupConversationWithOnlyConnected];
    [self makeConversationSecured:conversation];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // when
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        NOT_USED(session);
        [self.groupConversationWithOnlyConnected addUsersByUser:self.user1 addedUsers:@[self.user5]];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    ZMUser *addedUser = [self userForMockUser:self.user5];
    XCTAssertTrue([conversation.lastServerSyncedActiveParticipants containsObject:addedUser]);
    XCTAssertNil(addedUser.connection);
    
    XCTAssertFalse(conversation.allUsersTrusted);
    XCTAssertEqual(conversation.securityLevel, ZMConversationSecurityLevelSecureWithIgnored);
    
    // when
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        MockConversation *selfToUser5Conversation = [session insertOneOnOneConversationWithSelfUser:self.selfUser otherUser:self.user5];
        selfToUser5Conversation.creator = self.selfUser;
        MockConnection *connectionSelfToUser5 = [session insertConnectionWithSelfUser:self.selfUser toUser:self.user5];
        connectionSelfToUser5.status = @"accepted";
        connectionSelfToUser5.lastUpdate = [NSDate dateWithTimeIntervalSinceNow:-3];
        connectionSelfToUser5.conversation = selfToUser5Conversation;
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    XCTAssertEqual(conversation.securityLevel, ZMConversationSecurityLevelSecureWithIgnored);
    
    [self establishSessionWithMockUser:self.user5];
    WaitForAllGroupsToBeEmpty(0.5);

    ZMUser *user = [self userForMockUser:self.user5];

    [self.userSession performChanges:^{
        ZMUser *selfUser = [self userForMockUser:self.selfUser];
        [selfUser.selfClient trustClients:user.clients];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertTrue(conversation.allUsersTrusted);
    XCTAssertEqual(conversation.securityLevel, ZMConversationSecurityLevelSecure);
}

- (void)testThatItDeliversOTRMessageIfAllClientsAreTrustedAndNoMissingClients
{
    //given
    XCTAssertTrue([self login]);
    
    MockConversation *mockConversation = self.selfToUser1Conversation;
    ZMConversation *conversation = [self conversationForMockConversation:mockConversation];
    
    {
        // send a message to fetch all the missing client
        [self.userSession performChanges:^{
            [conversation appendText:[NSString stringWithFormat:@"Hey %lu", conversation.messages.count] mentions:@[] fetchLinkPreview:YES nonce:[NSUUID createUUID]];
        }];
        WaitForAllGroupsToBeEmpty(0.5);
    }
    
    [self makeConversationSecured:conversation];
    
    // when
    __block ZMClientMessage* message;
    [self.userSession performChanges:^{
        message = (id)[conversation appendText:[NSString stringWithFormat:@"Hey %lu", conversation.messages.count] mentions:@[] fetchLinkPreview:YES nonce:[NSUUID createUUID]];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    MockPushEvent *lastEvent = self.mockTransportSession.updateEvents.lastObject;
    NSDictionary *lastEventPayload = lastEvent.payload.asDictionary;
    ZMUpdateEventType lastEventType = [MockEvent typeFromString:lastEventPayload[@"type"]];
    
    XCTAssertEqual(lastEventType, ZMUpdateEventTypeConversationOtrMessageAdd);
    XCTAssertEqual(message.deliveryState, ZMDeliveryStateSent);
    
    XCTAssertEqual(message.conversation.securityLevel, ZMConversationSecurityLevelSecure);
}


- (void)testThatItDeliversOTRMessageAfterIgnoringAndResending
{
    __block BOOL notificationRecieved = NO;
    //given
    XCTAssertTrue([self login]);
    
    MockConversation *mockConversation = self.selfToUser1Conversation;
    ZMConversation *conversation = [self conversationForMockConversation:mockConversation];
    
    {
        // send a message to fetch all the missing client
        [self.userSession performChanges:^{
            [conversation appendText:[NSString stringWithFormat:@"Hey %lu", conversation.messages.count] mentions:@[] fetchLinkPreview:YES nonce:[NSUUID createUUID]];
        }];
        WaitForAllGroupsToBeEmpty(0.5);
    }
    [self makeConversationSecured:conversation];
    
    //when
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        [session registerClientForUser:self.user1 label:@"remote client" type:@"permanent"];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    __block ConversationChangeObserver *observer;
    observer = [[ConversationChangeObserver alloc] initWithConversation:conversation];
    observer.notificationCallback = ^(NSObject *note) {
        ConversationChangeInfo *changeInfo = (ConversationChangeInfo *)note;
        if (changeInfo.securityLevelChanged && changeInfo.didNotSendMessagesBecauseOfConversationSecurityLevel) {
            notificationRecieved = YES;
            [self.userSession performChanges:^{
                if (changeInfo.conversation.securityLevel == ZMConversationSecurityLevelSecureWithIgnored) {
                    [changeInfo.conversation resendMessagesThatCausedConversationSecurityDegradation];
                }
            }];
        }
    };
    [observer clearNotifications];
    
    // when
    __block ZMClientMessage* message;
    [self.userSession performChanges:^{
        message = (id)[conversation appendText:[NSString stringWithFormat:@"Hey %lu", conversation.messages.count] mentions:@[] fetchLinkPreview:YES nonce:[NSUUID createUUID]];
    }];
    [message.managedObjectContext saveOrRollback];
    WaitForAllGroupsToBeEmpty(0.5);
    
    XCTAssertTrue(notificationRecieved);
    XCTAssertEqual(message.deliveryState, ZMDeliveryStateSent);
    
    XCTAssertEqual(message.visibleInConversation, message.conversation);
    XCTAssertEqual(message.conversation.securityLevel, ZMConversationSecurityLevelNotSecure);
    
}

- (void)testThatItDoesNotDeliversOTRMessageAfterIgnoringExpiring
{
    __block BOOL notificationRecieved = NO;
    
    // when
    ZMClientMessage *message1 = [self sendOtrMessageWithInitialSecurityLevel:ZMConversationSecurityLevelSecure
                                                            numberOfMessages:1
                                                      createAdditionalClient:YES
                                             handleSecurityLevelNotification:^(ConversationChangeInfo *changeInfo) {
                                                 notificationRecieved = YES;
                                                 if (changeInfo.conversation.securityLevel == ZMConversationSecurityLevelSecureWithIgnored) {
                                                     XCTAssertTrue(changeInfo.didNotSendMessagesBecauseOfConversationSecurityLevel);
                                                 }
                                             }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertTrue(notificationRecieved);
    
    XCTAssertEqual(message1.deliveryState, ZMDeliveryStateFailedToSend);
    
    XCTAssertEqual(message1.conversation.securityLevel, ZMConversationSecurityLevelSecureWithIgnored);
}


- (void)testThatItDoesNotDeliverOriginalOTRMessageAfterIgnoringExpiringAndThenSendingAnotherOne
{
    // GIVEN
    __block BOOL notificationRecieved = NO;
    XCTAssertTrue([self login]);
    ZMConversation *conversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    
    [self.userSession performChanges:^ {
        [conversation appendText:[NSString stringWithFormat:@"Hey %lu", conversation.messages.count] mentions:@[] fetchLinkPreview:YES nonce:[NSUUID createUUID]];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    [self makeConversationSecured:conversation];
    
    // add extra user, that will cause conversation degradation
    [self.mockTransportSession performRemoteChanges:^(id<MockTransportSessionObjectCreation> session) {
        [session registerClientForUser:self.user1 label:@"remote client" type:@"permanent"];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    __block ConversationChangeObserver *observer;
    observer = [[ConversationChangeObserver alloc] initWithConversation:conversation];
    observer.notificationCallback = ^(NSObject *note) {
        ConversationChangeInfo *changeInfo = (ConversationChangeInfo *)note;
        if ([changeInfo securityLevelChanged]) {
            notificationRecieved = YES;
            if (changeInfo.conversation.securityLevel == ZMConversationSecurityLevelSecureWithIgnored) {
                XCTAssertTrue(changeInfo.didNotSendMessagesBecauseOfConversationSecurityLevel);
                [changeInfo.conversation doNotResendMessagesThatCausedDegradation];
            }
        }
    };
    [observer clearNotifications];
    
    // WHEN
    __block ZMClientMessage* message1;
    [self.userSession performChanges:^{ // this should cause conversation to degrade
        message1 = (id)[conversation appendText:[NSString stringWithFormat:@"Hey %lu", conversation.messages.count] mentions:@[] fetchLinkPreview:YES nonce:[NSUUID createUUID]];
    }];
    
    // THEN
    WaitForAllGroupsToBeEmpty(0.5);
    XCTAssertTrue(notificationRecieved);
    XCTAssertNotNil(message1);
    XCTAssertEqual(message1.deliveryState, ZMDeliveryStateFailedToSend);
    XCTAssertEqual(message1.conversation.securityLevel, ZMConversationSecurityLevelSecureWithIgnored);
    WaitForAllGroupsToBeEmpty(0.5);
    
    // GIVEN
    observer.notificationCallback = ^(NSObject *note) {
        ConversationChangeInfo *changeInfo = (ConversationChangeInfo *)note;
        if ([changeInfo securityLevelChanged]) {
            notificationRecieved &= YES;
            if (changeInfo.conversation.securityLevel == ZMConversationSecurityLevelSecureWithIgnored) {
                XCTAssertTrue(changeInfo.didNotSendMessagesBecauseOfConversationSecurityLevel);
                [self.userSession performChanges:^{
                    [changeInfo.conversation resendMessagesThatCausedConversationSecurityDegradation];
                }];
            }
        }
    };
    [observer clearNotifications];

    // WHEN
    __block ZMClientMessage* message2;
    [self.userSession performChanges:^{
        message2 = (id)[conversation appendText:[NSString stringWithFormat:@"Hey %lu", conversation.messages.count] mentions:@[] fetchLinkPreview:YES nonce:[NSUUID createUUID]];
    }];

    
    // THEN
    WaitForAllGroupsToBeEmpty(0.5);
    XCTAssertTrue(notificationRecieved);
    XCTAssertEqual(message2.deliveryState, ZMDeliveryStateSent);
    XCTAssertNotNil(message2);
    XCTAssertEqual(message2.conversation.securityLevel, ZMConversationSecurityLevelNotSecure);
    XCTAssertEqual(message1.deliveryState, ZMDeliveryStateFailedToSend);
}

- (void)testThatItDoesNotSendAnUploadedFailedMessageForFileMessagesUploadingThePlaceholderWhenDegrading
{
    // Given
    XCTAssertTrue([self login]);

    [self establishSessionWithMockUser:self.user1];
    ZMConversation *conversation = [self conversationForMockConversation:self.selfToUser1Conversation];

    WaitForAllGroupsToBeEmpty(0.5);

    [self makeConversationSecured:conversation];

    [self.mockTransportSession performRemoteChanges:^(id<MockTransportSessionObjectCreation> _Nonnull session) {
        [session registerClientForUser:self.user1 label:@"iPhone" type:@"permanent"];
    }];
    WaitForAllGroupsToBeEmpty(0.5);

    // When
    __block ZMAssetClientMessage *message;
    [self.userSession performChanges:^{
        NSURL *fileURL = [self createTestFile:self.name];
        ZMFileMetadata *fileMetadata = [[ZMFileMetadata alloc] initWithFileURL:fileURL thumbnail:nil];
        message = (ZMAssetClientMessage *)[conversation appendFile:fileMetadata nonce:NSUUID.createUUID];
    }];

    WaitForAllGroupsToBeEmpty(0.5);

    // Then
    XCTAssertEqual(conversation.securityLevel, ZMConversationSecurityLevelSecureWithIgnored);
    XCTAssert(message.isExpired);
    XCTAssertEqual(message.uploadState, AssetUploadStateDone);
    XCTAssertEqual(message.transferState, ZMFileTransferStateFailedUpload);
}

- (void)testThatItInsertsNewClientSystemMessageWhenReceivedMissingClients
{
    ZMClientMessage *message = [self sendOtrMessageWithInitialSecurityLevel:ZMConversationSecurityLevelSecure
                                                           numberOfMessages:1
                                                     createAdditionalClient:YES
                                            handleSecurityLevelNotification:nil];
    
    WaitForAllGroupsToBeEmpty(0.5);
    
    ZMConversation *conversation = message.conversation;
    ZMSystemMessage *lastMessage = [conversation.messages objectAtIndex:conversation.messages.count - 2];
    XCTAssertTrue([lastMessage isKindOfClass:[ZMSystemMessage class]]);
    
    NSArray<ZMUser *> *expectedUsers = @[[self userForMockUser:self.user1]];
    
    AssertArraysContainsSameObjects(lastMessage.users.allObjects, expectedUsers);
    XCTAssertEqual(lastMessage.systemMessageType, ZMSystemMessageTypeNewClient);
}

- (void)testThatItInsertsNewClientSystemMessageWhenReceivedMissingClientsEvenIfSeveralMessagesAppendedAfter
{
    ZMClientMessage *message = [self sendOtrMessageWithInitialSecurityLevel:ZMConversationSecurityLevelSecure
                                                           numberOfMessages:5
                                                     createAdditionalClient:YES
                                            handleSecurityLevelNotification:nil];
    
    WaitForAllGroupsToBeEmpty(0.5);
    
    ZMConversation *conversation = message.conversation;
    ZMSystemMessage *lastMessage = [conversation.messages objectAtIndex:conversation.messages.count - 6];
    XCTAssertTrue([lastMessage isKindOfClass:[ZMSystemMessage class]]);
    
    NSArray<ZMUser *> *expectedUsers = @[[self userForMockUser:self.user1]];
    
    AssertArraysContainsSameObjects(lastMessage.users.allObjects, expectedUsers);
    XCTAssertEqual(lastMessage.systemMessageType, ZMSystemMessageTypeNewClient);
}

- (void)testThatInsertsSecurityLevelDecreasedMessageInTheEndIfMessageCausedIsInOtherConversation
{
    XCTAssertTrue([self login]);
    
    //register other users clients
    
    void (^secureConversationBlock)(ZMConversation *) = ^(ZMConversation *conversation) {
        // send a message to fetch all the missing client
        [self.userSession performChanges:^{
            [conversation appendText:[NSString stringWithFormat:@"Hey %lu", conversation.messages.count] mentions:@[] fetchLinkPreview:YES nonce:[NSUUID createUUID]];
        }];
        WaitForAllGroupsToBeEmpty(0.5);
        [self makeConversationSecured:conversation];

    };
    
    ZMConversation *conversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    ZMConversation *groupLocalConversation = [self conversationForMockConversation:self.groupConversationWithOnlyConnected];

    secureConversationBlock(conversation);
    secureConversationBlock(groupLocalConversation);
    
    [self.mockTransportSession performRemoteChanges:^(id<MockTransportSessionObjectCreation> session){
        [session registerClientForUser:self.user1 label:@"remote client" type:@"permanent"];
    }];
    
    // when
    __block ZMClientMessage* message;
    [self.userSession performChanges:^{
        message = (id)[conversation appendText:[NSString stringWithFormat:@"Hey %lu", conversation.messages.count] mentions:@[] fetchLinkPreview:YES nonce:[NSUUID createUUID]];
    }];
    [message.managedObjectContext saveOrRollback];
    WaitForAllGroupsToBeEmpty(0.5);
    
    XCTAssertNotNil(message.conversation);
    
    ZMSystemMessage *lastMessage = [groupLocalConversation.messages objectAtIndex:groupLocalConversation.messages.count - 1];
    XCTAssertTrue([lastMessage isKindOfClass:[ZMSystemMessage class]]);
    
    XCTAssertEqual(message.conversation, conversation);
    NSArray<ZMUser *> *expectedUsers = @[[self userForMockUser:self.user1]];
    
    AssertArraysContainsSameObjects(lastMessage.users.allObjects, expectedUsers);
    XCTAssertEqual(lastMessage.systemMessageType, ZMSystemMessageTypeNewClient);


}

- (void)testThatInsertsSecurityLevelDecreasedMessageInTheEndOfConversationIfNotCausedByMessage
{
    // given
    XCTAssertTrue([self login]);
    
    UserClient *selfClient = [ZMUser selfUserInUserSession:self.userSession].selfClient;
    [self establishSessionWithMockUser:self.user1];
    WaitForAllGroupsToBeEmpty(0.5);
    
    ZMConversation *conversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    [self makeConversationSecured:conversation];
    
    // when
    ZMUser *localUser1 = [self userForMockUser:self.user1];
    [selfClient ignoreClient:localUser1.clients.anyObject];
    
    // then
    ZMSystemMessage *lastMessage = [conversation.messages objectAtIndex:conversation.messages.count - 1];
    XCTAssertTrue([lastMessage isKindOfClass:[ZMSystemMessage class]]);
    
    NSArray<ZMUser *> *expectedUsers = @[localUser1];
    
    AssertArraysContainsSameObjects(lastMessage.users.allObjects, expectedUsers);
    XCTAssertEqual(lastMessage.systemMessageType, ZMSystemMessageTypeIgnoredClient);

}

- (void)testThatItChangesSecurityLevelToInsecureBecauseFailedMessageAttemptWhenSelfTriesToSendMessageInDegradingConversation
{
    // GIVEN
    XCTAssertTrue([self login]);
    [self establishSessionWithMockUser:self.user1];
    ZMConversation *conversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    [self makeConversationSecured:conversation];
    [self.mockTransportSession performRemoteChanges:^(id<MockTransportSessionObjectCreation> _Nonnull session) {
        [session registerClientForUser:self.user1 label:@"iPod Touch" type:@"permanent"];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // WHEN
    [self.userSession performChanges:^{
        [conversation appendText:@"Hello" mentions:@[] fetchLinkPreview:YES nonce:NSUUID.createUUID];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // THEN
    ZMSystemMessage *lastMessage = [conversation.messages objectAtIndex:conversation.messages.count - 2];
    XCTAssertEqual(conversation.securityLevel, ZMConversationSecurityLevelSecureWithIgnored);
    XCTAssertEqual(conversation.messages.count, 4lu); // 3x system message (new device & secured & new client) + appended client message
    XCTAssertEqual(lastMessage.systemMessageData.systemMessageType, ZMSystemMessageTypeNewClient);
}

- (void)testThatItChangesSecurityLevelToInsecureBecauseOtherWhenOtherClientTriesToSendMessageAndDegradesDegradingConversation
{
    // GIVEN
    XCTAssertTrue([self login]);
    [self establishSessionWithMockUser:self.user1];
    ZMConversation *conversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    [self makeConversationSecured:conversation];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // WHEN
    ZMGenericMessage *message = [ZMGenericMessage messageWithContent:[ZMText textWith:@"Test" mentions:@[] linkPreviews:@[]] nonce:NSUUID.createUUID];
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> * __unused transportSession) {
        MockUserClient *newClient = [transportSession registerClientForUser:self.user1 label:@"test-it" type:@"permanent"];
        [self.selfToUser1Conversation encryptAndInsertDataFromClient:newClient toClient:self.selfUser.clients.anyObject data:message.data];
    }];
    
    WaitForAllGroupsToBeEmpty(0.5);
    
    // THEN
    ZMSystemMessage *lastMessage = [conversation.messages objectAtIndex:conversation.messages.count - 2];
    XCTAssertEqual(conversation.securityLevel, ZMConversationSecurityLevelSecureWithIgnored);
    XCTAssertEqual(conversation.messages.count, 4lu); // 3x system message (new device & secured & new client) + appended client message
    XCTAssertEqual(lastMessage.systemMessageData.systemMessageType, ZMSystemMessageTypeNewClient);
}

- (void)checkThatItShouldInsertSecurityLevelSystemMessageAfterSendingMessage:(BOOL)shouldInsert
                                                   shouldChangeSecurityLevel:(BOOL)shouldChangeSecurityLevel
                                                     forInitialSecurityLevel:(ZMConversationSecurityLevel)initialSecurityLevel
                                                       expectedSecurityLevel:(ZMConversationSecurityLevel)expectedSecurityLevel
{
    NSString *expectedText = @"The sky above the port was the color of ";
    ZMGenericMessage *message = [ZMGenericMessage messageWithContent:[ZMText textWith:expectedText mentions:@[] linkPreviews:@[]] nonce:NSUUID.createUUID];
    
    XCTAssertTrue([self login]);
    
    [self establishSessionWithMockUser:self.user1];
    WaitForAllGroupsToBeEmpty(0.5);
    
    ZMConversation *conversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    
    [self setupInitialSecurityLevel:initialSecurityLevel inConversation:conversation];
    
    //register new client for user1
    __block MockUserClient *newUser1Client;
    
    // Make sure this relationship is not a fault:
    for (id obj in conversation.messages) {
        (void) obj;
    }
    
    // when
    ConversationChangeObserver *observer = [[ConversationChangeObserver alloc] initWithConversation:conversation];
    [observer clearNotifications];
    
    NSOrderedSet *previousMessage = conversation.messages.copy;
    
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> * __unused transportSession) {
        newUser1Client = [transportSession registerClientForUser:self.user1 label:@"iphone-something" type:@"permanent"];
        [self.selfToUser1Conversation encryptAndInsertDataFromClient:newUser1Client toClient:self.selfUser.clients.anyObject data:message.data];
    }];
    
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    ConversationChangeInfo *note = [observer.notifications filterWithBlock:^BOOL(ConversationChangeInfo *notification) {
        return notification.securityLevelChanged;
    }].firstObject;
    if (shouldChangeSecurityLevel) {
        XCTAssertNotNil(note);
    }
    else {
        XCTAssertNil(note);
    }
    
    XCTAssertEqual(conversation.securityLevel, expectedSecurityLevel);

    NSMutableOrderedSet *messagesAfterInserting = conversation.messages.mutableCopy;
    [messagesAfterInserting minusOrderedSet:previousMessage];
    
    if (shouldInsert) {
        XCTAssertEqual(messagesAfterInserting.count, 2lu); // Client message and system message
        ZMSystemMessage *lastMessage = messagesAfterInserting.firstObject;
        XCTAssertTrue([lastMessage isKindOfClass:[ZMSystemMessage class]]);
        
        NSArray<ZMUser *> *expectedUsers = @[[self userForMockUser:self.user1]];
        
        AssertArraysContainsSameObjects(lastMessage.users.allObjects, expectedUsers);
        XCTAssertEqual(lastMessage.systemMessageType, ZMSystemMessageTypeNewClient);
    }
    else {
        XCTAssertEqual(messagesAfterInserting.count, 1lu); // Only the added client message
    }
    
}

- (void)testThatItInsertsNewClientSystemMessageWhenReceivingMessageFromNewClientInSecuredConversation
{
    [self checkThatItShouldInsertSecurityLevelSystemMessageAfterSendingMessage:YES
                                                     shouldChangeSecurityLevel:YES
                                                       forInitialSecurityLevel:ZMConversationSecurityLevelSecure
                                                         expectedSecurityLevel:ZMConversationSecurityLevelSecureWithIgnored];
}

- (void)testThatItInsertsNewClientSystemMessageWhenReceivingMessageFromNewClientInPartialSecureConversation
{
    [self checkThatItShouldInsertSecurityLevelSystemMessageAfterSendingMessage:NO
                                                     shouldChangeSecurityLevel:NO
                                                       forInitialSecurityLevel:ZMConversationSecurityLevelSecureWithIgnored
                                                         expectedSecurityLevel:ZMConversationSecurityLevelSecureWithIgnored];
}

- (void)testThatItDoesNotInsertNewClientSystemMessageWhenReceivingMessageFromNewClientInNotSecuredConversation
{
    [self checkThatItShouldInsertSecurityLevelSystemMessageAfterSendingMessage:NO
                                                     shouldChangeSecurityLevel:NO
                                                       forInitialSecurityLevel:ZMConversationSecurityLevelNotSecure
                                                         expectedSecurityLevel:ZMConversationSecurityLevelNotSecure];
}

- (void)checkThatItShouldInsertIgnoredSystemMessageAfterIgnoring:(BOOL)shouldInsert
                                       shouldChangeSecurityLevel:(BOOL)shouldChangeSecurityLevel
                                         forInitialSecurityLevel:(ZMConversationSecurityLevel)initialSecurityLevel
                                           expectedSecurityLevel:(ZMConversationSecurityLevel)expectedSecurityLevel
{
    XCTAssertTrue([self login]);
    
    [self establishSessionWithMockUser:self.user1];
    WaitForAllGroupsToBeEmpty(0.5);
    
    XCTAssertFalse(self.user1.clients.isEmpty);
    ZMConversation *conversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    
    [self setupInitialSecurityLevel:initialSecurityLevel inConversation:conversation];
    
    // Make sure this relationship is not a fault:
    for (id obj in conversation.messages) {
        (void) obj;
    }
    
    NSUInteger messageCountAfterSetup = conversation.messages.count;
    
    // when
    ConversationChangeObserver *observer = [[ConversationChangeObserver alloc] initWithConversation:conversation];
    [observer clearNotifications];
    
    UserClient *selfClient = [ZMUser selfUserInUserSession:self.userSession].selfClient;
    ZMUser *user1 = [self userForMockUser:self.user1];
    
    [self.userSession performChanges:^{
        if (initialSecurityLevel == ZMConversationSecurityLevelSecure) {
            [selfClient ignoreClients:user1.clients];
        } else {
            UserClient *trusted = [user1.clients.allObjects firstObjectMatchingWithBlock:^BOOL(UserClient *obj) {
                return [obj.trustedByClients containsObject:selfClient];
            }];
            if (nil != trusted) {
                [selfClient ignoreClient:trusted];
            }
        }
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    if (shouldChangeSecurityLevel) {
        ConversationChangeInfo *note = observer.notifications.firstObject;
        XCTAssertNotNil(note);
        XCTAssertTrue(note.securityLevelChanged);
    }
    else {
        ConversationChangeInfo *note = observer.notifications.firstObject;
        if (note) {
            XCTAssertFalse(note.securityLevelChanged);
        }
    }
    
    XCTAssertEqual(conversation.securityLevel, expectedSecurityLevel);
    
    if (shouldInsert) {
        __block ZMSystemMessage *systemMessage;
        [conversation.messages enumerateObjectsWithOptions:NSEnumerationReverse usingBlock:^(id  _Nonnull msg, NSUInteger __unused idx, BOOL * _Nonnull stop) {
            if([msg isKindOfClass:ZMSystemMessage.class]) {
                systemMessage = msg;
                *stop = YES;
            }
        }];
        XCTAssertNotNil(systemMessage);
        
        NSArray<ZMUser *> *expectedUsers = @[[self userForMockUser:self.user1]];
        
        AssertArraysContainsSameObjects(systemMessage.users.allObjects, expectedUsers);
        XCTAssertEqual(systemMessage.systemMessageType, ZMSystemMessageTypeIgnoredClient);
    }
    else {
        XCTAssertEqual(messageCountAfterSetup, conversation.messages.count);
    }
    
}

- (void)setupInitialSecurityLevel:(ZMConversationSecurityLevel)initialSecurityLevel inConversation:(ZMConversation *)conversation
{
    if(conversation.securityLevel == initialSecurityLevel) {
        return;
    }
    switch (initialSecurityLevel) {
        case ZMConversationSecurityLevelSecure:
        {
            [self makeConversationSecured:conversation];
            XCTAssertEqual(conversation.securityLevel, ZMConversationSecurityLevelSecure);
        }
            break;
            
        case ZMConversationSecurityLevelSecureWithIgnored:
        {
            [self makeConversationSecuredWithIgnored:conversation];
            XCTAssertEqual(conversation.securityLevel, ZMConversationSecurityLevelSecureWithIgnored);
        }
            break;
        default:
            break;
    }
}


- (void)testThatItInsertsIgnoredSystemMessageWhenIgnoringClientFromSecuredConversation;
{
    [self checkThatItShouldInsertIgnoredSystemMessageAfterIgnoring:YES
                                         shouldChangeSecurityLevel:YES
                                           forInitialSecurityLevel:ZMConversationSecurityLevelSecure
                                             expectedSecurityLevel:ZMConversationSecurityLevelSecureWithIgnored];
}


- (void)testThatItDoesNotAppendsIgnoredSytemMessageWhenIgnoringClientFromNotSecuredConversation;
{
    [self checkThatItShouldInsertIgnoredSystemMessageAfterIgnoring:NO
                                         shouldChangeSecurityLevel:NO
                                           forInitialSecurityLevel:ZMConversationSecurityLevelNotSecure
                                             expectedSecurityLevel:ZMConversationSecurityLevelNotSecure];
    
}

- (void)testThatItInsertsSystemMessageWhenAllClientsBecomeTrusted
{
    XCTAssertTrue([self login]);
    
    [self establishSessionWithMockUser:self.user1];
    WaitForAllGroupsToBeEmpty(0.5);
    
    ZMConversation *conversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    ConversationChangeObserver *observer = [[ConversationChangeObserver alloc] initWithConversation:conversation];
    [observer clearNotifications];
    
    // when
    [self makeConversationSecured:conversation];
    
    // then
    XCTAssertEqual(observer.notifications.count, 1u);
    ConversationChangeInfo *note = observer.notifications.firstObject;
    XCTAssertNotNil(note);
    XCTAssertTrue(note.securityLevelChanged);

    XCTAssertEqual(conversation.securityLevel, ZMConversationSecurityLevelSecure);
    
    ZMSystemMessage *lastMessage = [conversation.messages objectAtIndex:conversation.messages.count - 1];
    XCTAssertTrue([lastMessage isKindOfClass:[ZMSystemMessage class]]);
    
    XCTAssertEqual(lastMessage.systemMessageType, ZMSystemMessageTypeConversationIsSecure);
}

- (void)testThatItInsertsSystemMessageWhenAllSelfUserClientsBecomeTrusted
{
    // given
    XCTAssertTrue([self login]);
    
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        [session registerClientForUser:self.selfUser label:@"Second client" type:@"permanent"];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    ZMConversation *conversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    [self.userSession performChanges:^{
        [conversation appendText:@"Hey you" mentions:@[] fetchLinkPreview:NO nonce:[NSUUID createUUID]];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    UserClient *selfClient = [ZMUser selfUserInUserSession:self.userSession].selfClient;
    WaitForAllGroupsToBeEmpty(0.5);
    
    ZMUser *user1 = [self userForMockUser:self.user1];
    [self.userSession performChanges:^{
        [selfClient trustClient:user1.clients.anyObject];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    
    NSArray *clients = selfClient.user.clients.allObjects;
    UserClient *otherClient = [clients firstObjectMatchingWithBlock:^BOOL(UserClient *client) {
        return client.remoteIdentifier != selfClient.remoteIdentifier;
    }];
    XCTAssertNotNil(otherClient);
    XCTAssertEqual(conversation.securityLevel, ZMConversationSecurityLevelNotSecure);
    
    ConversationChangeObserver *observer = [[ConversationChangeObserver alloc] initWithConversation:conversation];
    [observer clearNotifications];
    
    // when
    [self.userSession performChanges:^{
        [selfClient trustClient:otherClient];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(observer.notifications.count, 1u);
    ConversationChangeInfo *note = observer.notifications.firstObject;
    XCTAssertNotNil(note);
    XCTAssertTrue(note.securityLevelChanged);
    
    XCTAssertEqual(conversation.securityLevel, ZMConversationSecurityLevelSecure);
    
    ZMSystemMessage *lastMessage = [conversation.messages objectAtIndex:conversation.messages.count - 1];
    XCTAssertTrue([lastMessage isKindOfClass:[ZMSystemMessage class]]);
    
    XCTAssertEqual(lastMessage.systemMessageType, ZMSystemMessageTypeConversationIsSecure);
}

- (void)testThatItInsertsSystemMessageWhenTheSelfUserDeletesAnUntrustedClient
{
    // given
    XCTAssertTrue([self login]);
    
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        [session registerClientForUser:self.selfUser label:@"other selfuser clients" type:@"permanent"];
    }];
    WaitForAllGroupsToBeEmpty(0.5);

    ZMConversation *conversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    
    ZMUser *otherUser = [self userForMockUser:self.user1];
    ZMUser *selfUser = [ZMUser selfUserInUserSession:self.userSession];

    XCTAssertEqual(conversation.securityLevel, ZMConversationSecurityLevelNotSecure);

    // (1) trust local client of user1
    {
        // adding a message to fetch client
        [self.userSession performChanges:^{
            [conversation appendText:[NSString stringWithFormat:@"Hey %lu", conversation.messages.count] mentions:@[] fetchLinkPreview:YES nonce:[NSUUID createUUID]];
        }];
        WaitForAllGroupsToBeEmpty(0.5);
        
        UserClient *selfClient = selfUser.selfClient;
        
        [self.userSession performChanges:^{
            for (UserClient *client in otherUser.clients) {
                [selfClient trustClient:client];
            }
        }];
        WaitForAllGroupsToBeEmpty(0.5);
        
        // then
        XCTAssertEqual(conversation.securityLevel, ZMConversationSecurityLevelNotSecure); // we do not trust one of our own devices,
    }
    
    NSArray *clients = selfUser.clients.allObjects;
    UserClient *otherSelfClient = [clients firstObjectMatchingWithBlock:^BOOL(UserClient *client) {
        return client.remoteIdentifier != selfUser.selfClient.remoteIdentifier;
    }];

    
    ConversationChangeObserver *observer = [[ConversationChangeObserver alloc] initWithConversation:conversation];
    [observer clearNotifications];
    
    NSUInteger currentMessageCount = conversation.messages.count;
    
    // when
    // (2) selfUser deletes remote selfUser client
    {
        [self.userSession performChanges:^{
            [self.userSession deleteClients:@[otherSelfClient] withCredentials:[ZMEmailCredentials credentialsWithEmail:IntegrationTest.SelfUserEmail password:IntegrationTest.SelfUserPassword]];
        }];
        WaitForAllGroupsToBeEmpty(0.5);
        
        // then
        XCTAssertEqual(observer.notifications.count, 1u);
        ConversationChangeInfo *note = observer.notifications.firstObject;
        XCTAssertNotNil(note);
        XCTAssertTrue(note.securityLevelChanged);
        
        XCTAssertEqual(conversation.securityLevel, ZMConversationSecurityLevelSecure);
        if (conversation.messages.count > currentMessageCount) {
            ZMSystemMessage *lastMessage = [conversation.messages objectAtIndex:currentMessageCount];
            XCTAssertTrue([lastMessage isKindOfClass:[ZMSystemMessage class]]);
            
            XCTAssertEqual(lastMessage.systemMessageType, ZMSystemMessageTypeConversationIsSecure);
        }
        else {
            XCTFail(@"Did not create system message");
        }
    }
}

- (void)testThatItInsertsSystemMessageWhenTheOtherUserDeletesAnUntrustedClient
{
    // given
    XCTAssertTrue([self login]);
    
    ZMConversation *conversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    ZMUser *otherUser = [self userForMockUser:self.user1];
    
    __block NSString *trustedRemoteID;
    // (1) trust local client of user1
    {
        // adding a message
        [self.userSession performChanges:^{
            [conversation appendText:[NSString stringWithFormat:@"Hey %lu", conversation.messages.count] mentions:@[] fetchLinkPreview:YES nonce:[NSUUID createUUID]];
        }];
        WaitForAllGroupsToBeEmpty(0.5);
        [self makeConversationSecured:conversation];
        trustedRemoteID = [otherUser.clients.anyObject remoteIdentifier];

        // then
        XCTAssertEqual(otherUser.clients.count, 1u);
        XCTAssertEqual(conversation.securityLevel, ZMConversationSecurityLevelSecure);
    }
    ConversationChangeObserver *observer = [[ConversationChangeObserver alloc] initWithConversation:conversation];
    [observer clearNotifications];
    
    __block MockUserClient *additionalUserClient;
    // (2) insert new client for user 1
    {
        [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
            additionalUserClient = [session registerClientForUser:self.user1 label:@"other user 1 clients" type:@"permanent"];
        }];
        WaitForAllGroupsToBeEmpty(0.5);
        
        [self.userSession performChanges:^{
            [otherUser fetchUserClients];
        }];
        WaitForAllGroupsToBeEmpty(0.5);
        XCTAssertEqual(otherUser.clients.count, 2u);
        
        XCTAssertEqual(observer.notifications.count, 1u);
        ConversationChangeInfo *note = observer.notifications.firstObject;
        XCTAssertNotNil(note);
        XCTAssertTrue(note.securityLevelChanged);
        
        XCTAssertEqual(conversation.securityLevel, ZMConversationSecurityLevelSecureWithIgnored);
        
        ZMSystemMessage *lastMessage = [conversation.messages objectAtIndex:conversation.messages.count - 1];
        XCTAssertTrue([lastMessage isKindOfClass:[ZMSystemMessage class]]);
        
        XCTAssertEqual(lastMessage.systemMessageType, ZMSystemMessageTypeNewClient);
    }
    
    [observer clearNotifications];
    
    
    // (3) remove inserted client for user1
    {
        [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *__unused session) {
            [self.user1.clients removeObject:additionalUserClient];
        }];
        WaitForAllGroupsToBeEmpty(0.5);

        // when
        [self.userSession performChanges:^{
            [otherUser fetchUserClients];
        }];
        WaitForAllGroupsToBeEmpty(0.5);
        XCTAssertEqual(otherUser.clients.count, 1u);
        
        // then
        XCTAssertEqual(observer.notifications.count, 1u);
        ConversationChangeInfo *note = observer.notifications.firstObject;
        XCTAssertNotNil(note);
        XCTAssertTrue(note.securityLevelChanged);
        
        XCTAssertEqual(conversation.securityLevel, ZMConversationSecurityLevelSecure);
        
        ZMSystemMessage *lastMessage = [conversation.messages objectAtIndex:conversation.messages.count - 1];
        XCTAssertTrue([lastMessage isKindOfClass:[ZMSystemMessage class]]);
        
        XCTAssertEqual(lastMessage.systemMessageType, ZMSystemMessageTypeConversationIsSecure);
    }
}

- (void)testThatItDoesNotSetAllConversationsToSecureWhenTrustingSelfUserClients
{
    // given
    XCTAssertTrue([self login]);
    
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        [session registerClientForUser:self.selfUser label:@"self" type:@"permanent"];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    ZMConversation *conversation1 = [self conversationForMockConversation:self.selfToUser1Conversation];
    ZMConversation *conversation2 = [self conversationForMockConversation:self.selfToUser2Conversation];
    
    [self.userSession performChanges:^{
        [conversation1 appendText:@"Hey!" mentions:@[] fetchLinkPreview:NO nonce:[NSUUID createUUID]];
    }];
    WaitForAllGroupsToBeEmpty(0.5);

    ZMUser *selfUser = [self userForMockUser:self.selfUser];
    ZMUser *user1 = [self userForMockUser:self.user1];

    // when
    [self.userSession performChanges:^{
        for (UserClient *client in selfUser.clients){
            [selfUser.selfClient trustClient:client];
        }
        [selfUser.selfClient trustClient:user1.clients.anyObject];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(conversation1.securityLevel, ZMConversationSecurityLevelSecure);
    XCTAssertEqual(conversation2.securityLevel, ZMConversationSecurityLevelNotSecure);
}

- (void)testThatItDoesNotSetAllConversationsToSecureWhenDeletingATrustedSelfUserClients
{
    // given
    XCTAssertTrue([self login]);
    
    ZMConversation *conversation1 = [self conversationForMockConversation:self.selfToUser1Conversation];
    [self.userSession performChanges:^{
        // this will eventually create a session with user1.client
        [conversation1 appendText:@"Please establish session" mentions:@[] fetchLinkPreview:NO nonce:[NSUUID createUUID]];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        // this creates an extra client for self user
        [session registerClientForUser:self.selfUser label:@"self" type:@"permanent"];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    
    ZMUser *selfUser = [self userForMockUser:self.selfUser];
    XCTAssertEqual(selfUser.clients.count, 2u);
    UserClient *notSelfClient = [selfUser.clients.allObjects firstObjectMatchingWithBlock:^BOOL(UserClient *obj) {
       return obj.remoteIdentifier != selfUser.selfClient.remoteIdentifier;
    }];
    ZMUser *user1 = [self userForMockUser:self.user1];
    XCTAssertNotNil(notSelfClient);
    
    // when
    [self.userSession performChanges:^{
        [selfUser.selfClient trustClient:user1.clients.anyObject];
    }];
    WaitForAllGroupsToBeEmpty(1.0);
    
    [self.userSession performChanges:^{
        [self.userSession deleteClients:@[notSelfClient] withCredentials:[ZMEmailCredentials credentialsWithEmail:IntegrationTest.SelfUserEmail password:IntegrationTest.SelfUserPassword]];
    }];
    WaitForAllGroupsToBeEmpty(1.0);
    
    // then
    ZMConversation *conversation2 = [self conversationForMockConversation:self.selfToUser2Conversation];
    XCTAssertEqual(conversation1.securityLevel, ZMConversationSecurityLevelSecure);
    XCTAssertEqual(conversation2.securityLevel, ZMConversationSecurityLevelNotSecure);
}

- (void)testThatItDoesNotSendMessagesWhenThereAreIgnoredClients
{
    // given
    XCTAssertTrue([self login]);

    void (^secureConversationBlock)(ZMConversation *) = ^(ZMConversation *conversation) {
        // send a message to fetch all the missing client
        [self.userSession performChanges:^{
            [conversation appendText:[NSString stringWithFormat:@"Hey %lu", conversation.messages.count] mentions:@[] fetchLinkPreview:YES nonce:[NSUUID createUUID]];
        }];
        WaitForAllGroupsToBeEmpty(0.5);
        [self makeConversationSecured:conversation];
        
    };

    ZMConversation *conversation1 = [self conversationForMockConversation:self.selfToUser1Conversation];
    ZMConversation *conversation2 = [self conversationForMockConversation:self.selfToUser2Conversation];
    
    secureConversationBlock(conversation1);
    secureConversationBlock(conversation2);

    ZMUser *user1 = [self userForMockUser:self.user1];
    
    // add additional client for user1 remotely
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        [session registerClientForUser:self.user1 label:@"other user 1 clients" type:@"permanent"];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    [self.userSession performChanges:^{
        [user1 fetchUserClients];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    XCTAssertEqual(user1.clients.count, 2u);

    [self.mockTransportSession resetReceivedRequests];
    
    // send a message in the trusted conversation
    [self.userSession performChanges:^{
        [conversation2 appendMessageWithText:@"Hello"];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(self.mockTransportSession.receivedRequests.count, 1u);
    [self.mockTransportSession resetReceivedRequests];

    // and when sending a message in the not safe conversation
    [self.userSession performChanges:^{
        [conversation1 appendMessageWithText:@"Hello"];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(self.mockTransportSession.receivedRequests.count, 0u);
}

@end

#pragma mark - Unable to decrypt message
@implementation ConversationTestsOTR (UnableToDecrypt)


- (void)testThatItInsertsASystemMessageWhenItCanNotDecryptAMessage {
    
    // given
    XCTAssertTrue([self login]);
    ZMConversation *conversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    [self establishSessionWithMockUser:self.user1];
    
    // when
    [self performIgnoringZMLogError:^{
        [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> * __unused session) {
            [self.selfToUser1Conversation insertOTRMessageFromClient:self.user1.clients.anyObject
                                                            toClient:self.selfUser.clients.anyObject
                                                                data:[@"😱" dataUsingEncoding:NSUTF8StringEncoding]];
        }];

        WaitForAllGroupsToBeEmpty(5);
    }];
    
    // then
    id<ZMConversationMessage> lastMessage = conversation.messages.lastObject;
    XCTAssertEqual(conversation.messages.count, 2lu);
    XCTAssertNotNil(lastMessage.systemMessageData);
    XCTAssertEqual(lastMessage.systemMessageData.systemMessageType, ZMSystemMessageTypeDecryptionFailed);
}

- (void)testThatItNotifiesWhenInsertingCannotDecryptMessage {
    
    // given
    XCTAssertTrue([self login]);
    ZMConversation *conversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    [self establishSessionWithMockUser:self.user1];
    
    // expect
    XCTestExpectation *expectation = [self expectationWithDescription:@"It should call the observer"];
    
    id token = [NotificationInContext addObserverWithName:ZMConversation.failedToDecryptMessageNotificationName
                                       context:self.userSession.managedObjectContext.notificationContext
                                        object:nil
                                         queue:nil
                                         using:^(NotificationInContext * note) {
                                             XCTAssertEqualObjects(conversation.remoteIdentifier, [(ZMConversation *)note.object remoteIdentifier]);
                                             XCTAssertNotNil(note.userInfo[@"cause"]);
                                             XCTAssertEqualObjects(note.userInfo[@"cause"], @3);
                                             [expectation fulfill];
                                         }];
    
    // when
    [self performIgnoringZMLogError:^{
        [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> * __unused session) {
            [self.selfToUser1Conversation insertOTRMessageFromClient:self.user1.clients.anyObject
                                                            toClient:self.selfUser.clients.anyObject
                                                                data:[@"😱" dataUsingEncoding:NSUTF8StringEncoding]];
        }];

        WaitForAllGroupsToBeEmpty(0.5);
    }];
    
    XCTAssertTrue([self waitForCustomExpectationsWithTimeout:5]);
    
    // then
    token = nil;
}

- (void)testThatItDoesNotInsertsASystemMessageWhenItDecryptsADuplicatedMessage {
    
    // given
    XCTAssertTrue([self login]);
    ZMConversation *conversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    __block NSData* firstMessageData;
    NSString *firstMessageText = @"Testing duplication";
    MockUserClient *mockSelfClient = self.selfUser.clients.anyObject;
    MockUserClient *mockUser1Client = self.user1.clients.anyObject;
    
    // when sending the fist message
    ZMGenericMessage *firstMessage = [ZMGenericMessage messageWithContent:[ZMText textWith:firstMessageText mentions:@[] linkPreviews:@[]] nonce:NSUUID.createUUID];

    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> * __unused session) {
        
        firstMessageData = [MockUserClient encryptedWithData:firstMessage.data from:mockUser1Client to:mockSelfClient];
        [self.selfToUser1Conversation insertOTRMessageFromClient:mockUser1Client toClient:mockSelfClient data:firstMessageData];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    
    // then
    NSUInteger previousNumberOfMessages = conversation.messages.count;
    id<ZMConversationMessage> lastMessage = conversation.messages.lastObject;
    XCTAssertNil(lastMessage.systemMessageData);
    XCTAssertEqualObjects(lastMessage.textMessageData.messageText, firstMessageText);
    
    // log out
    [self recreateSessionManager];
    WaitForAllGroupsToBeEmpty(0.5);
    
    [self performIgnoringZMLogError:^{
        // and when resending the same data (CBox should return DUPLICATED error)
        [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> * __unused session) {
            [self.selfToUser1Conversation insertOTRMessageFromClient:mockUser1Client toClient:mockSelfClient data:firstMessageData];
        }];
        WaitForAllGroupsToBeEmpty(0.5);
    }];
    
    // then
    conversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    NSUInteger newNumberOfMessages = conversation.messages.count;

    lastMessage = conversation.messages.lastObject;
    XCTAssertNil(lastMessage.systemMessageData);
    XCTAssertEqualObjects(lastMessage.textMessageData.messageText, firstMessageText);
    XCTAssertEqual(newNumberOfMessages, previousNumberOfMessages);
}

@end
