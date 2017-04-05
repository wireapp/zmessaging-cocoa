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
@import WireTesting;
@import WireDataModel;

#import "VoiceChannelV2Tests.h"
#import "ZMFlowSync.h"
#import "ZMUserSession.h"
#import "ZMAVSBridge.h"

#if TARGET_OS_IPHONE
@import CoreTelephony;
#endif

@interface VoiceChannelV2TestsWithDiscStore : MessagingTest
@end


@implementation VoiceChannelV2TestsWithDiscStore

- (BOOL)shouldUseInMemoryStore;
{
    return NO;
}

- (void)tearDownVoiceChannelForSyncConversation:(ZMConversation *)conversation
{
    ZMConversation *uiConv = (id)[self.uiMOC objectWithID:conversation.objectID];
    [uiConv.voiceChannelRouter.v2 tearDown];
}

- (void)testThatItResetsTheFlowManagerCategoryToNormalOnStoreCreationForUIContext;
{
    // given
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    conversation.conversationType = ZMConversationTypeOneOnOne;
    conversation.isFlowActive = YES;
    [self.uiMOC saveOrRollback];
    NSManagedObjectID *moid = conversation.objectID;

    // when
    [self resetUIandSyncContextsAndResetPersistentStore:YES];
    WaitForAllGroupsToBeEmpty(0.5);
    conversation = (id) [self.uiMOC existingObjectWithID:moid error:nil];

    // then
    XCTAssertNotNil(conversation);
    XCTAssertEqual(conversation.isFlowActive, false);
}

- (void)testThatItResetsTheFlowManagerCategoryToNormalOnStoreCreationForSyncContext;
{
    __block NSManagedObjectID *moid;
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        conversation.conversationType = ZMConversationTypeOneOnOne;
        conversation.isFlowActive = YES;
        [self.syncMOC saveOrRollback];
        moid = conversation.objectID;
    }];

    // when
    [self resetUIandSyncContextsAndResetPersistentStore:YES];
    __block ZMConversation *conversation;
    [self.syncMOC performGroupedBlockAndWait:^{
        conversation = (id) [self.syncMOC existingObjectWithID:moid error:nil];

        // then
        XCTAssertNotNil(conversation);
        XCTAssertEqual(conversation.isFlowActive, false);
    }];
    
    WaitForAllGroupsToBeEmpty(0.5);
}


- (void)testThatItResetsTheCallDeviceIsActiveToNoOnStoreCreationForUIContext;
{
    // given
    ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    conversation.conversationType = ZMConversationTypeOneOnOne;
    conversation.callDeviceIsActive = YES;
    [self.uiMOC saveOrRollback];
    NSManagedObjectID *moid = conversation.objectID;
    
    // when
    [self resetUIandSyncContextsAndResetPersistentStore:YES];
    WaitForAllGroupsToBeEmpty(0.5);
    conversation = (id) [self.uiMOC existingObjectWithID:moid error:nil];

    // then
    XCTAssertNotNil(conversation);
    XCTAssertFalse(conversation.callDeviceIsActive);
}

- (void)testThatItResetsTheCallDeviceIsActiveToNoOnStoreCreationForSyncContext;
{
    __block NSManagedObjectID *moid;
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        conversation.conversationType = ZMConversationTypeOneOnOne;
        conversation.callDeviceIsActive = YES;
        [self.syncMOC saveOrRollback];
        moid = conversation.objectID;
    }];

    // when
    [self resetUIandSyncContextsAndResetPersistentStore:YES];
    
    __block ZMConversation *conversation;
    [self.syncMOC performGroupedBlockAndWait:^{
        conversation = (id) [self.syncMOC existingObjectWithID:moid error:nil];

        // then
        XCTAssertNotNil(conversation);
        XCTAssertFalse(conversation.callDeviceIsActive);
    }];
    WaitForAllGroupsToBeEmpty(0.5);
}
@end




@implementation VoiceChannelV2Tests

- (void)setUp
{
    [super setUp];
    
    [ZMUserSession setCallingProtocolStrategy:CallingProtocolStrategyVersion2];

    self.receivedErrors = [NSMutableArray array];
    
    self.conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    self.conversation.conversationType = ZMConversationTypeOneOnOne;
    self.conversation.remoteIdentifier = [NSUUID new];
    self.conversation.connection = [ZMConnection insertNewObjectInManagedObjectContext:self.uiMOC];
    self.conversation.connection.to = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    self.conversation.connection.to.name = @"User 1";
    self.conversation.connection.to.remoteIdentifier = [NSUUID new];
    
    self.otherConversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    self.otherConversation.conversationType = ZMConversationTypeOneOnOne;
    self.otherConversation.remoteIdentifier = [NSUUID new];
    
    self.groupConversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    self.groupConversation.conversationType = ZMConversationTypeGroup;
    self.groupConversation.remoteIdentifier = [NSUUID new];
    
    self.selfUser = [ZMUser selfUserInContext:self.uiMOC];
    self.selfUser.name = @"Me Myself";
    self.selfUser.remoteIdentifier = NSUUID.createUUID;
    
    self.otherUser = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    self.otherUser.name = @"Other Guy";
    self.otherUser.remoteIdentifier = NSUUID.createUUID;
    
    [self.conversation.mutableOtherActiveParticipants addObject:self.otherUser];
    [self.uiMOC saveOrRollback];
    
    [self.syncMOC performGroupedBlockAndWait:^{
        self.syncSelfUser = [ZMUser selfUserInContext:self.syncMOC];
        self.syncUser1 = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        self.syncUser1.remoteIdentifier = NSUUID.createUUID;
        self.syncUser2 = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        self.syncUser2.remoteIdentifier = NSUUID.createUUID;
        self.syncUser3 = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        self.syncUser3.remoteIdentifier = NSUUID.createUUID;
        self.syncGroupConversation = (id)[self.syncMOC objectWithID:self.groupConversation.objectID];
        self.syncOneOnOneConversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        self.syncOneOnOneConversation.conversationType = ZMConversationTypeOneOnOne;
        self.syncOneOnOneConversation.remoteIdentifier = NSUUID.createUUID;
        [self.syncMOC saveOrRollback];
    }];
}

- (void)tearDown
{
    WaitForAllGroupsToBeEmpty(0.5);
    [ZMCallTimer resetTestCallTimeout];
    
    [ZMUserSession setCallingProtocolStrategy:CallingProtocolStrategyNegotiate];
    
    self.conversation = nil;
    self.otherConversation = nil;
    self.groupConversation = nil;

    self.selfUser = nil;
    self.otherUser = nil;
    
    self.receivedErrors = nil;

    [super tearDown];
}


- (void)couldNotInitialiseCallWithError:(NSError *)error;
{
    [self.receivedErrors addObject:error];
}

@end



@implementation VoiceChannelV2Tests (DebugInformation)

- (void)testThatItCanFormatEmptyInformation;
{
    // given
    [VoiceChannelV2 setLastSessionIdentifier:nil];
    [VoiceChannelV2 setLastSessionStartDate:nil];
    id userSession = [OCMockObject niceMockForClass:ZMUserSession.class];
    [[[userSession stub] andReturn:self.uiMOC] managedObjectContext];

    // when
    NSAttributedString *s = [VoiceChannelV2 voiceChannelDebugInformation];

    // then
    XCTAssertEqualObjects(s.string, @"Session ID: \nSession start date: \nSession start date (GMT): \n");
}

- (void)testThatItCanFormatInformation;
{
    // given
    [VoiceChannelV2 setLastSessionIdentifier:@"test-session-ID"];
    [VoiceChannelV2 setLastSessionStartDate:[NSDate dateWithTimeIntervalSinceReferenceDate:448206432.09855801]];
    id userSession = [OCMockObject niceMockForClass:ZMUserSession.class];
    [[[userSession stub] andReturn:self.uiMOC] managedObjectContext];

    // when
    NSAttributedString *s = [VoiceChannelV2 voiceChannelDebugInformation];

    // then
    NSArray *lines = [s.string componentsSeparatedByString:@"\n"];
    NSString *first = lines.firstObject;
    NSString *third = (lines.count >= 3) ? lines[2] : nil;
    XCTAssertEqualObjects(first, @"Session ID: test-session-ID");
    XCTAssertEqualObjects(third, @"Session start date (GMT): March 16, 2015 at 1:47:12 PM GMT");
}

@end



@implementation VoiceChannelV2Tests (VoiceChannelState)

- (void)testThatItReturnsNoActiveUsersForTheState;
{
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        [self.syncOneOnOneConversation.voiceChannelRouter.v2 removeAllCallParticipants];
        
        // then
        XCTAssertEqual(self.syncOneOnOneConversation.voiceChannel.state, VoiceChannelV2StateNoActiveUsers);
    }];
}

- (void)testThatItReturnsNoActiveUsersForNewConversation;
{
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        [self.syncGroupConversation.voiceChannelRouter.v2 removeAllCallParticipants];
        self.syncGroupConversation.isIgnoringCall = YES;
        
        // then
        XCTAssertEqual(self.syncGroupConversation.voiceChannel.state, VoiceChannelV2StateNoActiveUsers);
    }];
}

- (void)testThatItReturnsNoActiveUsersForTheStateWhenNoUsersAreJoined
{
    // given
    XCTAssertFalse([self.conversation.callParticipants containsObject:self.selfUser]);
    XCTAssertFalse([self.conversation.callParticipants containsObject:self.otherUser]);
    
    self.conversation.isFlowActive = NO;
    self.conversation.callDeviceIsActive = NO;
    
    // then
    XCTAssertEqual(self.conversation.voiceChannel.state, VoiceChannelV2StateNoActiveUsers);
}



- (void)testThatItReturnsSelfIsCallingForTheStateWhenSelfIsJoinedButNoMediaIsFlowing
{
    [self.syncMOC performGroupedBlockAndWait:^{
        
        // given
        [self.syncOneOnOneConversation.voiceChannelRouter.v2 addCallParticipant:self.syncSelfUser];
        XCTAssertFalse([self.syncOneOnOneConversation.callParticipants containsObject:self.syncUser1]);
        
        self.syncOneOnOneConversation.isFlowActive = NO;
        self.syncOneOnOneConversation.callDeviceIsActive = YES;
        
        // then
        XCTAssertEqual(self.syncOneOnOneConversation.voiceChannel.state, VoiceChannelV2StateOutgoingCall);
    }];
}

- (void)testThatItReturnsOtherUserIsCallingForTheStateWhenSelfIsNotJoinedAndOtherUsersAreJoined
{
    [self.syncMOC performGroupedBlockAndWait:^{
        
        // given
        XCTAssertFalse([self.syncOneOnOneConversation.callParticipants containsObject:self.syncSelfUser]);
        [self.syncOneOnOneConversation.voiceChannelRouter.v2 addCallParticipant:self.syncUser1];
        
        self.syncOneOnOneConversation.isFlowActive = NO;
        self.syncOneOnOneConversation.callDeviceIsActive = NO;
        
        // then
        XCTAssertEqual(self.syncOneOnOneConversation.voiceChannel.state, VoiceChannelV2StateIncomingCall);
    }];
}

- (void)testThatItReturnsSelfIfJoiningForTheStateWhenThesyncUser1IsConnectedAndSelfIsConnecting
{
    [self.syncMOC performGroupedBlockAndWait:^{
        
        // given
        [self.syncOneOnOneConversation.voiceChannelRouter.v2 addCallParticipant:self.syncSelfUser];
        [self.syncOneOnOneConversation.voiceChannelRouter.v2 addCallParticipant:self.syncUser1];
        
        self.syncOneOnOneConversation.isFlowActive = NO;
        self.syncOneOnOneConversation.callDeviceIsActive = YES;
        
        // then
        XCTAssertEqual(self.syncOneOnOneConversation.voiceChannel.state, VoiceChannelV2StateSelfIsJoiningActiveChannel);
    }];
}

- (void)testThatItReturnsSelfConnectedForTheStateWhenBothUsersAreConnectedAndTheFlowCategoryIsCall
{
    [self.syncMOC performGroupedBlockAndWait:^{
        
        // given
        [self.syncOneOnOneConversation.voiceChannelRouter.v2 addCallParticipant:self.syncSelfUser];
        [self.syncOneOnOneConversation.voiceChannelRouter.v2 addCallParticipant:self.syncUser1];
        
        [self.syncOneOnOneConversation.voiceChannelRouter.v2 updateActiveFlowParticipants:@[self.syncUser1]];
        self.syncOneOnOneConversation.callDeviceIsActive = YES;
        self.syncOneOnOneConversation.isFlowActive = YES;
        
        // then
        XCTAssertEqual(self.syncOneOnOneConversation.voiceChannel.state, VoiceChannelV2StateSelfConnectedToActiveChannel);
    }];
}

- (void)testThatItReturnsTransferReadyForTheStateWhenBothUsersAreConnectedButThisDeviceIsNotActive
{
    [self.syncMOC performGroupedBlockAndWait:^{
        
        // given
        [self.syncOneOnOneConversation.voiceChannelRouter.v2 addCallParticipant:self.syncSelfUser];
        [self.syncOneOnOneConversation.voiceChannelRouter.v2 addCallParticipant:self.syncUser1];
        
        [self.uiMOC saveOrRollback];
        
        self.syncOneOnOneConversation.isFlowActive = NO;
        self.syncOneOnOneConversation.callDeviceIsActive = NO;
        
        // then
        XCTAssertEqual(self.syncOneOnOneConversation.voiceChannel.state, VoiceChannelV2StateDeviceTransferReady);
    }];
}

- (void)testThatItReturnsTransferReadyForTheStateWhenWhenWeAreCallingFromAnotherDevice
{
    [self.syncMOC performGroupedBlockAndWait:^{
        
        // given
        [self.syncOneOnOneConversation.voiceChannelRouter.v2 addCallParticipant:self.syncSelfUser];
        XCTAssertFalse([self.syncOneOnOneConversation.callParticipants containsObject:self.syncUser1]);
        
        self.syncOneOnOneConversation.isFlowActive = NO;
        self.syncOneOnOneConversation.callDeviceIsActive = NO;
        
        // then
        XCTAssertEqual(self.syncOneOnOneConversation.voiceChannel.state, VoiceChannelV2StateDeviceTransferReady);
    }];
}

- (void)testThatOtherParticipantsDoesNotIncludeTheOtherUserIfItIsNotConnected
{
    [self.syncMOC performGroupedBlockAndWait:^{
        
        // given
        XCTAssertFalse([self.syncOneOnOneConversation.callParticipants containsObject:self.syncUser1]);
        
        // then
        XCTAssertEqual(self.syncOneOnOneConversation.voiceChannel.participants.count, 0u);
    }];
}

- (void)testThatOtherParticipantsDoesIncludeTheOtherUserIfItIsConnected
{
    [self.syncMOC performGroupedBlockAndWait:^{
        
        // given
        [self.syncOneOnOneConversation.voiceChannelRouter.v2 addCallParticipant:self.syncUser1];
        
        // then
        XCTAssertEqual(self.syncOneOnOneConversation.voiceChannel.participants.firstObject, self.syncUser1);
    }];
}


- (void)testThatItReturnsNoActiveUserWhenIgnoring_OneOnOneConversation
{
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        [self.syncOneOnOneConversation.voiceChannelRouter.v2 addCallParticipant:self.syncUser1];
        XCTAssertFalse([self.syncOneOnOneConversation.callParticipants containsObject:self.syncSelfUser]);
        XCTAssertTrue([self.syncOneOnOneConversation.callParticipants containsObject:self.syncUser1]);
        
        self.syncOneOnOneConversation.isFlowActive = NO;
        self.syncOneOnOneConversation.callDeviceIsActive = NO;
        self.syncOneOnOneConversation.isIgnoringCall = YES;
        
        // then
        XCTAssertEqual(self.syncOneOnOneConversation.voiceChannel.state, VoiceChannelV2StateNoActiveUsers);
    }];
}

- (void)testThatItSetsIgnoringCall
{
    // when
    [self.conversation.voiceChannelRouter.v2 ignore];
    
    // then
    XCTAssertTrue(self.conversation.isIgnoringCall);
}

- (void)testThatItResetsIsIgnoringCallWhenIgnoringACallAndImmediatelyCallingBack
{
    // when
    [self.conversation.voiceChannelRouter.v2 ignore];

    // then
    XCTAssertTrue(self.conversation.isIgnoringCall);

    // when
    [self.conversation.voiceChannelRouter.v2 join];
    
    // then
    XCTAssertFalse(self.conversation.isIgnoringCall);
}

- (void)testThatItReturns_Connected_ForAOneOnOneConversation_With_ActiveFlow_IncomingCall
{
    [self.syncMOC performGroupedBlockAndWait:^{
        // when
        // other user joins first (calls)
        [self.syncGroupConversation.voiceChannelRouter.v2 addCallParticipant:self.syncUser1];
        
        [self.syncGroupConversation.voiceChannelRouter.v2 join];
        [self.syncGroupConversation.voiceChannelRouter.v2 addCallParticipant:self.syncSelfUser];
        [self.syncGroupConversation.voiceChannelRouter.v2 updateActiveFlowParticipants:@[self.syncUser1]];
        self.syncGroupConversation.isFlowActive = YES;
        
        // then
        XCTAssertFalse(self.syncGroupConversation.isOutgoingCall);
        XCTAssertEqual(self.syncGroupConversation.voiceChannel.state, VoiceChannelV2StateSelfConnectedToActiveChannel);
    }];
}

- (void)testThatItReturns_Joining_ForAOneOnOneConversation_WithOut_ActiveFlow_IncomingCall
{
    [self.syncMOC performGroupedBlockAndWait:^{
        // when
        // other user joins first (calls)
        [self.syncGroupConversation.voiceChannelRouter.v2 addCallParticipant:self.syncUser1];
        
        [self.syncGroupConversation.voiceChannelRouter.v2 join];
        [self.syncGroupConversation.voiceChannelRouter.v2 addCallParticipant:self.syncSelfUser];
        
        // then
        XCTAssertFalse(self.syncGroupConversation.isOutgoingCall);
        XCTAssertEqual(self.syncGroupConversation.voiceChannel.state, VoiceChannelV2StateSelfIsJoiningActiveChannel);
    }];
}

- (void)testThatItReturns_Joining_ForAGroupConversation_WithOut_ActiveFlow_OutgoingCall
{
    [self.syncMOC performGroupedBlockAndWait:^{
        // when
        // selfuser joins first (calls)
        [self.syncGroupConversation.voiceChannelRouter.v2 join];
        
        [self.syncGroupConversation.voiceChannelRouter.v2 addCallParticipant:self.syncUser1];
        [self.syncGroupConversation.voiceChannelRouter.v2 addCallParticipant:self.syncSelfUser];
        
        // then
        XCTAssertTrue(self.syncGroupConversation.isOutgoingCall);
        XCTAssertEqual(self.syncGroupConversation.voiceChannel.state, VoiceChannelV2StateSelfIsJoiningActiveChannel);
    }];
}

- (void)testThatItResetsIsOutgoingCallWhenSecondParticipantJoins
{
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        // selfuser joins first (calls)
        [self.syncGroupConversation.voiceChannelRouter.v2 join];
        
        [self.syncGroupConversation.voiceChannelRouter.v2 addCallParticipant:self.syncUser1];
        [self.syncGroupConversation.voiceChannelRouter.v2 addCallParticipant:self.syncSelfUser];
        XCTAssertTrue(self.syncGroupConversation.isOutgoingCall);

        // when
        [self.syncGroupConversation.voiceChannelRouter.v2 updateActiveFlowParticipants:@[self.syncUser1]];
        
        // then
        XCTAssertFalse(self.syncGroupConversation.isOutgoingCall);
    }];
}


@end




@implementation VoiceChannelV2Tests (Participants)

- (void)testThatItReturnsEmptyParticipantsIfThereAreNoOtherUsers
{
    //when
    XCTAssertEqual(self.conversation.activeFlowParticipants.count, 0u);
    XCTAssertEqual(self.conversation.callParticipants.count, 0u);

    //then
    XCTAssertEqualObjects(self.conversation.voiceChannel.participants, [NSOrderedSet orderedSet]);
}


- (void)testThatItReturnsActiveFlowParticipantsIfThereAreSome
{
    // given
    [self.syncMOC performGroupedBlockAndWait:^{

        ZMConversation *conversation = (id)[self.syncMOC objectWithID:self.groupConversation.objectID];
        [conversation.mutableOtherActiveParticipants addObject:self.syncUser1];
        [conversation.mutableOtherActiveParticipants addObject:self.syncUser2];
        
        [conversation.voiceChannelRouter.v2 addCallParticipant:self.syncSelfUser];
        [conversation.voiceChannelRouter.v2 addCallParticipant:self.syncUser1];
        [conversation.voiceChannelRouter.v2 addCallParticipant:self.syncUser2];
        
        // when
        [conversation.voiceChannelRouter.v2 updateActiveFlowParticipants:@[self.syncUser1, self.syncUser2]];
        XCTAssertEqual(conversation.activeFlowParticipants.count, 2u);
        
        // then
        XCTAssertEqual(conversation.voiceChannel.participants.count, 2u);
    }];
}

@end



@implementation VoiceChannelV2Tests (ParticipantsState)

- (void)testThatItReturnsParticipantConnected
{
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMConversation *conv = (id)[self.syncMOC objectWithID:self.conversation.objectID];
        // given
        [conv.voiceChannelRouter.v2 addCallParticipant:self.syncUser1];
        [conv.voiceChannelRouter.v2 updateActiveFlowParticipants:@[self.syncUser1]];
        
        // when
        VoiceChannelV2ParticipantState *state = [conv.voiceChannelRouter.v2 stateForParticipant:self.syncUser1];
        
        // then
        XCTAssertEqual(state.connectionState, VoiceChannelV2ConnectionStateConnected);
    }];
}


- (void)testThatItReturnsParticipantConnecting
{
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMConversation *conv = (id)[self.syncMOC objectWithID:self.conversation.objectID];
        // given
        [conv.voiceChannelRouter.v2 addCallParticipant:self.syncUser1];
        conv.isFlowActive = NO;
        
        // when
        VoiceChannelV2ConnectionState state = [conv.voiceChannelRouter.v2 stateForParticipant:self.syncUser1].connectionState;
        
        // then
        XCTAssertEqual(state, VoiceChannelV2ConnectionStateConnecting);
    }];
}


- (void)testThatItReturnsParticipantNotConnected
{
    // given
    XCTAssertFalse([self.conversation.callParticipants containsObject:self.otherUser]);

    // then
    XCTAssertEqual([self.conversation.voiceChannelRouter.v2 stateForParticipant:self.otherUser].connectionState, VoiceChannelV2ConnectionStateNotConnected);
}

- (void)testThatItCanEnumerateConnectionStatesForParticipants;
{
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        [self.syncOneOnOneConversation.voiceChannelRouter.v2 addCallParticipant:self.syncUser1];
        
        XCTAssertTrue([self.syncOneOnOneConversation.callParticipants containsObject:self.syncUser1]);
        XCTAssertFalse([self.syncOneOnOneConversation.callParticipants containsObject:self.syncSelfUser]);
        
        // when
        NSMutableArray *users = [NSMutableArray array];
        [self.syncOneOnOneConversation.voiceChannelRouter.v2 enumerateParticipantStatesWithBlock:^(ZMUser *user, VoiceChannelV2ConnectionState connectionState, BOOL muted) {
            [users addObject:user];
            XCTAssertFalse(muted);
            if (user == self.syncUser1) {
                XCTAssertEqual(connectionState, VoiceChannelV2ConnectionStateConnecting);
            } else {
                XCTFail(@"Wrong user.");
            }
        }];
        
        // then
        NSArray *expectedUsers = @[self.syncUser1];
        AssertArraysContainsSameObjects(users, expectedUsers);
    }];
}

- (void)testThatItReturnsTheSelfUserConnectionStateConnected;
{
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        [self.syncOneOnOneConversation.voiceChannelRouter.v2 addCallParticipant:self.syncSelfUser];
        [self.syncOneOnOneConversation.voiceChannelRouter.v2 updateActiveFlowParticipants:@[self.syncUser1]];
        self.syncOneOnOneConversation.isFlowActive = YES;
        
        XCTAssertTrue([self.syncOneOnOneConversation.callParticipants containsObject:self.syncSelfUser]);
        XCTAssertFalse([self.syncOneOnOneConversation.callParticipants containsObject:self.syncUser1]);
        
        // then
        XCTAssertEqual(self.syncOneOnOneConversation.voiceChannelRouter.selfUserConnectionState, VoiceChannelV2ConnectionStateConnected);
    }];
   
}

- (void)testThatItReturnsTheSelfUserConnectionStateConnecting;
{
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        [self.syncOneOnOneConversation.voiceChannelRouter.v2 addCallParticipant:self.syncSelfUser];
        self.syncOneOnOneConversation.isFlowActive = NO;
        
        XCTAssertTrue([self.syncOneOnOneConversation.callParticipants containsObject:self.syncSelfUser]);
        XCTAssertFalse([self.syncOneOnOneConversation.callParticipants containsObject:self.syncUser1]);
        
        // then
        XCTAssertEqual(self.syncOneOnOneConversation.voiceChannelRouter.selfUserConnectionState, VoiceChannelV2ConnectionStateConnecting);
    }];
}

- (void)testThatItReturnsTheSelfUserConnectionStateNotConnected;
{
    // given
    XCTAssertFalse([self.conversation.callParticipants containsObject:self.selfUser]);

    // then
    XCTAssertEqual(self.conversation.voiceChannelRouter.selfUserConnectionState, VoiceChannelV2ConnectionStateNotConnected);
}

@end


@implementation VoiceChannelV2Tests (CallTimer)

- (void)testThatItTimesOutTheCallInAOneOnOneConversation_AndEndsIt
{
    ZMConversation *uiConv = (id)[self.uiMOC objectWithID:self.syncOneOnOneConversation.objectID];
    [uiConv.voiceChannelRouter.v2 join];
    NOT_USED([self.syncMOC mergeCallStateChanges:[self.uiMOC.zm_callState createCopyAndResetHasChanges]]);

    
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        [ZMCallTimer setTestCallTimeout:0.2];
        
        // when
        [self.syncOneOnOneConversation.voiceChannelRouter.v2 addCallParticipant:self.syncSelfUser];
        [self.syncGroupConversation resetHasLocalModificationsForCallDeviceIsActive]; // done by the BE, starts the timer
        XCTAssertEqual(self.syncOneOnOneConversation.voiceChannelRouter.v2.state, VoiceChannelV2StateOutgoingCall);
    }];
    
    [self spinMainQueueWithTimeout:0.5];
    
    [self.syncMOC performGroupedBlockAndWait:^{
        NOT_USED([self.syncMOC mergeCallStateChanges:self.uiMOC.zm_callState]); // callDeviceIsActive is set to NO on the uiContext, therefore need to merge changes
        [self.syncOneOnOneConversation.voiceChannelRouter.v2 removeCallParticipant:self.syncSelfUser]; // done by the BE when syncing callDeviceIsActive
        
        // then
        XCTAssertFalse(self.syncOneOnOneConversation.isOutgoingCall);
        XCTAssertFalse(self.syncOneOnOneConversation.callDeviceIsActive);
        XCTAssertTrue(self.syncOneOnOneConversation.hasLocalModificationsForCallDeviceIsActive);
        
        XCTAssertEqual(self.syncOneOnOneConversation.voiceChannelRouter.v2.state, VoiceChannelV2StateNoActiveUsers);
    }];
}


- (void)testThatItTimesOutTheCallInAGroupConversation_AndSilencesIt
{
    ZMConversation *uiConv = (id)[self.uiMOC objectWithID:self.syncGroupConversation.objectID];
    [uiConv.voiceChannelRouter.v2 join];
    NOT_USED([self.syncMOC mergeCallStateChanges:[self.uiMOC.zm_callState createCopyAndResetHasChanges]]);

    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        [ZMCallTimer setTestCallTimeout:0.2];

        // when
        [self.syncGroupConversation.voiceChannelRouter.v2 addCallParticipant:self.syncSelfUser]; // done by the BE, starts the timer
        [self.syncGroupConversation resetHasLocalModificationsForCallDeviceIsActive];
        XCTAssertEqual(self.syncGroupConversation.voiceChannelRouter.v2.state, VoiceChannelV2StateOutgoingCall);
    }];
    
    [self spinMainQueueWithTimeout:0.5];
    
    [self.syncMOC performGroupedBlockAndWait:^{
        NOT_USED([self.syncMOC mergeCallStateChanges:self.uiMOC.zm_callState]); // callTimedOut is set to YES on the uiContext, therefore need to merge changes
        
        // then
        XCTAssertTrue(self.syncGroupConversation.isOutgoingCall);
        XCTAssertTrue(self.syncGroupConversation.callDeviceIsActive);
        XCTAssertFalse(self.syncGroupConversation.hasLocalModificationsForCallDeviceIsActive);
        
        XCTAssertEqual(self.syncGroupConversation.voiceChannelRouter.v2.state, VoiceChannelV2StateOutgoingCallInactive);
    }];
}

- (void)testThatItDoesNotStartTheTimerWhenJoiningAConversationWithoutSynchingWithTheBE
{
    // given
    self.groupConversation.remoteIdentifier = NSUUID.createUUID;
    [ZMCallTimer setTestCallTimeout:0.2];
    
    // when
    [self.groupConversation.voiceChannelRouter.v2 join];
    // the BE usually adds the user to the callParticipants
    // however when the BE rejects the request, it just sets callDeviceIsActive to NO
    XCTAssertEqual(self.groupConversation.voiceChannelRouter.v2.state, VoiceChannelV2StateOutgoingCall);
    
    [self spinMainQueueWithTimeout:0.5];
    
    // then
    XCTAssertTrue(self.groupConversation.isOutgoingCall);
    XCTAssertEqual(self.groupConversation.voiceChannelRouter.v2.state, VoiceChannelV2StateOutgoingCall);
}

- (void)testThatItCancelsAStartedTimerIfThereAreNoCallParticipantsInAnOutgoingCall
{
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        [ZMCallTimer setTestCallTimeout:0.2];
        
        // (1) when selfUser joins
        [self.syncGroupConversation.voiceChannelRouter.v2 join]; // this does not start the timer
        [self.syncGroupConversation.voiceChannelRouter.v2 addCallParticipant:self.syncSelfUser]; // this starts the timer
        XCTAssertEqual(self.syncGroupConversation.voiceChannelRouter.v2.state, VoiceChannelV2StateOutgoingCall);
        
        // (2) the other user joins, the timer stops
        [self.syncGroupConversation.voiceChannelRouter.v2 addCallParticipant:self.syncUser1]; // this stops the timer
        XCTAssertEqual(self.syncGroupConversation.voiceChannelRouter.v2.state, VoiceChannelV2StateSelfIsJoiningActiveChannel);
        
        // (3) both users leave
        // the callstate transcoder removes them one after another
        [self.syncGroupConversation.voiceChannelRouter.v2 removeCallParticipant:self.syncUser1]; // this will start the timer
        XCTAssertEqual(self.syncGroupConversation.voiceChannelRouter.v2.state, VoiceChannelV2StateOutgoingCall);
        
        [self.syncGroupConversation.voiceChannelRouter.v2 removeCallParticipant:self.syncSelfUser]; // this should stop the timer
        XCTAssertEqual(self.syncGroupConversation.voiceChannelRouter.v2.state, VoiceChannelV2StateOutgoingCall);
        
        // (4) the call state transcoder will set callDeviceIsActive to NO for disconnected events that don't contain a self info
        self.syncGroupConversation.callDeviceIsActive = NO;
        XCTAssertEqual(self.syncGroupConversation.voiceChannelRouter.v2.state, VoiceChannelV2StateNoActiveUsers);
        
        // (5) if the timer wasn't cancelled before, it would fire now
        [self spinMainQueueWithTimeout:0.5];
        
        // (6) we initiate a new call, if the timer was fired, we would be in timedOut state (OutgoingCallInactive)
        [self.syncGroupConversation.voiceChannelRouter.v2 join];
        [self.syncGroupConversation.voiceChannelRouter.v2 addCallParticipant:self.syncSelfUser];
        
        // then
        XCTAssertTrue(self.syncGroupConversation.isOutgoingCall);
        XCTAssertEqual(self.syncGroupConversation.voiceChannelRouter.v2.state, VoiceChannelV2StateOutgoingCall);
    }];
}

- (void)testThatItSetsDidTimeOutWhenTheTimerFires_GroupCall
{
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMConversation *conversation = self.syncGroupConversation;
        conversation.callTimedOut = NO;
        NOT_USED([self.uiMOC mergeCallStateChanges:[self.syncMOC.zm_callState createCopyAndResetHasChanges]]);
        
        XCTAssertFalse(conversation.callTimedOut);

        [ZMCallTimer setTestCallTimeout:0.2];
        
        // when
        [self.syncMOC zm_addAndStartCallTimer:conversation];
    }];
    
    [self spinMainQueueWithTimeout:0.5];
    
    [self.syncMOC performGroupedBlockAndWait:^{
        NOT_USED([self.syncMOC mergeCallStateChanges:[self.uiMOC.zm_callState createCopyAndResetHasChanges]]);
        
        // then
        XCTAssertTrue(self.syncGroupConversation.callTimedOut);
    }];
}

- (void)testThatItSetsDidTimeOutWhenTheTimerFires_OneOnOneIncoming
{
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMConversation *conversation = self.syncOneOnOneConversation;
        conversation.callTimedOut = NO;
        conversation.isOutgoingCall = NO;
        NOT_USED([self.uiMOC mergeCallStateChanges:[self.syncMOC.zm_callState createCopyAndResetHasChanges]]);
        
        XCTAssertFalse(conversation.callTimedOut);
        
        [ZMCallTimer setTestCallTimeout:0.2];
        
        // when
        [self.syncMOC zm_addAndStartCallTimer:conversation];
    }];
    
    [self spinMainQueueWithTimeout:0.5];
    
    [self.syncMOC performGroupedBlockAndWait:^{
        NOT_USED([self.syncMOC mergeCallStateChanges:[self.uiMOC.zm_callState createCopyAndResetHasChanges]]);
        
        // then
        XCTAssertTrue(self.syncOneOnOneConversation.callTimedOut);
    }];
}

- (void)testThatItDoesNotSetDidTimeOutWhenTheTimerFires_OneOnOneOutGoing
{
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMConversation *conversation = self.syncOneOnOneConversation;
        conversation.callTimedOut = NO;
        conversation.isOutgoingCall = YES;
        NOT_USED([self.uiMOC mergeCallStateChanges:[self.syncMOC.zm_callState createCopyAndResetHasChanges]]);
        
        XCTAssertFalse(conversation.callTimedOut);
        
        [ZMCallTimer setTestCallTimeout:0.2];
        
        // when
        [self.syncMOC zm_addAndStartCallTimer:conversation];
        [self spinMainQueueWithTimeout:0.5];
        
        NOT_USED([self.syncMOC mergeCallStateChanges:[self.uiMOC.zm_callState createCopyAndResetHasChanges]]);
        
        // then
        XCTAssertFalse(conversation.callTimedOut);
    }];
}

- (void)testThatItReSetsDidTimeOutWhenRemovingAllCallParticipants
{
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMConversation *conversation = self.syncGroupConversation;
        [self.syncGroupConversation.voiceChannelRouter.v2 addCallParticipant:self.syncUser1];
        [self.syncGroupConversation.voiceChannelRouter.v2 addCallParticipant:self.syncUser2];
        [self.syncGroupConversation.voiceChannelRouter.v2 addCallParticipant:self.syncUser3];
        
        conversation.callTimedOut = YES;
        
        // when
        [conversation.voiceChannelRouter.v2 removeAllCallParticipants];
        
        // then
        XCTAssertFalse(conversation.callTimedOut);
    }];
}

- (void)testThatItReSetsDidTimeOutWhenRemovingTheLastCallParticipants
{
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMConversation *conversation = self.syncGroupConversation;
        [self.syncGroupConversation.voiceChannelRouter.v2 addCallParticipant:self.syncUser1];
        [self.syncGroupConversation.voiceChannelRouter.v2 addCallParticipant:self.syncUser2];
        [self.syncGroupConversation.voiceChannelRouter.v2 addCallParticipant:self.syncUser3];
        
        conversation.callTimedOut = YES;
        
        // when
        [conversation.voiceChannelRouter.v2 removeCallParticipant:self.syncUser1];
        [conversation.voiceChannelRouter.v2 removeCallParticipant:self.syncUser2];

        // then
        XCTAssertTrue(conversation.callTimedOut);
        
        // when
        [conversation.voiceChannelRouter.v2 removeCallParticipant:self.syncUser3];
        
        // then
        XCTAssertFalse(conversation.callTimedOut);
    }];
}

@end



@implementation VoiceChannelV2Tests (JoinAndLeave)

- (void)testThatWhenJoiningTheVoiceChannel_callDeviceIsActive_isSet
{
    // given
    XCTAssertFalse(self.conversation.callDeviceIsActive);
    
    // when
    [self.conversation.voiceChannelRouter.v2 join];
    
    // then
    XCTAssertTrue(self.conversation.callDeviceIsActive);
    
}

- (void)testThatWhenLeavingTheVoiceChannel_callDeviceIsActive_isUnset
{
    [self.syncMOC performGroupedBlockAndWait:^{
        
        // given
        [self.syncOneOnOneConversation.voiceChannelRouter.v2 addCallParticipant:self.syncSelfUser];
        self.syncOneOnOneConversation.callDeviceIsActive = YES;
        XCTAssertTrue([self.syncOneOnOneConversation.callParticipants containsObject:self.syncSelfUser]);
        
        // when
        [self.syncOneOnOneConversation.voiceChannelRouter.v2 leave];
        
        // then
        XCTAssertFalse(self.syncOneOnOneConversation.callDeviceIsActive);
    }];
}

- (void)testThatWhenLeavingTheVoiceChannel_reasonToLeave_isSet
{
    [self.syncMOC performGroupedBlockAndWait:^{
        
        // given
        [self.syncOneOnOneConversation.voiceChannelRouter.v2 addCallParticipant:self.syncSelfUser];
        self.syncOneOnOneConversation.callDeviceIsActive = YES;
        self.syncOneOnOneConversation.reasonToLeave = ZMCallStateReasonToLeaveNone;
        XCTAssertTrue([self.syncOneOnOneConversation.callParticipants containsObject:self.syncSelfUser]);
        
        // when
        [self.syncOneOnOneConversation.voiceChannelRouter.v2 leave];
        
        // then
        XCTAssertEqual(self.syncOneOnOneConversation.reasonToLeave, ZMCallStateReasonToLeaveUser);
    }];
}

- (void)testThatWhenLeavingTheVoiceChannelOnAVSError_reasonToLeave_isSet
{
    [self.syncMOC performGroupedBlockAndWait:^{
        
        // given
        [self.syncOneOnOneConversation.voiceChannelRouter.v2 addCallParticipant:self.syncSelfUser];
        self.syncOneOnOneConversation.callDeviceIsActive = YES;
        self.syncOneOnOneConversation.reasonToLeave = ZMCallStateReasonToLeaveNone;
        XCTAssertTrue([self.syncOneOnOneConversation.callParticipants containsObject:self.syncSelfUser]);
        
        // when
        [self.syncOneOnOneConversation.voiceChannelRouter.v2 leaveOnAVSError];
        
        // then
        XCTAssertEqual(self.syncOneOnOneConversation.reasonToLeave, ZMCallStateReasonToLeaveAvsError);
    }];
}

- (void)testThatLeavingTheVoiceChannelWithoutLeavingTheConversation_DoesNotReset_IsIgnoringCall_TwoParticipantsLeft
{
    [self.syncMOC performGroupedBlockAndWait:^{
        // given

        self.syncGroupConversation.callDeviceIsActive = YES;
        
        [self.syncGroupConversation.voiceChannelRouter.v2 addCallParticipant:self.syncSelfUser];
        [self.syncGroupConversation.voiceChannelRouter.v2 addCallParticipant:self.syncUser1];
        [self.syncGroupConversation.voiceChannelRouter.v2 addCallParticipant:self.syncUser2];

        XCTAssertFalse(self.syncGroupConversation.isIgnoringCall);
        XCTAssertEqual(self.syncGroupConversation.voiceChannelRouter.v2.state, VoiceChannelV2StateSelfIsJoiningActiveChannel);
        
        // when
        [self.syncGroupConversation.voiceChannelRouter.v2 leave];
        
        // then
        XCTAssertTrue(self.syncGroupConversation.isIgnoringCall);
    }];
}

- (void)testThatLeavingTheVoiceChannelWithoutLeavingTheConversation_DoesNotReset_IsIgnoringCall_OneParticipantsLeft
{
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        
        self.syncGroupConversation.callDeviceIsActive = YES;
        
        [self.syncGroupConversation.voiceChannelRouter.v2 addCallParticipant:self.syncSelfUser];
        [self.syncGroupConversation.voiceChannelRouter.v2 addCallParticipant:self.syncUser1];
        
        XCTAssertFalse(self.syncGroupConversation.isIgnoringCall);
        XCTAssertEqual(self.syncGroupConversation.voiceChannelRouter.v2.state, VoiceChannelV2StateSelfIsJoiningActiveChannel);
        
        // when
        [self.syncGroupConversation.voiceChannelRouter.v2 leave];
        
        // then
        XCTAssertFalse(self.syncGroupConversation.isIgnoringCall);
    }];
}

- (void)testThatTheVoiceChannelReturnsStateNoActiveUsersAfterLeavingTheConversation
{
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        self.syncGroupConversation.callDeviceIsActive = YES;
        
        [self.syncGroupConversation.voiceChannelRouter.v2 addCallParticipant:self.syncSelfUser];
        [self.syncGroupConversation.voiceChannelRouter.v2 addCallParticipant:self.syncUser1];
        
        XCTAssertFalse(self.syncGroupConversation.isIgnoringCall);
        XCTAssertEqual(self.syncGroupConversation.voiceChannelRouter.v2.state, VoiceChannelV2StateSelfIsJoiningActiveChannel);
        [self.syncMOC saveOrRollback];
        NOT_USED([self.uiMOC mergeCallStateChanges:[self.syncMOC.zm_callState createCopyAndResetHasChanges]]);
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    ZMConversation *uiConv = (id)[self.uiMOC objectWithID:self.syncGroupConversation.objectID];
    [self.uiMOC refreshObject:uiConv mergeChanges:NO];

    XCTAssertEqual(uiConv.voiceChannelRouter.v2.state, VoiceChannelV2StateSelfIsJoiningActiveChannel);

    // when
    [uiConv.voiceChannelRouter.v2 leave];
    [uiConv removeParticipant:self.selfUser];
    
    [self.syncMOC performGroupedBlockAndWait:^{
        // this step is done by the transcoder
        [self.syncGroupConversation.voiceChannelRouter.v2 removeAllCallParticipants];
        [self.syncMOC saveOrRollback];
    }];
    [self.uiMOC refreshObject:uiConv mergeChanges:YES];

    // then
    XCTAssertEqual(uiConv.voiceChannelRouter.v2.state, VoiceChannelV2StateNoActiveUsers);
}


- (void)testThatWhenCancellingAnOutgoingCallTheCallParticipantsAreReset
{
    ZMConversation *uiConv = (id)[self.uiMOC objectWithID:self.syncGroupConversation.objectID];
    [uiConv.voiceChannelRouter.v2 join];
    NOT_USED([self.syncMOC mergeCallStateChanges:[self.uiMOC.zm_callState createCopyAndResetHasChanges]]);
    
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        [self.syncGroupConversation.voiceChannelRouter.v2 addCallParticipant:self.syncSelfUser];
        XCTAssertTrue([self.syncGroupConversation.callParticipants containsObject:self.syncSelfUser]);
        XCTAssertFalse(self.syncGroupConversation.isIgnoringCall);
        XCTAssertEqual(self.syncGroupConversation.voiceChannelRouter.v2.state, VoiceChannelV2StateOutgoingCall);
        [self.syncMOC saveOrRollback];
        NOT_USED([self.uiMOC mergeCallStateChanges:[self.syncMOC.zm_callState createCopyAndResetHasChanges]]);
    }];
    [self.uiMOC refreshObject:uiConv mergeChanges:YES];

    
    // when
    [uiConv.voiceChannelRouter.v2 leave];
    
    // then
    XCTAssertEqual(uiConv.voiceChannelRouter.v2.state, VoiceChannelV2StateNoActiveUsers); // this is an intermediate state
    XCTAssertFalse(uiConv.isIgnoringCall);
}

- (void)testThatItSets_IsOutgoingCall_JoiningAVoiceChannelOnAOneOnOneConversationWithoutCallParticipants
{
    // when
    [self.conversation.voiceChannelRouter.v2 join];
    
    // then
    XCTAssertTrue(self.conversation.isOutgoingCall);
}

- (void)testThatWeDoNotSetIsOutgoingCallWhenThereAreAlreadyUsersInTheVoiceChannel
{
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        [self.syncOneOnOneConversation.voiceChannelRouter.v2 addCallParticipant:self.syncUser1];
        
        // when
        [self.syncOneOnOneConversation.voiceChannelRouter.v2 join];
        
        // then
        XCTAssertFalse(self.syncOneOnOneConversation.isOutgoingCall);
    }];
}

- (void)testThatItResetsIsOutgoingCallWhenLeavingAVoiceChannel
{
    // given
    [self.conversation.voiceChannelRouter.v2 join];
    XCTAssertTrue(self.conversation.isOutgoingCall);
    
    // when
    [self.conversation.voiceChannelRouter.v2 leave];
    
    // then
    XCTAssertFalse(self.conversation.isOutgoingCall);
}


- (void)testThatItResetsAndRecalculates_IsOutgoingCall_WhenJoiningAVoiceChannelWithPreviousOutgoingCall
{
    // given
    
    // the selfuser calls first
    [self.conversation.voiceChannelRouter.v2 join];
    [self.uiMOC saveOrRollback];
    NOT_USED([self.syncMOC mergeCallStateChanges:self.uiMOC.zm_callState.createCopyAndResetHasChanges]);
    XCTAssertTrue(self.conversation.isOutgoingCall);

    // the BE returns and other users join
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMConversation *syncConv = (id)[self.syncMOC objectWithID:self.conversation.objectID];
        [syncConv.voiceChannelRouter.v2 addCallParticipant:self.selfUser];
        [syncConv.voiceChannelRouter.v2 addCallParticipant:self.syncUser1];
        [syncConv.voiceChannelRouter.v2 addCallParticipant:self.syncUser2];
        [self.syncMOC saveOrRollback];
    }];
    NOT_USED([self.uiMOC mergeCallStateChanges:self.syncMOC.zm_callState.createCopyAndResetHasChanges]);
    XCTAssertTrue(self.conversation.isOutgoingCall);

    // (1) when the BE force idles the call
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMConversation *syncConv = (id)[self.syncMOC objectWithID:self.conversation.objectID];
        [syncConv.voiceChannelRouter.v2 removeCallParticipant:self.syncUser1];
        [syncConv.voiceChannelRouter.v2 removeCallParticipant:self.syncUser2];
        [syncConv.voiceChannelRouter.v2 removeCallParticipant:self.selfUser];
        [self.syncMOC saveOrRollback];
    }];
    NOT_USED([self.uiMOC mergeCallStateChanges:self.syncMOC.zm_callState.createCopyAndResetHasChanges]);
    
    // then
    // we reset isOutgoingCall
    XCTAssertFalse(self.conversation.isOutgoingCall);

    // (2) when the other user calls first
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMConversation *syncConv = (id)[self.syncMOC objectWithID:self.conversation.objectID];
        [syncConv.voiceChannelRouter.v2 addCallParticipant:self.syncUser1];
        [self.syncMOC saveOrRollback];
    }];
    [self.uiMOC refreshObject:self.conversation mergeChanges:NO];
    NOT_USED([self.uiMOC mergeCallStateChanges:self.syncMOC.zm_callState.createCopyAndResetHasChanges]);

    [self.conversation.voiceChannelRouter.v2 join];
    
    // then
    XCTAssertFalse(self.conversation.isOutgoingCall);
}

@end


@implementation VoiceChannelV2Tests (GSMCalls)

- (void)testThatItSendsANotificationWhenThereIsAnOngoingGSMCall_AndDoesNotJoinTheVoiceChannel
{
    // given
    id call = [OCMockObject niceMockForClass:[CTCall class]];
    [(CTCall *)[[call expect] andReturn:CTCallStateConnected] callState];
    id callCenter = [OCMockObject niceMockForClass:[CTCallCenter class]];
    
    VoiceChannelV2 *voiceChannel = [[VoiceChannelV2 alloc] initWithConversation:self.conversation callCenter:callCenter];
    id token = [self.conversation.voiceChannelRouter.v2 addCallingInitializationObserver:self];
    // expect
    [[[callCenter expect] andReturn:[NSSet setWithObject:call]] currentCalls];
    
    // when
    [voiceChannel join];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(self.receivedErrors.count, 1u);
    NSError *receivedError = self.receivedErrors.firstObject;
    if (receivedError != nil) {
        XCTAssertEqual(receivedError.code, (long)VoiceChannelV2ErrorCodeOngoingGSMCall);
    }
    XCTAssertFalse(self.conversation.callDeviceIsActive);
    [self.conversation.voiceChannelRouter.v2 removeCallingInitialisationObserver:token];
}

- (void)testThatItDoesNotSendANotificationWhenThereIsAIncomingGSMCall_AndDoesNotJoinTheVoiceChannel
{
    // given
    id token = [self.conversation.voiceChannelRouter.v2 addCallingInitializationObserver:self];
    id call1 = [OCMockObject niceMockForClass:[CTCall class]];
    [(CTCall *)[[call1 expect] andReturn:CTCallStateIncoming] callState];
    id call2 = [OCMockObject niceMockForClass:[CTCall class]];
    [(CTCall *)[[call2 expect] andReturn:CTCallStateDisconnected] callState];
    id call3 = [OCMockObject niceMockForClass:[CTCall class]];
    [(CTCall *)[[call3 expect] andReturn:CTCallStateDialing] callState];
    
    id callCenter = [OCMockObject niceMockForClass:[CTCallCenter class]];
    
    VoiceChannelV2 *voiceChannel = [[VoiceChannelV2 alloc] initWithConversation:self.conversation callCenter:callCenter];
    
    // expect
    [[[callCenter expect] andReturn:[NSSet setWithObjects:call1,call2, call3, nil]] currentCalls];

    // when
    [voiceChannel join];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(self.receivedErrors.count, 0u);
    XCTAssertTrue(self.conversation.callDeviceIsActive);
    [self.conversation.voiceChannelRouter.v2 removeCallingInitialisationObserver:token];
}



- (void)testThatItDoesNotSendANotificationWhenThereIsNoGSMCall_AndJoinsTheVoiceChannel
{
    // given
    id token = [self.conversation.voiceChannelRouter.v2 addCallingInitializationObserver:self];
    id callCenter = [OCMockObject niceMockForClass:[CTCallCenter class]];
    VoiceChannelV2 *voiceChannel = [[VoiceChannelV2 alloc] initWithConversation:self.groupConversation callCenter:callCenter];
    
    // expect
    [[[callCenter expect] andReturn:[NSSet set]] currentCalls];
    
    // when
    [voiceChannel join];
    
    // then
    XCTAssertEqual(self.receivedErrors.count, 0u);
    XCTAssertTrue(self.groupConversation.callDeviceIsActive);
    [self.conversation.voiceChannelRouter.v2 removeCallingInitialisationObserver:token];
}

@end



@implementation VoiceChannelV2Tests (Notifications)

- (void)testThatItPostsShouldKeepWebsocketOpenNotificationOnJoin
{
    //given
    __block BOOL selfJoined = NO;
    id observer = [[NSNotificationCenter defaultCenter] addObserverForName:ZMTransportSessionShouldKeepWebsocketOpenNotificationName object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
        selfJoined = [note.userInfo[ZMTransportSessionShouldKeepWebsocketOpenKey] boolValue];
    }];
    
    //when
    [self.conversation.voiceChannelRouter.v2 join];
    WaitForAllGroupsToBeEmpty(0.5);

    //then
    XCTAssertTrue(selfJoined);
    
    [[NSNotificationCenter defaultCenter] removeObserver:observer];
}

- (void)testThatItPostsShouldKeepWebsocketOpenNotificationOnLeave
{
    //given
    [self.conversation.voiceChannelRouter.v2 join];
    __block BOOL selfJoined = YES;
    
    id observer = [[NSNotificationCenter defaultCenter] addObserverForName:ZMTransportSessionShouldKeepWebsocketOpenNotificationName object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
        selfJoined = [note.userInfo[ZMTransportSessionShouldKeepWebsocketOpenKey] boolValue];
    }];
    
    //when
    [self.conversation.voiceChannelRouter.v2 leave];
    
    //then
    XCTAssertFalse(selfJoined);
    
    [[NSNotificationCenter defaultCenter] removeObserver:observer];
}

- (void)testThatItPostsShouldKeepWebsocketOpenNotificationOnRemoveCallParticipantIfParticipantIsSelf
{
    //given
    [self.conversation.voiceChannelRouter.v2 join];
    WaitForAllGroupsToBeEmpty(0.5);

    __block BOOL selfJoined = YES;
    
    id observer = [[NSNotificationCenter defaultCenter] addObserverForName:ZMTransportSessionShouldKeepWebsocketOpenNotificationName object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
        selfJoined = [note.userInfo[ZMTransportSessionShouldKeepWebsocketOpenKey] boolValue];
    }];
    
    //when
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMConversation *syncConv = (id)[self.syncMOC objectWithID:self.conversation.objectID];
        ZMUser *syncSelfUser = (id)[self.syncMOC objectWithID:self.selfUser.objectID];
        [syncConv.voiceChannelRouter.v2 removeCallParticipant:syncSelfUser];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    //then
    XCTAssertFalse(selfJoined);
    
    [[NSNotificationCenter defaultCenter] removeObserver:observer];
}

- (void)testThatItDoesNotPostShouldKeepWebsocketOpenNotificationOnRemoveCallParticipantIfParticipnatIsNotSelf
{
    //given
    [self.conversation.voiceChannelRouter.v2 join];
    WaitForAllGroupsToBeEmpty(0.5);

    __block BOOL selfJoined = YES;
    
    __block BOOL notificationPosted = NO;
    id observer = [[NSNotificationCenter defaultCenter] addObserverForName:ZMTransportSessionShouldKeepWebsocketOpenNotificationName object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
        selfJoined = [note.userInfo[ZMTransportSessionShouldKeepWebsocketOpenKey] boolValue];
        notificationPosted = YES;
    }];
    
    //when
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMConversation *syncConv = (id)[self.syncMOC objectWithID:self.conversation.objectID];
        ZMUser *syncOtherUser = (id)[self.syncMOC objectWithID:self.otherUser.objectID];
        [syncConv.voiceChannelRouter.v2 removeCallParticipant:syncOtherUser];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    //then
    XCTAssertTrue(selfJoined);
    XCTAssertFalse(notificationPosted);
    
    [[NSNotificationCenter defaultCenter] removeObserver:observer];
}

@end
