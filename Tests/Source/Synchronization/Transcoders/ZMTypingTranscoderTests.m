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
@import zmessaging;
@import ZMCDataModel;

#import "ZMTypingTranscoder+Internal.h"
#import "MessagingTest.h"
#import "ZMTyping.h"

static NSString * const TypingNotificationName = @"ZMTypingNotification";
static NSString * const IsTypingKey = @"isTyping";

@interface ZMTypingTranscoderTests : MessagingTest

@property (nonatomic) NSTimeInterval originalTimeout;
@property (nonatomic) ZMTypingTranscoder *sut;
@property (nonatomic) id typing;
@property (nonatomic) ZMConversation *conversationA;
@property (nonatomic) ZMUser *userA;

@end



@implementation ZMTypingTranscoderTests

- (void)setUp
{
    [super setUp];
    self.originalTimeout = ZMTypingDefaultTimeout;
    ZMTypingDefaultTimeout = 0.5;

    self.typing = [OCMockObject mockForClass:ZMTyping.class];
    self.sut = [[ZMTypingTranscoder alloc] initWithManagedObjectContext:self.syncMOC userInterfaceContext:self.uiMOC typing:self.typing];

    [self.syncMOC performGroupedBlockAndWait:^{
        self.conversationA = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        self.conversationA.remoteIdentifier = NSUUID.createUUID;
        self.userA = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        self.userA.remoteIdentifier = NSUUID.createUUID;
        XCTAssert([self.syncMOC saveOrRollback]);
    }];
}

- (void)tearDown
{
    self.conversationA = nil;
    self.userA = nil;
    
    [[self.typing expect] tearDown];

    [self.sut tearDown];
    [self.typing verify];
    self.typing = nil;
    self.sut = nil;
    
    ZMTypingDefaultTimeout = self.originalTimeout;
    [super tearDown];
}

- (void)testThatItForwardsAStartedTypingEvent;
{
    // given
    NSDictionary *payload = @{@"conversation": self.conversationA.remoteIdentifier.transportString,
                              @"data": @{@"status": @"started"},
                              @"from": self.userA.remoteIdentifier.transportString,
                              @"time": [NSDate date].transportString,
                              @"type": @"conversation.typing",
                              };
    
    ZMUpdateEvent *event = [ZMUpdateEvent eventFromEventStreamPayload:payload uuid:nil];
    
    // expect
    [[self.typing expect] setIsTyping:YES forUser:self.userA inConversation:self.conversationA];
    
    // when
    [self.sut processEvents:@[event] liveEvents:YES prefetchResult:nil];
    
    // then
    [self.typing verify];
}

- (void)testThatItForwardsAStoppedTypingEvent;
{
    // given
    NSDictionary *payload = @{@"conversation": self.conversationA.remoteIdentifier.transportString,
                              @"data": @{@"status": @"stopped"},
                              @"from": self.userA.remoteIdentifier.transportString,
                              @"time": [NSDate date].transportString,
                              @"type": @"conversation.typing",
                              };
    ZMUpdateEvent *event = [ZMUpdateEvent eventFromEventStreamPayload:payload uuid:nil];
    
    // expect
    [[self.typing expect] setIsTyping:NO forUser:self.userA inConversation:self.conversationA];
    
    // when
    [self.sut processEvents:@[event] liveEvents:YES prefetchResult:nil];
    
    // then
    [self.typing verify];
}

- (void)testThatItDoesNotForwardsAnUnknownTypingEvent;
{
    // given
    NSDictionary *payload = @{@"conversation": self.conversationA.remoteIdentifier.transportString,
                              @"data": @{@"status": @"foo"},
                              @"from": self.userA.remoteIdentifier.transportString,
                              @"time": [NSDate date].transportString,
                              @"type": @"conversation.typing",
                              };
    ZMUpdateEvent *event = [ZMUpdateEvent eventFromEventStreamPayload:payload uuid:nil];
    
    // expect
    [[self.typing reject] setIsTyping:YES forUser:OCMOCK_ANY inConversation:OCMOCK_ANY];
    [[self.typing reject] setIsTyping:NO forUser:OCMOCK_ANY inConversation:OCMOCK_ANY];
    
    // when
    [self.sut processEvents:@[event] liveEvents:YES prefetchResult:nil];
    
    // then
    [self.typing verify];
}

- (void)testThatItForwardsOTRMessageAddEventsAndSetsIsTypingToNo;
{
    // given
    NSDictionary *payload = @{@"conversation": self.conversationA.remoteIdentifier.transportString,
                              @"data": @{},
                              @"from": self.userA.remoteIdentifier.transportString,
                              @"time": [NSDate date].transportString,
                              @"type": @"conversation.otr-message-add",
                              };
    ZMUpdateEvent *event = [ZMUpdateEvent eventFromEventStreamPayload:payload uuid:nil];

    // expect
    [[self.typing reject] setIsTyping:YES forUser:OCMOCK_ANY inConversation:OCMOCK_ANY];
    [[self.typing expect] setIsTyping:NO forUser:OCMOCK_ANY inConversation:OCMOCK_ANY];
    
    // when
    [self.sut processEvents:@[event] liveEvents:YES prefetchResult:nil];
    
    // then
    [self.typing verify];
}

- (void)testThatItDoesNotForwardOtherEventTypes;
{
    // given
    NSDictionary *payload = @{@"conversation": self.conversationA.remoteIdentifier.transportString,
                              @"data": @{@"status": @"started"},
                              @"from": self.userA.remoteIdentifier.transportString,
                              @"time": [NSDate date].transportString,
                              @"type": @"conversation.voice-channel-activate",
                              };
    ZMUpdateEvent *event = [ZMUpdateEvent eventFromEventStreamPayload:payload uuid:nil];
    
    // expect
    [[self.typing reject] setIsTyping:YES forUser:OCMOCK_ANY inConversation:OCMOCK_ANY];
    [[self.typing reject] setIsTyping:NO forUser:OCMOCK_ANY inConversation:OCMOCK_ANY];
    
    // when
    [self.sut processEvents:@[event] liveEvents:YES prefetchResult:nil];
    
    // then
    [self.typing verify];
}

- (void)testThatItReturnsANextRequestWhenReceivingATypingNotification
{
    // given
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    conversation.remoteIdentifier = NSUUID.createUUID;
    [self.uiMOC saveOrRollback];
    
    NSDictionary *userInfo = @{IsTypingKey: @(YES)};
    
    // when
    [[NSNotificationCenter defaultCenter] postNotificationName:TypingNotificationName object:conversation userInfo:userInfo];
    WaitForAllGroupsToBeEmpty(0.5);
    
    ZMTransportRequest *request = [self.sut.requestGenerators nextRequest];
    
    // then
    NSString *expectedPath = [NSString pathWithComponents:@[@"/", @"conversations", conversation.remoteIdentifier.transportString, @"typing"]];
    NSDictionary *expectedPayload = @{@"status": @"started"};
    
    XCTAssertNotNil(request);
    XCTAssertEqualObjects(request.path, expectedPath);
    XCTAssertEqual(request.method, ZMMethodPOST);
    XCTAssertEqualObjects(request.payload, expectedPayload);
}


- (void)testThatItReturns_OnlyOne_RequestsWhenReceiving_One_TypingNotification
{
    // given
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    conversation.remoteIdentifier = NSUUID.createUUID;
    [self.uiMOC saveOrRollback];
    
    [[NSNotificationCenter defaultCenter] postNotificationName:TypingNotificationName object:conversation userInfo:@{IsTypingKey: @(YES)}];
    WaitForAllGroupsToBeEmpty(0.5);
    
    ZMTransportRequest *request1 = [self.sut.requestGenerators nextRequest];
    XCTAssertNotNil(request1);

    // when
    ZMTransportRequest *request2 = [self.sut.requestGenerators nextRequest];

    // then
    XCTAssertNil(request2);
}

- (void)testThatItDoesReturns_OnlyOne_RequestsWhenReceiving_Two_TypingNotification_ForTheSameConversation
{
    // given
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    conversation.remoteIdentifier = NSUUID.createUUID;
    [self.uiMOC saveOrRollback];
    
    [[NSNotificationCenter defaultCenter] postNotificationName:TypingNotificationName object:conversation userInfo:@{IsTypingKey: @(YES)}];
    [[NSNotificationCenter defaultCenter] postNotificationName:TypingNotificationName object:conversation userInfo:@{IsTypingKey: @(NO)}];

    WaitForAllGroupsToBeEmpty(0.5);
    
    // when
    ZMTransportRequest *request1 = [self.sut.requestGenerators nextRequest];
    XCTAssertNotNil(request1);
    
    NSString *expectedPath = [NSString pathWithComponents:@[@"/", @"conversations", conversation.remoteIdentifier.transportString, @"typing"]];
    NSDictionary *expectedPayload = @{@"status": @"stopped"};
    
    XCTAssertNotNil(request1);
    XCTAssertEqualObjects(request1.path, expectedPath);
    XCTAssertEqual(request1.method, ZMMethodPOST);
    XCTAssertEqualObjects(request1.payload, expectedPayload);
    
    // when
    ZMTransportRequest *request2 = [self.sut.requestGenerators nextRequest];
    
    // then
    XCTAssertNil(request2);
}

- (void)testThatItDoesReturn_OnlyOne_RequestsWhenReceiving_AnotherIdentical_TypingNotification;
{
    // when
    NSArray *requests = [self requestsForSendingNotificationsWithIsTyping:@[@YES, @YES] with:TestTyping_NoDelay];
    ZMTransportRequest *request1 = (requests[0] == [NSNull null]) ? nil : requests[0];
    ZMTransportRequest *request2 = (requests[1] == [NSNull null]) ? nil : requests[1];
    
    // then
    XCTAssertNotNil(request1);
    NSDictionary *expectedPayload = @{@"status": @"started"};
    XCTAssertEqualObjects(request1.payload, expectedPayload);

    XCTAssertNil(request2);
}

- (void)testThatItDoesReturn_Another_RequestsWhenReceiving_AnotherIdentical_TypingNotificationAfterTheFirstOneIsCleared;
{
    // when
    NSArray *requests = [self requestsForSendingNotificationsWithIsTyping:@[@YES, @YES] with:TestTyping_ClearTranscoder];
    ZMTransportRequest *request1 = (requests[0] == [NSNull null]) ? nil : requests[0];
    ZMTransportRequest *request2 = (requests[1] == [NSNull null]) ? nil : requests[1];
    
    // then
    XCTAssertNotNil(request1);
    NSDictionary *expectedPayload = @{@"status": @"started"};
    XCTAssertEqualObjects(request1.payload, expectedPayload);
    
    XCTAssertNotNil(request2);
    XCTAssertEqualObjects(request2.payload, expectedPayload);
}

- (void)testThatItDoesReturn_Another_RequestsWhenReceiving_AnotherIdentical_TypingNotificationAfterAppendingAMessage
{
    // when
    NSArray *requests = [self requestsForSendingNotificationsWithIsTyping:@[@YES, @YES] with:TestTyping_AppendMessage];
    ZMTransportRequest *request1 = (requests[0] == [NSNull null]) ? nil : requests[0];
    ZMTransportRequest *request2 = (requests[1] == [NSNull null]) ? nil : requests[1];
    
    // then
    XCTAssertNotNil(request1);
    NSDictionary *expectedPayload = @{@"status": @"started"};
    XCTAssertEqualObjects(request1.payload, expectedPayload);
    
    XCTAssertNotNil(request2);
    XCTAssertEqualObjects(request2.payload, expectedPayload);
}

- (void)testThatItDoesReturn_Two_RequestsWhenReceiving_AnotherDifferent_TypingNotification;
{
    // when
    NSArray *requests = [self requestsForSendingNotificationsWithIsTyping:@[@YES, @NO] with:TestTyping_NoDelay];
    ZMTransportRequest *request1 = (requests[0] == [NSNull null]) ? nil : requests[0];
    ZMTransportRequest *request2 = (requests[1] == [NSNull null]) ? nil : requests[1];
    
    // then
    XCTAssertNotNil(request1);
    XCTAssertEqualObjects(request1.payload, @{@"status": @"started"});
    
    XCTAssertNotNil(request2);
    XCTAssertEqualObjects(request2.payload, @{@"status": @"stopped"});
}

- (void)testThatItDoesReturn_Two_RequestsWhenReceiving_AnotherIdentical_TypingNotification_AfterADelay;
{
    // when
    NSArray *requests = [self requestsForSendingNotificationsWithIsTyping:@[@YES, @YES] with:TestTyping_Delay];
    ZMTransportRequest *request1 = (requests[0] == [NSNull null]) ? nil : requests[0];
    ZMTransportRequest *request2 = (requests[1] == [NSNull null]) ? nil : requests[1];
    
    // then
    XCTAssertNotNil(request1);
    XCTAssertEqualObjects(request1.payload, @{@"status": @"started"});
    
    XCTAssertNotNil(request2);
    XCTAssertEqualObjects(request2.payload, @{@"status": @"started"});
}

typedef NS_ENUM(int, TestTyping_t) {
    TestTyping_NoDelay,
    TestTyping_Delay,
    TestTyping_ClearTranscoder,
    TestTyping_AppendMessage,
};

- (NSArray *)requestsForSendingNotificationsWithIsTyping:(NSArray *)isTypingArray with:(TestTyping_t)delay;
{
    NSMutableArray *result = [NSMutableArray array];
    
    // given
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    conversation.remoteIdentifier = NSUUID.createUUID;
    [self.uiMOC saveOrRollback];
    
    for (NSNumber *isTyping in isTypingArray) {
        [ZMTypingTranscoder notifyTranscoderThatUserIsTyping:[isTyping boolValue] inConversation:conversation];
        WaitForAllGroupsToBeEmpty(0.5);
        
        if (delay == TestTyping_Delay) {
            NSTimeInterval interval = (ZMTypingDefaultTimeout / (ZMTypingRelativeSendTimeout - 1.));
            [NSThread sleepForTimeInterval:interval];
        }
        
        ZMTransportRequest *request = [self.sut.requestGenerators nextRequest];
        [result addObject:request ?: [NSNull null]];
        
        if (delay == TestTyping_ClearTranscoder) {
            [ZMTypingTranscoder clearTranscoderStateForTypingInConversation:conversation];
            WaitForAllGroupsToBeEmpty(0.1);
        } else if (delay == TestTyping_AppendMessage) {
            [conversation appendMessageWithText:@"ABABABABA"];
            WaitForAllGroupsToBeEmpty(0.1);
        }
    }
    
    return result;
}

- (void)testThatItDoesNotReturnARequestsWhenTheConversationsRemoteIdentifierIsNotSet
{
    // given
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    [self.uiMOC saveOrRollback];
    
    [[NSNotificationCenter defaultCenter] postNotificationName:TypingNotificationName object:conversation userInfo:@{IsTypingKey: @(YES)}];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // when
    ZMTransportRequest *request = [self.sut.requestGenerators nextRequest];
    
    // then
    XCTAssertNil(request);
}

- (void)testThatAppendingAMessageClearsTheIsTypingState;
{
    // given
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    [self.uiMOC saveOrRollback];
    
    // expect
    [self expectationForNotification:ZMConversationClearTypingNotificationName object:nil handler:^BOOL(NSNotification *notification) {
        return [notification.object isEqual:conversation];
    }];
    
    // when
    (void) [conversation appendMessageWithText:@"foo bar baz"];
    
    // then
    XCTAssert([self waitForCustomExpectationsWithTimeout:0.1]);
}

@end


@interface ZMTypingEventTests : MessagingTest

@property (nonatomic) NSTimeInterval originalTimeout;

@end



@implementation ZMTypingEventTests

- (void)setUp;
{
    [super setUp];
    self.originalTimeout = ZMTypingDefaultTimeout;
    ZMTypingDefaultTimeout = 0.5;
}

- (void)tearDown;
{
    ZMTypingDefaultTimeout = self.originalTimeout;
    [super tearDown];
}

- (void)testThatItComparesRecentAndEqualBasedOnIsTyping;
{
    // given
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    conversation.remoteIdentifier = NSUUID.createUUID;
    [self.uiMOC saveOrRollback];
    
    ZMTypingEvent *eventA = [ZMTypingEvent typingEventWithObjectID:conversation.objectID isTyping:YES];
    ZMTypingEvent *eventB = [ZMTypingEvent typingEventWithObjectID:conversation.objectID isTyping:YES];
    ZMTypingEvent *eventC = [ZMTypingEvent typingEventWithObjectID:conversation.objectID isTyping:NO];
    ZMTypingEvent *eventD = [ZMTypingEvent typingEventWithObjectID:conversation.objectID isTyping:NO];
    
    // then
    XCTAssertTrue([eventA isRecentAndEqualToEvent:eventB]);
    XCTAssertTrue([eventB isRecentAndEqualToEvent:eventA]);
    XCTAssertTrue([eventC isRecentAndEqualToEvent:eventD]);
    XCTAssertTrue([eventD isRecentAndEqualToEvent:eventC]);

    XCTAssertFalse([eventA isRecentAndEqualToEvent:eventC]);
    XCTAssertFalse([eventB isRecentAndEqualToEvent:eventC]);
    XCTAssertFalse([eventC isRecentAndEqualToEvent:eventA]);
    XCTAssertFalse([eventD isRecentAndEqualToEvent:eventA]);
}

- (void)testThatItComparesRecentAndEqualBasedOnConversation;
{
    // given
    ZMConversation *conversationA = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    conversationA.remoteIdentifier = NSUUID.createUUID;
    ZMConversation *conversationB = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    conversationB.remoteIdentifier = NSUUID.createUUID;
    [self.uiMOC saveOrRollback];
    
    ZMTypingEvent *eventA = [ZMTypingEvent typingEventWithObjectID:conversationA.objectID isTyping:YES];
    ZMTypingEvent *eventB = [ZMTypingEvent typingEventWithObjectID:conversationA.objectID isTyping:YES];
    ZMTypingEvent *eventC = [ZMTypingEvent typingEventWithObjectID:conversationB.objectID isTyping:YES];
    ZMTypingEvent *eventD = [ZMTypingEvent typingEventWithObjectID:conversationB.objectID isTyping:YES];
    
    // then
    XCTAssertTrue([eventA isRecentAndEqualToEvent:eventB]);
    XCTAssertTrue([eventB isRecentAndEqualToEvent:eventA]);
    XCTAssertTrue([eventC isRecentAndEqualToEvent:eventD]);
    XCTAssertTrue([eventD isRecentAndEqualToEvent:eventC]);
    
    XCTAssertFalse([eventA isRecentAndEqualToEvent:eventC]);
    XCTAssertFalse([eventB isRecentAndEqualToEvent:eventC]);
    XCTAssertFalse([eventC isRecentAndEqualToEvent:eventA]);
    XCTAssertFalse([eventD isRecentAndEqualToEvent:eventA]);
}

- (void)testThatItComparesRecentAndEqualBasedOnTime;
{
    // given
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    conversation.remoteIdentifier = NSUUID.createUUID;
    [self.uiMOC saveOrRollback];
    
    NSTimeInterval const interval = (ZMTypingDefaultTimeout / (ZMTypingRelativeSendTimeout - 1.));
    ZMTypingEvent *eventA = [ZMTypingEvent typingEventWithObjectID:conversation.objectID isTyping:YES];
    ZMTypingEvent *eventB = [ZMTypingEvent typingEventWithObjectID:conversation.objectID isTyping:YES];
    [NSThread sleepForTimeInterval:interval];
    ZMTypingEvent *eventC = [ZMTypingEvent typingEventWithObjectID:conversation.objectID isTyping:YES];
    ZMTypingEvent *eventD = [ZMTypingEvent typingEventWithObjectID:conversation.objectID isTyping:YES];
    [NSThread sleepForTimeInterval:interval];
    
    // then
    XCTAssertTrue([eventA isRecentAndEqualToEvent:eventB]);
    XCTAssertTrue([eventB isRecentAndEqualToEvent:eventA]);
    XCTAssertTrue([eventC isRecentAndEqualToEvent:eventD]);
    XCTAssertTrue([eventD isRecentAndEqualToEvent:eventC]);
    
    XCTAssertFalse([eventA isRecentAndEqualToEvent:eventC]);
    XCTAssertFalse([eventB isRecentAndEqualToEvent:eventC]);
    XCTAssertFalse([eventC isRecentAndEqualToEvent:eventA]);
    XCTAssertFalse([eventD isRecentAndEqualToEvent:eventA]);
}

@end
