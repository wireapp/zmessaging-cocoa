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
@import WireSyncEngine;

#import "ZMUserSession.h"
#import "ZMUserSession+Internal.h"
#import "ZMOperationLoop+Private.h"
#import "ZMSyncStrategy.h"
#import "WireSyncEngine_iOS_Tests-Swift.h"


@interface APNSTests : IntegrationTest

@end

@implementation APNSTests

- (void)setUp
{
    [super setUp];
    
    [self createSelfUserAndConversation];
    [self createExtraUsersAndConversations];
}

- (void)testThatAConversationIsCreatedFromAnAPNS
{
    // given
    XCTAssertTrue([self login]);
    
    [self closePushChannelAndWaitUntilClosed]; // do not use websocket
    
    NSString *conversationName = @"MYCONVO";
    __block NSString *conversationID;
    WaitForAllGroupsToBeEmpty(0.2);
    __block NSDictionary *conversationTransportData;
    
    ZMConversationList *conversationsList = [ZMConversationList conversationsInUserSession:self.userSession];
    NSUInteger oldCount = conversationsList.count;
    
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        MockConversation *conversation = [session insertGroupConversationWithSelfUser:self.selfUser otherUsers:@[self.user1]];
        [conversation changeNameByUser:self.selfUser name:conversationName];
        conversationID = conversation.identifier;
        conversationTransportData = (NSDictionary *)conversation.transportData;
    }];
    WaitForAllGroupsToBeEmpty(0.2);
        
    [self.application setBackground];
    
    // when
    [self.userSession receivedPushNotificationWith:[self noticePayloadForLastEvent] from:ZMPushNotficationTypeVoIP completion:nil];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    ZMConversationList *convs = [ZMConversationList conversationsInUserSession:self.userSession];
    XCTAssertEqual(convs.count, oldCount+1);
    NSUInteger index = [conversationsList indexOfObjectPassingTest:^BOOL(ZMConversation *conversation, NSUInteger idx, BOOL *stop) {
        NOT_USED(idx);
        NOT_USED(stop);
        return [conversation.displayName isEqualToString:conversationName];
    }];
    XCTAssertNotEqual(index, (NSUInteger) NSNotFound);
    
}


- (BOOL)registerForPushNotificationsWithToken:(NSData *)token
{
    [self.sessionManager didRegisteredForRemoteNotificationsWith:token];
    [self.mockTransportSession resetReceivedRequests];
    [self.userSession performChanges:^{
        [self.userSession setPushToken:token];
        [self.userSession setPushKitToken:token];
        [self.userSession.managedObjectContext forceSaveOrRollback];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    return [self lastRequestsContainedTokenRequests];
}

- (BOOL)lastRequestsContainedTokenRequests
{
    BOOL didContainVOIPRequest = NO;
    BOOL didContainRemoteRequest = NO;
    for (ZMTransportRequest *aRequest in self.mockTransportSession.receivedRequests) {
        if (![aRequest.path isEqualToString: @"/push/tokens"]) {
            continue;
        }
        NSString *transportType = aRequest.payload.asDictionary[@"transport"];
        if ([transportType isEqualToString:@"APNS_VOIP"]) {
            didContainVOIPRequest = YES;
        }
        if ([transportType isEqualToString:@"APNS"]) {
            didContainRemoteRequest = YES;
        }
    }
    return (didContainRemoteRequest && didContainVOIPRequest);
}

- (void)testThatItUpdatesNewTokensIfNeeded
{
    XCTAssertTrue([self login]);
    
    // given
    NSData *token = [NSData dataWithBytes:@"abc" length:3];
    NSData *newToken = [NSData dataWithBytes:@"def" length:6];
    
    XCTAssertTrue([self registerForPushNotificationsWithToken:token]);
    [self.mockTransportSession resetReceivedRequests];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // expect
    ZM_WEAK(self);
    self.application.registerForRemoteNotificationsCallback = ^{
        ZM_STRONG(self);
        [self.userSession performChanges:^{
            [self.userSession updatePushKitTokenTo:newToken forType:PushTokenTypeVoip];
            [self.userSession updatePushKitTokenTo:newToken forType:PushTokenTypeRegular];
        }];
    };
    
    // expect
    id mockPushRegistrant = [OCMockObject niceMockForClass:ZMPushRegistrant.class];
    [(ZMPushRegistrant *)[[mockPushRegistrant expect] andReturn:newToken] pushToken];

    [[[mockPushRegistrant stub] andReturn:mockPushRegistrant] alloc];
    (void)[[[mockPushRegistrant stub] andReturn:mockPushRegistrant] initWithDidUpdateCredentials:OCMOCK_ANY
                                                                               didReceivePayload:OCMOCK_ANY
                                                                              didInvalidateToken:OCMOCK_ANY];

    // when
    [self recreateSessionManager];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertTrue([self lastRequestsContainedTokenRequests], @"Did receive: %@", self.mockTransportSession.receivedRequests);
    XCTAssertEqual(self.application.registerForRemoteNotificationCount, 2);
    [mockPushRegistrant stopMocking];
}

- (void)testThatItReregistersPushTokensOnDemand
{
    XCTAssertTrue([self login]);
    
    // given
    NSData *token = [NSData dataWithBytes:@"abc" length:3];
    NSData *newToken = [NSData dataWithBytes:@"def" length:6];
    
    // when
    XCTAssertTrue([self registerForPushNotificationsWithToken:token]);
    
    // then
    ZMTransportRequest *request = self.mockTransportSession.receivedRequests.lastObject;
    XCTAssertEqualObjects(request.path, @"/push/tokens");
    [self.mockTransportSession resetReceivedRequests];
    
    // expect
    ZM_WEAK(self);
    self.application.registerForRemoteNotificationsCallback = ^{
        ZM_STRONG(self);
        [self.userSession performChanges:^{
            [self.userSession updatePushKitTokenTo:newToken forType:PushTokenTypeVoip];
            [self.userSession updatePushKitTokenTo:newToken forType:PushTokenTypeRegular];
        }];
    };
    
    // when
    [self.userSession resetPushTokens];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    BOOL didContainSignalingKeyRequest = NO;
    XCTAssertEqual(self.mockTransportSession.receivedRequests.count, 3u);
    for (ZMTransportRequest *aRequest in self.mockTransportSession.receivedRequests) {
        if ([aRequest.path containsString:@"/clients/"] && [aRequest.payload asDictionary][@"sigkeys"] != nil) {
            didContainSignalingKeyRequest = YES;
        }
    }
    XCTAssertTrue(didContainSignalingKeyRequest);
    XCTAssertTrue([self lastRequestsContainedTokenRequests]);
    XCTAssertEqual(self.application.registerForRemoteNotificationCount, 2);
}

- (void)testThatItDoesNotReregistersPushTokensOnDemandIfItsNotChanged
{
    XCTAssertTrue([self login]);
    
    // given
    NSData *token = [NSData dataWithBytes:@"abc" length:3];
    
    XCTAssertTrue([self registerForPushNotificationsWithToken:token]);
    [self.mockTransportSession resetReceivedRequests];
    
    // expect
    ZM_WEAK(self);
    self.application.registerForRemoteNotificationsCallback = ^{
        ZM_STRONG(self);
        [self.userSession performChanges:^{
            [self.userSession updatePushKitTokenTo:token forType:PushTokenTypeVoip];
        }];
    };
    
    // when
    [self.userSession performChanges:^{
        [self.userSession resetPushTokens];
    }];
    WaitForAllGroupsToBeEmpty(1.0);
    
    // then
    BOOL didContainSignalingKeyRequest = NO;
    XCTAssertEqual(self.mockTransportSession.receivedRequests.count, 1u);
    for (ZMTransportRequest *aRequest in self.mockTransportSession.receivedRequests) {
        if ([aRequest.path containsString:@"/clients/"] && [aRequest.payload asDictionary][@"sigkeys"] != nil) {
            didContainSignalingKeyRequest = YES;
        }
    }
    XCTAssertTrue(didContainSignalingKeyRequest);
    XCTAssertFalse([self lastRequestsContainedTokenRequests]);
    XCTAssertEqual(self.application.registerForRemoteNotificationCount, 2);
}

- (void)testThatItFetchesTheNotificationStreamWhenReceivingNotificationOfTypeNotice
{
    XCTAssertTrue([self login]);
    
    [self closePushChannelAndWaitUntilClosed]; // do not use websocket
    
    ZMUser *selfUser = [self userForMockUser:self.selfUser];
    XCTAssertEqual(selfUser.clients.count, 1u);

    __block NSDictionary *conversationTransportData;
    
    __block NSString *convIdentifier;
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        MockConversation *conversation = [session insertGroupConversationWithSelfUser:self.selfUser otherUsers:@[self.user1]];
        conversationTransportData = (NSDictionary *)conversation.transportData;
        convIdentifier = conversation.identifier;
    }];
    WaitForAllGroupsToBeEmpty(0.2);
    NSUUID *notificationID = NSUUID.timeBasedUUID;
    NSUUID *conversationID = [NSUUID uuidWithTransportString:convIdentifier];
    
    NSDictionary *eventPayload = [self conversationCreatePayloadWithNotificationID:notificationID
                                                                    conversationID:convIdentifier
                                                                     transportData:conversationTransportData
                                                                          senderID:self.user1.identifier];
    NSDictionary *notificationStreamPayload = [self notificationStreamPayloadWithNotifications:@[eventPayload]];
    NSDictionary *noticePayload = [self noticePayloadWithIdentifier:notificationID];

    [self.application setBackground];
    
    // when
    XCTestExpectation *fetchingExpectation = [self expectationWithDescription:@"fetching notification"];
    NSUUID *lastNotificationId = self.userSession.syncManagedObjectContext.zm_lastNotificationID;

    self.mockTransportSession.responseGeneratorBlock = ^ZMTransportResponse *(ZMTransportRequest *request) {
        NSString *path = [NSString stringWithFormat:@"/notifications?size=500&since=%@&client=%@", lastNotificationId.transportString ,selfUser.selfClient.remoteIdentifier];
        if ([request.path isEqualToString:path] && request.method == ZMMethodGET) {
            [fetchingExpectation fulfill];
            return [ZMTransportResponse responseWithPayload:notificationStreamPayload HTTPStatus:200 transportSessionError:nil];
        };
        return nil;
    };
    
    [self.mockTransportSession resetReceivedRequests];
    NSDictionary *apnsPayload = noticePayload;
    [self.userSession receivedPushNotificationWith:apnsPayload from:ZMPushNotficationTypeVoIP completion:nil];
    
    XCTAssert([self waitForCustomExpectationsWithTimeout:0.5]);
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    ZMConversation *conversation = [ZMConversation fetchObjectWithRemoteIdentifier:conversationID inManagedObjectContext:self.userSession.managedObjectContext];
    XCTAssertNotNil(conversation);
}

- (void)testThatItFetchesTheNotificationStreamWhenReceivingNotificationOfTypeNotice_TriesAgainWhenReceiving_401
{
    XCTAssertTrue([self login]);
    
    [self closePushChannelAndWaitUntilClosed]; // do not use websocket
    
    ZMUser *selfUser = [self userForMockUser:self.selfUser];
    XCTAssertEqual(selfUser.clients.count, 1u);
    
    __block NSDictionary *conversationTransportData;
    
    __block NSString *convIdentifier;
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        MockConversation *conversation = [session insertGroupConversationWithSelfUser:self.selfUser otherUsers:@[self.user1]];
        conversationTransportData = (NSDictionary *)conversation.transportData;
        convIdentifier = conversation.identifier;
    }];
    WaitForAllGroupsToBeEmpty(0.2);
    NSUUID *notificationID = NSUUID.timeBasedUUID;
    NSUUID *conversationID = [NSUUID uuidWithTransportString:convIdentifier];
    
    NSDictionary *eventPayload = [self conversationCreatePayloadWithNotificationID:notificationID
                                                                    conversationID:convIdentifier
                                                                     transportData:conversationTransportData
                                                                          senderID:self.user1.identifier];
    NSDictionary *notificationStreamPayload = [self notificationStreamPayloadWithNotifications:@[eventPayload]];
    NSDictionary *noticePayload = [self noticePayloadWithIdentifier:notificationID];

    [self.application setBackground];
    
    // when
    XCTestExpectation *fetchingExpectation = [self expectationWithDescription:@"fetching notification"];
    
    __block NSUInteger requestCount = 0;
    NSUUID *lastNotificationId = self.userSession.syncManagedObjectContext.zm_lastNotificationID;
    self.mockTransportSession.responseGeneratorBlock = ^ZMTransportResponse *(ZMTransportRequest *request) {
        NSString *path = [NSString stringWithFormat:@"/notifications?size=500&since=%@&client=%@", lastNotificationId.transportString, selfUser.selfClient.remoteIdentifier];
        if ([request.path isEqualToString:path] && request.method == ZMMethodGET) {
            if (++requestCount == 2) {
                [fetchingExpectation fulfill];
                return [ZMTransportResponse responseWithPayload:notificationStreamPayload HTTPStatus:200 transportSessionError:nil];
            } else {
                return [ZMTransportResponse responseWithTransportSessionError:NSError.tryAgainLaterError];
            }
        };
        return nil;
    };
    
    [self.mockTransportSession resetReceivedRequests];
    NSDictionary *apnsPayload = noticePayload;
    [self.userSession receivedPushNotificationWith:apnsPayload from:ZMPushNotficationTypeVoIP completion:nil];
    XCTAssert([self waitForCustomExpectationsWithTimeout:0.5]);
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(requestCount, 2lu);
    ZMConversation *conversation = [ZMConversation fetchObjectWithRemoteIdentifier:conversationID inManagedObjectContext:self.userSession.managedObjectContext];
    XCTAssertNotNil(conversation);
}

- (void)testThatItSendsAConfirmationMessageWhenReceivingATextMessage
{
    if (BackgroundAPNSConfirmationStatus.sendDeliveryReceipts) {
        // given
        XCTAssertTrue([self login]);

        ZMGenericMessage *textMessage = [ZMGenericMessage messageWithText:@"Hello" nonce:[NSUUID createUUID].transportString expiresAfter:nil];
        
        [self closePushChannelAndWaitUntilClosed]; // do not use websocket
        
        __block MockEvent *event;
        [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
            // insert message on "backend"
            event = [self.selfToUser1Conversation encryptAndInsertDataFromClient:self.user1.clients.anyObject toClient:self.selfUser.clients.anyObject data:textMessage.data];
            
            // register new client
            [session registerClientForUser:self.user1 label:@"foobar" type:@"permanent"];
        }];
        WaitForAllGroupsToBeEmpty(0.2);
        
        [self.application setBackground];
        [self.application simulateApplicationDidEnterBackground];
        WaitForAllGroupsToBeEmpty(0.2);
        
        XCTestExpectation *confirmationExpectation = [self expectationWithDescription:@"Did send confirmation"];
        XCTestExpectation *missingClientsExpectation = [self expectationWithDescription:@"Did fetch missing client"];
        __block NSUInteger requestCount = 0;
        
        ZM_WEAK(self);
        self.mockTransportSession.responseGeneratorBlock = ^ZMTransportResponse *(ZMTransportRequest *request) {
            ZM_STRONG(self);
            NSString *confirmationPath = [NSString stringWithFormat:@"/conversations/%@/otr/messages?report_missing=", self.selfToUser1Conversation.identifier];
            if ([request.path hasPrefix:confirmationPath] && request.method == ZMMethodPOST) {
                XCTAssertTrue(request.shouldUseVoipSession);
                requestCount++;
                if (requestCount == 2) {
                    [confirmationExpectation fulfill];
                }
            }
            NSString *clientsPath = [NSString stringWithFormat:@"/users/prekeys"];
            if ([request.path isEqualToString:clientsPath]) {
                XCTAssertTrue(request.shouldUseVoipSession);
                XCTAssertEqual(requestCount, 1u);
                [missingClientsExpectation fulfill];
            }
            return nil;
        };
        
        // when
        [self.userSession receivedPushNotificationWith:[self noticePayloadForLastEvent] from:ZMPushNotficationTypeVoIP completion:nil];
        XCTAssert([self waitForCustomExpectationsWithTimeout:0.5]);
        WaitForAllGroupsToBeEmpty(0.2);
    }
}


#pragma mark - Helper

- (NSDictionary *)conversationCreatePayloadWithNotificationID:(NSUUID *)notificationID
                                               conversationID:(NSString *)conversationID
                                                transportData:(NSDictionary *)transportData
                                                     senderID:(NSString *)senderID
{
    return @{
             @"id" :notificationID.transportString,
             @"payload" : @[
                     @{
                         @"conversation" : conversationID,
                         @"data" : transportData,
                         @"from" : senderID,
                         @"time" : @"2015-03-11T09:34:00.436Z",
                         @"type" : @"conversation.create"
                         }
                     ]
             };
}

- (NSDictionary *)notificationStreamPayloadWithNotifications:(NSArray <NSDictionary *>*)notifications
{
    return @{
             @"notifications": notifications,
             @"hasMore": @NO
             };
}

- (NSDictionary *)noticePayloadForLastEvent
{
    ZMUpdateEvent *lastEvent = self.mockTransportSession.updateEvents.lastObject;
    return [self noticePayloadWithIdentifier:lastEvent.uuid];
}

- (NSDictionary *)noticePayloadWithIdentifier:(NSUUID *)uuid
{
    return @{
             @"aps" : @{},
             @"data" : @{
                     @"data" : @{ @"id" : uuid.transportString },
                     @"type" : @"notice"
                     }
             };
}

- (NSDictionary *)APNSPayloadForNotificationPayload:(NSDictionary *)notificationPayload identifier:(NSUUID *)identifier {
    
    return @{ @"aps" :
                  @{
                      @"content-available" : @(1)
                      },
              @"data" :
                  @{
                      @"type": @"plain",
                      @"data": @{
                              @"id" : identifier ? identifier.transportString : @"bf96c4ce-c7d1-11e4-8001-22000a5a00c8",
                              @"payload" : @[notificationPayload],
                              @"transient" : @(0)
                              }
                      }
              };
    
}


- (NSDictionary *)APNSPayloadForNotificationPayload:(NSDictionary *)notificationPayload {
    
    return [self APNSPayloadForNotificationPayload:notificationPayload identifier:nil];
    
}

- (void)closePushChannelAndWaitUntilClosed
{
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        session.pushChannel.keepOpen = NO;
        [session simulatePushChannelClosed];
    }];
    WaitForAllGroupsToBeEmpty(0.2);
}

@end
