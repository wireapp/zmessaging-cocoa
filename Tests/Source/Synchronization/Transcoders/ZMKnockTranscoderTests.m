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


@import Foundation;
@import ZMTransport;
@import zmessaging;
@import ZMCDataModel;

#import "MessagingTest.h"
#import "ZMKnockTranscoder.h"
#import "ZMUpstreamModifiedObjectSync.h"
#import "ZMUpstreamInsertedObjectSync.h"
#import <zmessaging/ZMUpstreamRequest.h>

@interface ZMKnockTranscoderTests : MessagingTest

@property (nonatomic) ZMKnockTranscoder *sut;
@property (nonatomic) ZMUser *syncSelfUser;

@end

@implementation ZMKnockTranscoderTests

- (void)setUp {
    [super setUp];
    
    [self.syncMOC performGroupedBlockAndWait:^{
        self.syncSelfUser = [ZMUser selfUserInContext:self.syncMOC];
        self.syncSelfUser.remoteIdentifier = [NSUUID createUUID];
        [self setupSelfConversationInContext:self.syncMOC];
    }];
    WaitForAllGroupsToBeEmpty(0.1);
    self.sut = [[ZMKnockTranscoder alloc] initWithManagedObjectContext:self.uiMOC];
}

- (void)tearDown
{
    WaitForAllGroupsToBeEmpty(0.5);
    [self.sut tearDown];
    self.sut = nil;
    [super tearDown];
}

- (void)setupSelfConversationInContext:(NSManagedObjectContext *)context
{
    ZMConversation *selfConversation = [ZMConversation insertNewObjectInManagedObjectContext:context];
    selfConversation.remoteIdentifier = [ZMUser selfUserInContext:context].remoteIdentifier;
    selfConversation.conversationType = ZMConversationTypeSelf;
    [context saveOrRollback];
}

- (void)testThatItReturnsTheContextChangeTrackers;
{
    // then
    XCTAssertEqualObjects(self.sut.contextChangeTrackers, @[]);
}

- (void)testThatItIsCreatedWithSlowSyncComplete
{
    XCTAssertTrue(self.sut.isSlowSyncDone);
}

- (void)testThatANewKnockMessageIsCreatedFromAPushEvent
{
    // given
    id event = [OCMockObject mockForClass:ZMUpdateEvent.class];
    (void)[(ZMUpdateEvent *)[[(id)event stub] andReturnValue:OCMOCK_VALUE(ZMUpdateEventConversationKnock)] type];
    
    id mockKnockMessage = [OCMockObject niceMockForClass:ZMKnockMessage.class];
    
    // expect
    [[mockKnockMessage expect] createOrUpdateMessageFromUpdateEvent:event inManagedObjectContext:self.uiMOC prefetchResult:nil];

    // when
    [self.sut processEvents:@[event] liveEvents:YES prefetchResult:nil];
    
    // then
    [(id)mockKnockMessage stopMocking];
    [(id)mockKnockMessage verify];
}


- (void)testThatANewKnockMessageIsCreatedFromADownloadedEvent
{
    ZMTextMessage *mockKnockMessage = [OCMockObject mockForClass:ZMKnockMessage.class];
    
    // given
    ZMUpdateEvent *event = [OCMockObject mockForClass:ZMUpdateEvent.class];
    (void)[(ZMUpdateEvent *)[[(id)event stub] andReturnValue:OCMOCK_VALUE(ZMUpdateEventConversationKnock)] type];
    
    // expect
    [[[(id)mockKnockMessage expect] classMethod] createOrUpdateMessageFromUpdateEvent:event inManagedObjectContext:self.uiMOC prefetchResult:nil];
    
    // when
    [self.sut processEvents:@[event] liveEvents:NO prefetchResult:nil];
    
    // then
    [(id)mockKnockMessage stopMocking];
    [(id)mockKnockMessage verify];
    
}

- (ZMConversation *)insertGroupConversation
{
    ZMConversation *result = [self insertGroupConversationInMoc:self.uiMOC];
    XCTAssertTrue([self.uiMOC saveOrRollback]);
    return result;
}

- (void)checkThatRequestIsValid:(ZMUpstreamRequest *)request forPath:(NSString *)expectedPath failureRecorder:(ZMTFailureRecorder *)failureRecorder {
    FHAssertNotNil(failureRecorder, request);
    FHAssertNotNil(failureRecorder, request.transportRequest);
    FHAssertEqualObjects(failureRecorder, expectedPath, request.transportRequest.path);
    FHAssertEqual(failureRecorder, ZMMethodPOST, request.transportRequest.method);
    AssertIsValidUUIDString(request.transportRequest.payload[@"nonce"]);
}

- (ZMConversation *)insertGroupConversationInMoc:(NSManagedObjectContext *)moc
{
    ZMUser *user1 = [ZMUser insertNewObjectInManagedObjectContext:moc];
    user1.remoteIdentifier = [NSUUID createUUID];
    
    ZMUser *user2 = [ZMUser insertNewObjectInManagedObjectContext:moc];
    user2.remoteIdentifier = [NSUUID createUUID];
    
    ZMUser *user3 = [ZMUser insertNewObjectInManagedObjectContext:moc];
    user3.remoteIdentifier = [NSUUID createUUID];
    
    ZMConversation *conversation = [ZMConversation insertGroupConversationIntoManagedObjectContext:moc withParticipants:@[user1, user2, user3]];
    conversation.remoteIdentifier = [NSUUID createUUID];
    return conversation;
}

@end




@implementation ZMKnockTranscoderTests (Unread)

- (void)testThatItDoesNotSetTheHasUnreadKnockWhenReceivingAKnockOlderThatTheLastRead;
{
    [self.sut tearDown];
    self.sut = nil;
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        self.sut = [[ZMKnockTranscoder alloc] initWithManagedObjectContext:self.syncMOC];
        ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        conversation.remoteIdentifier = NSUUID.createUUID;
        conversation.lastEventID = self.createEventID;
        conversation.lastReadEventID = conversation.lastEventID;
        conversation.lastReadServerTimeStamp = [NSDate date];
        conversation.lastServerTimeStamp = conversation.lastReadServerTimeStamp;
        
        ZMEventID *eventID = [ZMEventID eventIDWithMajor:conversation.lastEventID.major - 1 minor:self.createEventID.minor];
        NSDate *knockDate = [conversation.lastServerTimeStamp dateByAddingTimeInterval:-10];
        
        ZMUser *otherUser = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        otherUser.remoteIdentifier = NSUUID.createUUID;
        
        NSDictionary *payload = @{@"conversation": conversation.remoteIdentifier.transportString,
                                  @"time": knockDate.transportString,
                                  @"data": @{@"nonce": NSUUID.createUUID,},
                                  @"from": otherUser.remoteIdentifier.transportString,
                                  @"id": eventID.transportString,
                                  @"type": @"conversation.knock"};
        ZMUpdateEvent *event = [ZMUpdateEvent eventFromEventStreamPayload:payload uuid:nil];
        
        // when
        [self.sut processEvents:@[event] liveEvents:YES prefetchResult:nil];
        
        // then
        XCTAssertEqual(conversation.conversationListIndicator, ZMConversationListIndicatorNone);
    }];
}

- (void)testThatItDoesNotSetTheHasUnreadKnockWhenReceivingAKnockFromSelf
{
    [self.sut tearDown];
    self.sut = nil;
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        self.sut = [[ZMKnockTranscoder alloc] initWithManagedObjectContext:self.syncMOC];
        ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        conversation.remoteIdentifier = NSUUID.createUUID;
        conversation.lastEventID = self.createEventID;
        conversation.lastReadEventID = conversation.lastEventID;
        conversation.lastReadServerTimeStamp = [NSDate date];
        conversation.lastServerTimeStamp = conversation.lastReadServerTimeStamp;
        
        ZMEventID *eventID = [ZMEventID eventIDWithMajor:conversation.lastEventID.major + 1 minor:self.createEventID.minor];
        NSDate *knockDate = [conversation.lastReadServerTimeStamp dateByAddingTimeInterval:10];
        
        NSDictionary *payload = @{@"conversation": conversation.remoteIdentifier.transportString,
                                  @"time": knockDate.transportString,
                                  @"data": @{@"nonce": NSUUID.createUUID,},
                                  @"from": self.syncSelfUser.remoteIdentifier.transportString,
                                  @"id": eventID.transportString,
                                  @"type": @"conversation.knock"};
        ZMUpdateEvent *event = [ZMUpdateEvent eventFromEventStreamPayload:payload uuid:nil];
        
        // when
        [self.sut processEvents:@[event] liveEvents:YES prefetchResult:nil];
        
        // then
        XCTAssertEqual(conversation.conversationListIndicator, ZMConversationListIndicatorNone);
    }];
}

@end

