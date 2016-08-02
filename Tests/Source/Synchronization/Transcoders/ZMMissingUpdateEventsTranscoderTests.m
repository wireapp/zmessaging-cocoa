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

#import <Foundation/Foundation.h>

#import "MessagingTest.h"
#import "ZMMissingUpdateEventsTranscoder+Internal.h"
#import "ZMSingleRequestSync.h"
#import "ZMSyncStrategy.h"
#import "ZMSimpleListRequestPaginator.h"
#import <zmessaging/zmessaging-Swift.h>


static NSString * const LastUpdateEventIDStoreKey = @"LastUpdateEventID";

@interface ZMMissingUpdateEventsTranscoderTests : MessagingTest

@property (nonatomic, readonly) ZMMissingUpdateEventsTranscoder *sut;
@property (nonatomic, readonly) id lastUpdateEventIDTranscoder;
@property (nonatomic, readonly) ZMSyncStrategy *syncStrategy;
@property (nonatomic, readonly) id mockPingBackStatus;

@end

@implementation ZMMissingUpdateEventsTranscoderTests

- (void)setUp {
    [super setUp];
    _mockPingBackStatus = [OCMockObject niceMockForClass:[BackgroundAPNSPingBackStatus class]];
    _syncStrategy = [OCMockObject niceMockForClass:ZMSyncStrategy.class];
    [[[(id) self.syncStrategy stub] andReturn:self.syncMOC] syncMOC];
    [self verifyMockLater:self.syncStrategy];
    
    _sut = [[ZMMissingUpdateEventsTranscoder alloc] initWithSyncStrategy:self.syncStrategy apnsPingBackStatus:self.mockPingBackStatus];
}

- (void)tearDown {
    [self.sut tearDown];
    _sut = nil;
    _syncStrategy = nil;
    
    [super tearDown];
}


- (void)testThatItCreatesAListPaginatorSync
{
    // when
    ZMMissingUpdateEventsTranscoder *sut = [[ZMMissingUpdateEventsTranscoder alloc] initWithSyncStrategy:self.syncStrategy apnsPingBackStatus:self.mockPingBackStatus];
    
    // then
    XCTAssertNotNil(sut.listPaginator);
    [sut tearDown];
}

- (void)testThatItOnlyProcessesMissingUpdateEvents;
{
    // when
    NSArray *generators = self.sut.requestGenerators;
    
    // then
    XCTAssertEqual(generators.count, 1u);
    XCTAssertTrue([generators.lastObject isKindOfClass:ZMSimpleListRequestPaginator.class]);
}

- (void)testThatItDoesNotReturnAContextChangeTracker;
{
    // when
    NSArray *trackers = self.sut.contextChangeTrackers;
    
    // then
    XCTAssertEqual(trackers.count, 0u);
}

@end


@implementation ZMMissingUpdateEventsTranscoderTests (MissingNotifications)

- (NSUUID *)olderNotificationID {
    return [NSUUID uuidWithTransportString:@"a6526b00-000a-11e5-a837-0800200c9a66"];
}

- (NSUUID *)newNotificationID {
    return [NSUUID uuidWithTransportString:@"54ad4672-be09-11e5-9912-ba0be0483c18"];
}

- (void)testThatItReturnSlowSyncNotDoneIfItHasNoLastUpdateEventID
{
    XCTAssertFalse(self.sut.isSlowSyncDone);
}

- (void)testThatItReturnSlowSyncDoneIfItHasALastUpdateEventID
{
    // given
    [self setLastUpdateEventID:[NSUUID createUUID] hasMore:NO];
    
    // then
    XCTAssertTrue(self.sut.isSlowSyncDone);
}

- (void)testThatItDoesNotSetLastUpdateEventIDAndSlowSyncDoneWhenThereIsMoreToFetch
{
    // given
    [self setLastUpdateEventID:[NSUUID createUUID] hasMore:YES];
    
    // then
    XCTAssertFalse(self.sut.isSlowSyncDone);
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
    id missingUpdateEventsTranscoder = [OCMockObject partialMockForObject:self.sut.listPaginator];
    ZMTransportRequest *expectedRequest = [ZMTransportRequest requestGetFromPath:@"555555"];
    
    // expect
    [[[missingUpdateEventsTranscoder expect] andReturn:expectedRequest] nextRequest];
    
    // when
    ZMTransportRequest *request = [self.sut.requestGenerators nextRequest];
    
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
    
    NSUUID *callEventID = [NSUUID createUUID];
    NSDictionary *callStatePayload = @{
                                       @"id" : callEventID.transportString,
                                       @"payload" : @[
                                               @{
                                                   @"conversation" : NSUUID.createUUID.transportString,
                                                   @"type" : @"call.state",
                                                   },
                                               ]
                                       };

    NSDictionary *payload = @{@"notifications" : @[payload1, payload2, callStatePayload]};
    
    NSMutableArray *expectedEvents = [NSMutableArray array];
    [expectedEvents addObjectsFromArray:[ZMUpdateEvent eventsArrayFromPushChannelData:payload1]];
    [expectedEvents addObjectsFromArray:[ZMUpdateEvent eventsArrayFromPushChannelData:payload2]];

    NSArray *callStateEvents = [ZMUpdateEvent eventsArrayFromPushChannelData:callStatePayload];

    // expect
    [[(id)self.syncStrategy expect] processUpdateEvents:expectedEvents ignoreBuffer:YES];
    [[(id)self.syncStrategy expect] processUpdateEvents:callStateEvents ignoreBuffer:NO];
    
    // when
    [(id)self.sut.listPaginator didReceiveResponse:[ZMTransportResponse responseWithPayload:payload HTTPstatus:200 transportSessionError:nil] forSingleRequest:nil];
    
    //then
    XCTAssertEqualObjects(self.sut.lastUpdateEventID, callEventID);
}

- (void)testThatItPassesTheDownloadedEventsExceptCallStateEventsToTheSyncStrategyOn404
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
    
    NSUUID *callEventID = [NSUUID createUUID];
    NSDictionary *callStatePayload = @{
                                       @"id" : callEventID.transportString,
                                       @"payload" : @[
                                               @{
                                                   @"conversation" : NSUUID.createUUID.transportString,
                                                   @"type" : @"call.state",
                                                   @"time" : [NSDate date].transportString
                                                   },
                                               ]
                                       };
    
    NSDictionary *payload = @{@"notifications" : @[payload1, payload2, callStatePayload]};
    
    NSMutableArray *expectedEvents = [NSMutableArray array];
    [expectedEvents addObjectsFromArray:[ZMUpdateEvent eventsArrayFromPushChannelData:payload1]];
    [expectedEvents addObjectsFromArray:[ZMUpdateEvent eventsArrayFromPushChannelData:payload2]];
    
    NSArray *callStateEvents = [ZMUpdateEvent eventsArrayFromPushChannelData:callStatePayload];
    
    // expect
    [[(id)self.syncStrategy expect] processUpdateEvents:expectedEvents ignoreBuffer:YES];
    
    //in second pass we process call state events with buffer
    [[(id)self.syncStrategy expect] processUpdateEvents:callStateEvents ignoreBuffer:NO];

    // when
    [(id)self.sut.listPaginator didReceiveResponse:[ZMTransportResponse responseWithPayload:payload HTTPstatus:404 transportSessionError:nil] forSingleRequest:nil];

    // then
    XCTAssertEqualObjects(self.sut.lastUpdateEventID, callEventID);
}

- (void)testThatItOnlyPassesTheLastCallStateEventToTheSyncStrategy
{
    // when
    NSUUID *callEventID1 = NSUUID.createUUID;
    NSUUID *callEventID2 = NSUUID.createUUID;
    NSUUID *callEventID3 = NSUUID.createUUID;
    NSUUID *convUUID1 = NSUUID.createUUID;
    NSUUID *convUUID2 = NSUUID.createUUID;

    NSDictionary *payload1 = @{
                                       @"id" : callEventID1.transportString,
                                       @"payload" : @[
                                               @{
                                                   @"conversation" : convUUID1.transportString,
                                                   @"type" : @"call.state",
                                                   },
                                               ]
                                       };
    NSDictionary *payload2 = @{
                                       @"id" : callEventID2.transportString,
                                       @"payload" : @[
                                               @{
                                                   @"conversation" : convUUID1.transportString,
                                                   @"type" : @"call.state",
                                                   },
                                               ]
                                       };
    NSDictionary *payload3 = @{
                                       @"id" : callEventID3.transportString,
                                       @"payload" : @[
                                               @{
                                                   @"conversation" : convUUID2.transportString,
                                                   @"type" : @"call.state",
                                                   },
                                               ]
                                       };
    
    NSDictionary *payload = @{@"notifications" : @[payload1, payload2, payload3]};
    
    NSMutableArray *expectedEvents = [NSMutableArray array];
    [expectedEvents addObjectsFromArray:[ZMUpdateEvent eventsArrayFromPushChannelData:payload2]];
    [expectedEvents addObjectsFromArray:[ZMUpdateEvent eventsArrayFromPushChannelData:payload3]];
    
    NSArray *rejectedEvents = [ZMUpdateEvent eventsArrayFromPushChannelData:payload1];

    //in second pass we process call state events with buffer
    [[(id)self.syncStrategy expect] processUpdateEvents:expectedEvents ignoreBuffer:NO];
    [[(id)self.syncStrategy reject] processUpdateEvents:rejectedEvents ignoreBuffer:NO];

    // when
    [(id)self.sut.listPaginator didReceiveResponse:[ZMTransportResponse responseWithPayload:payload HTTPstatus:404 transportSessionError:nil] forSingleRequest:nil];

    [(id)self.syncStrategy verify];
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
    [(id)self.sut.listPaginator didReceiveResponse:response forSingleRequest:nil];
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
    
    NSMutableArray *expectedEvents = [NSMutableArray array];
    [expectedEvents addObjectsFromArray:[ZMUpdateEvent eventsArrayFromPushChannelData:innerPayload]];
    
    return [ZMTransportResponse responseWithPayload:payload HTTPstatus:200 transportSessionError:nil];
}


- (void)testThatItHasALastUpdateEventIDAfterFetchingNotifications
{
    
    // given
    [self setLastUpdateEventID:[NSUUID createUUID] hasMore:NO];
    
    // then
    XCTAssertTrue(self.sut.hasLastUpdateEventID);
}


- (void)testThatItDoesNotHasALastUpdateEventIDAfterFailingToFetchNotifications
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
    [(id)self.sut.listPaginator didReceiveResponse:[ZMTransportResponse responseWithPayload:payload HTTPstatus:400 transportSessionError:nil] forSingleRequest:nil];

    
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
    ZMMissingUpdateEventsTranscoder *sut = [[ZMMissingUpdateEventsTranscoder alloc] initWithSyncStrategy:self.syncStrategy apnsPingBackStatus:self.mockPingBackStatus ];
    WaitForAllGroupsToBeEmpty(0.5);
    [sut.listPaginator resetFetching];
    ZMTransportRequest *request = [sut.listPaginator nextRequest];
    
    // then
    NSURLComponents *components = [NSURLComponents componentsWithString:request.path];
    XCTAssertTrue([components.queryItems containsObject:[NSURLQueryItem queryItemWithName:@"since" value:lastUpdateEventID.transportString]], @"missing valid since parameter");
    
    [sut tearDown];
}

- (void)testThatTheClientIDFromTheUserClientIsIncludedInRequest
{
    // Given
    UserClient *userClient = [self createSelfClient];
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
    XCTAssertEqualObjects(self.syncMOC.zm_lastNotificationID, expectedLastUpdateEventID);
}

- (void)testThatItStoresTheLastUpdateEventIDWhenItIsAMoreRecentType1
{
    // given
    [self setLastUpdateEventID:[self olderNotificationID] hasMore:NO];
    
    // when
    [self setLastUpdateEventID:[self newNotificationID] hasMore:NO];
    
    // then
    XCTAssertEqualObjects(self.syncMOC.zm_lastNotificationID, [self newNotificationID]);
}

- (void)testThatItDoesNotStoreTheLastUpdateEventIDWhenItIsNotAMoreRecentType1
{
    // given
    [self setLastUpdateEventID:[self newNotificationID] hasMore:NO];
    
    // when
    [self setLastUpdateEventID:[self olderNotificationID] hasMore:NO];
    
    // then
    XCTAssertEqualObjects(self.syncMOC.zm_lastNotificationID, [self newNotificationID]);
}

- (void)testThatItStoresTheLastUpdateEventIDWhenItIsNotAType1
{
    // given
    NSUUID *secondUUID = [NSUUID createUUID];
    [self setLastUpdateEventID:[self newNotificationID] hasMore:NO];
    
    // when
    [self setLastUpdateEventID:secondUUID hasMore:NO];
    
    // then
    XCTAssertEqualObjects(self.syncMOC.zm_lastNotificationID, secondUUID);
}

- (void)testThatItStoresTheLastUpdateEventIDWhenThePreviousOneIsNotAType1
{
    // given
    NSUUID *firstUUID = [NSUUID createUUID];
    [self setLastUpdateEventID:firstUUID hasMore:NO];
    
    // when
    [self setLastUpdateEventID:[self newNotificationID] hasMore:NO];
    
    // then
    XCTAssertEqualObjects(self.syncMOC.zm_lastNotificationID, [self newNotificationID]);
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
    XCTAssertEqualObjects(self.syncMOC.zm_lastNotificationID, expectedLastUpdateEventID);
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
    XCTAssertEqualObjects(self.syncMOC.zm_lastNotificationID, websocketUpdateEventID);
    
    // when
    [self.sut processEvents:@[downloadedEvent] liveEvents:YES prefetchResult:nil];
    
    // then
    XCTAssertEqualObjects(self.syncMOC.zm_lastNotificationID, downstreamUpdateEventID);
    
    // when
    [self.sut processEvents:@[pushNotificationEvent] liveEvents:YES prefetchResult:nil];
    
    // then
    XCTAssertNotEqualObjects(self.syncMOC.zm_lastNotificationID, notificationUpdateEventID);
    XCTAssertEqualObjects(self.syncMOC.zm_lastNotificationID, downstreamUpdateEventID);
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
    XCTAssertEqualObjects(self.syncMOC.zm_lastNotificationID, initialLastUpdateEventID);
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

@end


@implementation ZMMissingUpdateEventsTranscoderTests (APNSPingBack)

- (void)testThatItDoesNotReturnARequestWhenThereIsNoAPNSToFetch
{
    // given
    [(BackgroundAPNSPingBackStatus*)[[self.mockPingBackStatus expect] andReturnValue:OCMOCK_VALUE(PingBackStatusDone)] status];
    
    // when
    ZMTransportRequest *request = [self.sut nextRequest];
    
    // then
    XCTAssertNil(request);
}

- (void)testThatItReturnsARequestWhenThereIsAnAPNSToFetch
{
    // given
    self.syncMOC.zm_lastNotificationID = [NSUUID timeBasedUUID];
    
    EventsWithIdentifier *event = [[EventsWithIdentifier alloc] initWithEvents:@[] identifier:[NSUUID timeBasedUUID] isNotice:YES];
    [(BackgroundAPNSPingBackStatus*)[[self.mockPingBackStatus expect] andReturnValue:OCMOCK_VALUE(PingBackStatusFetchingNotificationStream)] status];
    [(BackgroundAPNSPingBackStatus*)[[self.mockPingBackStatus expect] andReturnValue:OCMOCK_VALUE(YES)] hasNoticeNotificationIDs];
    [(BackgroundAPNSPingBackStatus*)[[self.mockPingBackStatus expect] andReturn:event] nextNoticeNotificationEventsWithID];

    // when
    ZMTransportRequest *request = [self.sut nextRequest];
    
    // then
    XCTAssertNotNil(request);
    NSString *expectedPath = [NSString stringWithFormat:@"/notifications?size=500&since=%@&cancel_fallback=%@", self.syncMOC.zm_lastNotificationID.transportString, event.identifier.transportString];
    XCTAssertEqualObjects(request.path, expectedPath);
}

- (void)testThatItCallsBackPingBackStatusWhenRequestFinishes
{
    // given
    self.syncMOC.zm_lastNotificationID = [NSUUID timeBasedUUID];
    
    EventsWithIdentifier *event = [[EventsWithIdentifier alloc] initWithEvents:@[] identifier:[NSUUID timeBasedUUID] isNotice:YES];
    [(BackgroundAPNSPingBackStatus*)[[self.mockPingBackStatus stub] andReturnValue:OCMOCK_VALUE(PingBackStatusFetchingNotificationStream)] status];
    [(BackgroundAPNSPingBackStatus*)[[self.mockPingBackStatus expect] andReturnValue:OCMOCK_VALUE(YES)] hasNoticeNotificationIDs];
    [(BackgroundAPNSPingBackStatus*)[[self.mockPingBackStatus expect] andReturn:event] nextNoticeNotificationEventsWithID];
    ZMTransportRequest *request = [self.sut nextRequest];
    XCTAssertNotNil(request);

    // expect
    // it returns the events and hasMore No
    [[self.mockPingBackStatus expect] missingUpdateEventTranscoderWithDidReceiveEvents:@[] originalEvents:event hasMore:NO];
    
    // when
    [request completeWithResponse:[ZMTransportResponse responseWithPayload:@{@"notifications" : @[]} HTTPstatus:200 transportSessionError:nil]];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // and expect
    // when we call nextRequest again, it does not create a request, because the event to fetch should be cleared
    [(BackgroundAPNSPingBackStatus*)[[self.mockPingBackStatus expect] andReturnValue:OCMOCK_VALUE(NO)] hasNoticeNotificationIDs];
    
    // when
    ZMTransportRequest *nextRequest1 = [self.sut nextRequest];
    
    // then
    XCTAssertNil(nextRequest1);
    [self.mockPingBackStatus verify];
    
    // and when
    // when we do a normal quicksync it does not include the pingback parameter anymore
    [self.sut startDownloadingMissingNotifications];
    ZMTransportRequest *nextRequest2  = [[self.sut requestGenerators] nextRequest];
    
    // then
    XCTAssertNotNil(nextRequest2);
    NSString *expectedPath = [NSString stringWithFormat:@"/notifications?size=500&since=%@", self.syncMOC.zm_lastNotificationID.transportString];
    XCTAssertEqualObjects(nextRequest2.path, expectedPath);
}

- (void)testThatItCallsBackPingBackStatusWhenRequestFinishes_HasMore
{
    // given
    self.syncMOC.zm_lastNotificationID = [NSUUID timeBasedUUID];
    
    EventsWithIdentifier *event = [[EventsWithIdentifier alloc] initWithEvents:@[] identifier:[NSUUID timeBasedUUID] isNotice:YES];
    [(BackgroundAPNSPingBackStatus*)[[self.mockPingBackStatus stub] andReturnValue:OCMOCK_VALUE(PingBackStatusFetchingNotificationStream)] status];
    [(BackgroundAPNSPingBackStatus*)[[self.mockPingBackStatus expect] andReturnValue:OCMOCK_VALUE(YES)] hasNoticeNotificationIDs];
    [(BackgroundAPNSPingBackStatus*)[[self.mockPingBackStatus expect] andReturn:event] nextNoticeNotificationEventsWithID];
    ZMTransportRequest *request = [self.sut nextRequest];
    XCTAssertNotNil(request);
    
    // expect
    [[self.mockPingBackStatus expect] missingUpdateEventTranscoderWithDidReceiveEvents:@[] originalEvents:event hasMore:YES];
    
    // when
    [request completeWithResponse:[ZMTransportResponse responseWithPayload:@{@"notifications" : @[], @"has_more" : @1} HTTPstatus:200 transportSessionError:nil]];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // and expect
    // when we ask for the nextRequest it still has the event to fetch
    [(BackgroundAPNSPingBackStatus*)[[self.mockPingBackStatus expect] andReturnValue:OCMOCK_VALUE(NO)] hasNoticeNotificationIDs];

    // and when
    ZMTransportRequest *nextRequest  = [self.sut nextRequest];
    
    // then
    XCTAssertNotNil(nextRequest);
    NSString *expectedPath = [NSString stringWithFormat:@"/notifications?size=500&since=%@&cancel_fallback=%@", self.syncMOC.zm_lastNotificationID.transportString, event.identifier.transportString];
    XCTAssertEqualObjects(nextRequest.path, expectedPath);
    
    [self.mockPingBackStatus verify];
}

- (void)testThatWeCanPingBackTwiceInARow
{
    // given
    self.syncMOC.zm_lastNotificationID = [NSUUID timeBasedUUID];
    
    EventsWithIdentifier *event1 = [[EventsWithIdentifier alloc] initWithEvents:@[] identifier:[NSUUID timeBasedUUID] isNotice:YES];
    EventsWithIdentifier *event2 = [[EventsWithIdentifier alloc] initWithEvents:@[] identifier:[NSUUID timeBasedUUID] isNotice:YES];

    [(BackgroundAPNSPingBackStatus*)[[self.mockPingBackStatus stub] andReturnValue:OCMOCK_VALUE(PingBackStatusFetchingNotificationStream)] status];
    [(BackgroundAPNSPingBackStatus*)[[self.mockPingBackStatus expect] andReturnValue:OCMOCK_VALUE(YES)] hasNoticeNotificationIDs];
    [(BackgroundAPNSPingBackStatus*)[[self.mockPingBackStatus expect] andReturn:event1] nextNoticeNotificationEventsWithID];
    ZMTransportRequest *request = [self.sut nextRequest];
    XCTAssertNotNil(request);
    
    // expect
    [[self.mockPingBackStatus expect] missingUpdateEventTranscoderWithDidReceiveEvents:@[] originalEvents:event1 hasMore:NO];
    
    // when
    [request completeWithResponse:[ZMTransportResponse responseWithPayload:@{@"notifications" : @[]} HTTPstatus:200 transportSessionError:nil]];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // expect
    [(BackgroundAPNSPingBackStatus*)[[self.mockPingBackStatus expect] andReturnValue:OCMOCK_VALUE(YES)] hasNoticeNotificationIDs];
    [(BackgroundAPNSPingBackStatus*)[[self.mockPingBackStatus expect] andReturn:event2] nextNoticeNotificationEventsWithID];
    
    // when
    ZMTransportRequest *nextRequest = [self.sut nextRequest];
    
    // then
    XCTAssertNotNil(request);
    NSString *expectedPath = [NSString stringWithFormat:@"/notifications?size=500&since=%@&cancel_fallback=%@", self.syncMOC.zm_lastNotificationID.transportString, event2.identifier.transportString];
    XCTAssertEqualObjects(nextRequest.path, expectedPath);
    
    [self.mockPingBackStatus verify];
}

- (void)testThatItNotifiesPingBackStatusWhenRequestFailsPermanently
{
    // given
    self.syncMOC.zm_lastNotificationID = [NSUUID timeBasedUUID];
    
    EventsWithIdentifier *event = [[EventsWithIdentifier alloc] initWithEvents:@[] identifier:[NSUUID timeBasedUUID] isNotice:YES];
    [(BackgroundAPNSPingBackStatus*)[[self.mockPingBackStatus stub] andReturnValue:OCMOCK_VALUE(PingBackStatusFetchingNotificationStream)] status];
    [(BackgroundAPNSPingBackStatus*)[[self.mockPingBackStatus expect] andReturnValue:OCMOCK_VALUE(YES)] hasNoticeNotificationIDs];
    [(BackgroundAPNSPingBackStatus*)[[self.mockPingBackStatus expect] andReturn:event] nextNoticeNotificationEventsWithID];
    ZMTransportRequest *request = [self.sut nextRequest];
    XCTAssertNotNil(request);
    
    // expect
    [[self.mockPingBackStatus expect] missingUpdateEventTranscoderFailedDownloadingEvents:event];
    
    // when
    [request completeWithResponse:[ZMTransportResponse responseWithPayload:nil HTTPstatus:400 transportSessionError:nil]];
    WaitForAllGroupsToBeEmpty(0.5);
    
    [self.mockPingBackStatus verify];

    // and when
    // when we do a normal quicksync it does not include the pingback parameter anymore
    [self.sut startDownloadingMissingNotifications];
    ZMTransportRequest *nextRequest2  = [[self.sut requestGenerators] nextRequest];
    
    // then
    XCTAssertNotNil(nextRequest2);
    NSString *expectedPath = [NSString stringWithFormat:@"/notifications?size=500&since=%@", self.syncMOC.zm_lastNotificationID.transportString];
    XCTAssertEqualObjects(nextRequest2.path, expectedPath);
}

@end
