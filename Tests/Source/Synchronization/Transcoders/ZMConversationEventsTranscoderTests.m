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

#import "MessagingTest.h"
#import "ZMIncompleteConversationsCache.h"
#import "ZMConversationEventsTranscoder+Internal.h"

#import "ZMSyncStrategy.h"
#import <zmessaging/zmessaging-Swift.h>

static NSString const *GetConversationURL = @"/conversations/%@/events?size=%lu&start=%@&end=%@";



@interface ZMConversationEventsTranscoderTests : MessagingTest

@property (nonatomic) ZMConversationEventsTranscoder *sut;
@property (nonatomic) ZMSyncStrategy *syncStrategy;
@property (nonatomic) id messageSync;
@property (nonatomic) ZMIncompleteConversationsCache *incompleteConversationsCache;
@property (nonatomic) id<HistorySynchronizationStatus> mockHistorySyncStatus;

@end

@implementation ZMConversationEventsTranscoderTests


- (ZMTransportRequest *)requestForFetchingRange:(ZMEventIDRange *)gap inConversation:(ZMConversation *)conversation
{
    return [self.sut requestForFetchingRange:gap conversation:conversation];
}

- (void)updateRange:(ZMEventIDRange *)range inConversation:(ZMConversation *)conversation withResponse:(ZMTransportResponse *)response
{
    [self.sut updateRange:range conversation:conversation response:response];
}

- (void)setUp
{
    [super setUp];
    
    self.syncStrategy = [OCMockObject niceMockForClass:ZMSyncStrategy.class];
    [[[(id) self.syncStrategy stub] andReturn:self.syncMOC] syncMOC];
    
    self.incompleteConversationsCache = [OCMockObject niceMockForClass:[ZMIncompleteConversationsCache class]];
    [self verifyMockLater:self.incompleteConversationsCache];
    
    self.mockHistorySyncStatus = [OCMockObject niceMockForProtocol:@protocol(HistorySynchronizationStatus)];
    [self verifyMockLater:self.mockHistorySyncStatus];
    
    self.sut = [[ZMConversationEventsTranscoder alloc] initWithConversationsCache:self.incompleteConversationsCache
                                                     historySynchronizationStatus:self.mockHistorySyncStatus
                                                                     syncStrategy:self.syncStrategy];
}

- (void)tearDown
{
    self.incompleteConversationsCache = nil;
    [self.sut tearDown];
    self.sut = nil;
    [super tearDown];
}


- (NSString *)requestURLForConversation:(ZMConversation *)conversation oldestEvent:(ZMEventID *)oldestEvent newestEvent:(ZMEventID *)newestEvent
{
    return [NSString stringWithFormat:[GetConversationURL copy],  [conversation.remoteIdentifier transportString], ZMMaximumMessagesPageSize, oldestEvent.transportString, newestEvent.transportString];
}

- (void)testThatItIsCreatedWithSlowSyncComplete
{
    XCTAssertTrue(self.sut.isSlowSyncDone);
}


- (void)testThatItDoesNotNeedsSlowSyncEvenAfterSetNeedsSlowSync
{
    // when
    [self.sut setNeedsSlowSync];
    
    // then
    XCTAssertTrue(self.sut.isSlowSyncDone);
}

- (void)testThatItWhitelistOnIncompleteConversationCache
{
    // expect
    [[(id)self.incompleteConversationsCache expect] whitelistTopConversationsIfIncomplete];
    
    // when
    [self.sut downloadTopIncompleteConversations];
    [(id)self.incompleteConversationsCache verify];
}

- (NSDictionary *)payloadForEventWithEventID:(ZMEventID *)eventID conversationID:(NSUUID *)conversationID
{
    NSDictionary *data = @{
                           @"content" : @"Borg",
                           @"nonce" : @"5eaa4c31-80b7-164f-5b90-29113435d390"
                           };
    return [self payloadForEventWithEventID:eventID
                             conversationID:conversationID
                                       data:data
                                       type:@"conversation.message-add"];
}

- (NSDictionary *)payloadForEventWithEventID:(ZMEventID *)eventID
                              conversationID:(NSUUID *)conversationID
                                        data:(NSDictionary *)data
                                        type:(NSString *)type
{
    return
    @{
        @"conversation" : conversationID.transportString,
        @"data" : data,
        @"from" : @"39562cc3-717d-4395-979c-5387ae17f5c3",
        @"id" : eventID.transportString,
        @"time" : @"2014-06-11T12:48:32.225Z",
        @"type" : type
        };
}

- (ZMConversation *)conversationWithUUID:(NSUUID *)uuid
{
    __block ZMConversation *conversation;
    [self.syncMOC performGroupedBlockAndWaitWithReasonableTimeout:^{
        conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        conversation.remoteIdentifier = uuid;
    }];
    return conversation;
}

- (NSDictionary *)payloadToFillGap:(ZMEventIDRange *)gap inConversationID:(NSUUID *)conversationID
{
    NSMutableArray *payload = [NSMutableArray array];
    [payload addObject:[self payloadForEventWithEventID:gap.oldestMessage conversationID:conversationID]];
    for(uint64_t i = gap.oldestMessage.major+1; i < gap.newestMessage.major; ++i)
    {
        [payload addObject:[self payloadForEventWithEventID:[ZMEventID eventIDWithMajor:i minor:5256] conversationID:conversationID]];
    }
    [payload addObject:[self payloadForEventWithEventID:gap.newestMessage conversationID:conversationID]];
    return @{@"events":payload};
}

- (void)testThatItRequestsMessagesFromAnIncompleteConversationFromTheCache
{
    // given
    ZMEventID *oldestEvent = [ZMEventID eventIDWithString:@"4.3"];
    ZMEventID *newestEvent = [ZMEventID eventIDWithString:@"35.a"];
    ZMEventIDRange *gap = [[ZMEventIDRange alloc] initWithEventIDs:@[oldestEvent, newestEvent]];
    
    
    NSUUID *uuid = [NSUUID createUUID];
    ZMConversation *conversation = [self conversationWithUUID:uuid];
    
    // expect
    [[[(id)self.incompleteConversationsCache expect] andReturn:[NSOrderedSet orderedSetWithObject:conversation]] incompleteWhitelistedConversations];
    [[[(id)self.incompleteConversationsCache expect] andReturn:gap] gapForConversation:conversation];
    
    [self verifyMockLater:self.incompleteConversationsCache];
    
    // when
    ZMTransportRequest *request = [self.sut.requestGenerators nextRequest];
    
    // then
    XCTAssertNotNil(request);
    XCTAssertEqualObjects(request.path, [self requestURLForConversation:conversation oldestEvent:oldestEvent newestEvent:newestEvent]);
}

- (void)testThatIncompleteMessagesRequestCannotExceedTheMaximumPageSize;
{
    // given
    ZMEventID *oldestEvent = [ZMEventID eventIDWithString:@"100.3"];
    ZMEventID *newestEvent = [ZMEventID eventIDWithString:@"12a.a"];
    ZMEventIDRange *gap = [[ZMEventIDRange alloc] initWithEventIDs:@[oldestEvent, newestEvent]];
    
    NSUUID *uuid = [NSUUID createUUID];
    ZMConversation *conversation = [self conversationWithUUID:uuid];
    
    // expect
    [[[(id)self.incompleteConversationsCache expect] andReturn:[NSOrderedSet orderedSetWithObject:conversation]] incompleteWhitelistedConversations];
    [[[(id)self.incompleteConversationsCache expect] andReturn:gap] gapForConversation:conversation];
    
    [self verifyMockLater:self.incompleteConversationsCache];
    
    // when
    ZMTransportRequest *request = [self.sut.requestGenerators nextRequest];
    
    // then
    XCTAssertNotNil(request);
    XCTAssertEqualObjects(request.path, [self requestURLForConversation:conversation oldestEvent:oldestEvent newestEvent:newestEvent]);

    // but given
    oldestEvent = [ZMEventID eventIDWithString:@"100.3"];
    newestEvent = [ZMEventID eventIDWithString:@"500.a"];
    gap = [[ZMEventIDRange alloc] initWithEventIDs:@[oldestEvent, newestEvent]];
    
    uuid = [NSUUID createUUID];
    conversation = [self conversationWithUUID:uuid];
    
    [[[(id)self.incompleteConversationsCache expect] andReturn:[NSOrderedSet orderedSetWithObject:conversation]] incompleteWhitelistedConversations];
    [[[(id)self.incompleteConversationsCache expect] andReturn:gap] gapForConversation:conversation];
    
    request = [self.sut.requestGenerators nextRequest];
    
    // then
    XCTAssertNotNil(request);
    XCTAssertEqualObjects(request.path, [self requestURLForConversation:conversation oldestEvent:[ZMEventID eventIDWithMajor:newestEvent.major - ZMMaximumMessagesPageSize minor:0] newestEvent:newestEvent]);
}

- (void)testThatItReturnsNilRequestIfThereAreNoIncompleteConversations
{
    // expect
    [[[(id)self.incompleteConversationsCache expect] andReturn:[NSOrderedSet orderedSet]] incompleteWhitelistedConversations];
    [self verifyMockLater:self.incompleteConversationsCache];
    
    // when
    ZMTransportRequest *request = [self.sut.requestGenerators nextRequest];
    
    // then
    XCTAssertNil(request);
}

- (void)testThatItDoesNotRequestFromTheSameConversationWhileThereIsAPendingRequest
{
    // given
    ZMEventID *oldestEvent = [ZMEventID eventIDWithString:@"4.3"];
    ZMEventID *newestEvent = [ZMEventID eventIDWithString:@"35.a"];
    ZMEventIDRange *gap = [[ZMEventIDRange alloc] initWithEventIDs:@[oldestEvent, newestEvent]];
    
    NSUUID *uuid = [NSUUID createUUID];
    ZMConversation *conversation = [self conversationWithUUID:uuid];
    
    // expect
    [[[(id)self.incompleteConversationsCache stub] andReturn:[NSOrderedSet orderedSetWithObject:conversation]] incompleteWhitelistedConversations];
    [[[(id)self.incompleteConversationsCache stub] andReturn:gap] gapForConversation:conversation];
    
    [self verifyMockLater:self.incompleteConversationsCache];
    
    ZMTransportRequest *request1 = [self.sut.requestGenerators nextRequest];
    // - sanity check
    XCTAssertNotNil(request1);
    XCTAssertEqualObjects(request1.path, [self requestURLForConversation:conversation oldestEvent:oldestEvent newestEvent:newestEvent]);
    
    // when
    ZMTransportRequest *request2 = [self.sut.requestGenerators nextRequest];
    
    // then
    XCTAssertNil(request2);
    
}

- (void)testThatItRequestsFromADifferentConversationWhileThereIsAlreadyAPendingRequestForAConversation
{
    // given
    ZMEventID *oldestEvent = [ZMEventID eventIDWithString:@"4.3"];
    ZMEventID *newestEvent = [ZMEventID eventIDWithString:@"35.a"];
    ZMEventIDRange *gap = [[ZMEventIDRange alloc] initWithEventIDs:@[oldestEvent, newestEvent]];
    
    NSUUID *uuid1 = [NSUUID createUUID];
    ZMConversation *conversation1 = [self conversationWithUUID:uuid1];
    
    
    NSUUID *uuid2 = [NSUUID createUUID];
    ZMConversation *conversation2 = [self conversationWithUUID:uuid2];
    
    
    // expect
    [[[(id)self.incompleteConversationsCache stub] andReturn:[NSOrderedSet orderedSetWithObjects:conversation1, conversation2, nil]] incompleteWhitelistedConversations];
    
    [[[(id)self.incompleteConversationsCache stub] andReturn:gap] gapForConversation:conversation1];
    [[[(id)self.incompleteConversationsCache stub] andReturn:gap] gapForConversation:conversation2];
    ZMTransportRequest *request1 = [self.sut.requestGenerators nextRequest];
    // - sanity check
    XCTAssertNotNil(request1);
    
    // Because it's a set, we don't know which one is picked first
    ZMConversation *expectedSecondConversation;
    if ([request1.path isEqualToString:[self requestURLForConversation:conversation1 oldestEvent:oldestEvent newestEvent:newestEvent]]) {
        expectedSecondConversation = conversation2;
    }
    else if ([request1.path isEqualToString:[self requestURLForConversation:conversation2 oldestEvent:oldestEvent newestEvent:newestEvent]]) {
        expectedSecondConversation = conversation1;
    }
    else {
        XCTFail(@"Unexpected request");
    }
    
    [(id)self.incompleteConversationsCache stopMocking];
    // when
    
    ZMTransportRequest *request2 = [self.sut.requestGenerators nextRequest];
    
    // then
    XCTAssertNotNil(request2);
    XCTAssertEqualObjects(request2.path, [self requestURLForConversation:expectedSecondConversation oldestEvent:oldestEvent newestEvent:newestEvent]);
    
}

- (void)testThatItRequestFromSameConversationAfterPendingRequestIsCompleted
{
    // given
    ZMEventID *oldestEvent = [ZMEventID eventIDWithString:@"4.3"];
    ZMEventID *newestEvent = [ZMEventID eventIDWithString:@"35.a"];
    ZMEventIDRange *gap = [[ZMEventIDRange alloc] initWithEventIDs:@[oldestEvent, newestEvent]];
    
    NSUUID *uuid = [NSUUID createUUID];
    ZMConversation *conversation = [self conversationWithUUID:uuid];

    [[[(id)self.incompleteConversationsCache stub] andReturn:[NSOrderedSet orderedSetWithObject:conversation]] incompleteWhitelistedConversations];
    [[[(id)self.incompleteConversationsCache stub] andReturn:gap] gapForConversation:conversation];
    
    [self verifyMockLater:self.incompleteConversationsCache];
    
    ZMTransportRequest *request1 = [self.sut.requestGenerators nextRequest];
    // - sanity check
    XCTAssertNotNil(request1);
    XCTAssertEqualObjects(request1.path, [self requestURLForConversation:conversation oldestEvent:oldestEvent newestEvent:newestEvent]);
    
    [request1 completeWithResponse:[ZMTransportResponse responseWithPayload:[self payloadToFillGap:gap inConversationID:uuid] HTTPStatus:200 transportSessionError:nil]];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // when
    ZMTransportRequest *request2 = [self.sut.requestGenerators nextRequest];
    
    // then
    XCTAssertNotNil(request2);
    XCTAssertEqualObjects(request2.path, [self requestURLForConversation:conversation oldestEvent:oldestEvent newestEvent:newestEvent]);
}

- (void)testThatItGeneratesTheCorrectRequestPath
{
    // given
    ZMEventID *oldestEvent = [ZMEventID eventIDWithString:@"1.800122000a24dcca"];
    ZMEventID *newestEvent = [ZMEventID eventIDWithString:@"2.800122000a24dccb"];
    ZMEventIDRange *gap = [[ZMEventIDRange alloc] initWithEventIDs:@[oldestEvent, newestEvent]];
    
    NSUUID *uuid = [NSUUID createUUID];
    ZMConversation *conversation = [self conversationWithUUID:uuid];

    [[[(id)self.incompleteConversationsCache stub] andReturn:[NSOrderedSet orderedSetWithObject:conversation]] incompleteWhitelistedConversations];
    [[[(id)self.incompleteConversationsCache stub] andReturn:gap] gapForConversation:conversation];
    
    // when
    ZMTransportRequest *request = [self.sut.requestGenerators nextRequest];
    
    // then
    XCTAssertNotNil(request);
    XCTAssertEqualObjects(request.path, [self requestURLForConversation:conversation oldestEvent:oldestEvent newestEvent:newestEvent]);
}

- (void)testThatItPropagatesDownloadedConversationEventsToTheSyncStrategy
{
    // given
    NSDictionary *event1Payload = @{
                             @"id": @"1.800122000a24dcca",
                             @"type": @"conversation.member-join",
                             @"origin_id": @"origId1",
                             @"time" : [NSDate date].transportString
                             };
    NSDictionary *event2Payload = @{
                             @"id": @"2.800122000a24dccb",
                             @"type": @"conversation.message-add",
                             @"origin_id": @"origId2",
                             @"time" : [NSDate date].transportString
                             };
    
    NSDictionary *payload =  @{
                               @"events": @[event1Payload, event2Payload]
                               };
    
    ZMEventID *oldestEvent = [ZMEventID eventIDWithString:event1Payload[@"id"]];
    ZMEventID *newestEvent = [ZMEventID eventIDWithString:event2Payload[@"id"]];
    ZMEventIDRange *gap = [[ZMEventIDRange alloc] initWithEventIDs:@[oldestEvent, newestEvent]];
    
    NSUUID *uuid = [NSUUID createUUID];
    ZMConversation *conversation = [self conversationWithUUID:uuid];
    
    [[[(id)self.incompleteConversationsCache stub] andReturn:[NSOrderedSet orderedSetWithObject:conversation]] incompleteWhitelistedConversations];
    [[[(id)self.incompleteConversationsCache stub] andReturn:gap] gapForConversation:conversation];
    
    ZMTransportRequest *request = [self.sut.requestGenerators nextRequest];
    // - sanity check
    XCTAssertNotNil(request);
    XCTAssertEqualObjects(request.path, [self requestURLForConversation:conversation oldestEvent:oldestEvent newestEvent:newestEvent]);
    
    // expect
    ZMUpdateEvent *event1 = [ZMUpdateEvent eventFromEventStreamPayload:event1Payload uuid:nil];
    ZMUpdateEvent *event2 = [ZMUpdateEvent eventFromEventStreamPayload:event2Payload uuid:nil];

    // The events should only go to the message sync, not anyone else:
    [(ZMSyncStrategy*) [(id)self.syncStrategy expect] processDownloadedEvents:@[event1, event2]];
    
    // when
    [request completeWithResponse:[ZMTransportResponse responseWithPayload:payload HTTPStatus:200 transportSessionError:nil]];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    [(id)self.syncStrategy verify];
    [self.messageSync verify];
}


- (void)testThatItDoesNotPropagateAnInvalidArrayResponsePayloadToTheSyncStrategy
{
    // given
    ZMEventID *oldestEvent = [ZMEventID eventIDWithString:@"1.800122000a24dcca"];
    ZMEventID *newestEvent = [ZMEventID eventIDWithString:@"2.800122000a24dccb"];
    ZMEventIDRange *gap = [[ZMEventIDRange alloc] initWithEventIDs:@[oldestEvent, newestEvent]];
    
    NSUUID *uuid = [NSUUID createUUID];
    ZMConversation *conversation = [self conversationWithUUID:uuid];

    [[[(id)self.incompleteConversationsCache stub] andReturn:[NSOrderedSet orderedSetWithObject:conversation]] incompleteNonWhitelistedConversations];
    [[[(id)self.incompleteConversationsCache stub] andReturn:gap] gapForConversation:conversation];
    
    // expect
    [[(id)self.syncStrategy reject] processUpdateEvents:OCMOCK_ANY ignoreBuffer:NO];
    [[(id)self.syncStrategy reject] processUpdateEvents:OCMOCK_ANY ignoreBuffer:YES];

    [self verifyMockLater:self.syncStrategy];
    
    
    // when
    ZMTransportRequest *request = [self.sut.requestGenerators nextRequest];
    
    // then
    [self performIgnoringZMLogError:^{
        [request completeWithResponse:[ZMTransportResponse responseWithPayload:@[] HTTPStatus:200 transportSessionError:nil]];
        WaitForAllGroupsToBeEmpty(0.5);
    }];
}

- (void)testThatItDoesNotPropagateAnInvalidResponseWithoutEventsToTheSyncStrategy
{
    // given
    ZMEventID *oldestEvent = [ZMEventID eventIDWithString:@"1.800122000a24dcca"];
    ZMEventID *newestEvent = [ZMEventID eventIDWithString:@"2.800122000a24dccb"];
    ZMEventIDRange *gap = [[ZMEventIDRange alloc] initWithEventIDs:@[oldestEvent, newestEvent]];
    
    NSUUID *uuid = [NSUUID createUUID];
    ZMConversation *conversation = [self conversationWithUUID:uuid];
    
    [[[(id)self.incompleteConversationsCache stub] andReturn:[NSOrderedSet orderedSetWithObject:conversation]] incompleteNonWhitelistedConversations];
    [[[(id)self.incompleteConversationsCache stub] andReturn:gap] gapForConversation:conversation];
    
    // expect
    [[(id)self.syncStrategy reject] processUpdateEvents:OCMOCK_ANY ignoreBuffer:YES];
    [[(id)self.syncStrategy reject] processUpdateEvents:OCMOCK_ANY ignoreBuffer:NO];
    [self verifyMockLater:self.syncStrategy];
    
    
    // when
    ZMTransportRequest *request = [self.sut.requestGenerators nextRequest];
    
    // then
    [self performIgnoringZMLogError:^{
        [request completeWithResponse:[ZMTransportResponse responseWithPayload:@{@"foo":@"bar"} HTTPStatus:200 transportSessionError:nil]];
        WaitForAllGroupsToBeEmpty(0.5);
    }];
    
}

- (void)testThatItDoesNotPropagateAnInvalidResponseWithInvalidEventsToTheSyncStrategy
{
    // given
    ZMEventID *oldestEvent = [ZMEventID eventIDWithString:@"1.800122000a24dcca"];
    ZMEventID *newestEvent = [ZMEventID eventIDWithString:@"2.800122000a24dccb"];
    ZMEventIDRange *gap = [[ZMEventIDRange alloc] initWithEventIDs:@[oldestEvent, newestEvent]];
    
    NSUUID *uuid = [NSUUID createUUID];
    ZMConversation *conversation = [self conversationWithUUID:uuid];
    
    [[[(id)self.incompleteConversationsCache stub] andReturn:[NSOrderedSet orderedSetWithObject:conversation]] incompleteNonWhitelistedConversations];
    [[[(id)self.incompleteConversationsCache stub] andReturn:gap] gapForConversation:conversation];
    
    // expect
    [[(id)self.syncStrategy reject] processUpdateEvents:OCMOCK_ANY ignoreBuffer:NO];
    [[(id)self.syncStrategy reject] processUpdateEvents:OCMOCK_ANY ignoreBuffer:YES];
    [self verifyMockLater:self.syncStrategy];
    
    
    // when
    ZMTransportRequest *request = [self.sut.requestGenerators nextRequest];
    
    // then
    [self performIgnoringZMLogError:^{
        [request completeWithResponse:[ZMTransportResponse responseWithPayload:@{@"events":@22} HTTPStatus:200 transportSessionError:nil]];
        WaitForAllGroupsToBeEmpty(0.5);
    }];
}

- (void)testThatItDoesNotPropagateAnErrorResponseToTheSyncStrategy
{
    // given
    ZMEventID *oldestEvent = [ZMEventID eventIDWithString:@"1.800122000a24dcca"];
    ZMEventID *newestEvent = [ZMEventID eventIDWithString:@"2.800122000a24dccb"];
    ZMEventIDRange *gap = [[ZMEventIDRange alloc] initWithEventIDs:@[oldestEvent, newestEvent]];
    
    NSUUID *uuid = [NSUUID createUUID];
    ZMConversation *conversation = [self conversationWithUUID:uuid];
    
    [[[(id)self.incompleteConversationsCache stub] andReturn:[NSOrderedSet orderedSetWithObject:conversation]] incompleteNonWhitelistedConversations];
    [[[(id)self.incompleteConversationsCache stub] andReturn:gap] gapForConversation:conversation];
    
    // expect
    [[(id)self.syncStrategy reject] processUpdateEvents:OCMOCK_ANY ignoreBuffer:NO];
    [[(id)self.syncStrategy reject] processUpdateEvents:OCMOCK_ANY ignoreBuffer:YES];

    [self verifyMockLater:self.syncStrategy];
    
    
    // when
    ZMTransportRequest *request = [self.sut.requestGenerators nextRequest];
    
    // then
    [request completeWithResponse:[ZMTransportResponse responseWithPayload:@{@"events":@[oldestEvent.transportString, newestEvent.transportString]} HTTPStatus:500 transportSessionError:nil]];
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatWhenProcessingConversationUpdateEventsItRegistersThoseEventsAsNotMissing
{
    // given
    NSUUID *uuid = [NSUUID createUUID];
    NSString *eventID = @"2.800122000a24dccb";
    ZMEventID *oldestEvent = [ZMEventID eventIDWithString:@"1.800122000a24dcca"];
    ZMEventID *middleEvent = [ZMEventID eventIDWithString:eventID];
    ZMEventID *newestEvent = [ZMEventID eventIDWithString:@"3.800122000a24dccc"];
    
    NSDictionary *eventPayload = @{
                                   @"conversation" : [uuid transportString],
                                   @"id" : eventID,
                                   @"type": @"conversation.message-add"
                                   };
    
    ZMUpdateEvent *event = [ZMUpdateEvent eventFromEventStreamPayload:eventPayload uuid:nil];
    XCTAssertNotNil(event);

    ZMConversation *conversation = [self conversationWithUUID:uuid];
    ZMConversation *otherConversation = [self conversationWithUUID:[NSUUID createUUID]];
    
    [[[(id)self.incompleteConversationsCache stub] andReturn:[NSOrderedSet orderedSetWithObjects:otherConversation, conversation, nil]] incompleteNonWhitelistedConversations];
    
    ZMEventIDRange *range = [[ZMEventIDRange alloc] initWithEventIDs:@[oldestEvent, middleEvent, newestEvent]];
    ZMEventIDRangeSet *originalRangeSet = [[ZMEventIDRangeSet alloc] initWithRanges:@[range]];
    conversation.downloadedMessageIDs = originalRangeSet;
    
    ZMEventIDRangeSet *expectedRangeSet = [originalRangeSet setByAddingEvent:middleEvent];
        
        // when
    [self.syncMOC performGroupedBlockAndWait:^{
        [self.sut processEvents:@[event] liveEvents:YES prefetchResult:nil];
    }];

    // then
    XCTAssertEqualObjects(expectedRangeSet, conversation.downloadedMessageIDs);
}

- (void)testThatWhenProcessingAConversationEventsResponseWithInvalidDataTheGapIsMarkedAsFilledAnyway
{
    // given
    ZMEventID *oldestEvent = [ZMEventID eventIDWithMajor:1 minor:234];
    ZMEventID *newestEvent = [ZMEventID eventIDWithMajor:10 minor:4325];
    NSUUID *conversationUUID = [NSUUID createUUID];
    ZMEventIDRange *range = [[ZMEventIDRange alloc] initWithEventIDs:@[oldestEvent, newestEvent]];
    ZMEventIDRangeSet *expectedRange = [[ZMEventIDRangeSet alloc] initWithRanges:@[range]];
    
    NSDictionary *eventPayload = @{
                                   @"foo" : @"bar"
                                   };
    
    ZMConversation *conversation = [self conversationWithUUID:conversationUUID];
    
    [[[(id)self.incompleteConversationsCache stub] andReturn:[NSOrderedSet orderedSetWithObjects:conversation, nil]] incompleteWhitelistedConversations];
    [[[(id)self.incompleteConversationsCache expect] andReturn:range] gapForConversation:conversation];
    
    ZMTransportRequest *request = [self.sut.requestGenerators nextRequest];
    
    // when
    [self performIgnoringZMLogError:^{
        [request completeWithResponse:[ZMTransportResponse responseWithPayload:eventPayload HTTPStatus:200 transportSessionError:nil]];
        WaitForAllGroupsToBeEmpty(0.5);
    }];
    
    // then
    XCTAssertEqualObjects(conversation.downloadedMessageIDs, expectedRange);
}

- (void)testThatWhenProcessingAConversationEventsResponseWithAnInvalidEventTheRestOfTheGapIsMarkedAsFilledAnyway
{
    // given
    ZMEventID *oldestEvent = [ZMEventID eventIDWithMajor:1 minor:234];
    ZMEventID *newestEvent = [ZMEventID eventIDWithMajor:2 minor:4325];
    NSUUID *conversationUUID = [NSUUID createUUID];
    ZMEventIDRange *gap = [[ZMEventIDRange alloc] initWithEventIDs:@[oldestEvent, newestEvent]];
    ZMEventIDRangeSet *expectedRange = [[ZMEventIDRangeSet alloc] initWithEvent:oldestEvent];
    
    NSDictionary *eventPayload = @{
                                   @"events" : @[
                                           @{
                                               @"conversation" : conversationUUID.transportString,
                                               @"id": oldestEvent.transportString,
                                               @"type": @"conversation.member-join",
                                               @"time": [NSDate date].transportString
                                           }
                                       ]
                                   };
    
    ZMConversation *conversation = [self conversationWithUUID:conversationUUID];
    
    [[[(id)self.incompleteConversationsCache stub] andReturn:[NSOrderedSet orderedSetWithObjects:conversation, nil]] incompleteWhitelistedConversations];
    [[[(id)self.incompleteConversationsCache stub] andReturn:gap] gapForConversation:conversation];

    ZMTransportRequest *request = [self.sut.requestGenerators nextRequest];
    
    // when
    [request completeWithResponse:[ZMTransportResponse responseWithPayload:eventPayload HTTPStatus:200 transportSessionError:nil]];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqualObjects(conversation.downloadedMessageIDs, expectedRange);

}



- (void)testThatItMarksTheGapAsFilledWhenEncounteringAPermanentError
// this way we prevent an infinite refetch loop (because the gap would never get filled otherwise)
{
    // given
    ZMEventID *oldestEvent = [ZMEventID eventIDWithMajor:1 minor:234];
    ZMEventID *newestEvent = [ZMEventID eventIDWithMajor:2 minor:4325];
    NSUUID *conversationUUID = [NSUUID createUUID];
    ZMEventIDRange *gap = [[ZMEventIDRange alloc] initWithEventIDs:@[oldestEvent, newestEvent]];
    ZMEventIDRangeSet *expectedRange = [[ZMEventIDRangeSet alloc] initWithRanges:@[gap]];
    
    ZMConversation *conversation = [self conversationWithUUID:conversationUUID];
    
    [[[(id)self.incompleteConversationsCache stub] andReturn:[NSOrderedSet orderedSetWithObjects:conversation, nil]] incompleteWhitelistedConversations];
    [[[(id)self.incompleteConversationsCache stub] andReturn:gap] gapForConversation:conversation];
    
    ZMTransportRequest *request = [self.sut.requestGenerators nextRequest];
    
    // when
    [request completeWithResponse:[ZMTransportResponse responseWithPayload:@{} HTTPStatus:404 transportSessionError:nil]];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqualObjects(conversation.downloadedMessageIDs, expectedRange);

}

- (void)testThatIsSkipsSelfConversationEvents
{
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:ZMConversation.entityName];
        ZMEventID *eventID = [self createEventID];
        
        NSUUID *conversationUUID = [NSUUID createUUID];
        [ZMUser selfUserInContext:self.syncMOC].remoteIdentifier = conversationUUID;
        
        NSDictionary *payload = [self payloadForEventWithEventID:eventID conversationID:conversationUUID];
        ZMUpdateEvent *event = [ZMUpdateEvent eventFromEventStreamPayload:payload uuid:nil];
        
        // when
        NSUInteger const originalCount = [self.syncMOC countForFetchRequest:request error:nil];
        [self.sut processEvents:@[event] liveEvents:NO prefetchResult:nil];
        [self.syncMOC saveOrRollback];
        
        // then
        NSUInteger const count = [self.syncMOC countForFetchRequest:request error:nil];
        XCTAssertEqual(count, originalCount);
    }];
}

- (void)testThatWhenItReceivesAHotKnockEventWhichIsTheLastReadItSetsTheLastReadTimeStamp
{
    // given
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    conversation.remoteIdentifier = [NSUUID createUUID];
    [conversation addEventToDownloadedEvents:self.createEventID timeStamp:nil];
    conversation.lastReadEventID = self.createEventID;
    conversation.lastEventID = [ZMEventID eventIDWithMajor:conversation.lastReadEventID.major+1 minor:2];

    NSDictionary *eventData = [self payloadForEventWithEventID:conversation.lastReadEventID
                                              conversationID:conversation.remoteIdentifier
                                                        data:@{}
                                                        type:@"conversation.hot-knock"];
    NSDate *lastReadTimeStamp = [eventData dateForKey:@"time"];
    NSDictionary *payload = @{@"events": @[eventData]};
    
    ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:payload HTTPStatus:200 transportSessionError:nil];
    
    ZMEventIDRange *range = [[ZMEventIDRange alloc] initWithEventIDs:@[conversation.lastReadEventID, conversation.lastEventID]];
    XCTAssertTrue([range containsEvent:conversation.lastReadEventID]);
    XCTAssertFalse([conversation.downloadedMessageIDs containsEvent:conversation.lastReadEventID]);
    XCTAssertNil(conversation.lastReadServerTimeStamp);
    
    // when
    [self performIgnoringZMLogError:^{
        [self.sut updateRange:range conversation:conversation response:response];
    }];
    
    // then
    XCTAssertTrue([conversation.downloadedMessageIDs containsEvent:conversation.lastReadEventID]);
    XCTAssertNotNil(conversation.lastReadServerTimeStamp);
    XCTAssertEqualObjects(conversation.lastReadServerTimeStamp, lastReadTimeStamp);
}

@end
