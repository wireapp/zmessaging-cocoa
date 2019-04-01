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
@import WireRequestStrategy;
@import OCMock;


#import "MessagingTest.h"
#import "ZMUserSession+Internal.h"
#import "ZMSyncStrategy+Internal.h"
#import "ZMSyncStrategy+ManagedObjectChanges.h"
#import "ZMUpdateEventsBuffer.h"
#import "ZMOperationLoop.h"
#import "MessagingTest+EventFactory.h"
#import "WireSyncEngine_iOS_Tests-Swift.h"

// Transcoders & strategies
#import "ZMUserTranscoder.h"
#import "ZMConversationTranscoder.h"
#import "ZMSelfStrategy.h"
#import "ZMMissingUpdateEventsTranscoder.h"
#import "ZMConnectionTranscoder.h"
#import "MessagingTest+EventFactory.h"
#import "WireSyncEngine_iOS_Tests-Swift.h"

@interface OCMockObject (TearDown)
- (void)tearDown;
@end

// Only needed to be able to call these internal OCMock methods on teardown
@protocol MockOCMockMock <NSObject>
- (NSInvocation *)recordedInvocation;

@end

// A lot of objects end up in retain cycles because of extensive mocking.
// We need to break them manually by releasing some of the internal arrays
@implementation OCMockObject (TearDown)
- (void)tearDown
{
    for (id recorder in stubs) {
        objc_removeAssociatedObjects([recorder recordedInvocation]);
    }
    [stubs removeAllObjects];
    [exceptions removeAllObjects];
    [expectations removeAllObjects];
    [invocations removeAllObjects];
}

@end


@interface ZMSyncStrategyTests : MessagingTest <ZMRequestCancellation, ZMSyncStateDelegate>

@property (nonatomic) ZMSyncStrategy *sut;

@property (nonatomic) NSArray *syncObjects;
@property (nonatomic) id updateEventsBuffer;
@property (nonatomic) MockSyncStateDelegate *syncStateDelegate;
@property (nonatomic) id conversationTranscoder;
@property (nonatomic) id userTranscoder;
@property (nonatomic) id clientMessageTranscoder;
@property (nonatomic) id connectionTranscoder;
@property (nonatomic) ApplicationStatusDirectory *applicationStatusDirectory;

@property (nonatomic) BOOL shouldStubContextChangeTrackers;
@property (nonatomic) id mockUpstreamSync1;
@property (nonatomic) id mockUpstreamSync2;
@property (nonatomic) NSFetchRequest *fetchRequestForTrackedObjects1;
@property (nonatomic) NSFetchRequest *fetchRequestForTrackedObjects2;
@property (nonatomic) id mockDispatcher;
@property (nonatomic) FlowManagerMock *mockflowManager;
@property (nonatomic) id syncStatusMock;
@property (nonatomic) id operationStatusMock;
@property (nonatomic) id applicationStatusDirectoryMock;
@property (nonatomic) id userProfileImageUpdateStatus;
@property (nonatomic) id<LocalStoreProviderProtocol> storeProvider;

@end

@implementation ZMSyncStrategyTests;

- (void)cancelTaskWithIdentifier:(ZMTaskIdentifier *)taskIdentifier
{
    NOT_USED(taskIdentifier);
}

- (void)didStartSlowSync { }

- (void)didFinishSlowSync { }

- (void)didStartQuickSync { }

- (void)didFinishQuickSync { }

- (void)didRegisterUserClient:(UserClient *)userClient
{
    NOT_USED(userClient);
}

- (void)setUp
{
    [super setUp];
    
    ZMUser *selfUser = [ZMUser selfUserInContext:self.syncMOC];
    selfUser.remoteIdentifier = self.userIdentifier;
    
    ZMConversation *selfConversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
    selfConversation.remoteIdentifier = self.userIdentifier;
    selfConversation.conversationType = ZMConversationTypeSelf;
    
    [self.syncMOC saveOrRollback];
    
    self.mockDispatcher = [OCMockObject mockForClass:[LocalNotificationDispatcher class]];
    [(LocalNotificationDispatcher *)[self.mockDispatcher stub] tearDown];
    [(LocalNotificationDispatcher *)[self.mockDispatcher stub] processEvents:OCMOCK_ANY liveEvents:YES prefetchResult:OCMOCK_ANY];
    self.mockUpstreamSync1 = [OCMockObject mockForClass:[ZMUpstreamModifiedObjectSync class]];
    self.mockUpstreamSync2 = [OCMockObject mockForClass:[ZMUpstreamModifiedObjectSync class]];
    [self verifyMockLater:self.mockUpstreamSync1];
    [self verifyMockLater:self.mockUpstreamSync2];
    
    self.syncStateDelegate = [[MockSyncStateDelegate alloc] init];
    
    self.syncStatusMock = [OCMockObject mockForClass:SyncStatus.class];
    self.operationStatusMock = [OCMockObject mockForClass:OperationStatus.class];
    self.userProfileImageUpdateStatus = [OCMockObject mockForClass:UserProfileImageUpdateStatus.class];
    self.mockflowManager = [[FlowManagerMock alloc] init];
    
    self.applicationStatusDirectoryMock = [OCMockObject niceMockForClass:ApplicationStatusDirectory.class];
    [[[[self.applicationStatusDirectoryMock expect] andReturn: self.applicationStatusDirectoryMock] classMethod] alloc];
    (void) [[[self.applicationStatusDirectoryMock stub] andReturn:self.applicationStatusDirectoryMock] initWithManagedObjectContext:OCMOCK_ANY cookieStorage:OCMOCK_ANY requestCancellation:OCMOCK_ANY application:OCMOCK_ANY syncStateDelegate:OCMOCK_ANY analytics:nil];
    [[[self.applicationStatusDirectoryMock stub] andReturn:self.syncStatusMock] syncStatus];
    [[[self.applicationStatusDirectoryMock stub] andReturn:self.operationStatusMock] operationStatus];
    [(ApplicationStatusDirectory *)[[self.applicationStatusDirectoryMock stub] andReturn:self.userProfileImageUpdateStatus] userProfileImageUpdateStatus];
    AssetDeletionStatus *deletionStatus = [[AssetDeletionStatus alloc] initWithProvider:self.syncMOC queue:self.syncMOC];
    [(ApplicationStatusDirectory *)[[self.applicationStatusDirectoryMock stub] andReturn:deletionStatus] assetDeletionStatus];

    id userTranscoder = [OCMockObject mockForClass:ZMUserTranscoder.class];
    [[[[userTranscoder expect] andReturn:userTranscoder] classMethod] alloc];
    (void) [[[userTranscoder stub] andReturn:userTranscoder] initWithManagedObjectContext:self.syncMOC applicationStatus:OCMOCK_ANY syncStatus:OCMOCK_ANY];
    self.userTranscoder = userTranscoder;
    
    self.conversationTranscoder = [OCMockObject mockForClass:ZMConversationTranscoder.class];
    [[[[self.conversationTranscoder expect] andReturn:self.conversationTranscoder] classMethod] alloc];
    (void) [[[self.conversationTranscoder stub] andReturn:self.conversationTranscoder] initWithManagedObjectContext:OCMOCK_ANY applicationStatus:OCMOCK_ANY localNotificationDispatcher:OCMOCK_ANY syncStatus:OCMOCK_ANY];

    id clientMessageTranscoder = [OCMockObject mockForClass:ClientMessageTranscoder.class];
    [[[[clientMessageTranscoder expect] andReturn:clientMessageTranscoder] classMethod] alloc];
    (void) [[[clientMessageTranscoder expect] andReturn:clientMessageTranscoder] initIn:OCMOCK_ANY localNotificationDispatcher:self.mockDispatcher applicationStatus:OCMOCK_ANY];
    self.clientMessageTranscoder = clientMessageTranscoder;
    
    id connectionTranscoder = [OCMockObject mockForClass:ZMConnectionTranscoder.class];
    [[[[connectionTranscoder expect] andReturn:connectionTranscoder] classMethod] alloc];
    (void) [[[connectionTranscoder stub] andReturn:connectionTranscoder] initWithManagedObjectContext:OCMOCK_ANY applicationStatus:OCMOCK_ANY syncStatus:OCMOCK_ANY];
    self.connectionTranscoder = connectionTranscoder;
    
    self.updateEventsBuffer = [OCMockObject mockForClass:ZMUpdateEventsBuffer.class];
    [[[[self.updateEventsBuffer expect] andReturn:self.updateEventsBuffer] classMethod] alloc];
    (void) [[[self.updateEventsBuffer stub] andReturn:self.updateEventsBuffer] initWithUpdateEventConsumer:OCMOCK_ANY];
    [self verifyMockLater:self.updateEventsBuffer];
    
    self.syncObjects = @[
                         connectionTranscoder,
                         self.userTranscoder,
                         self.conversationTranscoder,
                         clientMessageTranscoder,
    ];
    
    for(ZMObjectSyncStrategy *strategy in self.syncObjects) {
        [self verifyMockLater:strategy];
    }
    self.fetchRequestForTrackedObjects1 = [NSFetchRequest fetchRequestWithEntityName:@"User"];
    self.fetchRequestForTrackedObjects1.predicate = [NSPredicate predicateWithFormat:@"name != nil"];
    self.fetchRequestForTrackedObjects2 = [NSFetchRequest fetchRequestWithEntityName:@"Conversation"];
    self.fetchRequestForTrackedObjects2.predicate = [NSPredicate predicateWithFormat:@"userDefinedName != nil"];
    
    [self stubChangeTrackerBootstrapInitialization];
    
    self.storeProvider = [[MockLocalStoreProvider alloc] initWithSharedContainerDirectory:self.sharedContainerURL userIdentifier:self.userIdentifier contextDirectory:self.contextDirectory];
    self.applicationStatusDirectory = [[ApplicationStatusDirectory alloc] initWithManagedObjectContext:self.syncMOC cookieStorage:[[FakeCookieStorage alloc] init] requestCancellation:self application:self.application syncStateDelegate:self analytics:nil];
    
    self.sut = [[ZMSyncStrategy alloc] initWithStoreProvider:self.storeProvider
                                               cookieStorage:nil
                                                 flowManager:self.mockflowManager
                                localNotificationsDispatcher:self.mockDispatcher
                                     notificationsDispatcher:[[NotificationDispatcher alloc] initWithManagedObjectContext:self.contextDirectory.uiContext]
                                  applicationStatusDirectory:self.applicationStatusDirectory
                                                 application:self.application];
    
    self.application.applicationState = UIApplicationStateBackground;
    XCTAssertEqual(self.sut.userTranscoder, self.userTranscoder);
    XCTAssertEqual(self.sut.conversationTranscoder, self.conversationTranscoder);
    XCTAssertEqual(self.sut.clientMessageTranscoder, clientMessageTranscoder);

    XCTAssertEqual(self.sut.connectionTranscoder, connectionTranscoder);
    
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
    self.applicationStatusDirectory = nil;
    self.fetchRequestForTrackedObjects1 = nil;
    self.fetchRequestForTrackedObjects2 = nil;
    [self.mockDispatcher tearDown];
    [self.mockDispatcher stopMocking];
    self.mockDispatcher = nil;
    [self.mockUpstreamSync1 stopMocking];
    [self.mockUpstreamSync1 tearDown];
    self.mockUpstreamSync1 = nil;
    [self.mockUpstreamSync2 stopMocking];
    [self.mockUpstreamSync2 tearDown];
    self.mockUpstreamSync2 = nil;
    self.syncStateDelegate = nil;
    [self.userProfileImageUpdateStatus tearDown];
    [self.userProfileImageUpdateStatus stopMocking];
    self.userProfileImageUpdateStatus = nil;
    [self.applicationStatusDirectoryMock tearDown];
    [self.applicationStatusDirectoryMock stopMocking];
    self.applicationStatusDirectoryMock = nil;
    [self.userTranscoder tearDown];
    [self.userTranscoder stopMocking];
    self.userTranscoder = nil;
    [self.conversationTranscoder tearDown];
    [self.conversationTranscoder stopMocking];
    self.conversationTranscoder = nil;
    [self.clientMessageTranscoder tearDown];
    [self.clientMessageTranscoder stopMocking];
    self.clientMessageTranscoder = nil;
    [self.connectionTranscoder tearDown];
    [self.connectionTranscoder stopMocking];
    self.connectionTranscoder = nil;
    [self.operationStatusMock tearDown];
    self.mockflowManager = nil;
    [self.operationStatusMock stopMocking];
    self.operationStatusMock = nil;
    [self.syncStatusMock tearDown];
    [self.syncStatusMock stopMocking];
    self.syncStatusMock = nil;
    self.storeProvider = nil;
    [self.sut tearDown];
    for (id syncObject in self.syncObjects) {
        if ([syncObject respondsToSelector:@selector(tearDown)]) {
            [syncObject tearDown];
        }
        if ([syncObject respondsToSelector:@selector(stopMocking)]) {
            [syncObject stopMocking];
        }
    }
    
    [self.updateEventsBuffer tearDown];
    [self.updateEventsBuffer stopMocking];
    self.updateEventsBuffer = nil;

    self.sut = nil;
    self.syncObjects = nil;
    [super tearDown];
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
                                          @"data" : @{},
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
                                     @"data" : @{},
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
    ZMFetchRequestBatch *fetchRequest = [self.sut prefetchRequestForUpdateEvents:events];
    NOT_USED(fetchRequest);
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
    for (id syncObject in self.syncObjects) {
        
        if ([syncObject conformsToProtocol:@protocol(ZMContextChangeTrackerSource)]) {
            [(ZMUpstreamModifiedObjectSync*)[[self.mockUpstreamSync1 stub] andReturn:self.fetchRequestForTrackedObjects1] fetchRequestForTrackedObjects];
            [(ZMUpstreamModifiedObjectSync*)[[self.mockUpstreamSync2 stub] andReturn:self.fetchRequestForTrackedObjects2] fetchRequestForTrackedObjects];
            
            [[self.mockUpstreamSync1 expect] addTrackedObjects:[NSSet setWithObject:user]];
            [[self.mockUpstreamSync2 expect] addTrackedObjects:[NSSet setWithObject:conversation]];
            [self verifyMockLater:syncObject];
        }
        [[syncObject stub] nextRequest];
    }
    
    // when
    (void)[self.sut nextRequest];
}

- (void)testThatManagedObjectChangesArePassedToAllSyncObjectsCaches
{
    
    // given
    id firstObject = [[ZMManagedObject alloc] init];
    id secondObject = [[ZMManagedObject alloc] init];
    
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

- (void)expectSyncObjectsToGiveNextRequest
{
    for (id obj in self.syncObjects) {
        if ([obj conformsToProtocol:@protocol(RequestStrategy)]) {
            [[obj stub] nextRequest];
        }
    }
}

- (void)expectSyncObjectsToProcessEvents:(BOOL)process liveEvents:(BOOL)liveEvents decryptEvents:(BOOL)decyptEvents returnIDsForPrefetching:(BOOL)returnIDs withEvents:(NSArray *)events;
{
    NOT_USED(decyptEvents);
    
    for (id obj in self.syncObjects) {
        if (![obj conformsToProtocol:@protocol(ZMEventConsumer)]) {
            continue;
        }
        
        if (process) {
            for (id event in events) {
                [[obj expect] processEvents:@[event] liveEvents:YES prefetchResult:OCMOCK_ANY];
            }
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

@end
