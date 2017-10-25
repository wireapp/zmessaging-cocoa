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
@import WireSyncEngine;

#import <Foundation/Foundation.h>

#import "MessagingTest.h"
#import "ZMSyncStateDelegate.h"
#import "ZMMissingUpdateEventsTranscoder+Internal.h"
#import "ZMSyncStrategy+EventProcessing.h"
#import "ZMSimpleListRequestPaginator.h"
#import <WireSyncEngine/WireSyncEngine-Swift.h>
#import "WireSyncEngine_iOS_Tests-Swift.h"


static NSString * const LastUpdateEventIDStoreKey = @"LastUpdateEventID";

@interface ZMMissingUpdateEventsTranscoderTests : MessagingTest

@property (nonatomic, readonly) ZMMissingUpdateEventsTranscoder *sut;
@property (nonatomic, readonly) id syncStrategy;
@property (nonatomic, readonly) id<PreviouslyReceivedEventIDsCollection> mockEventIDsCollection;
@property (nonatomic, readonly) id mockPingbackStatus;
@property (nonatomic) id requestSync;
@property (nonatomic) MockSyncStatus *mockSyncStatus;
@property (nonatomic) OperationStatus *mockOperationStatus;
@property (nonatomic) id syncStateDelegate;
@property (nonatomic) id mockApplicationDirectory;

@end

@implementation ZMMissingUpdateEventsTranscoderTests

- (void)setUp {
    [super setUp];
    
    self.requestSync = [OCMockObject mockForClass:ZMSingleRequestSync.class];
    self.syncStateDelegate = [OCMockObject niceMockForProtocol:@protocol(ZMSyncStateDelegate)];
    self.mockSyncStatus = [[MockSyncStatus alloc] initWithManagedObjectContext:self.syncMOC syncStateDelegate:self.syncStateDelegate];
    self.mockSyncStatus.mockPhase = SyncPhaseDone;
    self.mockOperationStatus = [[OperationStatus alloc] init];
    self.mockOperationStatus.isInBackground = NO;
    
    self.mockApplicationDirectory = [OCMockObject niceMockForClass:ZMApplicationStatusDirectory.class];
    [[[self.mockApplicationDirectory stub] andReturnValue:@(ZMSynchronizationStateSynchronizing)] synchronizationState];
    [[[self.mockApplicationDirectory stub] andReturn:self.mockOperationStatus] operationStatus];
    
    _syncStrategy = [OCMockObject niceMockForClass:ZMSyncStrategy.class];
    _mockEventIDsCollection = OCMProtocolMock(@protocol(PreviouslyReceivedEventIDsCollection));
    _mockPingbackStatus = [OCMockObject niceMockForClass:BackgroundAPNSPingBackStatus.class];
    [[[(id) self.syncStrategy stub] andReturn:self.uiMOC] syncMOC];
    [[[(id) self.syncStrategy stub] andReturn:self.mockApplicationDirectory] applicationStatusDirectory];
    [self verifyMockLater:self.syncStrategy];
    [self verifyMockLater:self.mockPingbackStatus];
    
    _sut = [[ZMMissingUpdateEventsTranscoder alloc] initWithSyncStrategy:self.syncStrategy
                                    previouslyReceivedEventIDsCollection:(id)self.mockEventIDsCollection
                                                             application:(id)self.application
                                            backgroundAPNSPingbackStatus:self.mockPingbackStatus
                                                          syncStatus:self.mockSyncStatus];
}

- (void)tearDown {
    [_syncStrategy stopMocking];
    _syncStrategy = nil;
    
    _mockEventIDsCollection = nil;
    
    [_mockPingbackStatus stopMocking];
    _mockPingbackStatus = nil;

    _requestSync = nil;
    _mockSyncStatus = nil;
    _mockOperationStatus = nil;
    
    [_syncStateDelegate stopMocking];
    _syncStateDelegate = nil;
    
    [_mockApplicationDirectory stopMocking];
    _mockApplicationDirectory = nil;
    
    _sut = nil;
    
    [super tearDown];
}

@end


@implementation ZMMissingUpdateEventsTranscoderTests (MissingNotifications)

- (NSUUID *)olderNotificationID {
    return [NSUUID uuidWithTransportString:@"a6526b00-000a-11e5-a837-0800200c9a66"];
}

- (NSUUID *)newNotificationID {
    return [NSUUID uuidWithTransportString:@"54ad4672-be09-11e5-9912-ba0be0483c18"];
}

- (void)testThatItGenerateARequestToFetchNotificationStreamWhenSyncing
{
    // given
    self.mockSyncStatus.mockPhase = SyncPhaseFetchingMissedEvents;
    
    // when
    ZMTransportRequest *request = self.sut.nextRequest;
    
    // then
    XCTAssertEqualObjects(request.path, @"/notifications?size=500");
}

- (void)testThatItFinishCurrentSyncPhaseIfThereIsNoMoreNotificationsToFetch
{
    // given
    self.mockSyncStatus.mockPhase = SyncPhaseFetchingMissedEvents;
    
    // when
    ZMTransportRequest *request = self.sut.nextRequest;
    [request completeWithResponse:[self responseForSettingLastUpdateEventID:[NSUUID createUUID] hasMore:NO]];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertTrue(self.mockSyncStatus.didCallFinishCurrentSyncPhase);
}

- (void)testThatItforwardsToDownstreamSyncOnStartDownloadingMissingNotifications
{
    // expect
    id missingUpdateEventsTranscoder = [OCMockObject partialMockForObject:self.sut.listPaginator];
    [[missingUpdateEventsTranscoder expect] resetFetching];
    
    // when
    [self.sut startDownloadingMissingNotifications];
    [missingUpdateEventsTranscoder verify];
}

- (void)testThatItGetsRequestFromDownstreamSync
{
    // given
    [[[self.mockPingbackStatus stub] andReturnValue:@(YES)] hasNotificationIDs];
    [(BackgroundAPNSPingBackStatus *)[[self.mockPingbackStatus stub] andReturnValue:@(BackgroundNotificationFetchStatusInProgress)] status];
    [self.application setBackground];
    
    id missingUpdateEventsTranscoder = [OCMockObject partialMockForObject:self.sut.listPaginator];
    ZMTransportRequest *expectedRequest = [ZMTransportRequest requestGetFromPath:@"555555"];
    
    // expect
    [[[missingUpdateEventsTranscoder expect] andReturn:expectedRequest] nextRequest];
    
    // when
    ZMTransportRequest *request = [self.sut nextRequest];
    
    // then
    XCTAssertEqual(request, expectedRequest);
    [missingUpdateEventsTranscoder verify];
}

- (void)testThatIsDownloadingWhenTheDownstreamSyncIsInProgress
{
    // given
    id missingUpdateEventsTranscoder = [OCMockObject partialMockForObject:self.sut.listPaginator];
    (void)[ (ZMSimpleListRequestPaginator *) [[missingUpdateEventsTranscoder stub] andReturnValue:OCMOCK_VALUE(YES)] hasMoreToFetch];
    
    // when
    XCTAssertTrue(self.sut.isDownloadingMissingNotifications);
}

- (void)testThatIsNotDownloadingWhenTheDownstreamSyncIsIdle
{
    // given
    id missingUpdateEventsTranscoder = [OCMockObject partialMockForObject:self.sut.listPaginator];
    (void)[ (ZMSimpleListRequestPaginator *) [[missingUpdateEventsTranscoder stub] andReturnValue:OCMOCK_VALUE(NO)] hasMoreToFetch];
    
    // when
    XCTAssertFalse(self.sut.isDownloadingMissingNotifications);
}

- (void)testThatItReturnANotificationRequestWhenAskedToStartDownload
{
    // when
    [self.sut startDownloadingMissingNotifications];
    ZMTransportRequest *request = [self.sut.listPaginator nextRequest];
    
    // then
    XCTAssertNotNil(request);
    XCTAssertEqualObjects([NSURLComponents componentsWithString:request.path].path, @"/notifications");
    XCTAssertEqual(request.method, ZMMethodGET);
}

- (void)testThatItPassesTheDownloadedEventsToTheSyncStrategyOnSuccess
{
    // when
    NSDictionary *payload1 = @{
                               @"id" : [NSUUID createUUID].transportString,
                               @"payload" : @[
                                       @{
                                           @"type" : @"conversation.message-add",
                                           },
                                       ]
                              };
    NSDictionary *payload2 = @{
                               @"id" : [NSUUID createUUID].transportString,
                               @"payload" : @[
                                       @{
                                           @"type" : @"conversation.message-add",
                                           },
                                       ]
                               };
    
    NSDictionary *payload = @{@"notifications" : @[payload1, payload2]};
    
    NSMutableArray *expectedEvents = [NSMutableArray array];
    [expectedEvents addObjectsFromArray:[ZMUpdateEvent eventsArrayFromPushChannelData:payload1]];
    [expectedEvents addObjectsFromArray:[ZMUpdateEvent eventsArrayFromPushChannelData:payload2]];

    // expect
    [[(id)self.syncStrategy expect] processUpdateEvents:expectedEvents ignoreBuffer:YES];
    
    // when
    [(id)self.sut.listPaginator didReceiveResponse:[ZMTransportResponse responseWithPayload:payload HTTPStatus:200 transportSessionError:nil] forSingleRequest:self.requestSync];
}

- (void)testThatItPassesTheDownloadedEventsToTheSyncStrategyOn404
{
    // when
    NSDictionary *payload1 = @{
                               @"id" : [NSUUID createUUID].transportString,
                               @"payload" : @[
                                       @{
                                           @"type" : @"conversation.message-add",
                                           @"time" : [NSDate date].transportString
                                           },
                                       ]
                               };
    NSDictionary *payload2 = @{
                               @"id" : [NSUUID createUUID].transportString,
                               @"payload" : @[
                                       @{
                                           @"type" : @"conversation.message-add",
                                           @"time" : [NSDate date].transportString
                                           },
                                       ]
                               };
    
    NSDictionary *payload = @{@"notifications" : @[payload1, payload2]};
    
    NSMutableArray *expectedEvents = [NSMutableArray array];
    [expectedEvents addObjectsFromArray:[ZMUpdateEvent eventsArrayFromPushChannelData:payload1]];
    [expectedEvents addObjectsFromArray:[ZMUpdateEvent eventsArrayFromPushChannelData:payload2]];
    
    // expect
    [[(id)self.syncStrategy expect] processUpdateEvents:expectedEvents ignoreBuffer:YES];
    
    // when
    [(id)self.sut.listPaginator didReceiveResponse:[ZMTransportResponse responseWithPayload:payload HTTPStatus:404 transportSessionError:nil] forSingleRequest:self.requestSync];
}

- (void)testThatHasNoLastUpdateEventIDOnStartup
{
    XCTAssertFalse(self.sut.hasLastUpdateEventID);
}

- (void)setLastUpdateEventID:(NSUUID *)uuid hasMore:(BOOL)hasMore
{
    // given
    ZMTransportResponse *response = [self responseForSettingLastUpdateEventID:uuid hasMore:hasMore];
    
    // when
    [(id)self.sut.listPaginator didReceiveResponse:response forSingleRequest:self.requestSync];
}


- (ZMTransportResponse *)responseForSettingLastUpdateEventID:(NSUUID *)uuid hasMore:(BOOL)hasMore
{
    // given
    NSDictionary *innerPayload = @{
                                   @"id" : uuid.transportString,
                                   @"payload" : @[
                                           @{
                                               @"type" : @"conversation.message-add",
                                               },
                                           ]
                                   };
    
    
    NSDictionary *payload = @{@"notifications" : @[innerPayload],
                              @"has_more" : @(hasMore)
                              };
    
    return [ZMTransportResponse responseWithPayload:payload HTTPStatus:200 transportSessionError:nil];
}

- (void)testThatItHasALastUpdateEventIDAfterFetchingNotifications
{
    
    // given
    [self setLastUpdateEventID:[NSUUID createUUID] hasMore:NO];
    
    // then
    XCTAssertTrue(self.sut.hasLastUpdateEventID);
}


- (void)testThatItDoesNotHaveALastUpdateEventIDAfterFailingToFetchNotifications
{
    // given
    NSDictionary *innerPayload = @{
                                   @"id" : [NSUUID createUUID].transportString,
                                   @"payload" : @[
                                           @{
                                               @"type" : @"conversation.message-add",
                                               },
                                           ]
                                   };
    
    
    NSDictionary *payload = @{@"notifications" : @[innerPayload]};
    
    NSMutableArray *expectedEvents = [NSMutableArray array];
    [expectedEvents addObjectsFromArray:[ZMUpdateEvent eventsArrayFromPushChannelData:innerPayload]];
    
    // when
    [(id)self.sut.listPaginator didReceiveResponse:[ZMTransportResponse responseWithPayload:payload HTTPStatus:400 transportSessionError:nil] forSingleRequest:self.requestSync];

    
    // then
    XCTAssertFalse(self.sut.hasLastUpdateEventID);
}


- (void)testThatItPaginatesTheRequests
{
    // given
    NSUUID *lastUpdateEventID = [NSUUID createUUID];
    NSNumber *pageSize = @(ZMMissingUpdateEventsTranscoderListPageSize);
    
    // when
    // the lastUpdateEventTranscoder might persist the lastUpdateEventID
    [self setLastUpdateEventID:lastUpdateEventID hasMore:NO];
    [self.sut startDownloadingMissingNotifications];
    
    WaitForAllGroupsToBeEmpty(0.5);
    
    ZMTransportRequest *request = [self.sut.listPaginator nextRequest];
    
    // then
    NSURLComponents *components = [NSURLComponents componentsWithString:request.path];
    XCTAssertTrue([components.queryItems containsObject:[NSURLQueryItem queryItemWithName:@"size" value:[pageSize stringValue]]], @"missing valid since parameter");
}

- (void)testThatWhenItHasALastUpdateEventIDItUsesItInTheRequest
{
    // given
    NSUUID *lastUpdateEventID = [NSUUID createUUID];
    
    // when
    // the lastUpdateEventTranscoder might persist the lastUpdateEventID
    [self setLastUpdateEventID:lastUpdateEventID hasMore:NO];
    [self.sut startDownloadingMissingNotifications];

    WaitForAllGroupsToBeEmpty(0.5);
    
    ZMTransportRequest *request = [self.sut.listPaginator nextRequest];
    
    // then
    NSURLComponents *components = [NSURLComponents componentsWithString:request.path];
    XCTAssertTrue([components.queryItems containsObject:[NSURLQueryItem queryItemWithName:@"since" value:lastUpdateEventID.transportString]], @"missing valid since parameter");
}

- (void)testThatTheLastUpdateEventIDIsReadFromTheManagedObjectContext
{
    // given
    NSUUID *lastUpdateEventID = [NSUUID createUUID];

    [self.syncMOC setPersistentStoreMetadata:lastUpdateEventID.UUIDString forKey:LastUpdateEventIDStoreKey];
    [self.syncMOC saveOrRollback];
    WaitForAllGroupsToBeEmpty(0.5);

    // when
    ZMMissingUpdateEventsTranscoder *sut = [[ZMMissingUpdateEventsTranscoder alloc] initWithSyncStrategy:self.syncStrategy
                                                                    previouslyReceivedEventIDsCollection:(id)self.mockEventIDsCollection
                                                                                             application:(id)self.application
                                                                            backgroundAPNSPingbackStatus:self.mockPingbackStatus
                                                                                          syncStatus:self.mockSyncStatus];
    WaitForAllGroupsToBeEmpty(0.5);
    [sut.listPaginator resetFetching];
    ZMTransportRequest *request = [sut.listPaginator nextRequest];
    
    // then
    NSURLComponents *components = [NSURLComponents componentsWithString:request.path];
    XCTAssertTrue([components.queryItems containsObject:[NSURLQueryItem queryItemWithName:@"since" value:lastUpdateEventID.transportString]], @"missing valid since parameter");
}

- (void)testThatTheClientIDFromTheUserClientIsIncludedInRequest
{
    // Given
    UserClient *userClient = [self setupSelfClientInMoc:self.uiMOC];
    [self.sut startDownloadingMissingNotifications];
    
    // when
    ZMTransportRequest *request = [self.sut.listPaginator nextRequest];
    
    // then
    NSURLComponents *components = [NSURLComponents componentsWithString:request.path];
    XCTAssertTrue([components.queryItems containsObject:[NSURLQueryItem queryItemWithName:@"client" value:userClient.remoteIdentifier]], @"missing client parameter");
}


- (void)testThatItStoresTheLastUpdateEventIDWhenDownloadingNotifications
{
    // when
    NSUUID *expectedLastUpdateEventID = [NSUUID createUUID];
    [self setLastUpdateEventID:expectedLastUpdateEventID hasMore:NO];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    NSUUID *lastUpdateEventID = [[self.uiMOC persistentStoreMetadataForKey:LastUpdateEventIDStoreKey] UUID];
    XCTAssertEqualObjects(lastUpdateEventID, expectedLastUpdateEventID);
}

- (void)testThatItStoresTheLastUpdateEventIDWhenItIsAMoreRecentType1
{
    // given
    [self setLastUpdateEventID:[self olderNotificationID] hasMore:NO];
    
    // when
    [self setLastUpdateEventID:[self newNotificationID] hasMore:NO];
    
    // then
    NSUUID *lastUpdateEventID = [[self.uiMOC persistentStoreMetadataForKey:LastUpdateEventIDStoreKey] UUID];
    XCTAssertEqualObjects(lastUpdateEventID, [self newNotificationID]);
}

- (void)testThatItDoesNotStoreTheLastUpdateEventIDWhenItIsNotAMoreRecentType1
{
    // given
    [self setLastUpdateEventID:[self newNotificationID] hasMore:NO];
    
    // when
    [self setLastUpdateEventID:[self olderNotificationID] hasMore:NO];
    
    // then
    NSUUID *lastUpdateEventID = [[self.uiMOC persistentStoreMetadataForKey:LastUpdateEventIDStoreKey] UUID];
    XCTAssertEqualObjects(lastUpdateEventID, [self newNotificationID]);
}

- (void)testThatItStoresTheLastUpdateEventIDWhenItIsNotAType1
{
    // given
    NSUUID *secondUUID = [NSUUID createUUID];
    [self setLastUpdateEventID:[self newNotificationID] hasMore:NO];
    
    // when
    [self setLastUpdateEventID:secondUUID hasMore:NO];
    
    // then
    NSUUID *lastUpdateEventID = [[self.uiMOC persistentStoreMetadataForKey:LastUpdateEventIDStoreKey] UUID];
    XCTAssertEqualObjects(lastUpdateEventID, secondUUID);
}

- (void)testThatItStoresTheLastUpdateEventIDWhenThePreviousOneIsNotAType1
{
    // given
    NSUUID *firstUUID = [NSUUID createUUID];
    [self setLastUpdateEventID:firstUUID hasMore:NO];
    
    // when
    [self setLastUpdateEventID:[self newNotificationID] hasMore:NO];
    
    // then
    NSUUID *lastUpdateEventID = [[self.uiMOC persistentStoreMetadataForKey:LastUpdateEventIDStoreKey] UUID];
    XCTAssertEqualObjects(lastUpdateEventID, [self newNotificationID]);
}

- (void)testThatItStoresTheLastUpdateEventIDWhenReceivingNonTransientUpdateEvents
{
    // given
    NSUUID *expectedLastUpdateEventID = [NSUUID createUUID];
    id <ZMTransportData> payload = [self updateEventTransportDataWithID:expectedLastUpdateEventID];
    ZMUpdateEvent *event = [ZMUpdateEvent eventsArrayFromPushChannelData:payload].firstObject;
    
    // when
    [self.sut processEvents:@[event] liveEvents:YES prefetchResult:nil];
    
    // then
    NSUUID *lastUpdateEventID = [[self.uiMOC persistentStoreMetadataForKey:LastUpdateEventIDStoreKey] UUID];
    XCTAssertEqualObjects(lastUpdateEventID, expectedLastUpdateEventID);
}

- (void)testThatItDoesStoreTheLastUpdateEventIDWhenEventIDSourceIsWebsocketOrDownload
{
    // given
    NSUUID *websocketUpdateEventID = NSUUID.createUUID;
    NSUUID *downstreamUpdateEventID = NSUUID.createUUID;
    NSUUID *notificationUpdateEventID = NSUUID.createUUID;
    
    ZMUpdateEvent *websocketEvent = [self updateEventWithIdentifier:websocketUpdateEventID source:ZMUpdateEventSourceWebSocket];
    ZMUpdateEvent *downloadedEvent = [self updateEventWithIdentifier:downstreamUpdateEventID source:ZMUpdateEventSourceDownload];
    ZMUpdateEvent *pushNotificationEvent = [self updateEventWithIdentifier:notificationUpdateEventID source:ZMUpdateEventSourcePushNotification];
    
    // when
    [self.sut processEvents:@[websocketEvent] liveEvents:YES prefetchResult:nil];
    
    // then
    NSUUID *lastUpdateEventID = [[self.uiMOC persistentStoreMetadataForKey:LastUpdateEventIDStoreKey] UUID];
    XCTAssertEqualObjects(lastUpdateEventID, websocketUpdateEventID);
    
    // when
    [self.sut processEvents:@[downloadedEvent] liveEvents:YES prefetchResult:nil];
    
    // then
    lastUpdateEventID = [[self.uiMOC persistentStoreMetadataForKey:LastUpdateEventIDStoreKey] UUID];
    XCTAssertEqualObjects(lastUpdateEventID, downstreamUpdateEventID);
    
    // when
    [self.sut processEvents:@[pushNotificationEvent] liveEvents:YES prefetchResult:nil];
    
    // then
    lastUpdateEventID = [[self.uiMOC persistentStoreMetadataForKey:LastUpdateEventIDStoreKey] UUID];
    XCTAssertNotEqualObjects(lastUpdateEventID, notificationUpdateEventID);
    XCTAssertEqualObjects(lastUpdateEventID, downstreamUpdateEventID);
}

- (void)testThatItDoesNotStoreTheLastUpdateEventIDWhenReceivingTransientUpdateEvents
{
    // given
    NSUUID *initialLastUpdateEventID = [NSUUID createUUID];
    [self setLastUpdateEventID:initialLastUpdateEventID hasMore:NO];
    NSUUID *expectedLastUpdateEventID = [NSUUID createUUID];
    
    id <ZMTransportData> payload = [self updateEventTransportDataWithID:expectedLastUpdateEventID transient:YES];
    ZMUpdateEvent *event = [ZMUpdateEvent eventsArrayFromPushChannelData:payload].firstObject;
    XCTAssertTrue(event.isTransient);
    // when
    
    [self.sut processEvents:@[event] liveEvents:YES prefetchResult:nil];
    
    // then
    NSUUID *lastUpdateEventID = [[self.uiMOC persistentStoreMetadataForKey:LastUpdateEventIDStoreKey] UUID];
    XCTAssertEqualObjects(lastUpdateEventID, initialLastUpdateEventID);
}

- (void)testThatItDoesNotStoreTheLastUpdateEventIDWhenReceivingTransientUpdateEvents_FromNotificationStream
{
    // given
    NSUUID *initialLastUpdateEventID = [NSUUID createUUID];
    [self setLastUpdateEventID:initialLastUpdateEventID hasMore:NO];
    NSUUID *expectedLastUpdateEventID = [NSUUID createUUID];
    NSUUID *lastTransientUpdateEventID = [NSUUID createUUID];

    
    id <ZMTransportData> payloadExpectedLast = [self updateEventTransportDataWithID:expectedLastUpdateEventID transient:NO];
    id <ZMTransportData> payloadTransientLast = [self updateEventTransportDataWithID:lastTransientUpdateEventID transient:YES];
    NSDictionary *payload = @{@"notifications" : @[payloadExpectedLast, payloadTransientLast],
                              @"has_more" : @(NO)
                              };
    
    ZMTransportResponse* response = [ZMTransportResponse responseWithPayload:payload HTTPStatus:200 transportSessionError:nil];
    
    // when

    [(id)self.sut.listPaginator didReceiveResponse:response forSingleRequest:self.requestSync];

    // then
    NSUUID *lastUpdateEventID = [[self.uiMOC persistentStoreMetadataForKey:LastUpdateEventIDStoreKey] UUID];
    XCTAssertEqualObjects(lastUpdateEventID, expectedLastUpdateEventID);
}

- (void)testThatItDoesNotStoreTheLastUpdateEventIDWhenReceivingTransientUpdateEvents_FromOnlyTransientNotificationStream
{
    // given
    NSUUID *initialLastUpdateEventID = [NSUUID createUUID];
    [self setLastUpdateEventID:initialLastUpdateEventID hasMore:NO];
    NSUUID *firstTransientUpdateEventID = [NSUUID createUUID];
    NSUUID *lastTransientUpdateEventID = [NSUUID createUUID];
    
    id <ZMTransportData> payloadFirstTransient = [self updateEventTransportDataWithID:firstTransientUpdateEventID transient:YES];
    id <ZMTransportData> payloadLastTransient = [self updateEventTransportDataWithID:lastTransientUpdateEventID transient:YES];
    NSDictionary *payload = @{@"notifications" : @[payloadFirstTransient, payloadLastTransient],
                              @"has_more" : @(NO)
                              };
    
    ZMTransportResponse* response = [ZMTransportResponse responseWithPayload:payload HTTPStatus:200 transportSessionError:nil];
    
    // when
    
    [(id)self.sut.listPaginator didReceiveResponse:response forSingleRequest:self.requestSync];
    
    // then
    NSUUID *lastUpdateEventID = [[self.uiMOC persistentStoreMetadataForKey:LastUpdateEventIDStoreKey] UUID];
    XCTAssertEqualObjects(lastUpdateEventID, initialLastUpdateEventID);
}

- (ZMUpdateEvent *)updateEventWithIdentifier:(NSUUID *)identifier source:(ZMUpdateEventSource)source
{
    id <ZMTransportData> payload = [self updateEventTransportDataWithID:identifier];
    return [ZMUpdateEvent eventsArrayFromTransportData:payload source:source].firstObject;
}

- (id <ZMTransportData>)updateEventTransportDataWithID:(NSUUID *)identifier
{
    return [self updateEventTransportDataWithID:identifier transient:NO];
}

- (id <ZMTransportData>)updateEventTransportDataWithID:(NSUUID *)identifier transient:(BOOL)transient
{
    return @{
             @"id" : identifier.transportString,
             @"transient": @(transient),
             @"payload" : @[
                     @{
                         @"time" : @"2014-06-20T14:04:37.870Z",
                         @"type" : @"conversation.member-update"
                         }
                     ]
             };
}

@end



@implementation ZMMissingUpdateEventsTranscoderTests (Pagination)

- (void)testThatItUsesLastStoredEventIDWhenFetchingNextNotifications
{
    // given
    NSUUID *lastUpdateEventID1 = [NSUUID createUUID];
    NSUUID *lastUpdateEventID2 = [NSUUID createUUID];

    [self setLastUpdateEventID:lastUpdateEventID1 hasMore:NO];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // when
    [self.sut startDownloadingMissingNotifications];
    ZMTransportRequest *request1 = [self.sut.listPaginator nextRequest];
    [request1 completeWithResponse:[self responseForSettingLastUpdateEventID:lastUpdateEventID2 hasMore:NO]];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertNotNil(request1);
    NSURLComponents *components1 = [NSURLComponents componentsWithString:request1.path];
    XCTAssertTrue([components1.queryItems containsObject:[NSURLQueryItem queryItemWithName:@"since" value:lastUpdateEventID1.transportString]]);
    
    // and when
    // when has_more == NO it should not create further requests
    ZMTransportRequest *request2 = [self.sut.listPaginator nextRequest];
    // then
    XCTAssertNil(request2);
    
    // and when
    // fetching the next notifications, it should use the new updateEventID
    [self.sut startDownloadingMissingNotifications];
    ZMTransportRequest *request3 = [self.sut.listPaginator nextRequest];
    
    // then
    XCTAssertNotNil(request3);
    NSURLComponents *components3 = [NSURLComponents componentsWithString:request3.path];
    XCTAssertTrue([components3.queryItems containsObject:[NSURLQueryItem queryItemWithName:@"since" value:lastUpdateEventID2.transportString]]);
}

- (void)testThatItDiscardsThePreviouslyReceivedEventIDsWhenReachingTheEndOfPagination
{
    // given
    NSUUID *lastUpdateEventID1 = [NSUUID createUUID];
    NSUUID *lastUpdateEventID2 = [NSUUID createUUID];
    
    [self setLastUpdateEventID:lastUpdateEventID1 hasMore:NO];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // when
    [self.sut startDownloadingMissingNotifications];
    ZMTransportRequest *request1 = [self.sut.listPaginator nextRequest];
    [request1 completeWithResponse:[self responseForSettingLastUpdateEventID:lastUpdateEventID2 hasMore:NO]];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    OCMVerify([self.mockEventIDsCollection discardListOfAlreadyReceivedPushEventIDs]);
}

- (void)testThatItDoesNotDiscardsThePreviouslyReceivedEventIDsWhenNotReachingTheEndOfPagination
{
    // given
    NSUUID *lastUpdateEventID1 = [NSUUID createUUID];
    NSUUID *lastUpdateEventID2 = [NSUUID createUUID];
    
    [self setLastUpdateEventID:lastUpdateEventID1 hasMore:NO];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // expect
    OCMReject([self.mockEventIDsCollection discardListOfAlreadyReceivedPushEventIDs]);

    // when
    [self.sut startDownloadingMissingNotifications];
    ZMTransportRequest *request1 = [self.sut.listPaginator nextRequest];
    [request1 completeWithResponse:[self responseForSettingLastUpdateEventID:lastUpdateEventID2 hasMore:YES]];
    WaitForAllGroupsToBeEmpty(0.5);
}

@end



@implementation ZMMissingUpdateEventsTranscoderTests (FallbackCancellation)


- (void)expectMockPingBackStatus:(BackgroundNotificationFetchStatus)status hasNotifications:(BOOL)hasNotifications nextEvents:(EventsWithIdentifier *)nextEvents inBackground:(BOOL)backgrounded
{
    self.application.applicationState = backgrounded ? UIApplicationStateBackground : UIApplicationStateActive;
    [[[self.mockPingbackStatus stub] andReturnValue:@(hasNotifications)] hasNotificationIDs];
    [(BackgroundAPNSPingBackStatus *)[[self.mockPingbackStatus expect] andReturnValue:@(status)] status];

    if (nil != nextEvents) {
        NOT_USED([[[self.mockPingbackStatus expect] andReturn:nextEvents] nextNotificationEventsWithID]);
    }
}

- (void)testThatItDoesNotReturnARequestItselfFromAPushWhenThePingBackStatusIsNotInProgress
{
    // given
    [self expectMockPingBackStatus:BackgroundNotificationFetchStatusDone hasNotifications:YES nextEvents:nil inBackground:YES];

    // then
    XCTAssertNil([self.sut nextRequest]);
}

- (void)testThatItDoesReturnARequestItselfFromAPushWhenThePaginatorIsNotInProgressButThereAreNewIds
{
    // given
    ZMUpdateEvent *updateEvent = [[ZMUpdateEvent alloc] init];
    EventsWithIdentifier *events = [[EventsWithIdentifier alloc] initWithEvents:@[updateEvent] identifier:NSUUID.createUUID isNotice:YES];
    [self expectMockPingBackStatus:BackgroundNotificationFetchStatusInProgress hasNotifications:YES nextEvents:events inBackground:YES];

    // then
    XCTAssertNotNil([self.sut nextRequest]);
}

- (void)testThatItAddsTheCancelationQueryToItsPathWhenItHasANotificationIdToCancel
{
    // given
    ZMUpdateEvent *updateEvent = [[ZMUpdateEvent alloc] init];
    EventsWithIdentifier *events = [[EventsWithIdentifier alloc] initWithEvents:@[updateEvent] identifier:NSUUID.createUUID isNotice:YES];
    [self expectMockPingBackStatus:BackgroundNotificationFetchStatusInProgress hasNotifications:YES nextEvents:events inBackground:YES];

    // when
    ZMTransportRequest *request = [self.sut nextRequest];

    // then
    XCTAssertNotNil(request);
    NSURLQueryItem *cancelItem = [NSURLComponents componentsWithString:request.path].queryItems.lastObject;
    XCTAssertNotNil(cancelItem);

    XCTAssertEqualObjects(cancelItem.name, @"cancel_fallback");
    XCTAssertEqualObjects(cancelItem.value, events.identifier.transportString);
}

- (void)testThatItForcesTheRequestToTheVoIPSession
{
    // given
    ZMUpdateEvent *updateEvent = [[ZMUpdateEvent alloc] init];
    EventsWithIdentifier *events = [[EventsWithIdentifier alloc] initWithEvents:@[updateEvent] identifier:NSUUID.createUUID isNotice:YES];
    [self expectMockPingBackStatus:BackgroundNotificationFetchStatusInProgress hasNotifications:YES nextEvents:events inBackground:YES];

    // when
    ZMTransportRequest *request = [self.sut nextRequest];

    // then
    XCTAssertNotNil(request);
    XCTAssertTrue(request.shouldUseVoipSession);
}

- (void)testThatItCallsThePingBackStatusWithFetchedNotificationsIfItHasANotificationIdToCancel
{
    // given
    ZMUpdateEvent *updateEvent = [[ZMUpdateEvent alloc] init];
    EventsWithIdentifier *events = [[EventsWithIdentifier alloc] initWithEvents:@[updateEvent] identifier:NSUUID.createUUID isNotice:YES];
    [self expectMockPingBackStatus:BackgroundNotificationFetchStatusInProgress hasNotifications:YES nextEvents:events inBackground:YES];

    // when
    ZMTransportResponse *response = [self responseForSettingLastUpdateEventID:NSUUID.createUUID hasMore:NO];
    ZMTransportRequest *request = [self.sut nextRequest];
    id <ZMTransportData> payload = response.payload[@"notifications"][0];
    NSArray <ZMUpdateEvent *> *expectedEvents = [ZMUpdateEvent eventsArrayFromPushChannelData:payload];

    // expect
    [(BackgroundAPNSPingBackStatus *)[self.mockPingbackStatus expect] didReceiveEncryptedEvents:expectedEvents originalEvents:events hasMore:NO];

    XCTAssertNotNil(request);
    [request completeWithResponse:response];
    WaitForAllGroupsToBeEmpty(0.5);
    [self expectMockPingBackStatus:BackgroundNotificationFetchStatusDone hasNotifications:NO nextEvents:nil inBackground:YES];

    XCTAssertNil([self.sut nextRequest]);
}

- (void)testThatItDoesNotCallThePingBackStatusWhenNoNotificationEventsToCancel
{
    // given
    ZMUpdateEvent *updateEvent = [[ZMUpdateEvent alloc] init];
    EventsWithIdentifier *events = [[EventsWithIdentifier alloc] initWithEvents:@[updateEvent] identifier:NSUUID.createUUID isNotice:YES];
    [self expectMockPingBackStatus:BackgroundNotificationFetchStatusInProgress hasNotifications:YES nextEvents:events inBackground:YES];
    
    // when
    ZMTransportResponse *response = [self responseForSettingLastUpdateEventID:NSUUID.createUUID hasMore:NO];
    ZMTransportRequest *request = [self.sut nextRequest];
    
    [(id)self.sut.listPaginator didReceiveResponse:[ZMTransportResponse responseWithPayload:@{} HTTPStatus:400 transportSessionError:nil] forSingleRequest:self.requestSync];
    
    id <ZMTransportData> payload = response.payload[@"notifications"][0];
    NSArray <ZMUpdateEvent *> *expectedEvents = [ZMUpdateEvent eventsArrayFromPushChannelData:payload];
    
    // expect
    id nilEvents = nil;
    [(BackgroundAPNSPingBackStatus *)[self.mockPingbackStatus reject] didReceiveEncryptedEvents:expectedEvents originalEvents:nilEvents hasMore:NO];
    
    XCTAssertNotNil(request);

    [(id)self.sut.listPaginator didReceiveResponse:response forSingleRequest:self.requestSync];
    WaitForAllGroupsToBeEmpty(0.5);
    
    XCTAssertNil([self.sut nextRequest]);
}

- (void)testThatItCallsThePingBackStatusWithFetchedNotificationsIfItHasANotificationIdToCancel_MultiplePages
{
    // given
    ZMUpdateEvent *updateEvent = [[ZMUpdateEvent alloc] init];
    EventsWithIdentifier *events = [[EventsWithIdentifier alloc] initWithEvents:@[updateEvent] identifier:NSUUID.createUUID isNotice:YES];

    // first batch
    {
        [self expectMockPingBackStatus:BackgroundNotificationFetchStatusInProgress hasNotifications:YES nextEvents:events inBackground:YES];

        ZMTransportResponse *response = [self responseForSettingLastUpdateEventID:NSUUID.createUUID hasMore:YES];
        ZMTransportRequest *request = [self.sut nextRequest];
        id <ZMTransportData> payload = response.payload[@"notifications"][0];
        NSArray <ZMUpdateEvent *> *expectedEvents = [ZMUpdateEvent eventsArrayFromPushChannelData:payload];

        // expect
        [(BackgroundAPNSPingBackStatus *)[self.mockPingbackStatus expect] didReceiveEncryptedEvents:expectedEvents originalEvents:events hasMore:YES];

        XCTAssertNotNil(request);
        [request completeWithResponse:response];
        WaitForAllGroupsToBeEmpty(0.5);
    }

    // second batch
    {
        [self expectMockPingBackStatus:BackgroundNotificationFetchStatusInProgress hasNotifications:YES nextEvents:nil inBackground:YES];
        ZMTransportResponse *response = [self responseForSettingLastUpdateEventID:NSUUID.createUUID hasMore:NO];
        ZMTransportRequest *request = [self.sut nextRequest];
        id <ZMTransportData> payload = response.payload[@"notifications"][0];
        NSArray <ZMUpdateEvent *> *expectedEvents = [ZMUpdateEvent eventsArrayFromPushChannelData:payload];

        // expect
        [(BackgroundAPNSPingBackStatus *)[self.mockPingbackStatus expect] didReceiveEncryptedEvents:expectedEvents originalEvents:events hasMore:NO];

        XCTAssertNotNil(request);
        [request completeWithResponse:response];
        WaitForAllGroupsToBeEmpty(0.5);
    }

   XCTAssertNil([self.sut nextRequest]);
}

- (void)testThatItAsksForTheNextNotificationIfThereIsOneAndThePreviousFetchFinished
{

    // given
    NSUUID *firstIdToCancel = NSUUID.createUUID;
    EventsWithIdentifier *firstEvents = [[EventsWithIdentifier alloc] initWithEvents:@[[[ZMUpdateEvent alloc] init]]
                                                                          identifier:firstIdToCancel
                                                                            isNotice:YES];

    NSUUID *lastNotificationIdAfterFirstPage = NSUUID.createUUID;
    self.uiMOC.zm_lastNotificationID = NSUUID.createUUID;

    // first batch
    {
        [self expectMockPingBackStatus:BackgroundNotificationFetchStatusInProgress hasNotifications:YES nextEvents:firstEvents inBackground:YES];

        ZMTransportResponse *response = [self responseForSettingLastUpdateEventID:lastNotificationIdAfterFirstPage hasMore:YES];
        ZMTransportRequest *request = [self.sut nextRequest];
        id <ZMTransportData> payload = response.payload[@"notifications"][0];
        NSArray <ZMUpdateEvent *> *expectedEvents = [ZMUpdateEvent eventsArrayFromPushChannelData:payload];

        // expect
        [(BackgroundAPNSPingBackStatus *)[self.mockPingbackStatus expect] didReceiveEncryptedEvents:expectedEvents originalEvents:firstEvents hasMore:YES];

        XCTAssertNotNil(request);
        XCTAssertEqualObjects(request.path, [self cancelationPathWithLastNotificationID:self.uiMOC.zm_lastNotificationID cancelingID:firstIdToCancel]);
        [request completeWithResponse:response];
        WaitForAllGroupsToBeEmpty(0.5);
    }

    // second batch
    NSUUID *lastEventID = NSUUID.createUUID;

    {
        [self expectMockPingBackStatus:BackgroundNotificationFetchStatusInProgress hasNotifications:YES nextEvents:nil inBackground:YES];
        ZMTransportResponse *response = [self responseForSettingLastUpdateEventID:lastEventID hasMore:NO];
        ZMTransportRequest *request = [self.sut nextRequest];
        id <ZMTransportData> payload = response.payload[@"notifications"][0];
        NSArray <ZMUpdateEvent *> *expectedEvents = [ZMUpdateEvent eventsArrayFromPushChannelData:payload];

        // expect
        [(BackgroundAPNSPingBackStatus *)[self.mockPingbackStatus expect] didReceiveEncryptedEvents:expectedEvents originalEvents:firstEvents hasMore:NO];

        XCTAssertNotNil(request);
        XCTAssertEqualObjects(request.path, [self cancelationPathWithLastNotificationID:lastNotificationIdAfterFirstPage cancelingID:firstIdToCancel]);
        [request completeWithResponse:response];
        [request completeWithResponse:response];
        WaitForAllGroupsToBeEmpty(0.5);
    }

    // After fetching 2 pages for the first notification, we receive another notification that we want to cancel

    {
        // when
        ZMUpdateEvent *updateEvent = [[ZMUpdateEvent alloc] init];
        NSUUID *idToCancel = NSUUID.createUUID;
        EventsWithIdentifier *events = [[EventsWithIdentifier alloc] initWithEvents:@[updateEvent] identifier:idToCancel isNotice:YES];
        [self expectMockPingBackStatus:BackgroundNotificationFetchStatusInProgress hasNotifications:YES nextEvents:events inBackground:YES];

        ZMTransportResponse *response = [self responseForSettingLastUpdateEventID:NSUUID.createUUID hasMore:NO];
        ZMTransportRequest *request = [self.sut nextRequest];
        id <ZMTransportData> payload = response.payload[@"notifications"][0];
        NSArray <ZMUpdateEvent *> *expectedEvents = [ZMUpdateEvent eventsArrayFromPushChannelData:payload];

        // expect
        [(BackgroundAPNSPingBackStatus *)[self.mockPingbackStatus expect] didReceiveEncryptedEvents:expectedEvents originalEvents:events hasMore:NO];

        XCTAssertNotNil(request);
        XCTAssertEqualObjects(request.path, [self cancelationPathWithLastNotificationID:lastEventID cancelingID:idToCancel]);
        [request completeWithResponse:response];
        WaitForAllGroupsToBeEmpty(0.5);
    }
    
    XCTAssertNil([self.sut nextRequest]);
}

- (void)testThatItUpdatesTheLastNotificationIdWhenStartedThroughAPush
{
    // given
    ZMUpdateEvent *updateEvent = [[ZMUpdateEvent alloc] init];
    EventsWithIdentifier *events = [[EventsWithIdentifier alloc] initWithEvents:@[updateEvent] identifier:NSUUID.createUUID isNotice:YES];
    [self expectMockPingBackStatus:BackgroundNotificationFetchStatusInProgress hasNotifications:YES nextEvents:events inBackground:YES];

    // when
    NSUUID *expectedLastUpdateEventID = NSUUID.createUUID;
    ZMTransportResponse *response = [self responseForSettingLastUpdateEventID:expectedLastUpdateEventID hasMore:NO];
    ZMTransportRequest *request = [self.sut nextRequest];
    [request completeWithResponse:response];
    WaitForAllGroupsToBeEmpty(0.5);

    // then
    NSUUID *lastUpdateEventID = [[self.uiMOC persistentStoreMetadataForKey:LastUpdateEventIDStoreKey] UUID];
    XCTAssertEqualObjects(lastUpdateEventID, expectedLastUpdateEventID);
    XCTAssertEqualObjects(self.sut.lastUpdateEventID, expectedLastUpdateEventID);
}

- (void)testThatItReportsWhenItIsFetchingFromAPushNotification
{
    // given
    [(BackgroundAPNSPingBackStatus *)[[self.mockPingbackStatus expect] andReturnValue:@(BackgroundNotificationFetchStatusInProgress)] status];

    // then
    XCTAssertTrue(self.sut.isFetchingStreamForAPNS);
}

- (void)testThatItDoesNotReportThatItIsFetchingFromAPushNotificationWhenTheApplicationIsActive
{
    // given
    self.application.applicationState = UIApplicationStateActive;

    // then
    XCTAssertFalse(self.sut.isFetchingStreamForAPNS);
}

- (void)testThatItDoesNotReportThatItIsFetchingFromAPushNotificationWhenNoPingBackIsInProgress
{
    // given
    [(BackgroundAPNSPingBackStatus *)[[self.mockPingbackStatus expect] andReturnValue:@(BackgroundNotificationFetchStatusDone)] status];
    self.application.applicationState = UIApplicationStateBackground;

    // then
    XCTAssertFalse(self.sut.isFetchingStreamForAPNS);
}

- (void)testThatItNotifiesThePingBackStatusInCaseOfAFailure
{
    // given
    ZMUpdateEvent *updateEvent = [[ZMUpdateEvent alloc] init];
    EventsWithIdentifier *events = [[EventsWithIdentifier alloc] initWithEvents:@[updateEvent] identifier:NSUUID.createUUID isNotice:YES];
    [self expectMockPingBackStatus:BackgroundNotificationFetchStatusInProgress hasNotifications:YES nextEvents:events inBackground:YES];

    // when
    ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:nil HTTPStatus:400 transportSessionError:nil];
    ZMTransportRequest *request = [self.sut nextRequest];
    [(BackgroundAPNSPingBackStatus *)[self.mockPingbackStatus expect] didFailDownloadingOriginalEvents:events];

    [request completeWithResponse:response];
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatIUsesTheLastNotificationIdToRequestTheNotificationStreamFromAPush
{
    // given
    NSUUID *lastID = NSUUID.createUUID;
    // sync strategy is mocked to return the uiMOC when asked for the syncMOC
    self.uiMOC.zm_lastNotificationID = lastID;

    ZMUpdateEvent *updateEvent = [[ZMUpdateEvent alloc] init];
    EventsWithIdentifier *events = [[EventsWithIdentifier alloc] initWithEvents:@[updateEvent] identifier:NSUUID.createUUID isNotice:YES];
    [self expectMockPingBackStatus:BackgroundNotificationFetchStatusInProgress hasNotifications:YES nextEvents:events inBackground:YES];

    // when
    ZMTransportRequest *request = [self.sut nextRequest];

    // then
    XCTAssertNotNil(request);
    BOOL hasSinceQuery = NO;
    NSArray <NSURLQueryItem *> *items = [NSURLComponents componentsWithString:request.path].queryItems;
    for (NSURLQueryItem *item in items) {
        if ([item.name isEqualToString:@"since"]) {
            hasSinceQuery = YES;
            XCTAssertEqualObjects(item.value, lastID.transportString);
        }
    }

    XCTAssertTrue(hasSinceQuery);
}

- (void)testThatItDoesForwardTheResponseInCaseOfA404AndDoesNotReportAFailure_MissingMessages
{
    // given
    ZMUpdateEvent *updateEvent = [[ZMUpdateEvent alloc] init];
    EventsWithIdentifier *events = [[EventsWithIdentifier alloc] initWithEvents:@[updateEvent] identifier:NSUUID.createUUID isNotice:YES];
    [self expectMockPingBackStatus:BackgroundNotificationFetchStatusInProgress hasNotifications:YES nextEvents:events inBackground:YES];
    ZMTransportRequest *request = [self.sut nextRequest];
    XCTAssertNotNil(request);

    self.application.applicationState = UIApplicationStateBackground;

    NSDictionary *payload =  @{
                               @"id" : NSUUID.createUUID.transportString,
                               @"payload" : @[
                                       @{
                                           @"type" : @"conversation.message-add",
                                           @"time": NSDate.date.transportString
                                           }
                                       ]
                               };

    NSArray <ZMUpdateEvent *> *expectedEvents = [ZMUpdateEvent eventsArrayFromPushChannelData:payload];
    [(BackgroundAPNSPingBackStatus *)[self.mockPingbackStatus expect] didReceiveEncryptedEvents:expectedEvents originalEvents:OCMOCK_ANY hasMore:NO];

    // when
    ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:@{@"notifications": @[payload]} HTTPStatus:404 transportSessionError:nil];
    [(id)self.sut.listPaginator didReceiveResponse:response forSingleRequest:self.requestSync];

    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatItDoesNotSetTheNotificationIdToCancelWhenTheListPaginatorIsStillInProgress
{

    // given we simulate fetching missing events
    self.mockSyncStatus.mockPhase = SyncPhaseFetchingMissedEvents;
    NSUUID *lastEventID = NSUUID.createUUID;

    // then it should generate a request to fetch the notification stream
    ZMTransportRequest *fetchRequest = self.sut.nextRequest;
    XCTAssertEqualObjects(fetchRequest.path, @"/notifications?size=500");

    // when
    ZMUpdateEvent *updateEvent = [[ZMUpdateEvent alloc] init];
    EventsWithIdentifier *events = [[EventsWithIdentifier alloc] initWithEvents:@[updateEvent] identifier:NSUUID.createUUID isNotice:YES];
    [self expectMockPingBackStatus:BackgroundNotificationFetchStatusInProgress hasNotifications:YES nextEvents:events inBackground:YES];

    // then it should not create a request as the notificaiton stream fetch is still in progress
    XCTAssertNil(self.sut.nextRequest);

    // when
    ZMTransportResponse *fetchResponse = [self responseForSettingLastUpdateEventID:lastEventID hasMore:NO];
    [fetchRequest completeWithResponse:fetchResponse];
    WaitForAllGroupsToBeEmpty(0.5);

    // then
    [self expectMockPingBackStatus:BackgroundNotificationFetchStatusInProgress hasNotifications:YES nextEvents:events inBackground:YES];
    ZMTransportRequest *pingBackRequest = self.sut.nextRequest;
    XCTAssertNotNil(pingBackRequest);
    XCTAssertEqualObjects(pingBackRequest.path, [self cancelationPathWithLastNotificationID:lastEventID cancelingID:events.identifier]);
}

- (NSString *)cancelationPathWithLastNotificationID:(NSUUID *)lastNotificationID cancelingID:(NSUUID *)idToCancel
{
    return [NSString stringWithFormat:@"/notifications?size=500&since=%@&cancel_fallback=%@", lastNotificationID.transportString, idToCancel.transportString];
}

@end


@implementation ZMMissingUpdateEventsTranscoderTests (ServerTimeDelta)

- (void)testThatServerTimeDeltaIsUpdatedWhenTimeFieldIsPresent
{
    // given
    NSTimeInterval delta = 500;
    NSDate *localTime = [NSDate date];
    NSDate *serverTime = [localTime dateByAddingTimeInterval:delta];
    
    NSDictionary *payload = @{@"time": [serverTime transportString],
                              @"notifications" : @[]};
    
    // when
    [self performPretendingUiMocIsSyncMoc:^{
        [(id)self.sut.listPaginator didReceiveResponse:[ZMTransportResponse responseWithPayload:payload HTTPStatus:200 transportSessionError:nil] forSingleRequest:self.requestSync];
    }];
    
    // then
    [self performPretendingUiMocIsSyncMoc:^{
        XCTAssertEqualWithAccuracy(self.sut.managedObjectContext.serverTimeDelta, delta, 1);
    }];
}

@end
