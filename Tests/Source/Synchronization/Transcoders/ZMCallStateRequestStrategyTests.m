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


#import "ZMCallStateRequestStrategyTests.h"
#import "MessagingTest+EventFactory.h"
#import "WireSyncEngine_iOS_Tests-Swift.h"


@implementation ZMCallStateRequestStrategyTests

- (void)setUp
{
    [super setUp];
    
    [ZMUserSession setCallingProtocolStrategy:CallingProtocolStrategyVersion2];
    
    self.keys = [NSSet setWithArray:@[ZMConversationCallDeviceIsActiveKey, ZMConversationIsSendingVideoKey]];

    [self.syncMOC performGroupedBlockAndWait:^{
        self.syncOtherUser1 = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        self.syncOtherUser1.remoteIdentifier = NSUUID.createUUID;
        self.syncOtherUser2 = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        self.syncOtherUser2.remoteIdentifier = NSUUID.createUUID;
        self.syncSelfUser = [ZMUser selfUserInContext:self.syncMOC];
        self.syncSelfUser.remoteIdentifier = NSUUID.createUUID;
        
        self.syncGroupConversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        self.syncGroupConversation.remoteIdentifier = NSUUID.createUUID;
        self.syncGroupConversation.conversationType = ZMConversationTypeGroup;
        [self.syncGroupConversation.mutableOtherActiveParticipants addObject:self.syncOtherUser1];
        [self.syncGroupConversation.mutableOtherActiveParticipants addObject:self.syncOtherUser2];
        
        self.syncSelfToUser1Conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        self.syncSelfToUser1Conversation.remoteIdentifier = NSUUID.createUUID;
        self.syncSelfToUser1Conversation.conversationType = ZMConversationTypeOneOnOne;
        [self.syncSelfToUser1Conversation.mutableOtherActiveParticipants addObject:self.syncOtherUser1];
        self.syncSelfToUser1Conversation.connection = [ZMConnection insertNewObjectInManagedObjectContext:self.syncMOC];
        self.syncSelfToUser1Conversation.connection.status = ZMConnectionStatusAccepted;
        self.syncSelfToUser1Conversation.connection.to = self.syncOtherUser1;
        
        self.syncSelfToUser2Conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        self.syncSelfToUser2Conversation.remoteIdentifier = NSUUID.createUUID;
        self.syncSelfToUser2Conversation.conversationType = ZMConversationTypeOneOnOne;
        [self.syncSelfToUser2Conversation.mutableOtherActiveParticipants addObject:self.syncOtherUser2];
        self.syncSelfToUser2Conversation.connection = [ZMConnection insertNewObjectInManagedObjectContext:self.syncMOC];
        self.syncSelfToUser2Conversation.connection.status = ZMConnectionStatusAccepted;
        self.syncSelfToUser2Conversation.connection.to = self.syncOtherUser2;
        
        [self.syncMOC saveOrRollback];
    }];
    
    self.callFlowRequestStrategy = [OCMockObject niceMockForClass:[ZMCallFlowRequestStrategy class]];
    [self verifyMockLater:self.callFlowRequestStrategy];
    
    self.gsmCallHandler = [OCMockObject niceMockForClass:[ZMGSMCallHandler class]];
    [self verifyMockLater:self.gsmCallHandler];
    
    self.mockApplicationStatus.mockSynchronizationState = ZMSynchronizationStateEventProcessing;

    self.sut = (id) [[ZMCallStateRequestStrategy alloc] initWithManagedObjectContext:self.syncMOC applicationStatus:self.mockApplicationStatus callFlowRequestStrategy:self.callFlowRequestStrategy gsmCallHandler:self.gsmCallHandler];

    [self simulateOpeningPushChannel];
}

- (void)tearDown
{
    WaitForAllGroupsToBeEmpty(0.5);
    [self.syncGroupConversation.voiceChannelRouter.v2 tearDown];
    [self.syncSelfToUser1Conversation.voiceChannelRouter.v2 tearDown];
    [self.syncSelfToUser2Conversation.voiceChannelRouter.v2 tearDown];
    [ZMCallTimer resetTestCallTimeout];
    [ZMUserSession setCallingProtocolStrategy:CallingProtocolStrategyNegotiate];
    
    self.syncGroupConversation = nil;
    self.syncSelfToUser1Conversation = nil;
    self.syncSelfToUser2Conversation = nil;

    self.sut = nil;
    [super tearDown];
}

- (void)simulateClosingPushChannel
{
    [[NSNotificationCenter defaultCenter] postNotificationName:ZMPushChannelStateChangeNotificationName
                                                        object:nil
                                                      userInfo:@{ZMPushChannelIsOpenKey : @(NO)}];
}

- (void)simulateOpeningPushChannel
{
    [[NSNotificationCenter defaultCenter] postNotificationName:ZMPushChannelStateChangeNotificationName
                                                        object:nil
                                                      userInfo:@{ZMPushChannelIsOpenKey : @(YES)}];
}

- (void)tearDownVoiceChannelForSyncConversation:(ZMConversation *)syncConversation
{
    ZMConversation *uiConv = (id)[self.uiMOC objectWithID:syncConversation.objectID];
    [uiConv.voiceChannelRouter.v2 tearDown];
}

- (void)saveAndMergeCallState:(NSManagedObjectContext *)fromContext intoContext:(NSManagedObjectContext *)intoContext
{
    [fromContext saveOrRollback];
    
    [intoContext performGroupedBlockAndWait:^{
        NOT_USED([intoContext mergeCallStateChanges:[fromContext.zm_callState createCopyAndResetHasChanges]]);
    }];
}

- (ZMConversation *)insertUiConversationWithCallDeviceActive:(BOOL)callDeviceIsActive
{
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    conversation.remoteIdentifier = [NSUUID createUUID]; // Otherwise we'll try to insert it
    conversation.conversationType = ZMConversationTypeOneOnOne; // We only don't update 'invalid' type
    conversation.callDeviceIsActive = callDeviceIsActive;
    XCTAssertTrue(conversation.hasLocalModificationsForCallDeviceIsActive);
    [self.uiMOC saveOrRollback];
    NOT_USED([self.syncMOC mergeCallStateChanges:self.uiMOC.zm_callState]);
    return conversation;
}

- (NSDictionary *)payloadForConversation:(ZMConversation *)conversation othersAreJoined:(BOOL)othersAreJoined selfIsJoined:(BOOL)selfIsJoined
{
    return [self payloadForCallStateEventInConversation:conversation othersAreJoined:othersAreJoined selfIsJoined:selfIsJoined sequence:nil];
}

- (void)testThatUsesCorrectRequestStrategyConfiguration
{
    XCTAssertEqual(self.sut.configuration, ZMStrategyConfigurationOptionAllowsRequestsDuringEventProcessing);
}

- (void)testThatItReturnsTheContextChangeTrackers;
{
    // when
    NSArray *trackers = self.sut.contextChangeTrackers;
    
    // then
    XCTAssertEqual(trackers.count, 3u);
    XCTAssertTrue([trackers.firstObject isKindOfClass:ZMCallStateRequestStrategy.class]);
    XCTAssertTrue([trackers[1] isKindOfClass:ZMDownstreamObjectSync.class]);
    XCTAssertTrue([trackers.lastObject isKindOfClass:ZMUpstreamModifiedObjectSync.class]);
}

- (void)testThatItReturnsARequestForAConversationThatNeedCallStateToBeSynced
{
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        ZMConversation *conversation = self.syncSelfToUser1Conversation;
        conversation.callStateNeedsToBeUpdatedFromBackend = YES;
        
        for(id<ZMContextChangeTracker> tracker in self.sut.contextChangeTrackers)
        {
            [tracker objectsDidChange:[NSSet setWithObject:conversation]];
        }
        
        // when
        ZMTransportRequest *request = [self.sut nextRequest];
        
        // then
        XCTAssertNotNil(request);
    }];
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatItDoesReturnANilRequestForAConversationThatDoesNotNeedCallStateToBeSynced
{
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        ZMConversation *conversation = self.syncSelfToUser1Conversation;
        conversation.needsToBeUpdatedFromBackend = YES;
        conversation.callStateNeedsToBeUpdatedFromBackend = NO;
        
        for(id<ZMContextChangeTracker> tracker in self.sut.contextChangeTrackers)
        {
            [tracker objectsDidChange:[NSSet setWithObject:conversation]];
        }
        
        // when
        ZMTransportRequest *request = [self.sut nextRequest];
        
        // then
        XCTAssertNil(request);
    }];
    
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatItDoesReturnANilRequestForAConversationThatDoesNotNeedCallStateToBeSynced_ButIsWaitingForMerge
{
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        ZMConversation *conversation = self.syncSelfToUser1Conversation;
        conversation.needsToBeUpdatedFromBackend = YES;
        conversation.callStateNeedsToBeUpdatedFromBackend = NO;
        
        for(id<ZMContextChangeTracker> tracker in self.sut.contextChangeTrackers)
        {
            [tracker objectsDidChange:[NSSet setWithObject:conversation]];
        }
        
        // when
        ZMTransportRequest *request = [self.sut nextRequest];
        
        // then
        XCTAssertNil(request);
    }];
    
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatItDoesReturnANilRequestForAConversationWithoutARemoteID
{
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        conversation.callStateNeedsToBeUpdatedFromBackend = YES;
        conversation.remoteIdentifier = nil;
        conversation.conversationType = ZMConversationTypeOneOnOne;
        [self.syncMOC saveOrRollback];
        
        for(id<ZMContextChangeTracker> tracker in self.sut.contextChangeTrackers)
        {
            [tracker objectsDidChange:[NSSet setWithObject:conversation]];
        }
        
        // when
        ZMTransportRequest *request = [self.sut nextRequest];
        
        // then
        XCTAssertNil(request);
    }];
    
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatItDoesReturnANilRequestForAnInvalidConversation
{
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        conversation.callStateNeedsToBeUpdatedFromBackend = YES;
        conversation.needsToBeUpdatedFromBackend = YES;
        conversation.conversationType = ZMConversationTypeInvalid;
        conversation.remoteIdentifier = [NSUUID createUUID];
        [self.syncMOC saveOrRollback];
        
        for(id<ZMContextChangeTracker> tracker in self.sut.contextChangeTrackers)
        {
            [tracker objectsDidChange:[NSSet setWithObject:conversation]];
        }
        
        // when
        ZMTransportRequest *request = [self.sut nextRequest];
        
        // then
        XCTAssertNil(request);
    }];
    
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatItDoesReturnANilRequestForAConversationWhereSelfUserIsNotActiveMember
{
    __block ZMConversation *conversation;

    [self.syncMOC performGroupedBlockAndWait:^{
        conversation = self.syncGroupConversation;
        conversation.callStateNeedsToBeUpdatedFromBackend = YES;
        conversation.needsToBeUpdatedFromBackend = YES;
        conversation.isSelfAnActiveMember = NO;
        
        for(id<ZMContextChangeTracker> tracker in self.sut.contextChangeTrackers)
        {
            [tracker objectsDidChange:[NSSet setWithObject:conversation]];
        }
        
        // when
        ZMTransportRequest *request = [self.sut nextRequest];
        
        // then
        XCTAssertNil(request);

    }];
    
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)checkThatItGeneratesARequestForAConversationThatNeedCallStateToBeSyncedWithBlock:(void (^)(ZMConversation* conversation))block
{
    __block ZMConversation *conversation;
    
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        conversation = self.syncSelfToUser1Conversation;
        conversation.callStateNeedsToBeUpdatedFromBackend = YES;
        
        // when
        block(conversation);
        ZMTransportRequest *request = [self.sut nextRequest];
        
        // then
        XCTAssertNotNil(request);
        NSString *path = [NSString stringWithFormat:@"/conversations/%@/call/state", conversation.remoteIdentifier.transportString];
        XCTAssertEqualObjects(request.path, path);
        XCTAssertEqual(request.method, ZMMethodGET);
        XCTAssertNil(request.payload);
    }];
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testItGeneratesARequestForAConversationThatNeedCallStateToBeSynced_OnInitialization
{
    [self checkThatItGeneratesARequestForAConversationThatNeedCallStateToBeSyncedWithBlock:^(ZMConversation *conversation) {
        NOT_USED(conversation);
        [ZMChangeTrackerBootstrap bootStrapChangeTrackers:self.sut.contextChangeTrackers onContext:self.syncMOC];
    }];
    
}

- (void)testItGeneratesARequestForAConversationThatNeedCallStateToBeSynced_OnObjectsDidChange
{
    [self checkThatItGeneratesARequestForAConversationThatNeedCallStateToBeSyncedWithBlock:^(ZMConversation *conversation) {
        [self.sut.contextChangeTrackers[1] objectsDidChange:[NSSet setWithObject:conversation]];
    }];
    
}

- (void)testThatItResetsTheCallStateToBeSyncedOnASuccessfulRequestWithBlock:(void(^)(ZMConversation *conversation))block
{
    __block ZMConversation *conversation;
    
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        conversation = self.syncSelfToUser1Conversation;
        conversation.callStateNeedsToBeUpdatedFromBackend = YES;

        NSDictionary *payload = @{
                                  @"self":@{@"state":@"joined"},
                                  @"participants":@{}
                                  };
        
        // when
        block(conversation);
        ZMTransportRequest *request = [self.sut nextRequest];
        [request completeWithResponse:[ZMTransportResponse responseWithPayload:payload HTTPStatus:200 transportSessionError:nil]];
    }];
        WaitForAllGroupsToBeEmpty(0.5);
    
    [self.syncMOC performGroupedBlockAndWait:^{
        // then
        XCTAssertFalse(conversation.callStateNeedsToBeUpdatedFromBackend);
    }];
}

- (void)testThatItResetsTheCallStateToBeSyncedOnASuccessfulRequest_OnInitialization
{
    [self testThatItResetsTheCallStateToBeSyncedOnASuccessfulRequestWithBlock:^(ZMConversation *conversation) {
        NOT_USED(conversation);
        [ZMChangeTrackerBootstrap bootStrapChangeTrackers:self.sut.contextChangeTrackers onContext:self.syncMOC];
    }];
    
}

- (void)testThatItResetsTheCallStateToBeSyncedOnASuccessfulRequest_OnObjectsDidChange
{
    [self testThatItResetsTheCallStateToBeSyncedOnASuccessfulRequestWithBlock:^(ZMConversation *conversation) {
        [self.sut.contextChangeTrackers[1] objectsDidChange:[NSSet setWithObject:conversation]];
    }];
    
}

- (void)shouldResetCallState:(BOOL)shouldResetState forHTTPStatus:(NSInteger)HTTPStatus WithBlock:(void(^)(ZMConversation *conversation))block;
{
    __block ZMConversation *conversation;
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        conversation = self.syncSelfToUser1Conversation;
        conversation.callStateNeedsToBeUpdatedFromBackend = YES;
        
        // when
        block(conversation);
        ZMTransportRequest *request = [self.sut nextRequest];
        [request completeWithResponse:[ZMTransportResponse responseWithPayload:nil HTTPStatus:HTTPStatus transportSessionError:nil]];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    [self.syncMOC performGroupedBlockAndWait:^{
        // then
        if (shouldResetState) {
            XCTAssertFalse(conversation.callStateNeedsToBeUpdatedFromBackend);
        }
        else {
            XCTAssertTrue(conversation.callStateNeedsToBeUpdatedFromBackend);
        }
    }];
    WaitForAllGroupsToBeEmpty(0.5);

}

- (void)testThatItResetsTheCallStateToBeSyncedOnAFailedRequest_OnInitialization
{
    [self shouldResetCallState:YES forHTTPStatus:400 WithBlock:^(ZMConversation *conversation) {
        NOT_USED(conversation);
        [ZMChangeTrackerBootstrap bootStrapChangeTrackers:self.sut.contextChangeTrackers onContext:self.syncMOC];
    }];
    
}

- (void)testThatItResetsTheCallStateToBeSyncedOnAFailedRequest_OnObjectsDidChange
{
    [self shouldResetCallState:YES forHTTPStatus:400 WithBlock:^(ZMConversation *conversation) {
        [self.sut.contextChangeTrackers[1] objectsDidChange:[NSSet setWithObject:conversation]];
    }];
    
}

- (void)testThatItDoesNotResetsTheCallStateToBeSyncedOnATemporaryFailedRequest_OnInitialization
{
    [self shouldResetCallState:NO forHTTPStatus:505 WithBlock:^(ZMConversation *conversation) {
        NOT_USED(conversation);
        [ZMChangeTrackerBootstrap bootStrapChangeTrackers:self.sut.contextChangeTrackers onContext:self.syncMOC];
    }];
    
}

- (void)testThatItDoesNotResetsTheCallStateToBeSyncedOnATemporaryFailedRequest_OnObjectsDidChange
{
    [self shouldResetCallState:NO forHTTPStatus:505 WithBlock:^(ZMConversation *conversation) {
        [self.sut.contextChangeTrackers[0] objectsDidChange:[NSSet setWithObject:conversation]];
    }];
    
}

- (void)testThatItUpdatesAConversationThatNeedCallStateToBeSynced_Joined_ButDoesNotSetTheDeviceActive
{
    __block ZMConversation *conversation;
    
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        conversation = self.syncSelfToUser1Conversation;
        conversation.callStateNeedsToBeUpdatedFromBackend = YES;
        conversation.callDeviceIsActive = NO;
        
        NSDictionary *payload = @{
                                  @"self":@{@"state":@"joined"},
                                  @"participants":@{}
                                  };
        ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:payload HTTPStatus:200 transportSessionError:nil];
        
        // when
        [self.sut updateObject:conversation withResponse:response downstreamSync:nil];
        
        // then
        XCTAssertFalse(conversation.callDeviceIsActive);
    }];
    WaitForAllGroupsToBeEmpty(0.5);
}


- (void)testThatItUpdatesAConversationThatNeedCallStateToBeSynced_NotJoined
{
    __block ZMConversation *conversation;
    
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        conversation = self.syncSelfToUser1Conversation;
        conversation.callStateNeedsToBeUpdatedFromBackend = YES;
        conversation.callDeviceIsActive = YES;
        
        NSDictionary *payload = @{
                                  @"self":@{@"state":@"idle"},
                                  @"participants":@{}
                                  };
        ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:payload HTTPStatus:200 transportSessionError:nil];
        
        // when
        [self.sut updateObject:conversation withResponse:response downstreamSync:nil];
        
        // then
        XCTAssertFalse(conversation.callDeviceIsActive);
    }];
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatItDoesUpdateAConversationsCallDeviceIsActiveEvenWhenItHasLocalModificationsIfItIsAResponse
{
    // given
    ZMConversation *uiConversation = [self insertUiConversationWithCallDeviceActive:YES];

    NSDictionary *payload = @{
                              @"self":@{@"state":@"idle"},
                              @"participants":@{}
                              };
    ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:payload HTTPStatus:200 transportSessionError:nil];
    
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMConversation *syncConversation = (id)[self.syncMOC objectWithID:uiConversation.objectID];

        // when
        [self.sut updateObject:syncConversation withResponse:response downstreamSync:nil];
        
        // then
        XCTAssertFalse(syncConversation.callDeviceIsActive);
        
        [syncConversation.voiceChannelRouter.v2 tearDown];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatItDoesNotUpdateAConversationThatNeedCallStateToBeSynced_Joined_fromPushEventButItDoesNotSetTheDeviceActive
{
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        ZMConversation *conversation = self.syncSelfToUser1Conversation;
        conversation.callStateNeedsToBeUpdatedFromBackend = YES;
        conversation.callDeviceIsActive = NO;
        
        NSDictionary *payload = @{
                                  @"id" : NSUUID.createUUID.transportString,
                                  @"payload" : @[
                                          @{
                                              @"type": @"call.state",
                                              @"conversation": conversation.remoteIdentifier.transportString,
                                              @"self":@{
                                                      @"state":@"joined"
                                                      },
                                              @"participants":@{},
                                              }
                                          ]
                                  };
        
        ZMUpdateEvent *event = [ZMUpdateEvent eventsArrayFromPushChannelData:payload][0];
        
        // when
        [self.sut processEvents:@[event] liveEvents:YES prefetchResult:nil];
        
        // then
        XCTAssertFalse(conversation.callDeviceIsActive);
    }];
    
    WaitForAllGroupsToBeEmpty(0.5);
}


- (void)testThatItDoesNotUpdatesConversationThatNeedCallStateToBeSynced_NotJoined_fromPushChannel_LiveEvent
{
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        ZMConversation *conversation = self.syncSelfToUser1Conversation;
        conversation.callStateNeedsToBeUpdatedFromBackend = YES;
        conversation.callDeviceIsActive = YES;
        
        NSDictionary *payload = @{
                                  @"id" : NSUUID.createUUID.transportString,
                                  @"payload" : @[
                                          @{
                                              @"type": @"call.state",
                                              @"conversation": conversation.remoteIdentifier.transportString,
                                              @"self":@{
                                                      @"state":@"idle"
                                                      },
                                              @"participants":@{},
                                              }
                                          ]
                                  };
        
        ZMUpdateEvent *event = [ZMUpdateEvent eventsArrayFromPushChannelData:payload][0];
        
        // when
        [self.sut processEvents:@[event] liveEvents:YES prefetchResult:nil];
        
        // then
        XCTAssertTrue(conversation.callDeviceIsActive);
    }];
    
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatItDoesNotUpdateAConversationThatNeedCallStateToBeSynced_NotJoined_fromPushChannel_NotLiveEvent
{
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        ZMConversation *conversation = self.syncSelfToUser1Conversation;
        conversation.callStateNeedsToBeUpdatedFromBackend = YES;
        conversation.callDeviceIsActive = YES;
        
        NSDictionary *payload = @{
                                  @"id" : NSUUID.createUUID.transportString,
                                  @"payload" : @[
                                          @{
                                              @"type": @"call.state",
                                              @"conversation": conversation.remoteIdentifier.transportString,
                                              @"self":@{
                                                      @"state":@"idle"
                                                      },
                                              @"participants":@{},
                                              }
                                          ]
                                  };
        
        ZMUpdateEvent *event = [ZMUpdateEvent eventsArrayFromPushChannelData:payload][0];
        
        // when
        [self.sut processEvents:@[event] liveEvents:NO prefetchResult:nil];
        
        // then
        XCTAssertTrue(conversation.callDeviceIsActive);
    }];
    
    WaitForAllGroupsToBeEmpty(0.5);
}


- (void)testThatItForwardsTheSessionIDToTheFlowSync
{
    __block ZMConversation *conversation;
    
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        conversation = self.syncSelfToUser1Conversation;
        conversation.callStateNeedsToBeUpdatedFromBackend = YES;
        conversation.callDeviceIsActive = NO;

        NSUUID *conversationID = conversation.remoteIdentifier;
        NSString *sessionID = @"test-session-id";
        
        NSDictionary *payload = @{
                                  @"session": sessionID,
                                  @"self":@{@"state":@"joined"},
                                  @"participants":@{}
                                  };
        ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:payload HTTPStatus:200 transportSessionError:nil];
        
        // expect
        [[self.callFlowRequestStrategy expect] setSessionIdentifier:sessionID forConversationIdentifier:conversationID];
        
        // when
        [self.sut updateObject:conversation withResponse:response downstreamSync:nil];
        
        // then
        [self.callFlowRequestStrategy verify];
    }];
    
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatItSetsTheSessionDebugInformation
{
    // given
    [VoiceChannelV2 setLastSessionIdentifier:nil];
    [VoiceChannelV2 setLastSessionStartDate:nil];
    XCTAssertNil([VoiceChannelV2 lastSessionIdentifier]);
    XCTAssertNil([VoiceChannelV2 lastSessionStartDate]);
    
    NSString *sessionID = @"foobar-session-id";
    NSDate *sessionDate = [NSDate date];
    __block ZMConversation *conversation;

    [self.syncMOC performGroupedBlockAndWait:^{
        conversation = self.syncSelfToUser1Conversation;
        conversation.callStateNeedsToBeUpdatedFromBackend = YES;
        conversation.callDeviceIsActive = NO;

        NSDictionary *payload = @{
                                  @"session": sessionID,
                                  @"self":@{@"state":@"joined"},
                                  @"participants":@{}
                                  };
        ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:payload HTTPStatus:200 transportSessionError:nil];
        
        // expect
        [[self.callFlowRequestStrategy stub] setSessionIdentifier:OCMOCK_ANY forConversationIdentifier:OCMOCK_ANY];
        
        // when
        [self.sut updateObject:conversation withResponse:response downstreamSync:nil];
    }];
    WaitForAllGroupsToBeEmpty(0.1);
    
    // then
    XCTAssertEqualObjects([VoiceChannelV2 lastSessionIdentifier], sessionID);
    XCTAssertEqualWithAccuracy([VoiceChannelV2 lastSessionStartDate].timeIntervalSinceReferenceDate, sessionDate.timeIntervalSinceReferenceDate, 0.05);

}

@end



@implementation ZMCallStateRequestStrategyTests (Participants)

- (ZMUser *)createUser;
{
    ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
    user.remoteIdentifier = [NSUUID createUUID];
    return user;
}


- (void)testThatItDoesNotFetchConversationThatAreNotOneToOneOrGroup
{
    {
        ZMConversation *oneToOneConversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
        oneToOneConversation.callStateNeedsToBeUpdatedFromBackend = YES;
        oneToOneConversation.remoteIdentifier = [NSUUID createUUID];
        oneToOneConversation.conversationType = ZMConversationTypeOneOnOne;
        
        XCTAssertTrue([[ZMConversation predicateForNeedingCallStateToBeUpdatedFromBackend] evaluateWithObject:oneToOneConversation]);
    }
    
    for(NSNumber *type in @[@(ZMConversationTypeSelf), @(ZMConversationTypeInvalid), @(ZMConversationTypeConnection)])
    {
        ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
        conversation.callStateNeedsToBeUpdatedFromBackend = YES;
        conversation.remoteIdentifier = [NSUUID createUUID];
        conversation.conversationType = (ZMConversationType) [type intValue];
        
        XCTAssertFalse([[ZMConversation predicateForNeedingCallStateToBeUpdatedFromBackend] evaluateWithObject:conversation]);
    }
    

}

- (void)testThatItUpdatesParticipantsOnAConversationThatNeedCallStateToBeSynced_NotJoined
{
    __block ZMConversation *conversation;
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        conversation = self.syncGroupConversation;
        conversation.callStateNeedsToBeUpdatedFromBackend = YES;
        conversation.callDeviceIsActive = YES;

        // {
        //   "participants": {
        //     "90c74fe0-cef7-446a-affb-6cba0e75d5da": {
        //       "state": "joined",
        //       "quality": 0.5
        //     },
        //     "08316f5e-3c0a-4847-a235-2b4d93f291a4": {
        //       "state": "idle",
        //       "quality": null
        //     }
        //   },
        //   "self": {
        //     "state": "idle",
        //     "quality": null
        //   },
        //   "flows": [
        //     {
        //       "active": false,
        //       "id": "5e0bd0be-0725-475c-9345-c38ae9dcd3f2"
        //     }
        //   ]
        // }
        
        NSDictionary *payload = @{@"self":@{@"state":@"joined"},
                                  @"participants": @{
                                          self.syncSelfUser.remoteIdentifier.transportString: @{
                                                  @"state": @"joined",
                                                  },
                                          self.syncOtherUser1.remoteIdentifier.transportString: @{
                                                  @"state": @"joined",
                                                  },
                                          self.syncOtherUser2.remoteIdentifier.transportString: @{
                                                  @"state": @"idle",
                                                  },
                                          
                                  }};
        ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:payload HTTPStatus:200 transportSessionError:nil];
        
        // when
        [self.sut updateObject:conversation withResponse:response downstreamSync:nil];
        
        // then
        XCTAssertTrue(conversation.callDeviceIsActive);
        
        NSArray *participants = conversation.callParticipants.array;
        XCTAssertEqual(participants.count, 2u);

        NSArray *expectedUsers = @[self.syncSelfUser, self.syncOtherUser1];
        AssertArraysContainsSameObjects(participants, expectedUsers);
    }];
    
    WaitForAllGroupsToBeEmpty(0.5);
}


- (void)testThatItProcessesUpdateEvents
{
    __block ZMConversation *conversation;

    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        conversation = self.syncGroupConversation;
        conversation.callDeviceIsActive = YES;

        // {
        //   "participants": {
        //     "90c74fe0-cef7-446a-affb-6cba0e75d5da": {
        //       "state": "joined",
        //       "quality": 0.5
        //     },
        //     "08316f5e-3c0a-4847-a235-2b4d93f291a4": {
        //       "state": "idle",
        //       "quality": null
        //     }
        //   },
        //   "self": {
        //     "state": "idle",
        //     "quality": null
        //   },
        //   "flows": [
        //     {
        //       "active": false,
        //       "id": "5e0bd0be-0725-475c-9345-c38ae9dcd3f2"
        //     }
        //   ]
        // }
        
        NSDictionary *payload = @{
                                  @"id" : NSUUID.createUUID.transportString,
                                  @"payload" : @[
                                          @{
                                              @"type": @"call.state",
                                              @"conversation": conversation.remoteIdentifier.transportString,
                                              @"self":@{
                                                      @"state":@"joined"
                                                      },
                                              @"participants": @{
                                                      self.syncSelfUser.remoteIdentifier.transportString: @{
                                                              @"state": @"joined",
                                                              },
                                                      self.syncOtherUser1.remoteIdentifier.transportString: @{
                                                              @"state": @"joined",
                                                              },
                                                      self.syncOtherUser2.remoteIdentifier.transportString: @{
                                                              @"state": @"idle",
                                                              },
                                                      
                                                      }
                                              }
                                          ]
                                  };
        
        ZMUpdateEvent *event = [ZMUpdateEvent eventsArrayFromPushChannelData:payload][0];
        
        // when
        [self.sut processEvents:@[event] liveEvents:YES prefetchResult:nil];

        // then
        XCTAssertTrue(conversation.callDeviceIsActive);
        
        NSArray *participants = conversation.callParticipants.array;
        XCTAssertEqual(participants.count, 2u);

        NSArray *expectedUsers = @[self.syncSelfUser, self.syncOtherUser1];
        AssertArraysContainsSameObjects(participants, expectedUsers);
    }];
    
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatItDoNotProcessUpdateEventsForConversationWhereSelfUserIsNotActiveMember
{
    __block ZMConversation *conversation;
    
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        conversation = self.syncGroupConversation;
        conversation.callStateNeedsToBeUpdatedFromBackend = YES;
        conversation.callDeviceIsActive = YES;
        
        NSDictionary *payload = @{
                                  @"id" : NSUUID.createUUID.transportString,
                                  @"payload" : @[
                                          @{
                                              @"type": @"call.state",
                                              @"conversation": conversation.remoteIdentifier.transportString,
                                              @"self":@{
                                                      @"state":@"joined"
                                                      },
                                              @"participants": @{
                                                      self.syncSelfUser.remoteIdentifier.transportString: @{
                                                              @"state": @"joined"
                                                              },
                                                      self.syncOtherUser1.remoteIdentifier.transportString: @{
                                                              @"state": @"joined",
                                                              },
                                                      self.syncOtherUser2.remoteIdentifier.transportString: @{
                                                              @"state": @"joined",
                                                              }
                                                      }
                                              }
                                          ]
                                  };
        
        ZMUpdateEvent *event = [ZMUpdateEvent eventsArrayFromPushChannelData:payload][0];
        [self.sut processEvents:@[event] liveEvents:YES prefetchResult:nil];
        
        // when
        [conversation removeParticipant:self.syncSelfUser]; // we should also leave call

        //then we get some call state update while backend didn't yet processed our leave request
        //we shoul dignore such events
        
        NSDictionary *ignoredPayload = @{
                    @"id" : NSUUID.createUUID.transportString,
                    @"payload" : @[
                            @{
                                @"type": @"call.state",
                                @"conversation": conversation.remoteIdentifier.transportString,
                                @"self":@{
                                        @"state":@"idle"
                                        },
                                @"participants": @{
                                        self.syncSelfUser.remoteIdentifier.transportString: @{
                                                @"state": @"idle"
                                                },
                                        self.syncOtherUser1.remoteIdentifier.transportString: @{
                                                @"state": @"joined",
                                                },
                                        self.syncOtherUser2.remoteIdentifier.transportString: @{
                                                @"state": @"joined",
                                                }
                                        }
                                }
                            ]
                    };

        ZMUpdateEvent *ignoredEvent = [ZMUpdateEvent eventsArrayFromPushChannelData:ignoredPayload][0];

        // when
        [self.sut processEvents:@[ignoredEvent] liveEvents:YES prefetchResult:nil];
        
        //then
        XCTAssertEqual(conversation.callParticipants.array.count, 0u);

    }];
    
    WaitForAllGroupsToBeEmpty(0.5);
}


- (void)testThatItUpdatesTheParticipantsFromAPushEvent
{
    __block ZMConversation *conversation;
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        conversation = self.syncGroupConversation;
        conversation.callDeviceIsActive = YES;
        [conversation.voiceChannelRouter.v2 addCallParticipant:self.syncOtherUser1];
        [conversation.voiceChannelRouter.v2 addCallParticipant:self.syncOtherUser2];
        [conversation.voiceChannelRouter.v2 addCallParticipant:self.syncSelfUser];
        
        NSDictionary *payload = @{@"id" : NSUUID.createUUID.transportString,
                                  @"payload" : @[@{@"type": @"call.state",
                                                   @"conversation": conversation.remoteIdentifier.transportString,
                                                   @"participants":@{
                                                           self.syncSelfUser.remoteIdentifier.transportString: @{
                                                                   @"state": @"idle",
                                                                   },
                                                           self.syncOtherUser1.remoteIdentifier.transportString: @{
                                                                   @"state": @"joined",
                                                                   },
                                                           },
                                                   }]
                                  };
        ZMUpdateEvent *event = [ZMUpdateEvent eventsArrayFromPushChannelData:payload][0];
        
        // when
        [self.sut processEvents:@[event] liveEvents:YES prefetchResult:nil];
        
        // then
        XCTAssertEqual(conversation.callParticipants.count, 1u);
        XCTAssertFalse([conversation.callParticipants containsObject:self.syncSelfUser]);
        XCTAssertFalse([conversation.callParticipants containsObject:self.syncOtherUser2]);
        XCTAssertTrue([conversation.callParticipants containsObject:self.syncOtherUser1]);
    }];
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatItDoesNotCrashWhenItReceivesAnEventForAConversationThatDoesNotExist;
{
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        NSDictionary *payload = @{
                                  @"id" : NSUUID.createUUID.transportString,
                                  @"payload" : @[
                                          @{@"type": @"call.state",
                                            @"conversation": NSUUID.createUUID.transportString,
                                            @"self":@{@"state":@"joined"},
                                            @"participants": @{
                                                    NSUUID.createUUID.transportString: @{@"state": @"joined",},
                                                    NSUUID.createUUID.transportString: @{@"state": @"idle",},
                                                    }
                                            }
                                          ]
                                  };
        
        ZMUpdateEvent *event = [ZMUpdateEvent eventsArrayFromPushChannelData:payload][0];
        
        // when
        [self.sut processEvents:@[event] liveEvents:YES prefetchResult:nil];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
}

@end



@implementation ZMCallStateRequestStrategyTests (Ignore)

- (ZMConversation *)selfToUser1SyncConversationWithOutgoingCall
{
    ZMConversation *conversation = self.syncSelfToUser1Conversation;
    
    [conversation.voiceChannelRouter.v2 addCallParticipant:self.syncSelfUser];
    conversation.callDeviceIsActive = YES;
    return conversation;
}

- (ZMConversation *)groupConversationWithIncomingCall
{
    ZMConversation *conversation = self.syncGroupConversation;
    [conversation.voiceChannelRouter.v2 addCallParticipant:self.syncOtherUser1];
    [conversation.voiceChannelRouter.v2 addCallParticipant:self.syncOtherUser2];

    return conversation;
}

- (ZMConversation *)groupConversationWithConnectingCall
{
    ZMConversation *conversation = self.syncGroupConversation;
    [conversation.voiceChannelRouter.v2 addCallParticipant:self.syncOtherUser1];
    [conversation.voiceChannelRouter.v2 addCallParticipant:self.syncOtherUser2];
    [conversation.voiceChannelRouter.v2 addCallParticipant:self.syncSelfUser];
    conversation.callDeviceIsActive = YES;

    return conversation;
}


- (ZMConversation *)selfToUser1SyncConversationWithConnectedCall
{
    ZMConversation *activeCallConversation = [self selfToUser1SyncConversationWithOutgoingCall];
    [activeCallConversation.voiceChannelRouter.v2 addCallParticipant:self.syncOtherUser1];
    [activeCallConversation.voiceChannelRouter.v2 updateActiveFlowParticipants:@[self.syncOtherUser1]];
    activeCallConversation.isFlowActive = YES;
    return activeCallConversation;
}


- (void)testThatItDoesNotIgnoreAConversationAfterACallStateUpdateEventIfThereIsAnotherActiveCall
{
    __block ZMConversation *activeCallConversation;

    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        activeCallConversation = [self selfToUser1SyncConversationWithOutgoingCall];
        XCTAssertEqual(activeCallConversation.voiceChannelRouter.v2.state, VoiceChannelV2StateOutgoingCall);
        
        ZMConversation *incomingCallConversation = self.syncSelfToUser2Conversation;
        XCTAssertEqual(incomingCallConversation.voiceChannelRouter.v2.state, VoiceChannelV2StateNoActiveUsers);

        NSDictionary *payload = @{@"id" : NSUUID.createUUID.transportString,
                                  @"payload" : @[@{@"type": @"call.state",
                                                   @"conversation": incomingCallConversation.remoteIdentifier.transportString,
                                                   @"participants":@{
                                                           self.syncOtherUser2.remoteIdentifier.transportString: @{
                                                                   @"state": @"joined",
                                                                   },
                                                           self.syncSelfUser.remoteIdentifier.transportString: @{
                                                                   @"state": @"idle",
                                                                   }
                                                           }
                                                   }]
                                  };
        ZMUpdateEvent *event = [ZMUpdateEvent eventsArrayFromPushChannelData:payload][0];
        
        // when
        [self.sut processEvents:@[event] liveEvents:YES prefetchResult:nil];
        
        // then
        XCTAssertFalse(incomingCallConversation.isIgnoringCall);
        XCTAssertEqual(incomingCallConversation.voiceChannelRouter.v2.state, VoiceChannelV2StateIncomingCall);

    }];
    WaitForAllGroupsToBeEmpty(0.5);
}


- (void)testThatWhenSomeoneJoinsAVoiceChannelWeDoNotIgnoreThatConversationIfWeAreAlreadyOnAnActiveVoiceChannel
{
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        ZMConversation *activeCallConversation = [self selfToUser1SyncConversationWithConnectedCall];
        XCTAssertEqual(activeCallConversation.voiceChannelRouter.v2.state, VoiceChannelV2StateSelfConnectedToActiveChannel);
        
        ZMConversation *incomingCallConversation = self.syncSelfToUser2Conversation;
        XCTAssertEqual(incomingCallConversation.voiceChannelRouter.v2.state, VoiceChannelV2StateNoActiveUsers);
        
        // when
        NSDictionary *payload = @{@"id" : NSUUID.createUUID.transportString,
                                  @"payload" : @[@{@"type": @"call.state",
                                                   @"conversation": incomingCallConversation.remoteIdentifier.transportString,
                                                   @"participants":@{
                                                           self.syncOtherUser2.remoteIdentifier.transportString: @{
                                                                   @"state": @"joined",
                                                                   },
                                                           self.syncSelfUser.remoteIdentifier.transportString: @{
                                                                   @"state": @"idle",
                                                                   }
                                                           }
                                                   }]
                                  };
        ZMUpdateEvent *event = [ZMUpdateEvent eventsArrayFromPushChannelData:payload][0];
        
        // when
        [self.sut processEvents:@[event] liveEvents:YES prefetchResult:nil];
        
        // then
        XCTAssertFalse(incomingCallConversation.isIgnoringCall);
        XCTAssertEqual(incomingCallConversation.voiceChannelRouter.v2.state, VoiceChannelV2StateIncomingCall);
    }];
    
    WaitForAllGroupsToBeEmpty(0.5);
}


- (void)testThatWhenSomeoneJoinsAVoiceChannelWeIgnoreThatConversation_DownstreamSync
{

    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        ZMConversation *incomingCallConversation = [self groupConversationWithIncomingCall];
        
        // when
        NSDictionary *payload = @{
                                  @"self":@{@"state":@"idle"},
                                  @"participants":@{
                                          [(ZMConversation *)incomingCallConversation.otherActiveParticipants.firstObject remoteIdentifier].transportString : @{
                                                  @"state": @"joined",
                                                  },
                                          [[ZMUser selfUserInContext:self.syncMOC] remoteIdentifier].transportString: @{
                                                  @"state": @"idle"
                                                  }
                                          }
                                  };
        ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:payload HTTPStatus:200 transportSessionError:nil];
        [self.sut updateObject:incomingCallConversation withResponse:response downstreamSync:nil];
        
        // then
        XCTAssertTrue(incomingCallConversation.isIgnoringCall);
        XCTAssertEqual(incomingCallConversation.voiceChannelRouter.v2.state, VoiceChannelV2StateIncomingCallInactive);
    }];
    WaitForAllGroupsToBeEmpty(0.5);
}




- (void)checkThatItSetsIsIgnoringCallTo:(BOOL)shouldBeIgnoringCall whenTheCallEndsWithBlock:(void(^)(ZMConversation *))block
{
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        ZMConversation *activeCallConversation = [self groupConversationWithConnectingCall];
        XCTAssertEqual(activeCallConversation.voiceChannelRouter.v2.state, VoiceChannelV2StateSelfIsJoiningActiveChannel);
        
        //when
        [activeCallConversation.voiceChannelRouter.v2 leave];
        XCTAssertTrue(activeCallConversation.isIgnoringCall);

        // then
        XCTAssertEqual(activeCallConversation.voiceChannelRouter.v2.state, VoiceChannelV2StateIncomingCallInactive);
        
        //and when
        block(activeCallConversation);
        
        // then
        if (shouldBeIgnoringCall) {
            XCTAssertTrue(activeCallConversation.isIgnoringCall);
            XCTAssertEqual(activeCallConversation.voiceChannelRouter.v2.state, VoiceChannelV2StateIncomingCallInactive);
            
        } else {
            XCTAssertFalse(activeCallConversation.isIgnoringCall);
            XCTAssertEqual(activeCallConversation.voiceChannelRouter.v2.state, VoiceChannelV2StateNoActiveUsers);
        }
        
    }];
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatItResetsIsIgnoringCallIfALeftCallIsDroppedByTheOtherUsers_PushEvents
{
    [self checkThatItSetsIsIgnoringCallTo:NO whenTheCallEndsWithBlock:^(ZMConversation *conv) {
        NSDictionary *payload = [self payloadForConversation:conv othersAreJoined:NO selfIsJoined:NO];
        ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:payload HTTPStatus:200 transportSessionError:nil];
        [self.sut updateObject:conv withResponse:response downstreamSync:nil];
    }];
}

- (void)testThatItDoesNotResetsIsIgnoringCallIfThereAreStillOtherUsersInTheCall_PushEvents
{
    [self checkThatItSetsIsIgnoringCallTo:YES whenTheCallEndsWithBlock:^(ZMConversation *conv) {
        NSDictionary *payload = [self payloadForConversation:conv othersAreJoined:YES selfIsJoined:NO];
        ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:payload HTTPStatus:200 transportSessionError:nil];
        [self.sut updateObject:conv withResponse:response downstreamSync:nil];
    }];
}

- (void)testThatItResetsIsIgnoringCallIfALeftCallIsDroppedByTheOtherUsers_Upstream
{
    [self checkThatItSetsIsIgnoringCallTo:NO whenTheCallEndsWithBlock:^(ZMConversation *conv) {
        NSDictionary *payload = [self payloadForConversation:conv othersAreJoined:NO selfIsJoined:NO];
        ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:payload HTTPStatus:200 transportSessionError:nil];
        [self.sut updateUpdatedObject:conv requestUserInfo:nil response:response keysToParse:[NSSet setWithObject:ZMConversationCallDeviceIsActiveKey]];
    }];
}

- (void)testThatItDoesNotResetsIsIgnoringCallIfThereAreStillOtherUsersInTheCall_Upstream
{
    [self checkThatItSetsIsIgnoringCallTo:YES whenTheCallEndsWithBlock:^(ZMConversation *conv) {
        NSDictionary *payload = [self payloadForConversation:conv othersAreJoined:YES selfIsJoined:NO];
        ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:payload HTTPStatus:200 transportSessionError:nil];
        [self.sut updateUpdatedObject:conv requestUserInfo:nil response:response keysToParse:[NSSet setWithObject:ZMConversationCallDeviceIsActiveKey]];
    }];
}

- (void)checkThatIgnoringCallIsResetOnLeavingConversationWithBlock:(void(^)(ZMConversation *))block
{
    __block ZMConversation *activeCallConversation;
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        activeCallConversation = [self groupConversationWithConnectingCall];
        XCTAssertEqual(activeCallConversation.voiceChannelRouter.v2.state, VoiceChannelV2StateSelfIsJoiningActiveChannel);
        
        // when
        block(activeCallConversation);
        XCTAssertTrue(activeCallConversation.isIgnoringCall);
        XCTAssertEqual(activeCallConversation.voiceChannelRouter.v2.state, VoiceChannelV2StateIncomingCallInactive);
    }];
    
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatItDoesResetsIsIgnoringCallIfThereAreStillOtherUsersInTheCallAndSelfUserLeavesConversation_PushEvents
{
    [self checkThatIgnoringCallIsResetOnLeavingConversationWithBlock:^(ZMConversation *conv) {
        //leaves call on another device
        NSDictionary *payload = [self payloadForConversation:conv othersAreJoined:YES selfIsJoined:NO];
        ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:payload HTTPStatus:200 transportSessionError:nil];
        [self.sut updateObject:conv withResponse:response downstreamSync:nil];
    }];
}

- (void)testThatItDoesResetsIsIgnoringCallIfThereAreStillOtherUsersInTheCallAndSelfUserLeavesConversation_Upstream
{
    [self checkThatIgnoringCallIsResetOnLeavingConversationWithBlock:^(ZMConversation *conv) {
        //leaves call on another device
        NSDictionary *payload = [self payloadForConversation:conv othersAreJoined:YES selfIsJoined:NO];
        ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:payload HTTPStatus:200 transportSessionError:nil];
        [self.sut updateUpdatedObject:conv requestUserInfo:nil response:response keysToParse:[NSSet setWithObject:ZMConversationCallDeviceIsActiveKey]];
    }];
}


- (void)setupTestForConversationType:(ZMConversationType)conversationType
                       otherUserJoined:(BOOL)isOtherUserJoined
                              withBlock:(void (^)(ZMConversation *, ZMTransportResponse *))block
{
    __block ZMConversation *conv;
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        if (conversationType == ZMConversationTypeGroup) {
            conv = self.syncGroupConversation;
        } else {
            conv = self.syncSelfToUser1Conversation;
        }

        XCTAssertEqual(conv.voiceChannelRouter.v2.state, VoiceChannelV2StateNoActiveUsers);
        XCTAssertFalse(conv.isIgnoringCall);
        
        NSString *otherState = isOtherUserJoined ? @"joined" : @"idle";
        
        NSDictionary *payload = @{
                                  @"type": @"call.state",
                                  @"conversation": conv.remoteIdentifier.transportString,
                                  @"self":@{@"state":@"idle"},
                                  @"participants":@{
                                          self.syncOtherUser1.remoteIdentifier.transportString: @{@"state":otherState},
                                          self.syncSelfUser.remoteIdentifier.transportString: @{@"state":@"idle"},
                                          }
                                  };
        ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:payload HTTPStatus:200 transportSessionError:nil];
        // when
        block(conv, response);
    }];
    
    WaitForAllGroupsToBeEmpty(0.5);
}


- (void)testThatItSetsIsIgnoringCallForConversationsDuringSlowSync_Group
{
    __block ZMConversation *conversation;
    [self setupTestForConversationType:ZMConversationTypeGroup otherUserJoined:YES withBlock:^(ZMConversation *conv, ZMTransportResponse *response) {
        conversation = conv;
        // when
        [self.sut updateObject:conv withResponse:response downstreamSync:nil];
    }];
    WaitForAllGroupsToBeEmpty(0.5);

    // then
    XCTAssertTrue(conversation.isIgnoringCall);
    XCTAssertEqual(conversation.voiceChannelRouter.v2.state, VoiceChannelV2StateIncomingCallInactive);

}

- (void)testThatItDoesNotSetsIsIgnoringCallForAConversationsDuringSlowSync_OneOnOne
{
    __block ZMConversation *conversation;
    [self setupTestForConversationType:ZMConversationTypeOneOnOne otherUserJoined:YES withBlock:^(ZMConversation *conv, ZMTransportResponse *response) {
        conversation = conv;
        // when
        [self.sut updateObject:conv withResponse:response downstreamSync:nil];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertFalse(conversation.isIgnoringCall);
    XCTAssertEqual(conversation.voiceChannelRouter.v2.state, VoiceChannelV2StateIncomingCall);
}

- (void)testThatItDoesNotSetIsIgnoringCallWhenThereAreNoCallParticipants_Group
{
    __block ZMConversation *conversation;

    [self setupTestForConversationType:ZMConversationTypeGroup otherUserJoined:NO withBlock:^(ZMConversation *conv, ZMTransportResponse *response) {
        conversation = conv;
        [self.sut updateObject:conv withResponse:response downstreamSync:nil];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertFalse(conversation.isIgnoringCall);
    XCTAssertEqual(conversation.voiceChannelRouter.v2.state, VoiceChannelV2StateNoActiveUsers);
}

- (void)testThatItDoesNotSetIsIgnoringCallWhenThereAreNoCallParticipants_OneOnOne
{
    __block ZMConversation *conversation;
    
    [self setupTestForConversationType:ZMConversationTypeOneOnOne otherUserJoined:NO withBlock:^(ZMConversation *conv, ZMTransportResponse *response) {
        conversation = conv;
        [self.sut updateObject:conv withResponse:response downstreamSync:nil];
    }];
    WaitForAllGroupsToBeEmpty(0.5);

    // then
    XCTAssertFalse(conversation.isIgnoringCall);
    XCTAssertEqual(conversation.voiceChannelRouter.v2.state, VoiceChannelV2StateNoActiveUsers);
}

- (void)testThatItDoesNotSetIsIgnoringCallFromPushEvents_Group
{
    __block ZMConversation *conversation;

    [self setupTestForConversationType:ZMConversationTypeGroup otherUserJoined:YES withBlock:^(ZM_UNUSED id conv, ZMTransportResponse *response) {
        conversation = conv;
        NSDictionary *fullPayload = @{@"id": NSUUID.createUUID.transportString,
                                      @"payload" : @[response.payload]};
        ZMUpdateEvent *event = [[ZMUpdateEvent eventsArrayFromPushChannelData:fullPayload] firstObject];
        [self.sut processEvents:@[event] liveEvents:YES prefetchResult:nil];
    }];
    WaitForAllGroupsToBeEmpty(0.5);

    // then
    XCTAssertFalse(conversation.isIgnoringCall);
    XCTAssertEqual(conversation.voiceChannelRouter.v2.state, VoiceChannelV2StateIncomingCall);
}

- (void)testThatItDoesNotSetIsIgnoringCallFromPushEvents_OneOnOne
{
    __block ZMConversation *conversation;
    
    [self setupTestForConversationType:ZMConversationTypeOneOnOne otherUserJoined:YES withBlock:^(ZM_UNUSED id conv, ZMTransportResponse *response) {
        conversation = conv;
        NSDictionary *fullPayload = @{@"id": NSUUID.createUUID.transportString,
                                      @"payload" : @[response.payload]};
        ZMUpdateEvent *event = [[ZMUpdateEvent eventsArrayFromPushChannelData:fullPayload] firstObject];
        [self.sut processEvents:@[event] liveEvents:YES prefetchResult:nil];
    }];
    WaitForAllGroupsToBeEmpty(0.5);

    // then
    XCTAssertFalse(conversation.isIgnoringCall);
    XCTAssertEqual(conversation.voiceChannelRouter.v2.state, VoiceChannelV2StateIncomingCall);
}

- (void)testThatItDoesNotSetIsIgnoringCallWhenSyncingCallDeviceIsActive
{
    __block ZMConversation *conversation;

    [self setupTestForConversationType:ZMConversationTypeGroup otherUserJoined:YES withBlock:^(ZMConversation *conv, ZMTransportResponse *response) {
        conversation = conv;
        [self.sut updateUpdatedObject:conv requestUserInfo:nil response:response keysToParse:[NSSet setWithObject:ZMConversationCallDeviceIsActiveKey]];
    }];
    WaitForAllGroupsToBeEmpty(0.5);

    // then
    XCTAssertFalse(conversation.isIgnoringCall);
    XCTAssertEqual(conversation.voiceChannelRouter.v2.state, VoiceChannelV2StateIncomingCall);
}

@end



@implementation ZMCallStateRequestStrategyTests (CallDeviceIsActive)

- (void)testThatItCreatesARequestForUpdatingTheCallIsJoinedAttribute
{
    // given
    ZMConversation *conversation = [self insertUiConversationWithCallDeviceActive:YES];
    
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMConversation *syncConversation = (id)[self.syncMOC objectWithID:conversation.objectID];
        
        XCTAssertNotNil(syncConversation);
        [self.sut.contextChangeTrackers.lastObject objectsDidChange:[NSSet setWithObject:syncConversation]];
        
        // when
        ZMTransportRequest *request = [self.sut nextRequest];
        XCTAssertNotNil(request);
        
        // then
        NSString *expectedPath = [NSString stringWithFormat:@"/conversations/%@/call/state", syncConversation.remoteIdentifier.transportString];
        XCTAssertEqualObjects(request.path, expectedPath);
        XCTAssertEqual(request.method, ZMMethodPUT);
        
        [syncConversation.voiceChannelRouter.v2 tearDown];

    }];
}

- (void)testThatItCreatesARequestForSettingTheCallIsJoinedAttribute
{
    // given
    ZMConversation *conversation = [self insertUiConversationWithCallDeviceActive:YES];
    
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMConversation *syncConversation = (id)[self.syncMOC objectWithID:conversation.objectID];
        XCTAssertNotNil(syncConversation);
        
        // when
        ZMUpstreamRequest *request = [self.sut requestForUpdatingObject:syncConversation forKeys:self.keys];
        XCTAssertNotNil(request);
        
        // then
        NSString *expectedPath = [NSString stringWithFormat:@"/conversations/%@/call/state", syncConversation.remoteIdentifier.transportString];
        NSDictionary *expectedPayload = @{@"self": @{@"state" : @"joined",
                                                     @"suspended": @(NO),
                                                     @"videod" : @(NO)
                                                     },
                                          @"cause" : @"requested"};
        XCTAssertEqualObjects(request.transportRequest.path, expectedPath);
        XCTAssertEqual(request.transportRequest.method, ZMMethodPUT);
        XCTAssertEqualObjects(request.transportRequest.payload, expectedPayload);
        XCTAssertEqualObjects(request.keys, self.keys);
        [syncConversation.voiceChannelRouter.v2 tearDown];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatItCreatesARequestForClearingTheCallIsJoinedAttribute
{
    // given
    __block ZMConversation *conversation;
    
    [self.syncMOC performGroupedBlockAndWait:^{
        conversation = self.syncSelfToUser1Conversation;
        
        // when
        ZMUpstreamRequest *request = [self.sut requestForUpdatingObject:conversation forKeys:self.keys];
        XCTAssertNotNil(request);
        
        // then
        NSString *expectedPath = [NSString stringWithFormat:@"/conversations/%@/call/state", conversation.remoteIdentifier.transportString];
        NSDictionary *expectedPayload = @{@"self": @{@"state" : @"idle",
                                                     },
                                          @"cause" : @"requested"};

        XCTAssertEqualObjects(request.transportRequest.path, expectedPath);
        XCTAssertEqual(request.transportRequest.method, ZMMethodPUT);
        XCTAssertEqualObjects(request.transportRequest.payload, expectedPayload);
        XCTAssertEqualObjects(request.keys, self.keys);
    }];
    WaitForAllGroupsToBeEmpty(0.5);
}


- (void)testThatItProcessesAConversationCallIsJoinedChangeResponse;
{
    // given
    ZMConversation *uiConversation = [self insertUiConversationWithCallDeviceActive:YES];
    [self saveAndMergeCallState:self.uiMOC intoContext:self.syncMOC];
    __block ZMConversation *syncConversation;
    
    [self.syncMOC performGroupedBlockAndWait:^{
        syncConversation = (id)[self.syncMOC objectWithID:uiConversation.objectID];
        XCTAssertTrue(syncConversation.hasLocalModificationsForCallDeviceIsActive);
        
        [self.sut.contextChangeTrackers.lastObject objectsDidChange:[NSSet setWithObject:syncConversation]];
        ZMTransportRequest *request = [self.sut nextRequest];
        XCTAssertNotNil(request);
        
        // when
        ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:@{
                                                                                   @"self": @{
                                                                                           @"state": @"joined",
                                                                                           @"quality": @1
                                                                                        }
                                                                                   }
                                                                      HTTPStatus:200 transportSessionError:nil];
        [request completeWithResponse:response];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    [self.syncMOC performGroupedBlockAndWait:^{
        // then
        XCTAssertEqual(syncConversation.keysThatHaveLocalModifications.count, 0u);
        ZMTransportRequest *request = [self.sut nextRequest];
        XCTAssertTrue(syncConversation.callDeviceIsActive);
        XCTAssertNil(request);
        
        [syncConversation.voiceChannelRouter.v2 tearDown];
    }];
}

- (void)testThatItProcessesAConversationCallIsJoinedChangeResponseIfTheStateDoesNotMatch
{
    // given
    ZMConversation *uiConversation = [self insertUiConversationWithCallDeviceActive:YES];
    __block ZMConversation *syncConversation;
    
    [self.syncMOC performGroupedBlockAndWait:^{
        syncConversation = (id)[self.syncMOC objectWithID:uiConversation.objectID];
        XCTAssertTrue(syncConversation.hasLocalModificationsForCallDeviceIsActive);
        [self.sut.contextChangeTrackers.lastObject objectsDidChange:[NSSet setWithObject:syncConversation]];
        
        ZMTransportRequest *request = [self.sut nextRequest];
        XCTAssertNotNil(request);
        
        // when
        ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:@{@"self": @{ @"state": @"idle",
                                                                                               @"quality": @1 }
                                                                                   }
                                                                      HTTPStatus:200
                                                           transportSessionError:nil];
        [request completeWithResponse:response];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    [self.syncMOC performGroupedBlockAndWait:^{
        // then
        XCTAssertEqual(syncConversation.keysThatHaveLocalModifications.count, 0u);
        XCTAssertFalse(syncConversation.callDeviceIsActive);
        ZMTransportRequest *request = [self.sut nextRequest];
        XCTAssertNil(request);
        
        [syncConversation.voiceChannelRouter.v2 tearDown];
    }];
}

- (void)testThatItAddsTheSelfUserToCallParticipants
{
    // given
    ZMConversation *uiConversation = [self insertUiConversationWithCallDeviceActive:YES];
    __block ZMConversation *syncConversation;
    
    [self.syncMOC performGroupedBlockAndWait:^{

        syncConversation = (id)[self.syncMOC objectWithID:uiConversation.objectID];
        XCTAssertTrue(syncConversation.hasLocalModificationsForCallDeviceIsActive);
        XCTAssertFalse([syncConversation.callParticipants containsObject:self.syncSelfUser]);
        
        [self.sut.contextChangeTrackers.lastObject objectsDidChange:[NSSet setWithObject:syncConversation]];
        
        ZMTransportRequest *request = [self.sut nextRequest];
        XCTAssertNotNil(request);
        
        // when
        ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:@{@"self":         @{ @"state": @"joined",
                                                                                                       @"quality": @1 },
                                                                                   @"participants": @{ self.syncSelfUser.remoteIdentifier.transportString:
                                                                                                              @{ @"state": @"joined",
                                                                                                                 @"quality": @1 }
                                                                                                      }
                                                                                   }
                                                                      HTTPStatus:200
                                                           transportSessionError:nil];
        [request completeWithResponse:response];
    }];
    
    WaitForAllGroupsToBeEmpty(0.5);
    [self.syncMOC performGroupedBlockAndWait:^{
        // then
        XCTAssertEqual(syncConversation.keysThatHaveLocalModifications.count, 0u);
        XCTAssertTrue(syncConversation.callDeviceIsActive);
        XCTAssertTrue([syncConversation.callParticipants containsObject:self.syncSelfUser]);

        ZMTransportRequest *request = [self.sut nextRequest];
        XCTAssertNil(request);
        [syncConversation.voiceChannelRouter.v2 tearDown];
    }];
}

- (void)testThatWhenSelfUserLeavesConversationActiveCallParticipantsAreNotUpdatedFromResponsePayloadOnSynced
{
    // given
    ZMConversation *syncConv = self.syncGroupConversation;
    ZMConversation *uiConversation = (id)[self.uiMOC objectWithID:syncConv.objectID];

    
    NSDictionary *payload = @{@"self":         @{ @"state": @"idle",
                                                  @"quality": @0 },
                              @"participants": @{ self.syncSelfUser.remoteIdentifier.transportString:
                                                      @{ @"state": @"idle",
                                                         @"quality": @0 },
                                                  self.syncOtherUser1.remoteIdentifier.transportString:
                                                      @{@"state": @"joined",
                                                        @"quality": @1 }
                                                  }
                              };
    XCTAssertEqual(uiConversation.callParticipants.count, 0u);
    
    // when
    
    //1. remove self user
    [uiConversation removeParticipant:[ZMUser selfUserInContext:self.uiMOC]];
    
    //2. process call state sync response
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:payload HTTPStatus:200 transportSessionError:nil];
        [self.sut updateUpdatedObject:syncConv requestUserInfo:nil response:response keysToParse:self.keys];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    // we don't want callParticipants to be updated
    XCTAssertEqual(uiConversation.callParticipants.count, 0u);
}


@end



@implementation ZMCallStateRequestStrategyTests (Flows)

- (void)testThatItReleasesTheFlowIfSelfStateIsIdle_ReceivingResponse
{
    __block ZMConversation *conversation;
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        conversation = self.syncSelfToUser1Conversation;
        conversation.callStateNeedsToBeUpdatedFromBackend = YES;
        conversation.callDeviceIsActive = YES;
        
        NSDictionary *payload = @{
                                  @"self":@{@"state":@"idle"},
                                  @"participants":@{}
                                  };
        // expect
        [[self.callFlowRequestStrategy expect] updateFlowsForConversation:[OCMArg checkWithBlock:^BOOL(ZMConversation *conv) {
            XCTAssertEqualObjects(conversation, conv);
            XCTAssertTrue(!conv.callDeviceIsActive);
            return true;
        }]];
        
        ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:payload HTTPStatus:200 transportSessionError:nil];
        
        // when
        [self.sut updateObject:conversation withResponse:response downstreamSync:nil];
        [self.callFlowRequestStrategy verify];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
}


- (void)testThatDoesNotAcquiresAFlowIfSelfStateIsActiveButCallDeviceIsNotActive
{
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        ZMConversation *conversation = self.syncSelfToUser1Conversation;
        conversation.callStateNeedsToBeUpdatedFromBackend = YES;

        NSDictionary *payload = @{
                                  @"self":@{@"state":@"joined"},
                                  @"participants":@{}
                                  };
        ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:payload HTTPStatus:200 transportSessionError:nil];
        
        // expect
        [[self.callFlowRequestStrategy expect] updateFlowsForConversation:[OCMArg checkWithBlock:^BOOL(ZMConversation *conv) {
            XCTAssertEqualObjects(conversation, conv);
            XCTAssertTrue(!conv.callDeviceIsActive);
            return true;
        }]];
        
        // when
        [self.sut updateObject:conversation withResponse:response downstreamSync:nil];
        [self.callFlowRequestStrategy verify];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatItReleasesTheFlowFromAPushEventIfSelfStateIsIdle;
{
    __block ZMConversation *conversation;
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        conversation = self.syncSelfToUser1Conversation;
        conversation.callDeviceIsActive = NO;
        
        NSDictionary *payload = @{
                                  @"id" : NSUUID.createUUID.transportString,
                                  @"payload" : @[
                                          @{
                                              @"type": @"call.state",
                                              @"conversation": conversation.remoteIdentifier.transportString,
                                              @"self":@{@"state":@"idle"},
                                              @"participants":@{},
                                              }
                                          ]
                                  };
        
        ZMUpdateEvent *event = [ZMUpdateEvent eventsArrayFromPushChannelData:payload][0];
        
        // expect
        [[self.callFlowRequestStrategy expect] updateFlowsForConversation:[OCMArg checkWithBlock:^BOOL(ZMConversation *conv) {
            XCTAssertEqualObjects(conversation, conv);
            XCTAssertTrue(!conv.callDeviceIsActive);
            return true;
        }]];
        
        // when
        [self.sut processEvents:@[event] liveEvents:YES prefetchResult:nil];
        [self.callFlowRequestStrategy verify];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatItDoesNotAcquiresTheFlowFromAPushEventIfSelfStateIsActiveButTheDeviceWasNotActive;
{
    __block ZMConversation *conversation;
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        conversation = self.syncSelfToUser1Conversation;
        conversation.callDeviceIsActive = NO;
        
        NSDictionary *payload = @{
                                  @"id" : NSUUID.createUUID.transportString,
                                  @"payload" : @[
                                          @{
                                              @"type": @"call.state",
                                              @"conversation": conversation.remoteIdentifier.transportString,
                                              @"self":@{@"state":@"joined"},
                                              @"participants":@{},
                                              }
                                          ]
                                  };
        
        ZMUpdateEvent *event = [ZMUpdateEvent eventsArrayFromPushChannelData:payload][0];
        
        // expect
        [[self.callFlowRequestStrategy expect] updateFlowsForConversation:[OCMArg checkWithBlock:^BOOL(ZMConversation *conv) {
            XCTAssertEqualObjects(conversation, conv);
            XCTAssertTrue(!conv.callDeviceIsActive);
            return true;
        }]];
        
        // when
        [self.sut processEvents:@[event] liveEvents:YES prefetchResult:nil];
        [self.callFlowRequestStrategy verify];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatItReleasesTheFlowFromA_Disconnect_PushEventIfTheDeviceWasActive_AndResetsCallDeviceActive;
{
    __block ZMConversation *conversation;
    
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        conversation = self.syncSelfToUser1Conversation;
        conversation.callStateNeedsToBeUpdatedFromBackend = NO;
        conversation.callDeviceIsActive = YES;
        XCTAssertFalse(conversation.hasLocalModificationsForCallDeviceIsActive);

        [conversation.voiceChannelRouter.v2 addCallParticipant:self.syncSelfUser];
        [conversation.voiceChannelRouter.v2 addCallParticipant:self.syncOtherUser1];
        
        NSDictionary *payload = @{
                                  @"id" : NSUUID.createUUID.transportString,
                                  @"payload" : @[
                                          @{
                                              @"type": @"call.state",
                                              @"conversation": conversation.remoteIdentifier.transportString,
                                              @"self":@{@"state": @"idle"},
                                              @"cause": @"disconnected",
                                              @"participants":@{self.syncSelfUser.remoteIdentifier.transportString: @{@"state" : @"idle"},
                                                                self.syncOtherUser1.remoteIdentifier.transportString: @{@"state" : @"idle"}
                                                                },
                                              }
                                          ]
                                  };
        
        ZMUpdateEvent *event = [ZMUpdateEvent eventsArrayFromPushChannelData:payload][0];
        
        // expect
        [[self.callFlowRequestStrategy expect] updateFlowsForConversation:[OCMArg checkWithBlock:^BOOL(ZMConversation *conv) {
            XCTAssertEqualObjects(conversation, conv);
            XCTAssertTrue(!conv.callDeviceIsActive);
            return true;
        }]];
        
        // when
        [self.sut processEvents:@[event] liveEvents:YES prefetchResult:nil];
        [self.callFlowRequestStrategy verify];
        
        // then
        XCTAssertFalse(conversation.callDeviceIsActive);
    }];
    WaitForAllGroupsToBeEmpty(0.5);
}


- (void)testThatDoesNotReleaseTheFlowFromA_Disconnect_PushEventIfTheDeviceWasActiveAndHasLocalModifications
{
    __block ZMConversation *conversation;
    ZMConversation *uiConversation = [self insertUiConversationWithCallDeviceActive:YES];
    
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        conversation = (id)[self.syncMOC objectWithID:uiConversation.objectID];
        [conversation.voiceChannelRouter.v2 addCallParticipant:self.syncSelfUser];
        [conversation.voiceChannelRouter.v2 addCallParticipant:self.syncOtherUser1];
        XCTAssertTrue(conversation.hasLocalModificationsForCallDeviceIsActive);
        [self.syncMOC saveOrRollback];
        
        NSDictionary *payload = @{
                                  @"id" : NSUUID.createUUID.transportString,
                                  @"payload" : @[
                                          @{
                                              @"type": @"call.state",
                                              @"conversation": conversation.remoteIdentifier.transportString,
                                              @"self":@{},
                                              @"cause": @"disconnected",
                                              @"participants":@{self.syncSelfUser.remoteIdentifier.transportString: @{@"state" : @"idle"},
                                                                self.syncOtherUser1.remoteIdentifier.transportString: @{@"state" : @"idle"}
                                                                },
                                              }
                                          ]
                                  };
        
        ZMUpdateEvent *event = [ZMUpdateEvent eventsArrayFromPushChannelData:payload][0];
        
        // expect
        [[self.callFlowRequestStrategy reject] updateFlowsForConversation:conversation];
        
        // when
        [self.sut processEvents:@[event] liveEvents:YES prefetchResult:nil];
        [self.callFlowRequestStrategy verify];
        
        // then
        XCTAssertTrue(conversation.callDeviceIsActive);
        
        [conversation.voiceChannelRouter.v2 tearDown];
    }];
    WaitForAllGroupsToBeEmpty(0.5);

}


- (ZMConversation *)insertSyncConversationWithCallDeviceIsActive:(BOOL)callDeviceIsactive
{
    __block ZMConversation *conversation;
    [self.syncMOC performGroupedBlockAndWait:^{
        conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        conversation.connection = [ZMConnection insertNewObjectInManagedObjectContext:self.syncMOC];
        conversation.needsToBeUpdatedFromBackend = NO;
        conversation.callStateNeedsToBeUpdatedFromBackend = NO;
        conversation.conversationType = ZMConversationTypeOneOnOne;
        conversation.remoteIdentifier = [NSUUID createUUID];
        conversation.callDeviceIsActive = callDeviceIsactive;
    }];
    
    return conversation;
}
- (void)testThatItDoesNotAcquiresAFlowWhenTheDeviceIsActiveGetsSet;
{
    // given
    // set callDeviceIsActive locally to YES
    ZMConversation *uiConversation = (id)[self insertUiConversationWithCallDeviceActive:YES];
    [self.uiMOC saveOrRollback];
    
    [self.syncMOC performGroupedBlockAndWait:^{
        [self saveAndMergeCallState:self.uiMOC intoContext:self.syncMOC];
        ZMConversation *syncConversation = (id)[self.syncMOC objectWithID:uiConversation.objectID];
        
        // expect
        [[self.callFlowRequestStrategy reject] updateFlowsForConversation:syncConversation];
        
        // when
        for (id<ZMContextChangeTracker> t in self.sut.contextChangeTrackers) {
            [t objectsDidChange:[NSSet setWithObject:syncConversation]];
        }
        XCTAssertNotNil([self.sut nextRequest]);
        
        // finally
        XCTAssertNoThrow([self.callFlowRequestStrategy verify]);
        
        [syncConversation.voiceChannelRouter.v2 tearDown];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatItReleasesTheFlowWhenTheDeviceIsActiveGetsSetToNO;
{
    // given
    // set callDeviceIsActive locally to YES
    ZMConversation *uiConversation = (id)[self insertUiConversationWithCallDeviceActive:NO];
    [self.uiMOC saveOrRollback];
    
    [self.syncMOC performGroupedBlockAndWait:^{
        [self saveAndMergeCallState:self.uiMOC intoContext:self.syncMOC];
        ZMConversation *syncConversation = (id)[self.syncMOC objectWithID:uiConversation.objectID];
        
        // expect
        XCTAssertFalse(syncConversation.callDeviceIsActive);
        XCTAssertTrue(syncConversation.hasLocalModificationsForCallDeviceIsActive);
        [[self.callFlowRequestStrategy expect] updateFlowsForConversation:[OCMArg checkWithBlock:^BOOL(ZMConversation *conv) {
            XCTAssertEqualObjects(syncConversation, conv);
            XCTAssertTrue(!conv.callDeviceIsActive);
            return true;
        }]];
        
        // when
        for (id<ZMContextChangeTracker> t in self.sut.contextChangeTrackers) {
            [t objectsDidChange:[NSSet setWithObject:syncConversation]];
        }
        // finally
        XCTAssertNoThrow([self.callFlowRequestStrategy verify]);
        
        [syncConversation.voiceChannelRouter.v2 tearDown];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatItAcquiresAFlowWhenReceivingTheResponseToARequestForSettingCallDeviceIsActive;
{
    // given
    // set callDeviceIsActive locally to YES
    ZMConversation *uiConversation = (id)[self insertUiConversationWithCallDeviceActive:YES];
    
    [self.syncMOC performGroupedBlockAndWait:^{
        [self saveAndMergeCallState:self.uiMOC intoContext:self.syncMOC];
        ZMConversation *syncConversation = (id)[self.syncMOC objectWithID:uiConversation.objectID];
        ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:@{@"self":@{
                                                                                           @"state": @"joined",
                                                                                           @"quality": @1}} HTTPStatus:200 transportSessionError:nil];
        
        // expect
        [[self.callFlowRequestStrategy expect] updateFlowsForConversation:[OCMArg checkWithBlock:^BOOL(ZMConversation *conv) {
            XCTAssertEqualObjects(syncConversation, conv);
            XCTAssertTrue(conv.callDeviceIsActive);
            return true;
        }]];
        
        // when
        [self.sut updateUpdatedObject:syncConversation requestUserInfo:nil response:response keysToParse:self.keys];
        
        // finally
        XCTAssertNoThrow([self.callFlowRequestStrategy verify]);
        
        [syncConversation.voiceChannelRouter.v2 tearDown];
    }];
    
}

- (void)testThatItReleasesTheFlowsWhenTheDeviceIsActiveGetsUnset;
{
    // given
    ZMConversation *syncConversation = [self insertSyncConversationWithCallDeviceIsActive:YES];
    [self saveAndMergeCallState:self.syncMOC intoContext:self.uiMOC];

    // set callDeviceIsActive locally to NO
    ZMConversation *uiConversation = (id)[self.uiMOC objectWithID:syncConversation.objectID];
    uiConversation.callDeviceIsActive = NO;
    [self saveAndMergeCallState:self.uiMOC intoContext:self.syncMOC];
    
    [self.syncMOC performGroupedBlockAndWait:^{
        // expect
        XCTAssertFalse(syncConversation.callDeviceIsActive);
        XCTAssertTrue(syncConversation.hasLocalModificationsForCallDeviceIsActive);
        
        [[self.callFlowRequestStrategy expect] updateFlowsForConversation:[OCMArg checkWithBlock:^BOOL(ZMConversation *conv) {
            XCTAssertEqualObjects(syncConversation, conv);
            XCTAssertTrue(!conv.callDeviceIsActive);
            return true;
        }]];
        
        // when
        for (id<ZMContextChangeTracker> t in self.sut.contextChangeTrackers) {
            [t objectsDidChange:[NSSet setWithObject:syncConversation]];
        }
        XCTAssertNotNil([self.sut nextRequest]);
        
        // finally
        XCTAssertNoThrow([self.callFlowRequestStrategy verify]);
        [syncConversation.voiceChannelRouter.v2 tearDown];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatItReleasesAFlowAfterTheDeviceIsActiveHasBeenResetOnTheBackend;
{
    // given
    ZMConversation *syncConversation = [self insertSyncConversationWithCallDeviceIsActive:YES];
    [self saveAndMergeCallState:self.syncMOC intoContext:self.uiMOC];
    
    // set callDeviceIsActive locally to NO
    ZMConversation *uiConversation = (id)[self.uiMOC objectWithID:syncConversation.objectID];
    uiConversation.callDeviceIsActive = NO;
    [self saveAndMergeCallState:self.uiMOC intoContext:self.syncMOC];
    
    ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:@{@"self":@{
                                                                                       @"state": @"idle",
                                                                                       @"quality": @1}} HTTPStatus:200 transportSessionError:nil];

    [self.syncMOC performGroupedBlockAndWait:^{
        // expect
        [[self.callFlowRequestStrategy expect] updateFlowsForConversation:[OCMArg checkWithBlock:^BOOL(ZMConversation *conv) {
            XCTAssertEqualObjects(syncConversation, conv);
            XCTAssertTrue(!conv.callDeviceIsActive);
            return true;
        }]];
        
        // when
        for (id<ZMContextChangeTracker> t in self.sut.contextChangeTrackers) {
            [t objectsDidChange:[NSSet setWithObject:syncConversation]];
        }
        ZMTransportRequest *request = [self.sut nextRequest];
        XCTAssertNotNil(request);
        [request completeWithResponse:response];
    }];
    WaitForAllGroupsToBeEmpty(0.25);
        
    // finally
    [self.syncMOC performGroupedBlockAndWait:^{
        XCTAssertNoThrow([self.callFlowRequestStrategy verify]);
        
        [syncConversation.voiceChannelRouter.v2 tearDown];
    }];
    WaitForAllGroupsToBeEmpty(0.25);

}

- (void)testThatItDoesNotReleasesOrAquireFlowsAfterTheDeviceIsActiveHasBeenSetOnTheBackend;
{
    // given
    ZMConversation *syncConversation = [self insertSyncConversationWithCallDeviceIsActive:NO];
    [self saveAndMergeCallState:self.syncMOC intoContext:self.uiMOC];
    
    // set callDeviceIsActive locally to YES
    ZMConversation *uiConversation = (id)[self.uiMOC objectWithID:syncConversation.objectID];
    uiConversation.callDeviceIsActive = YES;
    [self saveAndMergeCallState:self.uiMOC intoContext:self.syncMOC];
    
    ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:@{@"self": @{ @"state": @"joined",
                                                                                           @"quality": @1 }}
                                                                  HTTPStatus:200
                                                       transportSessionError:nil];
    [self.syncMOC performGroupedBlockAndWait:^{
        // expect
        [[self.callFlowRequestStrategy expect] updateFlowsForConversation:[OCMArg checkWithBlock:^BOOL(ZMConversation *conv) {
            XCTAssertEqualObjects(syncConversation, conv);
            XCTAssertTrue(conv.callDeviceIsActive);
            return true;
        }]];
        
        // when
        for (id<ZMContextChangeTracker> t in self.sut.contextChangeTrackers) {
            [t objectsDidChange:[NSSet setWithObject:syncConversation]];
        }
        ZMTransportRequest *request = [self.sut nextRequest];
        XCTAssertNotNil(request);
        
        // when
        [request completeWithResponse:response];
    }];
    WaitForAllGroupsToBeEmpty(0.25);
    
    // finally
    [self.syncMOC performGroupedBlockAndWait:^{
        XCTAssertNoThrow([self.callFlowRequestStrategy verify]);
        
        [syncConversation.voiceChannelRouter.v2 tearDown];
    }];
    WaitForAllGroupsToBeEmpty(0.25);}

@end



@implementation ZMCallStateRequestStrategyTests (DroppedCallNotification)

- (void)testThatItFiresANotificationWhenReceivingUpstreamResponseWithCauseRequested_OnUserInitiatedLeave
{
    __block ZMConversation *conversation;
    [self.syncMOC performGroupedBlockAndWait:^{
        
        // given
        conversation = self.syncGroupConversation;
        conversation.callDeviceIsActive = YES;
        conversation.reasonToLeave = ZMCallStateReasonToLeaveUser;
        
        // expect
        [self expectationForNotification:[CallEndedNotification notificationName] object:nil handler:^BOOL(NSNotification * _Nonnull notification) {
            CallEndedNotification *callEnded = (CallEndedNotification *)notification.userInfo[CallEndedNotification.userInfoKey];
            
            XCTAssertEqualObjects(conversation.remoteIdentifier, callEnded.conversationId);
            XCTAssertEqual(callEnded.reason, VoiceChannelV2CallEndReasonRequestedSelf);
            
            return true;
        }];
        
        ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:@{
                                                                                   @"cause": @"requested",
                                                                                   @"type": @"call.state",
                                                                                   @"conversation": conversation.remoteIdentifier.transportString,
                                                                                   @"self":@{
                                                                                           @"state":@"idle",
                                                                                           },
                                                                                   @"participants":@{},
                                                                                   } HTTPStatus:200 transportSessionError:nil];
        
        // when
        [self.sut updateUpdatedObject:conversation requestUserInfo:nil response:response keysToParse:self.keys];
        
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0.5]);
}

- (void)testThatItFiresANotificationWhenReceivingUpstreamResponseWithCauseRequested_OnAVSInitiatedLeave
{
    __block ZMConversation *conversation;
    [self.syncMOC performGroupedBlockAndWait:^{
        
        // given
        conversation = self.syncGroupConversation;
        conversation.callDeviceIsActive = YES;
        conversation.reasonToLeave = ZMCallStateReasonToLeaveAvsError;
        
        // expect
        [self expectationForNotification:[CallEndedNotification notificationName] object:nil handler:^BOOL(NSNotification * _Nonnull notification) {
            CallEndedNotification *callEnded = (CallEndedNotification *)notification.userInfo[CallEndedNotification.userInfoKey];
            
            XCTAssertEqualObjects(conversation.remoteIdentifier, callEnded.conversationId);
            XCTAssertEqual(callEnded.reason, VoiceChannelV2CallEndReasonRequestedAVS);
            
            return true;
        }];
        
        ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:@{
                                                                                   @"cause": @"requested",
                                                                                   @"type": @"call.state",
                                                                                   @"conversation": conversation.remoteIdentifier.transportString,
                                                                                   @"self":@{
                                                                                           @"state":@"idle",
                                                                                           },
                                                                                   @"participants":@{},
                                                                                   } HTTPStatus:200 transportSessionError:nil];
        
        // when
        [self.sut updateUpdatedObject:conversation requestUserInfo:nil response:response keysToParse:self.keys];
        
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0.5]);
}


- (void)testThatItFiresANotificationWhenReceivingAPushNotificationWithCauseDisconnected
{
    __block ZMConversation *conversation;
    
    [self.syncMOC performGroupedBlockAndWait:^{
        
        // given
        conversation = self.syncGroupConversation;
        conversation.callDeviceIsActive = YES;
        
        // expect
        [self expectationForNotification:[CallEndedNotification notificationName] object:nil handler:^BOOL(NSNotification * _Nonnull notification) {
            CallEndedNotification *callEnded = (CallEndedNotification *)notification.userInfo[CallEndedNotification.userInfoKey];
            
            XCTAssertEqualObjects(conversation.remoteIdentifier, callEnded.conversationId);
            XCTAssertEqual(callEnded.reason, VoiceChannelV2CallEndReasonDisconnected);
            
            return true;
        }];
        
        NSDictionary *payload = @{
                                  @"id" : NSUUID.createUUID.transportString,
                                  @"payload" : @[
                                          @{
                                              @"cause": @"disconnected",
                                              @"type": @"call.state",
                                              @"conversation": conversation.remoteIdentifier.transportString,
                                              @"self":@{
                                                      @"state":@"idle",
                                                      },
                                              @"participants":@{},
                                              }
                                          ]
                                  };
        
        // when
        [self.sut processEvents:@[[ZMUpdateEvent eventsArrayFromPushChannelData:payload][0]] liveEvents:YES prefetchResult:nil];
        
    }];
    
    XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0.5]);
    
    // then
    XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0.5]);
}

- (void)testThatItFiresANotificationWhenReceivingAPushNotificationWithCauseRequested
{
    __block ZMConversation *conversation;
    [self.syncMOC performGroupedBlockAndWait:^{
        
        // given
        conversation = self.syncGroupConversation;
        conversation.callDeviceIsActive = YES;
        
        // expect
        [self expectationForNotification:[CallEndedNotification notificationName] object:nil handler:^BOOL(NSNotification * _Nonnull notification) {
            CallEndedNotification *callEnded = (CallEndedNotification *)notification.userInfo[CallEndedNotification.userInfoKey];
            
            XCTAssertEqualObjects(conversation.remoteIdentifier, callEnded.conversationId);
            XCTAssertEqual(callEnded.reason, VoiceChannelV2CallEndReasonRequested);
            
            return true;
        }];
        
        NSDictionary *payload = @{
                                  @"id" : NSUUID.createUUID.transportString,
                                  @"payload" : @[
                                          @{
                                              @"cause": @"requested",
                                              @"type": @"call.state",
                                              @"conversation": conversation.remoteIdentifier.transportString,
                                              @"self":@{
                                                      @"state":@"idle",
                                                      },
                                              @"participants":@{},
                                              }
                                          ]
                                  };
        
        // when
        [self.sut processEvents:[ZMUpdateEvent eventsArrayFromPushChannelData:payload] liveEvents:YES prefetchResult:nil];
        
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0.5]);
}

- (void)testThatItDoesNotFireANotificationWhenReceivingAPushNotificationWithCauseRequestedWhenCallDeviceIsNotActive
{
    __block ZMConversation *conversation;
    __block BOOL didFireNotification = NO;
    
    // expect
    id observer = [[NSNotificationCenter defaultCenter] addObserverForName:CallEndedNotification.notificationName object:nil queue:NSOperationQueue.mainQueue usingBlock:^(__unused NSNotification * _Nonnull note) {
        didFireNotification = YES;
    }];
    
    [self.syncMOC performGroupedBlockAndWait:^{
        
        // given
        conversation = self.syncGroupConversation;
        conversation.callDeviceIsActive = NO;
        
        NSDictionary *payload = @{
                                  @"id" : NSUUID.createUUID.transportString,
                                  @"payload" : @[
                                          @{
                                              @"cause": @"requested",
                                              @"type": @"call.state",
                                              @"conversation": conversation.remoteIdentifier.transportString,
                                              @"self":@{
                                                      @"state":@"idle",
                                                      },
                                              @"participants":@{},
                                              }
                                          ]
                                  };
        
        // when
        [self.sut processEvents:[ZMUpdateEvent eventsArrayFromPushChannelData:payload] liveEvents:YES prefetchResult:nil];
        
    }];
    
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertFalse(didFireNotification);
    
    [NSNotificationCenter.defaultCenter removeObserver:observer];
}

@end


@implementation ZMCallStateRequestStrategyTests (ConversationEvents)

- (NSMutableDictionary *)responsePayloadForUserEventInConversationID:(NSUUID *)conversationID userIDs:(NSArray *)userIDs eventType:(NSString *)eventType;
{
    NSArray *userIDStrings = [userIDs mapWithBlock:^id(NSUUID *userID) {
        Require([userID isKindOfClass:[NSUUID class]]);
        return userID.transportString;
    }];
    return [@{@"conversation": conversationID.transportString,
              @"data": @{@"user_ids": userIDStrings},
              @"from": NSUUID.createUUID.transportString,
              @"id": NSUUID.createUUID.transportString,
              @"time": [NSDate date].transportString,
              @"type": eventType} mutableCopy];
}

- (void)testThatWhen_Self_JoiningAGroupConversation_Sets_CallStateNeedsToBeUpdatedFromTheBackend
{
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        ZMConversation *conversation = self.syncGroupConversation;
        conversation.callStateNeedsToBeUpdatedFromBackend = NO;
        conversation.isSelfAnActiveMember = NO;
        
        NSDictionary *payload = [self responsePayloadForUserEventInConversationID:conversation.remoteIdentifier
                                                                          userIDs:@[self.syncSelfUser.remoteIdentifier]
                                                                        eventType:@"conversation.member-join"];
        // when
        [self.sut processEvents:@[[ZMUpdateEvent eventFromEventStreamPayload:payload uuid:nil]] liveEvents:YES prefetchResult:nil];
        
        // then
        XCTAssertTrue(conversation.callStateNeedsToBeUpdatedFromBackend);
    }];
}

- (void)testThatWhen_Self_LeavingAGroupConversation_Sets_CallDeviceIsActiveToNoAndReleasesTheFlows
{
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        ZMConversation *conversation = self.syncGroupConversation;
        conversation.callDeviceIsActive = YES;
        conversation.isSelfAnActiveMember = NO;
        
        NSDictionary *payload = [self responsePayloadForUserEventInConversationID:conversation.remoteIdentifier
                                                                          userIDs:@[self.syncSelfUser.remoteIdentifier]
                                                                        eventType:@"conversation.member-leave"];
        // expect
        [[self.callFlowRequestStrategy expect] updateFlowsForConversation:[OCMArg checkWithBlock:^BOOL(ZMConversation *conv) {
            XCTAssertEqualObjects(conversation, conv);
            XCTAssertTrue(!conv.callDeviceIsActive);
            return true;
        }]];
        
        // when
        [self.sut processEvents:@[[ZMUpdateEvent eventFromEventStreamPayload:payload uuid:nil]] liveEvents:YES prefetchResult:nil];
        
        // then
        XCTAssertFalse(conversation.callDeviceIsActive);
        [self.callFlowRequestStrategy verify];
    }];
}

- (void)testThatWhen_OthersAndSelf_JoiningAGroupConversation_Sets_CallStateNeedsToBeUpdatedFromTheBackend
{
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        ZMConversation *conversation = self.syncGroupConversation;
        conversation.callStateNeedsToBeUpdatedFromBackend = NO;
        conversation.isSelfAnActiveMember = NO;
        
        NSDictionary *payload = [self responsePayloadForUserEventInConversationID:conversation.remoteIdentifier
                                                                          userIDs:@[self.syncSelfUser.remoteIdentifier,
                                                                                    NSUUID.createUUID, NSUUID.createUUID]
                                                                        eventType:@"conversation.member-join"];
        // when
        [self.sut processEvents:@[[ZMUpdateEvent eventFromEventStreamPayload:payload uuid:nil]] liveEvents:YES prefetchResult:nil];
        
        // then
        XCTAssertTrue(conversation.callStateNeedsToBeUpdatedFromBackend);
    }];
}

- (void)testThatWhen_Others_JoiningAGroupConversation_DoesNotSet_CallStateNeedsToBeUpdatedFromTheBackend
{
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        ZMConversation *conversation = self.syncGroupConversation;
        conversation.callStateNeedsToBeUpdatedFromBackend = NO;
        conversation.isSelfAnActiveMember = NO;
        
        NSDictionary *payload = [self responsePayloadForUserEventInConversationID:conversation.remoteIdentifier
                                                                          userIDs:@[NSUUID.createUUID]
                                                                        eventType:@"conversation.member-join"];
        // when
        [self.sut processEvents:@[[ZMUpdateEvent eventFromEventStreamPayload:payload uuid:nil]] liveEvents:YES prefetchResult:nil];
        
        // then
        XCTAssertFalse(conversation.callStateNeedsToBeUpdatedFromBackend);
    }];
}

- (void)testThatReceivingAConversationCreateEvent_Sets_CallStateNeedsToBeUpdatedFromTheBackend
{
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        conversation.callStateNeedsToBeUpdatedFromBackend = NO;
        conversation.conversationType = ZMConversationTypeOneOnOne;
        conversation.remoteIdentifier = [NSUUID createUUID];
        [self.syncMOC saveOrRollback];
        
        ZMUser *selfUser = [ZMUser selfUserInContext:self.syncMOC];
        selfUser.remoteIdentifier = NSUUID.createUUID;
        
        NSDictionary *payload = [self responsePayloadForUserEventInConversationID:conversation.remoteIdentifier
                                                                          userIDs:@[]
                                                                        eventType:@"conversation.create"];
        XCTAssertFalse(conversation.callStateNeedsToBeUpdatedFromBackend);
        
        // when
        [self.sut processEvents:@[[ZMUpdateEvent eventFromEventStreamPayload:payload uuid:nil]] liveEvents:YES prefetchResult:nil];
        
        // then
        XCTAssertTrue(conversation.callStateNeedsToBeUpdatedFromBackend);
        
        [conversation.voiceChannelRouter.v2 tearDown];
    }];
}

- (void)testThatReceivingAConversationMemberLeaveEventFor_SelfUser_Resets_CallStateNeedsToBeUpdatedFromTheBackend
{
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        ZMConversation *conversation = self.syncGroupConversation;
        conversation.callStateNeedsToBeUpdatedFromBackend = YES;
        
        NSDictionary *payload = [self responsePayloadForUserEventInConversationID:conversation.remoteIdentifier
                                                                          userIDs:@[self.syncSelfUser.remoteIdentifier]
                                                                        eventType:@"conversation.member-leave"];
        XCTAssertTrue(conversation.callStateNeedsToBeUpdatedFromBackend);
        
        // when
        [self.sut processEvents:@[[ZMUpdateEvent eventFromEventStreamPayload:payload uuid:nil]] liveEvents:YES prefetchResult:nil];
        
        // then
        XCTAssertFalse(conversation.callStateNeedsToBeUpdatedFromBackend);
    }];
}


- (void)testThatReceivingAConversationMemberLeaveEventFor_OtherUser_DoesNotReset_CallStateNeedsToBeUpdatedFromTheBackend
{
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        ZMConversation *conversation = self.syncGroupConversation;
        conversation.callStateNeedsToBeUpdatedFromBackend = YES;
        
        NSDictionary *payload = [self responsePayloadForUserEventInConversationID:conversation.remoteIdentifier
                                                                          userIDs:@[NSUUID.createUUID]
                                                                        eventType:@"conversation.member-leave"];
        XCTAssertTrue(conversation.callStateNeedsToBeUpdatedFromBackend);
        
        // when
        [self.sut processEvents:@[[ZMUpdateEvent eventFromEventStreamPayload:payload uuid:nil]] liveEvents:YES prefetchResult:nil];
        
        // then
        XCTAssertTrue(conversation.callStateNeedsToBeUpdatedFromBackend);
    }];
}

- (void)testThatWhenLeavingAConversationItLeavesTheVoiceChannel
{
    // given
    
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        ZMConversation *conversation = self.syncGroupConversation;
        conversation.callDeviceIsActive = YES;
        [conversation removeParticipant:[ZMUser selfUserInContext:self.syncMOC]];
        [conversation updateKeysThatHaveLocalModifications];

        XCTAssertTrue([conversation hasLocalModificationsForKey:ZMConversationIsSelfAnActiveMemberKey]);
        XCTAssertTrue(conversation.callDeviceIsActive);

        // expect
        [[self.callFlowRequestStrategy expect] updateFlowsForConversation:[OCMArg checkWithBlock:^BOOL(ZMConversation *conv) {
            XCTAssertEqualObjects(conversation, conv);
            XCTAssertTrue(!conv.callDeviceIsActive);
            return true;
        }]];
        
        // when
        [self.sut.contextChangeTrackers.firstObject objectsDidChange:[NSSet setWithObject:conversation]];
        
        // then
        XCTAssertFalse(conversation.callDeviceIsActive);
        [self.callFlowRequestStrategy verify];
    }];
}

@end


@implementation ZMCallStateRequestStrategyTests (SequenceNumber)

- (void)checkThatItStoresTheSequenceNumberWithBlock:(void (^)(ZMConversation *, ZMTransportResponse *))block
{
    // given
    NSNumber *sequenceNumber = @1;
    ZMConversation *conversation = self.syncSelfToUser1Conversation;
    NSDictionary *payload = [self payloadForCallStateEventInConversation:conversation othersAreJoined:YES selfIsJoined:YES sequence:sequenceNumber];
    ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:payload HTTPStatus:200 transportSessionError:nil];

    // when
    [self.syncMOC performGroupedBlockAndWait:^{
        block(conversation, response);
    }];
    
    // then
    NSNumber *lastSequence = [self.sut lastSequenceForConversation:conversation];
    XCTAssertNotNil(lastSequence);
    XCTAssertEqualObjects(lastSequence, sequenceNumber);
}

- (void)testThatItStoresTheSequenceNumber_PushEvent
{
    [self checkThatItStoresTheSequenceNumberWithBlock:^(ZM_UNUSED id conversation, ZMTransportResponse *response) {
        NSDictionary *eventPayload = @{@"id": NSUUID.createUUID.transportString,
                                      @"payload" : @[response.payload]};
        ZMUpdateEvent *event = [ZMUpdateEvent eventsArrayFromPushChannelData:eventPayload].firstObject;
        [self.sut processEvents:@[event] liveEvents:YES prefetchResult:nil];
    }];
}

- (void)testThatItStoresTheSequenceNumber_Downstream
{
    [self checkThatItStoresTheSequenceNumberWithBlock:^(ZMConversation *conversation, ZMTransportResponse *response) {
        [self.sut updateObject:conversation withResponse:response downstreamSync:nil];
    }];
}

- (void)testThatItStoresTheSequenceNumber_Upstream
{
    [self checkThatItStoresTheSequenceNumberWithBlock:^(ZMConversation *conversation, ZMTransportResponse *response) {
        [self.sut updateUpdatedObject:conversation requestUserInfo:nil response:response keysToParse:self.keys];
    }];
}


- (void)checkThatItDoesNotSaveALowerSequenceNumberAndRejectsThePayloadWithBlock:(void (^)(ZMConversation *, NSDictionary *))block
{
    // given
    NSNumber *sequenceNumber1 = @2;
    NSNumber *sequenceNumber2 = @1;
    XCTAssertGreaterThan(sequenceNumber1, sequenceNumber2);

    ZMConversation *conversation = self.syncSelfToUser1Conversation;
    XCTAssertFalse([conversation.callParticipants containsObject:self.syncSelfUser]);

    NSDictionary *payload1 = [self payloadForCallStateEventInConversation:conversation othersAreJoined:YES selfIsJoined:YES sequence:sequenceNumber1];
    NSDictionary *payload2 = [self payloadForCallStateEventInConversation:conversation othersAreJoined:YES selfIsJoined:NO sequence:sequenceNumber2];
    
    // when
    [self.syncMOC performGroupedBlockAndWait:^{
        block(conversation, payload1);
        block(conversation, payload2);
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    [self.syncMOC saveOrRollback];
    
    // then
    NSNumber *lastSequence = [self.sut lastSequenceForConversation:conversation];
    XCTAssertNotNil(lastSequence);
    XCTAssertEqualObjects(lastSequence, sequenceNumber1);
    XCTAssertTrue([conversation.callParticipants containsObject:self.syncSelfUser]);
}

- (void)testThatItDoesNotSaveALowerSequenceNumberAndRejectsThePayload_Push
{
    [self checkThatItDoesNotSaveALowerSequenceNumberAndRejectsThePayloadWithBlock:^(ZM_UNUSED id conversation, NSDictionary *payload) {
        NSDictionary *eventPayload = @{@"id": NSUUID.createUUID.transportString,
                                       @"payload" : @[payload]};
        ZMUpdateEvent *event = [ZMUpdateEvent eventsArrayFromPushChannelData:eventPayload].firstObject;
        [self.sut processEvents:@[event] liveEvents:YES prefetchResult:nil];
    }];
}

- (void)testThatItDoesNotSaveALowerSequenceNumberAndRejectsThePayload_Downstream
{
    [self checkThatItDoesNotSaveALowerSequenceNumberAndRejectsThePayloadWithBlock:^(ZMConversation *conversation, NSDictionary *payload) {
        ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:payload HTTPStatus:200 transportSessionError:nil];
        [self.sut updateObject:conversation withResponse:response downstreamSync:nil];
    }];
}

- (void)testThatItDoesNotSaveALowerSequenceNumberAndRejectsThePayload_Upstream
{
    [self checkThatItDoesNotSaveALowerSequenceNumberAndRejectsThePayloadWithBlock:^(ZMConversation *conversation, NSDictionary *payload) {
        ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:payload HTTPStatus:200 transportSessionError:nil];
        [self.sut updateUpdatedObject:conversation requestUserInfo:nil response:response keysToParse:self.keys];
    }];
}


- (void)checkThatItSavesAHigherSequenceNumberAndProcessesThePayloadWithBlock:(void (^)(ZMConversation *, NSDictionary *))block
{
    // given
    NSNumber *sequenceNumber1 = @1;
    NSNumber *sequenceNumber2 = @2;
    XCTAssertLessThan(sequenceNumber1, sequenceNumber2);
    
    ZMConversation *conversation = self.syncSelfToUser1Conversation;
    XCTAssertFalse([conversation.callParticipants containsObject:self.syncSelfUser]);

    NSDictionary *payload1 = [self payloadForCallStateEventInConversation:conversation othersAreJoined:YES selfIsJoined:YES sequence:sequenceNumber1];
    NSDictionary *payload2 = [self payloadForCallStateEventInConversation:conversation othersAreJoined:YES selfIsJoined:NO sequence:sequenceNumber2];
    
    // when
    [self.syncMOC performGroupedBlockAndWait:^{
        block(conversation, payload1);
        block(conversation, payload2);
    }];
    
    // then
    NSNumber *lastSequence = [self.sut lastSequenceForConversation:conversation];
    XCTAssertNotNil(lastSequence);
    XCTAssertEqualObjects(lastSequence, sequenceNumber2);
    XCTAssertFalse([conversation.callParticipants containsObject:self.syncSelfUser]);
}

- (void)testThatItSavesAHigherSequenceNumberAndProcessesThePayload_Push
{
    [self checkThatItSavesAHigherSequenceNumberAndProcessesThePayloadWithBlock:^(ZM_UNUSED id conversation, NSDictionary *payload) {
        NSDictionary *eventPayload = @{@"id": NSUUID.createUUID.transportString,
                                       @"payload" : @[payload]};
        ZMUpdateEvent *event = [ZMUpdateEvent eventsArrayFromPushChannelData:eventPayload].firstObject;
        [self.sut processEvents:@[event] liveEvents:YES prefetchResult:nil];
    }];
}

- (void)testThatItSavesAHigherSequenceNumberAndProcessesThePayload_Downstream
{
    [self checkThatItSavesAHigherSequenceNumberAndProcessesThePayloadWithBlock:^(ZMConversation *conversation, NSDictionary *payload) {
        ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:payload HTTPStatus:200 transportSessionError:nil];
        [self.sut updateObject:conversation withResponse:response downstreamSync:nil];
    }];
}

- (void)testThatItSavesAHigherSequenceNumberAndProcessesThePayload_Upstream
{
    [self checkThatItSavesAHigherSequenceNumberAndProcessesThePayloadWithBlock:^(ZMConversation *conversation, NSDictionary *payload) {
        ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:payload HTTPStatus:200 transportSessionError:nil];
        [self.sut updateUpdatedObject:conversation requestUserInfo:nil response:response keysToParse:self.keys];
    }];
}


- (void)checkThatItSavesASameSequenceNumberAndProcessesThePayloadWithBlock:(void (^)(ZMConversation *, NSDictionary *))block
{
    // given
    NSNumber *sequenceNumber1 = @1;
    NSNumber *sequenceNumber2 = @1;
    XCTAssertEqualObjects(sequenceNumber1, sequenceNumber2);
    
    ZMConversation *conversation = self.syncSelfToUser1Conversation;
    XCTAssertFalse([conversation.callParticipants containsObject:self.syncSelfUser]);
    
    NSDictionary *payload1 = [self payloadForCallStateEventInConversation:conversation othersAreJoined:YES selfIsJoined:YES sequence:sequenceNumber1];
    NSDictionary *payload2 = [self payloadForCallStateEventInConversation:conversation othersAreJoined:YES selfIsJoined:NO sequence:sequenceNumber2];
    
    // when
    [self.syncMOC performGroupedBlockAndWait:^{
        block(conversation, payload1);
        block(conversation, payload2);
    }];
    
    // then
    NSNumber *lastSequence = [self.sut lastSequenceForConversation:conversation];
    XCTAssertNotNil(lastSequence);
    XCTAssertEqualObjects(lastSequence, sequenceNumber2);
    XCTAssertFalse([conversation.callParticipants containsObject:self.syncSelfUser]);
}

- (void)testThatItSavesASameSequenceNumberAndProcessesThePayload_Push
{
    [self checkThatItSavesASameSequenceNumberAndProcessesThePayloadWithBlock:^(ZM_UNUSED id conversation, NSDictionary *payload) {
        NSDictionary *eventPayload = @{@"id": NSUUID.createUUID.transportString,
                                       @"payload" : @[payload]};
        ZMUpdateEvent *event = [ZMUpdateEvent eventsArrayFromPushChannelData:eventPayload].firstObject;
        [self.sut processEvents:@[event] liveEvents:YES prefetchResult:nil];
    }];
}

- (void)testThatItSavesASameSequenceNumberAndProcessesThePayload_Downstream
{
    [self checkThatItSavesASameSequenceNumberAndProcessesThePayloadWithBlock:^(ZMConversation *conversation, NSDictionary *payload) {
        ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:payload HTTPStatus:200 transportSessionError:nil];
        [self.sut updateObject:conversation withResponse:response downstreamSync:nil];
    }];
}

- (void)testThatItSavesASameSequenceNumberAndProcessesThePayload_Upstream
{
    [self checkThatItSavesASameSequenceNumberAndProcessesThePayloadWithBlock:^(ZMConversation *conversation, NSDictionary *payload) {
        ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:payload HTTPStatus:200 transportSessionError:nil];
        [self.sut updateUpdatedObject:conversation requestUserInfo:nil response:response keysToParse:self.keys];
    }];
}


@end


@implementation ZMCallStateRequestStrategyTests (UpstreamTranscoder)

- (ZMConversation *)insertConversationNeedsUpdateFromBackend:(BOOL)callStateNeedsToBeUpdatedFromBackend
                                          callDeviceIsActive:(BOOL)callDeviceIsActive;
{
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    conversation.remoteIdentifier = NSUUID.createUUID;
    conversation.conversationType = ZMConversationTypeGroup;
    conversation.callDeviceIsActive = callDeviceIsActive;
    conversation.callStateNeedsToBeUpdatedFromBackend = callStateNeedsToBeUpdatedFromBackend;
    [self.uiMOC saveOrRollback];
    NOT_USED([self.syncMOC mergeCallStateChanges:self.uiMOC.zm_callState]);
    return conversation;
}

- (ZMUpstreamModifiedObjectSync *)upstreamSync
{
    ZMUpstreamModifiedObjectSync *upstreamSync = (ZMUpstreamModifiedObjectSync *)self.sut.contextChangeTrackers.lastObject;
    XCTAssertTrue([upstreamSync isKindOfClass:[ZMUpstreamModifiedObjectSync class]]);
    return upstreamSync;
}


- (void)testThatItAddsAConversationThatHasLocallyModifiedCallDeviceIsActive_YES
{
    // given
    ZMConversation *conversation = [self insertConversationNeedsUpdateFromBackend:NO callDeviceIsActive:YES];
    
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMConversation *syncConv = (id)[self.syncMOC objectWithID:conversation.objectID];
        XCTAssertTrue(syncConv.hasLocalModificationsForCallDeviceIsActive);

        XCTAssertFalse([self.upstreamSync hasOutstandingItems]);

        // when
        [self.upstreamSync objectsDidChange:[NSSet setWithObject:syncConv]];
        
        // then
        XCTAssertTrue([self.upstreamSync hasOutstandingItems]);
        [syncConv.voiceChannelRouter.v2 tearDown];
    }];
}


- (void)testThatItDoesNotAddConversationsThatNeedCallStateUpdatedFromTheBackend
{
    // given
    ZMConversation *conversation = [self insertConversationNeedsUpdateFromBackend:YES callDeviceIsActive:YES];
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMConversation *syncConv = (id)[self.syncMOC objectWithID:conversation.objectID];
        XCTAssertTrue(syncConv.hasLocalModificationsForCallDeviceIsActive);
        
        XCTAssertFalse([self.upstreamSync hasOutstandingItems]);
        
        // when
        [self.upstreamSync objectsDidChange:[NSSet setWithObject:syncConv]];
        
        // then
        XCTAssertFalse([self.upstreamSync hasOutstandingItems]);
        [syncConv.voiceChannelRouter.v2 tearDown];
    }];
}

- (void)testThatIt_DoesNot_AddAConversationThatHasLocallyModifiedCallDeviceIsActive_NO
{
    // given
    ZMConversation *conversation = [self insertConversationNeedsUpdateFromBackend:YES callDeviceIsActive:YES];
    
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMConversation *syncConv = (id)[self.syncMOC objectWithID:conversation.objectID];
        [syncConv resetHasLocalModificationsForCallDeviceIsActive];
        XCTAssertFalse(syncConv.hasLocalModificationsForCallDeviceIsActive);
        
        XCTAssertFalse([self.upstreamSync hasOutstandingItems]);
        
        // when
        [self.upstreamSync objectsDidChange:[NSSet setWithObject:syncConv]];
        
        // then
        XCTAssertFalse([self.upstreamSync hasOutstandingItems]);
        [syncConv.voiceChannelRouter.v2 tearDown];
    }];
}


- (void)testThatItResetsHasLocalModificationsForCallDeviceActiveOnSuccess
{
    // given
    ZMConversation *conversation = [self insertConversationNeedsUpdateFromBackend:NO callDeviceIsActive:YES];
    
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMConversation *syncConv = (id)[self.syncMOC objectWithID:conversation.objectID];
        XCTAssertTrue(syncConv.hasLocalModificationsForCallDeviceIsActive);
        ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:@{} HTTPStatus:200 transportSessionError:nil];

        // when
        [self.sut updateUpdatedObject:syncConv requestUserInfo:nil response:response keysToParse:self.keys];
        
        // then
        XCTAssertFalse(syncConv.hasLocalModificationsForCallDeviceIsActive);
        [syncConv.voiceChannelRouter.v2 tearDown];
    }];
}


- (void)testThatItResetsCallDeviceIsActiveForTimeOutErrors_JoinRequest
{
    // given
    ZMConversation *uiConv = [self insertConversationNeedsUpdateFromBackend:NO callDeviceIsActive:YES];
    __block ZMConversation *conversation;
    
    [self.syncMOC performGroupedBlockAndWait:^{
        conversation = (id)[self.syncMOC objectWithID:uiConv.objectID];
        XCTAssertTrue(conversation.hasLocalModificationsForCallDeviceIsActive);
        
        [self.upstreamSync objectsDidChange:[NSSet setWithObject:conversation]];
        ZMTransportRequest *request = [self.upstreamSync nextRequest];
        ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:@{} HTTPStatus:0 transportSessionError:[NSError requestExpiredError]];
        XCTAssertNotNil(request);
        
        // expect
        [[self.callFlowRequestStrategy expect] updateFlowsForConversation:[OCMArg checkWithBlock:^BOOL(ZMConversation *conv) {
            XCTAssertEqualObjects(conversation, conv);
            XCTAssertTrue(!conv.callDeviceIsActive);
            return true;
        }]];
        
        // when
        [request completeWithResponse:response];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    [self.syncMOC performGroupedBlockAndWait:^{
        [conversation updateLocallyModifiedCallStateKeys];
        
        // then
        XCTAssertFalse(conversation.callDeviceIsActive);

        // when
        // it sends out a leave request, because the request might have been successful, but the response never arrived
        // in this case we need to reset the backend state as well
        ZMTransportRequest *nextRequest = [self.upstreamSync nextRequest];
        
        // then
        XCTAssertNotNil(nextRequest);
        [conversation.voiceChannelRouter.v2 tearDown];
    }];
}


- (void)testThatItDoesNotResetCallDeviceIsActiveForTimeOutErrors_LeaveRequest
{
    // given
    ZMConversation *uiConv = [self insertConversationNeedsUpdateFromBackend:NO callDeviceIsActive:NO];
    __block ZMConversation *conversation;
    
    [self.syncMOC performGroupedBlockAndWait:^{
        conversation = (id)[self.syncMOC objectWithID:uiConv.objectID];
        XCTAssertTrue(conversation.hasLocalModificationsForCallDeviceIsActive);
        
        [self.upstreamSync objectsDidChange:[NSSet setWithObject:conversation]];
        ZMTransportRequest *request = [self.upstreamSync nextRequest];
        ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:@{} HTTPStatus:0 transportSessionError:[NSError requestExpiredError]];
        XCTAssertNotNil(request);
        
        // expect
        [[self.callFlowRequestStrategy expect] updateFlowsForConversation:[OCMArg checkWithBlock:^BOOL(ZMConversation *conv) {
            XCTAssertEqualObjects(conversation, conv);
            XCTAssertTrue(!conv.callDeviceIsActive);
            return true;
        }]];
        
        // when
        [request completeWithResponse:response];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    [self.syncMOC performGroupedBlockAndWait:^{
        [conversation updateLocallyModifiedCallStateKeys];

        // then
        XCTAssertFalse(conversation.callDeviceIsActive);

        // when
        ZMTransportRequest *nextRequest = [self.upstreamSync nextRequest];
        
        // then
        XCTAssertNotNil(nextRequest);
        [conversation.voiceChannelRouter.v2 tearDown];
    }];
}


- (void)testThatItReaddsTheConversationForSyncingOnTimeOutError
{
    // given
    ZMConversation *uiConv = [self insertConversationNeedsUpdateFromBackend:NO callDeviceIsActive:YES];
    __block ZMConversation *conversation;

    [self.syncMOC performGroupedBlockAndWait:^{
        conversation = (id)[self.syncMOC objectWithID:uiConv.objectID];
        XCTAssertTrue(conversation.hasLocalModificationsForCallDeviceIsActive);
        XCTAssertFalse([self.upstreamSync hasOutstandingItems]);
        
        [self.upstreamSync objectsDidChange:[NSSet setWithObject:conversation]];
        XCTAssertTrue([self.upstreamSync hasOutstandingItems]);
        
        // when
        ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:@{} HTTPStatus:0 transportSessionError:[NSError tryAgainLaterError]];
        
        ZMTransportRequest *receivedRequest = [self.upstreamSync nextRequest];
        [receivedRequest completeWithResponse:response];
        
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    [self.syncMOC performGroupedBlockAndWait:^{
        // then
        XCTAssertTrue([self.upstreamSync hasOutstandingItems]);
    }];

    
    // and when you try again
    [self.syncMOC performGroupedBlockAndWait:^{
        // when
        ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:@{} HTTPStatus:200 transportSessionError:nil];
        
        ZMTransportRequest *receivedRequest = [self.upstreamSync nextRequest];
        [receivedRequest completeWithResponse:response];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    [self.syncMOC performGroupedBlockAndWait:^{
        // then
        XCTAssertFalse([self.upstreamSync hasOutstandingItems]);
        [conversation.voiceChannelRouter.v2 tearDown];
    }];
}

- (void)testThatResetsCallDeviceIsActiveForPermanentErrors_JoinRequest
{
    // given
    ZMConversation *uiConv = [self insertConversationNeedsUpdateFromBackend:NO callDeviceIsActive:YES];
    __block ZMConversation *conversation;

    [self.syncMOC performGroupedBlockAndWait:^{
        conversation = (id)[self.syncMOC objectWithID:uiConv.objectID];
        XCTAssertTrue(conversation.hasLocalModificationsForCallDeviceIsActive);
        ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:@{} HTTPStatus:400 transportSessionError:nil];
        
        // when
        ZMUpstreamRequest *request = [self.sut requestForUpdatingObject:conversation forKeys:self.keys];
        
        //expect
        [[self.callFlowRequestStrategy expect] updateFlowsForConversation:[OCMArg checkWithBlock:^BOOL(ZMConversation *conv) {
            XCTAssertEqualObjects(conversation, conv);
            XCTAssertTrue(!conv.callDeviceIsActive);
            return true;
        }]];
        
        // when
        // we want to send a leave request in case we are joined on the BE
        [request.transportRequest completeWithResponse:response];
        
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    [self.syncMOC performGroupedBlockAndWait:^{
        // then
        XCTAssertFalse(conversation.callDeviceIsActive);
        XCTAssertTrue(conversation.hasLocalModificationsForCallDeviceIsActive);
        XCTAssertFalse(conversation.callStateNeedsToBeUpdatedFromBackend);
        
        [self.callFlowRequestStrategy verify];
        [conversation.voiceChannelRouter.v2 tearDown];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatResetsIsIgnoringCallForPermanentErrors_LeaveRequest
{
    // given
    ZMConversation *uiConv = [self insertConversationNeedsUpdateFromBackend:NO callDeviceIsActive:NO];
    __block ZMConversation *conversation;

    [self.syncMOC performGroupedBlockAndWait:^{
        conversation = (id)[self.syncMOC objectWithID:uiConv.objectID];
        conversation.isIgnoringCall = YES;
        XCTAssertTrue(conversation.hasLocalModificationsForCallDeviceIsActive);
        
        ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:@{} HTTPStatus:400 transportSessionError:nil];
        
        // expect
        [[self.callFlowRequestStrategy expect] updateFlowsForConversation:conversation];
        
        // when
        ZMUpstreamRequest *request = [self.sut requestForUpdatingObject:conversation forKeys:self.keys];

        // expect
        [[self.callFlowRequestStrategy expect] updateFlowsForConversation:conversation];
        
        // when
        [request.transportRequest completeWithResponse:response];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    [self.syncMOC performGroupedBlockAndWait:^{
        // then
        XCTAssertFalse(conversation.hasLocalModificationsForCallDeviceIsActive);
        XCTAssertFalse(conversation.callDeviceIsActive);
        XCTAssertFalse(conversation.isIgnoringCall);
        XCTAssertFalse(conversation.callStateNeedsToBeUpdatedFromBackend);
        
        [conversation.voiceChannelRouter.v2 tearDown];
    }];
}

- (void)testThatWeSendErrorNotificationIfUserIsAnActiveMemberOfConversation
{
    // GIVEN
    
    ZMConversation *uiConv = [self insertConversationNeedsUpdateFromBackend:NO callDeviceIsActive:YES];
    XCTAssertTrue(uiConv.hasLocalModificationsForCallDeviceIsActive);
    [self.uiMOC saveOrRollback];
    
    __block BOOL errorNotificationPosted = NO;
    id errorObserver = [[NSNotificationCenter defaultCenter] addObserverForName:ZMConversationVoiceChannelJoinFailedNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
        XCTAssertNotNil(note.userInfo[@"error"]);
        errorNotificationPosted = YES;
    }];
    
    ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:@{} HTTPStatus:400 transportSessionError:nil];
    
    // WHEN
    
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMConversation *conversation = (id)[self.syncMOC objectWithID:uiConv.objectID];
        ZMUpstreamRequest *request = [self.sut requestForUpdatingObject:conversation forKeys:self.keys];
        [request.transportRequest completeWithResponse:response];
    }];
    
    // THEN
    WaitForAllGroupsToBeEmpty(0.5);
    XCTAssertTrue(errorNotificationPosted);
    
    
    WaitForAllGroupsToBeEmpty(0.5);
    [[NSNotificationCenter defaultCenter] removeObserver:errorObserver];
}

- (void)testThatWeDoNotSendErrorNotificationsIfUserIsNotActiveMemberOfConversation
{
    // GIVEN
    ZMConversation *uiConv = [self insertConversationNeedsUpdateFromBackend:NO callDeviceIsActive:YES];
    [self.uiMOC saveOrRollback];
    XCTAssertTrue(uiConv.hasLocalModificationsForCallDeviceIsActive);
    
    __block BOOL errorNotificationPosted = NO;
    id errorObserver = [[NSNotificationCenter defaultCenter] addObserverForName:ZMConversationVoiceChannelJoinFailedNotification object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(__unused NSNotification *note) {
        errorNotificationPosted = YES;
    }];
    
    ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:@{} HTTPStatus:400 transportSessionError:nil];
    
    // WHEN
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMConversation *conversation = (id)[self.syncMOC objectWithID:uiConv.objectID];
        conversation.isSelfAnActiveMember = NO;
        ZMUpstreamRequest *request = [self.sut requestForUpdatingObject:conversation forKeys:self.keys];
        [request.transportRequest completeWithResponse:response];
    }];

    
    // THEN
    WaitForAllGroupsToBeEmpty(0.5);
    XCTAssertFalse(errorNotificationPosted);
    
    WaitForAllGroupsToBeEmpty(0.5);
    [[NSNotificationCenter defaultCenter] removeObserver:errorObserver];
}


- (void)testThatItDoesNotReturnTheSameObjectTwiceIfTheRequestIsNotCompleteAndTheObjectDidNonChange
{
    // given
    ZMConversation *conversation = [self insertConversationNeedsUpdateFromBackend:NO callDeviceIsActive:YES];
    XCTAssertTrue(conversation.hasLocalModificationsForCallDeviceIsActive);
    [conversation updateLocallyModifiedCallStateKeys];

    XCTAssertFalse([self.upstreamSync hasOutstandingItems]);

    // when
    [self.upstreamSync objectsDidChange:[NSSet setWithObject:conversation]];
    ZMTransportRequest *initialRequest = [self.upstreamSync nextRequest];
    [self.upstreamSync objectsDidChange:[NSSet setWithObject:conversation]];
    ZMTransportRequest *finalRequest = [self.upstreamSync nextRequest];
    
    // then
    XCTAssertNotNil(initialRequest);
    XCTAssertNil(finalRequest);
}

- (void)testThatItCompressesRequests
{
    // given
    ZMConversation *conversation = [self insertConversationNeedsUpdateFromBackend:NO callDeviceIsActive:YES];
    XCTAssertTrue(conversation.hasLocalModificationsForCallDeviceIsActive);
    [conversation updateLocallyModifiedCallStateKeys];

    XCTAssertFalse([self.upstreamSync hasOutstandingItems]);
    
    // when
    [self.upstreamSync objectsDidChange:[NSSet setWithObject:conversation]];
    ZMTransportRequest *request = [self.upstreamSync nextRequest];
    
    // then
    XCTAssertNotNil(request);
    XCTAssertTrue(request.shouldCompress);
}

- (void)checkThatItCallsAddJoinedUsers:(BOOL)shouldCallAddUsers selfUserJoined:(BOOL)isSelfUserJoined withBlock:(void (^)(NSDictionary *, ZMConversation*))block
{
    // given
    ZMConversation *uiConversation = [self insertUiConversationWithCallDeviceActive:YES];
    __block ZMConversation *syncConversation;
    
    
    [self.syncMOC performGroupedBlockAndWait:^{
        
        syncConversation = (id)[self.syncMOC objectWithID:uiConversation.objectID];
        XCTAssertTrue(syncConversation.hasLocalModificationsForCallDeviceIsActive);
        XCTAssertFalse([syncConversation.callParticipants containsObject:self.syncSelfUser]);
        
        // expect
        [[self.callFlowRequestStrategy reject] addJoinedCallParticipant:self.syncSelfUser inConversation:syncConversation];

        if (shouldCallAddUsers) {
            [[self.callFlowRequestStrategy expect] addJoinedCallParticipant:self.syncOtherUser1 inConversation:syncConversation];
        } else {
            [[self.callFlowRequestStrategy reject] addJoinedCallParticipant:self.syncOtherUser1 inConversation:syncConversation];
        }
        
        // when
        NSString *selfState = isSelfUserJoined ? @"joined" : @"idle";
        NSDictionary *payload = @{@"self":         @{ @"state": selfState,
                                                      @"quality": @1 },
                                  @"participants": @{ self.syncSelfUser.remoteIdentifier.transportString:
                                                          @{ @"state": selfState,
                                                             @"quality": @1 },
                                                      self.syncOtherUser1.remoteIdentifier.transportString:
                                                          @{ @"state": @"joined",
                                                             @"quality": @1 }
                                                      }
                                  };
        
        block(payload, syncConversation);
    }];
    
    WaitForAllGroupsToBeEmpty(0.5);
    [self.syncMOC performGroupedBlockAndWait:^{
        [syncConversation.voiceChannelRouter.v2 tearDown];
    }];
    
    [self.callFlowRequestStrategy verify];
}

- (void)testThatItCallsAddUsersOnFLowSyncOnlyOnOtherUsers
{
    [self checkThatItCallsAddJoinedUsers:YES selfUserJoined:YES withBlock:^(NSDictionary * payload, ZMConversation *syncConversation) {
        [self.sut.contextChangeTrackers.lastObject objectsDidChange:[NSSet setWithObject:syncConversation]];
        
        ZMTransportRequest *request = [self.sut nextRequest];
        XCTAssertNotNil(request);
        
        ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:payload HTTPStatus:200 transportSessionError:nil];
        [request completeWithResponse:response];
    }];
}

- (void)testThatItDoesNotCallAddUsersOnFLowSyncIfSelfUserIsNotJoined
{
    [self checkThatItCallsAddJoinedUsers:NO selfUserJoined:NO withBlock:^(NSDictionary * payload, ZMConversation *syncConversation) {
        [self.sut.contextChangeTrackers.lastObject objectsDidChange:[NSSet setWithObject:syncConversation]];
        
        ZMTransportRequest *request = [self.sut nextRequest];
        XCTAssertNotNil(request);
        
        ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:payload HTTPStatus:200 transportSessionError:nil];
        [request completeWithResponse:response];
    }];
}

- (void)testThatItDoesNotCallAddUsersOnFLowSyncForPushEvents
{
    [self checkThatItCallsAddJoinedUsers:NO selfUserJoined:YES withBlock:^(NSDictionary * payload, ZMConversation *syncConversation) {
        NOT_USED(syncConversation);
        NSArray *events = [ZMUpdateEvent eventsArrayFromPushChannelData:@[payload]];
        [self.sut processEvents:events liveEvents:YES prefetchResult:nil];
    }];
}

- (void)testThatItDoesNotCallAddUsersOnFLowSyncForDownloadedEvents
{
    [self checkThatItCallsAddJoinedUsers:NO selfUserJoined:YES withBlock:^(NSDictionary * payload, ZMConversation *syncConversation) {
        NOT_USED(syncConversation);
        ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:payload HTTPStatus:200 transportSessionError:nil];
        [self.sut updateObject:syncConversation withResponse:response downstreamSync:nil];
    }];
}

@end


@implementation ZMCallStateRequestStrategyTests (PushChannel)

- (void)testThatItDoesNotReturnARequestWhileThePushChannelIsClosed
{
    // given
    ZMConversation *conversation = [self insertConversationNeedsUpdateFromBackend:NO callDeviceIsActive:YES];
    XCTAssertTrue(conversation.hasLocalModificationsForCallDeviceIsActive);
    [conversation updateLocallyModifiedCallStateKeys];

    [self.upstreamSync objectsDidChange:[NSSet setWithObject:conversation]];

    // when
    [self simulateClosingPushChannel];
    ZMTransportRequest *initialRequest = [self.upstreamSync nextRequest];
    
    // then
    XCTAssertNil(initialRequest);
    XCTAssertTrue([self.upstreamSync hasOutstandingItems]);
}

- (void)testThatItReturnsARequestWhenThePushChannelIsOpen
{
    // given
    ZMConversation *conversation = [self insertConversationNeedsUpdateFromBackend:NO callDeviceIsActive:YES];
    XCTAssertTrue(conversation.hasLocalModificationsForCallDeviceIsActive);
    [conversation updateLocallyModifiedCallStateKeys];

    [self.upstreamSync objectsDidChange:[NSSet setWithObject:conversation]];

    // when
    [self simulateOpeningPushChannel];
    ZMTransportRequest *initialRequest = [self.upstreamSync nextRequest];
    
    // then
    XCTAssertNotNil(initialRequest);
}

- (void)testThatItReturnsTheRequestWhenItOpensAgain
{
    // given
    ZMConversation *conversation = [self insertConversationNeedsUpdateFromBackend:NO callDeviceIsActive:YES];
    XCTAssertTrue(conversation.hasLocalModificationsForCallDeviceIsActive);
    [conversation updateLocallyModifiedCallStateKeys];
    
    [self.upstreamSync objectsDidChange:[NSSet setWithObject:conversation]];
    
    // when
    [self simulateClosingPushChannel];
    ZMTransportRequest *initialRequest = [self.upstreamSync nextRequest];
    [self simulateOpeningPushChannel];
    ZMTransportRequest *finalRequest = [self.upstreamSync nextRequest];
    
    // then
    XCTAssertNil(initialRequest);
    XCTAssertNotNil(finalRequest);
}


- (void)testThatItNotifiesTheOperationLoopWhenThePushChannelOpensAgain_OutstandingItems
{
    // given
    ZMConversation *conversation = [self insertConversationNeedsUpdateFromBackend:NO callDeviceIsActive:YES];
    XCTAssertTrue(conversation.hasLocalModificationsForCallDeviceIsActive);
    [conversation updateLocallyModifiedCallStateKeys];

    [self.upstreamSync objectsDidChange:[NSSet setWithObject:conversation]];
    [self simulateClosingPushChannel];
    
    // expect
    id mockRequestAvailableNotification = [OCMockObject niceMockForClass:ZMRequestAvailableNotification.class];
    [[[mockRequestAvailableNotification expect] classMethod] notifyNewRequestsAvailable:OCMOCK_ANY];
    
    // when
    [self simulateOpeningPushChannel];
    
    // then
    [(OCMockObject *) mockRequestAvailableNotification verify];
    
    // after
    [(OCMockObject *) mockRequestAvailableNotification stopMocking];
}


- (void)checkThatItAppendsTheLogForAllConversations:(void (^)(ZMConversation *, ZMTransportResponse *))block
{
    // given
    ZMConversation *conversation1 = self.syncGroupConversation;
    
    NSDictionary *payload1 = [self payloadForCallStateEventInConversation:conversation1 othersAreJoined:YES selfIsJoined:NO sequence:nil];
    ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:payload1 HTTPStatus:200 transportSessionError:nil];

    // then
    [[self.callFlowRequestStrategy expect] appendLogForConversationID:conversation1.remoteIdentifier message:[OCMArg checkWithBlock:^BOOL(NSString *message) {
        return [message hasPrefix:@"PushChannel did close"];
    }]];
    [[self.callFlowRequestStrategy expect] appendLogForConversationID:conversation1.remoteIdentifier message:[OCMArg checkWithBlock:^BOOL(NSString *message) {
        return [message hasPrefix:@"PushChannel did open"];
    }]];

    // when
    [self.syncMOC performGroupedBlockAndWait:^{
        block(conversation1, response);
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    [self simulateClosingPushChannel];
    [self simulateOpeningPushChannel];
    
    // then
    [self.callFlowRequestStrategy verify];
}

- (void)testThatItAppendsTheLogForAllConversations_Push
{
    __block ZMConversation *conv;

    [self checkThatItAppendsTheLogForAllConversations:^(ZM_UNUSED id conversation, ZMTransportResponse *response) {
        conv = conversation;
        NSDictionary *eventPayload = @{@"id": NSUUID.createUUID.transportString,
                                       @"payload" : @[response.payload]};
        ZMUpdateEvent *event = [ZMUpdateEvent eventsArrayFromPushChannelData:eventPayload].firstObject;
        [self.sut processEvents:@[event] liveEvents:YES prefetchResult:nil];
        [conv.voiceChannelRouter.v2 tearDown];
    }];
    WaitForAllGroupsToBeEmpty(0.5);

    XCTAssertEqual(conv.voiceChannelRouter.v2.state, VoiceChannelV2StateIncomingCall);
}

- (void)testThatItItAppendsTheLogForAllConversations_Downstream
{
    __block ZMConversation *conv;
    [self checkThatItAppendsTheLogForAllConversations:^(ZMConversation *conversation, ZMTransportResponse *response) {
        conv = conversation;
        [self.sut updateObject:conversation withResponse:response downstreamSync:nil];
        [conv.voiceChannelRouter.v2 tearDown];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    XCTAssertEqual(conv.voiceChannelRouter.v2.state, VoiceChannelV2StateIncomingCallInactive);
}

- (void)testThatItItAppendsTheLogForAllConversations_Upstream
{
    __block ZMConversation *conv;
    [self checkThatItAppendsTheLogForAllConversations:^(ZMConversation *conversation, ZMTransportResponse *response) {
        conv = conversation;
        [self.sut updateUpdatedObject:conversation requestUserInfo:nil response:response keysToParse:[NSSet setWithObject:ZMConversationCallDeviceIsActiveKey]];
        [conv.voiceChannelRouter.v2 tearDown];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    XCTAssertEqual(conv.voiceChannelRouter.v2.state, VoiceChannelV2StateIncomingCall);
}



@end





@implementation ZMCallStateRequestStrategyTests (GSMCalls)

- (void)testThatItSetsTheCause_Requested_CallDeviceIsActive_NO_ISInterruptedConv_YES
{
    // given
    ZMConversation *conversation = self.syncSelfToUser1Conversation;
    conversation.callDeviceIsActive = NO;
    
    NSDictionary *expectedPayload = @{@"self" : @{@"state" : @"idle",
                                                  },
                                      @"cause": @"requested"};
    
    // when
    [[[self.gsmCallHandler expect] andReturnValue:OCMOCK_VALUE(YES)] isInterruptedCallConversation:conversation];
    ZMTransportRequest *request = [self.sut requestForUpdatingObject:conversation forKeys:self.keys].transportRequest;
    
    // then
    XCTAssertEqualObjects([request.payload asDictionary], expectedPayload);
}

- (void)testThatItSetsTheCause_Requested_CallDeviceIsActive_YES_ISInterruptedConv_YES
{
    // given
    ZMConversation *conversation = self.syncSelfToUser1Conversation;
    conversation.callDeviceIsActive = YES;
    
    NSDictionary *expectedPayload = @{@"self" : @{@"state" : @"joined",
                                                  @"suspended" : @(YES),
                                                  @"videod" : @(NO)
                                                  },
                                      @"cause": @"interrupted"};

    // when
    [[[self.gsmCallHandler expect] andReturnValue:OCMOCK_VALUE(YES)] isInterruptedCallConversation:conversation];
    ZMTransportRequest *request = [self.sut requestForUpdatingObject:conversation forKeys:self.keys].transportRequest;
    
    // then
    XCTAssertEqualObjects([request.payload asDictionary], expectedPayload);
}

- (void)testThatItSetsTheCause_Requested_CallDeviceIsActive_YES_ISInterruptedConv_NO
{
    // given
    ZMConversation *conversation = self.syncSelfToUser1Conversation;
    conversation.callDeviceIsActive = YES;
    
    NSDictionary *expectedPayload = @{@"self" : @{@"state" : @"joined",
                                                  @"suspended" : @(NO),
                                                  @"videod" : @(NO)
                                                  },
                                      @"cause": @"requested"};
    
    // when
    [[[self.gsmCallHandler expect] andReturnValue:OCMOCK_VALUE(NO)] isInterruptedCallConversation:conversation];
    ZMTransportRequest *request = [self.sut requestForUpdatingObject:conversation forKeys:self.keys].transportRequest;
    
    // then
    XCTAssertEqualObjects([request.payload asDictionary], expectedPayload);
}

- (void)testThatItSetsTheCause_Requested_CallDeviceIsActive_NO_ISInterruptedConv_NO
{
    // given
    ZMConversation *conversation = self.syncSelfToUser1Conversation;
    conversation.callDeviceIsActive = NO;
    
    NSDictionary *expectedPayload = @{@"self" : @{@"state" : @"idle",
                                                  },
                                      @"cause": @"requested"};
    
    // when
    [[[self.gsmCallHandler expect] andReturnValue:OCMOCK_VALUE(NO)] isInterruptedCallConversation:conversation];
    ZMTransportRequest *request = [self.sut requestForUpdatingObject:conversation forKeys:self.keys].transportRequest;
    
    // then
    XCTAssertEqualObjects([request.payload asDictionary], expectedPayload);
}


- (void)testThatItSetsTheActiveConversationOnTheGSMCallHandler_UpstreamResponse
{
    // given
    ZMConversation *conversation = self.syncSelfToUser1Conversation;
    conversation.callDeviceIsActive = YES;
    
    // expect
    [[self.gsmCallHandler expect] setActiveCallSyncConversation:conversation];
    
    // then
    ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:@{} HTTPStatus:200 transportSessionError:nil];
    [self.sut updateUpdatedObject:conversation requestUserInfo:nil response:response keysToParse:self.keys];
}

- (void)testThatItReSetsTheActiveConversationOnTheGSMCallHandler_UpstreamResponse
{
    // given
    ZMConversation *conversation = self.syncSelfToUser1Conversation;
    conversation.callDeviceIsActive = NO;
    
    // expect
    [[self.gsmCallHandler expect] setActiveCallSyncConversation:nil];
    
    // then
    ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:@{} HTTPStatus:200 transportSessionError:nil];
    [self.sut updateUpdatedObject:conversation requestUserInfo:nil response:response keysToParse:self.keys];
}

- (void)testThatItDoesNotReleaseTheFlowsWhenParsingAResponseForInterruptedCallStateRequest
{
    // given
    ZMConversation *conversation = self.syncSelfToUser1Conversation;
    conversation.callDeviceIsActive = NO;
    
    // expect
    [[[self.gsmCallHandler expect] andReturnValue:OCMOCK_VALUE(YES)] isInterruptedCallConversation:conversation];
    [[self.callFlowRequestStrategy reject] updateFlowsForConversation:OCMOCK_ANY];

    // when
    ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:@{} HTTPStatus:200 transportSessionError:nil];
    [self.sut updateUpdatedObject:conversation requestUserInfo:nil response:response keysToParse:self.keys];
    
    [self.callFlowRequestStrategy verify];
}


- (void)testThatItReleasesTheFlowsWhenParsingAResponseForNormalRequest
{
    // given
    ZMConversation *conversation = self.syncSelfToUser1Conversation;
    conversation.callDeviceIsActive = NO;
    
    // expect
    [[[self.gsmCallHandler expect] andReturnValue:OCMOCK_VALUE(NO)] isInterruptedCallConversation:conversation];
    [[self.callFlowRequestStrategy expect] updateFlowsForConversation:[OCMArg checkWithBlock:^BOOL(ZMConversation *conv) {
        XCTAssertEqualObjects(conversation, conv);
        XCTAssertTrue(!conv.callDeviceIsActive);
        return true;
    }]];
    
    // when
    ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:@{} HTTPStatus:200 transportSessionError:nil];
    [self.sut updateUpdatedObject:conversation requestUserInfo:nil response:response keysToParse:self.keys];
    
    [self.callFlowRequestStrategy verify];
}

@end


@implementation ZMCallStateRequestStrategyTests (RejoiningAfterCrashOrRestart)


- (void)testThatOnStartUpItDoesNotSetCallStateNeedsToBeUpdatedFromBackend_InterruptedbyGSMCall
{
    // given
    ZMConversation *conversation = self.syncSelfToUser1Conversation;
    [[conversation mutableOrderedSetValueForKey:@"callParticipants"] addObject:self.syncOtherUser1];
    
    XCTAssertTrue(conversation.callParticipants.count > 0);
    XCTAssertFalse(conversation.callStateNeedsToBeUpdatedFromBackend);

    
    // expect
    [[[self.gsmCallHandler expect] andReturnValue:@YES] isInterruptedCallConversation:conversation];
    
    // when
    self.sut = (id) [[ZMCallStateRequestStrategy alloc] initWithManagedObjectContext:self.syncMOC applicationStatus:self.mockApplicationStatus callFlowRequestStrategy:self.callFlowRequestStrategy gsmCallHandler:self.gsmCallHandler];
    WaitForAllGroupsToBeEmpty(0.5);

    // then
    XCTAssertFalse(conversation.callStateNeedsToBeUpdatedFromBackend);
    [self.gsmCallHandler verify];
}

- (void)testThatOnStartUpItDoesNotSetCallStateNeedsToBeUpdatedFromBackend_NoCallParticipants
{
    // given
    ZMConversation *conversation = self.syncSelfToUser1Conversation;
    XCTAssertTrue(conversation.callParticipants.count == 0);
    XCTAssertFalse(conversation.callStateNeedsToBeUpdatedFromBackend);
    
    
    // expect
    [[self.gsmCallHandler reject] isInterruptedCallConversation:conversation];
    
    // when
    self.sut = (id) [[ZMCallStateRequestStrategy alloc] initWithManagedObjectContext:self.syncMOC applicationStatus:self.mockApplicationStatus callFlowRequestStrategy:self.callFlowRequestStrategy gsmCallHandler:self.gsmCallHandler];
    WaitForAllGroupsToBeEmpty(0.5);

    // then
    XCTAssertFalse(conversation.callStateNeedsToBeUpdatedFromBackend);
    [self.gsmCallHandler verify];
}


- (void)testThatOnStartUpItSetsCallStateNeedsToBeUpdatedFromBackend_NotInterruptedbyGSMCall
{
    ZMConversation *conversation = self.syncSelfToUser1Conversation;
    
    // given
    [self.syncMOC performGroupedBlockAndWait:^{
        [[conversation mutableOrderedSetValueForKey:@"callParticipants"] addObject:self.syncOtherUser1];
        [self.syncMOC saveOrRollback];
    }];
    
    XCTAssertTrue(conversation.callParticipants.count > 0);
    XCTAssertFalse(conversation.callStateNeedsToBeUpdatedFromBackend);
    
    
    // expect
    [[[self.gsmCallHandler expect] andReturnValue:@NO] isInterruptedCallConversation:conversation];
    
    // when
    self.sut = (id) [[ZMCallStateRequestStrategy alloc] initWithManagedObjectContext:self.syncMOC applicationStatus:self.mockApplicationStatus callFlowRequestStrategy:self.callFlowRequestStrategy gsmCallHandler:self.gsmCallHandler];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertTrue(conversation.callStateNeedsToBeUpdatedFromBackend);
    [self.gsmCallHandler verify];
}


- (void)testThatItLeavesAConversationWhenADownstreamRequestCompletesWithTheSelfUserJoined_CallDeviceIsActive_NO
{
    // given
    ZMConversation *conversation = self.syncSelfToUser1Conversation;
    [self.syncMOC performGroupedBlockAndWait:^{
        [[conversation mutableOrderedSetValueForKey:@"callParticipants"] addObject:self.syncOtherUser1];
        [[conversation mutableOrderedSetValueForKey:@"callParticipants"] addObject:self.syncSelfUser];
    }];

    // when
    NSDictionary *payload = [self payloadForConversation:conversation othersAreJoined:YES selfIsJoined:YES];
    ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:payload HTTPStatus:200 transportSessionError:nil];
    [self.sut updateObject:conversation withResponse:response downstreamSync:nil];
    WaitForAllGroupsToBeEmpty(0.5);
    
    NOT_USED([self.syncMOC mergeCallStateChanges:[self.uiMOC.zm_callState createCopyAndResetHasChanges]]);
    // then
    XCTAssertTrue(conversation.hasLocalModificationsForCallDeviceIsActive);
    XCTAssertFalse(conversation.callDeviceIsActive);
    XCTAssertTrue([conversation.keysThatHaveLocalModifications containsObject:ZMConversationCallDeviceIsActiveKey]);
}

- (void)testThatItDoesNotLeaveTheConversationWhenADownstreamRequestCompletesWithTheSelfUserJoined_CallDeviceIsActive_YES
{
    // given
    ZMConversation *conversation = self.syncSelfToUser1Conversation;
    conversation.callDeviceIsActive = YES;
    [[conversation mutableOrderedSetValueForKey:@"callParticipants"] addObject:self.syncOtherUser1];
    [[conversation mutableOrderedSetValueForKey:@"callParticipants"] addObject:self.syncSelfUser];
    
    // when
    NSDictionary *payload = [self payloadForConversation:conversation othersAreJoined:YES selfIsJoined:YES];
    ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:payload HTTPStatus:200 transportSessionError:nil];
    [self.sut updateObject:conversation withResponse:response downstreamSync:nil];
    WaitForAllGroupsToBeEmpty(0.5);
    
    NOT_USED([self.syncMOC mergeCallStateChanges:[self.uiMOC.zm_callState createCopyAndResetHasChanges]]);
    // then
    XCTAssertFalse(conversation.hasLocalModificationsForCallDeviceIsActive);
    XCTAssertTrue(conversation.callDeviceIsActive);
    XCTAssertFalse([conversation.keysThatHaveLocalModifications containsObject:ZMConversationCallDeviceIsActiveKey]);
}


@end


