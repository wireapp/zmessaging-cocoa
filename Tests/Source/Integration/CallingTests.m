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
@import ZMCDataModel;
@import avs;

#import "CallingTests.h"
#import "VoiceChannelV2+CallFlow.h"
#import <zmessaging/zmessaging-Swift.h>
#import "ZMGSMCallHandler.h"

@implementation TestWindowObserver

- (instancetype)init
{
    self = [super init];
    if(self) {
        self.notifications = [NSMutableArray array];
    }
    return self;
}

- (void)conversationWindowDidChange:(MessageWindowChangeInfo *)changeInfo
{
    if(self.notificationHandler) {
        self.notificationHandler(changeInfo);
    }
    
    [self.window.conversation setVisibleWindowFromMessage:self.window.conversation.messages.firstObject toMessage:self.window.conversation.messages.lastObject];
    [self.notifications addObject:changeInfo];
}

- (void)registerOnConversation:(ZMConversation *)conversation;
{
    NSAssert(self.observerToken == nil, @"Registered twice??");
    self.window = [conversation conversationWindowWithSize:20];
    self.observerToken = [MessageWindowChangeInfo addObserver:self forWindow:self.window];
}


@end


@implementation V2VoiceChannelParticipantTestObserver

- (instancetype)init
{
    self = [super init];
    
    if (self) {
        _changes = [NSMutableArray array];
    }
    
    return self;
}

- (void)voiceChannelParticipantsDidChange:(SetChangeInfo *)changeInfo
{
    [self.changes addObject:changeInfo];
}

@end


@implementation V2CallStateChange

@end


@implementation V2CallStateTestObserver

- (instancetype)init
{
    self = [super init];
    
    if (self) {
        _changes = [NSMutableArray array];
    }
    
    return self;
}

- (void)callCenterDidChangeVoiceChannelState:(VoiceChannelV2State)voiceChannelState conversation:(ZMConversation *)conversation
{
    V2CallStateChange *change = [[V2CallStateChange alloc] init];
    change.state = voiceChannelState;
    change.conversation = conversation;
    
    [self.changes addObject:change];
}

@end


@implementation CallingTests

- (void)setUp {
    [super setUp];
    
    self.windowObserver = [[TestWindowObserver alloc] init];
    
}

- (void)tearDown {
    self.windowObserver = nil;
    WaitForAllGroupsToBeEmpty(0.5);
    [self tearDownVoiceChannelForConversation:self.conversationUnderTest];
    [ZMCallTimer resetTestCallTimeout];
    self.useGroupConversation = NO;
    [self.gsmCallHandler setActiveCallSyncConversation:nil];
    [super tearDown];
}

- (MockConversation *)mockConversationUnderTest
{
    if (self.useGroupConversation) {
        return self.groupConversation;
    }
    return self.selfToUser2Conversation;
}

- (ZMConversation *)conversationUnderTest {
    return [self conversationForMockConversation:self.mockConversationUnderTest];
}

- (void)tearDownVoiceChannelForConversation:(ZMConversation *)conversation
{
    ZMConversation *syncConv = (id)[self.userSession.syncManagedObjectContext existingObjectWithID:conversation.objectID error:nil];
    [syncConv.voiceChannelRouter.v2 tearDown];
}

- (BOOL)lastRequestContainsSelfStateJoined
{
    return [self lastRequestContainsSelfStateJoinedWithCauseSuspended:NO];
}
- (BOOL)lastRequestContainsSelfStateJoinedWithCauseSuspended:(BOOL)causeIsIntertupted
{
    ZMTransportRequest *joinRequest = [self.mockTransportSession.receivedRequests firstObjectMatchingWithBlock:^BOOL(ZMTransportRequest *request) {
        BOOL rightPath = [request.path hasPrefix:@"/conversations/"] && [request.path hasSuffix:@"/call/state"];
        if (!rightPath) {
            return NO;
        }
        NSDictionary *selfDict = [[request.payload asDictionary] optionalDictionaryForKey:@"self"];
        BOOL stateJoined = [[selfDict optionalStringForKey:@"state"] isEqualToString:@"joined"];
        if (causeIsIntertupted) {
            BOOL isInterrupted = [[selfDict optionalNumberForKey:@"suspended"] boolValue];
            BOOL hasCauseSet = [[[request.payload asDictionary] optionalStringForKey:@"cause"] isEqualToString:@"interrupted"];
            return rightPath && stateJoined && isInterrupted && hasCauseSet;
        }
        return rightPath && stateJoined;
    }];
    
    return joinRequest != nil;
}

- (BOOL)lastRequestContainsSelfStateIdle
{
    return [self lastRequestContainsSelfStateIdleWithIsIgnored:NO];
}

- (BOOL)lastRequestContainsSelfStateIdleWithIsIgnored:(BOOL)isIgnored
{
    ZMTransportRequest *idleRequest = [self.mockTransportSession.receivedRequests firstObjectMatchingWithBlock:^BOOL(ZMTransportRequest *request) {
        BOOL rightPath = [request.path hasPrefix:@"/conversations/"] && [request.path hasSuffix:@"/call/state"];
        if (!rightPath) {
            return NO;
        }
        NSDictionary *selfDict = [[request.payload asDictionary] optionalDictionaryForKey:@"self"];

        BOOL stateIdle = [[selfDict optionalStringForKey:@"state"] isEqualToString:@"idle"];
        BOOL didIncludeIgnored = [[selfDict optionalNumberForKey:@"ignored"] boolValue];
        return rightPath && stateIdle && (didIncludeIgnored == isIgnored);
    }];
    
    return idleRequest != nil;
    
}

- (void)selfJoinCall
{
    [self.userSession enqueueChanges:^{
        [self.conversationUnderTest.voiceChannelRouter.v2 joinWithVideo:NO];
    }];
}

- (void)selfDropCall
{
    [self.userSession enqueueChanges:^{
        [self.conversationUnderTest.voiceChannelRouter.v2 leave];
    }];
}

- (void)selfLeavesConversation
{
    [self.userSession enqueueChanges:^{
        [self.conversationUnderTest removeParticipant:[self userForMockUser:self.selfUser]];
    }];
}

- (void)otherDropsCall
{
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        NOT_USED(session);
        [self.mockConversationUnderTest removeUserFromCall:self.user2];
    }];
}

- (void)otherLeavesUnansweredCall
{
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        NOT_USED(session);
        [self.mockConversationUnderTest callEndedEventFromUser:self.user2 selfUser:self.selfUser];
    }];
}

- (ZMTransportRequest *)selfJoinCallButDelayRequest
{
    __block ZMTransportRequest *delayedRequest = nil;
    
    self.mockTransportSession.responseGeneratorBlock = ^ZMTransportResponse *(ZMTransportRequest *request) {
        
        NSString *expectedString = [NSString stringWithFormat:@"/conversations/%@/call/state", self.conversationUnderTest.remoteIdentifier.transportString];
        if(request.method == ZMMethodPUT && [request.path isEqualToString:expectedString]) {
            delayedRequest = request;
            return ResponseGenerator.ResponseNotCompleted;
        }
        return nil;
    };
    
    [self selfJoinCall];
    WaitForAllGroupsToBeEmpty(0.5);
    
    XCTAssertNotNil(delayedRequest);
    self.mockTransportSession.responseGeneratorBlock = nil;
    
    return delayedRequest;
}


- (void)otherJoinCall
{
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        NOT_USED(session);
        [self.mockConversationUnderTest addUserToCall:self.user2];
    }];
}

- (void)usersJoinGroupCall:(NSOrderedSet *)users
{
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        NOT_USED(session);
        for (MockUser *user in users) {
            if (user != self.selfUser) {
                [self.mockConversationUnderTest addUserToCall:user];
            }
        }
    }];
}

- (void)usersLeaveGroupCall:(NSOrderedSet *)users
{
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        NOT_USED(session);
        for (MockUser *user in users) {
            if (user != self.selfUser) {
                [self.mockConversationUnderTest removeUserFromCall:user];
            }
        }
    }];
}

@end




@implementation CallingTests (General)

- (void)testJoiningAndLeavingAnEmptyVoiceChannel
{
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    
    V2CallStateTestObserver *observer = [[V2CallStateTestObserver alloc] init];
    id token = [WireCallCenterV2 addVoiceChannelStateObserverWithObserver:observer context:self.uiMOC];
    
    // when
    {
        [self selfJoinCall];
        WaitForAllGroupsToBeEmpty(0.5);
        
        // then
        XCTAssertTrue([self lastRequestContainsSelfStateJoined]);
        [self.mockTransportSession resetReceivedRequests];
        
        XCTAssertEqual(observer.changes.count, 1u);
        XCTAssertEqual(observer.changes.firstObject.state, VoiceChannelV2StateOutgoingCall);
    }
    
    [self.mockTransportSession resetReceivedRequests];
    
    // when
    {
        [self selfDropCall];
        WaitForAllGroupsToBeEmpty(0.5);
        
        // then
        XCTAssertEqual(observer.changes.count, 2u);
        XCTAssertTrue([self lastRequestContainsSelfStateIdle]);
        XCTAssertEqual(observer.changes.lastObject.state, VoiceChannelV2StateNoActiveUsers);

    }
    
    [WireCallCenterV2 removeObserverWithToken:token];
}


- (void)testThatItSendsOutAllExpectedNotificationsWhenSelfUserCalls
{
    // no active users -> self is calling -> self connected to active channel -> no active users
    
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    ZMConversation *oneToOneConversation = self.conversationUnderTest;
        
    V2CallStateTestObserver *stateObserver = [[V2CallStateTestObserver alloc] init];
    V2VoiceChannelParticipantTestObserver *participantObserver = [[V2VoiceChannelParticipantTestObserver alloc] init];
    
    id stateToken = [WireCallCenterV2 addVoiceChannelStateObserverWithObserver:stateObserver context:self.uiMOC];
    id participantToken = [WireCallCenterV2 addVoiceChannelParticipantObserverWithObserver:participantObserver forConversation:oneToOneConversation context:self.uiMOC];
    
    // (1) self calling & backend acknowledges
    //
    // when
    [self selfJoinCall];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(stateObserver.changes.count, 1u);
    XCTAssertEqual(stateObserver.changes.lastObject.state, VoiceChannelV2StateOutgoingCall);
    XCTAssertEqual(participantObserver.changes.count, 0u);
    // (2) other party joins
    //
    // when
    [self otherJoinCall];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(participantObserver.changes.count, 1u);
    SetChangeInfo *partInfo2 = participantObserver.changes.lastObject;
    XCTAssertEqualObjects(partInfo2.insertedIndexes, [NSIndexSet indexSetWithIndex:0]);
    XCTAssertEqualObjects(partInfo2.updatedIndexes, [NSIndexSet indexSet]);
    XCTAssertEqualObjects(partInfo2.deletedIndexes, [NSIndexSet indexSet]);
    XCTAssertEqualObjects(partInfo2.movedIndexPairs, @[]);

    // (3) flow aquired
    //
    // when
    [self simulateMediaFlowEstablishedOnConversation:oneToOneConversation];
    [self simulateParticipantsChanged:@[self.user2] onConversation:oneToOneConversation];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(stateObserver.changes.count, 3u);
    XCTAssertEqual(stateObserver.changes.lastObject.state, VoiceChannelV2StateSelfConnectedToActiveChannel);
    
    XCTAssertEqual(participantObserver.changes.count, 2u);
    SetChangeInfo *partInfo3 = participantObserver.changes.lastObject;
    XCTAssertEqualObjects(partInfo3.insertedIndexes, [NSIndexSet indexSet]);
    XCTAssertEqualObjects(partInfo3.updatedIndexes, [NSIndexSet indexSetWithIndex:0]);
    XCTAssertEqualObjects(partInfo3.deletedIndexes, [NSIndexSet indexSet]);
    XCTAssertEqualObjects(partInfo3.movedIndexPairs, @[]);

    // (4) self user leaves
    //
    // when
    [self selfDropCall];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(stateObserver.changes.count, 4u);
    XCTAssertEqual(stateObserver.changes.lastObject.state, VoiceChannelV2StateNoActiveUsers);
    
    SetChangeInfo *partInfo4 = participantObserver.changes.lastObject;
    XCTAssertEqualObjects(partInfo4.insertedIndexes, [NSIndexSet indexSet]);
    XCTAssertEqualObjects(partInfo4.updatedIndexes, [NSIndexSet indexSet]);
    XCTAssertEqualObjects(partInfo4.deletedIndexes, [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, 1)]);
    XCTAssertEqualObjects(partInfo4.movedIndexPairs, @[]);
    
    [WireCallCenterV2 removeObserverWithToken:stateToken];
    [WireCallCenterV2 removeObserverWithToken:participantToken];
}

- (void)testThatItSendsOutAllExpectedNotificationsWhenOtherUserCalls
{
    ///3333333
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    ZMConversation * NS_VALID_UNTIL_END_OF_SCOPE oneToOneConversation = self.conversationUnderTest;
    
    V2CallStateTestObserver *stateObserver = [[V2CallStateTestObserver alloc] init];
    V2VoiceChannelParticipantTestObserver *participantObserver = [[V2VoiceChannelParticipantTestObserver alloc] init];
    
    id stateToken = [WireCallCenterV2 addVoiceChannelStateObserverWithObserver:stateObserver context:self.uiMOC];
    id participantToken = [WireCallCenterV2 addVoiceChannelParticipantObserverWithObserver:participantObserver forConversation:oneToOneConversation context:self.uiMOC];

    // (1) other user joins
    // when
    [self otherJoinCall];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(stateObserver.changes.count, 1u);
    XCTAssertEqual(stateObserver.changes.lastObject.state, VoiceChannelV2StateIncomingCall);
    
    // (2) we join
    // when
    [self selfJoinCall];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    {
        XCTAssertEqual(stateObserver.changes.count, 2u);
        XCTAssertEqual(stateObserver.changes.lastObject.state, VoiceChannelV2StateSelfIsJoiningActiveChannel);
        [participantObserver.changes removeAllObjects];
    }
    
    // (3) flow aquired
    //
    // when
    [self simulateMediaFlowEstablishedOnConversation:self.conversationUnderTest];
    [self simulateParticipantsChanged:@[self.user2] onConversation:self.conversationUnderTest];
    WaitForAllGroupsToBeEmpty(0.5);

    // then
    {
        XCTAssertEqual(stateObserver.changes.count, 3u);
        XCTAssertEqual(stateObserver.changes.lastObject.state, VoiceChannelV2StateSelfConnectedToActiveChannel);
        XCTAssertEqual(participantObserver.changes.count, 1u); // we notify that user connected
    }
    
    // (4) the other user leaves. The backend tells us we are both idle
    
    [self otherDropsCall];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    {
        XCTAssertEqual(stateObserver.changes.count, 5u); // goes through transfer state before disconnect
        XCTAssertEqual(stateObserver.changes.lastObject.state, VoiceChannelV2StateNoActiveUsers);
    }
    
    [WireCallCenterV2 removeObserverWithToken:stateToken];
    [WireCallCenterV2 removeObserverWithToken:participantToken];
}

- (void)testThatItCreatesASystemMessageWhenWeMissedACall
{
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    ZMConversation * oneToOneConversation = self.conversationUnderTest;
    [self otherJoinCall];
    WaitForAllGroupsToBeEmpty(0.5);
    NSUInteger messageCount = oneToOneConversation.messages.count;
 
    // when
    {
        [self otherLeavesUnansweredCall];
        WaitForAllGroupsToBeEmpty(0.5);
    }
    
    // then
    // we receive a systemMessage that we missed a call
    {
        XCTAssertEqual(oneToOneConversation.messages.count, messageCount+1u);
        id<ZMConversationMessage> systemMessage = oneToOneConversation.messages.lastObject;
        XCTAssertNotNil(systemMessage.systemMessageData);
        XCTAssertEqual(systemMessage.systemMessageData.systemMessageType, ZMSystemMessageTypeMissedCall);
    }
}


- (void)testThatItDoesNotCreateASystemMessageWhenTheCallIsEndedWithoutBeingMissed
{
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    WaitForAllGroupsToBeEmpty(0.5);

    ZMConversation *oneToOneConversation = self.conversationUnderTest;
    NSUInteger messageCount = oneToOneConversation.messages.count;
    
    // when
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        NOT_USED(session);
        [self.mockConversationUnderTest addUserToCall:self.selfUser];
        [self.mockConversationUnderTest addUserToCall:self.user2];
        [self.mockConversationUnderTest callEndedEventFromUser:self.user2 selfUser:self.selfUser];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
        
    
    // we DO NOT receive a systemMessage
    XCTAssertEqual(oneToOneConversation.messages.count, messageCount);
}


- (void)testThatItSendsANotificationWhenWeIgnoreACall
{
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    WaitForAllGroupsToBeEmpty(0.5);

    ZMConversation *oneToOneConversation = self.conversationUnderTest;
    
    V2CallStateTestObserver *stateObserver = [[V2CallStateTestObserver alloc] init];
    id stateToken = [WireCallCenterV2 addVoiceChannelStateObserverWithObserver:stateObserver context:self.uiMOC];

    // (1) other user joins
    // when
    [self otherJoinCall];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(stateObserver.changes.count, 1u);
    XCTAssertEqual(stateObserver.changes.lastObject.state, VoiceChannelV2StateIncomingCall);
    
    // (2) we ignore
    // when
    [self.userSession performChanges:^{
        [oneToOneConversation.voiceChannelRouter.v2 ignore];
    }];
    WaitForAllGroupsToBeEmpty(0.5);

    // then
    XCTAssertEqual(stateObserver.changes.count, 2u);
    XCTAssertEqual(stateObserver.changes.lastObject.state, VoiceChannelV2StateNoActiveUsers);

    [WireCallCenterV2 removeObserverWithToken:stateToken];
    [self tearDownVoiceChannelForConversation:oneToOneConversation];
}

- (void)testThatItDoesNotAutomaticallyIgnoreASecondIncomingCall
{
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    WaitForAllGroupsToBeEmpty(0.5);
//    ZMConversation *conv = [self conversationForMockConversation:self.selfToUser2Conversation];
//    (void)conv.callParticipants.count;
    
    V2CallStateTestObserver *stateObserver = [[V2CallStateTestObserver alloc] init];
    id stateToken = [WireCallCenterV2 addVoiceChannelStateObserverWithObserver:stateObserver context:self.uiMOC];

    // (1) other user joins
    // when
    [self otherJoinCall];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(stateObserver.changes.count, 1u);
    XCTAssertEqual(stateObserver.changes.lastObject.state, VoiceChannelV2StateIncomingCall);

    // (2) another user joins another conversation
    // when
    [self.mockTransportSession performRemoteChanges:^(ZM_UNUSED id session) {
        NOT_USED(session);
        [self.selfToUser1Conversation addUserToCall:self.user2];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    ZMConversation *secondCallingConversation = [self conversationForMockConversation:self.selfToUser2Conversation];
    XCTAssertEqual(secondCallingConversation.voiceChannel.state, VoiceChannelV2StateIncomingCall);
    
    [WireCallCenterV2 removeObserverWithToken:stateToken];
    [self tearDownVoiceChannelForConversation:[self conversationForMockConversation:self.selfToUser1Conversation]];
}

- (void)testThatItSendsANotificationIfIgnoringACallAndImmediatelyAcceptingIt
{
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    ZMConversation *oneToOneConversation = self.conversationUnderTest;
    V2CallStateTestObserver *stateObserver = [[V2CallStateTestObserver alloc] init];
    id stateToken = [WireCallCenterV2 addVoiceChannelStateObserverWithObserver:stateObserver context:self.uiMOC];

    // (1) other user joins
    // when
    [self otherJoinCall];
    WaitForAllGroupsToBeEmpty(0.5);
    [stateObserver.changes removeAllObjects];
    
    // (2) we ignore
    // when
    [self.userSession performChanges:^{
        [oneToOneConversation.voiceChannelRouter.v2 ignore];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(stateObserver.changes.count, 1u);
    XCTAssertEqual(stateObserver.changes.lastObject.state, VoiceChannelV2StateNoActiveUsers);
    
    // when
    [self selfJoinCall];
    WaitForAllGroupsToBeEmpty(0.5);

    // then
    XCTAssertEqual(stateObserver.changes.count, 2u);
    XCTAssertEqual(stateObserver.changes.lastObject.state, VoiceChannelV2StateSelfIsJoiningActiveChannel);
    
    [WireCallCenterV2 removeObserverWithToken:stateToken];
}

@end



@implementation CallingTests (CallState)


- (void)registerWindowObserver
{
    [self.windowObserver registerOnConversation:self.conversationUnderTest];
}

- (void)testThatWeAreIn_JoiningState_AfterJoiningAnd_Not_ActivatingTheFlow_OutgoingCall_Group
{
    
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    self.useGroupConversation = YES;
    
    ZMConversation *conversation = self.conversationUnderTest;
    V2CallStateTestObserver *stateObserver = [[V2CallStateTestObserver alloc] init];
    id stateToken = [WireCallCenterV2 addVoiceChannelStateObserverWithObserver:stateObserver context:self.uiMOC];
    
    // when
    [self selfJoinCall];
    WaitForAllGroupsToBeEmpty(0.5);
    
    XCTAssertTrue([self lastRequestContainsSelfStateJoined]);
    
    [self otherJoinCall];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(conversation.voiceChannel.state, VoiceChannelV2StateSelfIsJoiningActiveChannel);
    XCTAssertEqual(stateObserver.changes.lastObject.state, VoiceChannelV2StateSelfIsJoiningActiveChannel);
    
    [WireCallCenterV2 removeObserverWithToken:stateToken];
}

- (void)testThatWeAreInThe_JoiningState_AfterJoiningAnd_Not_ActivatingTheFlow_IncomingCall_OneOnOne
{
    
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    
    ZMConversation *conversation = self.conversationUnderTest;
    V2CallStateTestObserver *stateObserver = [[V2CallStateTestObserver alloc] init];
    id stateToken = [WireCallCenterV2 addVoiceChannelStateObserverWithObserver:stateObserver context:self.uiMOC];
    
    // when
    [self otherJoinCall];
    WaitForAllGroupsToBeEmpty(0.5);
    
    [self selfJoinCall];
    WaitForAllGroupsToBeEmpty(0.5);
    
    XCTAssertTrue([self lastRequestContainsSelfStateJoined]);
    
    // then
    XCTAssertEqual(conversation.voiceChannel.state, VoiceChannelV2StateSelfIsJoiningActiveChannel);
    XCTAssertEqual(stateObserver.changes.count, 2u);
    XCTAssertEqual(stateObserver.changes.lastObject.state, VoiceChannelV2StateSelfIsJoiningActiveChannel);
    
    [WireCallCenterV2 removeObserverWithToken:stateToken];
}

- (void)testThatWeAreInThe_JoiningState_AfterJoiningAnd_Not_ActivatingTheFlow_IncomingCall_Group
{
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    self.useGroupConversation= YES;
    
    ZMConversation *conversation = self.conversationUnderTest;
    V2CallStateTestObserver *stateObserver = [[V2CallStateTestObserver alloc] init];
    id stateToken = [WireCallCenterV2 addVoiceChannelStateObserverWithObserver:stateObserver context:self.uiMOC];
    
    // when
    [self otherJoinCall];
    WaitForAllGroupsToBeEmpty(0.5);
    
    XCTAssertEqual(stateObserver.changes.count, 1u);
    XCTAssertEqual(stateObserver.changes.lastObject.state, VoiceChannelV2StateIncomingCall);

    [self selfJoinCall];
    WaitForAllGroupsToBeEmpty(0.5);
    
    XCTAssertTrue([self lastRequestContainsSelfStateJoined]);
    
    // then
    XCTAssertEqual(conversation.voiceChannel.state, VoiceChannelV2StateSelfIsJoiningActiveChannel);
    XCTAssertEqual(stateObserver.changes.count, 2u);
    XCTAssertEqual(stateObserver.changes.lastObject.state, VoiceChannelV2StateSelfIsJoiningActiveChannel);
    
    [WireCallCenterV2 removeObserverWithToken:stateToken];
}

- (void)testThatWeAreInThe_ConnectedState_AfterJoiningAndActivatingTheFlow
{
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    
    ZMConversation *conversation = self.conversationUnderTest;
    V2CallStateTestObserver *stateObserver = [[V2CallStateTestObserver alloc] init];
    id stateToken = [WireCallCenterV2 addVoiceChannelStateObserverWithObserver:stateObserver context:self.uiMOC];

    // when
    [self selfJoinCall];
    WaitForAllGroupsToBeEmpty(0.5);
    
    XCTAssertTrue([self lastRequestContainsSelfStateJoined]);
    
    [self otherJoinCall];
    WaitForAllGroupsToBeEmpty(0.5);
    XCTAssertEqual(conversation.voiceChannel.state, VoiceChannelV2StateSelfIsJoiningActiveChannel);

    [self simulateMediaFlowEstablishedOnConversation:conversation];
    [self simulateParticipantsChanged:@[self.user2] onConversation:conversation];
    WaitForAllGroupsToBeEmpty(0.5);
    
    //then
    VoiceChannelV2State state = conversation.voiceChannel.state;
    XCTAssertEqual(state, VoiceChannelV2StateSelfConnectedToActiveChannel);
    
    XCTAssertEqual(stateObserver.changes.count, 3u);
    XCTAssertEqual(stateObserver.changes.lastObject.state, VoiceChannelV2StateSelfConnectedToActiveChannel);

    [WireCallCenterV2 removeObserverWithToken:stateToken];
}

- (void)testThatWhenWeAreConnectedAndTheOtherUserDropsTheCallWeAreInNotConnectedState {
    
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    
    ZMConversation *conversation = self.conversationUnderTest;
    V2CallStateTestObserver *stateObserver = [[V2CallStateTestObserver alloc] init];
    id stateToken = [WireCallCenterV2 addVoiceChannelStateObserverWithObserver:stateObserver context:self.uiMOC];

    [self selfJoinCall];
    WaitForAllGroupsToBeEmpty(0.5);
    
    XCTAssertTrue([self lastRequestContainsSelfStateJoined]);
    
    [self otherJoinCall];
    WaitForAllGroupsToBeEmpty(0.5);
    
    [self simulateParticipantsChanged:@[self.user2] onConversation:conversation];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // when
    [self selfDropCall];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(conversation.voiceChannel.state, VoiceChannelV2StateNoActiveUsers);
    XCTAssertEqual(stateObserver.changes.count, 3u);
    XCTAssertEqual(stateObserver.changes.lastObject.state, VoiceChannelV2StateNoActiveUsers);

    [WireCallCenterV2 removeObserverWithToken:stateToken];
}


- (void)testThatWeCanMakeTwoCallsInARow {
    
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    
    ZMConversation *conversation = self.conversationUnderTest;
    V2CallStateTestObserver *stateObserver = [[V2CallStateTestObserver alloc] init];
    id stateToken = [WireCallCenterV2 addVoiceChannelStateObserverWithObserver:stateObserver context:self.uiMOC];

    { // Call 1
        [self.mockTransportSession resetReceivedRequests];
        [self selfJoinCall];
        WaitForAllGroupsToBeEmpty(0.5);
        
        XCTAssertTrue([self lastRequestContainsSelfStateJoined]);
        
        [self otherJoinCall];
        WaitForAllGroupsToBeEmpty(0.5);

        [self simulateParticipantsChanged:@[self.user2] onConversation:self.conversationUnderTest];
        WaitForAllGroupsToBeEmpty(0.5);
        
        // when
        [self selfDropCall];
        WaitForAllGroupsToBeEmpty(0.5);
        
        // then
        XCTAssertEqual(conversation.voiceChannel.state, VoiceChannelV2StateNoActiveUsers);
        XCTAssertEqual(stateObserver.changes.count, 3u);
        XCTAssertEqual(stateObserver.changes.lastObject.state, VoiceChannelV2StateNoActiveUsers);
    }

    [self.mockTransportSession resetReceivedRequests];
    stateObserver.changes = [NSMutableArray array];

    { // Call 2
        // when
        [self selfJoinCall];
        WaitForAllGroupsToBeEmpty(0.5);
        
        XCTAssertTrue([self lastRequestContainsSelfStateJoined]);

        [self otherJoinCall];
        WaitForAllGroupsToBeEmpty(0.5);

        [self simulateMediaFlowEstablishedOnConversation:self.conversationUnderTest];
        [self simulateParticipantsChanged:@[self.user2] onConversation:self.conversationUnderTest];
        WaitForAllGroupsToBeEmpty(0.5);
        
        // then
        XCTAssertEqual(conversation.voiceChannel.state, VoiceChannelV2StateSelfConnectedToActiveChannel);
        XCTAssertEqual(stateObserver.changes.count, 3u);
        XCTAssertEqual(stateObserver.changes.lastObject.state, VoiceChannelV2StateSelfConnectedToActiveChannel);
    }
    
    [WireCallCenterV2 removeObserverWithToken:stateToken];
}


- (void)testThatWeCanMakeTwoCallsInARowWithADelayOnTheNetworkOnTheFirstJoin {
    
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    
    ZMConversation *conversation = self.conversationUnderTest;
    V2CallStateTestObserver *stateObserver = [[V2CallStateTestObserver alloc] init];
    id stateToken = [WireCallCenterV2 addVoiceChannelStateObserverWithObserver:stateObserver context:self.uiMOC];

    { // Call 1
        
        ZMTransportRequest *request = [self selfJoinCallButDelayRequest];
        WaitForAllGroupsToBeEmpty(0.5);
        
        [self otherJoinCall];
        WaitForAllGroupsToBeEmpty(0.5);

        [self simulateMediaFlowEstablishedOnConversation:self.conversationUnderTest];
        [self simulateParticipantsChanged:@[self.user2] onConversation:self.conversationUnderTest];
        WaitForAllGroupsToBeEmpty(0.5);
        
        [self.mockTransportSession completePreviouslySuspendendRequest:request];
        WaitForAllGroupsToBeEmpty(0.5);
        
        XCTAssertTrue([self lastRequestContainsSelfStateJoined]);
        
        // then
        XCTAssertEqual(conversation.voiceChannel.state, VoiceChannelV2StateSelfConnectedToActiveChannel);
        XCTAssertEqual(stateObserver.changes.count, 3u);
        XCTAssertEqual(stateObserver.changes.lastObject.state, VoiceChannelV2StateSelfConnectedToActiveChannel);
        
        // and when
        [self.mockTransportSession resetReceivedRequests];

        [self selfDropCall];
        WaitForAllGroupsToBeEmpty(0.5);
        [self simulateMediaFlowReleasedOnConversation:self.conversationUnderTest];
        [self simulateParticipantsChanged:@[] onConversation:self.conversationUnderTest];
        WaitForAllGroupsToBeEmpty(0.5);
        
        XCTAssertTrue([self lastRequestContainsSelfStateIdle]);
        
        // then
        XCTAssertEqual(conversation.voiceChannel.state, VoiceChannelV2StateNoActiveUsers);
        XCTAssertEqual(stateObserver.changes.count, 4u);
        XCTAssertEqual(stateObserver.changes.lastObject.state, VoiceChannelV2StateNoActiveUsers);
        
    }
    
    [stateObserver.changes removeAllObjects];
    
    { // Call 2
        [self otherJoinCall];
        WaitForAllGroupsToBeEmpty(0.5);
        
        // when
        [self.mockTransportSession resetReceivedRequests];
        [stateObserver.changes removeAllObjects];
        
        [self selfJoinCall];
        WaitForAllGroupsToBeEmpty(0.5);
        
        XCTAssertEqual(stateObserver.changes.count, 1u);
        XCTAssertEqual(stateObserver.changes.lastObject.state, VoiceChannelV2StateSelfIsJoiningActiveChannel);

        [self simulateMediaFlowEstablishedOnConversation:self.conversationUnderTest];
        [self simulateParticipantsChanged:@[self.user2] onConversation:self.conversationUnderTest];
        WaitForAllGroupsToBeEmpty(0.5);
        
        XCTAssertTrue([self lastRequestContainsSelfStateJoined]);
        
        // then
        XCTAssertEqual(stateObserver.changes.count, 2u);
        XCTAssertEqual(stateObserver.changes.lastObject.state, VoiceChannelV2StateSelfConnectedToActiveChannel);
    }
    
    [WireCallCenterV2 removeObserverWithToken:stateToken];
}

- (void)testThatWeCanMakeTwoCallsInARowWithADelayOnTheSaveOnOtherUserJoin {
    
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    
    ZMConversation *conversation = self.conversationUnderTest;
    V2CallStateTestObserver *stateObserver = [[V2CallStateTestObserver alloc] init];
    id stateToken = [WireCallCenterV2 addVoiceChannelStateObserverWithObserver:stateObserver context:self.uiMOC];

    { // Call 1
        
        [self.syncMOC disableSaves];
        [self.uiMOC disableSaves];
        
        [self otherJoinCall];
        WaitForAllGroupsToBeEmpty(0.5);
     
        [self selfJoinCall];
        WaitForAllGroupsToBeEmpty(0.5);
        
        [self.syncMOC performGroupedBlockAndWait:^{
            [self.syncMOC enableSaves];
            [self.syncMOC saveOrRollback];
        }];
        
        [self.uiMOC enableSaves];
        [self.uiMOC saveOrRollback];
        [self simulateMediaFlowEstablishedOnConversation:self.conversationUnderTest];
        [self simulateParticipantsChanged:@[self.user2] onConversation:self.conversationUnderTest];
        WaitForAllGroupsToBeEmpty(0.5);
        
        XCTAssertTrue([self lastRequestContainsSelfStateJoined]);
        
        // then
        XCTAssertEqual(conversation.voiceChannel.state, VoiceChannelV2StateSelfConnectedToActiveChannel);
        XCTAssertEqual(stateObserver.changes.count, 3u);
        XCTAssertEqual(stateObserver.changes.lastObject.state, VoiceChannelV2StateSelfConnectedToActiveChannel);
        
        
        // and when
        [self selfDropCall];
        WaitForAllGroupsToBeEmpty(0.5);
        [self simulateMediaFlowReleasedOnConversation:self.conversationUnderTest];
        WaitForAllGroupsToBeEmpty(0.5);
        
        // then
        XCTAssertEqual(conversation.voiceChannel.state, VoiceChannelV2StateNoActiveUsers);
        XCTAssertEqual(stateObserver.changes.count, 4u);
        XCTAssertEqual(stateObserver.changes.lastObject.state, VoiceChannelV2StateNoActiveUsers);
    }
    
    [self.mockTransportSession resetReceivedRequests];
    stateObserver.changes = [NSMutableArray array];
    
    { // Call 2
        
        // when
        [self selfJoinCall];
        WaitForAllGroupsToBeEmpty(0.5);
        
        XCTAssertTrue([self lastRequestContainsSelfStateJoined]);
        
        // then
        XCTAssertEqual(conversation.voiceChannel.state, VoiceChannelV2StateOutgoingCall);
        XCTAssertEqual(stateObserver.changes.lastObject.state, VoiceChannelV2StateOutgoingCall);
        
        // when
        [self otherJoinCall];
        WaitForAllGroupsToBeEmpty(0.5);
        
        [self simulateMediaFlowEstablishedOnConversation:self.conversationUnderTest];
        [self simulateParticipantsChanged:@[self.user2] onConversation:self.conversationUnderTest];
        WaitForAllGroupsToBeEmpty(0.5);
        
        // then
        XCTAssertEqual(conversation.voiceChannel.state, VoiceChannelV2StateSelfConnectedToActiveChannel);
        XCTAssertEqual(stateObserver.changes.count, 3u);
        XCTAssertEqual(stateObserver.changes.lastObject.state, VoiceChannelV2StateSelfConnectedToActiveChannel);
    }
    
    XCTAssertTrue([self lastRequestContainsSelfStateJoined]);
    
    [WireCallCenterV2 removeObserverWithToken:stateToken];
}


- (void)testThatWeCanMakeTwoCallsInARowWithADelayOnTheSaveOnSelfUserJoin {
    
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    
    ZMConversation *conversation = self.conversationUnderTest;
    V2CallStateTestObserver *stateObserver = [[V2CallStateTestObserver alloc] init];
    id stateToken = [WireCallCenterV2 addVoiceChannelStateObserverWithObserver:stateObserver context:self.uiMOC];

    { // Call 1
        
        [self.uiMOC disableSaves];
        [self selfJoinCall];
        WaitForAllGroupsToBeEmpty(0.5);
        
        [self otherJoinCall];
        WaitForAllGroupsToBeEmpty(0.5);
        
        [self.uiMOC enableSaves];
        [self.uiMOC saveOrRollback];
        
        [self simulateMediaFlowEstablishedOnConversation:self.conversationUnderTest];
        [self simulateParticipantsChanged:@[self.user2] onConversation:self.conversationUnderTest];
        WaitForAllGroupsToBeEmpty(0.5);
        XCTAssertTrue([self lastRequestContainsSelfStateJoined]);
        
        // then
        XCTAssertEqual(conversation.voiceChannel.state, VoiceChannelV2StateSelfConnectedToActiveChannel);
        XCTAssertEqual(stateObserver.changes.count, 2u);
        XCTAssertEqual(stateObserver.changes.lastObject.state, VoiceChannelV2StateSelfConnectedToActiveChannel);
        
        // and when
        [self selfDropCall];
        WaitForAllGroupsToBeEmpty(0.5);
        [self simulateMediaFlowReleasedOnConversation:self.conversationUnderTest];
        [self simulateParticipantsChanged:@[] onConversation:self.conversationUnderTest];
        WaitForAllGroupsToBeEmpty(0.5);
        
        // then
        XCTAssertEqual(conversation.voiceChannel.state, VoiceChannelV2StateNoActiveUsers);
        XCTAssertEqual(stateObserver.changes.count, 3u);
        XCTAssertEqual(stateObserver.changes.lastObject.state, VoiceChannelV2StateNoActiveUsers);

    }
    
    [self.mockTransportSession resetReceivedRequests];
    [stateObserver.changes removeAllObjects];
    
    { // Call 2
        
        // when
        [self otherJoinCall];
        WaitForAllGroupsToBeEmpty(0.5);
    
        // when
        [self selfJoinCall];
        WaitForAllGroupsToBeEmpty(0.5);
        
        [self simulateMediaFlowEstablishedOnConversation:self.conversationUnderTest];
        [self simulateParticipantsChanged:@[self.user2] onConversation:self.conversationUnderTest];
        WaitForAllGroupsToBeEmpty(0.5);
        
        XCTAssertTrue([self lastRequestContainsSelfStateJoined]);
        
        // then
        XCTAssertEqual(stateObserver.changes.count, 3u);
        XCTAssertEqual(conversation.voiceChannel.state, VoiceChannelV2StateSelfConnectedToActiveChannel);
    }
    
    XCTAssertTrue([self lastRequestContainsSelfStateJoined]);
    
    [WireCallCenterV2 removeObserverWithToken:stateToken];
}



- (void)testThatWeDelaySaveOnTheNetworkResponse {
    
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    WaitForAllGroupsToBeEmpty(0.5);

    ZMConversation *conversation = self.conversationUnderTest;
    V2CallStateTestObserver *stateObserver = [[V2CallStateTestObserver alloc] init];
    id stateToken = [WireCallCenterV2 addVoiceChannelStateObserverWithObserver:stateObserver context:self.uiMOC];

    { // Call 1
        
        ZMTransportRequest *request = [self selfJoinCallButDelayRequest];
        WaitForAllGroupsToBeEmpty(0.5);
        
        [self.syncMOC disableSaves];
        [self otherJoinCall];
        WaitForAllGroupsToBeEmpty(0.5);
        
        [self.mockTransportSession completePreviouslySuspendendRequest:request];
        WaitForAllGroupsToBeEmpty(0.5);

        [self.syncMOC enableSaves];
        [self.syncMOC saveOrRollback];
        
        [self simulateMediaFlowEstablishedOnConversation:self.conversationUnderTest];
        [self simulateParticipantsChanged:@[self.user2] onConversation:self.conversationUnderTest];
        WaitForAllGroupsToBeEmpty(0.5);
        
        XCTAssertTrue([self lastRequestContainsSelfStateJoined]);
        
        // then
        XCTAssertEqual(conversation.voiceChannel.state, VoiceChannelV2StateSelfConnectedToActiveChannel);
        XCTAssertEqual(stateObserver.changes.count, 3u);
        XCTAssertEqual(stateObserver.changes.lastObject.state, VoiceChannelV2StateSelfConnectedToActiveChannel);

        
        // and when
        [self selfDropCall];
        WaitForAllGroupsToBeEmpty(0.5);
        [self simulateMediaFlowReleasedOnConversation:self.conversationUnderTest];
        [self simulateParticipantsChanged:@[] onConversation:self.conversationUnderTest];
        WaitForAllGroupsToBeEmpty(0.5);
        
        // then
        XCTAssertEqual(conversation.voiceChannel.state, VoiceChannelV2StateNoActiveUsers);
        XCTAssertEqual(stateObserver.changes.count, 4u);
        XCTAssertEqual(stateObserver.changes.lastObject.state, VoiceChannelV2StateNoActiveUsers);

    }
    
    [self.mockTransportSession resetReceivedRequests];
    [stateObserver.changes removeAllObjects];
    
    { // Call 2
        [self otherJoinCall];
        WaitForAllGroupsToBeEmpty(0.5);
        
        // when
        [self selfJoinCall];
        WaitForAllGroupsToBeEmpty(0.5);

        [self simulateParticipantsChanged:@[self.user2] onConversation:self.conversationUnderTest];
        WaitForAllGroupsToBeEmpty(0.5);
        
        XCTAssertTrue([self lastRequestContainsSelfStateJoined]);
        
        // then
        XCTAssertEqual(stateObserver.changes.count, 2u);

    }
    
    [WireCallCenterV2 removeObserverWithToken:stateToken];
}

- (void)testThatWeCanMakeTwoCallsInARowWhileObservingTheWindow {
    
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    
    ZMConversation *conversation = self.conversationUnderTest;
    V2CallStateTestObserver *stateObserver = [[V2CallStateTestObserver alloc] init];
    id stateToken = [WireCallCenterV2 addVoiceChannelStateObserverWithObserver:stateObserver context:self.uiMOC];

    [self registerWindowObserver];
    
    { // Call 1
        [self selfJoinCall];
        WaitForAllGroupsToBeEmpty(0.5);
        
        XCTAssertTrue([self lastRequestContainsSelfStateJoined]);
        
        [self otherJoinCall];
        WaitForAllGroupsToBeEmpty(0.5);
        
        [self simulateParticipantsChanged:@[self.user2] onConversation:self.conversationUnderTest];
        WaitForAllGroupsToBeEmpty(0.5);
        
        // when
        [self selfDropCall];
        WaitForAllGroupsToBeEmpty(0.5);
        
        // then
        XCTAssertEqual(conversation.voiceChannel.state, VoiceChannelV2StateNoActiveUsers);
        XCTAssertEqual(stateObserver.changes.count, 3u);
        XCTAssertEqual(stateObserver.changes.lastObject.state, VoiceChannelV2StateNoActiveUsers);
    }
    
    [self.mockTransportSession resetReceivedRequests];
    [stateObserver.changes removeAllObjects];
    
    { // Call 2
        // when
        [self selfJoinCall];
        WaitForAllGroupsToBeEmpty(0.5);
        
        XCTAssertTrue([self lastRequestContainsSelfStateJoined]);
        
        [self otherJoinCall];
        WaitForAllGroupsToBeEmpty(0.5);
        
        [self simulateMediaFlowEstablishedOnConversation:self.conversationUnderTest];
        [self simulateParticipantsChanged:@[self.user2] onConversation:self.conversationUnderTest];
        WaitForAllGroupsToBeEmpty(0.5);
        
        // then
        XCTAssertEqual(conversation.voiceChannel.state, VoiceChannelV2StateSelfConnectedToActiveChannel);
        XCTAssertEqual(stateObserver.changes.count, 3u);
        XCTAssertEqual(stateObserver.changes.lastObject.state, VoiceChannelV2StateSelfConnectedToActiveChannel);
    }
    
    [WireCallCenterV2 removeObserverWithToken:stateToken];
}


- (void)testThatItGoesThroughConnectingStateWhenReceivingAnIncomingCallAfterAnOutgoingCall {
    
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    
    ZMConversation *conversation = self.conversationUnderTest;
    V2CallStateTestObserver *stateObserver = [[V2CallStateTestObserver alloc] init];
    id stateToken = [WireCallCenterV2 addVoiceChannelStateObserverWithObserver:stateObserver context:self.uiMOC];
    
    { // Call 1
        // when selfUser calls
        [self selfJoinCall];
        WaitForAllGroupsToBeEmpty(0.5);
        
        [self otherJoinCall];
        WaitForAllGroupsToBeEmpty(0.5);
        
        // then
        // we are in the connecting state
        XCTAssertEqual(conversation.voiceChannel.state, VoiceChannelV2StateSelfIsJoiningActiveChannel);

        // users acquire flow
        [self simulateMediaFlowEstablishedOnConversation:self.conversationUnderTest];
        [self simulateParticipantsChanged:@[self.user2] onConversation:self.conversationUnderTest];
        WaitForAllGroupsToBeEmpty(0.5);
        
        // then
        // we are in connected state
        XCTAssertEqual(conversation.voiceChannel.state, VoiceChannelV2StateSelfConnectedToActiveChannel);
        
        [self selfDropCall];
        WaitForAllGroupsToBeEmpty(0.5);
        [self simulateMediaFlowReleasedOnConversation:self.conversationUnderTest];
        [self simulateParticipantsChanged:@[] onConversation:self.conversationUnderTest];
        WaitForAllGroupsToBeEmpty(0.5);
        
        // then
        XCTAssertEqual(conversation.voiceChannel.state, VoiceChannelV2StateNoActiveUsers);
        XCTAssertEqual(stateObserver.changes.count, 4u);
    }
    
    [stateObserver.changes removeAllObjects];
    
    { // Call 2
        // when other user calls
        [self otherJoinCall];
        WaitForAllGroupsToBeEmpty(0.5);
        
        [self selfJoinCall];
        WaitForAllGroupsToBeEmpty(0.5);
        
        // then
        // we should be in connecting state, because the other user is calling
        XCTAssertEqual(conversation.voiceChannel.state, VoiceChannelV2StateSelfIsJoiningActiveChannel);
        
        // users acquire flow
        [self simulateMediaFlowEstablishedOnConversation:self.conversationUnderTest];
        [self simulateParticipantsChanged:@[self.user2] onConversation:self.conversationUnderTest];
        WaitForAllGroupsToBeEmpty(0.5);
        
        // then
        XCTAssertEqual(conversation.voiceChannel.state, VoiceChannelV2StateSelfConnectedToActiveChannel);
        XCTAssertEqual(stateObserver.changes.count, 3u);
        XCTAssertEqual(stateObserver.changes[0].state, VoiceChannelV2StateIncomingCall);
        XCTAssertEqual(stateObserver.changes[1].state, VoiceChannelV2StateSelfIsJoiningActiveChannel);
        XCTAssertEqual(stateObserver.changes[2].state, VoiceChannelV2StateSelfConnectedToActiveChannel);
    }
    
    [WireCallCenterV2 removeObserverWithToken:stateToken];
}


- (void)testThatItTimesOutCallsAndDropsTheCall_OneOnOne_Outgoing_Second_Outgoing
{
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    
    ZMConversation *conversation = self.conversationUnderTest;
    [ZMCallTimer setTestCallTimeout: 0.2];
    
    V2CallStateTestObserver *stateObserver = [[V2CallStateTestObserver alloc] init];
    id stateToken = [WireCallCenterV2 addVoiceChannelStateObserverWithObserver:stateObserver context:self.uiMOC];
    
    // when selfUser calls
    [self selfJoinCall];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(conversation.voiceChannel.state, VoiceChannelV2StateOutgoingCall);
    XCTAssertEqual(conversation.voiceChannel.participants.count, 0u);
    
    // when
    [self spinMainQueueWithTimeout:0.5];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(conversation.voiceChannel.participants.count, 0u);
    XCTAssertEqual(stateObserver.changes.count, 2u);
    XCTAssertEqual(stateObserver.changes.lastObject.state, VoiceChannelV2StateNoActiveUsers);
    
    // and when
    [self selfJoinCall];
    WaitForAllGroupsToBeEmpty(0.5);

    // then
    XCTAssertEqual(conversation.voiceChannel.state, VoiceChannelV2StateOutgoingCall);
    
    // and when
    [self spinMainQueueWithTimeout:0.5];
    
    // then
    XCTAssertEqual(conversation.voiceChannel.state, VoiceChannelV2StateNoActiveUsers);
    
    [WireCallCenterV2 removeObserverWithToken:stateToken];
}

- (void)testThatItTimesOutCallsAndDropsTheCall_OneOnOne_Outgoing_Second_Incoming
{
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    
    ZMConversation *conversation = self.conversationUnderTest;
    [ZMCallTimer setTestCallTimeout: 0.2];
    V2CallStateTestObserver *stateObserver = [[V2CallStateTestObserver alloc] init];
    id stateToken = [WireCallCenterV2 addVoiceChannelStateObserverWithObserver:stateObserver context:self.uiMOC];
    
    // when selfUser calls
    [self selfJoinCall];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(conversation.voiceChannel.state, VoiceChannelV2StateOutgoingCall);
    XCTAssertEqual(conversation.voiceChannel.participants.count, 0u);
    XCTAssertEqual(stateObserver.changes.count, 1u);
    
    // when
    [self spinMainQueueWithTimeout:0.5];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(conversation.voiceChannel.participants.count, 0u);
    XCTAssertEqual(stateObserver.changes.count, 2u);
    XCTAssertEqual(stateObserver.changes.lastObject.state, VoiceChannelV2StateNoActiveUsers);
    
    // and when
    [self otherJoinCall];
    WaitForAllGroupsToBeEmpty(0.5);

    // then
    XCTAssertEqual(conversation.voiceChannel.state, VoiceChannelV2StateIncomingCall);
    
    // and when
    [self spinMainQueueWithTimeout:0.5];
    
    // then
    XCTAssertEqual(conversation.voiceChannel.state, VoiceChannelV2StateIncomingCallInactive);
    
    [WireCallCenterV2 removeObserverWithToken:stateToken];
}


- (void)testThatItTimesOutCallsAndSetsInactive_OneOnOne_Incoming
{
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    
    ZMConversation *conversation = self.conversationUnderTest;
    [ZMCallTimer setTestCallTimeout: 0.2];
    
    // when other user calls
    [self otherJoinCall];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(conversation.voiceChannel.state, VoiceChannelV2StateIncomingCall);
    XCTAssertEqual(conversation.voiceChannel.participants.count, 1u);
    
    // when
    [self spinMainQueueWithTimeout:0.8];
    WaitForAllGroupsToBeEmpty(0.5);

    // then
    XCTAssertEqual(conversation.voiceChannel.state, VoiceChannelV2StateIncomingCallInactive);
    XCTAssertEqual(conversation.voiceChannel.participants.count, 1u);
    
    // and when we reinitiate the call
    [self selfJoinCall];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(conversation.voiceChannel.state, VoiceChannelV2StateSelfIsJoiningActiveChannel);
}


- (void)testThatItTimesOutOutgoingCallsAndSilencesTheCall_Group
{
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    self.useGroupConversation = YES;
    
    ZMConversation *conversation = self.conversationUnderTest;
    [ZMCallTimer setTestCallTimeout: 0.2];
    
    // when selfUser calls
    [self selfJoinCall];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(conversation.voiceChannel.state, VoiceChannelV2StateOutgoingCall);
    XCTAssertEqual(conversation.voiceChannel.participants.count, 0u);

    // when
    [self spinMainQueueWithTimeout:0.5];
    
    // then
    XCTAssertEqual(conversation.voiceChannel.state, VoiceChannelV2StateOutgoingCallInactive);
    XCTAssertEqual(conversation.voiceChannel.participants.count, 0u);

    // and when we reinitiate the call
    [self selfDropCall];
    WaitForAllGroupsToBeEmpty(0.5);
    
    [self selfJoinCall];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(conversation.voiceChannel.state, VoiceChannelV2StateOutgoingCall);
}


- (void)testThatItTimesOutOutgoingCallsAndSilencesTheCall_Group_Second_Incoming
{
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    self.useGroupConversation = YES;
    
    ZMConversation *conversation = self.conversationUnderTest;
    [ZMCallTimer setTestCallTimeout: 0.2];
    
    // when selfUser calls
    [self selfJoinCall];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(conversation.voiceChannel.state, VoiceChannelV2StateOutgoingCall);
    XCTAssertEqual(conversation.voiceChannel.participants.count, 0u);
    
    // when
    [self spinMainQueueWithTimeout:0.5];
    
    // then
    XCTAssertEqual(conversation.voiceChannel.state, VoiceChannelV2StateOutgoingCallInactive);
    XCTAssertEqual(conversation.voiceChannel.participants.count, 0u);
    
    // and when we reinitiate the call
    [self selfDropCall];
    WaitForAllGroupsToBeEmpty(0.5);
    
    [self otherJoinCall];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(conversation.voiceChannel.state, VoiceChannelV2StateIncomingCall);
}


// TODO test that when the backend tells us that we are currently the active device but we know that we are not (callDeviceIsActive) we inform the backend that we are not.
// this is a bug and we are trying to recover from it


@end



@implementation CallingTests (SlowSync)

- (void)testThatItRefetchesTheCallStateDuringSlowSync
{
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    ZMConversation *oneToOneConversation = self.conversationUnderTest;
    NSString *expectedPath = [NSString stringWithFormat:@"/conversations/%@/call/state", oneToOneConversation.remoteIdentifier.transportString];
    
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *  __unused session) {
        [self.mockConversationUnderTest addUserToCall:self.user2];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    [self simulateAppStopped];
    
    // We simulate that we launched application after 3 days and backed returns 404 on notifications since lastUpdatedEventId
    // and we go to slow sync
    self.mockTransportSession.responseGeneratorBlock = ^ZMTransportResponse *(ZMTransportRequest *request) {
        if ([request.path containsString:@"/notifications"]) {
            ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:nil HTTPStatus:404 transportSessionError:nil];
            return response;
        }
        return nil;
    };

    // when
    [self simulateAppRestarted];

    // then
    ZMTransportRequest *foundRequest = [self.mockTransportSession.receivedRequests firstObjectMatchingWithBlock:^BOOL(ZMTransportRequest *request) {
        return [request.path isEqualToString:expectedPath] && request.method == ZMMethodGET;
    }];
    XCTAssertNotNil(foundRequest);
}

- (void)testThatItDoesNotRefetchTheCallStateDuringSlowSyncForConversationsWithNoCallParticipants
{
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    ZMConversation *oneToOneConversation = [self conversationForMockConversation:self.selfToUser1Conversation];
    NSString *expectedPath = [NSString stringWithFormat:@"/conversations/%@/call/state", oneToOneConversation.remoteIdentifier.transportString];
    
    [self simulateAppStopped];
    
    //We simulate that we launched application after 3 days and backed returns 404 on notifications since lastUpdatedEventId
    // and we go to slow sync
    self.mockTransportSession.responseGeneratorBlock = ^ZMTransportResponse *(ZMTransportRequest *request) {
        if ([request.path containsString:@"/notifications"]) {
            ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:nil HTTPStatus:404 transportSessionError:nil];
            return response;
        }
        return nil;
    };
    
    // when
    [self simulateAppRestarted];
    
    // then
    ZMTransportRequest *foundRequest = [self.mockTransportSession.receivedRequests firstObjectMatchingWithBlock:^BOOL(ZMTransportRequest *request) {
        return [request.path isEqualToString:expectedPath] && request.method == ZMMethodGET;
    }];
    XCTAssertNil(foundRequest);

}

@end



@implementation CallingTests (GroupedCalling)

- (void)testThatItDoesNotRetrieveTheCallStateWhenItIsAddedToAGroupCallWhileNoActiveUsers
{
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    
    // when
    MockConversation __block *mockConversation = nil;
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        mockConversation = [session insertConversationWithCreator:self.user1 otherUsers:@[self.user1,self.user2, self.user3] type:ZMTConversationTypeGroup];
        [mockConversation addUserToCall:self.user1];
        [mockConversation addUserToCall:self.user2];
    }];
    id<ZMConversationListObserver> listObserver = [OCMockObject niceMockForProtocol:@protocol(ZMConversationListObserver)];
    
    // Make sure we observe the conversation as soon as we figure out that a new conversation is available
    __block ZMConversation *conversationToObserve;
    __block VoiceChannelV2State voiceChannelState = VoiceChannelV2StateInvalid;
    XCTestExpectation *conversationListChangedExpectation = [self expectationWithDescription:@"Conversation list inserted"];
    
    [[(id) listObserver stub] conversationListDidChange:[OCMArg checkWithBlock:^BOOL(ConversationListChangeInfo* changeInfo) {
        ZMConversationList *innerList = changeInfo.conversationList;
        if(changeInfo.insertedIndexes.count == 1u) {
            conversationToObserve = innerList[changeInfo.insertedIndexes.firstIndex];
            voiceChannelState = conversationToObserve.voiceChannel.state;
            [conversationListChangedExpectation fulfill];
        }
        return YES;
    }]];
    
    ZMConversationList* list = [ZMConversationList conversationsInUserSession:self.userSession];
    id listToken = [ConversationListChangeInfo addObserver:listObserver forList:list];
    
    [self.mockTransportSession resetReceivedRequests];
    
    // when
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        NOT_USED(session);
        [mockConversation addUsersByUser:self.user1 addedUsers:@[self.selfUser]];
    }];
    XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0.5]);
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"path == %@ && method == %d", [NSString stringWithFormat:@"/conversations/%@/call/state", conversationToObserve.remoteIdentifier.transportString], ZMMethodGET];
    NSArray *callStateRequest = [self.mockTransportSession.receivedRequests filteredArrayUsingPredicate:predicate];
    XCTAssertEqual(callStateRequest.count, 0u);
   
    // after
    [self tearDownVoiceChannelForConversation:conversationToObserve];
    (void)listToken;
}

- (void)testThatItFiresAConversationChangeNotificationWhenAGroupCallIsDeclined
{
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    self.useGroupConversation = YES;

    ZMConversation *conversation = self.conversationUnderTest;

    ZMConversationList *list = [ZMConversationList conversationsInUserSession:self.userSession];
    id listObserver = [OCMockObject niceMockForProtocol:@protocol(ZMConversationListObserver)];
    id listToken = [ConversationListChangeInfo addObserver:listObserver forList:list];

    // Joining
    [self usersJoinGroupCall:[[self mockConversationUnderTest] activeUsers]];
    WaitForAllGroupsToBeEmpty(0.5);


    // Expect
    XCTestExpectation *expectation1 = [self expectationWithDescription:@"connection set to accepted"];
    [(id<ZMConversationListObserver>)[listObserver expect] conversationInsideList:list didChange:[OCMArg checkWithBlock:^BOOL(ConversationChangeInfo *note) {
        if (note.conversationListIndicatorChanged && note.conversation == conversation) {
            [expectation1 fulfill];
            return YES;
        }
        return NO;
    }]];

    // When
    [self.userSession performChanges:^{
        [self.conversationUnderTest.voiceChannelRouter.v2 ignoreIncomingCall];
    }];

    // Then
    XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0.5]);
    (void)listToken;
}


- (void)testThatWeCanJoinGroupCallAfterWeLeaveItAndItIsStillActive
{
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    self.useGroupConversation = YES;
    
    ZMConversation *conversation = self.conversationUnderTest;
    V2CallStateTestObserver *stateObserver = [[V2CallStateTestObserver alloc] init];
    id stateToken = [WireCallCenterV2 addVoiceChannelStateObserverWithObserver:stateObserver context:self.uiMOC];
    
    {
        //Joining
        [self usersJoinGroupCall:[[self mockConversationUnderTest] activeUsers]];
        WaitForAllGroupsToBeEmpty(0.5);

        [self selfJoinCall];
        WaitForAllGroupsToBeEmpty(0.5);

        [self simulateMediaFlowEstablishedOnConversation:self.conversationUnderTest];
        [self simulateParticipantsChanged:@[self.user2] onConversation:self.conversationUnderTest];
        WaitForAllGroupsToBeEmpty(0.5);

        XCTAssertTrue([self lastRequestContainsSelfStateJoined]);
        
        // then
        XCTAssertEqual(conversation.voiceChannel.state, VoiceChannelV2StateSelfConnectedToActiveChannel);
        XCTAssertEqual(stateObserver.changes.count, 3u);
        XCTAssertEqual(stateObserver.changes.lastObject.state, VoiceChannelV2StateSelfConnectedToActiveChannel);
        
        // and when
        [self selfDropCall];
        WaitForAllGroupsToBeEmpty(0.5);
        [self simulateMediaFlowReleasedOnConversation:self.conversationUnderTest];
        [self simulateParticipantsChanged:@[] onConversation:self.conversationUnderTest];
        WaitForAllGroupsToBeEmpty(0.5);
        
        // then
        XCTAssertTrue([self lastRequestContainsSelfStateIdleWithIsIgnored:NO]);
        XCTAssertEqual(stateObserver.changes.count, 4u);
        XCTAssertEqual(stateObserver.changes.lastObject.state, VoiceChannelV2StateIncomingCallInactive);
    }
    
    [stateObserver.changes removeAllObjects];
    [self.mockTransportSession resetReceivedRequests];
    
    { // Join again
        [self selfJoinCall];
        WaitForAllGroupsToBeEmpty(0.5);
        
        [self simulateMediaFlowEstablishedOnConversation:self.conversationUnderTest];
        [self simulateParticipantsChanged:@[self.user2] onConversation:self.conversationUnderTest];
        WaitForAllGroupsToBeEmpty(0.5);

        XCTAssertTrue([self lastRequestContainsSelfStateJoined]);
        
        // then
        XCTAssertFalse(self.conversationUnderTest.isIgnoringCall);
        XCTAssertEqual(stateObserver.changes.count, 2u);
        XCTAssertEqual(stateObserver.changes.lastObject.state, VoiceChannelV2StateSelfConnectedToActiveChannel);
    }
    
    [WireCallCenterV2 removeObserverWithToken:stateToken];
}

- (void)testThatGroupCallIsDroppedWhenTheLastOtherParticipantLeaves
{
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    self.useGroupConversation = YES;
    
    ZMConversation *conversation = self.conversationUnderTest;
    V2CallStateTestObserver *stateObserver = [[V2CallStateTestObserver alloc] init];
    id stateToken = [WireCallCenterV2 addVoiceChannelStateObserverWithObserver:stateObserver context:self.uiMOC];
    
    {
        //Joining
        NSMutableOrderedSet *joinedUsers = [[[self mockConversationUnderTest] activeUsers] mutableCopy];
        
        [self usersJoinGroupCall:joinedUsers];
        WaitForAllGroupsToBeEmpty(0.5);
        
        [self selfJoinCall];
        WaitForAllGroupsToBeEmpty(0.5);

        [self simulateMediaFlowEstablishedOnConversation:self.conversationUnderTest];
        [self simulateParticipantsChanged:joinedUsers.array onConversation:self.conversationUnderTest];
        WaitForAllGroupsToBeEmpty(0.5);
        
        XCTAssertTrue([self lastRequestContainsSelfStateJoined]);        
        // then
        XCTAssertEqual(conversation.voiceChannel.state, VoiceChannelV2StateSelfConnectedToActiveChannel);
        XCTAssertEqual(stateObserver.changes.count, 3u);
        XCTAssertEqual(stateObserver.changes.lastObject.state, VoiceChannelV2StateSelfConnectedToActiveChannel);
        
        // and when
        
        // everyone leaves
        [self usersLeaveGroupCall:joinedUsers];
        WaitForAllGroupsToBeEmpty(0.5);
        
        // then
        XCTAssertEqual(stateObserver.changes.count, 5u);  // goes through transfer state before disconnect
        XCTAssertEqual(stateObserver.changes.lastObject.state, VoiceChannelV2StateNoActiveUsers);
    }
    
    [WireCallCenterV2 removeObserverWithToken:stateToken];
}

- (void)testThatGroupCallDoesNotDropWhenThereAreTwoParticipantLeft
{
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    self.useGroupConversation = YES;
    
    ZMConversation *conversation = self.conversationUnderTest;
    V2CallStateTestObserver *stateObserver = [[V2CallStateTestObserver alloc] init];
    id stateToken = [WireCallCenterV2 addVoiceChannelStateObserverWithObserver:stateObserver context:self.uiMOC];
    
    {
        //Joining
        NSMutableOrderedSet *joinedUsers = [[[self mockConversationUnderTest] activeUsers] mutableCopy];
        //remove selfUser for now, it will join after all other users
        [joinedUsers removeObject:self.selfUser];
        
        [self usersJoinGroupCall:joinedUsers];
        WaitForAllGroupsToBeEmpty(0.5);
        
        [self selfJoinCall];
        WaitForAllGroupsToBeEmpty(0.5);

        [self simulateMediaFlowEstablishedOnConversation:self.conversationUnderTest];
        [self simulateParticipantsChanged:joinedUsers.array onConversation:self.conversationUnderTest];
        WaitForAllGroupsToBeEmpty(0.5);

        XCTAssertTrue([self lastRequestContainsSelfStateJoined]);
        
        // then
        XCTAssertEqual(conversation.voiceChannel.state, VoiceChannelV2StateSelfConnectedToActiveChannel);
        XCTAssertEqual(stateObserver.changes.count, 3u);
        XCTAssertEqual(stateObserver.changes.lastObject.state, VoiceChannelV2StateSelfConnectedToActiveChannel);
        
        // and when
        
        // everyone but one leaves
        [joinedUsers removeObject:joinedUsers.firstObject];
        
        [self usersLeaveGroupCall:joinedUsers];
        WaitForAllGroupsToBeEmpty(0.5);
        
        // then
        //voice channel state should not change, no notification should be posted
        XCTAssertEqual(stateObserver.changes.count, 3u);
    }
    
    [WireCallCenterV2 removeObserverWithToken:stateToken];
}

- (void)testThatItSendsCallParticipantsNotification
{
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    self.useGroupConversation = YES;
    
    ZMConversation *conversation = self.conversationUnderTest;
    V2VoiceChannelParticipantTestObserver *participantObserver = [[V2VoiceChannelParticipantTestObserver alloc] init];
    id participantsToken = [WireCallCenterV2 addVoiceChannelParticipantObserverWithObserver:participantObserver forConversation:conversation context:self.uiMOC];
    
    NSMutableOrderedSet *joinedUsers = [[[self mockConversationUnderTest] activeUsers] mutableCopy];
    [joinedUsers zm_sortUsingComparator:[MockFlowManager conferenceComparator] valueGetter:^id(MockUser *mockUser) {
        return mockUser.identifier;
    }];
    [joinedUsers removeObject:self.selfUser];
    XCTAssertFalse([joinedUsers containsObject:self.selfUser]);
    
    /////
    // (1) when we are connecting
    {
        [self selfJoinCall];
        WaitForAllGroupsToBeEmpty(0.5);
    }
    
    /////
    // (2) other user joins the call
    {
        [self usersJoinGroupCall:joinedUsers];
        WaitForAllGroupsToBeEmpty(0.5);
        
        // then
        // we should see an insert
        NSMutableIndexSet *expectedInsert = [NSMutableIndexSet indexSetWithIndexesInRange:NSMakeRange(0, joinedUsers.count)];
        XCTAssertEqual(participantObserver.changes.count, 1u);
        SetChangeInfo *lastChange = participantObserver.changes.lastObject;
        XCTAssertEqualObjects(lastChange.updatedIndexes, [NSIndexSet indexSet]);
        XCTAssertEqualObjects(lastChange.insertedIndexes, [expectedInsert copy]);
        XCTAssertEqualObjects(lastChange.deletedIndexes, [NSIndexSet indexSet]);
        [participantObserver.changes removeAllObjects];
    }
    /////
    // (3) when a flow is established
    {
        [self simulateMediaFlowEstablishedOnConversation:self.conversationUnderTest];
        [self simulateParticipantsChanged:joinedUsers.array onConversation:conversation];
        WaitForAllGroupsToBeEmpty(0.5);
        
        // then
        // we should see an update
        XCTAssertEqual(participantObserver.changes.count, 1u);
        SetChangeInfo *lastChange = participantObserver.changes.lastObject;
        XCTAssertEqualObjects(lastChange.updatedIndexes, [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, joinedUsers.count)]);
        XCTAssertEqualObjects(lastChange.insertedIndexes, [NSIndexSet indexSet]);
        XCTAssertEqualObjects(lastChange.deletedIndexes, [NSIndexSet indexSet]);
        [participantObserver.changes removeAllObjects];
    }
    
    /////
    // (4) when everyone but one and the selfUser leaves
    MockUser *leftOtherUser;
    {
        leftOtherUser = joinedUsers.firstObject;
        [joinedUsers removeObject:leftOtherUser];
        NSUInteger length = joinedUsers.count;

        [self usersLeaveGroupCall:joinedUsers];
        WaitForAllGroupsToBeEmpty(0.5);

        // then
        // we should see a delete
        XCTAssertEqual(participantObserver.changes.count, 1u);
        SetChangeInfo *lastChange = participantObserver.changes.lastObject;
        XCTAssertEqualObjects(lastChange.deletedIndexes, [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(1, length)]);
        XCTAssertEqualObjects(lastChange.insertedIndexes, [NSIndexSet indexSet]);
        XCTAssertEqualObjects(lastChange.updatedIndexes, [NSIndexSet indexSet]);
        [participantObserver.changes removeAllObjects];
    }
    
    /////
    // (5) when we receive an update from AVS
    {
        [self simulateParticipantsChanged:@[leftOtherUser] onConversation:conversation];
        WaitForAllGroupsToBeEmpty(0.5);

        // then the order should not have changed
        XCTAssertEqual(participantObserver.changes.count, 0u);
    }
    
    [WireCallCenterV2 removeObserverWithToken:participantsToken];
}

- (void)testThatItSendsAJoinCallbackWithErrorWhenTooManyMembers
{
    // given
    self.mockTransportSession.maxMembersForGroupCall = 25;
       
    // Provision
    __block MockConversation *mockBigGroupConversation = nil;
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        NSMutableArray *users = [NSMutableArray array];
        
        for (uint16_t i = 0; i < self.mockTransportSession.maxMembersForGroupCall; i++) {
            MockUser *user = [session insertUserWithName:[NSString stringWithFormat:@"Group Call User %d", i]];
            user.email = [NSString stringWithFormat:@"group-call-%d@example.com", i];
            user.phone = [NSString stringWithFormat:@"1234%d", i];
            user.accentID = i % 6 + 1;
            [session addProfilePictureToUser:user];
            [self storeRemoteIDForObject:user];
            [users addObject:user];
        }
        
        mockBigGroupConversation = [session insertGroupConversationWithSelfUser:self.selfUser
                                                                     otherUsers:users];
        mockBigGroupConversation.creator = self.selfUser;
        [self storeRemoteIDForObject:mockBigGroupConversation];
        [mockBigGroupConversation changeNameByUser:self.selfUser name:@"BIG Group conversation"];
    }];
    WaitForAllGroupsToBeEmpty(0.5);

    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    WaitForAllGroupsToBeEmpty(0.5);

    ZMConversation *bigGroupConversation = [self conversationForMockConversation:mockBigGroupConversation];
    
    [self expectationForNotification:ZMConversationVoiceChannelJoinFailedNotification object:nil handler:^BOOL(NSNotification * _Nonnull notification) {
        NSError *error = notification.userInfo[@"error"];
        
        XCTAssertTrue([[error domain] isEqualToString:ZMConversationErrorDomain]);
        XCTAssertTrue(error.conversationErrorCode == ZMConversationTooManyMembersInConversation);
        XCTAssertTrue([error.userInfo[ZMConversationErrorMaxMembersForGroupCallKey] unsignedIntegerValue] == self.mockTransportSession.maxMembersForGroupCall);
        
        return YES;
    }];

    WaitForAllGroupsToBeEmpty(0.5);
   
    // then
    XCTAssertEqual(bigGroupConversation.voiceChannel.state, VoiceChannelV2StateNoActiveUsers);

    // when
    [self.userSession performChanges:^{
        [bigGroupConversation.voiceChannelRouter.v2 joinWithVideo:NO];
    }];
    
    WaitForAllGroupsToBeEmpty(0.5f);
    XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0.5f]);
    
    [self tearDownVoiceChannelForConversation:bigGroupConversation];
}

- (void)testThatItSendsAJoinCallbackWithErrorWhenTooManyCallParticipants
{
    // given
    self.mockTransportSession.maxCallParticipants = 9;
    
    // Provision
    __block MockConversation *mockBigGroupConversation = nil;
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        NSMutableArray *users = [NSMutableArray array];
        
        for (uint16_t i = 0; i < self.mockTransportSession.maxCallParticipants; i++) {
            MockUser *user = [session insertUserWithName:[NSString stringWithFormat:@"Group Call User %d", i]];
            user.email = [NSString stringWithFormat:@"group-call-%d@example.com", i];
            user.phone = [NSString stringWithFormat:@"1234%d", i];
            user.accentID = i % 6 + 1;
            [session addProfilePictureToUser:user];
            [self storeRemoteIDForObject:user];
            [users addObject:user];
        }
        
        mockBigGroupConversation = [session insertGroupConversationWithSelfUser:self.selfUser
                                                                     otherUsers:users];
        mockBigGroupConversation.creator = self.selfUser;
        [self storeRemoteIDForObject:mockBigGroupConversation];
        [mockBigGroupConversation changeNameByUser:self.selfUser name:@"BIG Group conversation"];
        
        for (MockUser *user in users) {
            [mockBigGroupConversation addUserToCall:user];
        }
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    WaitForAllGroupsToBeEmpty(0.5);
    
    ZMConversation *bigGroupConversation = [self conversationForMockConversation:mockBigGroupConversation];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // when all remotes join
    NSMutableOrderedSet *joinedUsers = [[mockBigGroupConversation activeUsers] mutableCopy];
    [joinedUsers removeObject:self.selfUser];
    WaitForAllGroupsToBeEmpty(0.5);
    [self simulateParticipantsChanged:joinedUsers.array onConversation:bigGroupConversation];
    
    WaitForAllGroupsToBeEmpty(0.5);
        
    // expect
    [self expectationForNotification:ZMConversationVoiceChannelJoinFailedNotification object:nil handler:^BOOL(NSNotification * _Nonnull notification) {
        NSError *error = notification.userInfo[@"error"];
        
        XCTAssertTrue([[error domain] isEqualToString:ZMConversationErrorDomain]);
        XCTAssertTrue(error.conversationErrorCode == ZMConversationTooManyParticipantsInTheCall);
        XCTAssertTrue([error.userInfo[ZMConversationErrorMaxCallParticipantsKey] unsignedIntegerValue] == self.mockTransportSession.maxCallParticipants);
        
        return YES;
    }];
    
    // when
    [self.userSession performChanges:^{
        [bigGroupConversation.voiceChannelRouter.v2 joinWithVideo:NO];
    }];
    
    WaitForAllGroupsToBeEmpty(0.5f);
    XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0.5f]);
    [self tearDownVoiceChannelForConversation:bigGroupConversation];
}

- (void)testThatItDropsTheCallWhenLeavingAConversationWithAnActiveCall
{
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    self.useGroupConversation = YES;
    
    ZMConversation *conversation = self.conversationUnderTest;
    V2CallStateTestObserver *stateObserver = [[V2CallStateTestObserver alloc] init];
    id stateToken = [WireCallCenterV2 addVoiceChannelStateObserverWithObserver:stateObserver context:self.uiMOC];
    
    
    // (1) selfUser initiated a call
    {
        [self selfJoinCall];
        WaitForAllGroupsToBeEmpty(0.5);
        
        XCTAssertTrue([self lastRequestContainsSelfStateJoined]);

        XCTAssertEqual(stateObserver.changes.count, 1u);
        XCTAssertEqual(stateObserver.changes.lastObject.state, VoiceChannelV2StateOutgoingCall);
    }
    
    // (2) other user joins
    {
        [self otherJoinCall];
        [self simulateMediaFlowEstablishedOnConversation:conversation];
        [self simulateParticipantsChanged:@[self.user1] onConversation:conversation];
        WaitForAllGroupsToBeEmpty(0.5);
        
        // then
        XCTAssertEqual(stateObserver.changes.count, 2u);
        XCTAssertEqual(stateObserver.changes.lastObject.state, VoiceChannelV2StateSelfConnectedToActiveChannel);
    }
    
    // (3) selfUser leaves
    {
        [self selfLeavesConversation];
        [self simulateMediaFlowReleasedOnConversation:conversation];
        [self simulateParticipantsChanged:@[] onConversation:conversation];
        WaitForAllGroupsToBeEmpty(0.5);
        
        // then
        XCTAssertTrue([self lastRequestContainsSelfStateIdle]);

        XCTAssertFalse(conversation.callDeviceIsActive);
        XCTAssertEqual(stateObserver.changes.count, 3u);
        XCTAssertEqual(stateObserver.changes.lastObject.state, VoiceChannelV2StateNoActiveUsers);
    }
    
    [WireCallCenterV2 removeObserverWithToken:stateToken];
}

- (void)testThatItDropsTheCallWhenWeAreRemovedFromConversationWithAnActiveCall
{
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    self.useGroupConversation = YES;
    
    ZMConversation *conversation = self.conversationUnderTest;
    V2CallStateTestObserver *stateObserver = [[V2CallStateTestObserver alloc] init];
    id stateToken = [WireCallCenterV2 addVoiceChannelStateObserverWithObserver:stateObserver context:self.uiMOC];
    
    // (1) selfUser initiated a call
    {
        [self selfJoinCall];
        WaitForAllGroupsToBeEmpty(0.5);
        
        XCTAssertTrue([self lastRequestContainsSelfStateJoined]);
        XCTAssertEqual(stateObserver.changes.count, 1u);
        XCTAssertEqual(stateObserver.changes.lastObject.state, VoiceChannelV2StateOutgoingCall);
    }
    
    // (2) other user joins
    {
        [self otherJoinCall];
        [self simulateMediaFlowEstablishedOnConversation:conversation];
        [self simulateParticipantsChanged:@[self.user1] onConversation:conversation];
        WaitForAllGroupsToBeEmpty(0.5);
        
        // then
        XCTAssertEqual(stateObserver.changes.count, 2u);
        XCTAssertEqual(stateObserver.changes.lastObject.state, VoiceChannelV2StateSelfConnectedToActiveChannel);
    }
    
    // (3) selfUser leaves
    {
        [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
            NOT_USED(session);
            [self.mockConversationUnderTest removeUsersByUser:self.user2 removedUser:self.selfUser];
        }];
        [self simulateMediaFlowReleasedOnConversation:conversation];
        [self simulateParticipantsChanged:@[] onConversation:conversation];
        WaitForAllGroupsToBeEmpty(0.5);
        
        // then
        XCTAssertFalse(conversation.callDeviceIsActive);
        XCTAssertFalse(conversation.isIgnoringCall);
        XCTAssertFalse(conversation.isSelfAnActiveMember);
        
        //NOTE: we have an intermediate update here (Connected->TransferReady->NoActiveUsers), MEC-1236 can solve this // FIXME no true anymore?
        XCTAssertEqual(stateObserver.changes.count, 4u); // goes through transfer state before disconnect
        XCTAssertEqual(stateObserver.changes.lastObject.state, VoiceChannelV2StateNoActiveUsers);
        
    }
    
    [WireCallCenterV2 removeObserverWithToken:stateToken];
}

- (void)testThatItReturnsIncomingCallInactiveWhenBeingReaddedToAConversationWithALeftActiveCall_SelfUserLeft
{
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    self.useGroupConversation = YES;
    
    ZMConversation *conversation = self.conversationUnderTest;
    V2CallStateTestObserver *stateObserver = [[V2CallStateTestObserver alloc] init];
    id stateToken = [WireCallCenterV2 addVoiceChannelStateObserverWithObserver:stateObserver context:self.uiMOC];
    
    // (1) selfUser initiated a call
    [self selfJoinCall];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // (2) other user joins
    [self usersJoinGroupCall:[NSOrderedSet orderedSetWithObjects:self.user1, self.user2, nil]];
    [self simulateParticipantsChanged:@[self.user1, self.user2] onConversation:conversation];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // (3) selfUser first leaves call then conversation
    {
        [self selfDropCall];
        [self simulateParticipantsChanged:@[] onConversation:self.conversationUnderTest];
        WaitForAllGroupsToBeEmpty(0.5);
        XCTAssertEqual(conversation.voiceChannel.state, VoiceChannelV2StateIncomingCallInactive);
        
        // (4) selfUser leaves conversation
        [self selfLeavesConversation];
        WaitForAllGroupsToBeEmpty(0.5);
        XCTAssertTrue([self.uiMOC saveOrRollback]);
        
        XCTAssertEqual(conversation.voiceChannel.state, VoiceChannelV2StateNoActiveUsers);
        [stateObserver.changes removeAllObjects];
    }
    // (5) selfUser is readded
    {
        // when
        [self.mockTransportSession performRemoteChanges:^(ZM_UNUSED id session) {
            [self.mockConversationUnderTest addUsersByUser:self.user2 addedUsers:@[self.selfUser]];
        }];
        WaitForAllGroupsToBeEmpty(0.5);
        
        // then
        XCTAssertTrue(conversation.isSelfAnActiveMember);
        XCTAssertEqual(stateObserver.changes.count, 1u);
        XCTAssertEqual(stateObserver.changes.lastObject.state, VoiceChannelV2StateIncomingCallInactive);
    }
    
    [WireCallCenterV2 removeObserverWithToken:stateToken];
}

- (void)testThatItReturnsIncomingCallInactiveWhenBeingReaddedToAConversationWithALeftActiveCall_SelfUserRemovedRemotely
{
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    self.useGroupConversation = YES;
    
    ZMConversation *conversation = self.conversationUnderTest;
    V2CallStateTestObserver *stateObserver = [[V2CallStateTestObserver alloc] init];
    id stateToken = [WireCallCenterV2 addVoiceChannelStateObserverWithObserver:stateObserver context:self.uiMOC];
    
    // (1) selfUser initiated a call
    [self selfJoinCall];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // (2) other user joins
    [self usersJoinGroupCall:[NSOrderedSet orderedSetWithObjects:self.user1, self.user2, nil]];
    [self simulateParticipantsChanged:@[self.user1, self.user2] onConversation:conversation];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // (3) selfUser first leaves call then conversation
    {
        [self selfDropCall];
        WaitForAllGroupsToBeEmpty(0.5);
        XCTAssertEqual(conversation.voiceChannel.state, VoiceChannelV2StateIncomingCallInactive);
        
        // (4) selfUser is removed from conversation
        [self.mockTransportSession performRemoteChanges:^(ZM_UNUSED id session) {
            [self.mockConversationUnderTest removeUsersByUser:self.user2 removedUser:self.selfUser];
        }];
        WaitForAllGroupsToBeEmpty(0.5);
        
        XCTAssertEqual(conversation.voiceChannel.state, VoiceChannelV2StateNoActiveUsers);
        [stateObserver.changes removeAllObjects];
    }
    // (5) selfUser is readded
    {
        // when
        [self.mockTransportSession performRemoteChanges:^(ZM_UNUSED id session) {
            [self.mockConversationUnderTest addUsersByUser:self.user2 addedUsers:@[self.selfUser]];
        }];
        WaitForAllGroupsToBeEmpty(0.5);
        
        // then
        XCTAssertTrue(conversation.isSelfAnActiveMember);
        XCTAssertEqual(stateObserver.changes.count, 1u);
        XCTAssertEqual(stateObserver.changes.lastObject.state, VoiceChannelV2StateIncomingCallInactive);
    }
    
    [WireCallCenterV2 removeObserverWithToken:stateToken];
}

- (void)testThatItReturnsIncomingCallInactiveWhenBeingReaddedToAConversationWithAnActiveCall_SelfUserLeft
{
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    self.useGroupConversation = YES;
    
    ZMConversation *conversation = self.conversationUnderTest;
    V2CallStateTestObserver *stateObserver = [[V2CallStateTestObserver alloc] init];
    id stateToken = [WireCallCenterV2 addVoiceChannelStateObserverWithObserver:stateObserver context:self.uiMOC];
    
    // (1) selfUser initiated a call
    [self selfJoinCall];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // (2) other user joins
    [self usersJoinGroupCall:[NSOrderedSet orderedSetWithObjects:self.user1, self.user2, nil]];
    [self simulateParticipantsChanged:@[self.user1, self.user2] onConversation:conversation];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // (3) selfUser leaves conversation without leaving the call
    {
        [self selfLeavesConversation];
        WaitForAllGroupsToBeEmpty(0.5);
        XCTAssertTrue([self.uiMOC saveOrRollback]);
        
        XCTAssertEqual(conversation.voiceChannel.state, VoiceChannelV2StateNoActiveUsers);
        [stateObserver.changes removeAllObjects];
    }
    // (4) selfUser is readded
    {
        // when
        [self.mockTransportSession performRemoteChanges:^(ZM_UNUSED id session) {
            [self.mockConversationUnderTest addUsersByUser:self.user2 addedUsers:@[self.selfUser]];
        }];
        WaitForAllGroupsToBeEmpty(0.5);
        
        // then
        XCTAssertTrue(conversation.isSelfAnActiveMember);
        XCTAssertEqual(stateObserver.changes.count, 1u);
        XCTAssertEqual(stateObserver.changes.lastObject.state, VoiceChannelV2StateIncomingCallInactive);
    }
    
    [WireCallCenterV2 removeObserverWithToken:stateToken];
}


- (void)testThatItReturnsIncomingCallInactiveWhenBeingReaddedToAConversationWithAnActiveCall_SelfUserWasRemovedRemotely
{
    // given
    self.registeredOnThisDevice = YES;
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    self.useGroupConversation = YES;
    
    ZMConversation *conversation = self.conversationUnderTest;
    V2CallStateTestObserver *stateObserver = [[V2CallStateTestObserver alloc] init];
    id stateToken = [WireCallCenterV2 addVoiceChannelStateObserverWithObserver:stateObserver context:self.uiMOC];
    
    // (1) selfUser initiated a call
    [self selfJoinCall];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // (2) other user joins
    [self usersJoinGroupCall:[NSOrderedSet orderedSetWithObjects:self.user1, self.user2, nil]];
    [self simulateParticipantsChanged:@[self.user1, self.user2] onConversation:conversation];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // (3) selfUser is removed from conversation without leaving the call
    {
        [self.mockTransportSession performRemoteChanges:^(ZM_UNUSED id session) {
            [self.mockConversationUnderTest removeUsersByUser:self.user2 removedUser:self.selfUser];
        }];
        WaitForAllGroupsToBeEmpty(0.5);
        XCTAssertTrue([self.uiMOC saveOrRollback]);
        
        XCTAssertEqual(conversation.voiceChannel.state, VoiceChannelV2StateNoActiveUsers);
        [stateObserver.changes removeAllObjects];
        XCTAssertFalse(conversation.callDeviceIsActive);
        XCTAssertEqual(conversation.callParticipants.count, 0u);
        XCTAssertEqual(conversation.activeFlowParticipants.count, 0u);
        XCTAssertFalse(conversation.isIgnoringCall);
    }
    // (4) selfUser is readded
    {
        // when
        [self.mockTransportSession performRemoteChanges:^(ZM_UNUSED id session) {
            [self.mockConversationUnderTest addUsersByUser:self.user2 addedUsers:@[self.selfUser]];
        }];
        WaitForAllGroupsToBeEmpty(0.5);
        
        // then
        XCTAssertTrue(conversation.isSelfAnActiveMember);
        XCTAssertEqual(stateObserver.changes.count, 1u);
        XCTAssertEqual(stateObserver.changes.lastObject.state, VoiceChannelV2StateIncomingCallInactive);
        XCTAssertFalse(conversation.callDeviceIsActive);
        XCTAssertEqual(conversation.callParticipants.count, 2u);
        XCTAssertTrue(conversation.isIgnoringCall);
    }
    
    [WireCallCenterV2 removeObserverWithToken:stateToken];
}

- (void)testThatWeIgnoreCallEventsIfWeAreNotActiveMemberOfConversation
{
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    self.useGroupConversation = YES;
    
    ZMConversation *conversation = self.conversationUnderTest;
    V2CallStateTestObserver *stateObserver = [[V2CallStateTestObserver alloc] init];
    id stateToken = [WireCallCenterV2 addVoiceChannelStateObserverWithObserver:stateObserver context:self.uiMOC];
    
    // (1) selfUser initiated a call
    [self selfJoinCall];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // (2) other user joins
    [self usersJoinGroupCall:[NSOrderedSet orderedSetWithObjects:self.user2, self.user3, nil]];
    [self simulateParticipantsChanged:@[self.user2, self.user3] onConversation:conversation];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // (3) selfUser first leaves call then conversation
    [self selfDropCall];
    WaitForAllGroupsToBeEmpty(0.5);
    XCTAssertEqual(conversation.voiceChannel.state, VoiceChannelV2StateIncomingCallInactive);
    
    // (4) selfUser leaves conversation
    [self selfLeavesConversation];
    WaitForAllGroupsToBeEmpty(0.5);
    XCTAssertEqual(conversation.voiceChannel.state, VoiceChannelV2StateNoActiveUsers);
    [stateObserver.changes removeAllObjects];
    
    // (5) some user added to call
    [self usersJoinGroupCall:[NSOrderedSet orderedSetWithObject:self.user1]];
    WaitForAllGroupsToBeEmpty(0.5);
    
    //then
    // ignore all call state events while we are not active member of conversation
    XCTAssertEqual(stateObserver.changes.count, 0u);
    XCTAssertEqual(conversation.voiceChannel.state, VoiceChannelV2StateNoActiveUsers);
    
    [WireCallCenterV2 removeObserverWithToken:stateToken];
}

- (void)testThatItReturnsNoActiveUsersAfterIgnoredCallEnds
{
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    self.useGroupConversation = YES;
    
    ZMConversation *conversation = self.conversationUnderTest;
    V2CallStateTestObserver *stateObserver = [[V2CallStateTestObserver alloc] init];
    id stateToken = [WireCallCenterV2 addVoiceChannelStateObserverWithObserver:stateObserver context:self.uiMOC];
    
    NSMutableOrderedSet *joinedUsers = [[[self mockConversationUnderTest] activeUsers] mutableCopy];
    [joinedUsers zm_sortUsingComparator:[MockFlowManager conferenceComparator] valueGetter:^id(MockUser *mockUser) {
        return mockUser.identifier;
    }];
    [joinedUsers removeObject:self.selfUser];
    
    // (1) selfUser initiated a call
    {
        [self selfJoinCall];
        WaitForAllGroupsToBeEmpty(0.5);
    }
    
    // (2) other users join
    {
        [self usersJoinGroupCall:joinedUsers];
        [self simulateParticipantsChanged:joinedUsers.array onConversation:conversation];
        WaitForAllGroupsToBeEmpty(0.5);
    }
    
    // (3) selfUser leaves
    {
        [self selfDropCall];
        WaitForAllGroupsToBeEmpty(0.5);
        
        // then
        XCTAssertFalse(conversation.callDeviceIsActive);
        XCTAssertTrue(conversation.isIgnoringCall);
        XCTAssertEqual(conversation.voiceChannel.state, VoiceChannelV2StateIncomingCallInactive);
        [stateObserver.changes removeAllObjects];
    }
    
    // (4) other users leave
    // the call state should be NoActiveUsers (not IncomingCallInactive)
    {
        // when
        [self usersLeaveGroupCall:joinedUsers];
        WaitForAllGroupsToBeEmpty(0.5);
        
        // then
        XCTAssertEqual(conversation.voiceChannel.state, VoiceChannelV2StateNoActiveUsers);
        XCTAssertEqual(stateObserver.changes.count, 2u); // goes through transfer state before disconnect
        XCTAssertEqual(stateObserver.changes.lastObject.state, VoiceChannelV2StateNoActiveUsers);
        [stateObserver.changes removeAllObjects];
    }
    
    // (5) others reinitiate call
    // isIgnoringCall should be reset and
    // the call state should be IncomingCall (not IncomingCallInactive)
    {
        // when
        [self usersJoinGroupCall:joinedUsers];
        WaitForAllGroupsToBeEmpty(0.5);
        
        // then
        XCTAssertFalse(conversation.isIgnoringCall);
        XCTAssertEqual(conversation.voiceChannel.state, VoiceChannelV2StateIncomingCall);
        XCTAssertEqual(stateObserver.changes.count, 1u);
        XCTAssertEqual(stateObserver.changes.lastObject.state, VoiceChannelV2StateIncomingCall);
    }
    
    [WireCallCenterV2 removeObserverWithToken:stateToken];
}

- (void)testThatTheUserCanTryToJoinAgainAfterSheWasRejectedBecauseTheCallWasFull
{
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    self.useGroupConversation = YES;
    
    ZMConversation *conversation = self.conversationUnderTest;
    NSString *callStatePath = [NSString stringWithFormat:@"/conversations/%@/call/state", conversation.remoteIdentifier.transportString];
    
    NSMutableDictionary *joinSelfDict = [NSMutableDictionary dictionary];
    joinSelfDict[@"state"] = @"joined";
    joinSelfDict[@"videod"] = @(NO);
    NSMutableDictionary *leaveSelfDict = [NSMutableDictionary dictionary];
    leaveSelfDict[@"state"] = @"idle";
    leaveSelfDict[@"suspended"] = @(NO);
    joinSelfDict[@"suspended"] = @(NO);

    ZMTransportRequest *requestToJoin = [ZMTransportRequest requestWithPath:callStatePath
                                                                     method:ZMMethodPUT
                                                                    payload:@{ @"self" : joinSelfDict, @"cause" : @"requested"}];
    ZMTransportRequest *requestToLeave = [ZMTransportRequest requestWithPath:callStatePath
                                                                      method:ZMMethodPUT
                                                                     payload:@{ @"self" : leaveSelfDict, @"cause" : @"requested"}];
    
    NSMutableOrderedSet *joinedUsers = [self.mockConversationUnderTest.activeUsers mutableCopy];
    [joinedUsers removeObject:self.selfUser];
    
    // other users join
    {
        [self usersJoinGroupCall:joinedUsers];
        [self simulateParticipantsChanged:joinedUsers.array onConversation:conversation];
        WaitForAllGroupsToBeEmpty(0.5);
        self.mockTransportSession.maxCallParticipants = joinedUsers.count;
    }

    [self.mockTransportSession resetReceivedRequests];
    
    // when: it tries to join
    [self.userSession performChanges:^{
        [conversation.voiceChannelRouter.v2 joinWithVideo:NO];
    }];
    WaitForAllGroupsToBeEmpty(0.5);

    // then
    XCTAssertEqual(self.mockTransportSession.receivedRequests.count, 1u);
    ZMTransportRequest *firstRequest = self.mockTransportSession.receivedRequests.firstObject;
    XCTAssertEqualObjects(firstRequest, requestToJoin);
    XCTAssertNotEqualObjects(firstRequest, requestToLeave);
    XCTAssertEqual(conversation.voiceChannel.state, VoiceChannelV2StateIncomingCall);
    
    [self.mockTransportSession resetReceivedRequests];
    
    // when: it tries to join again
    [self.userSession performChanges:^{
        [conversation.voiceChannelRouter.v2 joinWithVideo:NO];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(self.mockTransportSession.receivedRequests.count, 1u);
    
    ZMTransportRequest *secondRequest = self.mockTransportSession.receivedRequests.firstObject;
    XCTAssertEqualObjects(secondRequest, requestToJoin);
    XCTAssertNotEqualObjects(secondRequest, requestToLeave);
    XCTAssertEqual(conversation.voiceChannel.state, VoiceChannelV2StateIncomingCall);
}

- (void)testThatItLeavesACallWhenRestartingTheAppWithAnOngoingCall
{
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    self.useGroupConversation = YES;
    
    [self selfJoinCall];
    WaitForAllGroupsToBeEmpty(0.5);

    [self usersJoinGroupCall:self.mockConversationUnderTest.activeUsers];
    WaitForAllGroupsToBeEmpty(0.5);

    XCTAssertEqual(self.conversationUnderTest.callParticipants.count, 4u);
    
    // when
    [self simulateAppStopped];
    
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    WaitForEverythingToBeDone();
    
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        [session simulatePushChannelOpened];
    }];
    WaitForEverythingToBeDone();
    
    // then
    XCTAssert([self waitForCustomExpectationsWithTimeout:0.5]);
    XCTAssertEqual(self.conversationUnderTest.callParticipants.count, 3u);
    XCTAssertEqual(self.conversationUnderTest.voiceChannel.state, VoiceChannelV2StateIncomingCallInactive);

    XCTAssertTrue([self lastRequestContainsSelfStateIdle]);
}


- (void)testThatItDoesNotLeaveACallWhenRestartingTheAppWithAnOngoingCall_InterruptedByGSMCall
{
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    self.useGroupConversation = YES;
    
    [self selfJoinCall];
    WaitForAllGroupsToBeEmpty(0.5);
    
    [self usersJoinGroupCall:self.mockConversationUnderTest.activeUsers];
    WaitForAllGroupsToBeEmpty(0.5);
    XCTAssertEqual(self.conversationUnderTest.callParticipants.count, 4u);
    
    [self.mockTransportSession resetReceivedRequests];

    // (1)when call is interrupted by incoming call
    {
        id call = [OCMockObject niceMockForClass:[CTCall class]];
        [(CTCall *)[[call expect] andReturn:CTCallStateDialing] callState];
        
        self.gsmCallHandler.callEventHandler(call);
        WaitForAllGroupsToBeEmpty(0.5);
        
        // then
        XCTAssertTrue([self lastRequestContainsSelfStateJoinedWithCauseSuspended:YES]);
    }
    
    [self.mockTransportSession resetReceivedRequests];

    // when we restart the app
    {
        [self simulateAppStopped];
        [self simulateAppRestarted];
        
        // then
        WaitForAllGroupsToBeEmpty(0.5);
        XCTAssertEqual(self.conversationUnderTest.callParticipants.count, 4u);
        XCTAssertTrue([self lastRequestContainsSelfStateJoinedWithCauseSuspended: NO]);
        XCTAssertFalse([self lastRequestContainsSelfStateIdle]);

    }
}

- (void)testThatItRejoinsAnInterruptedCallWhenGSMCallEnds
{
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    self.useGroupConversation = YES;
    
    [self selfJoinCall];
    WaitForAllGroupsToBeEmpty(0.5);
    
    [self usersJoinGroupCall:self.mockConversationUnderTest.activeUsers];
    WaitForAllGroupsToBeEmpty(0.5);
    XCTAssertEqual(self.conversationUnderTest.callParticipants.count, 4u);
    
    [self.mockTransportSession resetReceivedRequests];
    
    // (1)when call is interrupted by incoming call
    {
        id call = [OCMockObject niceMockForClass:[CTCall class]];
        [(CTCall *)[[call stub] andReturn:CTCallStateIncoming] callState];
        
        self.gsmCallHandler.callEventHandler(call);
        WaitForAllGroupsToBeEmpty(0.5);
        
        // then
        XCTAssertTrue([self lastRequestContainsSelfStateJoinedWithCauseSuspended:YES]);
    }
    [self.mockTransportSession resetReceivedRequests];

    // when the GSM call ends
    {
        id call = [OCMockObject niceMockForClass:[CTCall class]];
        [(CTCall *)[[call stub] andReturn:CTCallStateDisconnected] callState];
        
        self.gsmCallHandler.callEventHandler(call);
        [self spinMainQueueWithTimeout:0.3];
        WaitForAllGroupsToBeEmpty(0.5);
        
        // then
        XCTAssertTrue([self lastRequestContainsSelfStateJoinedWithCauseSuspended:NO]);
    }
}

- (void)testThatItSendsARequestToIgnoreWhenIgnoringACall
{
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);

    [self otherJoinCall];
    WaitForAllGroupsToBeEmpty(0.5);

    // when
    [self.userSession performChanges:^{
        [self.conversationUnderTest.voiceChannelRouter.v2 ignore];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertTrue([self lastRequestContainsSelfStateIdleWithIsIgnored:YES]);
    XCTAssertTrue(self.conversationUnderTest.isIgnoringCall);
    XCTAssertFalse(self.conversationUnderTest.callDeviceIsActive);

}


- (void)testThatItSetsIsIgnoringCallWhenSelfUserIgnoresCall
{
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    
    [self otherJoinCall];
    WaitForAllGroupsToBeEmpty(0.5);
    
    NSUInteger eventCount = self.mockTransportSession.updateEvents.count;

    // when
    [self.mockTransportSession performRemoteChanges:^(ZM_UNUSED id session) {
        [self.mockConversationUnderTest ignoreCallByUser:self.selfUser];
        [self.mockTransportSession saveAndCreatePushChannelEventForSelfUser];
        
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertGreaterThan(self.mockTransportSession.updateEvents.count, eventCount);
    XCTAssertFalse([self lastRequestContainsSelfStateIdleWithIsIgnored:YES]);
    XCTAssertTrue(self.conversationUnderTest.isIgnoringCall);
    XCTAssertFalse(self.conversationUnderTest.callDeviceIsActive);
}


@end



@implementation CallingTests (Websocket)

- (void)testThatItDoesNotSendOutRequestsWhileTheWebsocketIsDown
{
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    
    // when push Channel closes
    // we are not creating a request
    {
        [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
            [session simulatePushChannelClosed];
        }];
        WaitForAllGroupsToBeEmpty(0.5);
        
        [self selfJoinCall];
        WaitForAllGroupsToBeEmpty(0.5);
        
        // then
        XCTAssertFalse([self lastRequestContainsSelfStateJoined]);
    }
    
    // when push Channel opens again
    // we notify the operation loop about new request
    {
        [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
            [session simulatePushChannelOpened];
        }];
        WaitForAllGroupsToBeEmpty(0.5);
        
        // then
        XCTAssertTrue([self lastRequestContainsSelfStateJoined]);
    }
}

@end


@implementation CallingTests (Logging)

- (void)testThatItLogsEverything
{
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    
    ZMConversation *conversation = self.conversationUnderTest;
    
    // when
    [self selfJoinCall];
    WaitForAllGroupsToBeEmpty(0.5);
    
    XCTAssertTrue([self lastRequestContainsSelfStateJoined]);
    
    [self otherJoinCall];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(conversation.voiceChannel.state, VoiceChannelV2StateSelfIsJoiningActiveChannel);
    
    NSArray *messages = [self.mockTransportSession.mockFlowManager AVSlogMessagesForConversationID:conversation.remoteIdentifier.transportString];
    XCTAssertEqual(messages.count, 8u);
    NSString *firstMessage = messages.firstObject;
    NSString *lastMessage = messages.lastObject;

    NSString *expectedFirstMessage = [NSString stringWithFormat: @"Self user wants to join voice channel \n"
                                      @"-->  conversation remoteID: %@ \n"
                                      @"-->  current voiceChannel state: NoActiveUsers \n"
                                      @"-->  current callDeviceIsActive: 0 \n"
                                      @"-->  current hasLocalModificationsForCallDeviceIsActive: 0 \n"
                                      @"-->  current is flow active: 0 \n"
                                      @"-->  current self isJoined: 0 \n"
                                      @"-->  current other isJoined: 0 \n"
                                      @"-->  current isIgnoringCall: 0 \n"
                                      @"-->  conversation.isOutgoingCall: 0\n"
                                      @"-->  websocket is open: 1" , conversation.remoteIdentifier.transportString];
    
    NSString *expectedLastMessage = [NSString stringWithFormat:@"Finished updating call state from push event \n"
                                     @"-->  conversation remoteID: %@ \n"
                                     @"-->  current voiceChannel state: SelfIsJoiningActiveChannel \n"
                                     @"-->  current callDeviceIsActive: 1 \n"
                                     @"-->  current hasLocalModificationsForCallDeviceIsActive: 0 \n"
                                     @"-->  current is flow active: 0 \n"
                                     @"-->  current self isJoined: 1 \n"
                                     @"-->  current other isJoined: 1 \n"
                                     @"-->  current isIgnoringCall: 0 \n"
                                     @"-->  conversation.isOutgoingCall: 1\n"
                                     @"-->  websocket is open: 1", conversation.remoteIdentifier.transportString];
    
    XCTAssertEqualObjects(firstMessage, expectedFirstMessage);
    XCTAssertEqualObjects(lastMessage, expectedLastMessage);
    
}

@end
