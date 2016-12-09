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


@import CoreTelephony;
@import zmessaging;
@import ZMCDataModel;

#import "MessagingTest.h"
#import "ZMGSMCallHandler.h"
#import "ZMCallStateLogger.h"
#import "ZMSyncStateMachine.h"

@interface ZMGSMCallHandlerTest : MessagingTest

@property (nonatomic) ZMGSMCallHandler *sut;
@property (nonatomic) ZMConversation *activeSyncCallConversation;
@property (nonatomic) ZMConversation *activeUICallConversation;
@property (nonatomic) id mockCallStateLogger;

@property (nonatomic) ZMConversation *inactiveSyncCallConversation;
@property (nonatomic) ZMConversation *inactiveUICallConversation;

@end



@implementation ZMGSMCallHandlerTest

- (void)setUp {
    [super setUp];
    WaitForAllGroupsToBeEmpty(0.5);
    
    [self.syncMOC performGroupedBlockAndWait:^{
        self.activeSyncCallConversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        self.activeSyncCallConversation.conversationType = ZMConversationTypeGroup;
        self.activeSyncCallConversation.callDeviceIsActive = YES;
        [self.activeSyncCallConversation resetHasLocalModificationsForCallDeviceIsActive];
        [self.syncMOC saveOrRollback];
    }];
    self.activeUICallConversation = (id)[self.uiMOC objectWithID:self.activeSyncCallConversation.objectID];
    
    [self.syncMOC performGroupedBlockAndWait:^{
        self.inactiveSyncCallConversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        self.inactiveSyncCallConversation.conversationType = ZMConversationTypeGroup;
        [self.syncMOC saveOrRollback];
    }];
    self.inactiveUICallConversation = (id)[self.uiMOC objectWithID:self.inactiveSyncCallConversation.objectID];

    [self.uiMOC saveOrRollback];

    self.mockCallStateLogger = [OCMockObject niceMockForClass:[ZMCallStateLogger  class]];
    [self verifyMockLater:self.mockCallStateLogger];
    
    self.sut = [[ZMGSMCallHandler alloc] initWithUIManagedObjectContext:self.uiMOC
                                               syncManagedObjectContext:self.syncMOC
                                                        callStateLogger:self.mockCallStateLogger];
    
    [[NSNotificationCenter defaultCenter] postNotificationName:ZMApplicationDidEnterEventProcessingStateNotificationName object:nil];
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)tearDown
{
    [self.activeUICallConversation.voiceChannel tearDown];
    [self.inactiveSyncCallConversation.voiceChannel tearDown];

    self.activeSyncCallConversation = nil;
    self.activeUICallConversation = nil;
    self.inactiveSyncCallConversation = nil;
    self.inactiveUICallConversation = nil;
    [self.sut tearDown];
    self.sut = nil;
    [super tearDown];
}


- (void)testThatItStoresTheCurrentCallConversation
{
    // given
    ZMConversation *uiConv = self.activeUICallConversation;
    ZMConversation *syncConv = self.activeSyncCallConversation;
    
    // when
    [self.sut setActiveCallSyncConversation:syncConv];
    
    // then
    
    XCTAssertEqual(self.sut.activeCallUIConversation, uiConv);
}

- (void)testThatItResetsTheCurrentCallConversation
{
    // given
    ZMConversation *syncConv = self.activeSyncCallConversation;
    
    // when
    [self.sut setActiveCallSyncConversation:syncConv];
    [self.sut setActiveCallSyncConversation:nil];

    // then
    
    XCTAssertNil(self.sut.activeCallUIConversation);
}

- (void)testThatItSetsThePersistentStoreMetaData_CTCallStateDialing
{
    // given
    ZMConversation *uiConv = self.activeUICallConversation;
    ZMConversation *syncConv = self.activeSyncCallConversation;
    [self.sut setActiveCallSyncConversation:syncConv];
    XCTAssertFalse(self.sut.hasStoredInterruptedCallConversation);

    id mockCall = [OCMockObject niceMockForClass:[CTCall class]];
    [(CTCall *)[[mockCall stub] andReturn:CTCallStateDialing] callState];
    
    // when
    self.sut.callEventHandler(mockCall);
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertTrue(uiConv.callDeviceIsActive);
    XCTAssertTrue(uiConv.hasLocalModificationsForCallDeviceIsActive);

    XCTAssertTrue(self.sut.hasStoredInterruptedCallConversation);
}


- (void)testThatItSetsThePersistentStoreMetaData_CTCallStateIncoming
{
    // given
    ZMConversation *uiConv = self.activeUICallConversation;
    ZMConversation *syncConv = self.activeSyncCallConversation;
    [self.sut setActiveCallSyncConversation:syncConv];
    XCTAssertFalse(self.sut.hasStoredInterruptedCallConversation);

    id mockCall = [OCMockObject niceMockForClass:[CTCall class]];
    [(CTCall *)[[mockCall stub] andReturn:CTCallStateIncoming] callState];
    
    // when
    self.sut.callEventHandler(mockCall);
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertTrue(uiConv.callDeviceIsActive);
    XCTAssertTrue(uiConv.hasLocalModificationsForCallDeviceIsActive);

    XCTAssertTrue(self.sut.hasStoredInterruptedCallConversation);
}

- (void)testThatItResetsThePersistentStoreMetaData_CTCallStateDisconnected_CallParticipants
{
    // given
    ZMConversation *uiConv = self.activeUICallConversation;
    ZMConversation *syncConv = self.activeSyncCallConversation;
    [self.syncMOC performGroupedBlockAndWait:^{
        [syncConv.voiceChannel addCallParticipant:[ZMUser insertNewObjectInManagedObjectContext:self.syncMOC]];
        [self.syncMOC saveOrRollback];
    }];
    [self.sut setActiveCallSyncConversation:syncConv];
    
    // the user has a call
    {
        // expect
        id mockCall = [OCMockObject niceMockForClass:[CTCall class]];
        [(CTCall *)[[mockCall stub] andReturn:CTCallStateDialing] callState];
        
        self.sut.callEventHandler(mockCall);
        WaitForAllGroupsToBeEmpty(0.5);
        
        XCTAssertTrue(self.sut.hasStoredInterruptedCallConversation);
        XCTAssertTrue(uiConv.hasLocalModificationsForCallDeviceIsActive);
        
        // the changes are synced with the BE
        // callDeviceIsActiveIsReset
        [self.syncMOC performGroupedBlockAndWait:^{
            [self.syncMOC.zm_callState mergeChangesFromState:[self.uiMOC.zm_callState createCopyAndResetHasChanges]];
            [syncConv resetHasLocalModificationsForCallDeviceIsActive];
        }];
        
        XCTAssertFalse(uiConv.hasLocalModificationsForCallDeviceIsActive);
    }
    
    // the call ends
    {
        // expect
        id mockCall = [OCMockObject niceMockForClass:[CTCall class]];
        [(CTCall *)[[mockCall stub] andReturn:CTCallStateDisconnected] callState];
        
        // when
        self.sut.callEventHandler(mockCall);
        WaitForAllGroupsToBeEmpty(0.5);
        
        // then
        XCTAssertTrue(uiConv.callDeviceIsActive);
        XCTAssertTrue(uiConv.hasLocalModificationsForCallDeviceIsActive);
        
        XCTAssertFalse(self.sut.hasStoredInterruptedCallConversation);
    }
}

- (void)testThatItResetsThePersistentStoreMetaData_CTCallStateDisconnected_NOCallParticipants
{
    // given
    ZMConversation *uiConv = self.activeUICallConversation;
    ZMConversation *syncConv = self.activeSyncCallConversation;
    __block ZMUser *otherUser;
    [self.syncMOC performGroupedBlockAndWait:^{
        otherUser = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        [syncConv.voiceChannel addCallParticipant:otherUser];
        [self.syncMOC saveOrRollback];
    }];
    [self.uiMOC.zm_callState mergeChangesFromState:[self.syncMOC.zm_callState createCopyAndResetHasChanges]];

    XCTAssertTrue(uiConv.callDeviceIsActive);
    XCTAssertFalse(uiConv.hasLocalModificationsForCallDeviceIsActive);
    XCTAssertEqual(uiConv.voiceChannel.participants.count, 1u);
    XCTAssertEqual(syncConv.voiceChannel.participants.count, 1u);
    
    [self.sut setActiveCallSyncConversation:syncConv];
    
    // the user has a call
    {
        // expect
        id mockCall = [OCMockObject niceMockForClass:[CTCall class]];
        [(CTCall *)[[mockCall stub] andReturn:CTCallStateDialing] callState];
        
        self.sut.callEventHandler(mockCall);
        WaitForAllGroupsToBeEmpty(0.5);
        
        XCTAssertTrue(self.sut.hasStoredInterruptedCallConversation);
        XCTAssertTrue(uiConv.hasLocalModificationsForCallDeviceIsActive);
        
        // the changes are synced with the BE
        // callDeviceIsActiveIsReset
        [self.syncMOC performGroupedBlockAndWait:^{
            [self.syncMOC.zm_callState mergeChangesFromState:[self.uiMOC.zm_callState createCopyAndResetHasChanges]];
            [syncConv resetHasLocalModificationsForCallDeviceIsActive];
        }];
        [self.uiMOC.zm_callState mergeChangesFromState:[self.syncMOC.zm_callState createCopyAndResetHasChanges]];

        XCTAssertFalse(uiConv.hasLocalModificationsForCallDeviceIsActive);
        XCTAssertTrue(uiConv.callDeviceIsActive);

        // the BE drops the call because the other user left
        [self.syncMOC performGroupedBlockAndWait:^{
            syncConv.callDeviceIsActive = NO,
            [syncConv.voiceChannel removeAllCallParticipants];
            [self.syncMOC saveOrRollback];
        }];
        [self.uiMOC.zm_callState mergeChangesFromState:[self.syncMOC.zm_callState createCopyAndResetHasChanges]];
        [self.uiMOC refreshObject:uiConv mergeChanges:YES];

        XCTAssertEqual(uiConv.voiceChannel.participants.count, 0u);
        XCTAssertEqual(syncConv.voiceChannel.participants.count, 0u);
    }
    
    // the call ends
    {
        // expect
        id mockCall = [OCMockObject niceMockForClass:[CTCall class]];
        [(CTCall *)[[mockCall stub] andReturn:CTCallStateDisconnected] callState];
        
        // when
        self.sut.callEventHandler(mockCall);
        WaitForAllGroupsToBeEmpty(0.5);
        
        // then we don't do anything
        XCTAssertFalse(uiConv.callDeviceIsActive);
        XCTAssertFalse(uiConv.hasLocalModificationsForCallDeviceIsActive);
        
        XCTAssertFalse(self.sut.hasStoredInterruptedCallConversation);
    }
}


- (void)testThatItResetsThePersistentStoreMetaData_CTCallStateDisconnected_NOCallParticipants_CallDeviceIsActive
{
    // given
    ZMConversation *uiConv = self.activeUICallConversation;
    ZMConversation *syncConv = self.activeSyncCallConversation;
    __block ZMUser *otherUser;
    [self.syncMOC performGroupedBlockAndWait:^{
        otherUser = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        [syncConv.voiceChannel addCallParticipant:otherUser];
        [self.syncMOC saveOrRollback];
    }];
    [self.uiMOC.zm_callState mergeChangesFromState:[self.syncMOC.zm_callState createCopyAndResetHasChanges]];
    
    XCTAssertTrue(uiConv.callDeviceIsActive);
    XCTAssertFalse(uiConv.hasLocalModificationsForCallDeviceIsActive);
    XCTAssertEqual(uiConv.voiceChannel.participants.count, 1u);
    XCTAssertEqual(syncConv.voiceChannel.participants.count, 1u);
    
    [self.sut setActiveCallSyncConversation:syncConv];
    
    // the user has a call
    {
        // expect
        id mockCall = [OCMockObject niceMockForClass:[CTCall class]];
        [(CTCall *)[[mockCall stub] andReturn:CTCallStateDialing] callState];
        
        self.sut.callEventHandler(mockCall);
        WaitForAllGroupsToBeEmpty(0.5);
        
        XCTAssertTrue(self.sut.hasStoredInterruptedCallConversation);
        XCTAssertTrue(uiConv.hasLocalModificationsForCallDeviceIsActive);
        
        // the changes are synced with the BE
        // callDeviceIsActiveIsReset
        [self.syncMOC performGroupedBlockAndWait:^{
            [self.syncMOC.zm_callState mergeChangesFromState:[self.uiMOC.zm_callState createCopyAndResetHasChanges]];
            [syncConv resetHasLocalModificationsForCallDeviceIsActive];
            [self.syncMOC saveOrRollback];
        }];
        [self.uiMOC.zm_callState mergeChangesFromState:[self.syncMOC.zm_callState createCopyAndResetHasChanges]];
        
        XCTAssertFalse(uiConv.hasLocalModificationsForCallDeviceIsActive);
        XCTAssertTrue(uiConv.callDeviceIsActive);
        
        // the BE drops the call because the other user left
        [self.syncMOC performGroupedBlockAndWait:^{
            // there is no self dictionary in the disconnected force idle event
            [syncConv.voiceChannel removeAllCallParticipants];
            [self.syncMOC saveOrRollback];
        }];
        [self.uiMOC refreshObject:uiConv mergeChanges:YES];
        
        XCTAssertTrue(uiConv.callDeviceIsActive);
        XCTAssertEqual(uiConv.voiceChannel.participants.count, 0u);
        XCTAssertEqual(syncConv.voiceChannel.participants.count, 0u);
    }
    
    // the call ends
    {
        // expect
        id mockCall = [OCMockObject niceMockForClass:[CTCall class]];
        [(CTCall *)[[mockCall stub] andReturn:CTCallStateDisconnected] callState];
        
        // when
        self.sut.callEventHandler(mockCall);
        WaitForAllGroupsToBeEmpty(0.5);
        
        // then we need to reset
        // we need to reset the local call state and call [voiceChannel leave]

        XCTAssertFalse(uiConv.callDeviceIsActive);
        XCTAssertTrue(uiConv.hasLocalModificationsForCallDeviceIsActive);
        
        XCTAssertFalse(self.sut.hasStoredInterruptedCallConversation);
    }
}

- (void)testThatItResetsTheStoredConversationWhenResettingTheActiveCallConversation
{
    // given
    [self.sut setActiveCallSyncConversation:self.activeSyncCallConversation];
    id mockCall = [OCMockObject niceMockForClass:[CTCall class]];
    [(CTCall *)[[mockCall stub] andReturn:CTCallStateDialing] callState];
    
    self.sut.callEventHandler(mockCall);
    WaitForAllGroupsToBeEmpty(0.5);

    XCTAssertNotNil(self.sut.activeCallUIConversation);
    XCTAssertTrue(self.sut.hasStoredInterruptedCallConversation);

    // when
    [self.sut setActiveCallSyncConversation:nil];
    WaitForAllGroupsToBeEmpty(0.5);

    // then
    XCTAssertNil(self.sut.activeCallUIConversation);
    XCTAssertFalse(self.sut.hasStoredInterruptedCallConversation);
}


- (void)testThatAfterReInitializingGSMCallHandlerItSetsTheActiveCallUIConversation
{
    // given
    [self.sut setActiveCallSyncConversation:self.activeSyncCallConversation];
    id mockCall = [OCMockObject niceMockForClass:[CTCall class]];
    [(CTCall *)[[mockCall stub] andReturn:CTCallStateDialing] callState];
    
    self.sut.callEventHandler(mockCall);
    WaitForAllGroupsToBeEmpty(0.5);
    
    XCTAssertNotNil(self.sut.activeCallUIConversation);
    XCTAssertTrue(self.sut.hasStoredInterruptedCallConversation);
    
    // when
    [self.sut tearDown];
    self.sut = [[ZMGSMCallHandler alloc] initWithUIManagedObjectContext:self.uiMOC
                                               syncManagedObjectContext:self.syncMOC
                                                        callStateLogger:self.mockCallStateLogger];
    
    // then
    XCTAssertNotNil(self.sut.activeCallUIConversation);
    XCTAssertTrue(self.sut.hasStoredInterruptedCallConversation);
}

- (void)testThatItDoesNotLeaveTheCallWhenTheSyncIsNotFinished_NoCallParticipants
{
    // given
    [self.sut setActiveCallSyncConversation:self.activeSyncCallConversation];
    
    // when
    id mockCallCenter = [OCMockObject niceMockForClass:[CTCallCenter class]];
    [[[mockCallCenter stub] andReturn:[NSSet set]] currentCalls];
    
    id mockCall1 = [OCMockObject niceMockForClass:[CTCall class]];
    [(CTCall *)[[mockCall1 stub] andReturn:CTCallStateDialing] callState];
    
    self.sut.callEventHandler(mockCall1);
    WaitForAllGroupsToBeEmpty(0.5);
    
    [self.sut tearDown];
    self.sut = [[ZMGSMCallHandler alloc] initWithUIManagedObjectContext:self.uiMOC
                                               syncManagedObjectContext:self.syncMOC
                                                        callStateLogger:self.mockCallStateLogger
                                                             callCenter:mockCallCenter];
    
    XCTAssertNotNil(self.sut.activeCallUIConversation);
    XCTAssertTrue(self.sut.hasStoredInterruptedCallConversation);
    
    
    // when
    id mockCall2 = [OCMockObject niceMockForClass:[CTCall class]];
    [(CTCall *)[[mockCall2 stub] andReturn:CTCallStateDisconnected] callState];
    
    self.sut.callEventHandler(mockCall2);
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertTrue(self.sut.hasStoredInterruptedCallConversation);
    XCTAssertTrue(self.activeUICallConversation.callDeviceIsActive);
    
    // and when
    [[NSNotificationCenter defaultCenter] postNotificationName:ZMApplicationDidEnterEventProcessingStateNotificationName object:nil];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertFalse(self.sut.hasStoredInterruptedCallConversation);
    XCTAssertFalse(self.activeUICallConversation.callDeviceIsActive);
}

- (void)testThatItDoesNotLeaveTheCallWhenTheSyncIsFinishedButThereIsStillAnOngoingCall_NoCallParticipants
{
    // given
    [self.sut setActiveCallSyncConversation:self.activeSyncCallConversation];
    
    // when
    id mockCall1 = [OCMockObject niceMockForClass:[CTCall class]];
    [(CTCall *)[[mockCall1 stub] andReturn:CTCallStateDialing] callState];
    
    id mockCall2 = [OCMockObject niceMockForClass:[CTCall class]];
    [(CTCall *)[[mockCall2 stub] andReturn:CTCallStateDisconnected] callState];
    
    id mockCallCenter = [OCMockObject niceMockForClass:[CTCallCenter class]];
    [[[mockCallCenter stub] andReturn:[NSSet setWithObject:mockCall2]] currentCalls];
    
    self.sut.callEventHandler(mockCall1);
    WaitForAllGroupsToBeEmpty(0.5);
    
    [self.sut tearDown];
    self.sut = [[ZMGSMCallHandler alloc] initWithUIManagedObjectContext:self.uiMOC
                                               syncManagedObjectContext:self.syncMOC
                                                        callStateLogger:self.mockCallStateLogger
                                                             callCenter:mockCallCenter];
    
    XCTAssertNotNil(self.sut.activeCallUIConversation);
    XCTAssertTrue(self.sut.hasStoredInterruptedCallConversation);
    
    
    // when
    self.sut.callEventHandler(mockCall2);
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertTrue(self.sut.hasStoredInterruptedCallConversation);
    XCTAssertTrue(self.activeUICallConversation.callDeviceIsActive);
    
    // and when
    [[NSNotificationCenter defaultCenter] postNotificationName:ZMApplicationDidEnterEventProcessingStateNotificationName object:nil];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertTrue(self.sut.hasStoredInterruptedCallConversation);
    XCTAssertTrue(self.activeUICallConversation.callDeviceIsActive);

}

@end
