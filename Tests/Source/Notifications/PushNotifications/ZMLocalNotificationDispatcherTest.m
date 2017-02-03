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
@import ZMCDataModel;

#import "MessagingTest.h"
#import "ZMLocalNotificationDispatcher+Testing.h"
#import "ZMLocalNotification.h"
#import "MessagingTest+EventFactory.h"
#import "UILocalNotification+UserInfo.h"
#import "zmessaging_iOS_Tests-Swift.h"

@interface ZMLocalNotificationDispatcherTest : MessagingTest
@property (nonatomic) ZMLocalNotificationDispatcher *sut;
@property (nonatomic) ZMConversation *conversation1;
@property (nonatomic) ZMConversation *conversation2;

@property (nonatomic) ZMUser *user1;
@property (nonatomic) ZMUser *user2;

@property (nonatomic) ZMUser *selfUser;
@property (nonatomic) id mockEventNotificationSet;
@property (nonatomic) id mockFailedNotificationSet;
@property (nonatomic) id mockMessageNotificationSet;

@end



@implementation ZMLocalNotificationDispatcherTest

- (void)setUp
{
    [super setUp];
    
    self.mockEventNotificationSet = [OCMockObject niceMockForClass:[ZMLocalNotificationSet class]];
    self.mockFailedNotificationSet = [OCMockObject niceMockForClass:[ZMLocalNotificationSet class]];
    self.mockMessageNotificationSet = [OCMockObject niceMockForClass:[ZMLocalNotificationSet class]];

    [self verifyMockLater:self.mockEventNotificationSet];
    [self verifyMockLater:self.mockFailedNotificationSet];
    
    self.sut = [[ZMLocalNotificationDispatcher alloc] initWithManagedObjectContext:self.syncMOC
                                                                 sharedApplication:self.application
                                                              eventNotificationSet:self.mockEventNotificationSet
                                                             failedNotificationSet:self.mockFailedNotificationSet
                                                              messageNotifications:nil
                                                              callingNotifications:nil];
    
    self.conversation1 = [self insertConversationWithRemoteID:[NSUUID createUUID] name:@"Conversation 1"];
    self.conversation2 = [self insertConversationWithRemoteID:[NSUUID createUUID] name:@"Conversation 2"];
    self.user1 = [self insertUserWithRemoteID:[NSUUID createUUID] name:@"User 1"];
    self.user2 = [self insertUserWithRemoteID:[NSUUID createUUID] name:@"User 2"];

    self.selfUser = [ZMUser selfUserInContext:self.syncMOC];
    self.selfUser.remoteIdentifier = [NSUUID createUUID];
    
    [self.conversation1 addParticipant:self.user1];
    [self.conversation2 addParticipant:self.user1];
    [self.conversation2 addParticipant:self.user2];
}

- (void)tearDown
{
    self.mockFailedNotificationSet = nil;
    self.mockEventNotificationSet = nil;
    self.mockMessageNotificationSet = nil;
    WaitForAllGroupsToBeEmpty(0.5);
    
    [self.sut tearDown];
    self.sut = nil;
    [super tearDown];
}

- (ZMConversation *)insertConversationWithRemoteID:(NSUUID *)uuid name:(NSString *)userDefinedName {
    __block ZMConversation *conversation;
    
    [self.syncMOC performGroupedBlockAndWait:^{
        conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        conversation.remoteIdentifier = uuid;
        conversation.userDefinedName = userDefinedName;
        conversation.conversationType =  ZMConversationTypeGroup;
        [self.syncMOC saveOrRollback];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    return conversation;
}

- (ZMUser *)insertUserWithRemoteID:(NSUUID *)uuid name:(NSString *)name
{
    __block ZMUser *user;
    [self.syncMOC performGroupedBlockAndWait:^{
        user = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        user.name = name;
        user.remoteIdentifier = uuid;
        
        [self.syncMOC saveOrRollback];
    }];
    
    return user;
}

- (NSMutableDictionary *)payloadForSelfUserJoiningCallInConversation:(ZMConversation *)conversation state:(NSString *)state
{
    NSUUID *convRemoteID = conversation.remoteIdentifier ?: [NSUUID createUUID];
    NSUUID *selfUserUUID = NSUUID.createUUID;
    
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMUser *selfUser = [ZMUser selfUserInContext:self.syncMOC];
        selfUser.remoteIdentifier = selfUserUUID;
        [self.syncMOC saveOrRollback];
    }];
    
    [self.uiMOC saveOrRollback];
    WaitForAllGroupsToBeEmpty(0.5);
    
    return [@{
              @"type": @"call.state",
              @"conversation": convRemoteID,
              @"self" :@{},
              @"participants": @{selfUserUUID.transportString: @{@"state": state}},
              } mutableCopy];
}


@end

@implementation ZMLocalNotificationDispatcherTest (Tests)

- (void)testThatItCreatesNotificationFromMessages
{
    // given
    ZMClientMessage *message = (id)[self.conversation1 appendMessageWithText:@"foo"];
    message.sender = self.user1;
    
    // when
    [self.sut processMessage:message];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(self.application.scheduledLocalNotifications.count, 1u);
    UILocalNotification *scheduledNotification = self.application.scheduledLocalNotifications.firstObject;
    XCTAssertNotNil(scheduledNotification);
}


- (void)testThatItAddsNotificationsOfDifferentConversationsToTheList
{
    // given
    ZMClientMessage *message1 = (id)[self.conversation1 appendMessageWithText:@"foo"];
    message1.sender = self.user1;
    ZMClientMessage *message2 = (id)[self.conversation2 appendMessageWithText:@"bar"];
    message2.sender = self.user1;

    // when
    [self.sut processMessage:message1];
    [self.sut processMessage:message2];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(self.application.scheduledLocalNotifications.count, 2u);
    UILocalNotification *notification1 = self.application.scheduledLocalNotifications.firstObject;
    UILocalNotification *notification2 = self.application.scheduledLocalNotifications.lastObject;
    XCTAssertNotNil(notification1);
    XCTAssertNotNil(notification2);
    XCTAssertEqualObjects([notification1 conversationInManagedObjectContext:self.syncMOC], self.conversation1);
    XCTAssertEqualObjects([notification2 conversationInManagedObjectContext:self.syncMOC], self.conversation2);

}

- (void)testThatItDoesNotCreateANotificationForAnUnsupportedEventType
{
    // given
    ZMUpdateEvent *event = [self eventWithPayload:nil inConversation:self.conversation1 type:EventConversationTyping];
    XCTAssertNotNil(event);
    
    // when
    [self.sut didReceiveUpdateEvents:@[event] conversationMap:nil notificationID:NSUUID.createUUID];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(self.application.scheduledLocalNotifications.count, 0u);
}

- (void)testThatItDoesNotCancelNotificationsForCallStateSelfUserIdleEvents
{
    // given
    ZMUpdateEvent *callEvent = [self callStateEventInConversation:self.conversation2 joinedUsers:@[self.user1] videoSendingUsers:@[] sequence:@1 session:@"session1"];
    ZMUpdateEvent *selfUserDoesNotJoinCallEvent = [self callStateEventInConversation:self.conversation2 joinedUsers:@[self.user1, self.user2] videoSendingUsers:@[] sequence:@2 session:@"session1"];
    
    // expect
    [self.sut didReceiveUpdateEvents:@[callEvent] conversationMap:nil notificationID:NSUUID.createUUID];

    WaitForAllGroupsToBeEmpty(0.5);
    
    [[self.conversation2 mutableOrderedSetValueForKey:@"callParticipants"] addObject:self.user1];

    // when
    [self.sut didReceiveUpdateEvents:@[selfUserDoesNotJoinCallEvent] conversationMap:nil notificationID:NSUUID.createUUID];
    WaitForAllGroupsToBeEmpty(0.5);

    // then
    XCTAssertEqual(self.application.scheduledLocalNotifications.count, 1u);
    UILocalNotification *scheduledNotification1 = self.application.scheduledLocalNotifications.firstObject;
    XCTAssertEqualObjects([scheduledNotification1 conversationInManagedObjectContext:self.syncMOC], self.conversation2);
}

- (void)testThatItCancelsNotificationsWhenReceivingANotificationThatTheCallWasIgnored
{
    // given
    ZMUpdateEvent *callEvent = [self callStateEventInConversation:self.conversation2 joinedUsers:@[self.user1] videoSendingUsers:@[] sequence:@1 session:@"session1"];
    self.conversation2.isIgnoringCall = YES;
    
    [self.sut didReceiveUpdateEvents:@[callEvent] conversationMap:nil notificationID:NSUUID.createUUID];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // expect
    [[self.mockEventNotificationSet expect] cancelNotificationForIncomingCall:self.conversation2];
    [self expectationForNotification:ZMConversationCancelNotificationForIncomingCallNotificationName object:nil handler:^BOOL(NSNotification * _Nonnull notification) {
        return (notification.object == self.conversation2 );
    }];
    
    // when
    [[NSNotificationCenter defaultCenter] postNotificationName:ZMConversationCancelNotificationForIncomingCallNotificationName object:self.conversation2];
    XCTAssert([self waitForCustomExpectationsWithTimeout:0.5]);
    WaitForAllGroupsToBeEmpty(0.5);

    // then
    XCTAssertEqual(self.application.scheduledLocalNotifications.count, 1u);
    [self.mockEventNotificationSet verify];
}

- (void)testThatWhenFailingAMessageItSchedulesANotification
{
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        ZMMessage *message = [ZMMessage insertNewObjectInManagedObjectContext:self.syncMOC];
        [self.conversation1.mutableMessages addObject:message];
        UILocalNotification *note = (id) @"foo";
        
        id mockLocalNote = [OCMockObject niceMockForClass:ZMLocalNotificationForExpiredMessage.class];
        
        //expect
        [[[[mockLocalNote expect] classMethod] andReturn:mockLocalNote] alloc];
        (void) [[[mockLocalNote expect] andReturn:mockLocalNote] initWithExpiredMessage:message];
        [[[mockLocalNote stub] andReturn:note] uiNotification];
        [(ZMLocalNotificationSet *)[self.mockFailedNotificationSet expect] addObject:mockLocalNote];
        
        // when
        [self.sut didFailToSentMessage:message];
        
        // then
        XCTAssertEqual(self.application.scheduledLocalNotifications.count, 1u);
        [mockLocalNote verify];
        [self.mockFailedNotificationSet verify];
        [mockLocalNote stopMocking];
        
    }];
}

- (void)testThatItCancelsAllNotificationsForFailingMessagesWhenCancelingAllNotifications
{
    // expect
    [[self.mockFailedNotificationSet expect] cancelAllNotifications];
    [[self.mockEventNotificationSet expect] cancelAllNotifications];
    
    // when
    [self.sut cancelAllNotifications];
    
    // then
    [self.mockFailedNotificationSet verify];
    [self.mockEventNotificationSet verify];
}


- (void)testThatItCancelsNotificationsForFailingMessagesWhenCancelingNotificationsForASpecificConversation
{
    // expect
    [[self.mockFailedNotificationSet expect] cancelNotifications:self.conversation1];
    [[self.mockFailedNotificationSet reject] cancelNotifications:self.conversation2];

    [[self.mockEventNotificationSet expect] cancelNotifications:self.conversation1];
    [[self.mockEventNotificationSet reject] cancelNotifications:self.conversation2];

    // when
    [self.sut cancelNotificationForConversation:self.conversation1];
    
    // then
    [self.mockFailedNotificationSet verify];
    [self.mockEventNotificationSet verify];
}

- (NSDictionary *)payloadForEncryptedOTRMessageWithText:(NSString *)text nonce:(NSUUID *)nonce
{
    ZMGenericMessage *message = [ZMGenericMessage messageWithText:text nonce:nonce.transportString expiresAfter:nil];
    return [self payloadForOTRMessageWithGenericMessage:message];
}

- (NSDictionary *)payloadForOTRAssetWithGenericMessage:(ZMGenericMessage *)genericMessage
{
    return @{@"data": @{ @"info": genericMessage.data.base64String },
             @"conversation" : self.conversation1.remoteIdentifier.transportString,
             @"type": EventConversationAddOTRAsset,
             @"from": self.user1.remoteIdentifier.transportString,
             @"time": [NSDate date].transportString
             };
}

- (NSDictionary *)payloadForOTRMessageWithGenericMessage:(ZMGenericMessage *)genericMessage
{
    return @{@"data": @{ @"text": genericMessage.data.base64String },
             @"conversation" : self.conversation1.remoteIdentifier.transportString,
             @"type": EventConversationAddOTRMessage,
             @"from": self.user1.remoteIdentifier.transportString,
             @"time": [NSDate date].transportString
             };
}

- (void)testThatItCancelsReadNotificationsIfTheLastReadChanges
{
    // given
    [[self.mockFailedNotificationSet expect] cancelNotifications:self.conversation1];
    [[self.mockEventNotificationSet expect] cancelNotifications:self.conversation1];

    // when
    [self.conversation1 updateLastReadServerTimeStampIfNeededWithTimeStamp:[NSDate date] andSync:NO];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    [self.mockEventNotificationSet verify];
    [self.mockFailedNotificationSet verify];
}

- (void)testThatItSchedulesADefaultNotificationIfContentShouldNotBeVisible;
{
    [self.syncMOC setPersistentStoreMetadata:@(YES) forKey:ZMShouldHideNotificationContentKey];
    [self.syncMOC saveOrRollback];
    // given
    ZMClientMessage *message = (id)[self.conversation1 appendMessageWithText:@"foo"];
    message.sender = self.user1;

    //when
    [self.sut processMessage:message];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(self.application.scheduledLocalNotifications.count, 1u);
    UILocalNotification *scheduledNotification = self.application.scheduledLocalNotifications.firstObject;
    XCTAssertEqualObjects(scheduledNotification.alertBody, [ZMPushStringDefault localizedString]);
    XCTAssertEqualObjects(scheduledNotification.soundName, @"new_message_apns.caf");

}

- (void)testThatItDoesNotCreateNotificationForTwoMessageEventsWithTheSameNonce
{
    ZMLocalNotificationSet *localNotificationSet = [[ZMLocalNotificationSet alloc] initWithApplication:self.application
                                                                                          archivingKey:@"ZMLocalNotificationDispatcherEventNotificationsKey"
                                                                                         keyValueStore:[OCMockObject niceMockForProtocol:@protocol(ZMSynchonizableKeyValueStore)]];
    
    // Replace the default sut since we need a real ZMLocalNotificationSet
    [self.sut tearDown];
    self.sut = [[ZMLocalNotificationDispatcher alloc] initWithManagedObjectContext:self.syncMOC
                                                                 sharedApplication:self.application
                                                              eventNotificationSet:self.mockEventNotificationSet
                                                             failedNotificationSet:self.mockFailedNotificationSet
                                                              messageNotifications:localNotificationSet
                                                            callingNotifications:nil];
    
    // given
    ZMClientMessage *message = (id)[self.conversation1 appendMessageWithText:@"foo"];
    message.sender = self.user1;
    
    // when
    [self.sut processMessage:message];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(localNotificationSet.notifications.count, 1u);
    XCTAssertEqual(self.application.scheduledLocalNotifications.count, 1u);

    // when
    [self.sut processMessage:message];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(localNotificationSet.notifications.count, 1u);
    XCTAssertEqual(self.application.scheduledLocalNotifications.count, 1u);
}

- (void)testThatItDoesNotCreateNotificationForFileUploadEventsWithTheSameNonce
{
    // given
    ZMLocalNotificationSet *localNotificationSet = [[ZMLocalNotificationSet alloc] initWithApplication:self.application
                                                                                          archivingKey:@"ZMLocalNotificationDispatcherEventNotificationsKey"
                                                                                         keyValueStore:[OCMockObject niceMockForProtocol:@protocol(ZMSynchonizableKeyValueStore)]];
    
    NSURL *url = [[NSBundle bundleForClass:self.class] URLForResource:@"video" withExtension:@"mp4"];
    ZMAudioMetadata *audioMetadata = [[ZMAudioMetadata alloc] initWithFileURL:url duration:100 normalizedLoudness:@[] thumbnail:nil];
    ZMAssetClientMessage *message = (id)[self.conversation1 appendMessageWithFileMetadata:audioMetadata];
    message.sender = self.user1;
    
    // Replace the default sut since we need a real ZMLocalNotificationSet
    [self.sut tearDown];
    self.sut = [[ZMLocalNotificationDispatcher alloc] initWithManagedObjectContext:self.syncMOC
                                                                 sharedApplication:self.application
                                                              eventNotificationSet:self.mockEventNotificationSet
                                                             failedNotificationSet:self.mockFailedNotificationSet
                                                              messageNotifications:localNotificationSet
                                                              callingNotifications:nil];
    
    // when
    [self.sut processMessage:message];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(localNotificationSet.notifications.count, 1u);
    XCTAssertEqual(self.application.scheduledLocalNotifications.count, 1u);
    
    // when
    [self.sut processMessage:message];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(localNotificationSet.notifications.count, 1u);
    XCTAssertEqual(self.application.scheduledLocalNotifications.count, 1u);
}

@end
