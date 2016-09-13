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


@import zimages;
@import ZMTransport;
@import ZMCMockTransport;
@import CoreGraphics;
@import ImageIO;
@import zmessaging;
@import ZMCDataModel;

#import "MessagingTest.h"

#import "ZMAssetTranscoder.h"
#import "ZMContextChangeTracker.h"
#import "ZMUpstreamAssetSync.h"
#import "ZMContextChangeTracker.h"
#import "ZMUpstreamTranscoder.h"
#import "ZMDownstreamObjectSync.h"
#import "ZMImagePreprocessingTracker.h"
#import "ZMChangeTrackerBootstrap+Testing.h"




#if TARGET_OS_IPHONE
@import MobileCoreServices;
#else
@import CoreServices;
#endif


static NSString const *EventTypeAssetAdd = @"conversation.asset-add";

//OCMock can't stub dynamic properties, so we have to create a protocol for ZMImageMessage
@protocol ZMMockableImageMessage
- (NSData *)mediumData;
@end


@interface ZMImageMessage (Test) <ZMMockableImageMessage>
@end

@implementation ZMImageMessage (Test)
@end


@interface ZMAssetTranscoderTests : MessagingTest

@property (nonatomic) ZMAssetTranscoder *sut;
@property (nonatomic) ZMUser *user1;
@end



@implementation ZMAssetTranscoderTests

- (void)setUp
{
    [super setUp];

    [self.syncMOC performBlockAndWait:^{
        ZMUser *selfUser = [ZMUser selfUserInContext:self.syncMOC];
        selfUser.remoteIdentifier = NSUUID.createUUID;
        ZMConversation *selfConversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        selfConversation.remoteIdentifier = selfUser.remoteIdentifier;
        selfConversation.conversationType = ZMConversationTypeSelf;
        [self.syncMOC saveOrRollback];
    }];
    self.sut = [[ZMAssetTranscoder alloc] initWithManagedObjectContext:self.syncMOC];
}


- (void)resetSUT
{
    [self.sut tearDown];
    self.sut = [[ZMAssetTranscoder alloc] initWithManagedObjectContext:self.syncMOC];
    WaitForAllGroupsToBeEmpty(0.5);
    [ZMChangeTrackerBootstrap bootStrapChangeTrackers:self.sut.contextChangeTrackers onContext:self.syncMOC];
}
- (void)tearDown
{
    [self.sut tearDown];
    self.sut = nil;
    [super tearDown];
}

- (NSMutableDictionary *)createPushEventPayloadWithData:(NSDictionary *)data conversationID:(NSUUID *)conversationID;
{
    NSMutableDictionary *innerPayload = [@{
                                           @"conversation": conversationID.transportString,
                                           @"data": data,
                                           @"id": [self createEventID].transportString,
                                           @"from": [NSUUID createUUID].transportString,
                                           @"time": [NSDate date].transportString,
                                           @"type": EventTypeAssetAdd,
                                           } mutableCopy];
    
    return innerPayload;
}

- (NSMutableDictionary *)createAssetMediumEventPayloadForAssetID:(NSUUID *)assetID conversationID:(NSUUID *)conversationID
{
    
    NSUUID *nonce = [NSUUID createUUID];
    NSDictionary *info = @{
                           @"correlation_id": [NSUUID createUUID].transportString,
                           @"height": @464,
                           @"width": @510,
                           @"name": [NSNull null],
                           @"nonce": nonce.transportString,
                           @"original_height": @768,
                           @"original_width": @1024,
                           @"public": @NO,
                           @"tag": @"medium",
                           };
    
    NSDictionary *data = @{
                           @"content_length": @47566,
                           @"content_type": @"image/jpeg",
                           @"data": [NSNull null],
                           @"id": assetID.transportString,
                           @"info": info
                           };
    
    return [self createPushEventPayloadWithData:data conversationID:conversationID];
}



- (NSString *)assetPathForAssetID:(NSUUID *)assetID conversationID:(NSUUID *)conversationID {
    return [NSString pathWithComponents:@[@"/", @"assets", [NSString stringWithFormat:@"%@?conv_id=%@", assetID.transportString, conversationID.transportString]]];
}

- (ZMUpdateEvent *)createMediumImageUpdateEvent {
    NSUUID *assetID = [NSUUID createUUID];
    NSUUID *conversationID = [NSUUID createUUID];
    NSDictionary *eventPayload = [self createAssetMediumEventPayloadForAssetID:assetID conversationID:conversationID];
    ZMUpdateEvent *event = [ZMUpdateEvent eventFromEventStreamPayload:eventPayload uuid:nil];
    return event;
}

- (ZMImageMessage *)fetchOnlyExistingImageMessage
{
    NSFetchRequest *fetchRequest = [ZMImageMessage sortedFetchRequest];
    NSArray *imageMessages = [self.syncMOC executeFetchRequestOrAssert:fetchRequest];
    XCTAssertEqual(imageMessages.count, 1u);
    return [imageMessages firstObject];
}

- (ZMConversation *)insertGroupConversationInMoc:(NSManagedObjectContext *)moc
{
    ZMUser *user1 = [ZMUser insertNewObjectInManagedObjectContext:moc];
    user1.remoteIdentifier = [NSUUID createUUID];
    self.user1 = user1;
    
    ZMUser *user2 = [ZMUser insertNewObjectInManagedObjectContext:moc];
    user2.remoteIdentifier = [NSUUID createUUID];
    
    ZMConversation *conversation = [ZMConversation insertGroupConversationIntoManagedObjectContext:moc withParticipants:@[user1, user2]];
    conversation.remoteIdentifier = [NSUUID createUUID];
    return conversation;
}

- (ZMConversation *)insertGroupConversation
{
    __block ZMConversation *result = nil;
    [self.syncMOC performGroupedBlockAndWait:^{
        result = [self insertGroupConversationInMoc:self.syncMOC];
        XCTAssertTrue([self.syncMOC saveOrRollback]);
    }];
    return result;
}

/// This assumes we're on the syncMOC
- (void)pushContextChangesIntoChangeTrackers;
{
    [self.syncMOC processPendingChanges];
    NSMutableSet *unionSet = [NSMutableSet setWithSet:self.syncMOC.insertedObjects];
    [unionSet unionSet:self.syncMOC.updatedObjects];
    for (id<ZMContextChangeTracker> t in self.sut.contextChangeTrackers) {
        [t objectsDidChange:unionSet];
    }
}

- (void)notifyChangeTrackersWithObject:(ZMManagedObject *)mo;
{
    for (id<ZMContextChangeTracker> t in self.sut.contextChangeTrackers) {
        [t objectsDidChange:[NSSet setWithObject:mo]];
    }
}

@end


@implementation ZMAssetTranscoderTests (General)

- (void)testThatItIsCreatedWithIsSlowSyncDoneTrue
{
    XCTAssertTrue(self.sut.isSlowSyncDone);
}


- (void)testThatItReturnsNilIfThereIsNotAssetToSync
{
    ZMTransportRequest *request = [self.sut.requestGenerators nextRequest];
    XCTAssertNil(request);
}

- (void)testThatItDoesNotGeneratesAnAssetRequestWhenReceivingAMessageButNotRequestingToDownloadIt
{
    // given
    NSUUID *assetID = [NSUUID createUUID];
    NSUUID *conversationID = [NSUUID createUUID];
    NSDictionary *eventPayload = [self createAssetMediumEventPayloadForAssetID:assetID conversationID:conversationID];
    ZMUpdateEvent *event = [ZMUpdateEvent eventFromEventStreamPayload:eventPayload uuid:nil];
    
    // when
    __block ZMTransportRequest *request;
    [self.syncMOC performGroupedBlockAndWait:^{
        [self.sut processEvents:@[event] liveEvents:YES prefetchResult:nil];
        [self pushContextChangesIntoChangeTrackers];
        request = [self.sut.requestGenerators nextRequest];
    }];
    
    // then
    XCTAssertNil(request);
}

- (void)testThatItGeneratesAnAssetRequestWhenReceivingAMessageAndRequestingToDownloadIt
{
    // given
    NSUUID *assetID = [NSUUID createUUID];
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
    conversation.remoteIdentifier = [NSUUID createUUID];
    NSDictionary *eventPayload = [self createAssetMediumEventPayloadForAssetID:assetID conversationID:conversation.remoteIdentifier];
    ZMUpdateEvent *event = [ZMUpdateEvent eventFromEventStreamPayload:eventPayload uuid:nil];
    __block ZMImageMessage *imageMessage;
    [self.syncMOC performGroupedBlockAndWait:^{
        [self.sut processEvents:@[event] liveEvents:YES prefetchResult:nil];
        [self pushContextChangesIntoChangeTrackers];
        imageMessage = conversation.messages.firstObject;
    }];
    [self.syncMOC saveOrRollback];
    
    // when
    [imageMessage requestImageDownload];
    WaitForAllGroupsToBeEmpty(0.5);
    
    __block ZMTransportRequest *request;
    [self.syncMOC performGroupedBlockAndWait:^{
        request = [self.sut.requestGenerators nextRequest];
    }];

    // then
    NSString *expectedPath = [self assetPathForAssetID:assetID conversationID:conversation.remoteIdentifier];
    XCTAssertEqualObjects(request.path, expectedPath);
    XCTAssertEqual(request.method, ZMMethodGET);
    XCTAssertNil(request.payload);
    XCTAssertEqual(request.acceptedResponseMediaTypes, ZMTransportAcceptImage);
}



- (void)testThatItSyncsImageDataIfTheImageMessageHasARemoteIDButNoImageData
{
    // given
    NSUUID *assetID = [NSUUID createUUID];
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
    conversation.remoteIdentifier = [NSUUID createUUID];
    NSDictionary *eventPayload = [self createAssetMediumEventPayloadForAssetID:assetID conversationID:conversation.remoteIdentifier];
    ZMUpdateEvent *event = [ZMUpdateEvent eventFromEventStreamPayload:eventPayload uuid:nil];
    NSData *imageData = [@"image-data-0q39eijdkslfm" dataUsingEncoding:NSUTF8StringEncoding];
    ZMTransportResponse *response = [[ZMTransportResponse alloc] initWithImageData:imageData HTTPstatus:200 transportSessionError:nil headers:nil];
    
    [self.syncMOC performGroupedBlockAndWait:^{
        [self.sut processEvents:@[event] liveEvents:YES prefetchResult:nil];
        [self pushContextChangesIntoChangeTrackers];
        [self.syncMOC saveOrRollback];
    }];

    [conversation.messages.lastObject requestImageDownload];
    WaitForAllGroupsToBeEmpty(0.5);

    // when
    __block ZMImageMessage *imageMessage = nil;
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMTransportRequest *request = [self.sut.requestGenerators nextRequest];
        XCTAssertNotNil(request);
        [request completeWithResponse:response];
        
        // then
        imageMessage = [self fetchOnlyExistingImageMessage];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    XCTAssertEqualObjects(imageMessage.mediumData, imageData);
}


- (void)testThatItDoesNotDoAnythingIfTheRequestFails
{
    // given
    NSUUID *assetID = [NSUUID createUUID];
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
    conversation.remoteIdentifier = [NSUUID createUUID];
    NSDictionary *eventPayload = [self createAssetMediumEventPayloadForAssetID:assetID conversationID:conversation.remoteIdentifier];
    ZMUpdateEvent *event = [ZMUpdateEvent eventFromEventStreamPayload:eventPayload uuid:nil];
    NSData *imageData = [@"image-data-0q39eijdkslfm" dataUsingEncoding:NSUTF8StringEncoding];
    ZMTransportResponse *response = [[ZMTransportResponse alloc] initWithImageData:imageData HTTPstatus:404 transportSessionError:nil headers:nil];

    [self.syncMOC performGroupedBlockAndWait:^{
        [self.sut processEvents:@[event] liveEvents:YES prefetchResult:nil];
        [self pushContextChangesIntoChangeTrackers];
        [self.syncMOC saveOrRollback];
    }];
    WaitForAllGroupsToBeEmpty(0.5);

    [conversation.messages.lastObject requestImageDownload];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // when
    __block ZMImageMessage *imageMessage;
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMTransportRequest *request = [self.sut.requestGenerators nextRequest];
        XCTAssertNotNil(request);
        [request completeWithResponse:response];
        
        // then
        imageMessage = [self fetchOnlyExistingImageMessage];
    }];
    
    // then
    XCTAssertNil(imageMessage.mediumData);
}

- (void)testThatItDoesNotSendFurtherRequestsForAnImageWhileItDownloads
{
    // given
    NSUUID *assetID = [NSUUID createUUID];
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
    conversation.remoteIdentifier = [NSUUID createUUID];
    NSDictionary *eventPayload = [self createAssetMediumEventPayloadForAssetID:assetID conversationID:conversation.remoteIdentifier];
    ZMUpdateEvent *event = [ZMUpdateEvent eventFromEventStreamPayload:eventPayload uuid:nil];
    
    [self.syncMOC performGroupedBlockAndWait:^{
        [self.sut processEvents:@[event] liveEvents:YES prefetchResult:nil];
        [self pushContextChangesIntoChangeTrackers];
        [self.syncMOC saveOrRollback];
        
    }];
    [conversation.messages.lastObject requestImageDownload];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // when
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMTransportRequest *firstRequest = [self.sut.requestGenerators nextRequest];
        XCTAssertNotNil(firstRequest);
    }];
    
    ZMTransportRequest *secondRequest = [self.sut.requestGenerators nextRequest];
    
    // then
    XCTAssertNil(secondRequest);
}

- (void)testThatANewImageMessageIsCreatedFromAPushEventOfTheRightType
{
    // given
    ZMUpdateEvent *event = [OCMockObject mockForClass:ZMUpdateEvent.class];
    (void)[(ZMUpdateEvent *)[[(id)event stub] andReturnValue:OCMOCK_VALUE(ZMUpdateEventConversationAssetAdd)] type];

    __block ZMImageMessage *imageMessage;
    [self.syncMOC performGroupedBlockAndWait:^{
        imageMessage = [ZMImageMessage insertNewObjectInManagedObjectContext:self.syncMOC];
    }];
    
    // expect
    ZMImageMessage *mockImageMessage = [OCMockObject mockForClass:ZMImageMessage.class];
    [[[(id)mockImageMessage expect] andReturn:imageMessage] createOrUpdateMessageFromUpdateEvent:event inManagedObjectContext:self.syncMOC prefetchResult:nil];
    
    // when
    XCTAssertNoThrow([self.sut processEvents:@[event] liveEvents:YES prefetchResult:nil]);
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    [(id)event stopMocking];
    [(id)mockImageMessage verify];
    [(id)mockImageMessage stopMocking];
}

- (void)testThatANewImageMessageIsCreatedFromADownloadedEventOfTheRightType
{
    // given
    ZMUpdateEvent *event = [OCMockObject mockForClass:ZMUpdateEvent.class];
    (void)[(ZMUpdateEvent *)[[(id)event stub] andReturnValue:OCMOCK_VALUE(ZMUpdateEventConversationAssetAdd)] type];
    
    __block ZMImageMessage *imageMessage;
    [self.syncMOC performGroupedBlockAndWait:^{
        imageMessage = [ZMImageMessage insertNewObjectInManagedObjectContext:self.syncMOC];
    }];
    
    // expect
    ZMImageMessage *mockImageMessage = [OCMockObject mockForClass:ZMImageMessage.class];
    [[[(id)mockImageMessage expect] andReturn:imageMessage] createOrUpdateMessageFromUpdateEvent:event inManagedObjectContext:self.syncMOC prefetchResult:nil];
    
    // when
    [self.sut processEvents:@[event] liveEvents:NO prefetchResult:nil];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    [(id)event stopMocking];
    [(id)mockImageMessage verify];
    [(id)mockImageMessage stopMocking];
}



- (void)testThatItDoesNotGeneratesARequestOnStartupWhenAnImageMessageDoesNotHaveAMediumImageButItIsNotWhitelisted
{
    // given
    __block ZMImageMessage *imageMessage;
    ZMConversation *conversation = [self insertGroupConversation];
    NSUUID *assetID = [NSUUID createUUID];
    NSDictionary *payload = [self createAssetMediumEventPayloadForAssetID:assetID conversationID:conversation.remoteIdentifier];
    ZMUpdateEvent *event = [ZMUpdateEvent eventFromEventStreamPayload:payload uuid:nil];
    
    NSUUID *correlationID = [[NSUUID alloc] initWithUUIDString: (event.payload[@"data"][@"info"][@"correlation_id"]) ];
    NSData *imageData = [@"image-data-0q39eijdkslfm" dataUsingEncoding:NSUTF8StringEncoding];
    
    [self.syncMOC performGroupedBlockAndWait:^{
        imageMessage = [ZMImageMessage insertNewObjectInManagedObjectContext:self.syncMOC];
        imageMessage.nonce = correlationID;
        imageMessage.previewData = imageData;
        imageMessage.mediumRemoteIdentifier = [NSUUID createUUID];
        imageMessage.visibleInConversation = conversation;
        [self.syncMOC saveOrRollback];

        [self.sut processEvents:@[event] liveEvents:YES prefetchResult:nil];
    }];
    
    // when
    [self resetSUT];

    ZMTransportRequest *request = [self.sut.requestGenerators nextRequest];
    
    // then
    XCTAssertNil(request);
}

- (void)testThatItReturnsNoncesForAssetMessageFromTheUpdateEventsForPrefetching
{
    // given
    NSMutableSet *expectedNonces = [NSMutableSet set];
    NSMutableArray *events = [NSMutableArray array];
    
    for (ZMUpdateEventType type = 1; type < ZMUpdateEvent_LAST; type++) {
        NSString *eventTypeString = [ZMUpdateEvent eventTypeStringForUpdateEventType:type];
        NSUUID *nonce = NSUUID.createUUID;
        NSDictionary *payload = @{
                                  @"conversation" : NSUUID.createUUID.transportString,
                                  @"id" : self.createEventID.transportString,
                                  @"time" : [NSDate dateWithTimeIntervalSince1970:1234000].transportString,
                                  @"from" : NSUUID.createUUID.transportString,
                                  @"type" : eventTypeString,
                                  @"data" : @{
                                          @"content":@"fooo",
                                          @"nonce" : nonce.transportString,
                                          }
                                  };
        
        ZMUpdateEvent *event = [ZMUpdateEvent eventFromEventStreamPayload:payload uuid:nil];
        [events addObject:event];
        
        if (type == ZMUpdateEventConversationAssetAdd) {
            [expectedNonces addObject:nonce];
        }
    }
    
    // when
    NSSet <NSUUID *>* actualNonces = [self.sut messageNoncesToPrefetchToProcessEvents:events];
    
    // then
    XCTAssertNotNil(expectedNonces);
    XCTAssertEqual(actualNonces.count, 1lu);
    XCTAssertEqualObjects(expectedNonces, actualNonces);
}

- (void)testThatItGeneratesARequestOnStartupWhenAnImageMessageDoesNotHaveAMediumImageAndItIsWhitelisted
{
    // given
    __block ZMImageMessage *imageMessage;
    ZMConversation *conversation = [self insertGroupConversation];
    NSUUID *assetID = [NSUUID createUUID];
    NSDictionary *payload = [self createAssetMediumEventPayloadForAssetID:assetID conversationID:conversation.remoteIdentifier];
    ZMUpdateEvent *event = [ZMUpdateEvent eventFromEventStreamPayload:payload uuid:nil];
    
    NSUUID *correlationID = [[NSUUID alloc] initWithUUIDString: (event.payload[@"data"][@"info"][@"correlation_id"]) ];
    NSData *imageData = [@"image-data-0q39eijdkslfm" dataUsingEncoding:NSUTF8StringEncoding];
    
    [self.syncMOC performGroupedBlockAndWait:^{
        imageMessage = [ZMImageMessage insertNewObjectInManagedObjectContext:self.syncMOC];
        imageMessage.nonce = correlationID;
        imageMessage.previewData = imageData;
        imageMessage.mediumRemoteIdentifier = [NSUUID createUUID];
        imageMessage.visibleInConversation = conversation;
        [self.syncMOC saveOrRollback];
        
        [self.sut processEvents:@[event] liveEvents:YES prefetchResult:nil];
    }];
    
    // when
    [self resetSUT];
    
    [imageMessage requestImageDownload];
    WaitForAllGroupsToBeEmpty(0.5);
    
    ZMTransportRequest *request = [self.sut.requestGenerators nextRequest];
    
    // then
    XCTAssertNotNil(request);
}


- (void)testThatItDoesNotGenerateAnyRequestIfAllMessagesHaveAMediumImage
{
    // given
    __block ZMImageMessage *imageMessage;
    ZMConversation *conversation = [self insertGroupConversation];
    NSUUID *assetID = [NSUUID createUUID];
    NSDictionary *payload = [self createAssetMediumEventPayloadForAssetID:assetID conversationID:conversation.remoteIdentifier];
    ZMUpdateEvent *event = [ZMUpdateEvent eventFromEventStreamPayload:payload uuid:nil];
    
    NSUUID *correlationID = [[NSUUID alloc] initWithUUIDString: (event.payload[@"data"][@"info"][@"correlation_id"]) ];
    NSData *imageData = [@"image-data-0q39eijdkslfm" dataUsingEncoding:NSUTF8StringEncoding];
    
    
    [self.syncMOC performGroupedBlockAndWait:^{
        imageMessage = [ZMImageMessage insertNewObjectInManagedObjectContext:self.syncMOC];
        imageMessage.mediumRemoteIdentifier = [NSUUID createUUID];
        imageMessage.mediumData = imageData;
        imageMessage.nonce = correlationID;
        imageMessage.visibleInConversation = conversation;
        [self.syncMOC saveOrRollback];
    }];
    
    [self.syncMOC performGroupedBlockAndWait:^{
        [self.sut processEvents:@[event] liveEvents:YES prefetchResult:nil];
        [self fetchOnlyExistingImageMessage];
    }];
    
    // when
    ZMTransportRequest *request = [self.sut.requestGenerators nextRequest];
    
    // then
    XCTAssertNil(request);
}


- (void)testThatItIgnoresPushEventsOfTheWrongType
{
    // given
    ZMImageMessage *mockImageMessage = [OCMockObject mockForClass:ZMImageMessage.class];
    
    // expect
    [[(id)mockImageMessage reject] createOrUpdateMessageFromUpdateEvent:OCMOCK_ANY inManagedObjectContext:self.syncMOC prefetchResult:nil];
    
    
    ZMUpdateEventType ignoredEvents[] = {
        ZMUpdateEventUnknown,
        
        ZMUpdateEventConversationMessageAdd,
        ZMUpdateEventConversationKnock,
        // ZMUpdateEventConversationAssetAdd,
        ZMUpdateEventConversationMemberJoin,
        ZMUpdateEventConversationMemberLeave,
        ZMUpdateEventConversationRename,
        ZMUpdateEventConversationMemberUpdate,
        ZMUpdateEventConversationVoiceChannelActivate,
        ZMUpdateEventConversationVoiceChannel,
        ZMUpdateEventConversationCreate,
        ZMUpdateEventConversationConnectRequest,
        ZMUpdateEventUserUpdate,
        ZMUpdateEventUserNew,
        ZMUpdateEventUserConnection
    };
    
    for (size_t i = 0; i < (sizeof(ignoredEvents) / sizeof(ZMUpdateEventType)); ++i) {
        ZMUpdateEvent *event = [OCMockObject mockForClass:ZMUpdateEvent.class];
        (void)[(ZMUpdateEvent *)[[(id)event stub] andReturnValue:OCMOCK_VALUE(ignoredEvents[i])] type];
        
        // when
        [self.sut processEvents:@[event] liveEvents:YES prefetchResult:nil];
    }
    
    // then
    [(id)mockImageMessage verify];
    [(id)mockImageMessage stopMocking];
}

@end



@implementation ZMAssetTranscoderTests (OutstandingItems)

- (void)testThatItHasNoOutstandingItems;
{
    XCTAssertFalse(self.sut.hasOutstandingItems);
}

- (void)testThatItHasOutstandingItemsWhenAnImageMessageNeedsToBeDownloaded;
{
    // given
    __block ZMConversation *conversation;
    __block ZMImageMessage *message;
    [self.syncMOC performGroupedBlockAndWait:^{
        conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        conversation.remoteIdentifier = [NSUUID createUUID];
        message = [ZMImageMessage insertNewObjectInManagedObjectContext:self.syncMOC];
        message.originalDataProcessed = YES;
        message.visibleInConversation = conversation;
        message.eventID = [self createEventID];
        message.originalSize = CGSizeMake(40, 50);
        message.mediumRemoteIdentifier = [NSUUID createUUID];
        XCTAssert([message.managedObjectContext saveOrRollback]);
    }];
    
    [message requestImageDownload];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // when
    [self.syncMOC performGroupedBlockAndWait:^{
        [self notifyChangeTrackersWithObject:message];
    }];
    
    // then
    XCTAssertTrue(self.sut.hasOutstandingItems);
}

@end


#pragma mark - Upload

@implementation ZMAssetTranscoderTests (ImageUpload)

- (NSDictionary *)sampleCreationDictionary
{
    return @{
             @"time":[NSDate dateWithTimeIntervalSince1970:23344444].transportString,
             @"id" : [self createEventID].transportString,
             };
}

- (void)testThatItStopsRequestingAnAssetIfWeWereUnableToDecodeIt;
{
    // given
    __block ZMImageMessage *imageMessage;
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        conversation.remoteIdentifier = [NSUUID createUUID];
        
        imageMessage = [ZMImageMessage insertNewObjectInManagedObjectContext:self.syncMOC];
        imageMessage.originalDataProcessed = YES;
        imageMessage.visibleInConversation = conversation;
        imageMessage.originalSize = CGSizeMake(1900, 1500);
        imageMessage.mediumRemoteIdentifier = [NSUUID createUUID];
        [self.syncMOC saveOrRollback];
        
        for (id<ZMContextChangeTracker> t in self.sut.contextChangeTrackers) {
            [t objectsDidChange:[NSSet setWithObject:imageMessage]];
        }
    }];
    [imageMessage requestImageDownload];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // when
    __block ZMTransportRequest *request;
    [self.syncMOC performGroupedBlockAndWait:^{
        request = [self.sut.requestGenerators nextRequest];
        XCTAssertNotNil(request);
        
        NSData *data = [@"asdfasdf" dataUsingEncoding:NSUTF8StringEncoding];
        NSHTTPURLResponse *r = [[NSHTTPURLResponse alloc] initWithURL:[NSURL URLWithString:@"http://example.com/"] statusCode:200 HTTPVersion:@"HTTP/1.1" headerFields:@{@"Content-Type": @"jkadskj/adsdfsaa", @"Content-Length": @"8"}];
        ZMTransportResponse *response = [[ZMTransportResponse alloc] initWithHTTPURLResponse:r data:data error:nil];
        [request completeWithResponse:response];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    [self.syncMOC performGroupedBlockAndWait:^{
        for (id<ZMContextChangeTracker> t in self.sut.contextChangeTrackers) {
            [t objectsDidChange:[NSSet setWithObject:imageMessage]];
        }
    }];
    
    // then
    [self.syncMOC performGroupedBlockAndWait:^{
        XCTAssertNil([self.sut.requestGenerators nextRequest]);
        XCTAssertNotNil(imageMessage.mediumData);
        XCTAssertEqual(imageMessage.mediumData.length, 0u);
    }];
}

@end

