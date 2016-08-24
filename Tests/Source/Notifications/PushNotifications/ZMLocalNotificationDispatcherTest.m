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
#import "ZMBadge.h"
#import "MessagingTest+EventFactory.h"
#import "UILocalNotification+UserInfo.h"

@interface ZMLocalNotificationDispatcherTest : MessagingTest
@property (nonatomic) ZMLocalNotificationDispatcher *sut;
@property (nonatomic) ZMConversation *conversation1;
@property (nonatomic) ZMConversation *conversation2;

@property (nonatomic) ZMUser *user1;
@property (nonatomic) ZMUser *user2;

@property (nonatomic) ZMUser *selfUser;
@property (nonatomic) id mockUISharedApplication;
@property (nonatomic) id mockEventNotificationSet;
@property (nonatomic) id mockFailedNotificationSet;

@end



@implementation ZMLocalNotificationDispatcherTest

- (void)setUp
{
    [super setUp];
    
    self.mockUISharedApplication = [OCMockObject mockForClass:UIApplication.class];
    [[[self.mockUISharedApplication stub] andReturnValue:@(UIApplicationStateBackground)] applicationState];
    [self verifyMockLater:self.mockUISharedApplication];
    self.mockEventNotificationSet = [OCMockObject niceMockForClass:[ZMLocalNotificationSet class]];
    self.mockFailedNotificationSet = [OCMockObject niceMockForClass:[ZMLocalNotificationSet class]];
    [self verifyMockLater:self.mockEventNotificationSet];
    [self verifyMockLater:self.mockFailedNotificationSet];
    
    self.sut = [[ZMLocalNotificationDispatcher alloc] initWithManagedObjectContext:self.syncMOC
                                                                 sharedApplication:self.mockUISharedApplication
                                                              eventNotificationSet:self.mockEventNotificationSet
                                                             failedNotificationSet:self.mockFailedNotificationSet];
    
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
    [self.syncMOC zm_tearDownCallTimer];
    [self.mockUISharedApplication stopMocking];
    self.mockUISharedApplication = nil;
    self.mockFailedNotificationSet = nil;
    self.mockEventNotificationSet = nil;
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

- (void)testThatItCreatesNotifications
{
    // given
    NSDictionary *data = @{@"content" : @"hallo"};
    ZMUpdateEvent *event = [self eventWithPayload:data inConversation:self.conversation1 type:EventConversationAdd];
    
    // expect
    __block UILocalNotification *scheduledNotification;
    [[self.mockUISharedApplication expect] scheduleLocalNotification:ZM_ARG_SAVE(scheduledNotification)];
    
    // when
    [self.sut didReceiveUpdateEvents:@[event] notificationID:NSUUID.createUUID];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertNotNil(scheduledNotification);
    
    // after
    [[self.mockUISharedApplication stub] cancelLocalNotification:OCMOCK_ANY];
}


- (void)testThatItAddsNotificationsOfDifferentConversationsToTheList
{
    // given
    NSDictionary *data = @{@"content" : @"hallo"};
    
    ZMUpdateEvent *event1 = [self eventWithPayload:data inConversation:self.conversation1 type:EventConversationAdd];
    ZMUpdateEvent *event2 = [self eventWithPayload:data inConversation:self.conversation2 type:EventConversationAdd];

    // expect
    __block UILocalNotification *notification1;
    __block UILocalNotification *notification2;
    [[self.mockUISharedApplication expect] scheduleLocalNotification:ZM_ARG_SAVE(notification1)];
    [[self.mockUISharedApplication expect] scheduleLocalNotification:ZM_ARG_SAVE(notification2)];
    
    // when
    [self.sut didReceiveUpdateEvents:@[event1,event2] notificationID:NSUUID.createUUID];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertNotNil(notification1);
    XCTAssertNotNil(notification2);
    XCTAssertEqualObjects([notification1 conversationInManagedObjectContext:self.syncMOC], self.conversation1);
    XCTAssertEqualObjects([notification2 conversationInManagedObjectContext:self.syncMOC], self.conversation2);
    
    // after (teardown)
    [[self.mockUISharedApplication stub] cancelLocalNotification:OCMOCK_ANY];
}

- (void)testThatItDoesNotCreateANotificationForAnUnsupportedEventType
{
    // given
    ZMUpdateEvent *event = [self eventWithPayload:nil inConversation:self.conversation1 type:EventConversationTyping];
    XCTAssertNotNil(event);
    
    // expect
    [[self.mockUISharedApplication reject] scheduleLocalNotification:OCMOCK_ANY];
    
    // when
    [self.sut didReceiveUpdateEvents:@[event] notificationID:NSUUID.createUUID];
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatItDoesNotCancelNotificationsForCallStateSelfUserIdleEvents
{
    // given
    ZMUpdateEvent *callEvent = [self callStateEventInConversation:self.conversation2 joinedUsers:@[self.user1] videoSendingUsers:@[] sequence:nil];
    ZMUpdateEvent *selfUserDoesNotJoinCallEvent = [self callStateEventInConversation:self.conversation2 joinedUsers:@[self.user1, self.user2] videoSendingUsers:@[] sequence:nil];
    
    // expect
    __block UILocalNotification *scheduledNotification1;
    
    [[self.mockUISharedApplication expect] scheduleLocalNotification:ZM_ARG_SAVE(scheduledNotification1)];
    
    [self.sut didReceiveUpdateEvents:@[callEvent] notificationID:NSUUID.createUUID];
    WaitForAllGroupsToBeEmpty(0.5);
    
    [[self.conversation2 mutableOrderedSetValueForKey:@"callParticipants"] addObject:self.user1];

    // when
    [self.sut didReceiveUpdateEvents:@[selfUserDoesNotJoinCallEvent] notificationID:NSUUID.createUUID];
    WaitForAllGroupsToBeEmpty(0.5);

    [self.mockUISharedApplication verify];
    WaitForAllGroupsToBeEmpty(0.5);

    // then
    XCTAssertEqualObjects([scheduledNotification1 conversationInManagedObjectContext:self.syncMOC], self.conversation2);
    
    // after
    [[self.mockUISharedApplication stub] cancelLocalNotification:OCMOCK_ANY];
}

- (void)testThatItCancelsNotificationsWhenReceivingANotificationThatTheCallWasIgnored
{
    // given
    ZMUpdateEvent *callEvent = [self callStateEventInConversation:self.conversation2 joinedUsers:@[self.user1] videoSendingUsers:@[] sequence:nil];
    self.conversation2.isIgnoringCall = YES;
    [[self.mockUISharedApplication expect] scheduleLocalNotification:OCMOCK_ANY];
    
    [self.sut didReceiveUpdateEvents:@[callEvent] notificationID:NSUUID.createUUID];
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
        [[self.mockUISharedApplication expect] scheduleLocalNotification:note];
        [(ZMLocalNotificationSet *)[self.mockFailedNotificationSet expect] addObject:mockLocalNote];
        
        // when
        [self.sut didFailToSentMessage:message];
        
        // after
        [mockLocalNote verify];
        [self.mockFailedNotificationSet verify];
        [mockLocalNote stopMocking];
        
    }];
    
    // after
    [[self.mockUISharedApplication stub] cancelLocalNotification:OCMOCK_ANY];
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
    ZMGenericMessage *message = [ZMGenericMessage messageWithText:text nonce:nonce.transportString];
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

- (void)testThatItCanParseGenericMessages
{
    // given
    NSDictionary *payload = [self payloadForEncryptedOTRMessageWithText:@"Hallo" nonce:[NSUUID UUID]];
    ZMUpdateEvent *event = [ZMUpdateEvent eventFromEventStreamPayload:payload uuid:nil];
    
    // expect
    __block UILocalNotification *scheduledNotification;
    [[self.mockUISharedApplication expect] scheduleLocalNotification:ZM_ARG_SAVE(scheduledNotification)];
    
    // when
    [self.sut didReceiveUpdateEvents:@[event] notificationID:NSUUID.createUUID];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertNotNil(scheduledNotification);
    
    // after
    [[self.mockUISharedApplication stub] cancelLocalNotification:OCMOCK_ANY];
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
    [self.syncMOC setPersistentStoreMetadata:@(YES) forKey:@"ZMShouldHideNotificationContentKey"];
    [self.syncMOC saveOrRollback];
    // given
    NSDictionary *data = @{@"content" : @"hallo", @"nonce": [NSUUID UUID].transportString };
    ZMUpdateEvent *event = [self eventWithPayload:data inConversation:self.conversation1 type:EventConversationAdd];
    
    // expect
    [[self.mockUISharedApplication stub] scheduleLocalNotification:[OCMArg checkWithBlock:^BOOL(UILocalNotification *localNotification) {
        
        return [localNotification.alertBody isEqualToString:[ZMPushStringDefault localizedString]];
    }]];
    
    //when
    [self.sut didReceiveUpdateEvents:@[event] notificationID:NSUUID.createUUID];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    [[self.mockUISharedApplication stub] cancelLocalNotification:OCMOCK_ANY];

}

- (void)testThatItDoesNotCreateNotificationForTwoMessageEventsWithTheSameNonce
{
    ZMLocalNotificationSet *localNotificationSet = [[ZMLocalNotificationSet alloc] initWithApplication:self.mockUISharedApplication
                                                                                          archivingKey:@"ZMLocalNotificationDispatcherEventNotificationsKey"
                                                                                         keyValueStore:[OCMockObject niceMockForProtocol:@protocol(ZMSynchonizableKeyValueStore)]];
    
    // Replace the default sut since we need a real ZMLocalNotificationSet
    [self.sut tearDown];
    self.sut = [[ZMLocalNotificationDispatcher alloc] initWithManagedObjectContext:self.syncMOC
                                                                 sharedApplication:self.mockUISharedApplication
                                                              eventNotificationSet:localNotificationSet
                                                             failedNotificationSet:self.mockFailedNotificationSet];
    
    // given
    NSDictionary *payload = [self payloadForEncryptedOTRMessageWithText:@"Hallo" nonce:[NSUUID UUID]];
    ZMUpdateEvent *event1 = [ZMUpdateEvent eventFromEventStreamPayload:payload uuid:nil];
    ZMUpdateEvent *event2 = [ZMUpdateEvent eventFromEventStreamPayload:payload uuid:nil];
    
    // expect
    __block UILocalNotification *scheduledNotification;
    [[self.mockUISharedApplication expect] scheduleLocalNotification:ZM_ARG_SAVE(scheduledNotification)];
    
    // when
    [self.sut didReceiveUpdateEvents:@[event1] notificationID:NSUUID.createUUID];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertNotNil(scheduledNotification);
    
    // after
    [[self.mockUISharedApplication stub] cancelLocalNotification:OCMOCK_ANY];
    
    // expect
    [[self.mockUISharedApplication reject] scheduleLocalNotification:OCMOCK_ANY];
    
    // when
    [self.sut didReceiveUpdateEvents:@[event2] notificationID:NSUUID.createUUID];
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatItDoesNotCreateNotificationForFileUploadEventsWithTheSameNonce
{
    ZMLocalNotificationSet *localNotificationSet = [[ZMLocalNotificationSet alloc] initWithApplication:self.mockUISharedApplication
                                                                                          archivingKey:@"ZMLocalNotificationDispatcherEventNotificationsKey"
                                                                                         keyValueStore:[OCMockObject niceMockForProtocol:@protocol(ZMSynchonizableKeyValueStore)]];
    
    NSUUID *nonce = [NSUUID UUID];
    ZMAudioMetadata *audioMetadata = [[ZMAudioMetadata alloc] initWithFileURL:[NSURL fileURLWithPath:@"audiofile.m4a"] duration:100 normalizedLoudness:@[] thumbnail:nil];
    ZMGenericMessage *genericMessage = [ZMGenericMessage genericMessageWithFileMetadata:audioMetadata messageID:nonce.transportString];
    
    // Replace the default sut since we need a real ZMLocalNotificationSet
    [self.sut tearDown];
    self.sut = [[ZMLocalNotificationDispatcher alloc] initWithManagedObjectContext:self.syncMOC
                                                                 sharedApplication:self.mockUISharedApplication
                                                              eventNotificationSet:localNotificationSet
                                                             failedNotificationSet:self.mockFailedNotificationSet];
    // given
    ZMUpdateEvent *event1 = [ZMUpdateEvent eventFromEventStreamPayload:[self payloadForOTRMessageWithGenericMessage:genericMessage] uuid:nil];
    ZMUpdateEvent *event2 = [ZMUpdateEvent eventFromEventStreamPayload:[self payloadForOTRAssetWithGenericMessage:genericMessage] uuid:nil];
    
    // expect
    __block UILocalNotification *scheduledNotification;
    [[self.mockUISharedApplication expect] scheduleLocalNotification:ZM_ARG_SAVE(scheduledNotification)];
    
    // when
    [self.sut didReceiveUpdateEvents:@[event1] notificationID:NSUUID.createUUID];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertNotNil(scheduledNotification);
    
    // after
    [[self.mockUISharedApplication stub] cancelLocalNotification:OCMOCK_ANY];
    
    // expect
    [[self.mockUISharedApplication reject] scheduleLocalNotification:OCMOCK_ANY];
    
    // when
    [self.sut didReceiveUpdateEvents:@[event2] notificationID:NSUUID.createUUID];
    WaitForAllGroupsToBeEmpty(0.5);
}

@end
