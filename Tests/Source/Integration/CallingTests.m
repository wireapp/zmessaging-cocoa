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

#import "CallingTests.h"
#import "ZMVoiceChannel+CallFlow.h"
#import "AVSFlowManager.h"
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

- (void)conversationWindowDidChange:(MessageWindowChangeInfo *)note
{
    if(self.notificationHandler) {
        self.notificationHandler(note);
    }
    
    [self.window.conversation setVisibleWindowFromMessage:self.window.conversation.messages.firstObject toMessage:self.window.conversation.messages.lastObject];
    [self.notifications addObject:note];
}

- (void)registerOnConversation:(ZMConversation *)conversation;
{
    NSAssert(self.observerToken == nil, @"Registered twice??");
    self.window = [conversation conversationWindowWithSize:20];
    self.observerToken = [self.window addConversationWindowObserver:self];
}

- (void)dealloc
{
    [self.window removeConversationWindowObserverToken:self.observerToken];
}

@end



@implementation CallingTests

- (void)setUp {
    [super setUp];
    
    self.voiceChannelStateDidChangeNotes = [NSMutableArray array];
    self.voiceChannelParticipantStateDidChangeNotes = [NSMutableArray array];
    self.windowObserver = [[TestWindowObserver alloc] init];
    
}

- (void)tearDown {
    self.voiceChannelStateDidChangeNotes = nil;
    self.voiceChannelParticipantStateDidChangeNotes = nil;
    self.windowObserver = nil;
    WaitForAllGroupsToBeEmpty(0.5);
    [self tearDownVoiceChannelForConversation:self.conversationUnderTest];
    [ZMCallTimer resetTestCallTimeout];
    self.useGroupConversation = NO;
    [self.gsmCallHandler setActiveCallSyncConversation:nil];
    [super tearDown];
}

- (void)voiceChannelStateDidChange:(VoiceChannelStateChangeInfo *)note
{
    [self.voiceChannelStateDidChangeNotes addObject:note];
}

- (void)voiceChannelParticipantsDidChange:(VoiceChannelParticipantsChangeInfo *)note;
{
    [self.voiceChannelParticipantStateDidChangeNotes addObject:note];
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
    ZMConversation *syncConv = (id)[self.userSession.syncManagedObjectContext objectWithID:conversation.objectID];
    [syncConv.voiceChannel tearDown];
}

- (BOOL)lastRequestContainsSelfStateJoined
{
    return [self lastRequestContainsSelfStateJoinedWithCauseSuspended:NO];
}
- (BOOL)lastRequestContainsSelfStateJoinedWithCauseSuspended:(BOOL)causeIsIntertupted
{
    ZMTransportRequest *joinRequest = [self.mockTransportSession.receivedRequests firstObjectMatchingWithBlock:^BOOL(ZMTransportRequest *request) {
        BOOL rightPath = [request.path hasPrefix:@"/conversations/"] && [request.path hasSuffix:@"/call/state"];
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
        [self.conversationUnderTest.voiceChannel join];
    }];
}

- (void)selfDropCall
{
    [self.userSession enqueueChanges:^{
        [self.conversationUnderTest.voiceChannel leave];
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
    ZMConversation *oneToOneConversation = self.conversationUnderTest;
    
    id token = [oneToOneConversation.voiceChannel addVoiceChannelStateObserver:self];
    
    // when
    {
        [self selfJoinCall];
        WaitForAllGroupsToBeEmpty(0.5);
        
        // then
        XCTAssertTrue([self lastRequestContainsSelfStateJoined]);
        [self.mockTransportSession resetReceivedRequests];
        
        XCTAssertEqual(self.voiceChannelStateDidChangeNotes.count, 1u);
        VoiceChannelStateChangeInfo *note = self.voiceChannelStateDidChangeNotes.firstObject;
        XCTAssertNotNil(note);
        XCTAssertEqual(note.voiceChannel, oneToOneConversation.voiceChannel);
        XCTAssertEqual(note.previousState, ZMVoiceChannelStateNoActiveUsers);
        XCTAssertEqual(note.currentState, ZMVoiceChannelStateOutgoingCall);
    }
    
    [self.mockTransportSession resetReceivedRequests];
    [self.voiceChannelStateDidChangeNotes removeAllObjects];
    
    // when
    {
        [self selfDropCall];
        WaitForAllGroupsToBeEmpty(0.5);
        
        // then
        XCTAssertTrue([self lastRequestContainsSelfStateIdle]);
        XCTAssertEqual(self.voiceChannelStateDidChangeNotes.count, 1u);
        VoiceChannelStateChangeInfo *note = self.voiceChannelStateDidChangeNotes.firstObject;
        XCTAssertNotNil(note);
        XCTAssertEqual(note.voiceChannel, oneToOneConversation.voiceChannel);
        XCTAssertEqual(note.previousState, ZMVoiceChannelStateOutgoingCall);
        XCTAssertEqual(note.currentState, ZMVoiceChannelStateNoActiveUsers);

    }
    [oneToOneConversation.voiceChannel removeVoiceChannelStateObserverForToken:token];
}


- (void)testThatItSendsOutAllExpectedNotificationsWhenSelfUserCalls
{
    // no active users -> self is calling -> self connected to active channel -> no active users
    
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    ZMConversation *oneToOneConversation = self.conversationUnderTest;
    
    id stateToken = [oneToOneConversation.voiceChannel addVoiceChannelStateObserver:self];
    id participantToken = [oneToOneConversation.voiceChannel addCallParticipantsObserver:self];
    
    // (1) self calling & backend acknowledges
    //
    // when
    [self selfJoinCall];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(self.voiceChannelStateDidChangeNotes.count, 1u);
    VoiceChannelStateChangeInfo *info1 = self.voiceChannelStateDidChangeNotes.lastObject;
    XCTAssertEqual(info1.previousState, ZMVoiceChannelStateNoActiveUsers);
    XCTAssertEqual(info1.currentState, ZMVoiceChannelStateOutgoingCall);
    [self.voiceChannelStateDidChangeNotes removeAllObjects];
    
    XCTAssertEqual(self.voiceChannelParticipantStateDidChangeNotes.count, 0u);
    [self.voiceChannelParticipantStateDidChangeNotes removeAllObjects];
    // (2) other party joins
    //
    // when
    [self otherJoinCall];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(self.voiceChannelParticipantStateDidChangeNotes.count, 1u);
    VoiceChannelParticipantsChangeInfo *partInfo2 = self.voiceChannelParticipantStateDidChangeNotes.lastObject;
    XCTAssertEqualObjects(partInfo2.insertedIndexes, [NSIndexSet indexSetWithIndex:0]);
    XCTAssertEqualObjects(partInfo2.updatedIndexes, [NSIndexSet indexSet]);
    XCTAssertEqualObjects(partInfo2.deletedIndexes, [NSIndexSet indexSet]);
    XCTAssertEqualObjects(partInfo2.movedIndexPairs, @[]);
    [self.voiceChannelParticipantStateDidChangeNotes removeAllObjects];

    // (3) flow aquired
    //
    // when
    [self simulateMediaFlowEstablishedOnConversation:oneToOneConversation];
    [self simulateParticipantsChanged:@[self.user2] onConversation:oneToOneConversation];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(self.voiceChannelStateDidChangeNotes.count, 2u);
    VoiceChannelStateChangeInfo *info2 = self.voiceChannelStateDidChangeNotes.lastObject;
    XCTAssertEqual(info2.previousState, ZMVoiceChannelStateSelfIsJoiningActiveChannel);
    XCTAssertEqual(info2.currentState, ZMVoiceChannelStateSelfConnectedToActiveChannel);
    [self.voiceChannelStateDidChangeNotes removeAllObjects];
    
    XCTAssertEqual(self.voiceChannelParticipantStateDidChangeNotes.count, 1u);
    VoiceChannelParticipantsChangeInfo *partInfo3 = self.voiceChannelParticipantStateDidChangeNotes.lastObject;
    XCTAssertEqualObjects(partInfo3.insertedIndexes, [NSIndexSet indexSet]);
    XCTAssertEqualObjects(partInfo3.updatedIndexes, [NSIndexSet indexSetWithIndex:0]);
    XCTAssertEqualObjects(partInfo3.deletedIndexes, [NSIndexSet indexSet]);
    XCTAssertEqualObjects(partInfo3.movedIndexPairs, @[]);
    [self.voiceChannelParticipantStateDidChangeNotes removeAllObjects];

    // (4) self user leaves
    //
    // when
    [self selfDropCall];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertGreaterThanOrEqual(self.voiceChannelStateDidChangeNotes.count, 1u);
    VoiceChannelStateChangeInfo *info3 = self.voiceChannelStateDidChangeNotes.lastObject;

    XCTAssertEqual(info3.previousState, ZMVoiceChannelStateSelfConnectedToActiveChannel);
    XCTAssertEqual(info3.currentState, ZMVoiceChannelStateNoActiveUsers);
    [self.voiceChannelStateDidChangeNotes removeAllObjects];
    
    XCTAssertEqual(self.voiceChannelParticipantStateDidChangeNotes.count, 1u);
    VoiceChannelParticipantsChangeInfo *partInfo4 = self.voiceChannelParticipantStateDidChangeNotes.lastObject;
    XCTAssertEqualObjects(partInfo4.insertedIndexes, [NSIndexSet indexSet]);
    XCTAssertEqualObjects(partInfo4.updatedIndexes, [NSIndexSet indexSet]);
    XCTAssertEqualObjects(partInfo4.deletedIndexes, [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, 1)]);
    XCTAssertEqualObjects(partInfo4.movedIndexPairs, @[]);
    
    [oneToOneConversation.voiceChannel removeVoiceChannelStateObserverForToken:stateToken];
    [oneToOneConversation.voiceChannel removeCallParticipantsObserverForToken:participantToken];
}

- (void)checkNotification:(VoiceChannelStateChangeInfo *)note fromState:(ZMVoiceChannelState)fromState toState:(ZMVoiceChannelState)toState failureRecorder:(ZMTFailureRecorder *)failureRecorder
{
    FHAssertEqual(failureRecorder, note.previousState, fromState);
    FHAssertEqual(failureRecorder, note.currentState, toState);
}

- (void)checkNotifications:(NSArray *)notes at:(NSUInteger)index fromState:(ZMVoiceChannelState)fromState toState:(ZMVoiceChannelState)toState failureRecorder:(ZMTFailureRecorder *)failureRecorder {

    [self checkNotification:notes[index] fromState:fromState toState:toState failureRecorder:failureRecorder];
}


- (void)testThatItSendsOutAllExpectedNotificationsWhenOtherUserCalls
{
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    ZMConversation * NS_VALID_UNTIL_END_OF_SCOPE oneToOneConversation = self.conversationUnderTest;
    id stateToken = [oneToOneConversation.voiceChannel addVoiceChannelStateObserver:self];
    id participantsToken = [oneToOneConversation.voiceChannel addCallParticipantsObserver:self];

    // (1) other user joins
    // when
    [self otherJoinCall];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(self.voiceChannelStateDidChangeNotes.count, 1u);
    XCTAssertEqual([self.voiceChannelStateDidChangeNotes.firstObject previousState], ZMVoiceChannelStateNoActiveUsers);
    XCTAssertEqual([self.voiceChannelStateDidChangeNotes.firstObject currentState], ZMVoiceChannelStateIncomingCall);
    [self.voiceChannelStateDidChangeNotes removeAllObjects];
    
    // (2) we join
    // when
    [self selfJoinCall];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    {
        XCTAssertEqual(self.voiceChannelStateDidChangeNotes.count, 1u);
        XCTAssertEqual([self.voiceChannelStateDidChangeNotes.firstObject previousState], ZMVoiceChannelStateIncomingCall);
        XCTAssertEqual([self.voiceChannelStateDidChangeNotes.firstObject currentState], ZMVoiceChannelStateSelfIsJoiningActiveChannel);
        [self.voiceChannelStateDidChangeNotes removeAllObjects];
        
        [self.voiceChannelParticipantStateDidChangeNotes removeAllObjects];
    }
    
    // (3) flow aquired
    //
    // when
    [self simulateMediaFlowEstablishedOnConversation:self.conversationUnderTest];
    [self simulateParticipantsChanged:@[self.user2] onConversation:self.conversationUnderTest];
    WaitForAllGroupsToBeEmpty(0.5);

    // then
    {
        XCTAssertEqual(self.voiceChannelStateDidChangeNotes.count, 1u);
        XCTAssertEqual([self.voiceChannelStateDidChangeNotes.firstObject previousState], ZMVoiceChannelStateSelfIsJoiningActiveChannel);
        XCTAssertEqual([self.voiceChannelStateDidChangeNotes.firstObject currentState], ZMVoiceChannelStateSelfConnectedToActiveChannel);
        [self.voiceChannelStateDidChangeNotes removeAllObjects];
        
        XCTAssertEqual(self.voiceChannelParticipantStateDidChangeNotes.count, 1u); // we notify that user connected
        [self.voiceChannelParticipantStateDidChangeNotes removeAllObjects];
    }
    
    
    // (4) the other user leaves. The backend tells us we are both idle
    
    [self otherDropsCall];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    {
        XCTAssertEqual(self.voiceChannelStateDidChangeNotes.count, 1u);
        VoiceChannelStateChangeInfo *firstInfo = self.voiceChannelStateDidChangeNotes.firstObject;
        XCTAssertEqual(firstInfo.previousState, ZMVoiceChannelStateSelfConnectedToActiveChannel);
        XCTAssertEqual(firstInfo.currentState, ZMVoiceChannelStateNoActiveUsers);        
        [self.voiceChannelStateDidChangeNotes removeAllObjects];
        
        XCTAssertEqual(self.voiceChannelParticipantStateDidChangeNotes.count, 1u);
        
    }
    [oneToOneConversation.voiceChannel removeVoiceChannelStateObserverForToken:stateToken];
    [oneToOneConversation.voiceChannel removeVoiceChannelStateObserverForToken:participantsToken];
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
    id stateToken = [oneToOneConversation.voiceChannel addVoiceChannelStateObserver:self];

    // (1) other user joins
    // when
    [self otherJoinCall];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(self.voiceChannelStateDidChangeNotes.count, 1u);
    XCTAssertEqual([self.voiceChannelStateDidChangeNotes.firstObject previousState], ZMVoiceChannelStateNoActiveUsers);
    XCTAssertEqual([self.voiceChannelStateDidChangeNotes.firstObject currentState], ZMVoiceChannelStateIncomingCall);
    [self.voiceChannelStateDidChangeNotes removeAllObjects];
    
    // (2) we ignore
    // when
    [self.userSession performChanges:^{
        [oneToOneConversation.voiceChannel ignoreIncomingCall];
    }];
    WaitForAllGroupsToBeEmpty(0.5);

    // then
    XCTAssertEqual(self.voiceChannelStateDidChangeNotes.count, 1u);
    XCTAssertEqual([self.voiceChannelStateDidChangeNotes.firstObject previousState], ZMVoiceChannelStateIncomingCall);
    XCTAssertEqual([self.voiceChannelStateDidChangeNotes.firstObject currentState], ZMVoiceChannelStateNoActiveUsers);
    
    [oneToOneConversation.voiceChannel removeVoiceChannelStateObserverForToken:stateToken];
    [self tearDownVoiceChannelForConversation:oneToOneConversation];
}

- (void)testThatItDoesNotAutomaticallyIgnoreASecondIncomingCall
{
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    WaitForAllGroupsToBeEmpty(0.5);

    ZMConversation *oneToOneConversation = self.conversationUnderTest;
    id stateToken = [oneToOneConversation.voiceChannel addVoiceChannelStateObserver:self];

    // (1) other user joins
    // when
    [self otherJoinCall];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(self.voiceChannelStateDidChangeNotes.count, 1u);
    XCTAssertEqual([self.voiceChannelStateDidChangeNotes.firstObject previousState], ZMVoiceChannelStateNoActiveUsers);
    XCTAssertEqual([self.voiceChannelStateDidChangeNotes.firstObject currentState], ZMVoiceChannelStateIncomingCall);
    [self.voiceChannelStateDidChangeNotes removeAllObjects];

    // (2) another user joins another conversation
    // when
    [self.mockTransportSession performRemoteChanges:^(ZM_UNUSED id session) {
        NOT_USED(session);
        [self.selfToUser1Conversation addUserToCall:self.user2];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(self.voiceChannelStateDidChangeNotes.count, 0u);
    ZMConversation *secondCallingConversation = [self conversationForMockConversation:self.selfToUser2Conversation];
    XCTAssertEqual(secondCallingConversation.voiceChannel.state, ZMVoiceChannelStateIncomingCall);
    
    [oneToOneConversation.voiceChannel removeVoiceChannelStateObserverForToken:stateToken];
    [self tearDownVoiceChannelForConversation:[self conversationForMockConversation:self.selfToUser1Conversation]];
}

- (void)testThatItSendsANotificationIfIgnoringACallAndImmediatelyAcceptingIt
{
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    ZMConversation *oneToOneConversation = self.conversationUnderTest;
    id stateToken = [oneToOneConversation.voiceChannel addVoiceChannelStateObserver:self];

    // (1) other user joins
    // when
    [self otherJoinCall];
    WaitForAllGroupsToBeEmpty(0.5);
    
    [self.voiceChannelParticipantStateDidChangeNotes removeAllObjects];
    [self.voiceChannelStateDidChangeNotes removeAllObjects];
    
    // (2) we ignore
    // when
    [self.userSession performChanges:^{
        [oneToOneConversation.voiceChannel ignoreIncomingCall];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(self.voiceChannelStateDidChangeNotes.count, 1u);
    XCTAssertEqual([self.voiceChannelStateDidChangeNotes.firstObject previousState], ZMVoiceChannelStateIncomingCall);
    XCTAssertEqual([self.voiceChannelStateDidChangeNotes.firstObject currentState], ZMVoiceChannelStateNoActiveUsers);

    [self.voiceChannelParticipantStateDidChangeNotes removeAllObjects];
    [self.voiceChannelStateDidChangeNotes removeAllObjects];
    // when
    [self selfJoinCall];
    WaitForAllGroupsToBeEmpty(0.5);

    // then
    XCTAssertEqual(self.voiceChannelStateDidChangeNotes.count, 1u);
    XCTAssertEqual([self.voiceChannelStateDidChangeNotes.firstObject previousState], ZMVoiceChannelStateNoActiveUsers);
    XCTAssertEqual([self.voiceChannelStateDidChangeNotes.firstObject currentState], ZMVoiceChannelStateSelfIsJoiningActiveChannel);
    
    [oneToOneConversation.voiceChannel removeVoiceChannelStateObserverForToken:stateToken];
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
    id stateToken = [conversation.voiceChannel addVoiceChannelStateObserver:self];
    
    // when
    [self selfJoinCall];
    WaitForAllGroupsToBeEmpty(0.5);
    
    XCTAssertTrue([self lastRequestContainsSelfStateJoined]);
    
    [self otherJoinCall];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(conversation.voiceChannel.state, ZMVoiceChannelStateSelfIsJoiningActiveChannel);
    VoiceChannelStateChangeInfo *lastChange = self.voiceChannelStateDidChangeNotes.lastObject;
    XCTAssertEqual(lastChange.currentState, ZMVoiceChannelStateSelfIsJoiningActiveChannel);
    XCTAssertEqual(lastChange.previousState, ZMVoiceChannelStateOutgoingCall);

    [conversation.voiceChannel removeVoiceChannelStateObserverForToken:stateToken];
}

- (void)testThatWeAreInThe_JoiningState_AfterJoiningAnd_Not_ActivatingTheFlow_IncomingCall_OneOnOne
{
    
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    
    ZMConversation *conversation = self.conversationUnderTest;
    id stateToken = [conversation.voiceChannel addVoiceChannelStateObserver:self];
    
    // when
    [self otherJoinCall];
    WaitForAllGroupsToBeEmpty(0.5);
    
    [self selfJoinCall];
    WaitForAllGroupsToBeEmpty(0.5);
    
    XCTAssertTrue([self lastRequestContainsSelfStateJoined]);
    
    // then
    XCTAssertEqual(conversation.voiceChannel.state, ZMVoiceChannelStateSelfIsJoiningActiveChannel);
    XCTAssertEqual(self.voiceChannelStateDidChangeNotes.count, 2u);
    VoiceChannelStateChangeInfo *lastChange = self.voiceChannelStateDidChangeNotes.lastObject;
    XCTAssertEqual(lastChange.currentState, ZMVoiceChannelStateSelfIsJoiningActiveChannel);
    
    [conversation.voiceChannel removeVoiceChannelStateObserverForToken:stateToken];
}

- (void)testThatWeAreInThe_JoiningState_AfterJoiningAnd_Not_ActivatingTheFlow_IncomingCall_Group
{
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    self.useGroupConversation= YES;
    
    ZMConversation *conversation = self.conversationUnderTest;
    id stateToken = [conversation.voiceChannel addVoiceChannelStateObserver:self];
    
    // when
    [self otherJoinCall];
    WaitForAllGroupsToBeEmpty(0.5);
    
    [self selfJoinCall];
    WaitForAllGroupsToBeEmpty(0.5);
    
    XCTAssertTrue([self lastRequestContainsSelfStateJoined]);
    
    // then
    XCTAssertEqual(conversation.voiceChannel.state, ZMVoiceChannelStateSelfIsJoiningActiveChannel);
    XCTAssertEqual(self.voiceChannelStateDidChangeNotes.count, 2u);
    VoiceChannelStateChangeInfo *lastChange = self.voiceChannelStateDidChangeNotes.lastObject;
    XCTAssertEqual(lastChange.currentState, ZMVoiceChannelStateSelfIsJoiningActiveChannel);
    
    [conversation.voiceChannel removeVoiceChannelStateObserverForToken:stateToken];
}

- (void)testThatWeAreInThe_ConnectedState_AfterJoiningAndActivatingTheFlow
{
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    
    ZMConversation *conversation = self.conversationUnderTest;
    id stateToken = [conversation.voiceChannel addVoiceChannelStateObserver:self];

    // when
    [self selfJoinCall];
    WaitForAllGroupsToBeEmpty(0.5);
    
    XCTAssertTrue([self lastRequestContainsSelfStateJoined]);
    
    [self otherJoinCall];
    WaitForAllGroupsToBeEmpty(0.5);
    XCTAssertEqual(conversation.voiceChannel.state, ZMVoiceChannelStateSelfIsJoiningActiveChannel);

    [self simulateMediaFlowEstablishedOnConversation:conversation];
    [self simulateParticipantsChanged:@[self.user2] onConversation:conversation];
    WaitForAllGroupsToBeEmpty(0.5);
    
    //then
    ZMVoiceChannelState state = conversation.voiceChannel.state;
    XCTAssertEqual(state, ZMVoiceChannelStateSelfConnectedToActiveChannel);
    XCTAssertEqual(self.voiceChannelStateDidChangeNotes.count, 3u);

    VoiceChannelStateChangeInfo *lastChange = self.voiceChannelStateDidChangeNotes.lastObject;
    XCTAssertEqual(lastChange.currentState, ZMVoiceChannelStateSelfConnectedToActiveChannel);
    
    [conversation.voiceChannel removeVoiceChannelStateObserverForToken:stateToken];
}

- (void)testThatWhenWeAreConnectedAndTheOtherUserDropsTheCallWeAreInNotConnectedState {
    
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    
    ZMConversation *conversation = self.conversationUnderTest;
    id stateToken = [conversation.voiceChannel addVoiceChannelStateObserver:self];

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
    XCTAssertEqual(conversation.voiceChannel.state, ZMVoiceChannelStateNoActiveUsers);
    XCTAssertEqual(self.voiceChannelStateDidChangeNotes.count, 3u);

    VoiceChannelStateChangeInfo *lastChange = self.voiceChannelStateDidChangeNotes.lastObject;
    XCTAssertEqual(lastChange.currentState, ZMVoiceChannelStateNoActiveUsers);
    
    [conversation.voiceChannel removeVoiceChannelStateObserverForToken:stateToken];
}


- (void)testThatWeCanMakeTwoCallsInARow {
    
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    
    ZMConversation *conversation = self.conversationUnderTest;
    id stateToken = [conversation.voiceChannel addVoiceChannelStateObserver:self];

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
        XCTAssertEqual(conversation.voiceChannel.state, ZMVoiceChannelStateNoActiveUsers);
        XCTAssertEqual(self.voiceChannelStateDidChangeNotes.count, 3u);

        VoiceChannelStateChangeInfo *lastChange = self.voiceChannelStateDidChangeNotes.lastObject;
        XCTAssertEqual(lastChange.currentState, ZMVoiceChannelStateNoActiveUsers);
    }

    [self.mockTransportSession resetReceivedRequests];
    [self.voiceChannelStateDidChangeNotes removeAllObjects];

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
        XCTAssertEqual(conversation.voiceChannel.state, ZMVoiceChannelStateSelfConnectedToActiveChannel);
        XCTAssertEqual(self.voiceChannelStateDidChangeNotes.count, 3u);

        VoiceChannelStateChangeInfo *lastChange = self.voiceChannelStateDidChangeNotes.lastObject;
        XCTAssertEqual(lastChange.currentState, ZMVoiceChannelStateSelfConnectedToActiveChannel);
    }
    
    [conversation.voiceChannel removeVoiceChannelStateObserverForToken:stateToken];
}


- (void)testThatWeCanMakeTwoCallsInARowWithADelayOnTheNetworkOnTheFirstJoin {
    
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    
    ZMConversation *conversation = self.conversationUnderTest;
    id stateToken = [conversation.voiceChannel addVoiceChannelStateObserver:self];

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
        XCTAssertEqual(conversation.voiceChannel.state, ZMVoiceChannelStateSelfConnectedToActiveChannel);
        XCTAssertEqual(self.voiceChannelStateDidChangeNotes.count, 3u);

        VoiceChannelStateChangeInfo *lastChange = self.voiceChannelStateDidChangeNotes.lastObject;
        XCTAssertEqual(lastChange.currentState, ZMVoiceChannelStateSelfConnectedToActiveChannel);
        
        // and when
        [self.mockTransportSession resetReceivedRequests];
        [self.voiceChannelStateDidChangeNotes removeAllObjects];

        [self selfDropCall];
        WaitForAllGroupsToBeEmpty(0.5);
        [self simulateMediaFlowReleasedOnConversation:self.conversationUnderTest];
        [self simulateParticipantsChanged:@[] onConversation:self.conversationUnderTest];
        WaitForAllGroupsToBeEmpty(0.5);
        
        XCTAssertTrue([self lastRequestContainsSelfStateIdle]);
        
        // then
        XCTAssertEqual(conversation.voiceChannel.state, ZMVoiceChannelStateNoActiveUsers);
        XCTAssertEqual(self.voiceChannelStateDidChangeNotes.count, 1u);

        lastChange = self.voiceChannelStateDidChangeNotes.lastObject;
        XCTAssertEqual(lastChange.currentState, ZMVoiceChannelStateNoActiveUsers);
    }
    
    [self.voiceChannelStateDidChangeNotes removeAllObjects];
    
    { // Call 2
        [self otherJoinCall];
        WaitForAllGroupsToBeEmpty(0.5);
        
        // when
        [self.mockTransportSession resetReceivedRequests];
        [self.voiceChannelStateDidChangeNotes removeAllObjects];
        
        [self selfJoinCall];
        WaitForAllGroupsToBeEmpty(0.5);

        XCTAssertEqual(self.voiceChannelStateDidChangeNotes.count, 1u);
        VoiceChannelStateChangeInfo *lastChange = self.voiceChannelStateDidChangeNotes.lastObject;
        XCTAssertEqual(lastChange.previousState, ZMVoiceChannelStateIncomingCall);
        XCTAssertEqual(lastChange.currentState, ZMVoiceChannelStateSelfIsJoiningActiveChannel);
        [self.voiceChannelStateDidChangeNotes removeAllObjects];

        [self simulateMediaFlowEstablishedOnConversation:self.conversationUnderTest];
        [self simulateParticipantsChanged:@[self.user2] onConversation:self.conversationUnderTest];
        WaitForAllGroupsToBeEmpty(0.5);
        
        XCTAssertTrue([self lastRequestContainsSelfStateJoined]);
        
        // then
        XCTAssertEqual(self.voiceChannelStateDidChangeNotes.count, 1u);
        lastChange = self.voiceChannelStateDidChangeNotes.lastObject;
        XCTAssertEqual(lastChange.previousState, ZMVoiceChannelStateSelfIsJoiningActiveChannel);
        XCTAssertEqual(lastChange.currentState, ZMVoiceChannelStateSelfConnectedToActiveChannel);
    }
    [conversation.voiceChannel removeVoiceChannelStateObserverForToken:stateToken];
}

- (void)testThatWeCanMakeTwoCallsInARowWithADelayOnTheSaveOnOtherUserJoin {
    
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    
    ZMConversation *conversation = self.conversationUnderTest;
    id stateToken = [conversation.voiceChannel addVoiceChannelStateObserver:self];

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
        XCTAssertEqual(conversation.voiceChannel.state, ZMVoiceChannelStateSelfConnectedToActiveChannel);
        XCTAssertEqual(self.voiceChannelStateDidChangeNotes.count, 3u);

        VoiceChannelStateChangeInfo *lastChange = self.voiceChannelStateDidChangeNotes.lastObject;
        XCTAssertEqual(lastChange.currentState, ZMVoiceChannelStateSelfConnectedToActiveChannel);
        
        // and when
        [self selfDropCall];
        WaitForAllGroupsToBeEmpty(0.5);
        [self simulateMediaFlowReleasedOnConversation:self.conversationUnderTest];
        WaitForAllGroupsToBeEmpty(0.5);
        
        // then
        XCTAssertEqual(conversation.voiceChannel.state, ZMVoiceChannelStateNoActiveUsers);
        XCTAssertEqual(self.voiceChannelStateDidChangeNotes.count, 4u);

        lastChange = self.voiceChannelStateDidChangeNotes.lastObject;
        XCTAssertEqual(lastChange.currentState, ZMVoiceChannelStateNoActiveUsers);
    }
    
    [self.mockTransportSession resetReceivedRequests];
    [self.voiceChannelStateDidChangeNotes removeAllObjects];
    
    { // Call 2
        
        // when
        [self selfJoinCall];
        WaitForAllGroupsToBeEmpty(0.5);
        
        XCTAssertTrue([self lastRequestContainsSelfStateJoined]);
        
        // then
        XCTAssertEqual(conversation.voiceChannel.state, ZMVoiceChannelStateOutgoingCall);
        VoiceChannelStateChangeInfo *lastChange = self.voiceChannelStateDidChangeNotes.lastObject;
        XCTAssertEqual(lastChange.currentState, ZMVoiceChannelStateOutgoingCall);
        
        // when
        [self otherJoinCall];
        WaitForAllGroupsToBeEmpty(0.5);
        
        [self simulateMediaFlowEstablishedOnConversation:self.conversationUnderTest];
        [self simulateParticipantsChanged:@[self.user2] onConversation:self.conversationUnderTest];
        WaitForAllGroupsToBeEmpty(0.5);
        
        // then
        XCTAssertEqual(conversation.voiceChannel.state, ZMVoiceChannelStateSelfConnectedToActiveChannel);
        XCTAssertEqual(self.voiceChannelStateDidChangeNotes.count, 3u);

        lastChange = self.voiceChannelStateDidChangeNotes.lastObject;
        XCTAssertEqual(lastChange.currentState, ZMVoiceChannelStateSelfConnectedToActiveChannel);
    }
    
    XCTAssertTrue([self lastRequestContainsSelfStateJoined]);
    
    [conversation.voiceChannel removeVoiceChannelStateObserverForToken:stateToken];
}


- (void)testThatWeCanMakeTwoCallsInARowWithADelayOnTheSaveOnSelfUserJoin {
    
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    
    ZMConversation *conversation = self.conversationUnderTest;
    id stateToken = [conversation.voiceChannel addVoiceChannelStateObserver:self];

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
        XCTAssertEqual(conversation.voiceChannel.state, ZMVoiceChannelStateSelfConnectedToActiveChannel);
        XCTAssertEqual(self.voiceChannelStateDidChangeNotes.count, 2u);

        VoiceChannelStateChangeInfo *lastChange = self.voiceChannelStateDidChangeNotes.lastObject;
        XCTAssertEqual(lastChange.currentState, ZMVoiceChannelStateSelfConnectedToActiveChannel);
        [self.voiceChannelStateDidChangeNotes removeAllObjects];
        
        // and when
        [self selfDropCall];
        WaitForAllGroupsToBeEmpty(0.5);
        [self simulateMediaFlowReleasedOnConversation:self.conversationUnderTest];
        [self simulateParticipantsChanged:@[] onConversation:self.conversationUnderTest];
        WaitForAllGroupsToBeEmpty(0.5);
        
        // then
        XCTAssertEqual(conversation.voiceChannel.state, ZMVoiceChannelStateNoActiveUsers);
        XCTAssertEqual(self.voiceChannelStateDidChangeNotes.count, 1u);

        lastChange = self.voiceChannelStateDidChangeNotes.lastObject;
        XCTAssertEqual(lastChange.currentState, ZMVoiceChannelStateNoActiveUsers);
        [self.voiceChannelStateDidChangeNotes removeAllObjects];

    }
    
    [self.mockTransportSession resetReceivedRequests];
    [self.voiceChannelStateDidChangeNotes removeAllObjects];
    
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
        if (self.voiceChannelParticipantStateDidChangeNotes.count == 3) {
            VoiceChannelStateChangeInfo *change1 = self.voiceChannelStateDidChangeNotes.firstObject;
            XCTAssertEqual(change1.previousState, ZMVoiceChannelStateNoActiveUsers);
            VoiceChannelStateChangeInfo *change2 = self.voiceChannelStateDidChangeNotes[1];
            XCTAssertEqual(change2.previousState, ZMVoiceChannelStateIncomingCall);
            VoiceChannelStateChangeInfo *change3 = self.voiceChannelStateDidChangeNotes.lastObject;
            XCTAssertEqual(change3.previousState, ZMVoiceChannelStateSelfIsJoiningActiveChannel);
        } else {
            XCTAssertEqual(self.voiceChannelStateDidChangeNotes.count, 3u);
        }
        
        XCTAssertEqual(conversation.voiceChannel.state, ZMVoiceChannelStateSelfConnectedToActiveChannel);
    }
    
    XCTAssertTrue([self lastRequestContainsSelfStateJoined]);
    [conversation.voiceChannel removeVoiceChannelStateObserverForToken:stateToken];
}



- (void)testThatWeDelaySaveOnTheNetworkResponse {
    
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    WaitForAllGroupsToBeEmpty(0.5);

    ZMConversation *conversation = self.conversationUnderTest;
    id stateToken = [conversation.voiceChannel addVoiceChannelStateObserver:self];

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
        XCTAssertEqual(conversation.voiceChannel.state, ZMVoiceChannelStateSelfConnectedToActiveChannel);
        XCTAssertEqual(self.voiceChannelStateDidChangeNotes.count, 3u);

        VoiceChannelStateChangeInfo *lastChange = self.voiceChannelStateDidChangeNotes.lastObject;
        XCTAssertEqual(lastChange.currentState, ZMVoiceChannelStateSelfConnectedToActiveChannel);
        [self.voiceChannelStateDidChangeNotes removeAllObjects];

        
        // and when
        [self selfDropCall];
        WaitForAllGroupsToBeEmpty(0.5);
        [self simulateMediaFlowReleasedOnConversation:self.conversationUnderTest];
        [self simulateParticipantsChanged:@[] onConversation:self.conversationUnderTest];
        WaitForAllGroupsToBeEmpty(0.5);
        
        // then
        XCTAssertEqual(conversation.voiceChannel.state, ZMVoiceChannelStateNoActiveUsers);
        XCTAssertEqual(self.voiceChannelStateDidChangeNotes.count, 1u);

        lastChange = self.voiceChannelStateDidChangeNotes.lastObject;
        XCTAssertEqual(lastChange.currentState, ZMVoiceChannelStateNoActiveUsers);
        [self.voiceChannelStateDidChangeNotes removeAllObjects];

    }
    
    [self.mockTransportSession resetReceivedRequests];
    [self.voiceChannelStateDidChangeNotes removeAllObjects];
    
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
        if (self.voiceChannelParticipantStateDidChangeNotes.count == 2) {
            VoiceChannelStateChangeInfo *change2 = self.voiceChannelStateDidChangeNotes[1];
            XCTAssertEqual(change2.previousState, ZMVoiceChannelStateIncomingCall);
            VoiceChannelStateChangeInfo *change3 = self.voiceChannelStateDidChangeNotes.lastObject;
            XCTAssertEqual(change3.previousState, ZMVoiceChannelStateSelfIsJoiningActiveChannel);
        } else {
            XCTAssertEqual(self.voiceChannelStateDidChangeNotes.count, 2u);
        }

    }
    [conversation.voiceChannel removeVoiceChannelStateObserverForToken:stateToken];
}

- (void)testThatWeCanMakeTwoCallsInARowWhileObservingTheWindow {
    
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    
    ZMConversation *conversation = self.conversationUnderTest;
    id stateToken = [conversation.voiceChannel addVoiceChannelStateObserver:self];

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
        XCTAssertEqual(conversation.voiceChannel.state, ZMVoiceChannelStateNoActiveUsers);
        XCTAssertEqual(self.voiceChannelStateDidChangeNotes.count, 3u);

        VoiceChannelStateChangeInfo *lastChange = self.voiceChannelStateDidChangeNotes.lastObject;
        XCTAssertEqual(lastChange.currentState, ZMVoiceChannelStateNoActiveUsers);
    }
    
    [self.mockTransportSession resetReceivedRequests];
    [self.voiceChannelStateDidChangeNotes removeAllObjects];
    
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
        XCTAssertEqual(conversation.voiceChannel.state, ZMVoiceChannelStateSelfConnectedToActiveChannel);
        XCTAssertEqual(self.voiceChannelStateDidChangeNotes.count, 3u);

        VoiceChannelStateChangeInfo *lastChange = self.voiceChannelStateDidChangeNotes.lastObject;
        XCTAssertEqual(lastChange.currentState, ZMVoiceChannelStateSelfConnectedToActiveChannel);
    }
    [conversation.voiceChannel removeVoiceChannelStateObserverForToken:stateToken];
}


- (void)testThatItGoesThroughConnectingStateWhenReceivingAnIncomingCallAfterAnOutgoingCall {
    
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    
    ZMConversation *conversation = self.conversationUnderTest;
    id stateToken = [conversation.voiceChannel addVoiceChannelStateObserver:self];
    
    { // Call 1
        // when selfUser calls
        [self selfJoinCall];
        WaitForAllGroupsToBeEmpty(0.5);
        
        [self otherJoinCall];
        WaitForAllGroupsToBeEmpty(0.5);
        
        // then
        // we are in the connecting state
        XCTAssertEqual(conversation.voiceChannel.state, ZMVoiceChannelStateSelfIsJoiningActiveChannel);

        // users acquire flow
        [self simulateMediaFlowEstablishedOnConversation:self.conversationUnderTest];
        [self simulateParticipantsChanged:@[self.user2] onConversation:self.conversationUnderTest];
        WaitForAllGroupsToBeEmpty(0.5);
        
        // then
        // we are in connected state
        XCTAssertEqual(conversation.voiceChannel.state, ZMVoiceChannelStateSelfConnectedToActiveChannel);
        
        [self selfDropCall];
        WaitForAllGroupsToBeEmpty(0.5);
        [self simulateMediaFlowReleasedOnConversation:self.conversationUnderTest];
        [self simulateParticipantsChanged:@[] onConversation:self.conversationUnderTest];
        WaitForAllGroupsToBeEmpty(0.5);
        
        // then
        XCTAssertEqual(conversation.voiceChannel.state, ZMVoiceChannelStateNoActiveUsers);
        XCTAssertEqual(self.voiceChannelStateDidChangeNotes.count, 4u);
    }
    
    [self.voiceChannelStateDidChangeNotes removeAllObjects];
    
    { // Call 2
        // when other user calls
        [self otherJoinCall];
        WaitForAllGroupsToBeEmpty(0.5);
        
        [self selfJoinCall];
        WaitForAllGroupsToBeEmpty(0.5);
        
        // then
        // we should be in connecting state, because the other user is calling
        XCTAssertEqual(conversation.voiceChannel.state, ZMVoiceChannelStateSelfIsJoiningActiveChannel);
        
        // users acquire flow
        [self simulateMediaFlowEstablishedOnConversation:self.conversationUnderTest];
        [self simulateParticipantsChanged:@[self.user2] onConversation:self.conversationUnderTest];
        WaitForAllGroupsToBeEmpty(0.5);
        
        // then
        XCTAssertEqual(conversation.voiceChannel.state, ZMVoiceChannelStateSelfConnectedToActiveChannel);
        XCTAssertEqual(self.voiceChannelStateDidChangeNotes.count, 3u);
        VoiceChannelStateChangeInfo *firstChange = self.voiceChannelStateDidChangeNotes.firstObject;
        XCTAssertEqual(firstChange.previousState, ZMVoiceChannelStateNoActiveUsers);
        
        VoiceChannelStateChangeInfo *second = [self.voiceChannelStateDidChangeNotes objectAtIndex:1];
        XCTAssertEqual(second.previousState, ZMVoiceChannelStateIncomingCall);
        
        VoiceChannelStateChangeInfo *lastChange = self.voiceChannelStateDidChangeNotes.lastObject;
        XCTAssertEqual(lastChange.previousState, ZMVoiceChannelStateSelfIsJoiningActiveChannel);
        XCTAssertEqual(lastChange.currentState, ZMVoiceChannelStateSelfConnectedToActiveChannel);
    }
    [conversation.voiceChannel removeVoiceChannelStateObserverForToken:stateToken];
}


- (void)testThatItTimesOutCallsAndDropsTheCall_OneOnOne_Outgoing_Second_Outgoing
{
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    
    ZMConversation *conversation = self.conversationUnderTest;
    [ZMCallTimer setTestCallTimeout: 0.2];
    id stateToken = [conversation.voiceChannel addVoiceChannelStateObserver:self];
    
    // when selfUser calls
    [self selfJoinCall];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(conversation.voiceChannel.state, ZMVoiceChannelStateOutgoingCall);
    XCTAssertEqual(conversation.voiceChannel.participants.count, 0u);
    XCTAssertEqual(self.voiceChannelStateDidChangeNotes.count, 1u);
    
    [self.voiceChannelStateDidChangeNotes removeAllObjects];

    // when
    [self spinMainQueueWithTimeout:0.5];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(conversation.voiceChannel.participants.count, 0u);
    XCTAssertEqual(self.voiceChannelStateDidChangeNotes.count, 1u);
    
    VoiceChannelStateChangeInfo *lastChange = self.voiceChannelStateDidChangeNotes.lastObject;
    XCTAssertEqual(lastChange.previousState, ZMVoiceChannelStateOutgoingCall);
    XCTAssertEqual(lastChange.currentState, ZMVoiceChannelStateNoActiveUsers);
    
    // and when
    [self selfJoinCall];
    WaitForAllGroupsToBeEmpty(0.5);

    // then
    XCTAssertEqual(conversation.voiceChannel.state, ZMVoiceChannelStateOutgoingCall);
    
    // and when
    [self spinMainQueueWithTimeout:0.5];
    
    // then
    XCTAssertEqual(conversation.voiceChannel.state, ZMVoiceChannelStateNoActiveUsers);
    
    [conversation.voiceChannel removeVoiceChannelStateObserverForToken:stateToken];
}

- (void)testThatItTimesOutCallsAndDropsTheCall_OneOnOne_Outgoing_Second_Incoming
{
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    
    ZMConversation *conversation = self.conversationUnderTest;
    [ZMCallTimer setTestCallTimeout: 0.2];
    id stateToken = [conversation.voiceChannel addVoiceChannelStateObserver:self];
    
    // when selfUser calls
    [self selfJoinCall];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(conversation.voiceChannel.state, ZMVoiceChannelStateOutgoingCall);
    XCTAssertEqual(conversation.voiceChannel.participants.count, 0u);
    XCTAssertEqual(self.voiceChannelStateDidChangeNotes.count, 1u);
    
    [self.voiceChannelStateDidChangeNotes removeAllObjects];
    
    // when
    [self spinMainQueueWithTimeout:0.5];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(conversation.voiceChannel.participants.count, 0u);
    XCTAssertEqual(self.voiceChannelStateDidChangeNotes.count, 1u);
    
    VoiceChannelStateChangeInfo *lastChange = self.voiceChannelStateDidChangeNotes.lastObject;
    XCTAssertEqual(lastChange.previousState, ZMVoiceChannelStateOutgoingCall);
    XCTAssertEqual(lastChange.currentState, ZMVoiceChannelStateNoActiveUsers);
    
    // and when
    [self otherJoinCall];
    WaitForAllGroupsToBeEmpty(0.5);

    // then
    XCTAssertEqual(conversation.voiceChannel.state, ZMVoiceChannelStateIncomingCall);
    
    // and when
    [self spinMainQueueWithTimeout:0.5];
    
    // then
    XCTAssertEqual(conversation.voiceChannel.state, ZMVoiceChannelStateIncomingCallInactive);
    
    [conversation.voiceChannel removeVoiceChannelStateObserverForToken:stateToken];
}


- (void)testThatItTimesOutCallsAndSetsInactive_OneOnOne_Incoming
{
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    
    ZMConversation *conversation = self.conversationUnderTest;
    [ZMCallTimer setTestCallTimeout: 0.2];
    id stateToken = [conversation.voiceChannel addVoiceChannelStateObserver:self];
    
    // when other user calls
    [self otherJoinCall];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(conversation.voiceChannel.state, ZMVoiceChannelStateIncomingCall);
    XCTAssertEqual(conversation.voiceChannel.participants.count, 1u);
    
    // when
    [self spinMainQueueWithTimeout:0.8];
    WaitForAllGroupsToBeEmpty(0.5);

    // then
    XCTAssertEqual(conversation.voiceChannel.state, ZMVoiceChannelStateIncomingCallInactive);
    XCTAssertEqual(conversation.voiceChannel.participants.count, 1u);
    
    // and when we reinitiate the call
    [self selfJoinCall];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(conversation.voiceChannel.state, ZMVoiceChannelStateSelfIsJoiningActiveChannel);
    
    [conversation.voiceChannel removeVoiceChannelStateObserverForToken:stateToken];
}


- (void)testThatItTimesOutOutgoingCallsAndSilencesTheCall_Group
{
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    self.useGroupConversation = YES;
    
    ZMConversation *conversation = self.conversationUnderTest;
    [ZMCallTimer setTestCallTimeout: 0.2];
    id stateToken = [conversation.voiceChannel addVoiceChannelStateObserver:self];
    
    // when selfUser calls
    [self selfJoinCall];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(conversation.voiceChannel.state, ZMVoiceChannelStateOutgoingCall);
    XCTAssertEqual(conversation.voiceChannel.participants.count, 0u);

    // when
    [self spinMainQueueWithTimeout:0.5];
    
    // then
    XCTAssertEqual(conversation.voiceChannel.state, ZMVoiceChannelStateOutgoingCallInactive);
    XCTAssertEqual(conversation.voiceChannel.participants.count, 0u);

    // and when we reinitiate the call
    [self selfDropCall];
    WaitForAllGroupsToBeEmpty(0.5);
    
    [self selfJoinCall];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(conversation.voiceChannel.state, ZMVoiceChannelStateOutgoingCall);
    
    [conversation.voiceChannel removeVoiceChannelStateObserverForToken:stateToken];
}


- (void)testThatItTimesOutOutgoingCallsAndSilencesTheCall_Group_Second_Incoming
{
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    self.useGroupConversation = YES;
    
    ZMConversation *conversation = self.conversationUnderTest;
    [ZMCallTimer setTestCallTimeout: 0.2];
    id stateToken = [conversation.voiceChannel addVoiceChannelStateObserver:self];
    
    // when selfUser calls
    [self selfJoinCall];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(conversation.voiceChannel.state, ZMVoiceChannelStateOutgoingCall);
    XCTAssertEqual(conversation.voiceChannel.participants.count, 0u);
    
    // when
    [self spinMainQueueWithTimeout:0.5];
    
    // then
    XCTAssertEqual(conversation.voiceChannel.state, ZMVoiceChannelStateOutgoingCallInactive);
    XCTAssertEqual(conversation.voiceChannel.participants.count, 0u);
    
    // and when we reinitiate the call
    [self selfDropCall];
    WaitForAllGroupsToBeEmpty(0.5);
    
    [self otherJoinCall];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(conversation.voiceChannel.state, ZMVoiceChannelStateIncomingCall);
    
    [conversation.voiceChannel removeVoiceChannelStateObserverForToken:stateToken];
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
            ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:nil HTTPstatus:404 transportSessionError:nil];
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
            ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:nil HTTPstatus:404 transportSessionError:nil];
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
    
    id<ZMVoiceChannelStateObserver> callObserver = [OCMockObject mockForProtocol:@protocol(ZMVoiceChannelStateObserver)];
    id<ZMConversationListObserver> listObserver = [OCMockObject mockForProtocol:@protocol(ZMConversationListObserver)];
    
    // Make sure we observe the conversation as soon as we figure out that a new conversation is available
    __block ZMConversation *conversationToObserve;
    __block id<ZMVoiceChannelStateObserverOpaqueToken> voiceChannelStateToken;
    __block ZMVoiceChannelState voiceChannelState = ZMVoiceChannelStateInvalid;
    
    [[(id) listObserver stub] conversationListDidChange:[OCMArg checkWithBlock:^BOOL(ConversationListChangeInfo* changeInfo) {
        ZMConversationList *innerList = changeInfo.conversationList;
        if(changeInfo.insertedIndexes.count == 1u) {
            conversationToObserve = innerList[changeInfo.insertedIndexes.firstIndex];
            voiceChannelStateToken = [conversationToObserve.voiceChannel addVoiceChannelStateObserver:callObserver];
            voiceChannelState = conversationToObserve.voiceChannel.state;
        }
        return YES;
    }]];
    [[(id) listObserver stub] conversationInsideList:OCMOCK_ANY didChange:OCMOCK_ANY];
    
    ZMConversationList* list = [ZMConversationList conversationsInUserSession:self.userSession];
    id<ZMConversationListObserverOpaqueToken> listToken = [list addConversationListObserver:listObserver];
    
    
    // collect voice channel participant changes
    [[(id) callObserver stub] voiceChannelStateDidChange:[OCMArg checkWithBlock:^BOOL(VoiceChannelStateChangeInfo* changeInfo) {
        voiceChannelState = changeInfo.voiceChannel.state;
        return YES;
    }]];
    [self.mockTransportSession resetReceivedRequests];
    
    // when
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        NOT_USED(session);
        [mockConversation addUsersByUser:self.user1 addedUsers:@[self.selfUser]];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    NSPredicate *predicate = [NSPredicate predicateWithFormat:@"path == %@ && method == %d", [NSString stringWithFormat:@"/conversations/%@/call/state", conversationToObserve.remoteIdentifier.transportString], ZMMethodGET];
    NSArray *callStateRequest = [self.mockTransportSession.receivedRequests filteredArrayUsingPredicate:predicate];
    XCTAssertEqual(callStateRequest.count, 0u);
   
    // after
    [list removeConversationListObserverForToken:listToken];
    [conversationToObserve.voiceChannel removeVoiceChannelStateObserverForToken:voiceChannelStateToken];
    [self tearDownVoiceChannelForConversation:conversationToObserve];
}


- (void)testThatWeCanJoinGroupCallAfterWeLeaveItAndItIsStillActive
{
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    self.useGroupConversation = YES;
    
    
    ZMConversation *conversation = self.conversationUnderTest;
    id stateToken = [conversation.voiceChannel addVoiceChannelStateObserver:self];
    
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
        XCTAssertEqual(conversation.voiceChannel.state, ZMVoiceChannelStateSelfConnectedToActiveChannel);
        XCTAssertEqual(self.voiceChannelStateDidChangeNotes.count, 3u);

        VoiceChannelStateChangeInfo *lastChange = self.voiceChannelStateDidChangeNotes.lastObject;
        XCTAssertEqual(lastChange.currentState, ZMVoiceChannelStateSelfConnectedToActiveChannel);
        
        // and when
        [self selfDropCall];
        WaitForAllGroupsToBeEmpty(0.5);
        [self simulateMediaFlowReleasedOnConversation:self.conversationUnderTest];
        [self simulateParticipantsChanged:@[] onConversation:self.conversationUnderTest];
        WaitForAllGroupsToBeEmpty(0.5);
   
        XCTAssertTrue([self lastRequestContainsSelfStateIdleWithIsIgnored:NO]);
        
        XCTAssertEqual(self.voiceChannelStateDidChangeNotes.count, 4u);

        // then
        lastChange = self.voiceChannelStateDidChangeNotes.lastObject;
        XCTAssertEqual(lastChange.currentState, ZMVoiceChannelStateIncomingCallInactive);
    }
    
    [self.voiceChannelStateDidChangeNotes removeAllObjects];
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
        XCTAssertEqual(self.voiceChannelStateDidChangeNotes.count, 2u);
        VoiceChannelStateChangeInfo *lastChange = self.voiceChannelStateDidChangeNotes.lastObject;
        lastChange = self.voiceChannelStateDidChangeNotes.lastObject;
        XCTAssertEqual(lastChange.currentState, ZMVoiceChannelStateSelfConnectedToActiveChannel);
    }
    [conversation.voiceChannel removeVoiceChannelStateObserverForToken:stateToken];
}

- (void)testThatGroupCallIsDroppedWhenTheLastOtherParticipantLeaves
{
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    self.useGroupConversation = YES;
    
    
    ZMConversation *conversation = self.conversationUnderTest;
    id stateToken = [conversation.voiceChannel addVoiceChannelStateObserver:self];
    
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
        XCTAssertEqual(conversation.voiceChannel.state, ZMVoiceChannelStateSelfConnectedToActiveChannel);
        XCTAssertEqual(self.voiceChannelStateDidChangeNotes.count, 3u);

        VoiceChannelStateChangeInfo *lastChange = self.voiceChannelStateDidChangeNotes.lastObject;
        XCTAssertEqual(lastChange.currentState, ZMVoiceChannelStateSelfConnectedToActiveChannel);
        
        // and when
        
        // everyone leaves
        [self usersLeaveGroupCall:joinedUsers];
        WaitForAllGroupsToBeEmpty(0.5);
        
        // then
        XCTAssertEqual(self.voiceChannelStateDidChangeNotes.count, 4u);

        lastChange = self.voiceChannelStateDidChangeNotes.lastObject;
        XCTAssertEqual(lastChange.currentState, ZMVoiceChannelStateNoActiveUsers);
    }
    [conversation.voiceChannel removeVoiceChannelStateObserverForToken:stateToken];
}

- (void)testThatGroupCallDoesNotDropWhenThereAreTwoParticipantLeft
{
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    self.useGroupConversation = YES;
    
    
    ZMConversation *conversation = self.conversationUnderTest;
    id stateToken = [conversation.voiceChannel addVoiceChannelStateObserver:self];
    
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
        XCTAssertEqual(conversation.voiceChannel.state, ZMVoiceChannelStateSelfConnectedToActiveChannel);
        XCTAssertEqual(self.voiceChannelStateDidChangeNotes.count, 3u);

        VoiceChannelStateChangeInfo *lastChange = self.voiceChannelStateDidChangeNotes.lastObject;
        XCTAssertNotNil(lastChange);
        XCTAssertEqual(lastChange.currentState, ZMVoiceChannelStateSelfConnectedToActiveChannel);
        [self.voiceChannelParticipantStateDidChangeNotes removeAllObjects];
        
        // and when
        
        // everyone but one leaves
        [joinedUsers removeObject:joinedUsers.firstObject];
        
        [self usersLeaveGroupCall:joinedUsers];
        WaitForAllGroupsToBeEmpty(0.5);
        
        // then
        //voice channel state should not change, no notification should be posted
        XCTAssertEqual(self.voiceChannelStateDidChangeNotes.count, 3u);

        lastChange = self.voiceChannelStateDidChangeNotes.lastObject;
        XCTAssertEqual(lastChange.currentState, ZMVoiceChannelStateSelfConnectedToActiveChannel);
    }
    [conversation.voiceChannel removeVoiceChannelStateObserverForToken:stateToken];
}

- (void)testThatItSendsCallParticipantsNotification
{
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    self.useGroupConversation = YES;
    
    ZMConversation *conversation = self.conversationUnderTest;
    id participantsToken = [conversation.voiceChannel addCallParticipantsObserver:self];
    
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
        
        XCTAssertEqual(self.voiceChannelParticipantStateDidChangeNotes.count, 0u);
        [self.voiceChannelParticipantStateDidChangeNotes removeAllObjects];
    }
    
    /////
    // (2) oter user joins the call
    {
        [self usersJoinGroupCall:joinedUsers];
        WaitForAllGroupsToBeEmpty(0.5);
        
        // then
        // we should see an insert
        NSMutableIndexSet *expectedInsert = [NSMutableIndexSet indexSetWithIndexesInRange:NSMakeRange(0, joinedUsers.count)];
        XCTAssertEqual(self.voiceChannelParticipantStateDidChangeNotes.count, 1u);
        VoiceChannelParticipantsChangeInfo *lastChange = self.voiceChannelParticipantStateDidChangeNotes.lastObject;
        XCTAssertEqualObjects(lastChange.updatedIndexes, [NSIndexSet indexSet]);
        XCTAssertEqualObjects(lastChange.insertedIndexes, [expectedInsert copy]);
        XCTAssertEqualObjects(lastChange.deletedIndexes, [NSIndexSet indexSet]);
        [self.voiceChannelParticipantStateDidChangeNotes removeAllObjects];
    }
    /////
    // (3) when a flow is established
    {
        [self simulateMediaFlowEstablishedOnConversation:self.conversationUnderTest];
        [self simulateParticipantsChanged:joinedUsers.array onConversation:conversation];
        WaitForAllGroupsToBeEmpty(0.5);
        
        // then
        // we should see an update
        XCTAssertEqual(self.voiceChannelParticipantStateDidChangeNotes.count, 1u);
        VoiceChannelParticipantsChangeInfo *lastChange = self.voiceChannelParticipantStateDidChangeNotes.lastObject;
        XCTAssertEqualObjects(lastChange.updatedIndexes, [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, joinedUsers.count)]);
        XCTAssertEqualObjects(lastChange.insertedIndexes, [NSIndexSet indexSet]);
        XCTAssertEqualObjects(lastChange.deletedIndexes, [NSIndexSet indexSet]);

        [self.voiceChannelParticipantStateDidChangeNotes removeAllObjects];
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
        XCTAssertEqual(self.voiceChannelParticipantStateDidChangeNotes.count, 1u);
        VoiceChannelParticipantsChangeInfo *lastChange = self.voiceChannelParticipantStateDidChangeNotes.lastObject;
        XCTAssertEqualObjects(lastChange.deletedIndexes, [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(1, length)]);
        XCTAssertEqualObjects(lastChange.insertedIndexes, [NSIndexSet indexSet]);
        XCTAssertEqualObjects(lastChange.updatedIndexes, [NSIndexSet indexSet]);
        [self.voiceChannelParticipantStateDidChangeNotes removeAllObjects];
    }
    
    /////
    // (5) when we receive an update from AVS
    {
        [self simulateParticipantsChanged:@[leftOtherUser] onConversation:conversation];
        WaitForAllGroupsToBeEmpty(0.5);

        // then the order should not have changed
        XCTAssertEqual(self.voiceChannelParticipantStateDidChangeNotes.count, 0u);
    }
    
    [conversation.voiceChannel removeCallParticipantsObserverForToken:participantsToken];
}

- (void)testThatItSendsAJoinCallback
{
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);  

    self.useGroupConversation = YES;
    
    ZMConversation *conversation = self.conversationUnderTest;
    
    // when remotes join
    NSMutableOrderedSet *joinedUsers = [[[self mockConversationUnderTest] activeUsers] mutableCopy];
    [joinedUsers removeObject:self.selfUser];
    [self usersJoinGroupCall:joinedUsers];
    [self simulateParticipantsChanged:joinedUsers.array onConversation:self.conversationUnderTest];
    WaitForAllGroupsToBeEmpty(0.5);

    id<ZMVoiceChannelStateObserver> mockObserver = [OCMockObject mockForProtocol:@protocol(ZMVoiceChannelStateObserver)];
    
    [[(id)mockObserver reject] voiceChannelJoinFailedWithError:OCMOCK_ANY];
    
    [conversation.voiceChannel addVoiceChannelStateObserver:mockObserver];
    
    // then
    XCTAssertEqual(conversation.voiceChannel.state, ZMVoiceChannelStateIncomingCall);
    
    // when
    [self.userSession performChanges:^{
        [conversation.voiceChannel join];
    }];
    
    WaitForAllGroupsToBeEmpty(0.5f);
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
            user.accentID = i % 7;
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
    
    XCTestExpectation *joinCallbackExpectation = [self expectationWithDescription:@"JoinCallback"];
    id<ZMVoiceChannelStateObserver> mockObserver = [OCMockObject mockForProtocol:@protocol(ZMVoiceChannelStateObserver)];

    WaitForAllGroupsToBeEmpty(0.5);
   
    // then
    XCTAssertEqual(bigGroupConversation.voiceChannel.state, ZMVoiceChannelStateNoActiveUsers);
    
    [[(id)mockObserver stub] voiceChannelJoinFailedWithError:[OCMArg checkWithBlock:^BOOL(NSError *error) {
        
        // then
        XCTAssertNotNil(error);
        XCTAssertTrue([[error domain] isEqualToString:ZMConversationErrorDomain]);
        XCTAssertTrue(error.conversationErrorCode == ZMConversationTooManyMembersInConversation);
        XCTAssertTrue([error.userInfo[ZMConversationErrorMaxMembersForGroupCallKey] unsignedIntegerValue] == self.mockTransportSession.maxMembersForGroupCall);
        [joinCallbackExpectation fulfill];
        return YES;
    }]];
    
    [[(id)mockObserver stub] voiceChannelStateDidChange:OCMOCK_ANY];
    
    [bigGroupConversation.voiceChannel addVoiceChannelStateObserver:mockObserver];

    // when
    [self.userSession performChanges:^{
        [bigGroupConversation.voiceChannel join];
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
            user.accentID = i % 7;
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
    
    XCTestExpectation *joinCallbackExpectation = [self expectationWithDescription:@"JoinCallback"];
    id<ZMVoiceChannelStateObserver> mockObserver = [OCMockObject mockForProtocol:@protocol(ZMVoiceChannelStateObserver)];

    WaitForAllGroupsToBeEmpty(0.5);
    
    // when all remotes join
    NSMutableOrderedSet *joinedUsers = [[mockBigGroupConversation activeUsers] mutableCopy];
    [joinedUsers removeObject:self.selfUser];
    WaitForAllGroupsToBeEmpty(0.5);
    [self simulateParticipantsChanged:joinedUsers.array onConversation:bigGroupConversation];
    
    WaitForAllGroupsToBeEmpty(0.5);
        
    // then
    [[(id)mockObserver stub] voiceChannelJoinFailedWithError:[OCMArg checkWithBlock:^BOOL(NSError *error) {
        XCTAssertNotNil(error);
        XCTAssertTrue([[error domain] isEqualToString:ZMConversationErrorDomain]);
        XCTAssertTrue(error.conversationErrorCode == ZMConversationTooManyParticipantsInTheCall);
        XCTAssertTrue([error.userInfo[ZMConversationErrorMaxCallParticipantsKey] unsignedIntegerValue] == self.mockTransportSession.maxCallParticipants);
        [joinCallbackExpectation fulfill]; 
        return YES;
    }]];
    
    [[(id)mockObserver stub] voiceChannelStateDidChange:OCMOCK_ANY];
    
    [bigGroupConversation.voiceChannel addVoiceChannelStateObserver:mockObserver];

    // when
    [self.userSession performChanges:^{
        [bigGroupConversation.voiceChannel join];
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
    id stateToken = [conversation.voiceChannel addVoiceChannelStateObserver:self];
    
    // (1) selfUser initiated a call
    {
        [self selfJoinCall];
        WaitForAllGroupsToBeEmpty(0.5);
        
        XCTAssertTrue([self lastRequestContainsSelfStateJoined]);
        
        XCTAssertEqual(self.voiceChannelStateDidChangeNotes.count, 1u);
        VoiceChannelStateChangeInfo *lastChange = self.voiceChannelStateDidChangeNotes.lastObject;
        XCTAssertEqual(lastChange.previousState, ZMVoiceChannelStateNoActiveUsers);
        XCTAssertEqual(lastChange.currentState, ZMVoiceChannelStateOutgoingCall);
        [self.voiceChannelStateDidChangeNotes removeAllObjects];
    }
    
    // (2) other user joins
    {
        [self otherJoinCall];
        [self simulateMediaFlowEstablishedOnConversation:conversation];
        [self simulateParticipantsChanged:@[self.user1] onConversation:conversation];
        WaitForAllGroupsToBeEmpty(0.5);
        
        // then
        XCTAssertEqual(self.voiceChannelStateDidChangeNotes.count, 1u);
        VoiceChannelStateChangeInfo *lastChange = self.voiceChannelStateDidChangeNotes.lastObject;
        XCTAssertEqual(lastChange.previousState, ZMVoiceChannelStateOutgoingCall);
        XCTAssertEqual(lastChange.currentState, ZMVoiceChannelStateSelfConnectedToActiveChannel);
        [self.voiceChannelStateDidChangeNotes removeAllObjects];
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
        
        XCTAssertEqual(self.voiceChannelStateDidChangeNotes.count, 1u);
        VoiceChannelStateChangeInfo *lastChange = self.voiceChannelStateDidChangeNotes.lastObject;
        XCTAssertEqual(lastChange.previousState, ZMVoiceChannelStateSelfConnectedToActiveChannel);
        XCTAssertEqual(lastChange.currentState, ZMVoiceChannelStateNoActiveUsers);
    }
    
    [conversation.voiceChannel removeVoiceChannelStateObserverForToken:stateToken];
}

- (void)testThatItDropsTheCallWhenWeAreRemovedFromConversationWithAnActiveCall
{
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    self.useGroupConversation = YES;
    
    ZMConversation *conversation = self.conversationUnderTest;
    id stateToken = [conversation.voiceChannel addVoiceChannelStateObserver:self];
    
    // (1) selfUser initiated a call
    {
        [self selfJoinCall];
        WaitForAllGroupsToBeEmpty(0.5);
        
        XCTAssertTrue([self lastRequestContainsSelfStateJoined]);
        
        XCTAssertEqual(self.voiceChannelStateDidChangeNotes.count, 1u);
        VoiceChannelStateChangeInfo *lastChange = self.voiceChannelStateDidChangeNotes.lastObject;
        XCTAssertEqual(lastChange.previousState, ZMVoiceChannelStateNoActiveUsers);
        XCTAssertEqual(lastChange.currentState, ZMVoiceChannelStateOutgoingCall);
        [self.voiceChannelStateDidChangeNotes removeAllObjects];
    }
    
    // (2) other user joins
    {
        [self otherJoinCall];
        [self simulateMediaFlowEstablishedOnConversation:conversation];
        [self simulateParticipantsChanged:@[self.user1] onConversation:conversation];
        WaitForAllGroupsToBeEmpty(0.5);
        
        // then
        XCTAssertEqual(self.voiceChannelStateDidChangeNotes.count, 1u);
        VoiceChannelStateChangeInfo *lastChange = self.voiceChannelStateDidChangeNotes.lastObject;
        XCTAssertEqual(lastChange.previousState, ZMVoiceChannelStateOutgoingCall);
        XCTAssertEqual(lastChange.currentState, ZMVoiceChannelStateSelfConnectedToActiveChannel);
        [self.voiceChannelStateDidChangeNotes removeAllObjects];
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
        
        //NOTE: we have an intermediate update here (Connected->TransferReady->NoActiveUsers), MEC-1236 can solve this
        XCTAssertGreaterThanOrEqual(self.voiceChannelStateDidChangeNotes.count, 1u);
        VoiceChannelStateChangeInfo *lastChange = self.voiceChannelStateDidChangeNotes.lastObject;
        XCTAssertEqual(lastChange.currentState, ZMVoiceChannelStateNoActiveUsers);
    }
    
    [conversation.voiceChannel removeVoiceChannelStateObserverForToken:stateToken];
}

- (void)testThatItReturnsIncomingCallInactiveWhenBeingReaddedToAConversationWithALeftActiveCall_SelfUserLeft
{
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    self.useGroupConversation = YES;
    
    ZMConversation *conversation = self.conversationUnderTest;
    id stateToken = [conversation.voiceChannel addVoiceChannelStateObserver:self];
    
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
        XCTAssertEqual(conversation.voiceChannel.state, ZMVoiceChannelStateIncomingCallInactive);
        
        // (4) selfUser leaves conversation
        [self selfLeavesConversation];
        WaitForAllGroupsToBeEmpty(0.5);
        XCTAssertTrue([self.uiMOC saveOrRollback]);
        
        XCTAssertEqual(conversation.voiceChannel.state, ZMVoiceChannelStateNoActiveUsers);
        [self.voiceChannelStateDidChangeNotes removeAllObjects];
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
        
        XCTAssertEqual(self.voiceChannelStateDidChangeNotes.count, 1u);
        VoiceChannelStateChangeInfo *lastChange = self.voiceChannelStateDidChangeNotes.lastObject;
        XCTAssertEqual(lastChange.previousState, ZMVoiceChannelStateNoActiveUsers);
        XCTAssertEqual(lastChange.currentState, ZMVoiceChannelStateIncomingCallInactive);
    }
    
    [conversation.voiceChannel removeVoiceChannelStateObserverForToken:stateToken];
}

- (void)testThatItReturnsIncomingCallInactiveWhenBeingReaddedToAConversationWithALeftActiveCall_SelfUserRemovedRemotely
{
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    self.useGroupConversation = YES;
    
    ZMConversation *conversation = self.conversationUnderTest;
    id stateToken = [conversation.voiceChannel addVoiceChannelStateObserver:self];
    
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
        XCTAssertEqual(conversation.voiceChannel.state, ZMVoiceChannelStateIncomingCallInactive);
        
        // (4) selfUser is removed from conversation
        [self.mockTransportSession performRemoteChanges:^(ZM_UNUSED id session) {
            [self.mockConversationUnderTest removeUsersByUser:self.user2 removedUser:self.selfUser];
        }];
        WaitForAllGroupsToBeEmpty(0.5);
        
        XCTAssertEqual(conversation.voiceChannel.state, ZMVoiceChannelStateNoActiveUsers);
        [self.voiceChannelStateDidChangeNotes removeAllObjects];
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
        
        XCTAssertEqual(self.voiceChannelStateDidChangeNotes.count, 1u);
        VoiceChannelStateChangeInfo *firstChange = self.voiceChannelStateDidChangeNotes.firstObject;
        XCTAssertEqual(firstChange.previousState, ZMVoiceChannelStateNoActiveUsers);
        XCTAssertEqual(firstChange.currentState, ZMVoiceChannelStateIncomingCallInactive);
    }
    
    [conversation.voiceChannel removeVoiceChannelStateObserverForToken:stateToken];
}

- (void)testThatItReturnsIncomingCallInactiveWhenBeingReaddedToAConversationWithAnActiveCall_SelfUserLeft
{
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    self.useGroupConversation = YES;
    
    ZMConversation *conversation = self.conversationUnderTest;
    id stateToken = [conversation.voiceChannel addVoiceChannelStateObserver:self];
    
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
        
        XCTAssertEqual(conversation.voiceChannel.state, ZMVoiceChannelStateNoActiveUsers);
        [self.voiceChannelStateDidChangeNotes removeAllObjects];
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
        
        XCTAssertEqual(self.voiceChannelStateDidChangeNotes.count, 1u);
        VoiceChannelStateChangeInfo *lastChange = self.voiceChannelStateDidChangeNotes.lastObject;
        XCTAssertEqual(lastChange.previousState, ZMVoiceChannelStateNoActiveUsers);
        XCTAssertEqual(lastChange.currentState, ZMVoiceChannelStateIncomingCallInactive);
    }
    
    [conversation.voiceChannel removeVoiceChannelStateObserverForToken:stateToken];
}


- (void)testThatItReturnsIncomingCallInactiveWhenBeingReaddedToAConversationWithAnActiveCall_SelfUserWasRemovedRemotely
{
    // given
    self.registeredOnThisDevice = YES;
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    self.useGroupConversation = YES;
    
    ZMConversation *conversation = self.conversationUnderTest;
    id stateToken = [conversation.voiceChannel addVoiceChannelStateObserver:self];
    
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
        
        XCTAssertEqual(conversation.voiceChannel.state, ZMVoiceChannelStateNoActiveUsers);
        [self.voiceChannelStateDidChangeNotes removeAllObjects];
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
        
        XCTAssertEqual(self.voiceChannelStateDidChangeNotes.count, 1u);

        VoiceChannelStateChangeInfo *lastChange = self.voiceChannelStateDidChangeNotes.lastObject;
        XCTAssertEqual(lastChange.previousState, ZMVoiceChannelStateNoActiveUsers);
        XCTAssertEqual(lastChange.currentState, ZMVoiceChannelStateIncomingCallInactive);
        XCTAssertFalse(conversation.callDeviceIsActive);
        XCTAssertEqual(conversation.callParticipants.count, 2u);
        XCTAssertTrue(conversation.isIgnoringCall);
    }
    
    [conversation.voiceChannel removeVoiceChannelStateObserverForToken:stateToken];
}




- (void)testThatWeIgnoreCallEventsIfWeAreNotActiveMemberOfConversation
{
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    self.useGroupConversation = YES;
    
    ZMConversation *conversation = self.conversationUnderTest;
    id stateToken = [conversation.voiceChannel addVoiceChannelStateObserver:self];
    
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
    XCTAssertEqual(conversation.voiceChannel.state, ZMVoiceChannelStateIncomingCallInactive);
    
    // (4) selfUser leaves conversation
    [self selfLeavesConversation];
    WaitForAllGroupsToBeEmpty(0.5);
    XCTAssertEqual(conversation.voiceChannel.state, ZMVoiceChannelStateNoActiveUsers);
    [self.voiceChannelStateDidChangeNotes removeAllObjects];
    
    // (5) some user added to call
    [self usersJoinGroupCall:[NSOrderedSet orderedSetWithObject:self.user1]];
    WaitForAllGroupsToBeEmpty(0.5);
    
    //then
    // ignore all call state events while we are not active member of conversation
    XCTAssertEqual(self.voiceChannelStateDidChangeNotes.count, 0u);
    XCTAssertEqual(conversation.voiceChannel.state, ZMVoiceChannelStateNoActiveUsers);
    
    [conversation.voiceChannel removeVoiceChannelStateObserverForToken:stateToken];
}

- (void)testThatItReturnsNoActiveUsersAfterIgnoredCallEnds
{
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    self.useGroupConversation = YES;
    
    ZMConversation *conversation = self.conversationUnderTest;
    id stateToken = [conversation.voiceChannel addVoiceChannelStateObserver:self];
    
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
        XCTAssertEqual(conversation.voiceChannel.state, ZMVoiceChannelStateIncomingCallInactive);
        [self.voiceChannelStateDidChangeNotes removeAllObjects];
    }
    
    // (4) other users leave
    // the call state should be NoActiveUsers (not IncomingCallInactive)
    {
        // when
        [self usersLeaveGroupCall:joinedUsers];
        WaitForAllGroupsToBeEmpty(0.5);
        
        // then
        XCTAssertEqual(conversation.voiceChannel.state, ZMVoiceChannelStateNoActiveUsers);
        XCTAssertEqual(self.voiceChannelStateDidChangeNotes.count, 1u);
        VoiceChannelStateChangeInfo *lastChange = self.voiceChannelStateDidChangeNotes.lastObject;
        XCTAssertEqual(lastChange.previousState, ZMVoiceChannelStateIncomingCallInactive);
        XCTAssertEqual(lastChange.currentState, ZMVoiceChannelStateNoActiveUsers);
        [self.voiceChannelStateDidChangeNotes removeAllObjects];
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
        XCTAssertEqual(conversation.voiceChannel.state, ZMVoiceChannelStateIncomingCall);
        XCTAssertEqual(self.voiceChannelStateDidChangeNotes.count, 1u);
        VoiceChannelStateChangeInfo *lastChange = self.voiceChannelStateDidChangeNotes.lastObject;
        XCTAssertEqual(lastChange.previousState, ZMVoiceChannelStateNoActiveUsers);
        XCTAssertEqual(lastChange.currentState, ZMVoiceChannelStateIncomingCall);
    }
    
    [conversation.voiceChannel removeVoiceChannelStateObserverForToken:stateToken];
    
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

    id stateToken = [conversation.voiceChannel addVoiceChannelStateObserver:self];
    
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
        [conversation.voiceChannel join];
    }];
    WaitForAllGroupsToBeEmpty(0.5);

    // then
    XCTAssertEqual(self.mockTransportSession.receivedRequests.count, 1u);
    ZMTransportRequest *firstRequest = self.mockTransportSession.receivedRequests.firstObject;
    XCTAssertEqualObjects(firstRequest, requestToJoin);
    XCTAssertNotEqualObjects(firstRequest, requestToLeave);
    XCTAssertEqual(conversation.voiceChannel.state, ZMVoiceChannelStateIncomingCall);
    
    [self.mockTransportSession resetReceivedRequests];
    
    // when: it tries to join again
    [self.userSession performChanges:^{
        [conversation.voiceChannel join];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(self.mockTransportSession.receivedRequests.count, 1u);
    
    ZMTransportRequest *secondRequest = self.mockTransportSession.receivedRequests.firstObject;
    XCTAssertEqualObjects(secondRequest, requestToJoin);
    XCTAssertNotEqualObjects(secondRequest, requestToLeave);
    XCTAssertEqual(conversation.voiceChannel.state, ZMVoiceChannelStateIncomingCall);
    
    // after
    [conversation.voiceChannel removeVoiceChannelStateObserverForToken:stateToken];

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
    XCTAssertEqual(self.conversationUnderTest.voiceChannelState, ZMVoiceChannelStateIncomingCallInactive);

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
        [[[call expect] andReturn:CTCallStateDialing] callState];
        
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
        [[[call stub] andReturn:CTCallStateIncoming] callState];
        
        self.gsmCallHandler.callEventHandler(call);
        WaitForAllGroupsToBeEmpty(0.5);
        
        // then
        XCTAssertTrue([self lastRequestContainsSelfStateJoinedWithCauseSuspended:YES]);
    }
    [self.mockTransportSession resetReceivedRequests];

    // when the GSM call ends
    {
        id call = [OCMockObject niceMockForClass:[CTCall class]];
        [[[call stub] andReturn:CTCallStateDisconnected] callState];
        
        self.gsmCallHandler.callEventHandler(call);
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
        [self.conversationUnderTest.voiceChannel ignoreIncomingCall];
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
    XCTAssertEqual(conversation.voiceChannel.state, ZMVoiceChannelStateSelfIsJoiningActiveChannel);
    
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







