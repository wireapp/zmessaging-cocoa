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

@import avs;

#import "CallingTests.h"

@implementation CallingTests (VideoCalling)

- (void)selfJoinVideoCall
{
    [self.userSession enqueueChanges:^{
        NOT_USED([self.conversationUnderTest.voiceChannelRouter.v2 joinWithVideo:YES]);
    }];
}

- (void)selfDropVideoCall
{
    [self.userSession enqueueChanges:^{
        [self.conversationUnderTest.voiceChannelRouter.v2 leave];
    }];
}

- (void)otherJoinVideoCall
{
    [self.mockTransportSession performRemoteChanges:^(ZM_UNUSED id session) {
        [self.mockConversationUnderTest addUserToVideoCall:self.user2];
    }];
}

// NOTE simulate v2 video calling
- (void)simulateSelfUserActivatesVideo:(BOOL)activates
{
    [self.mockFlowManager simulateCanSendVideoInConversation:self.mockConversationUnderTest];
    [self.mockFlowManager simulateMediaIsEstablishedInConversation:self.mockConversationUnderTest];
    [self.userSession performChanges:^{
        NSError *error;
        [self.conversationUnderTest.voiceChannelRouter.v2 setVideoSendActive:activates error:&error];
        if (error != nil) {
            XCTFail(@"%@", error.description);
        }
    }];
}

- (void)simulateMediaFlowEstablished
{
    [self.mockFlowManager simulateCanSendVideoInConversation:self.mockConversationUnderTest];
    [self.mockFlowManager.delegate didEstablishMediaInConversation:self.mockConversationUnderTest.identifier];
}

- (BOOL)lastRequestIsVideoActive:(BOOL)isVideoActive
{
    ZMTransportRequest *request = self.mockTransportSession.receivedRequests.firstObject;
    if (request == nil) {
        XCTFail(@"did not create a request");
        return NO;
    }
    NSString *expectedPath = [NSString stringWithFormat:@"/conversations/%@/call/state", self.selfToUser2Conversation.identifier];
    XCTAssertEqualObjects(request.path, expectedPath);
    return ([request.payload[@"self"][@"videod"] boolValue] == isVideoActive);
}

- (BOOL)didResetCallingStateForConversation:(ZMConversation *)conversation;
{
    XCTAssertFalse(conversation.callDeviceIsActive);
    XCTAssertFalse(conversation.isVideoCall);
    XCTAssertEqual(conversation.otherActiveVideoCallParticipants.count, 0lu);
    XCTAssertEqual(conversation.activeFlowParticipants.count, 0lu );
    XCTAssertEqual(conversation.callParticipants.count, 0lu);
    XCTAssertFalse(conversation.isFlowActive);
    XCTAssertFalse(conversation.isSendingVideo);
    XCTAssertFalse([self.syncMOC zm_hasTimerForConversation:conversation]);
    
    
    return (!conversation.callDeviceIsActive &&
            !conversation.isVideoCall &&
            conversation.otherActiveVideoCallParticipants.count == 0lu &&
            conversation.activeFlowParticipants.count == 0lu &&
            conversation.callParticipants.count == 0lu &&
            !conversation.isFlowActive &&
            !conversation.isSendingVideo &&
            ![self.syncMOC zm_hasTimerForConversation:conversation]);
}

- (void)testThatItSetsIsVideoCallWhenReceivinigAnIncomingVideoCall
{
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    
    id mockFlowManager = [OCMockObject partialMockForObject:self.mockFlowManager];
    
    // when
    [self otherJoinVideoCall];
    WaitForEverythingToBeDone();
    
    // then
    XCTAssertTrue(self.conversationUnderTest.isVideoCall);
    [mockFlowManager stopMocking];
}

- (void)testThatItSendsARequestToInitializeAVideoCall
{
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    
    // when
    [self.mockTransportSession resetReceivedRequests];
    
    [self selfJoinVideoCall];
    WaitForEverythingToBeDone();
    
    // then
    XCTAssertEqual(self.mockTransportSession.receivedRequests.count, 1u);
    XCTAssertTrue([self lastRequestIsVideoActive:YES]);
    
    XCTAssertTrue(self.conversationUnderTest.isVideoCall);
}

- (void)testThatItCancelCallWhenFailToInitialiseCall;
{
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    
    // when
    self.mockTransportSession.responseGeneratorBlock = ^ZMTransportResponse *(__unused ZMTransportRequest *request) {
        return [ZMTransportResponse responseWithTransportSessionError:[NSError requestExpiredError]];
    };
    [self selfJoinVideoCall];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertTrue([self didResetCallingStateForConversation:self.conversationUnderTest]);
    XCTAssertTrue([self lastRequestContainsSelfStateIdle]);
}

- (void)testThatWeCanCancelACall;
{
    //given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    WaitForAllGroupsToBeEmpty(0.5);
    
    [self.mockTransportSession resetReceivedRequests];
    
    [self selfJoinVideoCall];
    WaitForAllGroupsToBeEmpty(0.5);
    XCTAssertTrue(self.conversationUnderTest.isVideoCall);
    XCTAssertFalse(self.conversationUnderTest.isSendingVideo);
    XCTAssertTrue([self lastRequestContainsSelfStateJoined]);
    
    //when
    [self selfDropVideoCall];
    WaitForAllGroupsToBeEmpty(0.5);
    
    //then
    XCTAssertTrue([self didResetCallingStateForConversation:self.conversationUnderTest]);
    XCTAssertTrue([self lastRequestContainsSelfStateIdle]);
}

- (void)testThatWeStopSendingCallIfBackendIsNotReachableAndTryToNotify;
{
    //given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    WaitForAllGroupsToBeEmpty(0.5);
    
    __block NSUInteger requestCount = 0;
    self.mockTransportSession.responseGeneratorBlock = ^ZMTransportResponse*(__unused ZMTransportRequest *request) {
        if (requestCount > 1) {
            return nil;
        }
        requestCount++;
        return [ZMTransportResponse responseWithTransportSessionError:[NSError requestExpiredError]];
    };
    [self.mockTransportSession resetReceivedRequests];
    
    [self selfJoinVideoCall];
    WaitForAllGroupsToBeEmpty(0.5);
    
    XCTAssertTrue([self didResetCallingStateForConversation:self.conversationUnderTest]);
    XCTAssertGreaterThan(self.mockTransportSession.receivedRequests.count, 1lu);
    XCTAssertTrue([self lastRequestContainsSelfStateIdle]);
}

- (void)testThatWeStopSendingCallForPermanentError;
{
    //given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    WaitForAllGroupsToBeEmpty(0.5);
    
    self.mockTransportSession.responseGeneratorBlock = ^ZMTransportResponse*(__unused ZMTransportRequest *request) {
        return [ZMTransportResponse responseWithPayload:@{} HTTPStatus:400 transportSessionError:nil];
    };
    [self.mockTransportSession resetReceivedRequests];
    
    [self selfJoinVideoCall];
    WaitForAllGroupsToBeEmpty(0.5);
    
    XCTAssertTrue([self didResetCallingStateForConversation:self.conversationUnderTest]);
    XCTAssertEqual(self.mockTransportSession.receivedRequests.count, 1lu);
    XCTAssertTrue([self lastRequestContainsSelfStateJoined]);
}


- (void)testThatWeContinueSendingRequestToCancelTheCallWhenFailingToSendCancelRequest;
{
    //given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    WaitForAllGroupsToBeEmpty(0.5);
    
    [self.mockTransportSession resetReceivedRequests];
    
    [self selfJoinVideoCall];
    WaitForAllGroupsToBeEmpty(0.5);
    XCTAssertTrue(self.conversationUnderTest.callDeviceIsActive);
    XCTAssertTrue(self.conversationUnderTest.isVideoCall);
    XCTAssertFalse(self.conversationUnderTest.isSendingVideo);
    XCTAssertTrue([self lastRequestContainsSelfStateJoined]);
    
    [self.mockTransportSession resetReceivedRequests];
    
    __block NSUInteger requestCount = 0;
    self.mockTransportSession.responseGeneratorBlock = ^ZMTransportResponse*(__unused ZMTransportRequest *request) {
        if (requestCount > 1) {
            return nil;
        }
        requestCount++;
        return [ZMTransportResponse responseWithTransportSessionError:[NSError requestExpiredError]];
    };
    
    //when drop is expiring
    [self selfDropVideoCall];
    WaitForAllGroupsToBeEmpty(0.5);
    
    //then conversation
    XCTAssertTrue([self didResetCallingStateForConversation:self.conversationUnderTest]);
    XCTAssertGreaterThan(self.mockTransportSession.receivedRequests.count, 1lu);
    XCTAssertTrue([self lastRequestContainsSelfStateIdle]);

}

- (void)testThatItResetsIsVideoCallWhenOtherDropsTheCall;
{
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    
    [self selfJoinVideoCall];
    WaitForEverythingToBeDone();
    XCTAssertTrue(self.conversationUnderTest.isVideoCall);
    
    // when
    [self otherDropsCall];
    WaitForEverythingToBeDone();
    
    //then
    XCTAssertTrue([self didResetCallingStateForConversation:self.conversationUnderTest]);
}

- (void)testThatWeCanIgnoreAVideoCall;
{
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    WaitForAllGroupsToBeEmpty(0.5);
    
    ZMConversation *oneToOneConversation = self.conversationUnderTest;
    V2CallStateTestObserver *observer = [[V2CallStateTestObserver alloc] init];
    id token = [WireCallCenterV2 addVoiceChannelStateObserverWithObserver:observer context:self.uiMOC];
    
    [self.mockTransportSession resetReceivedRequests];
    
    // (1) other user joins
    {
        // when
        [self otherJoinVideoCall];
        WaitForAllGroupsToBeEmpty(0.5);
        
        // then
        XCTAssertEqual(observer.changes.count, 1u);
        XCTAssertEqual(observer.changes.firstObject.state, VoiceChannelV2StateIncomingCall);
        XCTAssertTrue(self.conversationUnderTest.isVideoCall);
        XCTAssertFalse(self.conversationUnderTest.isIgnoringCall);
    }
    
    [self.mockTransportSession resetReceivedRequests];
    
    // (2) we ignore
    {
        // when
        [self.userSession performChanges:^{
            [oneToOneConversation.voiceChannelRouter.v2 ignore];
        }];
        WaitForAllGroupsToBeEmpty(0.5);
        
        // then
        XCTAssertEqual(observer.changes.count, 2u);
        XCTAssertEqual(observer.changes.lastObject.state, VoiceChannelV2StateNoActiveUsers);
        XCTAssertTrue(self.conversationUnderTest.isVideoCall);
        XCTAssertTrue(self.conversationUnderTest.isIgnoringCall);
    }
    
    [WireCallCenterV2 removeObserverWithToken:token];
    [self tearDownVoiceChannelForConversation:oneToOneConversation];
}

- (void)testThatWeProperlyReleaseVideoFlowWhenWeTimeout;
{
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    
    ZMConversation *conversation = self.conversationUnderTest;
    [ZMCallTimer setTestCallTimeout: 0.2];
    
    [self selfJoinVideoCall];
    WaitForAllGroupsToBeEmpty(0.5);
    XCTAssertTrue(conversation.isVideoCall);
        
    // when waiting for call to timeout
    [self spinMainQueueWithTimeout:0.5];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertTrue([self didResetCallingStateForConversation:self.conversationUnderTest]);
}

- (void)testThatItSetsIsSendingVideoWhenSelfUserTogglesVideoAndResetsIsVideoCallWhenTheSelfUserEndsTheCall
{
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    ZMUser *selfUser = [self userForMockUser:self.selfUser];
    ZMUser *otherUser = [self userForMockUser:self.user2];

    // when
    [self otherJoinVideoCall];
    WaitForEverythingToBeDone();
    XCTAssertTrue(self.conversationUnderTest.isVideoCall);
    XCTAssertFalse(self.conversationUnderTest.hasLocalModificationsForIsSendingVideo);

    [self selfJoinVideoCall];
    WaitForEverythingToBeDone();
    XCTAssertTrue(self.conversationUnderTest.isVideoCall);
    XCTAssertFalse(self.conversationUnderTest.isSendingVideo);
    XCTAssertFalse(self.conversationUnderTest.hasLocalModificationsForIsSendingVideo);
    XCTAssertFalse(self.conversationUnderTest.isFlowActive);
    XCTAssertEqual(self.conversationUnderTest.otherActiveVideoCallParticipants.count, 0u);

    // and when
    // selfuser establishes media
    {
        [self.mockTransportSession resetReceivedRequests];
        [self simulateMediaFlowEstablished];
        WaitForAllGroupsToBeEmpty(0.5);
        
        // then
        XCTAssertTrue([self.conversationUnderTest.voiceChannel stateForParticipant:otherUser].isSendingVideo);
        XCTAssertTrue([self.conversationUnderTest.voiceChannel stateForParticipant:selfUser].isSendingVideo);
        XCTAssertEqual(self.mockTransportSession.receivedRequests.count, 1u);
        XCTAssertTrue([self lastRequestIsVideoActive:YES]);
        
        XCTAssertTrue(self.conversationUnderTest.isSendingVideo);
        XCTAssertTrue(self.conversationUnderTest.isVideoCall);
        XCTAssertTrue(self.conversationUnderTest.isFlowActive);
        XCTAssertEqual(self.conversationUnderTest.otherActiveVideoCallParticipants.count, 1u);
    }
    
    // and when
    // selfuser deactivates video stream
    {
        [self.mockTransportSession resetReceivedRequests];
        [self simulateSelfUserActivatesVideo:NO];
        WaitForAllGroupsToBeEmpty(0.5);
        
        // then
        XCTAssertTrue([self.conversationUnderTest.voiceChannel stateForParticipant:otherUser].isSendingVideo);
        XCTAssertFalse([self.conversationUnderTest.voiceChannel stateForParticipant:selfUser].isSendingVideo);
        XCTAssertEqual(self.mockTransportSession.receivedRequests.count, 1u);
        XCTAssertTrue([self lastRequestIsVideoActive:NO]);
        
        XCTAssertFalse(self.conversationUnderTest.isSendingVideo);
        XCTAssertTrue(self.conversationUnderTest.isVideoCall);
        XCTAssertTrue(self.conversationUnderTest.isFlowActive);
        XCTAssertEqual(self.conversationUnderTest.otherActiveVideoCallParticipants.count, 1u);
    }
    
    // and when
    // selfuser activates video stream
    {
        [self.mockTransportSession resetReceivedRequests];
        [self simulateSelfUserActivatesVideo:YES];
        WaitForAllGroupsToBeEmpty(0.5);
        
        // then
        XCTAssertTrue([self.conversationUnderTest.voiceChannel stateForParticipant:otherUser].isSendingVideo);
        XCTAssertTrue([self.conversationUnderTest.voiceChannel stateForParticipant:selfUser].isSendingVideo);
        XCTAssertEqual(self.mockTransportSession.receivedRequests.count, 1u);
        XCTAssertTrue([self lastRequestIsVideoActive:YES]);
        
        XCTAssertTrue(self.conversationUnderTest.isSendingVideo);
        XCTAssertTrue(self.conversationUnderTest.isVideoCall);
        XCTAssertTrue(self.conversationUnderTest.isFlowActive);
        XCTAssertEqual(self.conversationUnderTest.otherActiveVideoCallParticipants.count, 1u);
    }
    
    // and when
    [self selfDropCall];
    WaitForEverythingToBeDone();
    
    // then
    XCTAssertTrue([self didResetCallingStateForConversation:self.conversationUnderTest]);
}

- (void)testThatItNotifiesTheUIIfMediaCanNotBeEstablishedButDoesNotUpdateStateOnBackend
{
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    id observer = [OCMockObject niceMockForProtocol:@protocol(CallingInitialisationObserver)];
    id token = [self.conversationUnderTest.voiceChannelRouter.v2 addCallingInitializationObserver:observer];
    
    // when
    [self otherJoinVideoCall];
    WaitForEverythingToBeDone();
    XCTAssertTrue(self.conversationUnderTest.isVideoCall);
    
    [self selfJoinVideoCall];
    WaitForEverythingToBeDone();
    XCTAssertTrue(self.conversationUnderTest.isVideoCall);
    XCTAssertFalse(self.conversationUnderTest.isSendingVideo);
    XCTAssertFalse(self.conversationUnderTest.isFlowActive);
    XCTAssertEqual(self.conversationUnderTest.otherActiveVideoCallParticipants.count, 0u);
    
    // and when
    // selfuser establishes media but can not send video
    {
        [[observer expect] couldNotInitialiseCallWithError:[OCMArg checkWithBlock:^BOOL(NSError *error) {
            return (error.code == VoiceChannelV2ErrorCodeVideoCallingNotSupported);
        }]];
        
        [self.mockTransportSession resetReceivedRequests];
        [self.mockFlowManager.delegate didEstablishMediaInConversation:self.mockConversationUnderTest.identifier];
        WaitForAllGroupsToBeEmpty(0.5);
        
        // then
        // we don't want to sync with the be, otherwise it is not compatible with older clients
        XCTAssertEqual(self.mockTransportSession.receivedRequests.count, 0u);
        
        XCTAssertFalse(self.conversationUnderTest.isSendingVideo);
        XCTAssertTrue(self.conversationUnderTest.isVideoCall);
        XCTAssertTrue(self.conversationUnderTest.isFlowActive);
        XCTAssertEqual(self.conversationUnderTest.otherActiveVideoCallParticipants.count, 1u);
    }
    
    // and when
    [self selfDropCall];
    WaitForEverythingToBeDone();
    
    // then
    XCTAssertTrue([self didResetCallingStateForConversation:self.conversationUnderTest]);
    
    [observer verify];
    [self.conversationUnderTest.voiceChannelRouter.v2 removeCallingInitialisationObserver:token];
}

- (void)testThatItNotifiesWhenOtherUserActivatesAndDeactivatesVideoAndResetsIsVideoCallWhenTheOtherUserEndsTheCall
{
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    
    id observer = [OCMockObject niceMockForProtocol:@protocol(ReceivedVideoObserver)];
    id token = nil;
    token = [WireCallCenterV2 addReceivedVideoObserverWithObserver:observer forConversation:self.conversationUnderTest context:self.uiMOC];
    
    // (0) the call gets established, selfUser starts sending video
    {
        [self otherJoinVideoCall];
        WaitForEverythingToBeDone();
        
        [self selfJoinVideoCall];
        WaitForEverythingToBeDone();
        XCTAssertTrue(self.conversationUnderTest.isVideoCall);
        XCTAssertFalse(self.conversationUnderTest.isSendingVideo);
        XCTAssertEqual(self.conversationUnderTest.otherActiveVideoCallParticipants.count, 0u);
        
        [[observer expect] callCenterDidChangeReceivedVideoState:ReceivedVideoStateStarted];
        
        [self simulateMediaFlowEstablished];
        WaitForEverythingToBeDone();
        XCTAssertTrue(self.conversationUnderTest.isSendingVideo);
        XCTAssertEqual(self.conversationUnderTest.otherActiveVideoCallParticipants.count, 1u);
    }
    
    // (1) other user deactivates video
    // we receive a push event with video NO
    {
        NSUInteger currentEventCount = self.mockTransportSession.updateEvents.count;
        
        [[observer expect] callCenterDidChangeReceivedVideoState:ReceivedVideoStateStopped];
        
        // when
        [self.mockTransportSession performRemoteChanges:^(ZM_UNUSED id session) {
            [self.mockFlowManager simulateOther:self.user2 isSendingVideo:NO conv:self.selfToUser2Conversation];
        }];
        WaitForEverythingToBeDone();
        
        // then
        XCTAssertNotEqual(self.mockTransportSession.updateEvents.count, currentEventCount);
        XCTAssertEqual(self.conversationUnderTest.otherActiveVideoCallParticipants.count, 0u);
    }
    // (2) other user activates video
    // we receive a push event with video YES
    {
        [[observer expect] callCenterDidChangeReceivedVideoState:ReceivedVideoStateStarted];
        NSUInteger currentEventCount1 = self.mockTransportSession.updateEvents.count;
        
        // when
        [self.mockTransportSession performRemoteChanges:^(ZM_UNUSED id session) {
            [self.mockFlowManager simulateOther:self.user2 isSendingVideo:YES conv:self.selfToUser2Conversation];
        }];
        WaitForEverythingToBeDone();
        
        // then
        XCTAssertNotEqual(self.mockTransportSession.updateEvents.count, currentEventCount1);
        XCTAssertEqual(self.conversationUnderTest.otherActiveVideoCallParticipants.count, 1u);
    }
    [observer verify];

    // (3) other user ends the call
    // everything is reset
    {
        [self otherDropsCall];
        WaitForEverythingToBeDone();
        
        // then
        XCTAssertTrue([self didResetCallingStateForConversation:self.conversationUnderTest]);
    }
    
    // (4) selfUser calls again with audio
    // we send an audio call request
    {
        [self.mockTransportSession resetReceivedRequests];
        [self selfJoinCall];
        WaitForAllGroupsToBeEmpty(0.5);
        
        // then
        XCTAssertEqual(self.mockTransportSession.receivedRequests.count, 1u);
        XCTAssertTrue([self lastRequestIsVideoActive:NO]);
        
        XCTAssertFalse(self.conversationUnderTest.isVideoCall);
        XCTAssertFalse(self.conversationUnderTest.isSendingVideo);
    }
}

- (void)testThatItCanJoinTwoVideoCallInARow;
{
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    
    // (0) the call gets established, selfUser starts sending video
    {
        [self otherJoinVideoCall];
        WaitForEverythingToBeDone();
        
        [self selfJoinVideoCall];
        WaitForEverythingToBeDone();
        XCTAssertTrue(self.conversationUnderTest.isVideoCall);
        XCTAssertFalse(self.conversationUnderTest.isSendingVideo);
        XCTAssertEqual(self.conversationUnderTest.otherActiveVideoCallParticipants.count, 0u);
        
        [self simulateMediaFlowEstablished];
        WaitForEverythingToBeDone();
        XCTAssertTrue(self.conversationUnderTest.isSendingVideo);
        XCTAssertEqual(self.conversationUnderTest.otherActiveVideoCallParticipants.count, 1u);
    }
    
    // (1) other user ends the call
    // everything is reset
    {
        [self otherDropsCall];
        WaitForEverythingToBeDone();
        
        // then
        XCTAssertTrue([self didResetCallingStateForConversation:self.conversationUnderTest]);
    }
    
    // (2) re-establish an new call
    // we send an video call request
    
    {
        [self otherJoinVideoCall];
        WaitForEverythingToBeDone();
        
        [self selfJoinVideoCall];
        WaitForEverythingToBeDone();
        XCTAssertTrue(self.conversationUnderTest.isVideoCall);
        XCTAssertFalse(self.conversationUnderTest.isSendingVideo);
        XCTAssertEqual(self.conversationUnderTest.otherActiveVideoCallParticipants.count, 0u);
        
        [self simulateMediaFlowEstablished];
        WaitForEverythingToBeDone();
        XCTAssertTrue(self.conversationUnderTest.isSendingVideo);
        XCTAssertEqual(self.conversationUnderTest.otherActiveVideoCallParticipants.count, 1u);
    }
}

- (void)testThatUserReceivesMissedCalledMessageWhenMissingVideoCall;
{
    //given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    WaitForAllGroupsToBeEmpty(0.5);
    
    
    [self otherJoinVideoCall];
    WaitForAllGroupsToBeEmpty(0.5);
    XCTAssertTrue(self.conversationUnderTest.isVideoCall);
    XCTAssertFalse(self.conversationUnderTest.isSendingVideo);
    
    //when
    [self otherLeavesUnansweredCall];
    WaitForAllGroupsToBeEmpty(0.5);
    
    //then
    XCTAssertTrue([self didResetCallingStateForConversation:self.conversationUnderTest]);
    
    ZMMessage *lastMessage = [self.conversationUnderTest.messages lastObject];
    XCTAssertTrue([lastMessage isKindOfClass:[ZMSystemMessage class]]);
    ZMSystemMessage *systemMessage = (ZMSystemMessage *)lastMessage;
    XCTAssertEqual(systemMessage.systemMessageType, ZMSystemMessageTypeMissedCall);
}

- (void)testThatCallStopsAfterTimeout;
{
    //given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    WaitForAllGroupsToBeEmpty(0.5);
    [ZMCallTimer setTestCallTimeout:0.2];
    
    [self selfJoinVideoCall];
    WaitForAllGroupsToBeEmpty(0.5);
    XCTAssertTrue(self.conversationUnderTest.isVideoCall);
    XCTAssertFalse(self.conversationUnderTest.isSendingVideo);
    XCTAssertTrue([self lastRequestContainsSelfStateJoined]);

    //when timeout
    [self spinMainQueueWithTimeout:0.5];
    WaitForAllGroupsToBeEmpty(0.5);
    
    //then
    [self didResetCallingStateForConversation:self.conversationUnderTest];
    XCTAssertTrue([self lastRequestContainsSelfStateIdle]);
}

@end
