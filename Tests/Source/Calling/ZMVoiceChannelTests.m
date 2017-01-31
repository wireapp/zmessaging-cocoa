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
@import ZMTesting;
@import ZMCDataModel;

#import "ZMVoiceChannelTests.h"
#import "ZMFlowSync.h"
#import "ZMUserSession.h"
#import "ZMAVSBridge.h"

#if TARGET_OS_IPHONE
@import CoreTelephony;
#endif

@interface ZMVoiceChannelTestsWithDiscStore : MessagingTest
@end


@implementation ZMVoiceChannelTestsWithDiscStore

- (BOOL)shouldUseInMemoryStore;
{
    return NO;
}

- (void)tearDownVoiceChannelForSyncConversation:(ZMConversation *)conversation
{
    ZMConversation *uiConv = (id)[self.uiMOC objectWithID:conversation.objectID];
    [uiConv.voiceChannel tearDown];
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




@implementation ZMVoiceChannelTests

- (void)setUp
{
    [super setUp];

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
    
    self.groupConversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    self.groupConversation.conversationType = ZMConversationTypeGroup;
    
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
        [self.syncMOC saveOrRollback];
    }];
}

- (void)tearDown
{
    WaitForAllGroupsToBeEmpty(0.5);
    [ZMCallTimer resetTestCallTimeout];
    
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


- (void)testThatItReturnsAVoiceChannelForAOneOnOneConversations;
{
    // when
    ZMVoiceChannel *channel = self.conversation.voiceChannel;

    // then
    XCTAssertNotNil(channel);
    ZMConversation *c = channel.conversation;
    XCTAssertEqual(c, self.conversation);
}

- (void)testThatItAlwaysReturnsTheSameVoiceChannelForAOneOnOneConversations;
{
    // when
    ZMVoiceChannel *channel = self.conversation.voiceChannel;

    XCTAssertEqual(self.conversation.voiceChannel, channel);
}

- (void)testThatItReturnsAVoiceChannelForAGroupConversation;
{
    // when
    ZMVoiceChannel *channel = self.groupConversation.voiceChannel;

    XCTAssertNotNil(channel);
}

@end



@implementation ZMVoiceChannelTests (DebugInformation)

- (void)testThatItCanFormatEmptyInformation;
{
    // given
    [ZMVoiceChannel setLastSessionIdentifier:nil];
    [ZMVoiceChannel setLastSessionStartDate:nil];
    id userSession = [OCMockObject niceMockForClass:ZMUserSession.class];
    [[[userSession stub] andReturn:self.uiMOC] managedObjectContext];

    // when
    NSAttributedString *s = [ZMVoiceChannel voiceChannelDebugInformation];

    // then
    XCTAssertEqualObjects(s.string, @"Session ID: \nSession start date: \nSession start date (GMT): \n");
}

- (void)testThatItCanFormatInformation;
{
    // given
    [ZMVoiceChannel setLastSessionIdentifier:@"test-session-ID"];
    [ZMVoiceChannel setLastSessionStartDate:[NSDate dateWithTimeIntervalSinceReferenceDate:448206432.09855801]];
    id userSession = [OCMockObject niceMockForClass:ZMUserSession.class];
    [[[userSession stub] andReturn:self.uiMOC] managedObjectContext];

    // when
    NSAttributedString *s = [ZMVoiceChannel voiceChannelDebugInformation];

    // then
    NSArray *lines = [s.string componentsSeparatedByString:@"\n"];
    NSString *first = lines.firstObject;
    NSString *third = (lines.count >= 3) ? lines[2] : nil;
    XCTAssertEqualObjects(first, @"Session ID: test-session-ID");
    XCTAssertEqualObjects(third, @"Session start date (GMT): March 16, 2015 at 1:47:12 PM GMT");
}

@end



@implementation ZMVoiceChannelTests (VoiceChannelState)

- (void)testThatItReturnsNoActiveUsersForTheState;
{
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        [self.syncOneOnOneConversation.voiceChannel removeAllCallParticipants];
        
        // then
        XCTAssertEqual(self.syncOneOnOneConversation.voiceChannel.state, ZMVoiceChannelStateNoActiveUsers);
    }];
}

- (void)testThatItReturnsNoActiveUsersForNewConversation;
{
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        [self.syncGroupConversation.voiceChannel removeAllCallParticipants];
        self.syncGroupConversation.isIgnoringCall = YES;
        
        // then
        XCTAssertEqual(self.syncGroupConversation.voiceChannel.state, ZMVoiceChannelStateNoActiveUsers);
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
    XCTAssertEqual(self.conversation.voiceChannel.state, ZMVoiceChannelStateNoActiveUsers);
}



- (void)testThatItReturnsSelfIsCallingForTheStateWhenSelfIsJoinedButNoMediaIsFlowing
{
    [self.syncMOC performGroupedBlockAndWait:^{
        
        // given
        [self.syncOneOnOneConversation.voiceChannel addCallParticipant:self.syncSelfUser];
        XCTAssertFalse([self.syncOneOnOneConversation.callParticipants containsObject:self.syncUser1]);
        
        self.syncOneOnOneConversation.isFlowActive = NO;
        self.syncOneOnOneConversation.callDeviceIsActive = YES;
        
        // then
        XCTAssertEqual(self.syncOneOnOneConversation.voiceChannel.state, ZMVoiceChannelStateOutgoingCall);
    }];
}

- (void)testThatItReturnsOtherUserIsCallingForTheStateWhenSelfIsNotJoinedAndOtherUsersAreJoined
{
    [self.syncMOC performGroupedBlockAndWait:^{
        
        // given
        XCTAssertFalse([self.syncOneOnOneConversation.callParticipants containsObject:self.syncSelfUser]);
        [self.syncOneOnOneConversation.voiceChannel addCallParticipant:self.syncUser1];
        
        self.syncOneOnOneConversation.isFlowActive = NO;
        self.syncOneOnOneConversation.callDeviceIsActive = NO;
        
        // then
        XCTAssertEqual(self.syncOneOnOneConversation.voiceChannel.state, ZMVoiceChannelStateIncomingCall);
    }];
}

- (void)testThatItReturnsSelfIfJoiningForTheStateWhenThesyncUser1IsConnectedAndSelfIsConnecting
{
    [self.syncMOC performGroupedBlockAndWait:^{
        
        // given
        [self.syncOneOnOneConversation.voiceChannel addCallParticipant:self.syncSelfUser];
        [self.syncOneOnOneConversation.voiceChannel addCallParticipant:self.syncUser1];
        
        self.syncOneOnOneConversation.isFlowActive = NO;
        self.syncOneOnOneConversation.callDeviceIsActive = YES;
        
        // then
        XCTAssertEqual(self.syncOneOnOneConversation.voiceChannel.state, ZMVoiceChannelStateSelfIsJoiningActiveChannel);
    }];
}

- (void)testThatItReturnsSelfConnectedForTheStateWhenBothUsersAreConnectedAndTheFlowCategoryIsCall
{
    [self.syncMOC performGroupedBlockAndWait:^{
        
        // given
        [self.syncOneOnOneConversation.voiceChannel addCallParticipant:self.syncSelfUser];
        [self.syncOneOnOneConversation.voiceChannel addCallParticipant:self.syncUser1];
        
        [self.syncOneOnOneConversation.voiceChannel updateActiveFlowParticipants:@[self.syncUser1]];
        self.syncOneOnOneConversation.callDeviceIsActive = YES;
        self.syncOneOnOneConversation.isFlowActive = YES;
        
        // then
        XCTAssertEqual(self.syncOneOnOneConversation.voiceChannel.state, ZMVoiceChannelStateSelfConnectedToActiveChannel);
    }];
}

- (void)testThatItReturnsTransferReadyForTheStateWhenBothUsersAreConnectedButThisDeviceIsNotActive
{
    [self.syncMOC performGroupedBlockAndWait:^{
        
        // given
        [self.syncOneOnOneConversation.voiceChannel addCallParticipant:self.syncSelfUser];
        [self.syncOneOnOneConversation.voiceChannel addCallParticipant:self.syncUser1];
        
        [self.uiMOC saveOrRollback];
        
        self.syncOneOnOneConversation.isFlowActive = NO;
        self.syncOneOnOneConversation.callDeviceIsActive = NO;
        
        // then
        XCTAssertEqual(self.syncOneOnOneConversation.voiceChannel.state, ZMVoiceChannelStateDeviceTransferReady);
    }];
}

- (void)testThatItReturnsTransferReadyForTheStateWhenWhenWeAreCallingFromAnotherDevice
{
    [self.syncMOC performGroupedBlockAndWait:^{
        
        // given
        [self.syncOneOnOneConversation.voiceChannel addCallParticipant:self.syncSelfUser];
        XCTAssertFalse([self.syncOneOnOneConversation.callParticipants containsObject:self.syncUser1]);
        
        self.syncOneOnOneConversation.isFlowActive = NO;
        self.syncOneOnOneConversation.callDeviceIsActive = NO;
        
        // then
        XCTAssertEqual(self.syncOneOnOneConversation.voiceChannel.state, ZMVoiceChannelStateDeviceTransferReady);
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
        [self.syncOneOnOneConversation.voiceChannel addCallParticipant:self.syncUser1];
        
        // then
        XCTAssertEqual(self.syncOneOnOneConversation.voiceChannel.participants.firstObject, self.syncUser1);
    }];
}


- (void)testThatItReturnsNoActiveUserWhenIgnoring_OneOnOneConversation
{
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        [self.syncOneOnOneConversation.voiceChannel addCallParticipant:self.syncUser1];
        XCTAssertFalse([self.syncOneOnOneConversation.callParticipants containsObject:self.syncSelfUser]);
        XCTAssertTrue([self.syncOneOnOneConversation.callParticipants containsObject:self.syncUser1]);
        
        self.syncOneOnOneConversation.isFlowActive = NO;
        self.syncOneOnOneConversation.callDeviceIsActive = NO;
        self.syncOneOnOneConversation.isIgnoringCall = YES;
        
        // then
        XCTAssertEqual(self.syncOneOnOneConversation.voiceChannel.state, ZMVoiceChannelStateNoActiveUsers);
    }];
}

- (void)testThatItSetsIgnoringCall
{
    // when
    [self.conversation.voiceChannel ignoreIncomingCall];
    
    // then
    XCTAssertTrue(self.conversation.isIgnoringCall);
}

- (void)testThatItReturnsNoOtherConversationWithActiveCallIfThereIsNoCalls
{
    // given
    XCTAssertEqual(self.otherConversation.callParticipants.count, 0u);
    XCTAssertEqual(self.conversation.callParticipants.count, 0u);
    
    // when
    ZMConversation *fetchedConversation = self.otherConversation.firstOtherConversationWithActiveCall;
    
    // then
    XCTAssertNil(fetchedConversation);
}

- (void)testThatItReturnsOtherConversationWithActiveCallWithOtherUserCallParticipant
{
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMConversation *firstCall = self.syncOneOnOneConversation;
        ZMConversation *secondCall = self.syncGroupConversation;
        
        // given
        [firstCall.voiceChannel addCallParticipant:self.syncUser1];
        XCTAssertEqual(firstCall.voiceChannelState, ZMVoiceChannelStateIncomingCall);
        
        [secondCall.voiceChannel addCallParticipant:self.syncUser1];
        XCTAssertEqual(secondCall.voiceChannelState, ZMVoiceChannelStateIncomingCall);
        
        // when
        ZMConversation *fetchedConversation = firstCall.firstOtherConversationWithActiveCall;
        
        // then
        XCTAssertEqual(fetchedConversation, secondCall);
    }];
}

- (void)testThatItReturnsOtherConversationWithActiveCallWithSelfUserCallParticipant
{
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMConversation *firstCall = self.syncOneOnOneConversation;
        ZMConversation *secondCall = self.syncGroupConversation;
        
        // given
        [firstCall.voiceChannel addCallParticipant:self.syncSelfUser];
        firstCall.callDeviceIsActive = YES;
        XCTAssertEqual(firstCall.voiceChannelState, ZMVoiceChannelStateOutgoingCall);
        
        [secondCall.voiceChannel addCallParticipant:self.syncSelfUser];
        secondCall.callDeviceIsActive = YES;
        XCTAssertEqual(secondCall.voiceChannelState, ZMVoiceChannelStateOutgoingCall);
        
        // when
        ZMConversation *fetchedConversation = firstCall.firstOtherConversationWithActiveCall;
        
        // then
        XCTAssertEqual(fetchedConversation, secondCall);
    }];
}

- (void)testThatItReturnsNoOtherConversationWithActiveCallIfOneIsIgnored
{
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMConversation *firstCall = self.syncOneOnOneConversation;
        ZMConversation *secondCall = self.syncGroupConversation;
        
        // given
        [firstCall.voiceChannel addCallParticipant:self.syncUser1];
        XCTAssertEqual(firstCall.voiceChannelState, ZMVoiceChannelStateIncomingCall);

        [secondCall.voiceChannel addCallParticipant:self.syncUser2];
        secondCall.isIgnoringCall = YES;
        XCTAssertEqual(secondCall.voiceChannelState, ZMVoiceChannelStateIncomingCallInactive);
        
        // when
        ZMConversation *fetchedConversation = firstCall.firstOtherConversationWithActiveCall;
        
        // then
        XCTAssertNil(fetchedConversation);
    }];
}

- (void)testThatItReturnsOtherConversationWithActiveCallIfOneIsInTransferReadyState
{
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMConversation *firstCall = self.syncOneOnOneConversation;
        ZMConversation *secondCall = self.syncGroupConversation;
        
        // given
        [firstCall.voiceChannel addCallParticipant:self.syncUser2];
        XCTAssertEqual(firstCall.voiceChannelState, ZMVoiceChannelStateIncomingCall);
        
        [secondCall.voiceChannel addCallParticipant:self.syncUser1];
        [secondCall.voiceChannel addCallParticipant:self.syncSelfUser];
        secondCall.callDeviceIsActive = NO;
        secondCall.isIgnoringCall = NO;
        XCTAssertEqual(secondCall.voiceChannelState, ZMVoiceChannelStateDeviceTransferReady);

        // when
        ZMConversation *fetchedConversation = firstCall.firstOtherConversationWithActiveCall;
        
        // then
        XCTAssertEqual(fetchedConversation, secondCall);
    }];
}


- (void)testThatItReturnNoOtherConversationsWithActiveCallIfOnlyCurrentConversationHasActiveCall
{
    [self.syncMOC performGroupedBlockAndWait:^{
        
        // given
        [self.syncOneOnOneConversation.voiceChannel addCallParticipant:self.selfUser];
        
        XCTAssertEqual(self.syncOneOnOneConversation.callParticipants.count, 1u);
        XCTAssertEqual(self.syncGroupConversation.callParticipants.count, 0u);
        
        // when
        ZMConversation *fetchedConversation = self.syncOneOnOneConversation.firstOtherConversationWithActiveCall;
        
        // then
        XCTAssertNil(fetchedConversation);
    }];
}

- (void)testThatItResetsIsIgnoringCallWhenIgnoringACallAndImmediatelyCallingBack
{
    // when
    [self.conversation.voiceChannel ignoreIncomingCall];

    // then
    XCTAssertTrue(self.conversation.isIgnoringCall);

    // when
    [self.conversation.voiceChannel join];
    
    // then
    XCTAssertFalse(self.conversation.isIgnoringCall);
}

- (void)testThatItReturns_Connected_ForAOneOnOneConversation_With_ActiveFlow_IncomingCall
{
    [self.syncMOC performGroupedBlockAndWait:^{
        // when
        // other user joins first (calls)
        [self.syncGroupConversation.voiceChannel addCallParticipant:self.syncUser1];
        
        [self.syncGroupConversation.voiceChannel join];
        [self.syncGroupConversation.voiceChannel addCallParticipant:self.syncSelfUser];
        [self.syncGroupConversation.voiceChannel updateActiveFlowParticipants:@[self.syncUser1]];
        self.syncGroupConversation.isFlowActive = YES;
        
        // then
        XCTAssertFalse(self.syncGroupConversation.isOutgoingCall);
        XCTAssertEqual(self.syncGroupConversation.voiceChannel.state, ZMVoiceChannelStateSelfConnectedToActiveChannel);
    }];
}

- (void)testThatItReturns_Joining_ForAOneOnOneConversation_WithOut_ActiveFlow_IncomingCall
{
    [self.syncMOC performGroupedBlockAndWait:^{
        // when
        // other user joins first (calls)
        [self.syncGroupConversation.voiceChannel addCallParticipant:self.syncUser1];
        
        [self.syncGroupConversation.voiceChannel join];
        [self.syncGroupConversation.voiceChannel addCallParticipant:self.syncSelfUser];
        
        // then
        XCTAssertFalse(self.syncGroupConversation.isOutgoingCall);
        XCTAssertEqual(self.syncGroupConversation.voiceChannel.state, ZMVoiceChannelStateSelfIsJoiningActiveChannel);
    }];
}

- (void)testThatItReturns_Joining_ForAGroupConversation_WithOut_ActiveFlow_OutgoingCall
{
    [self.syncMOC performGroupedBlockAndWait:^{
        // when
        // selfuser joins first (calls)
        [self.syncGroupConversation.voiceChannel join];
        
        [self.syncGroupConversation.voiceChannel addCallParticipant:self.syncUser1];
        [self.syncGroupConversation.voiceChannel addCallParticipant:self.syncSelfUser];
        
        // then
        XCTAssertTrue(self.syncGroupConversation.isOutgoingCall);
        XCTAssertEqual(self.syncGroupConversation.voiceChannel.state, ZMVoiceChannelStateSelfIsJoiningActiveChannel);
    }];
}

- (void)testThatItResetsIsOutgoingCallWhenSecondParticipantJoins
{
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        // selfuser joins first (calls)
        [self.syncGroupConversation.voiceChannel join];
        
        [self.syncGroupConversation.voiceChannel addCallParticipant:self.syncUser1];
        [self.syncGroupConversation.voiceChannel addCallParticipant:self.syncSelfUser];
        XCTAssertTrue(self.syncGroupConversation.isOutgoingCall);

        // when
        [self.syncGroupConversation.voiceChannel updateActiveFlowParticipants:@[self.syncUser1]];
        
        // then
        XCTAssertFalse(self.syncGroupConversation.isOutgoingCall);
    }];
}


@end




@implementation ZMVoiceChannelTests (Participants)

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
        
        [conversation.voiceChannel addCallParticipant:self.syncSelfUser];
        [conversation.voiceChannel addCallParticipant:self.syncUser1];
        [conversation.voiceChannel addCallParticipant:self.syncUser2];
        
        // when
        [conversation.voiceChannel updateActiveFlowParticipants:@[self.syncUser1, self.syncUser2]];
        XCTAssertEqual(conversation.activeFlowParticipants.count, 2u);
        
        // then
        XCTAssertEqual(conversation.voiceChannel.participants.count, 2u);
    }];
}

@end



@implementation ZMVoiceChannelTests (ParticipantsState)

- (void)testThatItReturnsParticipantConnected
{
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMConversation *conv = (id)[self.syncMOC objectWithID:self.conversation.objectID];
        // given
        [conv.voiceChannel addCallParticipant:self.syncUser1];
        [conv.voiceChannel updateActiveFlowParticipants:@[self.syncUser1]];
        
        // when
        ZMVoiceChannelParticipantState *state = [conv.voiceChannel participantStateForUser:self.syncUser1];
        
        // then
        XCTAssertEqual(state.connectionState, ZMVoiceChannelConnectionStateConnected);
    }];
}


- (void)testThatItReturnsParticipantConnecting
{
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMConversation *conv = (id)[self.syncMOC objectWithID:self.conversation.objectID];
        // given
        [conv.voiceChannel addCallParticipant:self.syncUser1];
        conv.isFlowActive = NO;
        
        // when
        ZMVoiceChannelConnectionState state = [conv.voiceChannel participantStateForUser:self.syncUser1].connectionState;
        
        // then
        XCTAssertEqual(state, ZMVoiceChannelConnectionStateConnecting);
    }];
}


- (void)testThatItReturnsParticipantNotConnected
{
    // given
    XCTAssertFalse([self.conversation.callParticipants containsObject:self.otherUser]);

    // then
    XCTAssertEqual([self.conversation.voiceChannel participantStateForUser:self.otherUser].connectionState, ZMVoiceChannelConnectionStateNotConnected);
}

- (void)testThatItCanEnumerateConnectionStatesForParticipants;
{
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        [self.syncOneOnOneConversation.voiceChannel addCallParticipant:self.syncUser1];
        
        XCTAssertTrue([self.syncOneOnOneConversation.callParticipants containsObject:self.syncUser1]);
        XCTAssertFalse([self.syncOneOnOneConversation.callParticipants containsObject:self.syncSelfUser]);
        
        // when
        NSMutableArray *users = [NSMutableArray array];
        [self.syncOneOnOneConversation.voiceChannel enumerateParticipantStatesWithBlock:^(ZMUser *user, ZMVoiceChannelConnectionState connectionState, BOOL muted) {
            [users addObject:user];
            XCTAssertFalse(muted);
            if (user == self.syncUser1) {
                XCTAssertEqual(connectionState, ZMVoiceChannelConnectionStateConnecting);
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
        [self.syncOneOnOneConversation.voiceChannel addCallParticipant:self.syncSelfUser];
        [self.syncOneOnOneConversation.voiceChannel updateActiveFlowParticipants:@[self.syncUser1]];
        self.syncOneOnOneConversation.isFlowActive = YES;
        
        XCTAssertTrue([self.syncOneOnOneConversation.callParticipants containsObject:self.syncSelfUser]);
        XCTAssertFalse([self.syncOneOnOneConversation.callParticipants containsObject:self.syncUser1]);
        
        // then
        XCTAssertEqual(self.syncOneOnOneConversation.voiceChannel.selfUserConnectionState, ZMVoiceChannelConnectionStateConnected);
    }];
   
}

- (void)testThatItReturnsTheSelfUserConnectionStateConnecting;
{
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        [self.syncOneOnOneConversation.voiceChannel addCallParticipant:self.syncSelfUser];
        self.syncOneOnOneConversation.isFlowActive = NO;
        
        XCTAssertTrue([self.syncOneOnOneConversation.callParticipants containsObject:self.syncSelfUser]);
        XCTAssertFalse([self.syncOneOnOneConversation.callParticipants containsObject:self.syncUser1]);
        
        // then
        XCTAssertEqual(self.syncOneOnOneConversation.voiceChannel.selfUserConnectionState, ZMVoiceChannelConnectionStateConnecting);
    }];
}

- (void)testThatItReturnsTheSelfUserConnectionStateNotConnected;
{
    // given
    XCTAssertFalse([self.conversation.callParticipants containsObject:self.selfUser]);

    // then
    XCTAssertEqual(self.conversation.voiceChannel.selfUserConnectionState, ZMVoiceChannelConnectionStateNotConnected);
}

@end

@implementation ZMVoiceChannelTests (ActiveVoiceChannel)

- (ZMUserSession *)mockUserSession
{
    id mock = [OCMockObject mockForClass:ZMUserSession.class];
    [[[mock stub] andReturn:self.uiMOC] managedObjectContext];
    return mock;
}

- (ZMUser *)addCallParticipantToConversation:(ZMConversation *)conversation
{
    ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    return [self addCallParticipant:user toConversation:conversation];
}

- (ZMUser *)addCallParticipant:(ZMUser*)user toConversation:(ZMConversation *)conversation
{
    if(!user.isSelfUser) {
        [conversation.mutableOtherActiveParticipants addObject:user];
    }
    [conversation.voiceChannel addCallParticipant:user];
    return user;
}

- (ZMConversation *)createActiveChannelConversation
{
    __block NSManagedObjectID *objectID;
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMConversation *activeConversation = (id)[self.syncMOC objectWithID:self.groupConversation.objectID];
        ZMUser *syncSelfUser = (id)[self.syncMOC objectWithID:self.selfUser.objectID];
        ZMUser *syncOtherUser = (id)[self.syncMOC objectWithID:self.otherUser.objectID];
        activeConversation.callDeviceIsActive = YES;
        activeConversation.isFlowActive = YES;
        [activeConversation.voiceChannel addCallParticipant:syncOtherUser];
        [activeConversation.voiceChannel addCallParticipant:syncSelfUser];
        [activeConversation.voiceChannel updateActiveFlowParticipants:@[syncOtherUser]];
        [self.syncMOC saveOrRollback];
        objectID = activeConversation.objectID;
    }];
    [self.uiMOC mergeCallStateChanges:self.syncMOC.zm_callState];
    ZMConversation *conversation =  (id)[self.uiMOC objectWithID:objectID];
    [self.uiMOC refreshObject:conversation mergeChanges:NO];
    return conversation;
}

- (void)testThatActiveVoiceChannelReturnsNilWhenThereAreNoConversations
{
    // when
    ZMVoiceChannel *channel = [ZMVoiceChannel activeVoiceChannelInSession:self.mockUserSession];

    // then
    XCTAssertNil(channel);
}

- (void)testThatActiveVoiceChannelReturnsNilWhenTheConversationIsNotActive
{
    // given
    ZMConversation *activeConversation = self.groupConversation;
    XCTAssertNotEqual(activeConversation.voiceChannel.state, ZMVoiceChannelStateSelfConnectedToActiveChannel);

    // when
    ZMVoiceChannel *channel = [ZMVoiceChannel activeVoiceChannelInSession:self.mockUserSession];

    // then
    XCTAssertNil(channel);
    
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatActiveVoiceChannelReturnsTheConversationWithTheActiveChannel
{
    // given
    ZMConversation *activeConversation = [self createActiveChannelConversation];
    XCTAssertEqual(activeConversation.voiceChannel.state, ZMVoiceChannelStateSelfConnectedToActiveChannel);

    // when
    ZMVoiceChannel *channel = [ZMVoiceChannel activeVoiceChannelInSession:self.mockUserSession];

    // then
    XCTAssertEqual(channel, activeConversation.voiceChannel);
    
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testPerformanceOfGettingTheActiveVoiceChannel;
{
    // given
    // 100 conversations
    NSUInteger const count = 100;
    for (NSUInteger i = 0; i < count; ++i) {
        ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
        conversation.remoteIdentifier = NSUUID.createUUID;

        BOOL const isGroup = (i % 3) == 0;
        if (isGroup) {
            conversation.conversationType = ZMConversationTypeGroup;
        } else {
            conversation.conversationType = ZMConversationTypeOneOnOne;
            conversation.connection = [ZMConnection insertNewObjectInManagedObjectContext:self.uiMOC];
            conversation.connection.status = ZMConnectionStatusAccepted;
        }
    }
    [self.uiMOC saveOrRollback];

    // then
    [self measureBlock:^{
        for (size_t i = 0; i < 100; ++i) {
            ZMVoiceChannel *channel = [ZMVoiceChannel activeVoiceChannelInManagedObjectContext:self.uiMOC];
            XCTAssertNil(channel);
        }
    }];
}

@end



@implementation ZMVoiceChannelTests (CallTimer)

- (void)testThatItTimesOutTheCallInAOneOnOneConversation_AndEndsIt
{
    ZMConversation *uiConv = (id)[self.uiMOC objectWithID:self.syncOneOnOneConversation.objectID];
    [uiConv.voiceChannel join];
    [self.syncMOC mergeCallStateChanges:[self.uiMOC.zm_callState createCopyAndResetHasChanges]];

    
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        [ZMCallTimer setTestCallTimeout:0.2];
        
        // when
        [self.syncOneOnOneConversation.voiceChannel addCallParticipant:self.syncSelfUser];
        [self.syncGroupConversation resetHasLocalModificationsForCallDeviceIsActive]; // done by the BE, starts the timer
        XCTAssertEqual(self.syncOneOnOneConversation.voiceChannelState, ZMVoiceChannelStateOutgoingCall);
        
        [self spinMainQueueWithTimeout:0.5];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
     
    [self.syncMOC performGroupedBlockAndWait:^{
        [self.syncMOC mergeCallStateChanges:self.uiMOC.zm_callState]; // callDeviceIsActive is set to NO on the uiContext, therefore need to merge changes
        [self.syncOneOnOneConversation.voiceChannel removeCallParticipant:self.syncSelfUser]; // done by the BE when syncing callDeviceIsActive

        // then
        XCTAssertFalse(self.syncOneOnOneConversation.isOutgoingCall);
        XCTAssertFalse(self.syncOneOnOneConversation.callDeviceIsActive);
        XCTAssertTrue(self.syncOneOnOneConversation.hasLocalModificationsForCallDeviceIsActive);

        XCTAssertEqual(self.syncOneOnOneConversation.voiceChannelState, ZMVoiceChannelStateNoActiveUsers);
    }];
}


- (void)testThatItTimesOutTheCallInAGroupConversation_AndSilencesIt
{
    ZMConversation *uiConv = (id)[self.uiMOC objectWithID:self.syncGroupConversation.objectID];
    [uiConv.voiceChannel join];
    [self.syncMOC mergeCallStateChanges:[self.uiMOC.zm_callState createCopyAndResetHasChanges]];

    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        [ZMCallTimer setTestCallTimeout:0.2];

        // when
        [self.syncGroupConversation.voiceChannel addCallParticipant:self.syncSelfUser]; // done by the BE, starts the timer
        [self.syncGroupConversation resetHasLocalModificationsForCallDeviceIsActive];
        XCTAssertEqual(self.syncGroupConversation.voiceChannelState, ZMVoiceChannelStateOutgoingCall);
        
        [self spinMainQueueWithTimeout:0.5];
    }];
    WaitForAllGroupsToBeEmpty(0.5);

    [self.syncMOC performGroupedBlockAndWait:^{
        [self.syncMOC mergeCallStateChanges:self.uiMOC.zm_callState]; // callTimedOut is set to YES on the uiContext, therefore need to merge changes

        // then
        XCTAssertTrue(self.syncGroupConversation.isOutgoingCall);
        XCTAssertTrue(self.syncGroupConversation.callDeviceIsActive);
        XCTAssertFalse(self.syncGroupConversation.hasLocalModificationsForCallDeviceIsActive);
        
        XCTAssertEqual(self.syncGroupConversation.voiceChannelState, ZMVoiceChannelStateOutgoingCallInactive);
    }];
}

- (void)testThatItDoesNotStartTheTimerWhenJoiningAConversationWithoutSynchingWithTheBE
{
    // given
    self.groupConversation.remoteIdentifier = NSUUID.createUUID;
    [ZMCallTimer setTestCallTimeout:0.2];
    
    // when
    [self.groupConversation.voiceChannel join];
    // the BE usually adds the user to the callParticipants
    // however when the BE rejects the request, it just sets callDeviceIsActive to NO
    XCTAssertEqual(self.groupConversation.voiceChannelState, ZMVoiceChannelStateOutgoingCall);
    
    [self spinMainQueueWithTimeout:0.5];
    
    // then
    XCTAssertTrue(self.groupConversation.isOutgoingCall);
    XCTAssertEqual(self.groupConversation.voiceChannelState, ZMVoiceChannelStateOutgoingCall);
}

- (void)testThatItCancelsAStartedTimerIfThereAreNoCallParticipantsInAnOutgoingCall
{
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        [ZMCallTimer setTestCallTimeout:0.2];
        
        // (1) when selfUser joins
        [self.syncGroupConversation.voiceChannel join]; // this does not start the timer
        [self.syncGroupConversation.voiceChannel addCallParticipant:self.syncSelfUser]; // this starts the timer
        XCTAssertEqual(self.syncGroupConversation.voiceChannelState, ZMVoiceChannelStateOutgoingCall);
        
        // (2) the other user joins, the timer stops
        [self.syncGroupConversation.voiceChannel addCallParticipant:self.syncUser1]; // this stops the timer
        XCTAssertEqual(self.syncGroupConversation.voiceChannelState, ZMVoiceChannelStateSelfIsJoiningActiveChannel);
        
        // (3) both users leave
        // the callstate transcoder removes them one after another
        [self.syncGroupConversation.voiceChannel removeCallParticipant:self.syncUser1]; // this will start the timer
        XCTAssertEqual(self.syncGroupConversation.voiceChannelState, ZMVoiceChannelStateOutgoingCall);
        
        [self.syncGroupConversation.voiceChannel removeCallParticipant:self.syncSelfUser]; // this should stop the timer
        XCTAssertEqual(self.syncGroupConversation.voiceChannelState, ZMVoiceChannelStateOutgoingCall);
        
        // (4) the call state transcoder will set callDeviceIsActive to NO for disconnected events that don't contain a self info
        self.syncGroupConversation.callDeviceIsActive = NO;
        XCTAssertEqual(self.syncGroupConversation.voiceChannelState, ZMVoiceChannelStateNoActiveUsers);
        
        // (5) if the timer wasn't cancelled before, it would fire now
        [self spinMainQueueWithTimeout:0.5];
        
        // (6) we initiate a new call, if the timer was fired, we would be in timedOut state (OutgoingCallInactive)
        [self.syncGroupConversation.voiceChannel join];
        [self.syncGroupConversation.voiceChannel addCallParticipant:self.syncSelfUser];
        
        // then
        XCTAssertTrue(self.syncGroupConversation.isOutgoingCall);
        XCTAssertEqual(self.syncGroupConversation.voiceChannelState, ZMVoiceChannelStateOutgoingCall);
    }];
}

- (void)testThatItSetsDidTimeOutWhenTheTimerFires_GroupCall
{
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMConversation *conversation = self.syncGroupConversation;
        conversation.callTimedOut = NO;
        [self.uiMOC mergeCallStateChanges:[self.syncMOC.zm_callState createCopyAndResetHasChanges]];
        
        XCTAssertFalse(conversation.callTimedOut);

        [ZMCallTimer setTestCallTimeout:0.2];
        
        // when
        [self.syncMOC zm_addAndStartCallTimer:conversation];
        [self spinMainQueueWithTimeout:0.5];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    [self.syncMOC performGroupedBlockAndWait:^{
        [self.syncMOC mergeCallStateChanges:[self.uiMOC.zm_callState createCopyAndResetHasChanges]];
        
        // then
        ZMConversation *conversation = self.syncGroupConversation;
        XCTAssertTrue(conversation.callTimedOut);
    }];
}

- (void)testThatItSetsDidTimeOutWhenTheTimerFires_OneOnOneIncoming
{
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMConversation *conversation = self.syncOneOnOneConversation;
        conversation.callTimedOut = NO;
        conversation.isOutgoingCall = NO;
        [self.uiMOC mergeCallStateChanges:[self.syncMOC.zm_callState createCopyAndResetHasChanges]];
        
        XCTAssertFalse(conversation.callTimedOut);
        
        [ZMCallTimer setTestCallTimeout:0.2];
        
        // when
        [self.syncMOC zm_addAndStartCallTimer:conversation];
        [self spinMainQueueWithTimeout:0.5];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    [self.syncMOC performGroupedBlockAndWait:^{
        [self.syncMOC mergeCallStateChanges:[self.uiMOC.zm_callState createCopyAndResetHasChanges]];
        
        // then
        ZMConversation *conversation = self.syncOneOnOneConversation;
        XCTAssertTrue(conversation.callTimedOut);
    }];
}

- (void)testThatItDoesNotSetDidTimeOutWhenTheTimerFires_OneOnOneOutGoing
{
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMConversation *conversation = self.syncOneOnOneConversation;
        conversation.callTimedOut = NO;
        conversation.isOutgoingCall = YES;
        [self.uiMOC mergeCallStateChanges:[self.syncMOC.zm_callState createCopyAndResetHasChanges]];
        
        XCTAssertFalse(conversation.callTimedOut);
        
        [ZMCallTimer setTestCallTimeout:0.2];
        
        // when
        [self.syncMOC zm_addAndStartCallTimer:conversation];
        [self spinMainQueueWithTimeout:0.5];
        
        [self.syncMOC mergeCallStateChanges:[self.uiMOC.zm_callState createCopyAndResetHasChanges]];
        
        // then
        XCTAssertFalse(conversation.callTimedOut);
    }];
}

- (void)testThatItReSetsDidTimeOutWhenRemovingAllCallParticipants
{
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMConversation *conversation = self.syncGroupConversation;
        [self.syncGroupConversation.voiceChannel addCallParticipant:self.syncUser1];
        [self.syncGroupConversation.voiceChannel addCallParticipant:self.syncUser2];
        [self.syncGroupConversation.voiceChannel addCallParticipant:self.syncUser3];
        
        conversation.callTimedOut = YES;
        
        // when
        [conversation.voiceChannel removeAllCallParticipants];
        
        // then
        XCTAssertFalse(conversation.callTimedOut);
    }];
}

- (void)testThatItReSetsDidTimeOutWhenRemovingTheLastCallParticipants
{
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMConversation *conversation = self.syncGroupConversation;
        [self.syncGroupConversation.voiceChannel addCallParticipant:self.syncUser1];
        [self.syncGroupConversation.voiceChannel addCallParticipant:self.syncUser2];
        [self.syncGroupConversation.voiceChannel addCallParticipant:self.syncUser3];
        
        conversation.callTimedOut = YES;
        
        // when
        [conversation.voiceChannel removeCallParticipant:self.syncUser1];
        [conversation.voiceChannel removeCallParticipant:self.syncUser2];

        // then
        XCTAssertTrue(conversation.callTimedOut);
        
        // when
        [conversation.voiceChannel removeCallParticipant:self.syncUser3];
        
        // then
        XCTAssertFalse(conversation.callTimedOut);
    }];
}

@end



@implementation ZMVoiceChannelTests (JoinAndLeave)

- (void)testThatWhenJoiningTheVoiceChannel_callDeviceIsActive_isSet
{
    // given
    XCTAssertFalse(self.conversation.callDeviceIsActive);
    
    // when
    [self.conversation.voiceChannel join];
    
    // then
    XCTAssertTrue(self.conversation.callDeviceIsActive);
    
}

- (void)testThatWhenLeavingTheVoiceChannel_callDeviceIsActive_isUnset
{
    [self.syncMOC performGroupedBlockAndWait:^{
        
        // given
        [self.syncOneOnOneConversation.voiceChannel addCallParticipant:self.syncSelfUser];
        self.syncOneOnOneConversation.callDeviceIsActive = YES;
        XCTAssertTrue([self.syncOneOnOneConversation.callParticipants containsObject:self.syncSelfUser]);
        
        // when
        [self.syncOneOnOneConversation.voiceChannel leave];
        
        // then
        XCTAssertFalse(self.syncOneOnOneConversation.callDeviceIsActive);
    }];
}

- (void)testThatWhenLeavingTheVoiceChannel_reasonToLeave_isSet
{
    [self.syncMOC performGroupedBlockAndWait:^{
        
        // given
        [self.syncOneOnOneConversation.voiceChannel addCallParticipant:self.syncSelfUser];
        self.syncOneOnOneConversation.callDeviceIsActive = YES;
        self.syncOneOnOneConversation.reasonToLeave = ZMCallStateReasonToLeaveNone;
        XCTAssertTrue([self.syncOneOnOneConversation.callParticipants containsObject:self.syncSelfUser]);
        
        // when
        [self.syncOneOnOneConversation.voiceChannel leave];
        
        // then
        XCTAssertEqual(self.syncOneOnOneConversation.reasonToLeave, ZMCallStateReasonToLeaveUser);
    }];
}

- (void)testThatWhenLeavingTheVoiceChannelOnAVSError_reasonToLeave_isSet
{
    [self.syncMOC performGroupedBlockAndWait:^{
        
        // given
        [self.syncOneOnOneConversation.voiceChannel addCallParticipant:self.syncSelfUser];
        self.syncOneOnOneConversation.callDeviceIsActive = YES;
        self.syncOneOnOneConversation.reasonToLeave = ZMCallStateReasonToLeaveNone;
        XCTAssertTrue([self.syncOneOnOneConversation.callParticipants containsObject:self.syncSelfUser]);
        
        // when
        [self.syncOneOnOneConversation.voiceChannel leaveOnAVSError];
        
        // then
        XCTAssertEqual(self.syncOneOnOneConversation.reasonToLeave, ZMCallStateReasonToLeaveAvsError);
    }];
}

- (void)testThatLeavingTheVoiceChannelWithoutLeavingTheConversation_DoesNotReset_IsIgnoringCall_TwoParticipantsLeft
{
    [self.syncMOC performGroupedBlockAndWait:^{
        // given

        self.syncGroupConversation.callDeviceIsActive = YES;
        
        [self.syncGroupConversation.voiceChannel addCallParticipant:self.syncSelfUser];
        [self.syncGroupConversation.voiceChannel addCallParticipant:self.syncUser1];
        [self.syncGroupConversation.voiceChannel addCallParticipant:self.syncUser2];

        XCTAssertFalse(self.syncGroupConversation.isIgnoringCall);
        XCTAssertEqual(self.syncGroupConversation.voiceChannel.state, ZMVoiceChannelStateSelfIsJoiningActiveChannel);
        
        // when
        [self.syncGroupConversation.voiceChannel leave];
        
        // then
        XCTAssertTrue(self.syncGroupConversation.isIgnoringCall);
    }];
}

- (void)testThatLeavingTheVoiceChannelWithoutLeavingTheConversation_DoesNotReset_IsIgnoringCall_OneParticipantsLeft
{
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        
        self.syncGroupConversation.callDeviceIsActive = YES;
        
        [self.syncGroupConversation.voiceChannel addCallParticipant:self.syncSelfUser];
        [self.syncGroupConversation.voiceChannel addCallParticipant:self.syncUser1];
        
        XCTAssertFalse(self.syncGroupConversation.isIgnoringCall);
        XCTAssertEqual(self.syncGroupConversation.voiceChannel.state, ZMVoiceChannelStateSelfIsJoiningActiveChannel);
        
        // when
        [self.syncGroupConversation.voiceChannel leave];
        
        // then
        XCTAssertFalse(self.syncGroupConversation.isIgnoringCall);
    }];
}

- (void)testThatTheVoiceChannelReturnsStateNoActiveUsersAfterLeavingTheConversation
{
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        self.syncGroupConversation.callDeviceIsActive = YES;
        
        [self.syncGroupConversation.voiceChannel addCallParticipant:self.syncSelfUser];
        [self.syncGroupConversation.voiceChannel addCallParticipant:self.syncUser1];
        
        XCTAssertFalse(self.syncGroupConversation.isIgnoringCall);
        XCTAssertEqual(self.syncGroupConversation.voiceChannel.state, ZMVoiceChannelStateSelfIsJoiningActiveChannel);
        [self.syncMOC saveOrRollback];
        [self.uiMOC mergeCallStateChanges:[self.syncMOC.zm_callState createCopyAndResetHasChanges]];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    ZMConversation *uiConv = (id)[self.uiMOC objectWithID:self.syncGroupConversation.objectID];
    [self.uiMOC refreshObject:uiConv mergeChanges:NO];

    XCTAssertEqual(uiConv.voiceChannelState, ZMVoiceChannelStateSelfIsJoiningActiveChannel);

    // when
    [uiConv.voiceChannel leave];
    [uiConv removeParticipant:self.selfUser];
    
    [self.syncMOC performGroupedBlockAndWait:^{
        // this step is done by the transcoder
        [self.syncGroupConversation.voiceChannel removeAllCallParticipants];
        [self.syncMOC saveOrRollback];
    }];
    [self.uiMOC refreshObject:uiConv mergeChanges:YES];

    // then
    XCTAssertEqual(uiConv.voiceChannelState, ZMVoiceChannelStateNoActiveUsers);
}


- (void)testThatWhenCancellingAnOutgoingCallTheCallParticipantsAreReset
{
    ZMConversation *uiConv = (id)[self.uiMOC objectWithID:self.syncGroupConversation.objectID];
    [uiConv.voiceChannel join];
    [self.syncMOC mergeCallStateChanges:[self.uiMOC.zm_callState createCopyAndResetHasChanges]];
    
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        [self.syncGroupConversation.voiceChannel addCallParticipant:self.syncSelfUser];
        XCTAssertTrue([self.syncGroupConversation.callParticipants containsObject:self.syncSelfUser]);
        XCTAssertFalse(self.syncGroupConversation.isIgnoringCall);
        XCTAssertEqual(self.syncGroupConversation.voiceChannel.state, ZMVoiceChannelStateOutgoingCall);
        [self.syncMOC saveOrRollback];
        [self.uiMOC mergeCallStateChanges:[self.syncMOC.zm_callState createCopyAndResetHasChanges]];
    }];
    [self.uiMOC refreshObject:uiConv mergeChanges:YES];

    
    // when
    [uiConv.voiceChannel leave];
    
    // then
    XCTAssertEqual(uiConv.voiceChannel.state, ZMVoiceChannelStateNoActiveUsers); // this is an intermediate state
    XCTAssertFalse(uiConv.isIgnoringCall);
}

- (void)testThatItSets_IsOutgoingCall_JoiningAVoiceChannelOnAOneOnOneConversationWithoutCallParticipants
{
    // when
    [self.conversation.voiceChannel join];
    
    // then
    XCTAssertTrue(self.conversation.isOutgoingCall);
}

- (void)testThatWeDoNotSetIsOutgoingCallWhenThereAreAlreadyUsersInTheVoiceChannel
{
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        [self.syncOneOnOneConversation.voiceChannel addCallParticipant:self.syncUser1];
        
        // when
        [self.syncOneOnOneConversation.voiceChannel join];
        
        // then
        XCTAssertFalse(self.syncOneOnOneConversation.isOutgoingCall);
    }];
}

- (void)testThatItResetsIsOutgoingCallWhenLeavingAVoiceChannel
{
    // given
    [self.conversation.voiceChannel join];
    XCTAssertTrue(self.conversation.isOutgoingCall);
    
    // when
    [self.conversation.voiceChannel leave];
    
    // then
    XCTAssertFalse(self.conversation.isOutgoingCall);
}


- (void)testThatItResetsAndRecalculates_IsOutgoingCall_WhenJoiningAVoiceChannelWithPreviousOutgoingCall
{
    // given
    
    // the selfuser calls first
    [self.conversation.voiceChannel join];
    [self.uiMOC saveOrRollback];
    [self.syncMOC mergeCallStateChanges:self.uiMOC.zm_callState.createCopyAndResetHasChanges];
    XCTAssertTrue(self.conversation.isOutgoingCall);

    // the BE returns and other users join
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMConversation *syncConv = (id)[self.syncMOC objectWithID:self.conversation.objectID];
        [syncConv.voiceChannel addCallParticipant:self.selfUser];
        [syncConv.voiceChannel addCallParticipant:self.syncUser1];
        [syncConv.voiceChannel addCallParticipant:self.syncUser2];
        [self.syncMOC saveOrRollback];
    }];
    [self.uiMOC mergeCallStateChanges:self.syncMOC.zm_callState.createCopyAndResetHasChanges];
    XCTAssertTrue(self.conversation.isOutgoingCall);

    // (1) when the BE force idles the call
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMConversation *syncConv = (id)[self.syncMOC objectWithID:self.conversation.objectID];
        [syncConv.voiceChannel removeCallParticipant:self.syncUser1];
        [syncConv.voiceChannel removeCallParticipant:self.syncUser2];
        [syncConv.voiceChannel removeCallParticipant:self.selfUser];
        [self.syncMOC saveOrRollback];
    }];
    [self.uiMOC mergeCallStateChanges:self.syncMOC.zm_callState.createCopyAndResetHasChanges];
    
    // then
    // we reset isOutgoingCall
    XCTAssertFalse(self.conversation.isOutgoingCall);

    // (2) when the other user calls first
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMConversation *syncConv = (id)[self.syncMOC objectWithID:self.conversation.objectID];
        [syncConv.voiceChannel addCallParticipant:self.syncUser1];
        [self.syncMOC saveOrRollback];
    }];
    [self.uiMOC refreshObject:self.conversation mergeChanges:NO];
    [self.uiMOC mergeCallStateChanges:self.syncMOC.zm_callState.createCopyAndResetHasChanges];

    [self.conversation.voiceChannel join];
    
    // then
    XCTAssertFalse(self.conversation.isOutgoingCall);
}

@end


@implementation ZMVoiceChannelTests (GSMCalls)

- (void)testThatItSendsANotificationWhenThereIsAnOngoingGSMCall_AndDoesNotJoinTheVoiceChannel
{
    // given
    id call = [OCMockObject niceMockForClass:[CTCall class]];
    [(CTCall *)[[call expect] andReturn:CTCallStateConnected] callState];
    id callCenter = [OCMockObject niceMockForClass:[CTCallCenter class]];
    
    ZMVoiceChannel *voiceChannel = [[ZMVoiceChannel alloc] initWithConversation:self.conversation callCenter:callCenter];
    id token = [self.conversation.voiceChannel addCallingInitializationObserver:self];
    // expect
    [[[callCenter expect] andReturn:[NSSet setWithObject:call]] currentCalls];
    
    // when
    [voiceChannel join];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(self.receivedErrors.count, 1u);
    NSError *receivedError = self.receivedErrors.firstObject;
    if (receivedError != nil) {
        XCTAssertEqual(receivedError.code, (long)ZMVoiceChannelErrorCodeOngoingGSMCall);
    }
    XCTAssertFalse(self.conversation.callDeviceIsActive);
    [self.conversation.voiceChannel removeCallingInitialisationObserver:token];
}

- (void)testThatItDoesNotSendANotificationWhenThereIsAIncomingGSMCall_AndDoesNotJoinTheVoiceChannel
{
    // given
    id token = [self.conversation.voiceChannel addCallingInitializationObserver:self];
    id call1 = [OCMockObject niceMockForClass:[CTCall class]];
    [(CTCall *)[[call1 expect] andReturn:CTCallStateIncoming] callState];
    id call2 = [OCMockObject niceMockForClass:[CTCall class]];
    [(CTCall *)[[call2 expect] andReturn:CTCallStateDisconnected] callState];
    id call3 = [OCMockObject niceMockForClass:[CTCall class]];
    [(CTCall *)[[call3 expect] andReturn:CTCallStateDialing] callState];
    
    id callCenter = [OCMockObject niceMockForClass:[CTCallCenter class]];
    
    ZMVoiceChannel *voiceChannel = [[ZMVoiceChannel alloc] initWithConversation:self.conversation callCenter:callCenter];
    
    // expect
    [[[callCenter expect] andReturn:[NSSet setWithObjects:call1,call2, call3, nil]] currentCalls];

    // when
    [voiceChannel join];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(self.receivedErrors.count, 0u);
    XCTAssertTrue(self.conversation.callDeviceIsActive);
    [self.conversation.voiceChannel removeCallingInitialisationObserver:token];
}



- (void)testThatItDoesNotSendANotificationWhenThereIsNoGSMCall_AndJoinsTheVoiceChannel
{
    // given
    id token = [self.conversation.voiceChannel addCallingInitializationObserver:self];
    id callCenter = [OCMockObject niceMockForClass:[CTCallCenter class]];
    ZMVoiceChannel *voiceChannel = [[ZMVoiceChannel alloc] initWithConversation:self.groupConversation callCenter:callCenter];
    
    // expect
    [[[callCenter expect] andReturn:[NSSet set]] currentCalls];
    
    // when
    [voiceChannel join];
    
    // then
    XCTAssertEqual(self.receivedErrors.count, 0u);
    XCTAssertTrue(self.groupConversation.callDeviceIsActive);
    [self.conversation.voiceChannel removeCallingInitialisationObserver:token];
}

@end



@implementation ZMVoiceChannelTests (Notifications)

- (void)testThatItPostsShouldKeepWebsocketOpenNotificationOnJoin
{
    //given
    __block BOOL selfJoined = NO;
    id observer = [[NSNotificationCenter defaultCenter] addObserverForName:ZMTransportSessionShouldKeepWebsocketOpenNotificationName object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
        selfJoined = [note.userInfo[ZMTransportSessionShouldKeepWebsocketOpenKey] boolValue];
    }];
    
    //when
    [self.conversation.voiceChannel join];
    WaitForAllGroupsToBeEmpty(0.5);

    //then
    XCTAssertTrue(selfJoined);
    
    [[NSNotificationCenter defaultCenter] removeObserver:observer];
}

- (void)testThatItPostsShouldKeepWebsocketOpenNotificationOnLeave
{
    //given
    [self.conversation.voiceChannel join];
    __block BOOL selfJoined = YES;
    
    id observer = [[NSNotificationCenter defaultCenter] addObserverForName:ZMTransportSessionShouldKeepWebsocketOpenNotificationName object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
        selfJoined = [note.userInfo[ZMTransportSessionShouldKeepWebsocketOpenKey] boolValue];
    }];
    
    //when
    [self.conversation.voiceChannel leave];
    
    //then
    XCTAssertFalse(selfJoined);
    
    [[NSNotificationCenter defaultCenter] removeObserver:observer];
}

- (void)testThatItPostsShouldKeepWebsocketOpenNotificationOnRemoveCallParticipantIfParticipantIsSelf
{
    //given
    [self.conversation.voiceChannel join];
    WaitForAllGroupsToBeEmpty(0.5);

    __block BOOL selfJoined = YES;
    
    id observer = [[NSNotificationCenter defaultCenter] addObserverForName:ZMTransportSessionShouldKeepWebsocketOpenNotificationName object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *note) {
        selfJoined = [note.userInfo[ZMTransportSessionShouldKeepWebsocketOpenKey] boolValue];
    }];
    
    //when
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMConversation *syncConv = (id)[self.syncMOC objectWithID:self.conversation.objectID];
        ZMUser *syncSelfUser = (id)[self.syncMOC objectWithID:self.selfUser.objectID];
        [syncConv.voiceChannel removeCallParticipant:syncSelfUser];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    //then
    XCTAssertFalse(selfJoined);
    
    [[NSNotificationCenter defaultCenter] removeObserver:observer];
}

- (void)testThatItDoesNotPostShouldKeepWebsocketOpenNotificationOnRemoveCallParticipantIfParticipnatIsNotSelf
{
    //given
    [self.conversation.voiceChannel join];
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
        [syncConv.voiceChannel removeCallParticipant:syncOtherUser];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    //then
    XCTAssertTrue(selfJoined);
    XCTAssertFalse(notificationPosted);
    
    [[NSNotificationCenter defaultCenter] removeObserver:observer];
}

@end




