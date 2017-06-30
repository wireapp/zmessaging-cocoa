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


@import UIKit;
@import WireTransport;
@import WireSyncEngine;
@import WireDataModel;
@import WireMessageStrategy;


#import "MessagingTest.h"
#import "ZMUserSession+Internal.h"
#import "ZMSyncStrategy+Internal.h"
#import "ZMSyncStrategy+EventProcessing.h"
#import "ZMSyncStrategy+ManagedObjectChanges.h"
#import "ZMUpdateEventsBuffer.h"
#import "ZMOperationLoop.h"
#import "MessagingTest+EventFactory.h"
#import "WireSyncEngine_iOS_Tests-Swift.h"
#import "ZMNotifications+UserSession.h"

// Status
#import "ZMAuthenticationStatus.h"
#import "ZMClientRegistrationStatus.h"

// Transcoders & strategies
#import "ZMUserTranscoder.h"
#import "ZMConversationTranscoder.h"
#import "ZMSelfStrategy.h"
#import "ZMMissingUpdateEventsTranscoder.h"
#import "ZMRegistrationTranscoder.h"
#import "ZMCallFlowRequestStrategy.h"
#import "ZMConnectionTranscoder.h"
#import "ZMLoginCodeRequestTranscoder.h"
#import "ZMPhoneNumberVerificationTranscoder.h"
#import "MessagingTest+EventFactory.h"
#import "WireSyncEngine_iOS_Tests-Swift.h"


@interface ZMSyncStrategyTests : MessagingTest

@property (nonatomic) ZMSyncStrategy *sut;

@property (nonatomic) NSArray *syncObjects;
@property (nonatomic) id updateEventsBuffer;
@property (nonatomic) id syncStateDelegate;
@property (nonatomic) id backgroundableSession;
@property (nonatomic) id conversationTranscoder;
@property (nonatomic) BOOL shouldStubContextChangeTrackers;
@property (nonatomic) id mockUpstreamSync1;
@property (nonatomic) id mockUpstreamSync2;
@property (nonatomic) NSFetchRequest *fetchRequestForTrackedObjects1;
@property (nonatomic) NSFetchRequest *fetchRequestForTrackedObjects2;
@property (nonatomic) id mockDispatcher;
@property (nonatomic) id syncStatusMock;
@property (nonatomic) id operationStatusMock;
@property (nonatomic) id applicationStatusDirectoryMock;
@property (nonatomic) id userProfileImageUpdateStatus;
@end



@implementation ZMSyncStrategyTests;

- (void)setUp
{
    [super setUp];
    
    self.mockDispatcher = [OCMockObject niceMockForClass:[LocalNotificationDispatcher class]];
    self.mockUpstreamSync1 = [OCMockObject mockForClass:[ZMUpstreamModifiedObjectSync class]];
    self.mockUpstreamSync2 = [OCMockObject mockForClass:[ZMUpstreamModifiedObjectSync class]];
    [self verifyMockLater:self.mockUpstreamSync1];
    [self verifyMockLater:self.mockUpstreamSync2];
    
    self.syncStateDelegate = [OCMockObject niceMockForProtocol:@protocol(ZMSyncStateDelegate)];
    self.syncStatusMock = [OCMockObject mockForClass:SyncStatus.class];
    self.operationStatusMock = [OCMockObject mockForClass:ZMOperationStatus.class];
    self.userProfileImageUpdateStatus = [OCMockObject niceMockForClass:UserProfileImageUpdateStatus.class];
    
    self.applicationStatusDirectoryMock = [OCMockObject niceMockForClass:ZMApplicationStatusDirectory.class];
    [[[[self.applicationStatusDirectoryMock expect] andReturn: self.applicationStatusDirectoryMock] classMethod] alloc];
    (void) [[[self.applicationStatusDirectoryMock expect] andReturn:self.applicationStatusDirectoryMock] initWithManagedObjectContext:OCMOCK_ANY cookie:OCMOCK_ANY requestCancellation:OCMOCK_ANY application:OCMOCK_ANY syncStateDelegate:OCMOCK_ANY];
    [[[self.applicationStatusDirectoryMock stub] andReturn:self.syncStatusMock] syncStatus];
    [[[self.applicationStatusDirectoryMock stub] andReturn:self.operationStatusMock] operationStatus];
    [(ZMApplicationStatusDirectory *)[[self.applicationStatusDirectoryMock stub] andReturn:self.userProfileImageUpdateStatus] userProfileImageUpdateStatus];
    
    id userTranscoder = [OCMockObject niceMockForClass:ZMUserTranscoder.class];
    [[[[userTranscoder expect] andReturn:userTranscoder] classMethod] alloc];
    (void) [[[userTranscoder expect] andReturn:userTranscoder] initWithManagedObjectContext:self.syncMOC applicationStatus:OCMOCK_ANY syncStatus:OCMOCK_ANY];

    self.conversationTranscoder = [OCMockObject niceMockForClass:ZMConversationTranscoder.class];
    [[[[self.conversationTranscoder expect] andReturn:self.conversationTranscoder] classMethod] alloc];
    (void) [[[self.conversationTranscoder expect] andReturn:self.conversationTranscoder] initWithSyncStrategy:OCMOCK_ANY applicationStatus:OCMOCK_ANY syncStatus:OCMOCK_ANY];

    id clientMessageTranscoder = [OCMockObject niceMockForClass:ClientMessageTranscoder.class];
    [[[[clientMessageTranscoder expect] andReturn:clientMessageTranscoder] classMethod] alloc];
    (void) [[[clientMessageTranscoder expect] andReturn:clientMessageTranscoder] initIn:self.syncMOC localNotificationDispatcher:self.mockDispatcher applicationStatus:OCMOCK_ANY];

    id selfStrategy = [OCMockObject niceMockForClass:ZMSelfStrategy.class];
    [[[[selfStrategy expect] andReturn:selfStrategy] classMethod] alloc];
    (void) [(ZMSelfStrategy *)[[selfStrategy expect] andReturn:selfStrategy] initWithManagedObjectContext:self.syncMOC applicationStatus:OCMOCK_ANY clientRegistrationStatus:OCMOCK_ANY syncStatus:OCMOCK_ANY];
    [[selfStrategy stub] contextChangeTrackers];
    [[selfStrategy expect] tearDown];

    id connectionTranscoder = [OCMockObject niceMockForClass:ZMConnectionTranscoder.class];
    [[[[connectionTranscoder expect] andReturn:connectionTranscoder] classMethod] alloc];
    (void) [[[connectionTranscoder expect] andReturn:connectionTranscoder] initWithManagedObjectContext:self.syncMOC applicationStatus:OCMOCK_ANY syncStatus:OCMOCK_ANY];

    id registrationTranscoder = [OCMockObject niceMockForClass:ZMRegistrationTranscoder.class];
    [[[[registrationTranscoder expect] andReturn:registrationTranscoder] classMethod] alloc];
    (void) [[[registrationTranscoder expect] andReturn:registrationTranscoder] initWithManagedObjectContext:self.syncMOC applicationStatusDirectory:OCMOCK_ANY];

    id missingUpdateEventsTranscoder = [OCMockObject niceMockForClass:ZMMissingUpdateEventsTranscoder.class];
    [[[[missingUpdateEventsTranscoder expect] andReturn:missingUpdateEventsTranscoder] classMethod] alloc];
    (void) [[[missingUpdateEventsTranscoder expect] andReturn:missingUpdateEventsTranscoder] initWithSyncStrategy:OCMOCK_ANY previouslyReceivedEventIDsCollection:OCMOCK_ANY application:OCMOCK_ANY backgroundAPNSPingbackStatus:OCMOCK_ANY syncStatus:OCMOCK_ANY];
    
    id callFlowRequestStrategy = [OCMockObject niceMockForClass:ZMCallFlowRequestStrategy.class];
    [[[[callFlowRequestStrategy expect] andReturn:callFlowRequestStrategy] classMethod] alloc];
    (void)[[[callFlowRequestStrategy expect] andReturn:callFlowRequestStrategy] initWithMediaManager:nil onDemandFlowManager:nil managedObjectContext:self.syncMOC applicationStatus:OCMOCK_ANY application:self.application];
        
    id loginCodeRequestTranscoder = [OCMockObject niceMockForClass:ZMLoginCodeRequestTranscoder.class];
    [[[[loginCodeRequestTranscoder expect] andReturn:loginCodeRequestTranscoder] classMethod] alloc];
    (void) [[[loginCodeRequestTranscoder expect] andReturn:loginCodeRequestTranscoder] initWithManagedObjectContext:self.syncMOC applicationStatusDirectory:OCMOCK_ANY];
    
    id phoneNumberVerificationTranscoder = [OCMockObject niceMockForClass:ZMPhoneNumberVerificationTranscoder.class];
    [[[[phoneNumberVerificationTranscoder expect] andReturn:phoneNumberVerificationTranscoder] classMethod] alloc];
    (void) [[[phoneNumberVerificationTranscoder expect] andReturn:phoneNumberVerificationTranscoder] initWithManagedObjectContext:self.syncMOC applicationStatusDirectory:OCMOCK_ANY];
    
    self.updateEventsBuffer = [OCMockObject mockForClass:ZMUpdateEventsBuffer.class];
    [[[[self.updateEventsBuffer expect] andReturn:self.updateEventsBuffer] classMethod] alloc];
    (void) [[[self.updateEventsBuffer expect] andReturn:self.updateEventsBuffer] initWithUpdateEventConsumer:OCMOCK_ANY];
    [self verifyMockLater:self.updateEventsBuffer];
    

    self.syncObjects = @[
                         connectionTranscoder,
                         userTranscoder,
                         self.conversationTranscoder,
                         clientMessageTranscoder,
                         missingUpdateEventsTranscoder,
                         registrationTranscoder,
                         loginCodeRequestTranscoder,
                         phoneNumberVerificationTranscoder
    ];
    
    for(ZMObjectSyncStrategy *strategy in self.syncObjects) {
        [self verifyMockLater:strategy];
    }
    self.fetchRequestForTrackedObjects1 = [NSFetchRequest fetchRequestWithEntityName:@"User"];
    self.fetchRequestForTrackedObjects1.predicate = [NSPredicate predicateWithFormat:@"name != nil"];
    self.fetchRequestForTrackedObjects2 = [NSFetchRequest fetchRequestWithEntityName:@"Conversation"];
    self.fetchRequestForTrackedObjects2.predicate = [NSPredicate predicateWithFormat:@"userDefinedName != nil"];
    
    [self stubChangeTrackerBootstrapInitialization];
    
    self.sut = [[ZMSyncStrategy alloc] initWithSyncManagedObjectContextMOC:self.syncMOC
                                                    uiManagedObjectContext:self.uiMOC
                                                                    cookie:nil
                                                              mediaManager:nil
                                                       onDemandFlowManager:nil
                                                         syncStateDelegate:self.syncStateDelegate
                                              localNotificationsDispatcher:self.mockDispatcher
                                                  taskCancellationProvider:nil
                                                        appGroupIdentifier:nil
                                                               application:self.application];
    
    XCTAssertEqual(self.sut.userTranscoder, userTranscoder);
    XCTAssertEqual(self.sut.conversationTranscoder, self.conversationTranscoder);
    XCTAssertEqual(self.sut.clientMessageTranscoder, clientMessageTranscoder);
    XCTAssertEqual(self.sut.selfStrategy, selfStrategy);
    XCTAssertEqual(self.sut.connectionTranscoder, connectionTranscoder);
    XCTAssertEqual(self.sut.registrationTranscoder, registrationTranscoder);
    XCTAssertEqual(self.sut.loginCodeRequestTranscoder, loginCodeRequestTranscoder);
    XCTAssertEqual(self.sut.phoneNumberVerificationTranscoder, phoneNumberVerificationTranscoder);
    
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)stubChangeTrackerBootstrapInitialization
{
    for(ZMObjectSyncStrategy *strategy in self.syncObjects) {
        if ([strategy conformsToProtocol:@protocol(ZMContextChangeTrackerSource)]) {
            [[[(id)strategy expect] andReturn:@[self.mockUpstreamSync1, self.mockUpstreamSync2]] contextChangeTrackers];
            [self verifyMockLater:strategy];
        }
    }
}


- (void)tearDown;
{
    [self.operationStatusMock stopMocking];
    self.operationStatusMock = nil;
    [self.syncStatusMock stopMocking];
    self.syncStatusMock = nil;
    [self.applicationStatusDirectoryMock stopMocking];
    self.applicationStatusDirectoryMock = nil;
    [self.userProfileImageUpdateStatus stopMocking];
    self.userProfileImageUpdateStatus = nil;
    
    [self.sut tearDown];
    for (id syncObject in self.syncObjects) {
        [syncObject stopMocking];
    }
    
    [self.updateEventsBuffer stopMocking];
    self.updateEventsBuffer = nil;

    self.sut = nil;
    self.syncObjects = nil;
    [super tearDown];
}

- (void)testThatDownloadedEventsAreForwardedToAllIndividualObjects
{
    // given
    ZMConversation *conv = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    conv.remoteIdentifier = [NSUUID createUUID];
    NSDictionary *payload = [self payloadForMessageInConversation:conv type:EventConversationAdd data:@{@"foo" : @"bar"}];
    ZMUpdateEvent *event = [ZMUpdateEvent eventFromEventStreamPayload:payload uuid:[NSUUID createUUID]];
    NSArray *eventsArray = @[event];
    
    
    // expect
    [self expectSyncObjectsToProcessEvents:YES
                                liveEvents:NO
                             decryptEvents:YES
                   returnIDsForPrefetching:YES
                                withEvents:eventsArray];
    
    // when
    [self.sut processDownloadedEvents:eventsArray];
    WaitForAllGroupsToBeEmpty(0.5);
    
}

- (void)testThatPushEventsAreProcessedForConversationEventSyncBeforeConversationSync
{
    // given
    NSString *eventType = @"user.update";
    
    NSDictionary *payload = @{
                               @"type" : eventType,
                               @"foo" : @"bar"
                               };
    
    NSDictionary *eventData = @{
                                @"id" : @"5cc1ab91-45f4-49ec-bb7a-a5517b7a4173",
                                @"payload" : @[payload],
                                };
    
    NSArray *expectedEvents = [ZMUpdateEvent eventsArrayFromPushChannelData:eventData];
    XCTAssertEqual(expectedEvents.count, 1u);
    
    // expect
    for(id obj in self.syncObjects) {
        if ([obj conformsToProtocol:@protocol(ZMEventConsumer)] && obj != self.sut.conversationTranscoder) {
            [[obj stub] processEvents:OCMOCK_ANY liveEvents:YES prefetchResult:OCMOCK_ANY];
        }
    }
    
    [self expectSyncObjectsToProcessEvents:NO
                                liveEvents:NO
                             decryptEvents:YES
                   returnIDsForPrefetching:YES
                                withEvents:expectedEvents];
    
    __block BOOL didCallConversationSync = NO;
    
    [[[(id) self.sut.conversationTranscoder expect] andDo:^(NSInvocation *i ZM_UNUSED) {
        didCallConversationSync = YES;
    }] processEvents:expectedEvents liveEvents:YES prefetchResult:OCMOCK_ANY];
    
    // when
    [self.sut consumeUpdateEvents:@[expectedEvents.firstObject]];
    
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertTrue(didCallConversationSync);
}

- (void)testThatWhenItConsumesEventsTheyAreForwardedToAllIndividualObjects
{
    // given
    NSString *uuid = [NSUUID createUUID].transportString;
    NSArray *eventsArray = @[
                             [ZMUpdateEvent eventFromEventStreamPayload:@{@"type": @"conversation.member-join",
                                                                          @"f": @2,
                                                                          @"conversation": uuid
                                                                          } uuid:nil],
                             [ZMUpdateEvent eventFromEventStreamPayload:@{@"type": @"conversation.message-add",
                                                                          @"a": @3,
                                                                          @"conversation": uuid
                                                                          } uuid:nil]];
    XCTAssertEqual(eventsArray.count, 2u);
    
    // expect
    for(ZMUpdateEvent *event in eventsArray) {
            [self expectSyncObjectsToProcessEvents:YES
                                        liveEvents:YES
                                     decryptEvents:YES
                           returnIDsForPrefetching:YES
                                        withEvents:@[event]];
    }

    // when
    for(id event in eventsArray) {
        [self.sut consumeUpdateEvents:@[event]];
        WaitForAllGroupsToBeEmpty(0.5);
    }
}

- (void)testThatItAsksClientMessageTranscoderToDecryptUpdateEvents
{
    // given
    NSString *uuid = [NSUUID createUUID].transportString;
    NSArray *eventsArray = @[
                             [ZMUpdateEvent eventFromEventStreamPayload:@{@"type": @"conversation.member-join",
                                                                          @"f": @2,
                                                                          @"conversation": uuid
                                                                          } uuid:nil],
                             [ZMUpdateEvent eventFromEventStreamPayload:@{@"type": @"conversation.message-add",
                                                                          @"a": @3,
                                                                          @"conversation": uuid
                                                                          } uuid:nil]];
    XCTAssertEqual(eventsArray.count, 2u);
    
    // expect
    [self expectSyncObjectsToProcessEvents:YES
                                liveEvents:YES
                             decryptEvents:YES
                   returnIDsForPrefetching:YES
                                withEvents:eventsArray];
    
    // when
    [self.sut processUpdateEvents:eventsArray ignoreBuffer:YES];
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatItProcessUpdateEventsIfTheCurrentStateShouldProcessThem
{
    // given
    NSDictionary *eventData = @{
                                @"id" : @"5cc1ab91-45f4-49ec-bb7a-a5517b7a4173",
                                @"payload" : @[
                                        @{
                                            @"type" : @"user.update",
                                            @"foo" : @"bar"
                                            }
                                        ]
                                };
    NSMutableArray *expectedEvents = [NSMutableArray array];
    [expectedEvents addObjectsFromArray:[ZMUpdateEvent eventsArrayFromPushChannelData:eventData]];
    
    [[[self.syncStatusMock stub] andReturnValue:@(NO)] isSyncing];
    
    // expect
    [self expectSyncObjectsToProcessEvents:YES
                                liveEvents:YES
                             decryptEvents:YES
                   returnIDsForPrefetching:YES
                                withEvents:expectedEvents];
    
    // when
    [self.sut processUpdateEvents:expectedEvents ignoreBuffer:NO];
    WaitForAllGroupsToBeEmpty(0.5);
}


- (void)testThatItForwardsUpdateEventsToBufferIfTheCurrentStateShouldBufferThemAndDoesNotDecryptTheUpdateEvents
{
    // given
    NSDictionary *eventData = @{
                                @"id" : @"5cc1ab91-45f4-49ec-bb7a-a5517b7a4173",
                                @"payload" : @[
                                        @{
                                            @"type" : @"user.update",
                                            @"foo" : @"bar"
                                            }
                                        ]
                                };
    NSMutableArray *expectedEvents = [NSMutableArray array];
    [expectedEvents addObjectsFromArray:[ZMUpdateEvent eventsArrayFromPushChannelData:eventData]];
    XCTAssertGreaterThan(expectedEvents.count, 0u);
    
    [[[self.syncStatusMock stub] andReturnValue:@(YES)] isSyncing];
    
    // expect
    [self expectSyncObjectsToProcessEvents:NO
                                liveEvents:YES
                             decryptEvents:NO
                   returnIDsForPrefetching:NO
                                withEvents:expectedEvents];

    for(id obj in expectedEvents) {
        [[self.updateEventsBuffer expect] addUpdateEvent:obj];
    }
    
    // when
    [self.sut processUpdateEvents:expectedEvents ignoreBuffer:NO];
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatItProcessUpdateEventsToBufferIfTheCurrentStateShouldBufferThemButIgnoreBufferIsYes
{
    // given
    NSDictionary *eventData = @{
                                @"id" : @"5cc1ab91-45f4-49ec-bb7a-a5517b7a4173",
                                @"payload" : @[
                                        @{
                                            @"type" : @"user.update",
                                            @"foo" : @"bar"
                                            }
                                        ]
                                };
    NSMutableArray *expectedEvents = [NSMutableArray array];
    [expectedEvents addObjectsFromArray:[ZMUpdateEvent eventsArrayFromPushChannelData:eventData]];
    XCTAssertGreaterThan(expectedEvents.count, 0u);
    
    [[[self.syncStatusMock stub] andReturnValue:@(NO)] isSyncing];

    // expect
    [self expectSyncObjectsToProcessEvents:YES
                                liveEvents:YES
                             decryptEvents:YES
                   returnIDsForPrefetching:YES
                                withEvents:expectedEvents];
    [[self.updateEventsBuffer reject] addUpdateEvent:OCMOCK_ANY];
    
    // when
    [self.sut processUpdateEvents:expectedEvents ignoreBuffer:YES];
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatItDoesProcessesFlowUpdateEvents;
{
    // given
    NSMutableArray *expectedEvents = [NSMutableArray array];
    for (ZMUpdateEventType type = ZMUpdateEventUnknown; type < ZMUpdateEvent_LAST; type++) {
        // given
        NSString *typeString = [ZMUpdateEvent eventTypeStringForUpdateEventType:type];
        if (typeString == nil) {
            continue;
        }
        NSDictionary *eventData = @{
                                    @"id" : NSUUID.createUUID.transportString,
                                    @"payload" : @[
                                            @{
                                                @"type" :  typeString,
                                                @"foo" : @"bar"
                                                }
                                            ]
                                    };
        ZMUpdateEvent *event = [ZMUpdateEvent eventsArrayFromPushChannelData:eventData].firstObject;
        if (event.isFlowEvent) {
            [expectedEvents addObject:event];
        }
    }
    
    [[[self.syncStatusMock stub] andReturnValue:@(NO)] isSyncing];
    XCTAssertGreaterThan(expectedEvents.count, 0u);
    
    // expect
    [self expectSyncObjectsToProcessEvents:YES
                                liveEvents:YES
                             decryptEvents:YES
                   returnIDsForPrefetching:YES
                                withEvents:expectedEvents];
    [[self.updateEventsBuffer reject] addUpdateEvent:OCMOCK_ANY];
    
    // when
    [self.sut processUpdateEvents:expectedEvents ignoreBuffer:NO];
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatItDoesProcessUpdateEventsIfTheCurrentStateShouldIgnoreThemButIgnoreBufferIsYes
{
    // given
    NSDictionary *eventData = @{
                                @"id" : @"5cc1ab91-45f4-49ec-bb7a-a5517b7a4173",
                                @"payload" : @[
                                        @{
                                            @"type" : @"user.update",
                                            @"foo" : @"bar"
                                            }
                                        ]
                                };
    NSMutableArray *expectedEvents = [NSMutableArray array];
    [expectedEvents addObjectsFromArray:[ZMUpdateEvent eventsArrayFromPushChannelData:eventData]];
    XCTAssertGreaterThan(expectedEvents.count, 0u);
    
    [[[self.syncStatusMock stub] andReturnValue:@(YES)] isSyncing];
    
    // expect
    [self expectSyncObjectsToProcessEvents:YES
                                liveEvents:YES
                             decryptEvents:YES
                   returnIDsForPrefetching:YES
                                withEvents:expectedEvents];
    
    // when
    [self.sut processUpdateEvents:expectedEvents ignoreBuffer:YES];
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatItItCreatesAFetchBatchRequestWithTheNoncesAndRemoteIdentifiersFromUpdateEvents
{
    // given
    id <ZMTransportData> firstPayload = @{
                                          @"conversation" : NSUUID.createUUID,
                                          @"data" : @{
                                                  @"last_read" : @"3.800122000a5efe70"
                                                  },
                                          @"from": NSUUID.createUUID.transportString,
                                          @"time" : NSDate.date.transportString,
                                          @"type" : @"conversation.member-update"
                                          };
    
    id <ZMTransportData> secondPayload = @{
                                           @"conversation" : NSUUID.createUUID,
                                           @"data" : @{
                                                   @"content" : @"www.wire.com",
                                                   @"nonce" : NSUUID.createUUID,
                                                   },
                                           @"from": NSUUID.createUUID.transportString,
                                           @"id" : @"6c9d.800122000a5911ba",
                                           @"time" : NSDate.date.transportString,
                                           @"type" : @"conversation.message-add"
                                           };
    
    NSArray <ZMUpdateEvent *> *events = @[
                                          [ZMUpdateEvent eventFromEventStreamPayload:firstPayload uuid:nil],
                                          [ZMUpdateEvent eventFromEventStreamPayload:secondPayload uuid:nil]
                                          ];
    
    // expect
    [[self.conversationTranscoder expect] conversationRemoteIdentifiersToPrefetchToProcessEvents:events];
    
    for (id obj in self.syncObjects) {
        for (Class class in self.transcodersExpectedToReturnNonces) {
            if ([obj isKindOfClass:class]) {
                [[obj expect] messageNoncesToPrefetchToProcessEvents:events];
            }
        }
    }

    // `returnIDsForPrefetching` is set to NO here because we explicitly
    // expect for the transcoders we expect to conform to the protocol above
    [self expectSyncObjectsToProcessEvents:YES
                                liveEvents:YES
                             decryptEvents:YES
                   returnIDsForPrefetching:NO
                                withEvents:events];
    
    // when
    [self.sut processUpdateEvents:events ignoreBuffer:YES];
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatItRequestsNoncesAndRemoteIdentifiersToPrefetchFromAllOfItsSyncObjects
{
    // given
    id <ZMTransportData> payload = @{
                                     @"conversation" : NSUUID.createUUID,
                                     @"data" : @{ @"last_read" : @"3.800122000a5efe70" },
                                     @"time" : NSDate.date.transportString,
                                     @"type" : @"conversation.member-update"
                                     };
    
    NSArray <ZMUpdateEvent *> *events = @[[ZMUpdateEvent eventFromEventStreamPayload:payload uuid:nil]];
    
    // expect
    [[self.conversationTranscoder expect] conversationRemoteIdentifiersToPrefetchToProcessEvents:events];
    
    for (id obj in self.syncObjects) {
        for (Class class in self.transcodersExpectedToReturnNonces) {
            if ([obj isKindOfClass:class]) {
                [[obj expect] messageNoncesToPrefetchToProcessEvents:events];
            }
        }
    }
    
    // when
    [self.sut fetchRequestBatchForEvents:events];
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatCallingNextRequestFetchesObjectsAndDistributesThemToTheChangeTracker
{
    // given
    __block ZMUser *user;
    __block ZMConversation *conversation;
    [self.syncMOC performGroupedBlockAndWait:^{
        user = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        user.name = @"User1";
        conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        conversation.userDefinedName = @"Conversation1";
        [self.syncMOC saveOrRollback];
    }];
    
    // expect
    for (id<ZMObjectStrategy> syncObject in self.syncObjects) {
        
        if (![syncObject conformsToProtocol:@protocol(ZMContextChangeTrackerSource)]) {
            continue;
        }
        
        [(ZMUpstreamModifiedObjectSync*)[[self.mockUpstreamSync1 stub] andReturn:self.fetchRequestForTrackedObjects1] fetchRequestForTrackedObjects];
        [(ZMUpstreamModifiedObjectSync*)[[self.mockUpstreamSync2 stub] andReturn:self.fetchRequestForTrackedObjects2] fetchRequestForTrackedObjects];
        
        [[self.mockUpstreamSync1 expect] addTrackedObjects:[NSSet setWithObject:user]];
        [[self.mockUpstreamSync2 expect] addTrackedObjects:[NSSet setWithObject:conversation]];
        [self verifyMockLater:syncObject];
    }
    
    // when
    (void)[self.sut nextRequest];
}

- (void)testThatManagedObjectChangesArePassedToAllSyncObjectsCaches
{
    
    // given
    id firstObject = [OCMockObject niceMockForClass:ZMManagedObject.class];
    id secondObject = [OCMockObject niceMockForClass:ZMManagedObject.class];
    
    [[[firstObject stub] andReturn:nil] entity];
    [[[secondObject stub] andReturn:nil] entity];
    
    NSSet *cacheInsertSet = [NSSet setWithObject:firstObject];
    NSSet *cacheUpdateSet = [NSSet setWithObject:secondObject];
    
    NSMutableSet *totalSet = [NSMutableSet setWithSet:cacheInsertSet];
    [totalSet unionSet:cacheUpdateSet];
    
    // expect
    for (id<ZMObjectStrategy> syncObject in self.syncObjects) {
        if (![syncObject conformsToProtocol:@protocol(ZMContextChangeTrackerSource)]) {
            continue;
        }
        
        [(id<ZMContextChangeTracker>)[self.mockUpstreamSync1 expect] objectsDidChange:totalSet];
        [(id<ZMContextChangeTracker>)[self.mockUpstreamSync2 expect] objectsDidChange:totalSet];
        
        [self verifyMockLater:syncObject];
    }
    
    // when
    [self.sut processSaveWithInsertedObjects:cacheInsertSet updateObjects:cacheUpdateSet];
    WaitForAllGroupsToBeEmpty(0.5);
}


- (void)testThatItSynchronizesChangesInUIContextToSyncContext
{
    // given
    
    [(id<ZMContextChangeTracker>)[self.mockUpstreamSync1 stub] objectsDidChange:OCMOCK_ANY];
    [(id<ZMContextChangeTracker>)[self.mockUpstreamSync2 stub] objectsDidChange:OCMOCK_ANY];
    
    ZMUser *uiUser = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    XCTAssertTrue([self.uiMOC saveOrRollback]);
    WaitForAllGroupsToBeEmpty(0.5);
    
    [self.sut.syncMOC performGroupedBlockAndWaitWithReasonableTimeout:^{
        ZMUser *syncUser =  (ZMUser *)[self.sut.syncMOC objectWithID:uiUser.objectID];
        XCTAssertNotNil(syncUser);
        XCTAssertNil(syncUser.name);
    }];
    
    NSString *name = @"very-unique-name_w938ruojfdmnsf";

    // when
    uiUser.name = name;
    XCTAssertTrue([self.uiMOC saveOrRollback]);
    WaitForAllGroupsToBeEmpty(0.5);
    // sut automagically synchronizes objects

    // then
    [self.sut.syncMOC performGroupedBlockAndWaitWithReasonableTimeout:^{
        ZMUser *syncUser =  (ZMUser *)[self.sut.syncMOC objectWithID:uiUser.objectID];
        XCTAssertNotNil(syncUser);
        XCTAssertEqualObjects(syncUser.name, name);
    }];
}

- (void)testThatItSynchronizesChangesInSyncContextToUIContext
{
    __block ZMUser *syncUser;
    
    // expect
    [self expectationForNotification:NSManagedObjectContextObjectsDidChangeNotification object:self.uiMOC handler:nil];
    
    // when
    [self.syncMOC performGroupedBlockAndWaitWithReasonableTimeout:^{
        syncUser = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        XCTAssertTrue([self.syncMOC saveOrRollback]);
    }];
    
    XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0.5]);
    
    ZMUser *uiUser =  (ZMUser *)[self.uiMOC objectWithID:syncUser.objectID];
    XCTAssertNotNil(uiUser);
    XCTAssertNil(uiUser.name);
    
    NSString *name = @"very-unique-name_ps9ijsdnmf";

    // and expect
    [self expectationForNotification:NSManagedObjectContextObjectsDidChangeNotification object:self.uiMOC handler:^BOOL(NSNotification *notification ZM_UNUSED) {
        return uiUser.name != nil;
    }];
    
    // when
    [self.syncMOC performGroupedBlockAndWaitWithReasonableTimeout:^{
        syncUser.name = name;
        XCTAssertTrue([self.syncMOC saveOrRollback]);
    }];
    
    XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0.2]);
    
    // then
    XCTAssertEqualObjects(name, uiUser.name);
}

- (void)testThatItFlushesTheInternalBufferWhenAsked
{
    // expect
    [[self.updateEventsBuffer expect] processAllEventsInBuffer];
    
    // when
    [self.sut processAllEventsInBuffer];
}

- (void)testThatARollbackTriggersAnObjectsDidChange;
{
    //
    
    // given
    __block ZMConversation *syncConversation;
    __block NSManagedObjectID *moid;
    [self.syncMOC performGroupedBlockAndWait:^{
        syncConversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        syncConversation.conversationType = ZMConversationTypeOneOnOne;
        [self.syncMOC saveOrRollback];
        moid = syncConversation.objectID;
    }];
    ZMConversation *uiConversation = (id) [self.uiMOC objectWithID:moid];
    WaitForAllGroupsToBeEmpty(0.5);
    //
    self.sut.contextMergingDisabled = YES;
    NSMutableArray *objectsDidChangeNotifications = [NSMutableArray array];
    id token1 = [[NSNotificationCenter defaultCenter] addObserverForName:NSManagedObjectContextObjectsDidChangeNotification object:self.uiMOC queue:nil usingBlock:^(NSNotification *note) {
        
        [objectsDidChangeNotifications addObject:note];
    }];
    NSMutableArray *didSaveNotificationsA = [NSMutableArray array];
    id token2A = [[NSNotificationCenter defaultCenter] addObserverForName:NSManagedObjectContextDidSaveNotification object:self.uiMOC queue:nil usingBlock:^(NSNotification *note) {
        
        [didSaveNotificationsA addObject:note];
    }];
    NSMutableArray *didSaveNotificationsB = [NSMutableArray array];
    id token2B = [[NSNotificationCenter defaultCenter] addObserverForName:NSManagedObjectContextDidSaveNotification object:self.syncMOC queue:nil usingBlock:^(NSNotification *note) {
        
        [didSaveNotificationsB addObject:note];
    }];
    //
    uiConversation.userDefinedName = @"UI";
    [self.syncMOC performGroupedBlockAndWait:^{
        syncConversation.userDefinedName = @"SYNC";
    }];
    [self.uiMOC saveOrRollback];
    [self.syncMOC performGroupedBlockAndWait:^{
        [self.syncMOC saveOrRollback];
    }];
    
    // stub
    [(id<ZMContextChangeTracker>)[self.mockUpstreamSync1 stub] objectsDidChange:OCMOCK_ANY];
    [(id<ZMContextChangeTracker>)[self.mockUpstreamSync2 stub] objectsDidChange:OCMOCK_ANY];

    // when
    //
    // The conversation in the UI context is still 'USER', and we expect
    // 1 objects-did-cahnge about it changing to 'SYNC'
    [objectsDidChangeNotifications removeAllObjects];
    XCTAssertEqualObjects(uiConversation.userDefinedName, @"UI");
    // MERGE:
    self.sut.contextMergingDisabled = NO;
    [[NSNotificationCenter defaultCenter] removeObserver:token2A];
    [[NSNotificationCenter defaultCenter] removeObserver:token2B];
    for (NSNotification *note in didSaveNotificationsA) {
        [[NSNotificationCenter defaultCenter] postNotification:note];
    }
    for (NSNotification *note in didSaveNotificationsB) {
        [[NSNotificationCenter defaultCenter] postNotification:note];
    }
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqualObjects(uiConversation.userDefinedName, @"SYNC");
    XCTAssertEqual(objectsDidChangeNotifications.count, 1u);
    NSDictionary *userInfo = [(NSNotification *) objectsDidChangeNotifications.lastObject userInfo];
    XCTAssertEqual([userInfo[NSRefreshedObjectsKey] anyObject], uiConversation);
    
    // finally
    [[NSNotificationCenter defaultCenter] removeObserver:token1];
}


- (void)testThatItReturnsTrueForCoversationsThatHasBufferedCallStateEvents
{
    // given
    NSUUID *remoteId = NSUUID.createUUID;
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        conversation.remoteIdentifier = remoteId;
        [self.syncMOC saveOrRollback];
    }];

    NSDictionary *eventData = @{
                                @"id" : @"5cc1ab91-45f4-49ec-bb7a-a5517b7a4173",
                                @"payload" : @[
                                        @{
                                            @"type" : @"call.state",
                                            @"conversation" : remoteId.transportString
                                            }
                                        ]
                                };

    NSArray *events = [ZMUpdateEvent eventsArrayFromPushChannelData:eventData];
    
    [[[self.syncStatusMock stub] andReturnValue:@(YES)] isSyncing];

    // expect
    for(id obj in events) {
        [[self.updateEventsBuffer expect] addUpdateEvent:obj];
    }
    
    [self expectSyncObjectsToProcessEvents:NO
                                liveEvents:YES
                             decryptEvents:NO
                   returnIDsForPrefetching:NO
                                withEvents:events];
    
    [[[self.updateEventsBuffer expect] andReturn:events] updateEvents];
    
    [self.sut processUpdateEvents:events ignoreBuffer:NO];
    
    // when
    NSArray *ids = [self.sut conversationIdsThatHaveBufferedUpdatesForCallState];
    
    // then
    XCTAssertTrue([ids containsObject:remoteId]);
}

- (void)testThatItReturnsFalseForConversationsThatHasNoBufferedCallStateEvents
{
    // given
    NSUUID *remoteId = NSUUID.createUUID;
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        conversation.remoteIdentifier = remoteId;
        [self.syncMOC saveOrRollback];
    }];
    
    NSDictionary *eventData = @{
                                @"id" : @"5cc1ab91-45f4-49ec-bb7a-a5517b7a4173",
                                @"payload" : @[
                                        @{
                                            @"type" : @"call.state",
                                            @"conversation" : NSUUID.createUUID.transportString
                                            }
                                        ]
                                };
    
    NSArray *events = [ZMUpdateEvent eventsArrayFromPushChannelData:eventData];
    
    [[[self.syncStatusMock stub] andReturnValue:@(YES)] isSyncing];

    // expect
    for(id obj in events) {
        [[self.updateEventsBuffer expect] addUpdateEvent:obj];
    }
    
    [self expectSyncObjectsToProcessEvents:NO
                                liveEvents:YES
                             decryptEvents:NO
                   returnIDsForPrefetching:NO
                                withEvents:events];
    
    [[[self.updateEventsBuffer expect] andReturn:events] updateEvents];

    [self.sut processUpdateEvents:events ignoreBuffer:NO];
    
    // when
    NSArray *ids = [self.sut conversationIdsThatHaveBufferedUpdatesForCallState];
    
    // then
    XCTAssertFalse([ids containsObject:remoteId]);
}

- (void)testThatItMergesTheUserInfoOfContexts {
    
    // The security level degradation info is stored in the user info. I'm using this one to verify that it is merged correcly
    // GIVEN
    __block ZMOTRMessage *message;
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        conversation.conversationType = ZMConversationTypeGroup;
        conversation.remoteIdentifier = [NSUUID createUUID];
        
        message = (ZMOTRMessage *)[conversation appendMessageWithText:@"foo bar bar bar"];
        message.causedSecurityLevelDegradation = YES;
        
        // WHEN
        [self.syncMOC saveOrRollback];
    }];
    [self spinMainQueueWithTimeout:0.2];
    
    // THEN
    ZMOTRMessage *uiMessage = [self.uiMOC existingObjectWithID:message.objectID error:nil];
    XCTAssertTrue(uiMessage.causedSecurityLevelDegradation);
}
#pragma mark - Helper

- (NSSet <Class> *)transcodersExpectedToReturnNonces
{
    return @[
             ClientMessageTranscoder.class,
             ].set;
}

- (void)expectSyncObjectsToProcessEvents:(BOOL)process liveEvents:(BOOL)liveEvents decryptEvents:(BOOL)decyptEvents returnIDsForPrefetching:(BOOL)returnIDs withEvents:(id)events;
{
    NOT_USED(decyptEvents);
    
    for (id obj in self.syncObjects) {
        if (![obj conformsToProtocol:@protocol(ZMEventConsumer)]) {
            continue;
        }
        
        if (process) {
            [[obj expect] processEvents:[OCMArg checkWithBlock:^BOOL(NSArray *receivedEvents) {
                return [receivedEvents isEqualToArray:events];
            }] liveEvents:liveEvents prefetchResult:OCMOCK_ANY];
        } else {
            [[obj reject] processEvents:OCMOCK_ANY liveEvents:liveEvents prefetchResult:OCMOCK_ANY];
        }
        
        if (returnIDs) {
            if ([obj respondsToSelector:@selector(messageNoncesToPrefetchToProcessEvents:)]) {
                [[obj expect] messageNoncesToPrefetchToProcessEvents:[OCMArg checkWithBlock:^BOOL(NSArray *receivedEvents) {
                    return [receivedEvents isEqualToArray:events];
                }]];
            }
            if ([obj respondsToSelector:@selector(conversationRemoteIdentifiersToPrefetchToProcessEvents:)]) {
                [[obj expect] conversationRemoteIdentifiersToPrefetchToProcessEvents:[OCMArg checkWithBlock:^BOOL(NSArray *receivedEvents) {
                    return [receivedEvents isEqualToArray:events];
                }]];
            }
        }
    }
}

@end



@implementation ZMSyncStrategyTests (Background)

- (void)goToBackground
{
    [self.application simulateApplicationDidEnterBackground];
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)goToForeground
{
    [self.application simulateApplicationWillEnterForeground];
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatItUpdateOperationStatusWhenTheAppEntersBackground
{
    // expect
    [[self.operationStatusMock expect] setIsInBackground:YES];
    
    // when
    [self goToBackground];
    WaitForAllGroupsToBeEmpty(0.5);
}


- (void)testThatItUpdateOperationStatusWhenTheAppWillEnterForeground
{
    // expect
    [[self.operationStatusMock expect] setIsInBackground:NO];

    // when
    [self goToForeground];
}

- (void)testThatItNotifiesTheOperationLoopOfNewOperationWhenEnteringBackground
{
    // expect
    [[self.operationStatusMock expect] setIsInBackground:YES];
    id mockRequestNotification = [OCMockObject mockForClass:ZMRequestAvailableNotification.class];
    [[[mockRequestNotification expect] classMethod] notifyNewRequestsAvailable:OCMOCK_ANY];

    // when
    [self goToBackground];
    
    // then
    [mockRequestNotification verify];
    [mockRequestNotification stopMocking];
}

- (void)testThatItNotifiesTheOperationLoopOfNewOperationWhenEnteringForeground
{
    // expect
    [[self.operationStatusMock expect] setIsInBackground:NO];
    id mockRequestAvailableNotification = [OCMockObject mockForClass:ZMRequestAvailableNotification.class];
    [[mockRequestAvailableNotification expect] notifyNewRequestsAvailable:OCMOCK_ANY];
    
    // when
    [self goToForeground];
    
    // then
    [mockRequestAvailableNotification verify];
    [mockRequestAvailableNotification stopMocking];
}

- (void)testThatItUpdatesTheBadgeCount
{
    // given
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        conversation.conversationType = ZMConversationTypeGroup;
        conversation.internalEstimatedUnreadCount = 1;
        [self.syncMOC saveOrRollback];
        
        // when
        [self.sut updateBadgeCount];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(self.application.applicationIconBadgeNumber, 1);
}

@end


@implementation ZMSyncStrategyTests (SyncStateDelegate)

- (void)testThatItNotifiesSyncStateDelegateWhenSyncStarts
{    
    // expect
    [[self.syncStateDelegate expect] didStartSync];
    
    // when
    [self.sut didStartSync];
    
    // then
    [self.syncStateDelegate verify];
}


- (void)testThatItNotifiesSyncObserverWhenSyncCompletes
{
    // given
    [[self.updateEventsBuffer stub] processAllEventsInBuffer];

    id mockObserver = [OCMockObject niceMockForProtocol:@protocol(ZMInitialSyncCompletionObserver)];
    [ZMUserSession addInitalSyncCompletionObserver:mockObserver];

    // expect
    [[mockObserver expect] initialSyncCompleted:OCMOCK_ANY];

    // when
    [self.sut didFinishSync];

    // then
    XCTAssert([self waitForCustomExpectationsWithTimeout:0.5]);


    // tearDown
    [ZMUserSession removeInitalSyncCompletionObserver:mockObserver];

    [self performIgnoringZMLogError:^{
        WaitForAllGroupsToBeEmpty(0.5);
    }];
}

- (void)testThatItProcessesAllEventsInBufferWhenSyncFinishes
{
    // expect
    [[self.updateEventsBuffer expect] processAllEventsInBuffer];

    // when
    [self.sut didFinishSync];

    // then
    [self.updateEventsBuffer verify];

    [self performIgnoringZMLogError:^{
        WaitForAllGroupsToBeEmpty(0.5);
    }];
}

@end
