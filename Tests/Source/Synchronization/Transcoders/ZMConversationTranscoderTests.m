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
@import OCMock;
@import WireSyncEngine;
@import WireDataModel;

#import "ObjectTranscoderTests.h"
#import "ZMConversationTranscoder.h"
#import "ZMConversationTranscoder+Internal.h"
#import "ZMSimpleListRequestPaginator.h"
#import "WireSyncEngine_iOS_Tests-Swift.h"


static NSString *const CONVERSATIONS_PATH = @"/conversations";
static NSString *const CONVERSATION_ID_REQUEST_PREFIX = @"/conversations?ids=";


@interface ZMConversationTranscoderTests : ObjectTranscoderTests

- (ZMUpdateEvent *)conversationCreateEventForConversationID:(NSUUID *)conversationID selfID:(NSUUID *)selfID otherUserID:(NSUUID *)otherUserID;
- (ZMConversation *)setupConversation;
- (ZMTransportRequest *)requestToSyncConversation:(ZMConversation *)conversation andCompleteWithResponse:(ZMTransportResponse*)response;

@property (nonatomic) NSMutableArray *downloadedEvents;
@property (nonatomic) ZMConversationTranscoder<ZMUpstreamTranscoder, ZMDownstreamTranscoder> *sut;
@property (nonatomic) NSUUID *selfUserID;
@property (nonatomic) MockSyncStatus *mockSyncStatus;
@property (nonatomic) ZMMockClientRegistrationStatus *mockClientRegistrationDelegate;
@property (nonatomic) id syncStateDelegate;

@end



@implementation ZMConversationTranscoderTests

- (void)setUp
{
    [super setUp];
    self.selfUserID = NSUUID.createUUID;
    [self setupSelfConversation]; // when updating lastRead we are posting to the selfConversation

    [[[(id)self.syncStrategy stub] andReturn:self.syncMOC] moc];
    [self verifyMockLater:self.syncStrategy];
    
    NSMutableArray *downloadedEvents = [NSMutableArray array];
    ZMSyncStrategy* syncStrategyMock = [(id)self.syncStrategy stub];
    [syncStrategyMock processDownloadedEvents:[OCMArg checkWithBlock:^BOOL(NSArray* events) {
        [downloadedEvents addObjectsFromArray:events];
        return YES;
    }]];
    
    id authStatusMock = [OCMockObject niceMockForClass:[ZMAuthenticationStatus class]];
    [[[authStatusMock stub] andReturnValue:@YES] registeredOnThisDevice];
    
    self.downloadedEvents = downloadedEvents;
    self.syncStateDelegate = [OCMockObject niceMockForProtocol:@protocol(ZMSyncStateDelegate)];
    self.mockSyncStatus = [[MockSyncStatus alloc] initWithManagedObjectContext:self.syncMOC syncStateDelegate:self.syncStateDelegate];
    self.mockSyncStatus.mockPhase = SyncPhaseDone;
    self.mockApplicationStatus.mockSynchronizationState = ZMSynchronizationStateEventProcessing;

    self.sut = (id) [[ZMConversationTranscoder alloc] initWithSyncStrategy:self.syncStrategy applicationStatus:self.mockApplicationStatus syncStatus:self.mockSyncStatus];
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)setSut:(ZMConversationTranscoder<ZMUpstreamTranscoder,ZMDownstreamTranscoder> *)sut
{
    _sut = sut;
}

- (void)tearDown
{
    WaitForAllGroupsToBeEmpty(0.5);
    [self.mockClientRegistrationDelegate tearDown];
    self.sut = nil;
    [super tearDown];
}

- (void)setupSelfConversation
{
    ZMUser *selfUser = [ZMUser selfUserInContext:self.uiMOC];
    selfUser.remoteIdentifier = self.selfUserID;
    ZMConversation *selfConversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    selfConversation.remoteIdentifier = self.selfUserID;
    selfConversation.conversationType = ZMConversationTypeSelf;
    [self.uiMOC saveOrRollback];
}

- (ZMConversation *)setupConversation
{
    ZMConversation * conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    conversation.remoteIdentifier = [NSUUID createUUID];
    conversation.conversationType = ZMConversationTypeGroup;
    
    ZMMessage *msg = [ZMTextMessage insertNewObjectInManagedObjectContext:self.uiMOC];
    msg.serverTimestamp = [NSDate date];
    [conversation.mutableMessages addObject:msg];
    conversation.lastServerTimeStamp = [msg.serverTimestamp dateByAddingTimeInterval:5];

    [self.uiMOC saveOrRollback];
    return conversation;
}

- (ZMTransportRequest *)requestToSyncConversation:(ZMConversation *)conversation andCompleteWithResponse:(ZMTransportResponse*)response
{
    __block ZMTransportRequest *request;
    [self.syncMOC performBlockAndWait:^{
        ZMConversation *syncConv = (id)[self.syncMOC objectWithID:conversation.objectID];
        
        for (id<ZMContextChangeTracker> tracker in self.sut.contextChangeTrackers) {
            [tracker objectsDidChange:[NSSet setWithObject:syncConv]];
        }
        
        request = [self.sut nextRequest];
        XCTAssertNotNil(request);
        
        // when
        [request completeWithResponse:response];
        [self.syncMOC saveOrRollback];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    return request;
}

- (BOOL)isConversation:(ZMConversation *)conversation matchingPayload:(NSDictionary *)payload
{
    const BOOL sameRemoteIdentifier = [NSObject isEqualOrBothNil:conversation.remoteIdentifier toObject:[payload uuidForKey:@"id"]];
    const BOOL sameModifiedDate = [NSObject isEqualOrBothNil:conversation.lastModifiedDate toObject:[payload dateForKey:@"last_event_time"]];
    const BOOL sameCreator = [NSObject isEqualOrBothNil:conversation.creator.remoteIdentifier toObject:[payload uuidForKey:@"creator"]];
    const BOOL sameName = [NSObject isEqualOrBothNil:conversation.userDefinedName toObject:[payload optionalStringForKey:@"name"]];
    const BOOL sameType = conversation.conversationType == [self.class typeFromNumber:payload[@"type"]];

    NSMutableSet* activeParticipants = [NSMutableSet set];
    NSMutableSet* inactiveParticipants = [NSMutableSet set];
    for(NSDictionary *user in [[payload dictionaryForKey:@"members"] arrayForKey:@"others"]) {
        
        if([[user numberForKey:@"status"] intValue] == 0) {
            [activeParticipants addObject:[user uuidForKey:@"id"]];
        }
        else {
            [inactiveParticipants addObject:[user uuidForKey:@"id"]];
        }
    }
    
    BOOL sameActiveUsers = activeParticipants.count == conversation.otherActiveParticipants.count;
    for(ZMUser *user in conversation.otherActiveParticipants) {
        sameActiveUsers = sameActiveUsers && [activeParticipants containsObject:user.remoteIdentifier];
    }
    
    return (sameRemoteIdentifier
            && sameModifiedDate
            && sameCreator
            && sameName
            && sameType
            && sameActiveUsers);
}


- (NSDictionary *)conversationMetaDataForConversation:(NSUUID *)conversationID selfID:(NSUUID *)selfID otherUserID:(NSUUID *)otherUserID isArchived:(BOOL)isArchived isSelfAnActiveMember:(BOOL)isSelfAnActiveMember
{
    return @{
             @"creator": selfID.transportString,
             @"id": conversationID.transportString,
             @"last_event_time": @"2014-06-30T09:09:14.738Z",
             @"members" : @{
                     @"others" : @[
                             @{
                                 @"id": otherUserID.transportString,
                                 @"status": @0
                                 },
                             ],
                     @"self" : @{
                             @"otr_archived" : @(isArchived),
                             @"otr_archived_ref" : (isArchived ? @"2014-06-30T09:09:14.738Z" : [NSNull null]),
                             @"id": selfID.transportString,
                             @"muted" : [NSNull null],
                             @"muted_time" : [NSNull null],
                             @"status": [NSNumber numberWithBool:!isSelfAnActiveMember],
                             @"status_ref": @"0.0",
                             @"status_time": @"2013-06-30T09:09:14.738Z"
                             }
                     },
             @"name" : [NSNull null],
             @"type": @3,
             };
}

- (ZMUpdateEvent *)conversationCreateEventForConversationID:(NSUUID *)conversationID selfID:(NSUUID *)selfID otherUserID:(NSUUID *)otherUserID isArchived:(BOOL)isArchived
{
    NSDictionary *payload = @{@"conversation": conversationID.transportString,
                              @"data" : [self conversationMetaDataForConversation:conversationID selfID:selfID otherUserID:otherUserID isArchived:isArchived isSelfAnActiveMember: NO],
                              @"from": selfID.transportString,
                              @"time": @"2013-06-30T09:09:14.752Z",
                              @"type": @"conversation.create"
                              };
    ZMUpdateEvent *event = [ZMUpdateEvent eventFromEventStreamPayload:payload uuid:nil];
    return event;
}

- (ZMUpdateEvent *)conversationCreateEventForConversationID:(NSUUID *)conversationID selfID:(NSUUID *)selfID otherUserID:(NSUUID *)otherUserID
{
    return  [self conversationCreateEventForConversationID:conversationID selfID:selfID otherUserID:otherUserID isArchived:NO];
}


+ (ZMConversationType) typeFromNumber:(NSNumber *)number {
    const static int ZMConvTypeGroup = 0;
    const static int ZMConvOneToOne = 2;
    
    if([number intValue] == ZMConvTypeGroup) {
        return ZMConversationTypeGroup;
    }
    if([number intValue] == ZMConvOneToOne) {
        return ZMConversationTypeOneOnOne;
    }
    return ZMConversationTypeSelf;
}

- (NSMutableDictionary *)responsePayloadForUserEventInConversationID:(NSUUID *)conversationID userIDs:(NSArray *)userIDs eventType:(NSString *)eventType;
{
    return [self responsePayloadForUserEventInConversationID:conversationID lastTimeStamp:[NSDate date] userIDs:userIDs eventType:eventType];
}

- (NSMutableDictionary *)responsePayloadForUserEventInConversationID:(NSUUID *)conversationID
                                                       lastTimeStamp:(NSDate *)lastServerTimeStamp
                                                             userIDs:(NSArray *)userIDs
                                                           eventType:(NSString *)eventType;
{
    NSArray *userIDStrings = [userIDs mapWithBlock:^id(NSUUID *userID) {
        Require([userID isKindOfClass:[NSUUID class]]);
        return userID.transportString;
    }];
    return [@{@"conversation": conversationID.transportString,
              @"data": @{@"user_ids": userIDStrings},
              @"from": self.selfUserID.transportString,
              @"time": [lastServerTimeStamp dateByAddingTimeInterval:5].transportString,
              @"type": eventType} mutableCopy];
}


- (NSMutableDictionary *)responsePayloadForRenameOfConversationID:(NSUUID *)conversationID name:(NSString *)name;
{
    return [@{@"conversation": conversationID.transportString,
              @"data": @{@"name": name},
              @"from": self.selfUserID.transportString,
              @"time": [NSDate date].transportString,
              @"type": @"conversation.rename"} mutableCopy];
}

- (void)testThatItProcessesListPaginatorRequestsBeforeRemoteIDRequestsDuringSlowSync
{
    // given
    self.mockSyncStatus.mockPhase = SyncPhaseFetchingConversations;
    
    // when
    NSArray *generators = self.sut.requestGenerators;
    
    // then
    XCTAssertEqual(generators.count, 2u);
    XCTAssertTrue([generators.firstObject isKindOfClass:ZMSimpleListRequestPaginator.class]);
    XCTAssertTrue([generators.lastObject isKindOfClass:ZMRemoteIdentifierObjectSync.class]);
}

- (void)testThatItProcessesDownstreamRequestsBeforeUpstreamWhenSlowSyncIsDone
{
    // given
    self.mockSyncStatus.mockPhase = SyncPhaseDone;
    
    // when
    NSArray *generators = self.sut.requestGenerators;
    
    // then
    XCTAssertEqual(generators.count, 3u);
    XCTAssertTrue([generators.firstObject isKindOfClass:ZMDownstreamObjectSync.class]);
    XCTAssertTrue([generators[1] isKindOfClass:ZMUpstreamInsertedObjectSync.class]);
    XCTAssertTrue([generators.lastObject isKindOfClass:ZMUpstreamModifiedObjectSync.class]);
}

- (void)testThatItReturnsTheContextChangeTrackers;
{
    // when
    NSArray *trackers = self.sut.contextChangeTrackers;
    
    // then
    XCTAssertEqual(trackers.count, 3u);
    NSArray *classes = [trackers mapWithBlock:^id(id<NSObject> obj) {
        return obj.class;
    }];
    NSArray *expected = @[ZMDownstreamObjectSync.class, ZMUpstreamInsertedObjectSync.class, ZMUpstreamModifiedObjectSync.class];
    XCTAssertEqualObjects(classes, expected);
}

- (void)testThatItDoesNotGenerateARequestIfSlowSyncIsDone {
    
    [self.syncMOC performGroupedBlockAndWait:^{
        
        // given
        // hard sync is done
        for (id<ZMContextChangeTracker> tracker in self.sut.contextChangeTrackers) {
            [tracker objectsDidChange:[NSSet set]];
        }
        
        // when
        ZMTransportRequest *request = [self.sut nextRequest];
        
        // then
        XCTAssertNil(request);
    }];
}

- (void)testThatItDownloadsConversationsThatNeedToBeSynchronizedFromTheBackendWithBlock:(void(^)(ZMConversation *conversation))block;
{
    // given
    __block NSUUID *remoteID;
    __block ZMConversation *conversation;
    [self.syncMOC performGroupedBlockAndWait:^{
        conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        conversation.conversationType = ZMConversationTypeOneOnOne;
        conversation.remoteIdentifier = [NSUUID createUUID];
        remoteID = conversation.remoteIdentifier;
        conversation.needsToBeUpdatedFromBackend = YES;
        XCTAssert([self.syncMOC saveOrRollback]);
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // when
    __block ZMTransportRequest *request;
    [self.syncMOC performGroupedBlockAndWait:^{
        block(conversation);
        request = [self.sut nextRequest];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertNotNil(request);
    NSString *path = [NSString pathWithComponents:@[@"/conversations", remoteID.transportString]];
    XCTAssertEqualObjects(request.path, path);
    XCTAssertEqual(request.method, ZMMethodGET);
}

- (void)testThatItDownloadsConversationsThatNeedToBeSynchronizedFromTheBackend_OnInitialization;
{
    [self testThatItDownloadsConversationsThatNeedToBeSynchronizedFromTheBackendWithBlock:^(ZMConversation *conversation) {
        NOT_USED(conversation);
        [ZMChangeTrackerBootstrap bootStrapChangeTrackers:self.sut.contextChangeTrackers onContext:self.syncMOC];
    }];
}

- (void)testThatItDownloadsConversationsThatNeedToBeSynchronizedFromTheBackend_OnObjectsDidChange;
{
    [self testThatItDownloadsConversationsThatNeedToBeSynchronizedFromTheBackendWithBlock:^(ZMConversation *conversation) {
        [self.sut.contextChangeTrackers[0] objectsDidChange:[NSSet setWithObject:conversation]];
    }];
}

- (void)checkThatItDowloadsConversationWithConnectionOfTipe:(ZMConnectionStatus)status shouldDownload:(BOOL)shouldDownload failureRecorder:(ZMTFailureRecorder *)recorder
{
    // given
    __block NSUUID *remoteID;
    __block ZMConversation *conversation;
    [self.syncMOC performGroupedBlockAndWait:^{
        conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        conversation.conversationType = ZMConversationTypeOneOnOne;
        conversation.remoteIdentifier = [NSUUID createUUID];
        remoteID = conversation.remoteIdentifier;
        conversation.needsToBeUpdatedFromBackend = YES;
        
        ZMConnection *connection = [ZMConnection insertNewObjectInManagedObjectContext:self.syncMOC];
        connection.status = status;
        connection.conversation = conversation;
        
        XCTAssert([self.syncMOC saveOrRollback]);
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // when
    [ZMChangeTrackerBootstrap bootStrapChangeTrackers:self.sut.contextChangeTrackers onContext:self.syncMOC];

    __block ZMTransportRequest *request;
    [self.syncMOC performGroupedBlockAndWait:^{
        request = [self.sut nextRequest];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    FHAssertEqual(recorder, request != nil, shouldDownload);
    
}

- (void)testThatItDoesNotDownloadConversationsThatHaveAPendingConnection;
{
    [self checkThatItDowloadsConversationWithConnectionOfTipe:ZMConnectionStatusPending shouldDownload:NO failureRecorder:NewFailureRecorder()];
}

- (void)testThatItDoesNotDownloadConversationsThatHaveAnIgnoredConnection;
{
    [self checkThatItDowloadsConversationWithConnectionOfTipe:ZMConnectionStatusIgnored shouldDownload:NO failureRecorder:NewFailureRecorder()];
}

- (void)testThatItDownloadsAConversationsThatHaveAnAcceptedConnection;
{
    [self checkThatItDowloadsConversationWithConnectionOfTipe:ZMConnectionStatusAccepted shouldDownload:YES failureRecorder:NewFailureRecorder()];
}

- (void)testThatItDownloadsAConversationsThatHaveABlockedConnection;
{
    [self checkThatItDowloadsConversationWithConnectionOfTipe:ZMConnectionStatusBlocked shouldDownload:YES failureRecorder:NewFailureRecorder()];
}

- (void)testThatItDownloadsAConversationsThatHaveAnInvalidConnection;
{
    [self checkThatItDowloadsConversationWithConnectionOfTipe:ZMConnectionStatusInvalid shouldDownload:YES failureRecorder:NewFailureRecorder()];
}

- (void)testThatItDownloadsAConversationsThatHaveASentConnection;
{
    [self checkThatItDowloadsConversationWithConnectionOfTipe:ZMConnectionStatusSent shouldDownload:YES failureRecorder:NewFailureRecorder()];
}

- (void)testThatItUpdatesAConversationFromDownstreamPayload;
{
    // given
    NSUUID *remoteID = [NSUUID createUUID];
    NSDate *lastEventDate = [NSDate dateWithTimeIntervalSinceReferenceDate:417000000];
    NSDictionary *payload = @{@"creator": @"08316f5e-3c0a-4847-a235-2b4d93f291a4",
                              @"members": @{
                                      @"self": @{
                                              @"status": @0,
                                              @"muted_time": [NSNull null],
                                              @"muted": [NSNull null],
                                              @"status_time": @"2014-07-02T14:52:45.211Z",
                                              @"status_ref": @"0.0",
                                              @"id": @"08316f5e-3c0a-4847-a235-2b4d93f291a4",
                                              @"archived": [NSNull null]
                                              },
                                      @"others": @[]
                                      },
                              @"name": @"Jonathan",
                              @"id": remoteID.transportString,
                              @"type": @3,
                              @"last_event_time": lastEventDate.transportString};
    ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:payload HTTPStatus:200 transportSessionError:nil];
    
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        conversation.conversationType = ZMConversationTypeOneOnOne;
        conversation.remoteIdentifier = remoteID;
        conversation.needsToBeUpdatedFromBackend = YES;
        XCTAssert([self.syncMOC saveOrRollback]);
        
        // when
        
        id<ZMDownstreamTranscoder> t = (id) self.sut;
        [t updateObject:conversation withResponse:response downstreamSync:nil];
        
        // then
        XCTAssertEqual(conversation.conversationType, ZMConversationTypeConnection);
        XCTAssertEqualWithAccuracy(conversation.lastModifiedDate.timeIntervalSinceReferenceDate, lastEventDate.timeIntervalSinceReferenceDate, 0.1);
    }];
}



-(void)testThatItDoesNotFetchEventsForConversationWithoutRemoteIdentifier
{
    // given
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMUser *user1 = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        user1.remoteIdentifier = [NSUUID createUUID];
        
        ZMUser *user2 = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        user2.remoteIdentifier = [NSUUID createUUID];
        
        [ZMConversation insertGroupConversationIntoManagedObjectContext:self.syncMOC
                                                       withParticipants:@[user1, user2]];
        
        // when
        ZMTransportRequest *request;
        do {
            request = [self.sut nextRequest];
            if (request == nil) {
                break;
            }
            XCTAssertEqual([request.path rangeOfString:@"events"].location, (NSUInteger) NSNotFound);
        } while (YES);
    }];
}

- (void)testThatItReturnsTheConversationRemoteIdentifiersToPrefetchFromUpdateEvents;
{
    // given
    NSUUID *firstRemoteID = NSUUID.createUUID;
    NSUUID *secondRemoteID = NSUUID.createUUID;
    
    id <ZMTransportData> firstPayload = @{
                              @"conversation" : firstRemoteID,
                              @"data" : @{
                                      @"last_read" : @"3.800122000a5efe70"
                                      },
                              @"from": NSUUID.createUUID,
                              @"time" : NSDate.date.transportString,
                              @"type" : @"conversation.member-update"
                              };
    
    id <ZMTransportData> secondPayload = @{
                              @"conversation" : secondRemoteID,
                              @"data" : @{
                                      @"content" : @"www.wire.com",
                                      @"nonce" : NSUUID.createUUID,
                                      },
                              @"from": NSUUID.createUUID,
                              @"id" : @"6c9d.800122000a5911ba",
                              @"time" : NSDate.date.transportString,
                              @"type" : @"conversation.message-add"
                              };
    
    NSArray <ZMUpdateEvent *> *events = @[
                                          [ZMUpdateEvent eventFromEventStreamPayload:firstPayload uuid:nil],
                                          [ZMUpdateEvent eventFromEventStreamPayload:secondPayload uuid:nil]
                                          ];

    // when
    NSSet <NSUUID *>*identifiers = [self.sut conversationRemoteIdentifiersToPrefetchToProcessEvents:events];

    // then
    NSSet *expected = @[firstRemoteID, secondRemoteID].set;
    XCTAssertEqualObjects(identifiers, expected);
}

- (void)testThatNoRequestIsGeneratedForAConversationWithoutRemoteIdentifierEvenAfterTheyAreInserted
{
    // given
    __block NSUUID *remoteID;
    __block ZMConversation *conversation;
    [self.syncMOC performGroupedBlockAndWait:^{
        conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        conversation.conversationType = ZMConversationTypeOneOnOne;
        conversation.remoteIdentifier = [NSUUID createUUID];
        remoteID = conversation.remoteIdentifier;
        conversation.needsToBeUpdatedFromBackend = YES;
        XCTAssert([self.syncMOC saveOrRollback]);
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // when
    __block ZMTransportRequest *request;
    [self.syncMOC performGroupedBlockAndWait:^{
        conversation.remoteIdentifier = nil;
        request = [self.sut nextRequest];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertNil(request);
}



- (void)testThatItDoesNotCreateTheSelfConversationWhenReceivingAssetOrMessageEvents;
{
    // given
    NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:ZMConversation.entityName];
    
    [self.syncMOC performGroupedBlockAndWait:^{
        NSUUID * const selfUserIdentifier = [NSUUID createUUID];
        [ZMUser selfUserInContext:self.syncMOC].remoteIdentifier = selfUserIdentifier;
        
        for(NSString* type in @[@"conversation.message-add", @"conversation.asset-add"]) {
            NSMutableDictionary *payload = [self responsePayloadForUserEventInConversationID:selfUserIdentifier userIDs:@[] eventType:type];
            ZMUpdateEvent *event = [ZMUpdateEvent eventFromEventStreamPayload:payload uuid:nil];
            
            // when
            NSUInteger const originalCount = [self.syncMOC countForFetchRequest:request error:nil];
            [self.sut processEvents:@[event] liveEvents:YES prefetchResult:nil];
            [self.syncMOC saveOrRollback];
            
            // then
            NSUInteger const count = [self.syncMOC countForFetchRequest:request error:nil];
            XCTAssertEqual(count, originalCount);
        }
    }];
}

- (ZMConversation *)createModifiedSyncMocConversationAndAddToTrackedObjectsWithID:(NSUUID *)conversationID name:(NSString *)name
{
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
    conversation.remoteIdentifier = conversationID; // Otherwise we'll try to insert it
    conversation.conversationType = ZMConversationTypeGroup; // We only don't update 'invalid' type
    conversation.userDefinedName = name;
    [conversation setLocallyModifiedKeys:[NSSet setWithObject:ZMConversationUserDefinedNameKey]];
    [self.syncMOC saveOrRollback];
    
    for (id<ZMContextChangeTracker> tracker in self.sut.contextChangeTrackers) {
        [tracker objectsDidChange:[NSSet setWithObject:conversation]];
    }
    return conversation;
}

- (void)testThatItCreatesARequestForUpdatingTheConversationName
{
    // given
    NSString *name = @"My Conversation Name";
    NSUUID *conversationID = NSUUID.createUUID;
    NSDictionary *responsePayload = [self responsePayloadForRenameOfConversationID:conversationID name:@"foo"];
    
    __block ZMConversation *conversation;
    
    [self.syncMOC performGroupedBlockAndWait:^{
        
        conversation = [self createModifiedSyncMocConversationAndAddToTrackedObjectsWithID:conversationID name:name];
        
        // when
        ZMTransportRequest *request = [self.sut nextRequest];
        XCTAssertNotNil(request);
        
        // then
        NSString *expectedString = [NSString stringWithFormat:@"/conversations/%@", conversationID.transportString];
        XCTAssertEqualObjects(request.path, expectedString);
        XCTAssertEqual(request.method, ZMMethodPUT);
        XCTAssertEqualObjects(request.payload, @{@"name":name});
        XCTAssertNotNil(request.expirationDate);
        
        // and when
        ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:responsePayload HTTPStatus:200 transportSessionError:nil];
        [request completeWithResponse:response];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    [self.syncMOC performGroupedBlockAndWait:^{
        // then
        XCTAssertFalse([conversation.keysThatHaveLocalModifications containsObject:ZMConversationUserDefinedNameKey]);
        
        XCTAssertEqual(self.downloadedEvents.count, 1u);
        ZMUpdateEvent *downloadedEvent = self.downloadedEvents.firstObject;
        XCTAssertEqualObjects(downloadedEvent.payload, responsePayload);
    }];
}

- (void)testThatItSetsTheLastReadToTheConversationNameChangeResponse;
{
    // given
    NSString *name = @"My Conversation Name";
    NSUUID *conversationID = [NSUUID createUUID];
    
    NSDate *oldEventTime = [NSDate date];
    NSDate *newEventTime = [oldEventTime dateByAddingTimeInterval:20];

    __block ZMConversation *conversation;
    
    [self.syncMOC performGroupedBlockAndWait:^{
        conversation = [self createModifiedSyncMocConversationAndAddToTrackedObjectsWithID:conversationID name:name];
        conversation.lastReadServerTimeStamp = oldEventTime;
        
        ZMTransportRequest *request = [[self.sut requestGenerators] nextRequest];
        XCTAssertNotNil(request);
        
        // when
        NSMutableDictionary *responsePayload = [self responsePayloadForRenameOfConversationID:conversation.remoteIdentifier name:@"foo"];
        responsePayload[@"time"] = newEventTime.transportString;
        
        ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:responsePayload HTTPStatus:200 transportSessionError:nil];
        [request completeWithResponse:response];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    [self.syncMOC performGroupedBlockAndWait:^{
        // then
        XCTAssertEqualWithAccuracy([conversation.lastReadServerTimeStamp timeIntervalSince1970], [newEventTime timeIntervalSince1970], 0.1);
    }];
}

- (void)testThatItDoesNotSetTheLastReadToTheConversationNameChangeResponseIfItIsOlder;
{
    // given
    NSString *name = @"My Conversation Name";
    NSUUID *conversationID = [NSUUID createUUID];
    
    NSDate *oldEventTime = [[NSDate date] dateByAddingTimeInterval:-30];
    NSDate *newEventTime = [NSDate date];
    
    __block ZMConversation *conversation;
    
    [self.syncMOC performGroupedBlockAndWait:^{
        conversation = [self createModifiedSyncMocConversationAndAddToTrackedObjectsWithID:conversationID name:name];
        conversation.lastReadServerTimeStamp = newEventTime;
        
        ZMTransportRequest *request = [[self.sut requestGenerators] nextRequest];
        XCTAssertNotNil(request);
        
        // when
        NSMutableDictionary *responsePayload = [self responsePayloadForRenameOfConversationID:conversation.remoteIdentifier name:@"foo"];
        responsePayload[@"time"] = oldEventTime.transportString;
        
        ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:responsePayload HTTPStatus:200 transportSessionError:nil];
        [request completeWithResponse:response];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    [self.syncMOC performGroupedBlockAndWait:^{
        // then
        XCTAssertEqualObjects(conversation.lastReadServerTimeStamp, newEventTime);
    }];
}

- (void)testThatItDoesNotCreateARequestIfThereIsNoUpdatedField
{
    // given
    NSString *name = @"My Conversation Name";
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        conversation.remoteIdentifier = [NSUUID createUUID]; // Otherwise we'll try to insert it
        conversation.userDefinedName = name;
        [conversation setLocallyModifiedKeys:[NSSet set]];
        [self.syncMOC saveOrRollback];
        
        for (id<ZMContextChangeTracker> tracker in self.sut.contextChangeTrackers) {
            [tracker objectsDidChange:[NSSet setWithObject:conversation]];
        }
        
        ZMTransportRequest *request = [self.sut nextRequest];
        XCTAssertNil(request);
    }];
}



- (void)testThatItRevertsToTheOriginalNameWhenARequestForChangingItTimesOut
{
    
    // given
    NSString *oldName = @"Old conversation name";
    
    NSUUID *conversationID = [NSUUID createUUID];
    
    __block ZMConversation *conversation;
    
    [self.syncMOC performGroupedBlockAndWait:^{
        conversation = [self createModifiedSyncMocConversationAndAddToTrackedObjectsWithID:conversationID name:oldName];
        
        ZMUpstreamRequest *request = [self.sut requestForUpdatingObject:conversation forKeys:[NSSet setWithObject:@"userDefinedName"]];
        XCTAssertNotNil(request);
        
        // when
        [self.sut requestExpiredForObject:conversation forKeys:request.keys];
        
        
        // then
        XCTAssertTrue(conversation.needsToBeUpdatedFromBackend);
        XCTAssertFalse([conversation.keysThatHaveLocalModifications containsObject:@"userDefinedName"]);
        
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
}


- (void)testThatItRevertsChangedActiveParticipantsWhenARequestTimesOut
{
    
    [self.syncMOC performGroupedBlockAndWait:^{
        
        ZMConversation *conversation;
        ZMUser *user1;
        ZMUser *user2;
        ZMUser *selfUser;
        [self createConversation:&conversation withUser1:&user1 user2:&user2 selfUser:&selfUser];
        
        
        ZMUser *newUser = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        newUser.remoteIdentifier = [NSUUID createUUID];
        
        
        XCTAssertEqual(conversation.activeParticipants.count, 3u);
        
        [conversation addParticipant:newUser];
        
        // when
        ZMUpstreamRequest *request = [self.sut requestForUpdatingObject:conversation forKeys:[NSSet setWithObject:@"unsyncedActiveParticipants"]];
        XCTAssertNotNil(request);
        [self.sut requestExpiredForObject:conversation forKeys:request.keys];
        
        // then
        XCTAssertTrue(conversation.needsToBeUpdatedFromBackend);
        XCTAssertFalse([conversation.keysThatHaveLocalModifications containsObject:@"unsyncedActiveParticipants"]);
        
        XCTAssertEqual(conversation.unsyncedActiveParticipants.count, 0u);
        
        [self checkConversation:conversation
        forExpectedParticipants:@[selfUser, user1, user2]
         unexpectedParticipants:@[newUser]
                failureRecorder:NewFailureRecorder()];
        
        
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
}




- (void)testThatItRevertsChangedInactiveParticipantsWhenARequestTimesOut
{
    
    [self.syncMOC performGroupedBlockAndWait:^{
        
        // given
        ZMConversation *conversation;
        ZMUser *user1;
        ZMUser *user2;
        ZMUser *selfUser;
        [self createConversation:&conversation withUser1:&user1 user2:&user2 selfUser:&selfUser];
        
        
        ZMUser *newUser = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        newUser.remoteIdentifier = [NSUUID createUUID];
        
        
        [conversation addParticipant:newUser];
        [conversation synchronizeAddedUser:newUser];
        
        XCTAssertEqual(conversation.activeParticipants.count, 4u);
        
        [conversation removeParticipant:newUser];
        
        // when
        ZMUpstreamRequest *request = [self.sut requestForUpdatingObject:conversation forKeys:[NSSet setWithObject:@"unsyncedInactiveParticipants"]];
        XCTAssertNotNil(request);
        [self.sut requestExpiredForObject:conversation forKeys:request.keys];
        
        // then
        XCTAssertTrue(conversation.needsToBeUpdatedFromBackend);
        XCTAssertFalse([conversation.keysThatHaveLocalModifications containsObject:@"unsyncedInactiveParticipants"]);
        
        XCTAssertEqual(conversation.unsyncedInactiveParticipants.count, 0u);
        
        
        [self checkConversation:conversation
        forExpectedParticipants:@[selfUser, user1, user2, newUser]
         unexpectedParticipants:@[]
                failureRecorder:NewFailureRecorder()];
        
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
}


- (void)createConversation:(ZMConversation **)conversationPointer
                 withUser1:(ZMUser **)user1Pointer
                     user2:(ZMUser **)user2Pointer
                  selfUser:(ZMUser **)selfUserPointer {
    // given
    ZMUser *selfUser = [ZMUser selfUserInContext:self.syncMOC];
    selfUser.remoteIdentifier = [NSUUID createUUID];
    
    ZMUser *user1 = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
    user1.remoteIdentifier = [NSUUID createUUID];
    
    ZMUser *user2 = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
    user2.remoteIdentifier = [NSUUID createUUID];
    
    ZMConversation *conversation = [ZMConversation insertGroupConversationIntoManagedObjectContext:self.syncMOC
                                                                                  withParticipants:@[user1, user2]];
    conversation.remoteIdentifier = [NSUUID createUUID];
    
    
    [conversation synchronizeAddedUser:selfUser];
    [conversation synchronizeAddedUser:user1];
    [conversation synchronizeAddedUser:user2];
    
    
    *conversationPointer = conversation;
    *user1Pointer = user1;
    *user2Pointer = user2;
    *selfUserPointer = selfUser;
}

- (void)checkConversation:(ZMConversation *)conversation
  forExpectedParticipants:(NSArray *)expectedParticipants
   unexpectedParticipants:(NSArray *)unexpectedParticipants
          failureRecorder:(ZMTFailureRecorder *)failureRecorder
{
    
    for (ZMUser *expectedUser in expectedParticipants) {
        FHAssertTrue(failureRecorder, [conversation.activeParticipants containsObject:expectedUser]);
    }
    for (ZMUser *unexpectedUser in unexpectedParticipants) {
        FHAssertTrue(failureRecorder, ![conversation.activeParticipants containsObject:unexpectedUser]);
    }
    XCTAssertEqual(conversation.activeParticipants.count, expectedParticipants.count);
}


@end



@implementation ZMConversationTranscoderTests (SingleRequestSync)


- (NSDictionary *)createConversationDataWithRemoteIDString:(NSString *)remoteIDString
{
    return @{
             @"last_event_time" : @"2014-04-30T16:30:16.625Z",
             @"name" : [NSNull null],
             @"creator" : @"3bc5750a-b965-40f8-aff2-831e9b5ac2e9",
             @"last_event" : @"5.800112314308490f",
             @"members" : @{
                     @"self" : @{
                             @"status" : @0,
                             @"muted_time" : [NSNull null],
                             @"status_ref" : @"0.0",
                             @"last_read" : @"5.800112314308490f",
                             @"muted" : [NSNull null],
                             @"archived" : [NSNull null],
                             @"status_time" : @"2014-03-14T16:47:37.573Z",
                             @"id" : @"3bc5750a-b965-40f8-aff2-831e9b5ac2e9",
                             ZMConversationInfoOTRArchivedReferenceKey : [NSNull null],
                             ZMConversationInfoOTRArchivedValueKey : [NSNull null],
                             ZMConversationInfoOTRMutedReferenceKey : [NSNull null],
                             ZMConversationInfoOTRMutedValueKey : [NSNull null],
                             },
                     @"others" : @[]
                     },
             @"type" : @0,
             @"id" : remoteIDString
             };
}


- (void)setUpSyncWithConversationIDs:(NSArray *)conversationIDs
{
    ZMTransportResponse *idResponse = [ZMTransportResponse responseWithPayload:@{@"conversations" : conversationIDs } HTTPStatus:200 transportSessionError:nil];
    [self generateRequestAndCompleteWithResponse:idResponse];
}


- (void)generateRequestAndCompleteWithResponse:(ZMTransportResponse *)response
{
    [self generateRequestAndCompleteWithResponse:response checkRequest:nil];
}


- (void)generateRequestAndCompleteWithResponse:(ZMTransportResponse *)response checkRequest:(void(^)(ZMTransportRequest *))block {
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMTransportRequest *request = [self.sut nextRequest];
        XCTAssertNotNil(request);
        if (block) {
            block(request);
        }
        [request completeWithResponse:response];
    }];
}


- (NSArray *)createConversationIDArrayOfSize:(NSUInteger)size {
    NSMutableArray *conversationIDs = [NSMutableArray array];
    for (NSUInteger i=0; i < size; ++i) {
        [conversationIDs addObject:[NSUUID createUUID].transportString];
    }
    return conversationIDs;
}


- (void)checkThatThereAreConversationsForAllRawConversations:(NSArray *)rawConversations failureRecorder:(ZMTFailureRecorder *)failureRecorder
{
    [self.syncMOC performGroupedBlockAndWait:^{
        
        NSFetchRequest *conversationFetchRequest = [NSFetchRequest fetchRequestWithEntityName:ZMConversation.entityName];
        NSArray *conversations = [self.syncMOC executeFetchRequestOrAssert:conversationFetchRequest];
        
        for (NSDictionary *payload in rawConversations) {
            FHAssertTrue(failureRecorder, [conversations indexOfObjectPassingTest:^BOOL(ZMConversation *obj, NSUInteger idx ZM_UNUSED, BOOL *stop ZM_UNUSED) {
                return [self isConversation:obj matchingPayload:payload];
            }] != NSNotFound);
        }
    }];
}


- (ZMTransportResponse *)createConversationResponseForRawConversations:(NSArray *)rawConversations
{
    NSDictionary *responsePayload = @{@"conversations" : rawConversations};
    ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:responsePayload HTTPStatus:200 transportSessionError:nil];
    return response;
}


- (void)checkThatRequest:(ZMTransportRequest *)request isGetRequestForConversationIDs:(NSArray *)expectedConversationIDs failureRecorder:(ZMTFailureRecorder *)failureRecorder
{
    FHAssertNotNil(failureRecorder, request);
    FHAssertNotNil(failureRecorder, expectedConversationIDs);
    
    NSString *requestPath = request.path;
    NSString *expectedPrefix = CONVERSATION_ID_REQUEST_PREFIX;
    
    FHAssertTrue(failureRecorder, [request.path hasPrefix:expectedPrefix]);
    
    NSString *requestedIdentifiersString = [requestPath substringFromIndex:expectedPrefix.length];
    NSArray *requestedIdentifiers = [requestedIdentifiersString componentsSeparatedByString:@","];
    
    FHAssertEqualObjects(failureRecorder, [NSSet setWithArray:expectedConversationIDs], [NSSet setWithArray:requestedIdentifiers]);
    FHAssertEqual(failureRecorder, ZMMethodGET, request.method);
}

- (NSArray *)createRawConversationsForIds:(NSArray *)conversationIDs {
    return [conversationIDs mapWithBlock:^id(id obj) {
        return [self createConversationDataWithRemoteIDString:obj];
    }];
}


- (void)testThatItRequestsAllIDsWhenStartingSlowSync
{
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        self.mockSyncStatus.mockPhase = SyncPhaseFetchingConversations;
        
        // when
        ZMTransportRequest *request = [self.sut nextRequest];

        // then
        NSString *expectedPath = [NSString stringWithFormat:@"/conversations/ids?size=100"];
        XCTAssertNotNil(request);
        XCTAssertTrue([request.path isEqualToString:expectedPath]);
        XCTAssertEqual(ZMMethodGET, request.method);
    }];
}


- (void)testThatItFetchesAllConversationsById
{
    __block NSArray *conversationIDs;
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        self.mockSyncStatus.mockPhase = SyncPhaseFetchingConversations;
        
        conversationIDs = [self createConversationIDArrayOfSize:20];
        [self setUpSyncWithConversationIDs:conversationIDs];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    [self.syncMOC performGroupedBlockAndWait:^{
        // when
        ZMTransportRequest *request = [self.sut nextRequest];
        
        // then
        [self checkThatRequest:request isGetRequestForConversationIDs:conversationIDs failureRecorder:NewFailureRecorder()];
    }];
}


- (void)testThatItAddsConversationsFromAResponse
{
    __block NSArray *rawConversations;
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        self.mockSyncStatus.mockPhase = SyncPhaseFetchingConversations;
        
        NSArray *conversationIDs = [self createConversationIDArrayOfSize:3];
        rawConversations = [self createRawConversationsForIds:conversationIDs];
        [self setUpSyncWithConversationIDs:conversationIDs];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    [self.syncMOC performGroupedBlockAndWait:^{
     
        // when
        ZMTransportResponse *response = [self createConversationResponseForRawConversations:rawConversations];
        [self generateRequestAndCompleteWithResponse:response];
        
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    [self.syncMOC performGroupedBlockAndWait:^{
        // then
        [self checkThatThereAreConversationsForAllRawConversations:rawConversations failureRecorder:NewFailureRecorder()];
        XCTAssertTrue(self.mockSyncStatus.didCallFinishCurrentSyncPhase);
    }];
}


- (void)testThatIsResets_NeedsToUpdateFromBackend_OnExistingConversationsInAResponse
{
    __block NSArray *rawConversations;
    __block NSArray *conversationIDs;
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        self.mockSyncStatus.mockPhase = SyncPhaseFetchingConversations;
        
        conversationIDs = [self createConversationIDArrayOfSize:3];
        rawConversations = [self createRawConversationsForIds:conversationIDs];
        [self setUpSyncWithConversationIDs:conversationIDs];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    [self.syncMOC performGroupedBlockAndWait:^{
        
        // when
        ZMTransportResponse *response = [self createConversationResponseForRawConversations:rawConversations];
        [self generateRequestAndCompleteWithResponse:response checkRequest:^(ZMTransportRequest *req __unused) {
            // Artificially set the needsToUpdateFromBackend to true
            for(NSString *remoteID in conversationIDs) {
                ZMConversation * conversation = [ZMConversation conversationWithRemoteID:[NSUUID uuidWithTransportString:remoteID] createIfNeeded:YES inContext:self.sut.managedObjectContext];
                conversation.needsToBeUpdatedFromBackend = YES;
            }
        }];
        
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    [self.syncMOC performGroupedBlockAndWait:^{
        // then
        for(NSString *remoteID in conversationIDs) {
            ZMConversation * conversation = [ZMConversation conversationWithRemoteID:[NSUUID uuidWithTransportString:remoteID] createIfNeeded:YES inContext:self.sut.managedObjectContext];
            XCTAssertFalse(conversation.needsToBeUpdatedFromBackend);
        }
    }];
}

- (void)testThatItPaginatesConversationRequests
{
    __block NSArray *allConversationIDs;
    __block ZMTransportResponse *response1;
    NSMutableArray *requestedIDs = [NSMutableArray array];
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        self.mockSyncStatus.mockPhase = SyncPhaseFetchingConversations;
        
        NSUInteger pageSize = 13;
        self.sut.conversationPageSize = pageSize;
        
        NSArray *conversationIDPage1 = [self createConversationIDArrayOfSize:pageSize];
        NSArray *rawConversations1 = [self createRawConversationsForIds:conversationIDPage1];
        response1 = [self createConversationResponseForRawConversations:rawConversations1];
        
        NSArray *conversationIDPage2 = [self createConversationIDArrayOfSize:5];
        
        allConversationIDs = [conversationIDPage1 arrayByAddingObjectsFromArray:conversationIDPage2];
        
        [self setUpSyncWithConversationIDs:allConversationIDs];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    [self.syncMOC performGroupedBlockAndWait:^{
        
        // when
        [self generateRequestAndCompleteWithResponse:response1 checkRequest:^(ZMTransportRequest *request) {
            [self addIDsFromRequest:request toArray:requestedIDs];
        }];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    [self.syncMOC performGroupedBlockAndWait:^{
        __block ZMTransportRequest *page2Request;
        [self.syncMOC performGroupedBlockAndWait:^{
            page2Request = [self.sut nextRequest];
        }];
        
        [self addIDsFromRequest:page2Request toArray:requestedIDs];
        
        // then
        XCTAssertEqual(allConversationIDs.count, requestedIDs.count);
        XCTAssertEqualObjects([NSSet setWithArray:allConversationIDs], [NSSet setWithArray:requestedIDs]);
    }];
}


- (void)addIDsFromRequest:(ZMTransportRequest *)request toArray:(NSMutableArray *)array {
    
    NSString *requestedIDs = [request.path substringFromIndex:CONVERSATION_ID_REQUEST_PREFIX.length];
    NSArray *justIDArray = [requestedIDs componentsSeparatedByString:@","];
    [array addObjectsFromArray:justIDArray];
}

- (void)testThatItDoeNotSendAnotherRequestIfItReceivedAllPages
{
    __block ZMTransportResponse *response1;
    __block ZMTransportResponse *response2;
    
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        self.mockSyncStatus.mockPhase = SyncPhaseFetchingConversations;
        
        NSUInteger pageSize = 13;
        self.sut.conversationPageSize = pageSize;
        
        NSArray *conversationIDPage1 = [self createConversationIDArrayOfSize:pageSize];
        NSArray *rawConversations1 = [self createRawConversationsForIds:conversationIDPage1];
        response1 = [self createConversationResponseForRawConversations:rawConversations1];
        
        NSArray *conversationIDPage2 = [self createConversationIDArrayOfSize:5];
        NSArray *rawConversations2 = [self createRawConversationsForIds:conversationIDPage2];
        response2 = [self createConversationResponseForRawConversations:rawConversations2];
        
        
        NSArray *allConversationIDs = [conversationIDPage1 arrayByAddingObjectsFromArray:conversationIDPage2];
        
        [self setUpSyncWithConversationIDs:allConversationIDs];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    [self.syncMOC performGroupedBlockAndWait:^{
        
        // when
        [self generateRequestAndCompleteWithResponse:response1];
    }];
    WaitForAllGroupsToBeEmpty(0.15);
    [self.syncMOC performGroupedBlockAndWait:^{
        [self generateRequestAndCompleteWithResponse:response2];
    }];
    WaitForAllGroupsToBeEmpty(0.15);
    [self.syncMOC performGroupedBlockAndWait:^{
        // then
        ZMTransportRequest *request = [self.sut nextRequest];
        XCTAssertNil(request);
    }];
}





- (void)testThatPageSizeIsSetToDefault
{
    // then
    XCTAssertEqual(self.sut.conversationPageSize, ZMConversationTranscoderDefaultConversationPageSize);
}

- (void)testThatIsSlowSyncDoneIsTrueWhenAllConversationsAreFetched
{
    __block NSArray *rawConversations;
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        self.mockSyncStatus.mockPhase = SyncPhaseFetchingConversations;
        
        NSArray *conversationIDs = [self createConversationIDArrayOfSize:3];
        rawConversations = [self createRawConversationsForIds:conversationIDs];
        [self setUpSyncWithConversationIDs:conversationIDs];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    [self.syncMOC performGroupedBlockAndWait:^{
        
        // when
        ZMTransportResponse *response = [self createConversationResponseForRawConversations:rawConversations];
        [self generateRequestAndCompleteWithResponse:response];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    [self.syncMOC performGroupedBlockAndWait:^{
        // then
        XCTAssertTrue(self.mockSyncStatus.didCallFinishCurrentSyncPhase);
    }];
}


- (void)testThatItDoesNotCreateANewRequestWhileARequestIsAlreadyInProgress
{
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        self.mockSyncStatus.mockPhase = SyncPhaseFetchingConversations;
        ZMTransportRequest *firstRequest = [self.sut nextRequest];
        XCTAssertNotNil(firstRequest);
        
        // when
        ZMTransportRequest *request = [self.sut nextRequest];
        
        // then
        XCTAssertNil(request);
    }];
}


- (void)testThatItDoesNotFetchConversationsIfThereIsNothingToFetch
{
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        self.mockSyncStatus.mockPhase = SyncPhaseFetchingConversations;
        [self setUpSyncWithConversationIDs:@[]];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    [self.syncMOC performGroupedBlockAndWait:^{
        
        // when
        ZMTransportRequest *request = [self.sut nextRequest];
        
        // then
        XCTAssertNil(request);
        XCTAssertTrue(self.mockSyncStatus.didCallFinishCurrentSyncPhase);
    }];
}




- (void)testThatItDoesNotGenerateConversationsDuringSlowSync
{
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        self.mockSyncStatus.mockPhase = SyncPhaseFetchingConversations;
        
        ZMUser *user1 = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        user1.remoteIdentifier = [NSUUID createUUID];
        
        ZMUser *user2 = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        user2.remoteIdentifier = [NSUUID createUUID];
        
        ZMConversation *insertedConversation = [ZMConversation insertGroupConversationIntoManagedObjectContext:self.syncMOC
                                                                                              withParticipants:@[user1, user2]];
        NOT_USED(insertedConversation);
        
        
        // - this is the hard sync request
        ZMTransportRequest *request1 = [self.sut nextRequest];
        XCTAssertNotNil(request1);
        NSString *expectedPath = @"/conversations/ids?size=100";
        XCTAssertEqualObjects(expectedPath, request1.path);
        XCTAssertEqual(ZMMethodGET, request1.method);
        
        // when
        ZMTransportRequest *request2 = [self.sut nextRequest];
        
        // then
        XCTAssertNil(request2);
    }];
}

- (void)testThatItGeneratesRequestsAfterSlowSyncIsDone
{
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        self.mockSyncStatus.mockPhase = SyncPhaseFetchingConversations;
        
        ZMUser *user1 = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        user1.remoteIdentifier = [NSUUID createUUID];
        
        ZMUser *user2 = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        user2.remoteIdentifier = [NSUUID createUUID];
        
        ZMConversation *insertedConversation = [ZMConversation insertGroupConversationIntoManagedObjectContext:self.syncMOC
                                                                                              withParticipants:@[user1, user2]];
        [self.syncMOC saveOrRollback];
        // expect
        for (id<ZMContextChangeTracker> tracker in self.sut.contextChangeTrackers) {
            [tracker objectsDidChange:[NSSet setWithObject:insertedConversation]];
        }
        
        // - this is the hard sync request
        ZMTransportRequest *request1 = [self.sut nextRequest];
        XCTAssertNotNil(request1);
        NSString *expectedPath = @"/conversations/ids?size=100";
        XCTAssertEqualObjects(expectedPath, request1.path);
        XCTAssertEqual(ZMMethodGET, request1.method);
        
        
        [request1 completeWithResponse:[ZMTransportResponse responseWithPayload:nil HTTPStatus:200 transportSessionError:nil]];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    [self.syncMOC performGroupedBlockAndWait:^{
        // when
        self.mockSyncStatus.mockPhase = SyncPhaseDone;
        ZMTransportRequest *request2 = [self.sut nextRequest];
        
        // then
        XCTAssertNotNil(request2);
        
        XCTAssertEqualObjects(@"/conversations", request2.path);
        XCTAssertEqual(ZMMethodPOST, request2.method);
    }];
}






@end



@implementation ZMConversationTranscoderTests (InsertNewConversation)


- (void)testThatItGeneratesARequestToGenerateAConversation
{
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        ZMUser *user1 = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        user1.remoteIdentifier = [NSUUID createUUID];
        
        ZMUser *user2 = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        user2.remoteIdentifier = [NSUUID createUUID];
        
        ZMUser *user3 = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        user3.remoteIdentifier = [NSUUID createUUID];
        
        ZMConversation *insertedConversation = [ZMConversation insertGroupConversationIntoManagedObjectContext:self.syncMOC withParticipants:@[
                                                                                                                                             user1, user2, user3
                                                                                                                                             ]];
        XCTAssertTrue([self.syncMOC saveOrRollback]);
        
        
        // expect
        for (id<ZMContextChangeTracker> tracker in self.sut.contextChangeTrackers) {
            [tracker objectsDidChange:[NSSet setWithObject:insertedConversation]];
        }
        
        // when
        ZMTransportRequest *request = [self.sut nextRequest];
        
        
        // then
        XCTAssertEqualObjects(@"/conversations", request.path);
        XCTAssertEqual(ZMMethodPOST, request.method);
        
        NSSet *expectedUsers = [NSSet setWithArray:@[
                                                     [user1.remoteIdentifier transportString],
                                                     [user2.remoteIdentifier transportString],
                                                     [user3.remoteIdentifier transportString]
                                                     ]];
        XCTAssertEqualObjects([NSSet setWithArray:request.payload[@"users"]], expectedUsers);
    }];
}

- (void)testThatItGeneratesARequestToGenerateAConversationWithAName
{
    
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        NSString *name = @"Foo foo conversation";
        ZMUser *user1 = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        user1.remoteIdentifier = [NSUUID createUUID];
        
        ZMUser *user2 = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        user2.remoteIdentifier = [NSUUID createUUID];
        
        ZMUser *user3 = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        user3.remoteIdentifier = [NSUUID createUUID];
        
        ZMConversation *insertedConversation = [ZMConversation insertGroupConversationIntoManagedObjectContext:self.syncMOC withParticipants:@[
                                                                                                                                             user1, user2, user3
                                                                                                                                             ]];
        insertedConversation.userDefinedName = name;
        XCTAssertTrue([self.syncMOC saveOrRollback]);
        
        // expect
        for (id<ZMContextChangeTracker> tracker in self.sut.contextChangeTrackers) {
            [tracker objectsDidChange:[NSSet setWithObject:insertedConversation]];
        }
        
        // when
        ZMTransportRequest *request = [self.sut nextRequest];
        
        
        // then
        XCTAssertEqualObjects(@"/conversations", request.path);
        XCTAssertEqual(ZMMethodPOST, request.method);
        
        NSSet *expectedUsers = [NSSet setWithArray:@[
                                                     [user1.remoteIdentifier transportString],
                                                     [user2.remoteIdentifier transportString],
                                                     [user3.remoteIdentifier transportString]
                                                     ]];
        XCTAssertEqualObjects([NSSet setWithArray:request.payload[@"users"]], expectedUsers);
        XCTAssertEqualObjects(request.payload[@"name"], name);
    }];
}



- (void)testThatModifedSyncIsUpdatedWhenConversationTranscoderShouldNotCreateRequest;
{
    __block ZMConversation *conversation = nil;
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMUser *user1 = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        user1.remoteIdentifier = [NSUUID createUUID];
        
        ZMUser *user2 = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        user2.remoteIdentifier = [NSUUID createUUID];
        
        conversation = [ZMConversation insertGroupConversationIntoManagedObjectContext:self.syncMOC withParticipants:@[user1, user2]];
        conversation.userDefinedName = nil;
        [conversation setLocallyModifiedKeys:[NSSet setWithObject:ZMConversationUserDefinedNameKey]];
        XCTAssertTrue([self.syncMOC saveOrRollback]);
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    ZMUpstreamModifiedObjectSync *mockUpstream = [OCMockObject niceMockForClass:ZMUpstreamModifiedObjectSync.class];
    
    [self.syncMOC performGroupedBlockAndWait:^{
        // when
        XCTAssertTrue([conversation.keysThatHaveLocalModifications containsObject:ZMConversationUserDefinedNameKey]);

        [self.sut shouldCreateRequestToSyncObject:conversation forKeys:[NSSet set] withSync:mockUpstream];
        
        XCTAssertFalse([conversation.keysThatHaveLocalModifications containsObject:ZMConversationUserDefinedNameKey]);
    }];
}

- (void)checkThatItResetsLocallyModifiedKeysIfNeededBeforeCreatingRequestForKey:(NSString *)key shouldCreateRequest:(BOOL)shouldCreateRequest withBlock:(void(^)(ZMConversation *conversation, NSArray<ZMUser *> *users))block
{
    __block ZMConversation *conversation = nil;
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMUser *user1 = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        user1.remoteIdentifier = [NSUUID createUUID];
        ZMUser *user2 = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        user2.remoteIdentifier = [NSUUID createUUID];
        conversation = [ZMConversation insertGroupConversationIntoManagedObjectContext:self.syncMOC withParticipants:@[user1, user2]];

        block(conversation, @[user1, user2]);
        XCTAssertTrue([self.syncMOC saveOrRollback]);
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    ZMUpstreamModifiedObjectSync *mockUpstream = [OCMockObject niceMockForClass:ZMUpstreamModifiedObjectSync.class];
    
    [self.syncMOC performGroupedBlockAndWait:^{
        // when
        [conversation setLocallyModifiedKeys:[NSSet setWithObject:key]];
        XCTAssertTrue([conversation.keysThatHaveLocalModifications containsObject:key]);
        
        BOOL willCreate = [self.sut shouldCreateRequestToSyncObject:conversation forKeys:[NSSet setWithObject:key] withSync:mockUpstream];
        if (!shouldCreateRequest) {
            XCTAssertFalse([conversation.keysThatHaveLocalModifications containsObject:key]);
            XCTAssertFalse(willCreate);

        } else {
            XCTAssertTrue([conversation.keysThatHaveLocalModifications containsObject:key]);
            XCTAssertTrue(willCreate);
        }
    }];
}

- (void)testThatItResetsUserDefinedNameKeyIfTranscoderShould_Not_CreateRequest;
{
    [self checkThatItResetsLocallyModifiedKeysIfNeededBeforeCreatingRequestForKey:ZMConversationUserDefinedNameKey shouldCreateRequest:NO withBlock:^(ZMConversation *conversation, id ZM_UNUSED users){
        conversation.userDefinedName = nil;
    }];
}

- (void)testThatItResetsIsSelfAnActiveMemberKeysIfTranscoderShould_Not_CreateRequest;
{
    [self checkThatItResetsLocallyModifiedKeysIfNeededBeforeCreatingRequestForKey:ZMConversationIsSelfAnActiveMemberKey shouldCreateRequest:NO withBlock:^(ZMConversation *conversation, id ZM_UNUSED users){
        conversation.isSelfAnActiveMember = YES;
    }];
}

- (void)testThatItDoesNotResetsIsSelfAnActiveMemberKeysIfTranscoderShouldCreateRequest;
{
    [self checkThatItResetsLocallyModifiedKeysIfNeededBeforeCreatingRequestForKey:ZMConversationIsSelfAnActiveMemberKey shouldCreateRequest:YES withBlock:^(ZMConversation *conversation, id ZM_UNUSED users){
        conversation.isSelfAnActiveMember = NO;
    }];
}

- (void)testThatItResetsUnsyncedActiveParticipantsKeysIfTranscoderShould_Not_CreateRequest;
{
    [self checkThatItResetsLocallyModifiedKeysIfNeededBeforeCreatingRequestForKey:ZMConversationUnsyncedActiveParticipantsKey shouldCreateRequest:NO withBlock:^(ZMConversation *conversation, NSArray<ZMUser*>* users){
        for (ZMUser *user in users){
            [conversation synchronizeAddedUser:user];
        }
        XCTAssertEqual(conversation.unsyncedActiveParticipants.count, 0u);
    }];
}

- (void)testThatItResetsUnsyncedActiveParticipantsKeysIfTranscoderShouldCreateRequest;
{
    [self checkThatItResetsLocallyModifiedKeysIfNeededBeforeCreatingRequestForKey:ZMConversationUnsyncedActiveParticipantsKey shouldCreateRequest:YES withBlock:^(ZMConversation *conversation, id ZM_UNUSED users){
        XCTAssertNotEqual(conversation.unsyncedActiveParticipants.count, 0u);
    }];
}

- (void)testThatItResetsUnsyncedInctiveParticipantsKeysIfTranscoderShould_Not_CreateRequest;
{
    [self checkThatItResetsLocallyModifiedKeysIfNeededBeforeCreatingRequestForKey:ZMConversationUnsyncedInactiveParticipantsKey shouldCreateRequest:NO withBlock:^(ZMConversation *conversation, id ZM_UNUSED users){
        for (ZMUser *user in users){
            [conversation removeParticipant:user];
            [conversation synchronizeRemovedUser:user];
        }
        XCTAssertEqual(conversation.unsyncedInactiveParticipants.count, 0u);
    }];
}

- (void)testThatItResetsUnsyncedInctiveParticipantsKeysIfTranscoderShouldCreateRequest;
{
    [self checkThatItResetsLocallyModifiedKeysIfNeededBeforeCreatingRequestForKey:ZMConversationUnsyncedInactiveParticipantsKey shouldCreateRequest:YES withBlock:^(ZMConversation *conversation, id ZM_UNUSED users){
        for (ZMUser *user in users){
            [conversation synchronizeAddedUser:user];
            [conversation removeParticipant:user];
        }
        XCTAssertNotEqual(conversation.unsyncedInactiveParticipants.count, 0u);
    }];
}


- (void)testThatItOnlyResetsTheKeysItNeedsToReset
{
    NSSet *keys = [NSSet setWithObjects:ZMConversationIsSelfAnActiveMemberKey, ZMConversationUserDefinedNameKey, nil];
    __block ZMConversation *conversation = nil;
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMUser *user1 = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        user1.remoteIdentifier = [NSUUID createUUID];
        ZMUser *user2 = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        user2.remoteIdentifier = [NSUUID createUUID];
        conversation = [ZMConversation insertGroupConversationIntoManagedObjectContext:self.syncMOC withParticipants:@[user1, user2]];
        
        conversation.userDefinedName = nil;
        conversation.isSelfAnActiveMember = NO;
        
        XCTAssertTrue([self.syncMOC saveOrRollback]);
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    ZMUpstreamModifiedObjectSync *mockUpstream = [OCMockObject niceMockForClass:ZMUpstreamModifiedObjectSync.class];
    
    [self.syncMOC performGroupedBlockAndWait:^{
        // when
        [conversation setLocallyModifiedKeys:keys];
        XCTAssertTrue([conversation.keysThatHaveLocalModifications isEqualToSet:keys]);
        
        BOOL shouldCreate = [self.sut shouldCreateRequestToSyncObject:conversation forKeys:keys withSync:mockUpstream];
        XCTAssertFalse([conversation.keysThatHaveLocalModifications containsObject:ZMConversationUserDefinedNameKey]);
        XCTAssertTrue([conversation.keysThatHaveLocalModifications containsObject:ZMConversationIsSelfAnActiveMemberKey]);
        XCTAssertTrue(shouldCreate);
    }];
}


- (void)testThatItDoesNotGeneratesTheSameConversationTwice
{
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        ZMUser *user1 = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        user1.remoteIdentifier = [NSUUID createUUID];
        
        ZMUser *user2 = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        user2.remoteIdentifier = [NSUUID createUUID];
        
        ZMConversation *insertedConversation = [ZMConversation insertGroupConversationIntoManagedObjectContext:self.syncMOC
                                                                                              withParticipants:@[user1, user2]];
        insertedConversation.userDefinedName = @"Test conversation 1";
        
        [self.syncMOC saveOrRollback];
        // expect
        for (id<ZMContextChangeTracker> tracker in self.sut.contextChangeTrackers) {
            [tracker objectsDidChange:[NSSet setWithObject:insertedConversation]];
        }
        
        // when
        ZMTransportRequest *request1 = [self.sut nextRequest];
        XCTAssertNotNil(request1);
        ZMTransportRequest *request2 = [self.sut nextRequest];
        
        // then
        XCTAssertNil(request2);
    }];
}


- (void)testThatItUpdatesANewlyInsertedConversationWithTheResponsePayload
{
    // given
    
    __block ZMConversation *insertedConversation;
    __block ZMTransportRequest *request;
    
    NSDate *lastModifiedDate = [NSDate dateWithTimeIntervalSinceNow:2133333];
    NSUUID *convUUID =[NSUUID createUUID];
    NSString *name = @"Procrastination";
    
    
    [self.syncMOC performGroupedBlockAndWaitWithReasonableTimeout:^{
        ZMUser *user1 = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        user1.remoteIdentifier = [NSUUID createUUID];
        NSUUID *user1ID = user1.remoteIdentifier;
        
        ZMUser *user2 = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        user2.remoteIdentifier = [NSUUID createUUID];
        NSUUID *user2ID = user2.remoteIdentifier;
        
        insertedConversation = [ZMConversation insertGroupConversationIntoManagedObjectContext:self.syncMOC
                                                                              withParticipants:@[user1, user2]];
        
        
        
        NSDictionary *payload =  @{
                                   @"creator" : user1ID.transportString,
                                   @"id" : convUUID.transportString,
                                   @"last_event_time" : lastModifiedDate.transportString,
                                   @"members" : @{
                                           @"others" : @[
                                                   @{
                                                       @"id" : user1ID.transportString,
                                                       @"status" : @0,
                                                       },
                                                   @{
                                                       @"id" : user2ID.transportString,
                                                       @"status" : @0,
                                                       },
                                                   ],
                                           @"self" : @{
                                                   @"id" : @"90c74fe0-cef7-446a-affb-6cba0e75d5da",
                                                   @"status" : @0,
                                                   },
                                           },
                                   @"name" : name,
                                   @"type" : @0
                                   };
        
        [self.syncMOC saveOrRollback];
        
        // when
        for (id<ZMContextChangeTracker> tracker in self.sut.contextChangeTrackers) {
            [tracker objectsDidChange:[NSSet setWithObject:insertedConversation]];
        }
        
        
        request = [self.sut nextRequest];
        [request completeWithResponse:[ZMTransportResponse responseWithPayload:payload HTTPStatus:200 transportSessionError:nil]];
    }];
    
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    [self.syncMOC performGroupedBlockAndWait:^{
        XCTAssertEqualObjects(convUUID, insertedConversation.remoteIdentifier);
        XCTAssertEqualObjects(name, insertedConversation.userDefinedName);
        XCTAssertEqualWithAccuracy([lastModifiedDate timeIntervalSince1970], [insertedConversation.lastModifiedDate timeIntervalSince1970], 0.1);
        
        //[NSDate transportString] truncates date
        XCTAssertEqual(round([lastModifiedDate timeIntervalSince1970] * 1000),
                       round([insertedConversation.lastModifiedDate timeIntervalSince1970] * 1000));
    }];
}

- (void)testThatItDoesNotUpdateLastModifiedDateIfItsPriorCurrentValue
{
    __block ZMConversation *insertedConversation;
    __block ZMTransportRequest *request;

    NSDate *lastModifiedDate = [NSDate dateWithTimeIntervalSinceNow:-2133333];
    NSUUID *convUUID =[NSUUID createUUID];
    NSString *name = @"Procrastination";
    
    __block NSDate *currentLastModified;
    
    [self.syncMOC performGroupedBlockAndWaitWithReasonableTimeout:^{
        ZMUser *user1 = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        user1.remoteIdentifier = [NSUUID createUUID];
        NSUUID *user1ID = user1.remoteIdentifier;
        
        ZMUser *user2 = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        user2.remoteIdentifier = [NSUUID createUUID];
        NSUUID *user2ID = user2.remoteIdentifier;
        
        insertedConversation = [ZMConversation insertGroupConversationIntoManagedObjectContext:self.syncMOC
                                                                              withParticipants:@[user1, user2]];
        
        currentLastModified = insertedConversation.lastModifiedDate;
        
        NSDictionary *payload =  @{
                                   @"creator" : user1ID.transportString,
                                   @"id" : convUUID.transportString,
                                   @"last_event_time" : lastModifiedDate.transportString,
                                   @"members" : @{
                                           @"others" : @[
                                                   @{
                                                       @"id" : user1ID.transportString,
                                                       @"status" : @0,
                                                       },
                                                   @{
                                                       @"id" : user2ID.transportString,
                                                       @"status" : @0,
                                                       },
                                                   ],
                                           @"self" : @{
                                                   @"id" : @"90c74fe0-cef7-446a-affb-6cba0e75d5da",
                                                   @"status" : @0,
                                                   },
                                           },
                                   @"name" : name,
                                   @"type" : @0
                                   };
        
        [self.syncMOC saveOrRollback];
        
        // when
        for (id<ZMContextChangeTracker> tracker in self.sut.contextChangeTrackers) {
            [tracker objectsDidChange:[NSSet setWithObject:insertedConversation]];
        }
        
        
        request = [self.sut nextRequest];
        [request completeWithResponse:[ZMTransportResponse responseWithPayload:payload HTTPStatus:200 transportSessionError:nil]];
    }];
    
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    [self.syncMOC performGroupedBlockAndWait:^{
        XCTAssertEqualObjects(currentLastModified, insertedConversation.lastModifiedDate);
    }];

}

- (void)testThatANewConversationIsDeletedOnBackendError
{
    // given
    __block ZMTransportRequest *request;
    [self.syncMOC performGroupedBlockAndWaitWithReasonableTimeout:^{
        ZMUser *user1 = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        user1.remoteIdentifier = [NSUUID createUUID];
        
        ZMUser *user2 = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        user2.remoteIdentifier = [NSUUID createUUID];
        
        ZMConversation *insertedConversation = [ZMConversation insertGroupConversationIntoManagedObjectContext:self.syncMOC
                                                                                              withParticipants:@[user1, user2]];
        [self.syncMOC saveOrRollback];
        
        for (id<ZMContextChangeTracker> tracker in self.sut.contextChangeTrackers) {
            [tracker objectsDidChange:[NSSet setWithObject:insertedConversation]];
        }
        
        request = [self.sut nextRequest];
    }];
    
    // when
    [request completeWithResponse:[ZMTransportResponse responseWithPayload:nil HTTPStatus:430 transportSessionError:nil]];
    WaitForAllGroupsToBeEmpty(0.5);
    
    [self.syncMOC performGroupedBlockAndWaitWithReasonableTimeout:^{
        [self.syncMOC saveOrRollback];
    }];
    
    // then
    NSFetchRequest *convFetchRequest = [ZMConversation sortedFetchRequest];
    NSArray *conversations = [self.uiMOC executeFetchRequestOrAssert:convFetchRequest];
    XCTAssertEqual(0u, conversations.count);
}


- (void)testThatWhenCreatedItGeneratesRequestForConversationMissingRemoteIdentifier
{
    // given
    
    __block ZMUser *user1;
    __block ZMUser *user2;
    [self.syncMOC performGroupedBlockAndWait:^{
        user1 = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        user1.remoteIdentifier = [NSUUID createUUID];
        
        user2 = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        user2.remoteIdentifier = [NSUUID createUUID];
        
        [ZMConversation insertGroupConversationIntoManagedObjectContext:self.syncMOC withParticipants:@[user1, user2]];
        XCTAssertTrue([self.syncMOC saveOrRollback]);
    }];
    
    id authStatusMock = [OCMockObject mockForClass:[ZMAuthenticationStatus class]];
    [[[authStatusMock stub] andReturnValue:@YES] registeredOnThisDevice];
    
    self.sut = (id) [[ZMConversationTranscoder alloc] initWithSyncStrategy:self.syncStrategy applicationStatus:self.mockApplicationStatus syncStatus:self.mockSyncStatus];
    WaitForAllGroupsToBeEmpty(0.5);
    
    [ZMChangeTrackerBootstrap bootStrapChangeTrackers:self.sut.contextChangeTrackers onContext:self.syncMOC];
    [self.syncMOC performGroupedBlockAndWait:^{
        // when
        ZMTransportRequest *request = [self.sut nextRequest];
        
        // then
        XCTAssertEqualObjects(@"/conversations", request.path);
        XCTAssertEqual(ZMMethodPOST, request.method);
        
        NSSet *expectedUsers = [NSSet setWithArray:@[
                                                     [user1.remoteIdentifier transportString],
                                                     [user2.remoteIdentifier transportString],
                                                     ]];
        XCTAssertEqualObjects([NSSet setWithArray:request.payload[@"users"]], expectedUsers);
    }];
}


- (void)testThatItWhenTheCreationRequestReturnsAnyAlreadyExistingConversationIsDeletedAndTheNewOneIsMarkedAsToDownloadIfTheOldOneHasADifferentLastEventId
{
    // this can happen if we received a push event notification before we received the conversation creation roundtrip
    
    // given
    NSUUID *remoteID = [NSUUID createUUID];
    __block ZMConversation *createdConversation;
    __block ZMConversation *existingConversation;
    [self.syncMOC performGroupedBlockAndWait:^{
        
        existingConversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        existingConversation.remoteIdentifier = remoteID;
        existingConversation.conversationType = ZMConversationTypeGroup;
        createdConversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        createdConversation.conversationType = ZMConversationTypeGroup;
        [self.syncMOC saveOrRollback];
        
        for (id<ZMContextChangeTracker> tracker in self.sut.contextChangeTrackers) {
            [tracker objectsDidChange:[NSSet setWithObject:createdConversation]];
        }
        
        
        NSDictionary *responsePayload = @{
                                          @"creator" : @"39562cc3-717d-4395-979c-5387ae17f5c3",
                                          @"id" : remoteID.transportString,
                                          @"last_event_time" : @"2014-06-02T12:50:43.047Z",
                                          @"members" : @{
                                                  @"others" : @[],
                                                  @"self" : @{
                                                          @"status" : @0,
                                                          }
                                                  },
                                          @"name" : [NSNull null],
                                          @"type" : @(ZMConversationTypeGroup)
                                          };
        
        // when
        
        
        ZMTransportRequest *request = [self.sut nextRequest];
        XCTAssertNotNil(request);
        
        ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:responsePayload HTTPStatus:200 transportSessionError:nil];
        [request completeWithResponse:response];
        
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    [self.syncMOC performGroupedBlockAndWait:^{
        
        NSFetchRequest *fetchRequest = [NSFetchRequest fetchRequestWithEntityName:[ZMConversation entityName]];
        fetchRequest.predicate = [NSPredicate predicateWithFormat:@"remoteIdentifier_data == %@", remoteID.data];
        NSArray *result = [self.syncMOC executeFetchRequestOrAssert:fetchRequest];
        
        XCTAssertEqual(result.count, 1u);
        
        XCTAssertEqual(createdConversation, result[0]);
        XCTAssertTrue(existingConversation.isDeleted || existingConversation.managedObjectContext == nil);
        XCTAssertTrue(createdConversation.needsToBeUpdatedFromBackend);
        
    }];
}


- (void)testThatItWhenTheCreationRequestReturnsAnyAlreadyExistingConversationIsDeletedAndTheNewOneIsNotMarkedAsToDownloadIfTheOldOneDoesNotHaveEvents
{
    // this can happen if we received a push event notification before we received the conversation creation roundtrip
    
    // given
    NSDate *lastEventTime = [NSDate date];
    NSUUID *remoteID = [NSUUID createUUID];
    __block ZMConversation *createdConversation;
    __block ZMConversation *existingConversation;
    [self.syncMOC performGroupedBlockAndWait:^{
        
        existingConversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        existingConversation.remoteIdentifier = remoteID;
        existingConversation.conversationType = ZMConversationTypeGroup;
        existingConversation.lastServerTimeStamp = lastEventTime;
        createdConversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        createdConversation.conversationType = ZMConversationTypeGroup;
        [self.syncMOC saveOrRollback];
        
        for (id<ZMContextChangeTracker> tracker in self.sut.contextChangeTrackers) {
            [tracker objectsDidChange:[NSSet setWithObject:createdConversation]];
        }
    }];
    
    NSDictionary *responsePayload = @{
                                      @"creator" : @"39562cc3-717d-4395-979c-5387ae17f5c3",
                                      @"id" : remoteID.transportString,
                                      @"last_event_time" : lastEventTime.transportString,
                                      @"members" : @{
                                              @"others" : @[],
                                              @"self" : @{
                                                      @"last_read" : @"1.800122000a4a0dd1",
                                                      @"status" : @0,
                                                      }
                                              },
                                      @"name" : [NSNull null],
                                      @"type" : @(ZMConversationTypeGroup)
                                      };
    
    // when
    [self.syncMOC performGroupedBlockAndWait:^{
        
        ZMTransportRequest *request = [self.sut nextRequest];
        XCTAssertNotNil(request);
        
        ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:responsePayload HTTPStatus:200 transportSessionError:nil];
        [request completeWithResponse:response];
        
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    [self.syncMOC performGroupedBlockAndWait:^{
        
        NSFetchRequest *fetchRequest = [NSFetchRequest fetchRequestWithEntityName:[ZMConversation entityName]];
        fetchRequest.predicate = [NSPredicate predicateWithFormat:@"remoteIdentifier_data == %@", remoteID.data];
        NSArray *result = [self.syncMOC executeFetchRequestOrAssert:fetchRequest];
        
        XCTAssertEqual(result.count, 1u);
        
        XCTAssertEqual(createdConversation, result[0]);
        XCTAssertTrue(existingConversation.isDeleted || existingConversation.managedObjectContext == nil);
        XCTAssertFalse(createdConversation.needsToBeUpdatedFromBackend);
        
    }];
}

- (void)testThatItDoesNotAppendsYouStartedUsingANewDeviceIfRegisteredDevice {
    
    // given

    UserClient *selfClient = [self createSelfClient];
    
    __block NSDictionary *rawConversation;
    [self.syncMOC performGroupedBlockAndWait:^{
        self.mockSyncStatus.mockPhase = SyncPhaseFetchingConversations;
        
        NSArray *conversationIDs = [self createConversationIDArrayOfSize:1];
        rawConversation = [self createRawConversationsForIds:conversationIDs][0];
        [self setUpSyncWithConversationIDs:conversationIDs];
    }];
    
    WaitForAllGroupsToBeEmpty(0.5);
    [self.syncMOC performGroupedBlockAndWait:^{
        
        // when
        ZMTransportResponse *response = [self createConversationResponseForRawConversations:@[rawConversation]];
        [self generateRequestAndCompleteWithResponse:response];
    }];
    
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    ZMConversation *conv = [ZMConversation conversationWithRemoteID:[NSUUID uuidWithTransportString:rawConversation[@"id"]] createIfNeeded:NO inContext:self.syncMOC];
    
    NSArray *messages = [conv.messages filteredOrderedSetUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(ZMMessage * _Nonnull evaluatedObject, NSDictionary<NSString *,id> * _Nullable ZM_UNUSED bindings) {
        return [evaluatedObject isKindOfClass:[ZMSystemMessage class]] && [(ZMSystemMessage *)evaluatedObject systemMessageType] == ZMSystemMessageTypeNewClient && [[(ZMSystemMessage *)evaluatedObject clients] containsObject:(id<UserClientType>)selfClient];
    }]].array;
    
    XCTAssertEqual(messages.count, 0u);
}

- (void)testThatItDoesAppendsNewConversationSystemMessage
{
    // given
    id authStatusMock = [OCMockObject niceMockForClass:[ZMAuthenticationStatus class]];
    [[[authStatusMock stub] andReturnValue:@YES] registeredOnThisDevice];
    [(ZMAuthenticationStatus *)[[authStatusMock stub] andReturnValue:OCMOCK_VALUE((ZMAuthenticationPhase){ZMAuthenticationPhaseAuthenticated})] currentPhase];
    
    self.sut = (id) [[ZMConversationTranscoder alloc] initWithSyncStrategy:self.syncStrategy applicationStatus:self.mockApplicationStatus syncStatus:self.mockSyncStatus];
    
    __block NSDictionary *rawConversation;
    [self.syncMOC performGroupedBlockAndWait:^{
        self.mockSyncStatus.mockPhase = SyncPhaseFetchingConversations;
        
        NSArray *conversationIDs = [self createConversationIDArrayOfSize:1];
        rawConversation = [self createRawConversationsForIds:conversationIDs][0];
        [self setUpSyncWithConversationIDs:conversationIDs];
    }];
    
    WaitForAllGroupsToBeEmpty(0.5);
    [self.syncMOC performGroupedBlockAndWait:^{
        
        // when
        ZMTransportResponse *response = [self createConversationResponseForRawConversations:@[rawConversation]];
        [self generateRequestAndCompleteWithResponse:response];
    }];
    
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    ZMConversation *conv = [ZMConversation conversationWithRemoteID:[NSUUID uuidWithTransportString:rawConversation[@"id"]] createIfNeeded:NO inContext:self.syncMOC];
    
    NSArray *messages = [conv.messages filteredOrderedSetUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(ZMMessage * _Nonnull evaluatedObject, NSDictionary<NSString *,id> * _Nullable ZM_UNUSED bindings) {
        return [evaluatedObject isKindOfClass:[ZMSystemMessage class]] && [(ZMSystemMessage *)evaluatedObject systemMessageType] == ZMSystemMessageTypeNewConversation;
    }]].array;
    
    XCTAssertEqual(messages.count, 1u);
}

@end




@implementation ZMConversationTranscoderTests (Participants)

- (void)testThatItRemovesUsersFromAConversationAfterAPushEvent
{
    // given
    NSUUID* conversationID = [NSUUID createUUID];
    
    __block ZMConversation *conversation;
    __block NSUUID* userID;
    __block ZMUser *nonRemovedUser;
    __block ZMUser *removedUser;
    
    [self.syncMOC performGroupedBlockAndWait:^{
        removedUser = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        removedUser.remoteIdentifier = [NSUUID createUUID];
        userID = removedUser.remoteIdentifier;
        
        nonRemovedUser = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        nonRemovedUser.remoteIdentifier = [NSUUID createUUID];
        
        conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        conversation.conversationType = ZMConversationTypeGroup;
        conversation.remoteIdentifier = conversationID;
        [conversation addParticipant:removedUser];
        [conversation addParticipant:nonRemovedUser];
        
        XCTAssertEqual(conversation.otherActiveParticipants.count, 2u);
    }];
    
    NSDictionary *payload = [self responsePayloadForUserEventInConversationID:conversationID userIDs:@[userID] eventType:@"conversation.member-leave"];
    // when
    [self.syncMOC performGroupedBlockAndWait:^{
        [self.sut processEvents:@[[ZMUpdateEvent eventFromEventStreamPayload:payload uuid:nil]] liveEvents:YES prefetchResult:nil];
    }];
    
    // then
    [self.syncMOC performGroupedBlockAndWait:^{
        XCTAssertEqual(conversation.otherActiveParticipants.count, 1u);
        XCTAssertEqualObjects(conversation.otherActiveParticipants.firstObject, nonRemovedUser);
        
    }];
}


- (void)testThatItDoesNotArchiveAConversationAfterAPushEventWhenRemovingTheSelfUser
{
    // given
    NSUUID* conversationID = [NSUUID createUUID];
    
    __block ZMConversation *conversation;
    __block NSUUID* userID;
    __block ZMUser *selfUser;
    
    [self.syncMOC performGroupedBlockAndWait:^{
        selfUser = [ZMUser selfUserInContext:self.syncMOC];
        selfUser.remoteIdentifier = [NSUUID createUUID];
        userID = selfUser.remoteIdentifier;
        
        conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        conversation.conversationType = ZMConversationTypeGroup;
        conversation.remoteIdentifier = conversationID;
        [self.syncMOC saveOrRollback];
        
        XCTAssertTrue(conversation.isSelfAnActiveMember);
        XCTAssertFalse(conversation.isArchived);
    }];
    
    NSDictionary *payload = [self responsePayloadForUserEventInConversationID:conversationID userIDs:@[userID] eventType:@"conversation.member-leave"];
    
    // when
    [self.syncMOC performGroupedBlockAndWait:^{
        [self.sut processEvents:@[[ZMUpdateEvent eventFromEventStreamPayload:payload uuid:nil]] liveEvents:YES prefetchResult:nil];
    }];
    
    // then
    [self.syncMOC performGroupedBlockAndWait:^{
        XCTAssertFalse(conversation.isSelfAnActiveMember);
        XCTAssertFalse(conversation.isArchived);
    }];
}


- (void)testThatItCreatesARequestForRemovingAParticipant
{
    // given
    NSString *modifiedKey = ZMConversationUnsyncedInactiveParticipantsKey;
    NSSet *keys = [NSSet setWithObject:modifiedKey];
    NSUUID *user3ID = [NSUUID createUUID];
    NSUUID *conversationID = [NSUUID createUUID];
    __block ZMConversation *conversation;
    
    [self.syncMOC performBlockAndWait:^{
        ZMUser *selfUser = [ZMUser selfUserInContext:self.syncMOC];
        selfUser.remoteIdentifier = self.selfUserID;
        
        ZMUser *user1 = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        user1.remoteIdentifier = [NSUUID createUUID];
        
        ZMUser *user2 = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        user2.remoteIdentifier = [NSUUID createUUID];
        
        ZMUser *user3 = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        user3.remoteIdentifier = user3ID;
        
        conversation = [ZMConversation insertGroupConversationIntoManagedObjectContext:self.syncMOC withParticipants:@[user1, user2, user3]];
        conversation.remoteIdentifier = conversationID;
        
        [conversation synchronizeAddedUser:user1];
        [conversation synchronizeAddedUser:user2];
        [conversation synchronizeAddedUser:user3];
        
        [conversation removeParticipant:user3];
        [conversation setLocallyModifiedKeys:keys];
        
        [self.syncMOC saveOrRollback];
    }];
    
    
    for (id<ZMContextChangeTracker> tracker in self.sut.contextChangeTrackers) {
        [tracker objectsDidChange:[NSSet setWithObject:conversation]];
    }
    
    ZMTransportRequest *request = [self.sut nextRequest];
    XCTAssertNotNil(request);
    XCTAssertNotNil(request.expirationDate);
    
    // when
    NSDictionary *responsePayload = [self responsePayloadForUserEventInConversationID:conversationID userIDs:@[user3ID] eventType:@"conversation.member-leave"];
    ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:responsePayload HTTPStatus:200 transportSessionError:nil];
    [request completeWithResponse:response];
    WaitForAllGroupsToBeEmpty(0.5);
    
    [self.syncMOC saveOrRollback];
    
    // then
    XCTAssertEqual(request.method, ZMMethodDELETE);
    NSString *expectedPath = [NSString pathWithComponents:@[ @"/", @"conversations", conversationID.transportString, @"members", user3ID.transportString ]];
    XCTAssertEqualObjects(request.path, expectedPath);
    
    XCTAssertFalse([conversation.keysThatHaveLocalModifications containsObject:modifiedKey]);
    
    XCTAssertEqual(self.downloadedEvents.count, 1u);
    ZMUpdateEvent *downloadedEvent = self.downloadedEvents.firstObject;
    XCTAssertEqualObjects(downloadedEvent.payload, responsePayload);
    
    
}

- (void)testThatItCreatesSeveralRequestsForRemovingSeveralParticipants
{
    // given
    NSString *modifiedKey = ZMConversationUnsyncedInactiveParticipantsKey;
    NSSet *keys = [NSSet setWithObject:modifiedKey];
    NSUUID *user2ID = [NSUUID createUUID];
    NSUUID *user3ID = [NSUUID createUUID];
    NSUUID *conversationID = [NSUUID createUUID];
    __block ZMConversation *conversation;
    
    [self.syncMOC performBlockAndWait:^{
        ZMUser *user1 = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        user1.remoteIdentifier = [NSUUID createUUID];
        
        ZMUser *user2 = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        user2.remoteIdentifier = user2ID;
        
        ZMUser *user3 = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        user3.remoteIdentifier = user3ID;
        
        conversation = [ZMConversation insertGroupConversationIntoManagedObjectContext:self.syncMOC withParticipants:@[user1, user2, user3]];
        conversation.remoteIdentifier = conversationID;
        
        [conversation synchronizeAddedUser:user1];
        [conversation synchronizeAddedUser:user2];
        [conversation synchronizeAddedUser:user3];
        
        [conversation resetLocallyModifiedKeys:keys];
        
        [conversation removeParticipant:user3];
        [conversation removeParticipant:user2];
        
        [conversation setLocallyModifiedKeys:keys];
        
        [self.syncMOC saveOrRollback];
    }];
    
    
    for (id<ZMContextChangeTracker> tracker in self.sut.contextChangeTrackers) {
        [tracker objectsDidChange:[NSSet setWithObject:conversation]];
    }
    
    NSDictionary *responsePayload = [self responsePayloadForUserEventInConversationID:conversationID userIDs:@[user2ID] eventType:@"conversation.member-leave"];
    ZMTransportResponse *response1 = [ZMTransportResponse responseWithPayload:responsePayload HTTPStatus:200 transportSessionError:nil];
    responsePayload = [self responsePayloadForUserEventInConversationID:conversationID userIDs:@[user3ID] eventType:@"conversation.member-leave"];
    ZMTransportResponse *response2 = [ZMTransportResponse responseWithPayload:responsePayload HTTPStatus:200 transportSessionError:nil];
    
    // when
    ZMTransportRequest *request1 = [self.sut nextRequest];
    [request1 completeWithResponse:response1];
    WaitForAllGroupsToBeEmpty(0.5);
    ZMTransportRequest *request2 = [self.sut nextRequest];
    [request2 completeWithResponse:response2];
    WaitForAllGroupsToBeEmpty(0.5);
    ZMTransportRequest *request3 = [self.sut nextRequest];
    WaitForAllGroupsToBeEmpty(0.5);
    
    [self.syncMOC saveOrRollback];
    
    // then
    XCTAssertEqual(request1.method, ZMMethodDELETE);
    NSString *expectedPath1 = [NSString pathWithComponents:@[ @"/", @"conversations", conversationID.transportString, @"members", user2ID.transportString ]];
    XCTAssertEqualObjects(request1.path, expectedPath1);
    
    XCTAssertEqual(request2.method, ZMMethodDELETE);
    NSString *expectedPath2 = [NSString pathWithComponents:@[ @"/", @"conversations", conversationID.transportString, @"members", user3ID.transportString ]];
    XCTAssertEqualObjects(request2.path, expectedPath2);
    
    XCTAssertNil(request3);
    
    XCTAssertFalse([conversation.keysThatHaveLocalModifications containsObject:modifiedKey]);
}

- (void)testThatItCreatesARequestsForRemovingSelf
{
    // given
    NSString *modifiedKey = ZMConversationIsSelfAnActiveMemberKey;
    NSSet *keys = [NSSet setWithObject:modifiedKey];
    NSUUID *conversationID = [NSUUID createUUID];
    __block ZMConversation *conversation;
    __block ZMTransportRequest *request;
    
    [self.syncMOC performBlockAndWait:^{
        ZMUser *user1 = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        user1.remoteIdentifier = [NSUUID createUUID];
        
        ZMUser *user2 = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        user2.remoteIdentifier = [NSUUID createUUID];
        
        ZMUser *selfUser = [ZMUser selfUserInContext:self.syncMOC];
        selfUser.remoteIdentifier = self.selfUserID;
        
        conversation = [ZMConversation insertGroupConversationIntoManagedObjectContext:self.syncMOC withParticipants:@[user1, user2]];
        conversation.remoteIdentifier = conversationID;
        
        [conversation synchronizeAddedUser:user1];
        [conversation synchronizeAddedUser:user2];
        
        [conversation resetLocallyModifiedKeys:keys];
        
        conversation.isSelfAnActiveMember = NO;
        [conversation setLocallyModifiedKeys:keys];
        
        [self.syncMOC saveOrRollback];
        
        for (id<ZMContextChangeTracker> tracker in self.sut.contextChangeTrackers) {
            [tracker objectsDidChange:[NSSet setWithObject:conversation]];
        }
        
        NSDictionary *responsePayload = [self responsePayloadForUserEventInConversationID:conversationID userIDs:@[self.selfUserID] eventType:@"conversation.member-leave"];
        ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:responsePayload HTTPStatus:200 transportSessionError:nil];
        
        // when
        request = [self.sut nextRequest];
        [request completeWithResponse:response];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    [self.syncMOC performGroupedBlockAndWait:^{
        
        // then
        XCTAssertNotNil(request);
        XCTAssertEqual(request.method, ZMMethodDELETE);
        NSString *expectedPath = [NSString pathWithComponents:@[ @"/", @"conversations", conversationID.transportString, @"members", self.selfUserID.transportString ]];
        XCTAssertEqualObjects(request.path, expectedPath);
        XCTAssertNil(request.payload);
        XCTAssertFalse([conversation.keysThatHaveLocalModifications containsObject:modifiedKey]);
    }];
}

- (void)testThatItSetsAndSyncsTheLastReadTimestampWhenRemovingSelf
{
    // given
    NSSet *keys = [NSSet setWithObject:ZMConversationIsSelfAnActiveMemberKey];
    NSUUID *conversationID = [NSUUID createUUID];
    __block ZMConversation *conversation;
    __block ZMTransportRequest *request;
    __block NSDate *lastReadTimeStamp;

    [self.syncMOC performBlockAndWait:^{
        ZMUser *user1 = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        user1.remoteIdentifier = [NSUUID createUUID];
        
        ZMUser *user2 = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        user2.remoteIdentifier = [NSUUID createUUID];
        
        ZMUser *selfUser = [ZMUser selfUserInContext:self.syncMOC];
        selfUser.remoteIdentifier = self.selfUserID;
        
        conversation = [ZMConversation insertGroupConversationIntoManagedObjectContext:self.syncMOC withParticipants:@[user1, user2]];
        conversation.remoteIdentifier = conversationID;
        conversation.lastReadServerTimeStamp = [[NSDate date] dateByAddingTimeInterval:-20];
        [conversation synchronizeAddedUser:user1];
        [conversation synchronizeAddedUser:user2];
        
        [conversation resetLocallyModifiedKeys:keys];
        
        conversation.isSelfAnActiveMember = NO;
        [conversation setLocallyModifiedKeys:keys];
        
        [self.syncMOC saveOrRollback];
        
        for (id<ZMContextChangeTracker> tracker in self.sut.contextChangeTrackers) {
            [tracker objectsDidChange:[NSSet setWithObject:conversation]];
        }
        
        NSDictionary *responsePayload = [self responsePayloadForUserEventInConversationID:conversationID userIDs:@[self.selfUserID] eventType:@"conversation.member-leave"];
        ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:responsePayload HTTPStatus:200 transportSessionError:nil];
        
        lastReadTimeStamp = [responsePayload dateForKey:@"time"];

        // when
        request = [self.sut nextRequest];
        [request completeWithResponse:response];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    [self.syncMOC performGroupedBlockAndWait:^{
        
        // then
        XCTAssertEqualWithAccuracy([conversation.lastReadServerTimeStamp timeIntervalSince1970], [lastReadTimeStamp timeIntervalSince1970], 0.1);
        XCTAssertTrue([conversation.keysThatHaveLocalModifications containsObject:ZMConversationLastReadServerTimeStampKey]);
    }];
}

- (void)testThatClearedEventIDAndTimestampAreUpdatedWhenRemovingSelfAndLastMessageIsCleared
{
    // given
    NSSet *keys = [NSSet setWithArray:@[ZMConversationArchivedChangedTimeStampKey, ZMConversationIsSelfAnActiveMemberKey]];

    ZMConversation * conversation = [self setupConversation];
    [conversation clearMessageHistory];
    [self.uiMOC saveOrRollback];
    [conversation resetLocallyModifiedKeys:conversation.keysThatHaveLocalModifications];
    
    // when
    conversation.isSelfAnActiveMember = NO;
    [self.uiMOC saveOrRollback];
    [self.syncMOC refreshAllObjects];
    XCTAssertTrue([conversation hasLocalModificationsForKeys:keys]);

    NSDictionary *responsePayload = [self responsePayloadForUserEventInConversationID:conversation.remoteIdentifier userIDs:@[self.selfUserID] eventType:@"conversation.member-leave"];
    ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:responsePayload HTTPStatus:200 transportSessionError:nil];
    (void)[self requestToSyncConversation:conversation andCompleteWithResponse:response];
    
    [self.syncMOC performGroupedBlockAndWait:^{
        // then
        ZMConversation *synConv = [(id)self.syncMOC objectWithID:conversation.objectID];
        NSDate *lastTimeStamp = [responsePayload dateForKey:@"time"];
        XCTAssertEqualWithAccuracy([synConv.lastReadServerTimeStamp timeIntervalSince1970], [lastTimeStamp timeIntervalSince1970], 1.0);
        
        XCTAssertEqualObjects(synConv.clearedTimeStamp, lastTimeStamp);
    }];
}

- (void)testThatClearedEventIDIsNotUpdatedWhenRemovingSelfAndLastMessageIsntCleared
{
    // given
    NSSet *keys = [NSSet setWithObject:ZMConversationIsSelfAnActiveMemberKey];
    NSUUID *conversationID = [NSUUID createUUID];
    __block ZMConversation *conversation;
    __block ZMTransportRequest *request;
    __block NSString *orignalClearedTimestampString;

    [self.syncMOC performBlockAndWait:^{
        ZMUser *user1 = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        user1.remoteIdentifier = [NSUUID createUUID];
        
        ZMUser *user2 = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        user2.remoteIdentifier = [NSUUID createUUID];
        
        ZMUser *selfUser = [ZMUser selfUserInContext:self.syncMOC];
        selfUser.remoteIdentifier = self.selfUserID;
        
        conversation = [ZMConversation insertGroupConversationIntoManagedObjectContext:self.syncMOC withParticipants:@[user1, user2]];
        conversation.remoteIdentifier = conversationID;
        
        [conversation synchronizeAddedUser:user1];
        [conversation synchronizeAddedUser:user2];
        
        [conversation resetLocallyModifiedKeys:keys];
        
        conversation.isSelfAnActiveMember = NO;
        [conversation setLocallyModifiedKeys:keys];
        
        ZMMessage *message1 = (id)[conversation appendMessageWithText:@"message 1"];
        [conversation appendMessageWithText:@"message 2"];
        
        conversation.clearedTimeStamp = message1.serverTimestamp;
        orignalClearedTimestampString = conversation.clearedTimeStamp.transportString;
        
        [self.syncMOC saveOrRollback];
        
        for (id<ZMContextChangeTracker> tracker in self.sut.contextChangeTrackers) {
            [tracker objectsDidChange:[NSSet setWithObject:conversation]];
        }
        
        NSDictionary *responsePayload = [self responsePayloadForUserEventInConversationID:conversationID userIDs:@[self.selfUserID] eventType:@"conversation.member-leave"];
        ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:responsePayload HTTPStatus:200 transportSessionError:nil];
        
        // when
        request = [self.sut nextRequest];
        [request completeWithResponse:response];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    [self.syncMOC performGroupedBlockAndWait:^{
        // then
        XCTAssertEqualObjects(conversation.clearedTimeStamp.transportString, orignalClearedTimestampString);
        XCTAssertFalse([conversation.keysThatHaveLocalModifications containsObject:ZMConversationClearedTimeStampKey]);
    }];
}

- (void)testThatItCreatesARequestForAddingAParticipant
{
    // given
    NSString *modifiedKey = ZMConversationUnsyncedActiveParticipantsKey;
    NSSet *keys = [NSSet setWithObject:modifiedKey];
    NSUUID *user3ID = [NSUUID createUUID];
    NSUUID *conversationID = [NSUUID createUUID];
    __block ZMConversation *conversation;
    __block ZMTransportRequest *request;
    __block NSDictionary *responsePayload;
    
    [self.syncMOC performBlockAndWait:^{
        ZMUser *selfUser = [ZMUser selfUserInContext:self.syncMOC];
        selfUser.remoteIdentifier = self.selfUserID;
        
        ZMUser *user1 = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        user1.remoteIdentifier = [NSUUID createUUID];
        
        ZMUser *user2 = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        user2.remoteIdentifier = [NSUUID createUUID];
        
        ZMUser *user3 = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        user3.remoteIdentifier = user3ID;
        
        conversation = [ZMConversation insertGroupConversationIntoManagedObjectContext:self.syncMOC withParticipants:@[user1, user2]];
        conversation.remoteIdentifier = conversationID;
        
        [conversation synchronizeAddedUser:user1];
        [conversation synchronizeAddedUser:user2];
        
        [conversation addParticipant:user3];
        [conversation setLocallyModifiedKeys:keys];
        
        [self.syncMOC saveOrRollback];
        
        for (id<ZMContextChangeTracker> tracker in self.sut.contextChangeTrackers) {
            [tracker objectsDidChange:[NSSet setWithObject:conversation]];
        }
        
        
        request = [self.sut nextRequest];
        XCTAssertNotNil(request);
        XCTAssertNotNil(request.expirationDate);
        
        // when
        responsePayload = [self responsePayloadForUserEventInConversationID:conversationID userIDs:@[user3ID] eventType:@"conversation.member-join"];
        ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:responsePayload HTTPStatus:200 transportSessionError:nil];
        [request completeWithResponse:response];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    [self.syncMOC performGroupedBlockAndWait:^{
        [self.syncMOC saveOrRollback];
        
        // then
        XCTAssertEqual(request.method, ZMMethodPOST);
        NSString *expectedPath = [NSString pathWithComponents:@[ @"/", @"conversations", conversationID.transportString, @"members" ]];
        XCTAssertEqualObjects(request.path, expectedPath);
        XCTAssertEqualObjects(request.payload, @{ @"users": @[ user3ID.transportString ] });
        
        XCTAssertFalse([conversation.keysThatHaveLocalModifications containsObject:modifiedKey]);
        
        XCTAssertEqual(self.downloadedEvents.count, 1u);
        ZMUpdateEvent *downloadedEvent = self.downloadedEvents.firstObject;
        XCTAssertEqualObjects(downloadedEvent.payload, responsePayload);
    }];
}

- (void)testThatItAddsUsersToAConversationAfterAPushEvent
{
    // given
    __block ZMConversation *conversation;
    NSUUID* conversationID = [NSUUID createUUID];
    NSUUID* userID = [NSUUID createUUID];
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMUser *user1 = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        user1.remoteIdentifier = [NSUUID createUUID];
        
        ZMUser *user2 = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        user2.remoteIdentifier = [NSUUID createUUID];
        
        conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        conversation.conversationType = ZMConversationTypeGroup;
        conversation.remoteIdentifier = conversationID;
        [conversation addParticipant:user1];
        [conversation addParticipant:user2];
        
        XCTAssertEqual(conversation.otherActiveParticipants.count, 2u);
        
        NSDictionary *payload = [self responsePayloadForUserEventInConversationID:conversationID userIDs:@[userID] eventType:@"conversation.member-join"];
        
        // when
        [self.sut processEvents:@[[ZMUpdateEvent eventFromEventStreamPayload:payload uuid:nil]] liveEvents:YES prefetchResult:nil];
        
        // then
        XCTAssertEqual(conversation.otherActiveParticipants.count, 3u);
    }];
}



- (void)testThatItCreatesARequestsForAddingSeveralParticipants
{
    // given
    NSString *modifiedKey = ZMConversationUnsyncedActiveParticipantsKey;
    NSSet *keys = [NSSet setWithObject:modifiedKey];
    NSUUID *user4ID = [NSUUID createUUID];
    NSUUID *user5ID = [NSUUID createUUID];
    NSUUID *conversationID = [NSUUID createUUID];
    __block ZMConversation *conversation;
    __block ZMTransportRequest *request;
    __block ZMTransportResponse *response;
    
    [self.syncMOC performBlockAndWait:^{
        ZMUser *user1 = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        user1.remoteIdentifier = [NSUUID createUUID];
        
        ZMUser *user2 = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        user2.remoteIdentifier = [NSUUID createUUID];
        
        ZMUser *user3 = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        user3.remoteIdentifier = [NSUUID createUUID];
        
        ZMUser *user4 = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        user4.remoteIdentifier = user4ID;
        
        ZMUser *user5 = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        user5.remoteIdentifier = user5ID;
        
        
        conversation = [ZMConversation insertGroupConversationIntoManagedObjectContext:self.syncMOC withParticipants:@[user1, user2, user3]];
        conversation.remoteIdentifier = conversationID;
        
        [conversation synchronizeAddedUser:user1];
        [conversation synchronizeAddedUser:user2];
        [conversation synchronizeAddedUser:user3];
        
        [conversation resetLocallyModifiedKeys:keys];
        
        [conversation addParticipant:user4];
        [conversation addParticipant:user5];
        
        [conversation setLocallyModifiedKeys:keys];
        
        [self.syncMOC saveOrRollback];
        
        
        for (id<ZMContextChangeTracker> tracker in self.sut.contextChangeTrackers) {
            [tracker objectsDidChange:[NSSet setWithObject:conversation]];
        }
        
        NSDictionary *responsePayload = [self responsePayloadForUserEventInConversationID:conversationID userIDs:@[user4ID, user4ID] eventType:@"conversation.member-join"];
        response = [ZMTransportResponse responseWithPayload:responsePayload HTTPStatus:200 transportSessionError:nil];
        
        // when
        request = [self.sut nextRequest];
        [request completeWithResponse:response];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    __block ZMTransportRequest *request2;
    [self.syncMOC performGroupedBlockAndWait:^{
        request2 = [self.sut nextRequest];
        [request2 completeWithResponse:response];
    }];
    
    WaitForAllGroupsToBeEmpty(0.5);
    [self.syncMOC performGroupedBlockAndWait:^{
        [self.syncMOC saveOrRollback];
        
        // then
        XCTAssertEqual(request.method, ZMMethodPOST);
        NSString *expectedPath = [NSString pathWithComponents:@[ @"/", @"conversations", conversationID.transportString, @"members" ]];
        XCTAssertEqualObjects(request.path, expectedPath);
        NSDictionary *expectedPayload =  @{ @"users": @[ user4ID.transportString, user5ID.transportString ] };
        XCTAssertEqualObjects(request.payload, expectedPayload);
        XCTAssertNil(request2);
        
        XCTAssertFalse([conversation.keysThatHaveLocalModifications containsObject:modifiedKey]);
    }];
}

- (void)testThatItMarksTheConversationAsNeedingToBeUpdatedWhenTheSelfUserIsAdded
{
    [self.syncMOC performBlockAndWait:^{
        // given
        
        // A conversation that we were previously in:
        NSUUID *conversationID = [NSUUID createUUID];
        ZMUser *selfUser = [ZMUser selfUserInContext:self.syncMOC];
        selfUser.remoteIdentifier = self.selfUserID;
        ZMUser *user1 = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        user1.remoteIdentifier = [NSUUID createUUID];
        
        ZMUser *user2 = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        user2.remoteIdentifier = [NSUUID createUUID];
        
        ZMUser *user3 = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        user3.remoteIdentifier = [NSUUID createUUID];
        
        ZMConversation *conversation = [ZMConversation insertGroupConversationIntoManagedObjectContext:self.syncMOC withParticipants:@[user1, user2, user3]];
        conversation.remoteIdentifier = conversationID;
        
        [conversation synchronizeAddedUser:user1];
        [conversation synchronizeAddedUser:user2];
        [conversation synchronizeAddedUser:user3];
        
        conversation.isSelfAnActiveMember = NO;
        
        [conversation resetLocallyModifiedKeys:conversation.keysThatHaveLocalModifications];
        XCTAssert([self.syncMOC save:nil]);
        
        // when
        for (id<ZMContextChangeTracker> t in self.sut.contextChangeTrackers) {
            [t objectsDidChange:[NSSet setWithObject:conversation]];
        }
        ZMTransportRequest *request = [self.sut nextRequest];
        
        // then
        XCTAssertNil(request);
        
        // and when (2)
        
        NSDictionary *payload = [self responsePayloadForUserEventInConversationID:conversationID userIDs:@[self.selfUserID] eventType:@"conversation.member-join"];
        NSDictionary *joinPayload = @{@"id": NSUUID.createUUID.transportString,
                                      @"payload": @[payload]};
        NSArray *events = [ZMUpdateEvent eventsArrayFromPushChannelData:joinPayload];
        for (ZMUpdateEvent *e in events) {
            [self.sut processEvents:@[e] liveEvents:YES prefetchResult:nil];
        }
        
        // then
        XCTAssertEqualObjects(conversation.keysThatHaveLocalModifications, [NSSet set]);
        XCTAssertTrue(conversation.isSelfAnActiveMember);
        XCTAssertTrue(conversation.needsToBeUpdatedFromBackend);
        ZMTransportRequest *request2 = [self.sut nextRequest];
        XCTAssertNil(request2);
    }];
}

- (void)testThatWhenARequestToRemoveAParticipantFailsWithAPermanentErrorItDoesNotRequestItAgain
{
    // given
    NSString *modifiedKey = ZMConversationUnsyncedInactiveParticipantsKey;
    NSSet *keys = [NSSet setWithObject:modifiedKey];
    __block ZMConversation *conversation;
    __block ZMTransportRequest *request1;
    [self.syncMOC performBlockAndWait:^{
        ZMUser *user1 = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        user1.remoteIdentifier = [NSUUID createUUID];
        
        ZMUser *user2 = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        user2.remoteIdentifier = [NSUUID createUUID];
        
        conversation = [ZMConversation insertGroupConversationIntoManagedObjectContext:self.syncMOC withParticipants:@[user1, user2]];
        conversation.remoteIdentifier = [NSUUID createUUID];
        
        [conversation synchronizeAddedUser:user1];
        [conversation synchronizeAddedUser:user2];
        
        [conversation resetLocallyModifiedKeys:keys];
        
        [conversation removeParticipant:user2];
        
        [conversation setLocallyModifiedKeys:keys];
        
        [self.syncMOC saveOrRollback];
        
        
        for (id<ZMContextChangeTracker> tracker in self.sut.contextChangeTrackers) {
            [tracker objectsDidChange:[NSSet setWithObject:conversation]];
        }
        
        ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:nil HTTPStatus:403 transportSessionError:nil];
        
        // when
        request1 = [self.sut nextRequest];
        [request1 completeWithResponse:response];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    [self.syncMOC performGroupedBlockAndWait:^{
        // then
        XCTAssertTrue(conversation.needsToBeUpdatedFromBackend);
        
        // and when
        // it resyncs the conversation
        ZM_ALLOW_MISSING_SELECTOR(ZMTransportRequest *request = [self.sut.requestGenerators firstNonNilReturnedFromSelector:@selector(nextRequest)];)
        XCTAssertNotNil(request);
        XCTAssertEqual(request.method, ZMMethodGET);
        
        NSDictionary *metaData = [self conversationMetaDataForConversation:conversation.remoteIdentifier selfID:[NSUUID createUUID] otherUserID:[NSUUID createUUID] isArchived:NO isSelfAnActiveMember:NO];
        [request completeWithResponse:[ZMTransportResponse responseWithPayload:metaData HTTPStatus:200 transportSessionError:nil]];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    [self.syncMOC performGroupedBlockAndWait:^{
        // then
        XCTAssertFalse(conversation.needsToBeUpdatedFromBackend);
        
        // and when
        // it does not create a new request for the selfUser leaving
        ZM_ALLOW_MISSING_SELECTOR(ZMTransportRequest *request = [self.sut.requestGenerators firstNonNilReturnedFromSelector:@selector(nextRequest)];)
        XCTAssertNil(request);
    }];
}

- (void)testThatAConversationIsMarkedAsNeedToBeUpdatedIfItFailedToUpload
{
    [self.syncMOC performBlockAndWait:^{
        // given
        ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
       
        // when
        ZMManagedObject *object = [self.sut objectToRefetchForFailedUpdateOfObject:conversation];
        
        // then
        XCTAssertEqual(object, conversation);
    }];
}

@end



@implementation ZMConversationTranscoderTests (SilencedAndArchived)

- (void)testThatItSendsARequestWhenConversationIsSilenced
{
    [self checkThatItSendsARequestForIsSilenced:YES];
}


- (void)testThatItSendsARequestWhenConversationIsUnsilenced
{
    [self checkThatItSendsARequestForIsSilenced:NO];
}


- (void)testThatItSendsARequestWithANewTimestampWhenConversationIsSilencedWithNoSilencedTimestamp
{
    // given
    ZMConversation *conversation = [self setupConversation];
    
    // when
    conversation.isSilenced = YES;
    conversation.silencedChangedTimestamp = nil;
    [self.uiMOC saveOrRollback];

    ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:nil HTTPStatus:200 transportSessionError:nil];
    ZMTransportRequest *request = [self requestToSyncConversation:conversation andCompleteWithResponse:response];
    
    [self.uiMOC refreshObject:conversation mergeChanges:NO];
    XCTAssertNotNil(request);
    XCTAssertNotNil(conversation.silencedChangedTimestamp);
    
    // then
    XCTAssertEqual(request.method, ZMMethodPUT);
    NSString *expectedPath = [NSString pathWithComponents:@[ @"/", @"conversations", conversation.remoteIdentifier.transportString, @"self" ]];
    XCTAssertEqualObjects(request.path, expectedPath);
    
    NSDictionary *expected = @{ @"otr_muted_ref": conversation.silencedChangedTimestamp.transportString,
                                @"otr_muted" : @(YES)};
    XCTAssertEqualObjects(request.payload, expected);
}

- (void)checkThatItSendsARequestForIsSilenced:(BOOL)isSilenced
{
    // given
    NSString *modifiedKey = ZMConversationSilencedChangedTimeStampKey;
    NSSet *keys = [NSSet setWithObject:modifiedKey];
    
    ZMConversation *conversation =  [self setupConversation];
    conversation.isSilenced = isSilenced;
    XCTAssertEqualObjects(conversation.keysThatHaveLocalModifications, keys);
    [self.uiMOC saveOrRollback];
    
    ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:@{} HTTPStatus:200 transportSessionError:nil];
    ZMTransportRequest *request = [self requestToSyncConversation:conversation andCompleteWithResponse:response];
    
    [self.syncMOC performGroupedBlockAndWait:^{
        [self.syncMOC saveOrRollback];

        ZMConversation *syncConv = (id)[self.syncMOC objectWithID:conversation.objectID];

        // then
        XCTAssertEqual(request.method, ZMMethodPUT);
        NSString *expectedPath = [NSString pathWithComponents:@[ @"/", @"conversations", conversation.remoteIdentifier.transportString, @"self" ]];
        XCTAssertEqualObjects(request.path, expectedPath);
        NSDictionary *expected = @{ @"otr_muted": @(isSilenced),
                                    @"otr_muted_ref": syncConv.silencedChangedTimestamp.transportString
                                    };
        XCTAssertEqualObjects(request.payload, expected);
        
        XCTAssertFalse([syncConv.keysThatHaveLocalModifications containsObject:modifiedKey]);
    }];
}


- (void)testThatItSendsARequestWhenConversationIsArchived
{
    [self checkThatItSendsARequestForIsArchived:YES];
}

- (void)testThatItSendsARequestWhenConversationIsUnarchived
{
    [self checkThatItSendsARequestForIsArchived:NO];
}

- (void)testThatItSendsARequestWithANewTimestampWhenConversationIsArchivedWithNoArchivedTimestamp
{
    // given
    ZMConversation *conversation = [self setupConversation];
    
    // when
    conversation.isArchived = YES;
    conversation.archivedChangedTimestamp = nil;
    [self.uiMOC saveOrRollback];
    
    
    ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:nil HTTPStatus:200 transportSessionError:nil];
    ZMTransportRequest *request = [self requestToSyncConversation:conversation andCompleteWithResponse:response];
    
    [self.uiMOC refreshObject:conversation mergeChanges:NO];
    XCTAssertNotNil(request);
    XCTAssertNotNil(conversation.archivedChangedTimestamp);

    // then
    [self.uiMOC refreshObject:conversation mergeChanges:NO];
    XCTAssertEqual(request.method, ZMMethodPUT);
    NSString *expectedPath = [NSString pathWithComponents:@[ @"/", @"conversations", conversation.remoteIdentifier.transportString, @"self" ]];
    XCTAssertEqualObjects(request.path, expectedPath);
    
    NSDictionary *expected = @{ @"otr_archived_ref": conversation.archivedChangedTimestamp.transportString,
                                @"otr_archived" : @(YES)};
    XCTAssertEqualObjects(request.payload, expected);
}


- (void)checkThatItSendsARequestForIsArchived:(BOOL)isArchived
{
    // given
    NSString *modifiedKey = ZMConversationArchivedChangedTimeStampKey;
    NSSet *keys = [NSSet setWithObject:modifiedKey];
    
    ZMConversation *conversation = [self setupConversation];

    // when
    conversation.isArchived = isArchived;
    [self.uiMOC saveOrRollback];
    
    XCTAssertEqualObjects(conversation.keysThatHaveLocalModifications, keys);
    
    ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:nil HTTPStatus:200 transportSessionError:nil];
    ZMTransportRequest *request = [self requestToSyncConversation:conversation andCompleteWithResponse:response];
    
    [self.syncMOC performGroupedBlockAndWait:^{
        [self.syncMOC saveOrRollback];
        
        ZMConversation *syncConv = [(id)self.syncMOC objectWithID:conversation.objectID];
        // then
        XCTAssertEqual(request.method, ZMMethodPUT);
        NSString *expectedPath = [NSString pathWithComponents:@[ @"/", @"conversations", conversation.remoteIdentifier.transportString, @"self" ]];
        XCTAssertEqualObjects(request.path, expectedPath);
        
        NSDictionary *expected = @{ @"otr_archived_ref": syncConv.lastServerTimeStamp.transportString,
                                    @"otr_archived" : @(isArchived)};
        XCTAssertEqualObjects(request.payload, expected);
        
        XCTAssertFalse([syncConv.keysThatHaveLocalModifications containsObject:modifiedKey]);
    }];
}



- (void)testThatItCombinesUpdatesForMuteAndArchive
{
    // given
    NSString *modifiedKey1 = ZMConversationArchivedChangedTimeStampKey;
    NSString *modifiedKey2 = ZMConversationSilencedChangedTimeStampKey;
    __block ZMConversation *syncConv;
    __block ZMTransportResponse *response;
    __block ZMTransportRequest *request;
    __block ZMTransportRequest *request2;
    
    
    ZMConversation *conversation = [self setupConversation];
    conversation.isArchived = YES;
    conversation.isSilenced = YES;
    [self.uiMOC saveOrRollback];
    
    [self.syncMOC performBlockAndWait:^{
        syncConv = (id)[self.syncMOC objectWithID:conversation.objectID];
        XCTAssertTrue([syncConv.keysThatHaveLocalModifications containsObject:modifiedKey1]);
        XCTAssertTrue([syncConv.keysThatHaveLocalModifications containsObject:modifiedKey2]);
        
        for (id<ZMContextChangeTracker> tracker in self.sut.contextChangeTrackers) {
            [tracker objectsDidChange:[NSSet setWithObject:syncConv]];
        }
        
        request = [self.sut nextRequest];
        XCTAssertNotNil(request);
        
        request2 = [self.sut nextRequest];
        
        // when
        response = [ZMTransportResponse responseWithPayload:nil HTTPStatus:200 transportSessionError:nil];
        [request completeWithResponse:response];
    }];
    
    WaitForAllGroupsToBeEmpty(0.5);
    [self.syncMOC performGroupedBlockAndWait:^{
            
        // then
        XCTAssertEqual(request.method, ZMMethodPUT);
        NSString *expectedPath = [NSString pathWithComponents:@[ @"/", @"conversations", conversation.remoteIdentifier.transportString, @"self" ]];
        XCTAssertEqualObjects(request.path, expectedPath);
        XCTAssertEqualObjects(request.payload, (@{
                                                  ZMConversationInfoOTRArchivedReferenceKey: [conversation.lastServerTimeStamp transportString],
                                                  ZMConversationInfoOTRArchivedValueKey: @YES,
                                                  ZMConversationInfoOTRMutedReferenceKey: [conversation.lastServerTimeStamp transportString],
                                                  ZMConversationInfoOTRMutedValueKey: @YES,
                                                  }));
        
        XCTAssertFalse([syncConv.keysThatHaveLocalModifications containsObject:modifiedKey1]);
        XCTAssertFalse([syncConv.keysThatHaveLocalModifications containsObject:modifiedKey2]);
        
        XCTAssertNil(request2);
    }];
}



- (void)checkThatItProcessesUpdateEventForIsSilencedBefore:(BOOL)isSilencedBefore
                                           isSilencedAfter:(BOOL)isSilencedAfter
                                                      data:(NSDictionary *)data
{
    // given
    __block ZMConversation *conversation;
    NSUUID* conversationID = [NSUUID createUUID];
    
    [self.syncMOC performGroupedBlockAndWait:^{
        conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        conversation.remoteIdentifier = conversationID;
        conversation.isSilenced = isSilencedBefore;
        
        NSDictionary *payload = @{
                                  @"conversation" : conversation.remoteIdentifier.transportString,
                                  @"data" : data,
                                  @"from" : @"08316f5e-3c0a-4847-a235-2b4d93f291a4",
                                  @"time" : @"2014-08-07T13:19:42.394Z",
                                  @"type" : @"conversation.member-update",
                                  };
        
        ZMUpdateEvent *updateEvent = [ZMUpdateEvent eventFromEventStreamPayload:payload uuid:nil];
        XCTAssertNotNil(updateEvent);
        
        // when
        [self.sut processEvents:@[updateEvent] liveEvents:YES prefetchResult:nil];
        
        // then
        XCTAssertEqual(conversation.isSilenced, isSilencedAfter);
    }];
}


- (void)testThatItDoesNotSetIsSilencedFromNonOTRPayload
{
    [self checkThatItProcessesUpdateEventForIsSilencedBefore:NO isSilencedAfter:NO data:@{
                                                                                           @"muted" : @YES
                                                                                           }];
}



- (void)testThatItDoesNotUpdateIsSilencedIfItIsNotInThePayload
{
    [self checkThatItProcessesUpdateEventForIsSilencedBefore:YES isSilencedAfter:YES data:@{}];
}





- (ZMConversation *)checkThatItProcessesUpdateEventForIsArchivedBefore:(BOOL)isArchivedBefore
                                                       isArchivedAfter:(BOOL)isArchivedAfter
                                                                  data:(NSDictionary *)data
{
    // given
    __block ZMConversation *conversation;
    NSUUID* conversationID = [NSUUID createUUID];
    
    [self.syncMOC performGroupedBlockAndWait:^{
        conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        conversation.remoteIdentifier = conversationID;
        conversation.isArchived = isArchivedBefore;
        
        NSDictionary *payload = @{
                                  @"conversation" : conversation.remoteIdentifier.transportString,
                                  @"data" : data,
                                  @"from" : @"08316f5e-3c0a-4847-a235-2b4d93f291a4",
                                  @"time" : @"2014-08-07T13:19:42.394Z",
                                  @"type" : @"conversation.member-update",
                                  };
        
        ZMUpdateEvent *updateEvent = [ZMUpdateEvent eventFromEventStreamPayload:payload uuid:nil];
        XCTAssertNotNil(updateEvent);
        
        // when
        [self.sut processEvents:@[updateEvent] liveEvents:YES prefetchResult:nil];
        
        // then
        XCTAssertEqual(conversation.isArchived, isArchivedAfter);
    }];
    
    return conversation;
}


- (void)testThatItSetsIsArchivedAndArchivedChangedTimestampFromPayload
{
    NSDate *archivedDate = [NSDate date];
    ZMConversation *conversation = [self checkThatItProcessesUpdateEventForIsArchivedBefore:NO
                                                                            isArchivedAfter:YES
                                                                                       data:@{ @"otr_archived" : @1,
                                                                                               @"otr_archived_ref" : archivedDate.transportString}];
    [self.syncMOC performGroupedBlockAndWait:^{
        XCTAssertEqualWithAccuracy([archivedDate timeIntervalSince1970], [conversation.archivedChangedTimestamp timeIntervalSince1970], 1.0);
    }];
}


- (void)testThatItResetsIsArchivedFromNullPayload
{
    NSDate *unarchivedDate = [NSDate date];
    ZMConversation *conversation = [self checkThatItProcessesUpdateEventForIsArchivedBefore:YES
                                             isArchivedAfter:NO
                                                        data:@{@"otr_archived" : @0,
                                                               @"otr_archived_ref" : unarchivedDate.transportString}];
    [self.syncMOC performGroupedBlockAndWait:^{
        XCTAssertEqualWithAccuracy([unarchivedDate timeIntervalSince1970], [conversation.archivedChangedTimestamp timeIntervalSince1970], 1.0);
    }];
    
}

- (void)testThatItResetsIsArchivedFromFalsePayload
{
    [self checkThatItProcessesUpdateEventForIsArchivedBefore:YES isArchivedAfter:YES data:@{
                                                                                           @"archived" : @"false"
                                                                                           }];
}



- (void)testThatItDoesNotUpdateIsArchivedIfItIsNotInThePayload
{
    [self checkThatItProcessesUpdateEventForIsArchivedBefore:YES isArchivedAfter:YES data:@{}];
}


@end




@implementation ZMConversationTranscoderTests (UpdateEvents)

- (void)testThatItProcessesConversationCreateEvents
{
    // given
    NSUUID *remoteID = [NSUUID createUUID];
    NSDictionary *innerPayload = @{
                                   @"last_event_time" : @"2014-04-30T16:30:16.625Z",
                                   @"name" : @"foobarz",
                                   @"creator" : @"3bc5750a-b965-40f8-aff2-831e9b5ac2e9",
                                   @"last_event" : @"5.800112314308490f",
                                   @"members" : @{
                                           @"self" : @{
                                                   @"status" : @0,
                                                   @"muted_time" : [NSNull null],
                                                   @"status_ref" : @"0.0",
                                                   @"last_read" : @"5.800112314308490f",
                                                   @"muted" : [NSNull null],
                                                   @"archived" : [NSNull null],
                                                   @"status_time" : @"2014-03-14T16:47:37.573Z",
                                                   @"id" : @"3bc5750a-b965-40f8-aff2-831e9b5ac2e9",
                                                   },
                                           @"others" : @[]
                                           },
                                   @"type" : @0,
                                   @"id" : remoteID.transportString,
                                   };
    
    
    NSDictionary *payload = @{
                              @"type" : @"conversation.create",
                              @"data" : innerPayload
                              };
    
    ZMUpdateEvent *event = [OCMockObject mockForClass:[ZMUpdateEvent class]];
    (void)[(ZMUpdateEvent *)[[(id)event stub] andReturnValue:OCMOCK_VALUE(ZMUpdateEventConversationCreate)] type];
    (void)[(ZMUpdateEvent *)[[(id)event stub] andReturn:payload] payload];
    
    [self.syncMOC performGroupedBlockAndWait:^{
        
        
        // when
        [self.sut processEvents:@[event] liveEvents:YES prefetchResult:nil];
        
        // then
        ZMConversation *conversation = [ZMConversation conversationWithRemoteID:remoteID createIfNeeded:NO inContext:self.syncMOC];
        XCTAssertNotNil(conversation);
        XCTAssertTrue([self isConversation:conversation matchingPayload:innerPayload]);
    }];
}

- (void)testThatItUpdatesTheConversationTypeWhenProcessingConversationCreateEventForConnection;
{
    // When a one-on-one is create on the server (due to auto-connect) we 1st receive a "conversation.connect-request"
    // which triggers the conversation to get created locally with needsToBeUpdatedFromBackend set
    // We _must_ reset this to the type in the payload once we receive the "conversation.create".
    
    // given
    NSUUID *remoteID = NSUUID.createUUID;
    __block NSManagedObjectID *localID;
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMConversation *conversation = [ZMConversation conversationWithRemoteID:remoteID createIfNeeded:YES inContext:self.syncMOC];
        XCTAssert([self.syncMOC saveOrRollback]);
        localID = conversation.objectID;
        // This should not be set, yet.
        XCTAssertNotEqual(conversation.conversationType, ZMConversationTypeOneOnOne);
    }];
    
    NSUUID *selfID = NSUUID.createUUID;
    NSDictionary *innerPayload = @{
                                   @"creator": selfID.transportString,
                                   @"members": @{
                                       @"self": @{
                                           @"status": @0,
                                           @"muted_time": [NSNull null],
                                           @"muted": [NSNull null],
                                           @"status_time": @"2015-05-06T12:15:00.049Z",
                                           @"status_ref": @"0.0",
                                           @"id": selfID.transportString,
                                           @"archived": [NSNull null]
                                       },
                                       @"others": @[]
                                   },
                                   @"name": [NSNull null],
                                   @"id": remoteID.transportString,
                                   @"type": @3, //  <-------------------------------- "Connection"
                                   @"last_event_time": @"2015-05-06T12:15:00.049Z",
                                   };
    
    
    NSDictionary *payload = @{@"conversation": remoteID.transportString,
                              @"time": @"2015-05-06T12:15:00.104Z",
                              @"from": selfID.transportString,
                              @"type" : @"conversation.create",
                              @"data" : innerPayload
                              };
    
    ZMUpdateEvent *event = [OCMockObject mockForClass:[ZMUpdateEvent class]];
    (void)[(ZMUpdateEvent *)[[(id)event stub] andReturnValue:OCMOCK_VALUE(ZMUpdateEventConversationCreate)] type];
    (void)[(ZMUpdateEvent *)[[(id)event stub] andReturn:payload] payload];
    
    [self.syncMOC performGroupedBlockAndWait:^{
        // when
        [self.sut processEvents:@[event] liveEvents:YES prefetchResult:nil];
        
        // then
        ZMConversation *conversation = (id) [self.syncMOC objectWithID:localID];
        XCTAssertEqual(conversation.conversationType, ZMConversationTypeConnection);
    }];
}

- (void)testThatItProcessesConversationCreateEventForPendingConnectionConversation
{
    // When the other end hasn't accepted, yet, they're not in the 'others' array.
    // We can not (safely) match this conversation with the connection, since we have
    // no way of looking up the user / connection.
    
    // given
    NSUUID *remoteID = [NSUUID createUUID];
    NSDictionary *innerPayload = @{@"creator": @"08316f5e-3c0a-4847-a235-2b4d93f291a4",
                                   @"id": remoteID.transportString,
                                   @"last_event": @"2.800112314202039b",
                                   @"last_event_time": @"2014-07-02T14:52:45.211Z",
                                   @"members": @{
                                           @"others": @[],
                                           @"self": @{
                                                   @"archived": [NSNull null],
                                                   @"id": @"08316f5e-3c0a-4847-a235-2b4d93f291a4",
                                                   @"last_read": @"2.800112314202039b",
                                                   @"muted": [NSNull null],
                                                   @"muted_time": [NSNull null],
                                                   @"status": @0,
                                                   @"status_ref": @"0.0",
                                                   @"status_time": @"2014-07-02T14:52:45.211Z",
                                                   },
                                           },
                                   @"name": @"Jonathan",
                                   @"type": @3,};
    
    
    NSDictionary *payload = @{
                              @"type" : @"conversation.create",
                              @"data" : innerPayload
                              };
    
    ZMUpdateEvent *event = [OCMockObject mockForClass:[ZMUpdateEvent class]];
    (void)[(ZMUpdateEvent *)[[(id)event stub] andReturnValue:OCMOCK_VALUE(ZMUpdateEventConversationCreate)] type];
    (void)[(ZMUpdateEvent *)[[(id)event stub] andReturn:payload] payload];
    
    [self.syncMOC performGroupedBlockAndWait:^{
        // when
        [self.sut processEvents:@[event] liveEvents:YES prefetchResult:nil];
        
        // then
        ZMConversation *conversation = [ZMConversation conversationWithRemoteID:remoteID createIfNeeded:NO inContext:self.syncMOC];
        XCTAssertNil(conversation);
    }];
}

- (void)testThatItProcessesConversationRenameEvents
{
    // given
    __block ZMUser *user3;
    __block ZMConversation *conversation;
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMUser *user1 = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        user1.remoteIdentifier = [NSUUID createUUID];
        ZMUser *user2 = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        user2.remoteIdentifier = [NSUUID createUUID];
        user3 = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        user3.remoteIdentifier = [NSUUID createUUID];
        conversation = [ZMConversation insertGroupConversationIntoManagedObjectContext:self.syncMOC withParticipants:@[user1, user2, user3]];
        conversation.userDefinedName = @"Some old name";
        conversation.remoteIdentifier = [NSUUID createUUID];
        XCTAssertTrue([self.syncMOC saveOrRollback]);
    }];
    
    NSString *newName = @"My New Name";
    NSDate *time = [NSDate date];
    NSDictionary *payload = @{@"type" : @"conversation.rename",
                              @"from": user3.remoteIdentifier.transportString,
                              @"time": time.transportString,
                              @"conversation" : conversation.remoteIdentifier.transportString,
                              @"data": @{@"name": newName}
                              };
    ZMUpdateEvent *event = [OCMockObject mockForClass:[ZMUpdateEvent class]];
    (void)[(ZMUpdateEvent *)[[(id)event stub] andReturnValue:OCMOCK_VALUE(ZMUpdateEventConversationRename)] type];
    (void)[(ZMUpdateEvent *)[[(id)event stub] andReturn:payload] payload];
    (void)[(ZMUpdateEvent *)[[(id)event stub] andReturn:time] timeStamp];
    (void)[(ZMUpdateEvent *)[[(id)event stub] andReturn:user3.remoteIdentifier] senderUUID];
    (void)[(ZMUpdateEvent *)[[(id)event stub] andReturn:conversation.remoteIdentifier] conversationUUID];

    [(ZMUpdateEvent *)[[(id)event stub] andReturnValue:OCMOCK_VALUE(NO)] canUnarchiveConversation:conversation];

    // when
    [self.syncMOC performGroupedBlockAndWait:^{
        [self.sut processEvents:@[event] liveEvents:YES prefetchResult:nil];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    [self.syncMOC performGroupedBlockAndWait:^{
        XCTAssertEqualObjects(conversation.userDefinedName, newName);
    }];
}

- (void)testThatItDoesNotProcessUpdateEventWrongType
{
    // given
    NSUUID *remoteID = [NSUUID createUUID];
    NSDictionary *payload = @{
                              @"id" : [remoteID transportString],
                              @"type" : @"fooz",
                              @"connection" : @{}
                              };
    ZMUpdateEvent *event = [OCMockObject mockForClass:[ZMUpdateEvent class]];
    (void)[(ZMUpdateEvent *)[[(id)event stub] andReturnValue:OCMOCK_VALUE(ZMUpdateEventUnknown)] type];
    (void)[(ZMUpdateEvent *)[[(id)event stub] andReturn:payload] payload];
    (void)[(ZMUpdateEvent *)[[(id)event stub] andReturn:nil] conversationUUID];

    [self.syncMOC performGroupedBlockAndWait:^{
        
        // when
        [self.sut processEvents:@[event] liveEvents:YES prefetchResult:nil];
        
        // then
        ZMConversation *conversation = [ZMConversation conversationWithRemoteID:remoteID createIfNeeded:NO inContext:self.syncMOC];
        XCTAssertNil(conversation);
    }];
}

- (void)testThatItDoesNotCreateANewConversationWhenItProcessesAConversationCreateEventForAOneOnOneConversation;
{
    // given
    NSUUID *otherUserID = [NSUUID createUUID];
    __block ZMUser *otherUser;
    __block ZMConnection *existingConnection;
    [self.syncMOC performGroupedBlockAndWait:^{
        [ZMUser selfUserInContext:self.syncMOC].remoteIdentifier = self.selfUserID;
        [ZMUser selfUserInContext:self.syncMOC].name = @"Me, myself";
        otherUser = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        otherUser.name = @"Other";
        otherUser.remoteIdentifier = otherUserID;
        existingConnection = [ZMConnection insertNewSentConnectionToUser:otherUser];
        XCTAssertNotNil(existingConnection.conversation);
        XCTAssertNil(existingConnection.conversation.remoteIdentifier);
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // when
    NSUUID *conversationID = [NSUUID createUUID];
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMUpdateEvent *event = [self conversationCreateEventForConversationID:conversationID selfID:self.selfUserID otherUserID:otherUserID];
        XCTAssertNotNil(event);
        [self.sut processEvents:@[event] liveEvents:YES prefetchResult:nil];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    [self.syncMOC performGroupedBlockAndWait:^{
        NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:[ZMConversation entityName]];
        request.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"conversationType" ascending:YES]];
        NSArray *allConversations = [self.syncMOC executeFetchRequestOrAssert:request];
        XCTAssertEqual(allConversations.count, 2u);
        
        ZMConversation *selfConversation = allConversations.firstObject;
        XCTAssertNotNil(selfConversation);
        XCTAssertEqual(selfConversation.conversationType, ZMConversationTypeSelf);
        XCTAssertEqualObjects(selfConversation.remoteIdentifier, self.selfUserID);
        
        ZMConversation *conversation = allConversations.lastObject;
        XCTAssertNotNil(conversation);
        XCTAssertEqual(conversation, existingConnection.conversation);
        XCTAssertEqualObjects(conversation.remoteIdentifier, conversationID);
        XCTAssertEqual(conversation.conversationType, ZMConversationTypeConnection);
        
        
        // also check that the existing connection is not altered
        XCTAssertNotNil(existingConnection.to);
        XCTAssertEqual(existingConnection.to, otherUser);
        XCTAssertEqualObjects(existingConnection.to.remoteIdentifier, otherUserID);
    }];
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatItMergesConversationsWhenItProcessesAConversationCreateEventForAOneOnOneConversationAndTheConnectionAlreadyHasAConversation
{
    // given
    id authStatusMock = [OCMockObject niceMockForClass:[ZMAuthenticationStatus class]];
    [[[authStatusMock stub] andReturnValue:@YES] registeredOnThisDevice];
    [(ZMAuthenticationStatus *)[[authStatusMock stub] andReturnValue:OCMOCK_VALUE((ZMAuthenticationPhase){ZMAuthenticationPhaseAuthenticated})] currentPhase];
    
    id accountStatus = [OCMockObject niceMockForClass:[ZMAccountStatus class]];
    [[[accountStatus stub]
      andReturnValue: OCMOCK_VALUE((AccountState){AccountStateOldDeviceActiveAccount})] currentAccountState];
    
    self.sut = (id) [[ZMConversationTranscoder alloc]  initWithSyncStrategy:self.syncStrategy applicationStatus:self.mockApplicationStatus syncStatus:self.mockSyncStatus];

    
    NSUUID *otherUserID = [NSUUID createUUID];
    NSUUID *conversationID = [NSUUID createUUID];
    
    __block ZMUser *otherUser;
    __block ZMConnection *existingConnection;
    [self.syncMOC performGroupedBlockAndWait:^{
        
        // create connection + connection-conversation
        [ZMUser selfUserInContext:self.syncMOC].remoteIdentifier = self.selfUserID;
        [ZMUser selfUserInContext:self.syncMOC].name = @"Me, myself";
        otherUser = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        otherUser.name = @"Other";
        otherUser.remoteIdentifier = otherUserID;
        existingConnection = [ZMConnection insertNewSentConnectionToUser:otherUser];
        XCTAssertNotNil(existingConnection.conversation);
        XCTAssertNil(existingConnection.conversation.remoteIdentifier);
        
        // process a member-join event on that connection-conversation, before I know that it is a connection-conversation
        NSDictionary *eventPayload = [self responsePayloadForUserEventInConversationID:conversationID userIDs:@[otherUserID] eventType:@"conversation.member-join"];
        ZMUpdateEvent *event = [ZMUpdateEvent eventFromEventStreamPayload:eventPayload uuid:nil];
        [self.sut processEvents:@[event] liveEvents:YES prefetchResult:nil];
        
        // forcing an event here - in real code it will be created in another syncObject, not tested here
        ZMSystemMessage *memberJoinEvent = [ZMSystemMessage insertNewObjectInManagedObjectContext:self.syncMOC];
        memberJoinEvent.systemMessageType = ZMSystemMessageTypeParticipantsAdded;
        [existingConnection.conversation.mutableMessages addObject:memberJoinEvent];
        
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    [self.syncMOC performGroupedBlockAndWait:^{
        // SANITY CHECK - now I should have two conversations
        ZMConversation *createdConversation = [ZMConversation conversationWithRemoteID:conversationID createIfNeeded:NO inContext:self.syncMOC];
        XCTAssertNotNil(createdConversation);
        XCTAssertNotEqual(createdConversation, existingConnection.conversation);
        
        ZMSystemMessage *memberJoinEvent = [ZMSystemMessage insertNewObjectInManagedObjectContext:self.syncMOC];
        memberJoinEvent.systemMessageType = ZMSystemMessageTypeParticipantsAdded;
        [createdConversation.mutableMessages addObject:memberJoinEvent];
        
        // forcing an event here - in real code it will be created in another syncObject, not tested here
        XCTAssertEqual(createdConversation.messages.count, 1u);
        NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:[ZMConversation entityName]];
        NSArray *allConversations = [self.syncMOC executeFetchRequestOrAssert:request];
        
        XCTAssertEqual(allConversations.count, 3u);
    }];
    
    // when
    [self.syncMOC performGroupedBlockAndWait:^{
        
        ZMUpdateEvent *event = [self conversationCreateEventForConversationID:conversationID selfID:self.selfUserID otherUserID:otherUserID];
        XCTAssertNotNil(event);
        [self.sut processEvents:@[event] liveEvents:YES prefetchResult:nil];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    [self.syncMOC performGroupedBlockAndWait:^{
        NSFetchRequest *request = [NSFetchRequest fetchRequestWithEntityName:[ZMConversation entityName]];
        request.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"conversationType" ascending:YES]];
        NSArray *allConversations = [self.syncMOC executeFetchRequestOrAssert:request];
        XCTAssertEqual(allConversations.count, 2u);
        
        ZMConversation *conversation = allConversations.lastObject;
        XCTAssertNotNil(conversation);
        XCTAssertEqual(conversation, existingConnection.conversation);
        XCTAssertEqualObjects(conversation.remoteIdentifier, conversationID);
        XCTAssertEqual(conversation.conversationType, ZMConversationTypeConnection);
        
        // also check that the existing connection is not altered
        XCTAssertNotNil(existingConnection.to);
        XCTAssertEqual(existingConnection.to, otherUser);
        XCTAssertEqualObjects(existingConnection.to.remoteIdentifier, otherUserID);
        
        // check that the conversation has both events
        XCTAssertEqual(conversation.messages.count, 2u);
    }];
    WaitForAllGroupsToBeEmpty(0.5);
}


- (void)testThatItSetsLastModifiedDateFromPushPayload
{
    // given
    __block ZMConversation *conversation;
    NSUUID* conversationID = [NSUUID createUUID];
    NSDate *lastModifiedDate = [NSDate dateWithTimeIntervalSinceReferenceDate:417002300];
    
    [self.syncMOC performGroupedBlockAndWait:^{
        conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        conversation.remoteIdentifier = conversationID;
        
        NSDictionary *payload = @{@"conversation": conversation.remoteIdentifier.transportString,
                                  @"data": @{
                                          @"content": @"http://www.youtube.com/watch?v=CRbWeUN1n7k#t=544",
                                          @"nonce": [NSUUID createUUID].transportString,
                                          },
                                  @"from": @"6185dc93-aabd-4ece-bf75-372a6dd3592b",
                                  @"time": lastModifiedDate.transportString,
                                  @"type": @"conversation.message-add"};
        
        ZMUpdateEvent *updateEvent = [ZMUpdateEvent eventFromEventStreamPayload:payload uuid:nil];
        XCTAssertNotNil(updateEvent);
        
        // when
        [self.sut processEvents:@[updateEvent] liveEvents:YES prefetchResult:nil];
        
        // then
        XCTAssertEqualWithAccuracy(conversation.lastModifiedDate.timeIntervalSinceReferenceDate, lastModifiedDate.timeIntervalSinceReferenceDate, 0.1);
    }];
}

- (void)testThatItSetsLastModifiedDateFromVoiceChannelActivateUpdateEvent
{
    // given
    __block ZMConversation *conversation;
    NSUUID* conversationID = [NSUUID createUUID];
    NSDate *lastModifiedDate = [NSDate dateWithTimeIntervalSinceReferenceDate:417002300];
    
    [self.syncMOC performGroupedBlockAndWait:^{
        conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        conversation.remoteIdentifier = conversationID;
        
        NSDictionary *activatePayload = @{@"conversation": conversation.remoteIdentifier.transportString,
                                  @"data": [NSNull null],
                                  @"from": @"c6ce694f-5108-4fa7-8c63-6342c540541e",
                                  @"time": lastModifiedDate.transportString,
                                  @"type": @"conversation.voice-channel-activate"};
//        NSDictionary *deactivatePayload = @{@"conversation": conversation.remoteIdentifier.transportString,
//                                            @"data": {@"reason": @"missed"},
//                                            @"from": @"c6ce694f-5108-4fa7-8c63-6342c540541e",
//                                            @"id": lastEventID.transportString,
//                                            @"time": lastModifiedDate.transportString,
//                                            @"type": @"conversation.voice-channel-activate"};
        
        ZMUpdateEvent *updateEvent = [ZMUpdateEvent eventFromEventStreamPayload:activatePayload uuid:nil];
        XCTAssertNotNil(updateEvent);
        
        // when
        [self.sut processEvents:@[updateEvent] liveEvents:YES prefetchResult:nil];
        
        // then
        XCTAssertEqualWithAccuracy(conversation.lastModifiedDate.timeIntervalSinceReferenceDate, lastModifiedDate.timeIntervalSinceReferenceDate, 0.1);
    }];
}

- (void)testThatItDoesNotSetLastModifiedDateFromCallStateUpdateEvents
{
    // We had a bug https://wearezeta.atlassian.net/browse/MEC-626
    // where we would incorrectly set the conversation.lastModifiedDate to [NSDate date]
    
    
    // given
    __block ZMConversation *conversation;
    NSUUID *conversationID = [NSUUID createUUID];
    NSDate *lastModifiedDate = [NSDate dateWithTimeIntervalSinceReferenceDate:417002300];
    
    [self.syncMOC performGroupedBlockAndWait:^{
        conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        conversation.remoteIdentifier = conversationID;
        conversation.lastModifiedDate = lastModifiedDate;
        
        NSDictionary *payload = @{@"type": @"call.state",
                                  @"conversation": conversation.remoteIdentifier.transportString,
                                  @"self":@{@"state":@"idle",
                                            @"reason":@"ended"},
                                  @"participants":@{},};
        
        ZMUpdateEvent *updateEvent = [ZMUpdateEvent eventFromEventStreamPayload:payload uuid:nil];
        XCTAssertNotNil(updateEvent);
        
        // when
        [self.sut processEvents:@[updateEvent] liveEvents:YES prefetchResult:nil];
        
        // then
        XCTAssertEqualWithAccuracy(conversation.lastModifiedDate.timeIntervalSinceReferenceDate, lastModifiedDate.timeIntervalSinceReferenceDate, 0.1);
    }];
}


- (void)testThatItDoesNotSetLastModifiedDateFromPushPayloadIfItIsAMemberUpdate
{
    // given
    __block ZMConversation *conversation;
    NSUUID* conversationID = [NSUUID createUUID];
    NSDate *lastModifiedDate = [NSDate dateWithTimeIntervalSinceReferenceDate:417002300];
    NSDate *newerLastModifiedDate = [lastModifiedDate dateByAddingTimeInterval:10];
    
    [self.syncMOC performGroupedBlockAndWait:^{
        conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        conversation.remoteIdentifier = conversationID;
        conversation.lastModifiedDate = lastModifiedDate;
        
        NSDictionary *payload = @{@"conversation": conversation.remoteIdentifier.transportString,
                                  @"data": @{
                                          },
                                  @"from": @"6185dc93-aabd-4ece-bf75-372a6dd3592b",
                                  @"time": newerLastModifiedDate.transportString,
                                  @"type": @"conversation.member-update"};
        
        ZMUpdateEvent *updateEvent = [ZMUpdateEvent eventFromEventStreamPayload:payload uuid:nil];
        XCTAssertNotNil(updateEvent);
        
        // when
        [self.sut processEvents:@[updateEvent] liveEvents:YES prefetchResult:nil];
        
        // then
        XCTAssertEqualWithAccuracy(conversation.lastModifiedDate.timeIntervalSinceReferenceDate, lastModifiedDate.timeIntervalSinceReferenceDate, 0.2);
    }];
}

- (void)testThatItDoesNotSetLastModifiedDateFromPushPayloadWhenItIsAlreadyNewer
{
    // given
    __block ZMConversation *conversation;
    NSUUID* conversationID = [NSUUID createUUID];
    NSDate *lastModifiedDate = [NSDate dateWithTimeIntervalSinceReferenceDate:417002300];
    NSDate *newerLastModifiedDate = [lastModifiedDate dateByAddingTimeInterval:10];
    
    [self.syncMOC performGroupedBlockAndWait:^{
        conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        conversation.remoteIdentifier = conversationID;
        conversation.lastModifiedDate = newerLastModifiedDate;
        
        NSDictionary *payload = @{@"conversation": conversation.remoteIdentifier.transportString,
                                  @"data": @{
                                          @"content": @"http://www.youtube.com/watch?v=CRbWeUN1n7k#t=544",
                                          @"nonce": [NSUUID createUUID].transportString,
                                          },
                                  @"from": @"6185dc93-aabd-4ece-bf75-372a6dd3592b",
                                  @"time": lastModifiedDate.transportString,
                                  @"type": @"conversation.message-add"};
        
        ZMUpdateEvent *updateEvent = [ZMUpdateEvent eventFromEventStreamPayload:payload uuid:nil];
        XCTAssertNotNil(updateEvent);
        
        // when
        [self.sut processEvents:@[updateEvent] liveEvents:YES prefetchResult:nil];
        
        // then
        XCTAssertEqualWithAccuracy(conversation.lastModifiedDate.timeIntervalSinceReferenceDate, newerLastModifiedDate.timeIntervalSinceReferenceDate, 0.1);
    }];
}

- (void)testThatWhenReceivingEventsForAnUnknownConversationAndThenItIsDownloadedAsOneToOneItSetsTheTypeAsOneToOne
{
    // given
    __block ZMConversation *conversation;
    NSUUID* conversationID = [NSUUID createUUID];
    NSUUID* userID = [NSUUID createUUID];
    NSDictionary *payload = @{@"conversation": conversationID.transportString,
                              @"data": @{
                                      @"content": @"http://www.youtube.com/watch?v=CRbWeUN1n7k#t=544",
                                      @"nonce": [NSUUID createUUID].transportString,
                                      },
                              @"from": @"6185dc93-aabd-4ece-bf75-372a6dd3592b",
                              @"time": [NSDate date].transportString,
                              @"type": @"conversation.message-add"};
    
    ZMUpdateEvent *updateEvent = [ZMUpdateEvent eventFromEventStreamPayload:payload uuid:nil];
    XCTAssertNotNil(updateEvent);
    
    // when
    [self.syncMOC performGroupedBlockAndWait:^{
        [self.sut processEvents:@[updateEvent] liveEvents:YES prefetchResult:nil];
        
        // then
        conversation = [ZMConversation conversationWithRemoteID:conversationID createIfNeeded:NO inContext:self.syncMOC];
        XCTAssertNotNil(conversation);
        
        // given
        NSDictionary *conversationPayload = @{
                                              @"creator": userID.transportString,
                                              @"members": @{
                                                      @"self": @{
                                                              @"status": @0,
                                                              @"last_read": @"2f.800122000a5281dc",
                                                              @"status_time": @"2014-09-16T13:08:36.567Z",
                                                              @"id": @"39562cc3-717d-4395-979c-5387ae17f5c3",
                                                              },
                                                      @"others": @[
                                                              @{
                                                                  @"status": @0,
                                                                  @"id": userID.transportString,
                                                                  }
                                                              ]
                                                      },
                                              @"name": @"Marco1",
                                              @"id": conversationID.transportString,
                                              @"type": @2,
                                              @"last_event_time": @"2014-10-06T14:27:17.945Z",
                                              };
        ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:conversationPayload HTTPStatus:200 transportSessionError:nil];
        
        // when
        [self.sut updateObject:conversation withResponse:response downstreamSync:nil];
        
        // then
        XCTAssertEqual(conversation.conversationType, ZMConversationTypeOneOnOne);
    }];
    
}

- (void)testThatItUnArchivesConversations
{
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        NSDate *oldDate = [NSDate date];
        NSDate *newDate = [oldDate dateByAddingTimeInterval:10];
        
        ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        conversation.remoteIdentifier = NSUUID.createUUID;
        conversation.lastServerTimeStamp = oldDate;
        conversation.isArchived = YES;
        
        XCTAssertNotNil(conversation);
        XCTAssertTrue(conversation.isArchived);
        XCTAssertEqualObjects(conversation.archivedChangedTimestamp, oldDate);
        
        NSDictionary *payload = @{
                                  @"conversation" : conversation.remoteIdentifier.transportString,
                                  @"data" : @{},
                                  @"from" : @"08316f5e-3c0a-4847-a235-2b4d93f291a4",
                                  @"time" : newDate.transportString,
                                  @"type" : @"conversation.voice-channel-activate",
                                  };
        
        ZMUpdateEvent *updateEvent = [ZMUpdateEvent eventFromEventStreamPayload:payload uuid:nil];
        XCTAssertNotNil(updateEvent);
        
        // when
        [self.sut processEvents:@[updateEvent] liveEvents:YES prefetchResult:nil];
        
        // then
        XCTAssertFalse(conversation.isArchived);
        XCTAssertTrue([conversation.keysThatHaveLocalModifications containsObject:ZMConversationArchivedChangedTimeStampKey]);
    }];
}

- (void)testThatItDoesNotUnArchiveAConversations_WhenTheConversationsArchivedChangeTimeStampIsNewer
{
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        NSDate *oldArchived = [NSDate date];
        NSDate *newArchived = [oldArchived dateByAddingTimeInterval:100];
        
        ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        conversation.remoteIdentifier = NSUUID.createUUID;
        conversation.lastServerTimeStamp = newArchived;
        conversation.isArchived = YES;
        [conversation resetLocallyModifiedKeys:[NSSet setWithObject:ZMConversationArchivedChangedTimeStampKey]];
        
        XCTAssertNotNil(conversation);
        XCTAssertTrue(conversation.isArchived);
        XCTAssertEqualObjects(conversation.archivedChangedTimestamp, newArchived);
        
        NSDictionary *payload = @{
                                  @"conversation" : conversation.remoteIdentifier.transportString,
                                  @"data" : @{},
                                  @"from" : @"08316f5e-3c0a-4847-a235-2b4d93f291a4",
                                  @"time" : [oldArchived transportString],
                                  @"type" : @"conversation.voice-channel-activate",
                                  };
        
        ZMUpdateEvent *updateEvent = [ZMUpdateEvent eventFromEventStreamPayload:payload uuid:nil];
        XCTAssertNotNil(updateEvent);
        
        // when
        [self.sut processEvents:@[updateEvent] liveEvents:YES prefetchResult:nil];
        
        // then
        XCTAssertTrue(conversation.isArchived);
        XCTAssertFalse([conversation.keysThatHaveLocalModifications containsObject:ZMConversationArchivedChangedTimeStampKey]);
    }];
}

@end



@implementation ZMConversationTranscoderTests (LastRead)

- (void)testThatItSetsLastReadWhenTheVisibleWindowChanges;
{
    // given
    size_t const MessageCount = 300;
    __block ZMConversation *syncConversation;
    [self.syncMOC performGroupedBlockAndWait:^{
        syncConversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        syncConversation.remoteIdentifier = [NSUUID createUUID];
        
        NSDate *date = [NSDate dateWithTimeIntervalSinceReferenceDate:417005700];
        for (size_t i = 0; i < MessageCount; ++i) {
            ZMTextMessage *message = [ZMTextMessage insertNewObjectInManagedObjectContext:self.syncMOC];
            message.text = [NSString stringWithFormat:@"%llu", (long long unsigned) i];
            message.serverTimestamp = [date dateByAddingTimeInterval:(NSTimeInterval) i];
            [syncConversation.mutableMessages addObject:message];
        }
        XCTAssert([self.syncMOC saveOrRollback]);
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // when
    ZMConversation *conversation = (id) [self.uiMOC objectWithID:syncConversation.objectID];
    conversation.lastReadTimestampSaveDelay = 0.2;
    ZMMessage *fromMessage = conversation.messages[42];
    ZMMessage *toMessage = conversation.messages[56];
    [conversation setVisibleWindowFromMessage:fromMessage toMessage:toMessage];
    XCTAssert([self.uiMOC saveOrRollback]);
    WaitForAllGroupsToBeEmpty(conversation.lastReadTimestampSaveDelay + 0.2);
    
    // then
    XCTAssertEqual(conversation.lastReadServerTimeStamp, toMessage.serverTimestamp);
    XCTAssertTrue([conversation.keysThatHaveLocalModifications containsObject:@"lastReadServerTimeStamp"],
                  @"{%@}", [conversation.keysThatHaveLocalModifications.allObjects componentsJoinedByString:@", "]);
}


- (void)testThatWhenReceivingAnInvisibleEventRightAfterTheLastReadTheLastReadIsIncreased
{
    [self.syncMOC performGroupedBlockAndWait:^{
        
        // given
        ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        conversation.remoteIdentifier = [NSUUID createUUID];
        conversation.lastReadServerTimeStamp = [NSDate date];
        conversation.lastServerTimeStamp = conversation.lastReadServerTimeStamp;
        
        NSDate *newDate = [conversation.lastReadServerTimeStamp dateByAddingTimeInterval:5];
        
        NSDictionary *payload = @{
                                  @"conversation" : conversation.remoteIdentifier.transportString,
                                  @"data" : @{@"reason": @"completed"},
                                  @"from" : @"08316f5e-3c0a-4847-a235-2b4d93f291a4",
                                  @"time" : newDate.transportString,
                                  @"type" : @"conversation.voice-channel-deactivate",
                                  };
        
        ZMUpdateEvent *updateEvent = [ZMUpdateEvent eventFromEventStreamPayload:payload uuid:nil];
        XCTAssertNotNil(updateEvent);
        
        // when
        [self.sut processEvents:@[updateEvent] liveEvents:YES prefetchResult:nil];
        
        // then
        XCTAssertEqualWithAccuracy(conversation.lastReadServerTimeStamp.timeIntervalSinceReferenceDate, newDate.timeIntervalSinceReferenceDate, 0.1);
    }];
}

- (void)testThatWhenReceivingAnInvisibleEventThatIsNotTheNextAfterTheLastReadTheLastReadIsNotIncreased
{
    [self.syncMOC performGroupedBlockAndWait:^{
        
        // given
        ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        conversation.remoteIdentifier = [NSUUID createUUID];
        conversation.lastReadServerTimeStamp = [NSDate date];
        conversation.lastServerTimeStamp = [NSDate date];
        
        NSDate *lastReadTimeStamp = conversation.lastReadServerTimeStamp;
        NSDate *newDate = [NSDate date];

        NSDictionary *payload = @{
                                  @"conversation" : conversation.remoteIdentifier.transportString,
                                  @"data" : @{@"reason": @"completed"},
                                  @"from" : @"08316f5e-3c0a-4847-a235-2b4d93f291a4",
                                  @"time" : newDate.transportString,
                                  @"type" : @"conversation.voice-channel-deactivate",
                                  };

        ZMUpdateEvent *updateEvent = [ZMUpdateEvent eventFromEventStreamPayload:payload uuid:nil];
        XCTAssertNotNil(updateEvent);
        
        // when
        [self.sut processEvents:@[updateEvent] liveEvents:YES prefetchResult:nil];
        
        // then
        XCTAssertEqualObjects(conversation.lastReadServerTimeStamp, lastReadTimeStamp);
    }];
}


- (void)testThatWhenReceivingAnInvisibleEventThatIsOlderThanTheLastReadTheLastReadIsNotDecreased
{
    [self.syncMOC performGroupedBlockAndWait:^{
        
        // given
        ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        conversation.remoteIdentifier = [NSUUID createUUID];
        conversation.lastReadServerTimeStamp = [NSDate date];
        conversation.lastServerTimeStamp = [NSDate date];
        
        NSDate *lastReadTimeStamp = conversation.lastReadServerTimeStamp;
        NSDate *newDate = [NSDate date];
        
        NSDictionary *payload = @{
                                  @"conversation" : conversation.remoteIdentifier.transportString,
                                  @"data" : @{@"reason": @"completed"},
                                  @"from" : @"08316f5e-3c0a-4847-a235-2b4d93f291a4",
                                  @"time" : newDate.transportString,
                                  @"type" : @"conversation.voice-channel-activate",
                                  };
        
        ZMUpdateEvent *updateEvent = [ZMUpdateEvent eventFromEventStreamPayload:payload uuid:nil];
        XCTAssertNotNil(updateEvent);
        
        // when
        [self.sut processEvents:@[updateEvent] liveEvents:YES prefetchResult:nil];
        
        // then
        XCTAssertEqualObjects(conversation.lastReadServerTimeStamp, lastReadTimeStamp);
        
    }];
}



- (void)testThatWhenReceivingAVisibleEventAfterTheLastReadTheLastReadIsNotIncreased
{
    [self.syncMOC performGroupedBlockAndWait:^{
        
        // given
        ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        conversation.remoteIdentifier = [NSUUID createUUID];
        conversation.lastReadServerTimeStamp = [NSDate date];
        conversation.lastServerTimeStamp = [NSDate date];
        
        NSDate *lastReadTimeStamp = conversation.lastReadServerTimeStamp;
        NSDate *newDate = [NSDate date];
        
        NSDictionary *payload = @{
                                  @"conversation" : conversation.remoteIdentifier.transportString,
                                  @"data" : @{
                                          @"nonce" : [NSUUID createUUID].transportString,
                                          @"content" : @"this should not increase the last read"
                                          },
                                  @"from" : @"08316f5e-3c0a-4847-a235-2b4d93f291a4",
                                  @"time" : newDate.transportString,
                                  @"type" : @"conversation.message-add",
                                  };
        
        ZMUpdateEvent *updateEvent = [ZMUpdateEvent eventFromEventStreamPayload:payload uuid:nil];
        XCTAssertNotNil(updateEvent);
        
        // when
        [self.sut processEvents:@[updateEvent] liveEvents:YES prefetchResult:nil];
        
        // then
        XCTAssertEqualObjects(conversation.lastReadServerTimeStamp, lastReadTimeStamp);

    }];
}

- (void)testThatWhenDownloadingAnInvisibleEventRightAfterTheLastReadTheLastReadIsIncreased
{
    [self.syncMOC performGroupedBlockAndWait:^{
        
        // given
        ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        conversation.remoteIdentifier = [NSUUID createUUID];
        conversation.lastReadServerTimeStamp = [NSDate date];
        conversation.lastServerTimeStamp = conversation.lastReadServerTimeStamp;
        
        NSDate *newDate = [NSDate dateWithTimeInterval:10 sinceDate:conversation.lastServerTimeStamp];
        
        
        NSDictionary *payload = @{
                                  @"conversation" : conversation.remoteIdentifier.transportString,
                                  @"data" : @{@"reason": @"completed"},
                                  @"from" : @"08316f5e-3c0a-4847-a235-2b4d93f291a4",
                                  @"time" : newDate.transportString,
                                  @"type" : @"conversation.voice-channel-deactivate",
                                  };
        
        ZMUpdateEvent *updateEvent = [ZMUpdateEvent eventFromEventStreamPayload:payload uuid:nil];
        XCTAssertNotNil(updateEvent);
        
        
        // when
        [self.sut processEvents:@[updateEvent] liveEvents:NO prefetchResult:nil];
        
        // then
        XCTAssertEqualWithAccuracy(conversation.lastReadServerTimeStamp.timeIntervalSinceReferenceDate, newDate.timeIntervalSinceReferenceDate, 0.1);
    }];
}


- (void)testThatWhenDownloadingAVoiceChannelDeactivateEventWithReasonMissedTheLastReadTheLastReadIsNotIncreased
{
    [self.syncMOC performGroupedBlockAndWait:^{
        
        // given
        ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        conversation.lastReadServerTimeStamp = [NSDate dateWithTimeIntervalSince1970:12345678];
        conversation.remoteIdentifier = [NSUUID createUUID];
        
        NSDate *newTimestamp = [NSDate dateWithTimeIntervalSince1970:1234523891];
        
        NSDictionary *payload = @{
                                  @"conversation" : conversation.remoteIdentifier.transportString,
                                  @"data" : @{@"reason": @"missed"},
                                  @"from" : @"08316f5e-3c0a-4847-a235-2b4d93f291a4",
                                  @"time" : newTimestamp.transportString,
                                  @"type" : @"conversation.voice-channel-deactivate",
                                  };
        
        ZMUpdateEvent *updateEvent = [ZMUpdateEvent eventFromEventStreamPayload:payload uuid:nil];
        XCTAssertNotNil(updateEvent);
        
        // when
        [self.sut processEvents:@[updateEvent] liveEvents:NO prefetchResult:nil];
        
        // then
        XCTAssertNotEqualObjects(conversation.lastReadServerTimeStamp, newTimestamp);
        XCTAssertFalse([conversation.keysThatHaveLocalModifications containsObject:ZMConversationLastReadServerTimeStampKey]);
    }];
}

- (void)testThatWhenDownloadingAVoiceChannelDeactivateEventWithReasonCompletedTheLastReadTheLastReadIsIncreased
{
    [self.syncMOC performGroupedBlockAndWait:^{
        
        // given
        ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        conversation.remoteIdentifier = [NSUUID createUUID];
        conversation.lastReadServerTimeStamp = [NSDate dateWithTimeIntervalSince1970:100000];
        conversation.lastServerTimeStamp = conversation.lastReadServerTimeStamp;
        
        NSDate *newDate = [NSDate dateWithTimeInterval:1 sinceDate:conversation.lastServerTimeStamp];
        
        NSDictionary *payload = @{
                                  @"conversation" : conversation.remoteIdentifier.transportString,
                                  @"data" : @{@"reason": @"completed"},
                                  @"from" : @"08316f5e-3c0a-4847-a235-2b4d93f291a4",
                                  @"time" : newDate.transportString,
                                  @"type" : @"conversation.voice-channel-deactivate",
                                  };
        
        ZMUpdateEvent *updateEvent = [ZMUpdateEvent eventFromEventStreamPayload:payload uuid:nil];
        XCTAssertNotNil(updateEvent);
        
        // when
        [self.sut processEvents:@[updateEvent] liveEvents:NO prefetchResult:nil];
        
        // then
        XCTAssertEqualWithAccuracy(conversation.lastReadServerTimeStamp.timeIntervalSinceReferenceDate, newDate.timeIntervalSinceReferenceDate, 0.1);
    }];
}

@end


@implementation ZMConversationTranscoderTests (hasUnreadMissedCall)


- (void)testThatItDoesNotSetHasUnreadMissedCallWhenTheSenderIsTheSelfUser
{
    [self.syncMOC performGroupedBlockAndWait:^{
        
        // given
        ZMUser *selfUser = [ZMUser selfUserInContext:self.syncMOC];
        selfUser.remoteIdentifier = NSUUID.createUUID;
        ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        conversation.remoteIdentifier = [NSUUID createUUID];
        conversation.lastReadServerTimeStamp = [NSDate date];

        [self.syncMOC saveOrRollback];
        
        // newDate is newer than the lastReadServerTimestamp

        NSDate *newDate = [conversation.lastReadServerTimeStamp dateByAddingTimeInterval:30];

        NSDictionary *payload = @{
                                  @"conversation" : conversation.remoteIdentifier.transportString,
                                  @"data" : @{@"reason": @"missed"},
                                  @"from" : selfUser.remoteIdentifier.transportString,
                                  @"time" : newDate.transportString,
                                  @"type" : @"conversation.voice-channel-deactivate",
                                  };
        
        ZMUpdateEvent *updateEvent = [ZMUpdateEvent eventFromEventStreamPayload:payload uuid:nil];
        XCTAssertNotNil(updateEvent);
        
        // when
        [self.sut processEvents:@[updateEvent] liveEvents:NO prefetchResult:nil];
        
        // then
        XCTAssertEqual(conversation.conversationListIndicator, ZMConversationListIndicatorNone);
        XCTAssertFalse([conversation.keysThatHaveLocalModifications containsObject:ZMConversationHasUnreadMissedCallKey]);
    }];
}

- (void)testThatItDoesNotSetHasUnreadMissedCallWhenTheLastReadEventIDIsBigger
{
    [self.syncMOC performGroupedBlockAndWait:^{
        
        // given
        ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        conversation.lastReadServerTimeStamp = [NSDate date];
        conversation.remoteIdentifier = [NSUUID createUUID];
        
        // newDate is older than the lastReadServerTimestamp
        NSDate *newDate = [conversation.lastReadServerTimeStamp dateByAddingTimeInterval:-30];
        
        NSDictionary *payload = @{
                                  @"conversation" : conversation.remoteIdentifier.transportString,
                                  @"data" : @{@"reason": @"missed"},
                                  @"from" : @"08316f5e-3c0a-4847-a235-2b4d93f291a4",
                                  @"time" : newDate.transportString,
                                  @"type" : @"conversation.voice-channel-deactivate",
                                  };
        
        ZMUpdateEvent *updateEvent = [ZMUpdateEvent eventFromEventStreamPayload:payload uuid:nil];
        XCTAssertNotNil(updateEvent);
        
        // when
        [self.sut processEvents:@[updateEvent] liveEvents:NO prefetchResult:nil];
        
        // then
        XCTAssertEqual(conversation.conversationListIndicator, ZMConversationListIndicatorNone);
        XCTAssertFalse([conversation.keysThatHaveLocalModifications containsObject:ZMConversationHasUnreadMissedCallKey]);
    }];
}

- (void)testThatItDoesNotSetHasUnreadMissedCallWhenTheVoiceCallWasAcceptedAndCompleted
{
    [self.syncMOC performGroupedBlockAndWait:^{
        
        // given
        ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        conversation.lastReadServerTimeStamp = [NSDate date];
        conversation.remoteIdentifier = [NSUUID createUUID];
        
        // newDate is newer than the lastReadServerTimestamp
        NSDate *newDate = [conversation.lastReadServerTimeStamp dateByAddingTimeInterval:30];
        
        NSDictionary *payload = @{
                                  @"conversation" : conversation.remoteIdentifier.transportString,
                                  @"data" : @{@"reason": @"completed"},
                                  @"from" : @"08316f5e-3c0a-4847-a235-2b4d93f291a4",
                                  @"time" : newDate.transportString,
                                  @"type" : @"conversation.voice-channel-deactivate",
                                  };
        
        ZMUpdateEvent *updateEvent = [ZMUpdateEvent eventFromEventStreamPayload:payload uuid:nil];
        XCTAssertNotNil(updateEvent);
        
        // when
        [self.sut processEvents:@[updateEvent] liveEvents:NO prefetchResult:nil];
        
        // then
        XCTAssertEqual(conversation.conversationListIndicator, ZMConversationListIndicatorNone);
        XCTAssertFalse([conversation.keysThatHaveLocalModifications containsObject:ZMConversationHasUnreadMissedCallKey]);
    }];
}

@end



@implementation ZMConversationTranscoderTests (EventsInConnectionConversations)

- (void)testThatWhenProcessingConversationUpdateEventsItDoesNotRefetchThatConversationIfItWasAnAcceptedConnection
{
    [self.syncMOC performGroupedBlockAndWait:^{
        
        // given
        ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        user.remoteIdentifier = [NSUUID createUUID];
        NSUUID *uuid = [NSUUID createUUID];
        NSDictionary *eventPayload = @{
                                       @"conversation" : [uuid transportString],
                                       @"type": @"conversation.otr-message-add",
                                       @"time" : [NSDate dateWithTimeIntervalSince1970:1233253].transportString
                                       };
        
        ZMUpdateEvent *event = [ZMUpdateEvent eventFromEventStreamPayload:eventPayload uuid:nil];
        XCTAssertNotNil(event);
        
        ZMConnection *connection = [ZMConnection insertNewSentConnectionToUser:user];
        ZMConversation *conversation = connection.conversation;
        conversation.remoteIdentifier = uuid;
        conversation.conversationType = ZMConversationTypeOneOnOne;
        connection.status = ZMConnectionStatusAccepted;
        XCTAssertNotNil(conversation);
        XCTAssertFalse(conversation.needsToBeUpdatedFromBackend);
        XCTAssertFalse(connection.needsToBeUpdatedFromBackend);
        
        // when
        [self.sut processEvents:@[event] liveEvents:YES prefetchResult:nil];
        
        // then
        XCTAssertFalse(conversation.needsToBeUpdatedFromBackend);
        XCTAssertFalse(connection.needsToBeUpdatedFromBackend);
        
    }];
}

- (void)testThatWhenProcessingConversationUpdateEventsItRefetchesThatConversationIfItWasAConnection
{
    [self.syncMOC performGroupedBlockAndWait:^{
        
        // given
        ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        user.remoteIdentifier = [NSUUID createUUID];
        NSUUID *uuid = [NSUUID createUUID];
        NSDictionary *eventPayload = @{
                                       @"conversation" : [uuid transportString],
                                       @"type": @"conversation.otr-message-add",
                                       @"time" : [NSDate dateWithTimeIntervalSince1970:1233253].transportString
                                       };
        
        ZMUpdateEvent *event = [ZMUpdateEvent eventFromEventStreamPayload:eventPayload uuid:nil];
        XCTAssertNotNil(event);
        
        ZMConnection *connection = [ZMConnection insertNewSentConnectionToUser:user];
        ZMConversation *conversation = connection.conversation;
        conversation.remoteIdentifier = uuid;
        XCTAssertNotNil(conversation);
        XCTAssertFalse(conversation.needsToBeUpdatedFromBackend);
        XCTAssertFalse(connection.needsToBeUpdatedFromBackend);
        
        // when
        [self.sut processEvents:@[event] liveEvents:YES prefetchResult:nil];
        
        // then
        XCTAssertTrue(conversation.needsToBeUpdatedFromBackend);
        XCTAssertTrue(connection.needsToBeUpdatedFromBackend);
        
    }];
}

- (void)testThatWhenProcessingConversationUpdateEventsItDoesNotRefetchThatConversationIfItWasAGroupConversation
{
    [self.syncMOC performGroupedBlockAndWait:^{
        
        // given
        ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        user.remoteIdentifier = [NSUUID createUUID];
        NSUUID *uuid = [NSUUID createUUID];
        NSDictionary *eventPayload = @{
                                       @"conversation" : [uuid transportString],
                                       @"type": @"conversation.otr-message-add",
                                       @"time" : [NSDate dateWithTimeIntervalSince1970:1233253].transportString
                                       };
        
        ZMUpdateEvent *event = [ZMUpdateEvent eventFromEventStreamPayload:eventPayload uuid:nil];
        XCTAssertNotNil(event);
        
        ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        conversation.remoteIdentifier = uuid;
        conversation.conversationType = ZMConversationTypeGroup;
        XCTAssertNotNil(conversation);
        XCTAssertFalse(conversation.needsToBeUpdatedFromBackend);
        
        // when
        [self.sut processEvents:@[event] liveEvents:YES prefetchResult:nil];
        
        // then
        XCTAssertFalse(conversation.needsToBeUpdatedFromBackend);
        
    }];
}

- (void)testThatWhenProcessingConversationUpdateEventsItDoesNotRefetchThatConversationIfItWasNotInvalid
{
    [self.syncMOC performGroupedBlockAndWait:^{

        // given
        NSUUID *uuid = [NSUUID createUUID];
        NSDictionary *eventPayload = @{
                                       @"conversation" : [uuid transportString],
                                       @"type": @"conversation.otr-message-add",
                                       @"time" : [NSDate dateWithTimeIntervalSince1970:1233253].transportString
                                       };
        
        ZMUpdateEvent *event = [ZMUpdateEvent eventFromEventStreamPayload:eventPayload uuid:nil];
        XCTAssertNotNil(event);
        
        ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        conversation.remoteIdentifier = uuid;
        conversation.conversationType = ZMConversationTypeOneOnOne;
        XCTAssertFalse(conversation.needsToBeUpdatedFromBackend);
        
        // when
        [self.sut processEvents:@[event] liveEvents:YES prefetchResult:nil];
        
        // then
        XCTAssertFalse(conversation.needsToBeUpdatedFromBackend);
    }];
}

- (void)testThatWhenProcessingConversationUpdateEventsItDoesNotRefetchThatConversationIfItWasInvalid
{
    [self.syncMOC performGroupedBlockAndWait:^{
        
        // given
        NSUUID *uuid = [NSUUID createUUID];
        NSDictionary *eventPayload = @{
                                       @"conversation" : [uuid transportString],
                                       @"type": @"conversation.otr-message-add",
                                       @"time" : [NSDate dateWithTimeIntervalSince1970:1233253].transportString
                                       };
        
        ZMUpdateEvent *event = [ZMUpdateEvent eventFromEventStreamPayload:eventPayload uuid:nil];
        XCTAssertNotNil(event);
        
        ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        conversation.remoteIdentifier = uuid;
        conversation.conversationType = ZMConversationTypeInvalid;
        XCTAssertFalse(conversation.needsToBeUpdatedFromBackend);
        
        // when
        [self.sut processEvents:@[event] liveEvents:YES prefetchResult:nil];
        
        // then
        XCTAssertTrue(conversation.needsToBeUpdatedFromBackend);
    }];
}


- (void)testThatItDoesNotTryToSyncAgainAfterAPermanentError
{
    id partialSUTMock = [OCMockObject partialMockForObject:self.sut];
    __block ZMConversation *conversation;
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        NSSet *changedKeys = [NSSet setWithObject:ZMConversationIsSelfAnActiveMemberKey];
        ZMUser *selfUser = [ZMUser selfUserInContext:self.syncMOC];
        selfUser.remoteIdentifier = [NSUUID createUUID];
        
        conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        conversation.conversationType = ZMConversationTypeGroup;
        conversation.remoteIdentifier = [NSUUID createUUID];
        conversation.isSelfAnActiveMember = NO;
        [conversation setLocallyModifiedKeys:changedKeys];
        
        for (id<ZMContextChangeTracker> tracker in self.sut.contextChangeTrackers) {
            [tracker objectsDidChange:[NSSet setWithObject:conversation]];
        }
        
        [[[partialSUTMock expect] andForwardToRealObject] shouldRetryToSyncAfterFailedToUpdateObject:conversation request:OCMOCK_ANY response:OCMOCK_ANY keysToParse:changedKeys];
        
        // when
        ZM_ALLOW_MISSING_SELECTOR(ZMTransportRequest *request = [self.sut.requestGenerators firstNonNilReturnedFromSelector:@selector(nextRequest)];)
        XCTAssertNotNil(request);
        [request completeWithResponse:[ZMTransportResponse responseWithPayload:@{} HTTPStatus:404 transportSessionError:nil]];
        
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    [self.syncMOC performGroupedBlockAndWait:^{
        // then
        [partialSUTMock verify];
        XCTAssertTrue(conversation.needsToBeUpdatedFromBackend);
        XCTAssertFalse([conversation hasLocalModificationsForKey:ZMConversationIsSelfAnActiveMemberKey]);
        
        // and when
        // it resyncs the conversation
        ZM_ALLOW_MISSING_SELECTOR(ZMTransportRequest *request = [self.sut.requestGenerators firstNonNilReturnedFromSelector:@selector(nextRequest)];)
        XCTAssertNotNil(request);
        XCTAssertEqual(request.method, ZMMethodGET);
        
        NSDictionary *metaData = [self conversationMetaDataForConversation:conversation.remoteIdentifier selfID:[NSUUID createUUID] otherUserID:[NSUUID createUUID] isArchived:NO isSelfAnActiveMember:NO];
        [request completeWithResponse:[ZMTransportResponse responseWithPayload:metaData HTTPStatus:200 transportSessionError:nil]];
    }];
    WaitForAllGroupsToBeEmpty(0.5);

    [self.syncMOC performGroupedBlockAndWait:^{
        // then
        XCTAssertFalse(conversation.needsToBeUpdatedFromBackend);
        
        // and when
        // it does not create a new request for the selfUser leaving
        ZM_ALLOW_MISSING_SELECTOR(ZMTransportRequest *request = [self.sut.requestGenerators firstNonNilReturnedFromSelector:@selector(nextRequest)];)
        XCTAssertNil(request);
    }];
}


- (void)testThatItResetsAllKeysAfterAPermanentError
{
    id partialSUTMock = [OCMockObject partialMockForObject:self.sut];
    __block ZMConversation *conversation;
    __block ZMUser *otherUser;
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        NSSet *changedKeys = [NSSet setWithArray:@[ZMConversationIsSelfAnActiveMemberKey, ZMConversationUnsyncedActiveParticipantsKey]];
        ZMUser *selfUser = [ZMUser selfUserInContext:self.syncMOC];
        selfUser.remoteIdentifier = [NSUUID createUUID];
        otherUser = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        otherUser.remoteIdentifier = [NSUUID UUID];
        otherUser.name = @"Hans";
        
        conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        conversation.conversationType = ZMConversationTypeGroup;
        conversation.remoteIdentifier = [NSUUID createUUID];
        [conversation addParticipant:otherUser];
        conversation.isSelfAnActiveMember = NO;
        [conversation setLocallyModifiedKeys:changedKeys];
        
        for (id<ZMContextChangeTracker> tracker in self.sut.contextChangeTrackers) {
            [tracker objectsDidChange:[NSSet setWithObject:conversation]];
        }
        
        [[[partialSUTMock expect] andForwardToRealObject] shouldRetryToSyncAfterFailedToUpdateObject:conversation request:OCMOCK_ANY response:OCMOCK_ANY keysToParse: [NSSet setWithObject:ZMConversationUnsyncedActiveParticipantsKey]];
        
        // when
        ZM_ALLOW_MISSING_SELECTOR(ZMTransportRequest *request = [self.sut.requestGenerators firstNonNilReturnedFromSelector:@selector(nextRequest)];)
        XCTAssertNotNil(request);
        [request completeWithResponse:[ZMTransportResponse responseWithPayload:@{} HTTPStatus:404 transportSessionError:nil]];
        
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    [self.syncMOC performGroupedBlockAndWait:^{
        // then
        [partialSUTMock verify];
        XCTAssertTrue(conversation.needsToBeUpdatedFromBackend);
        XCTAssertFalse([conversation hasLocalModificationsForKey:ZMConversationIsSelfAnActiveMemberKey]);
        XCTAssertFalse([conversation hasLocalModificationsForKey:ZMConversationUnsyncedActiveParticipantsKey]);

        // and when
        // it resyncs the conversation
        ZM_ALLOW_MISSING_SELECTOR(ZMTransportRequest *request = [self.sut.requestGenerators firstNonNilReturnedFromSelector:@selector(nextRequest)];)
        XCTAssertNotNil(request);
        XCTAssertEqual(request.method, ZMMethodGET);
        
        // the update changes the local isSelfAnActiveMember state to true - if we don't reset all keys, the transcoder will crash when asked for the next request
        NSDictionary *metaData = [self conversationMetaDataForConversation:conversation.remoteIdentifier selfID:[NSUUID createUUID] otherUserID:otherUser.remoteIdentifier isArchived:NO isSelfAnActiveMember:YES];
        [request completeWithResponse:[ZMTransportResponse responseWithPayload:metaData HTTPStatus:200 transportSessionError:nil]];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    [self.syncMOC performGroupedBlockAndWait:^{
        // then
        XCTAssertFalse(conversation.needsToBeUpdatedFromBackend);
        XCTAssertTrue(conversation.isSelfAnActiveMember);

        // and when
        // it does not create a new request for the selfUser leaving
        ZM_ALLOW_MISSING_SELECTOR(ZMTransportRequest *request = [self.sut.requestGenerators firstNonNilReturnedFromSelector:@selector(nextRequest)];)
        XCTAssertNil(request);
    }];
}

@end

