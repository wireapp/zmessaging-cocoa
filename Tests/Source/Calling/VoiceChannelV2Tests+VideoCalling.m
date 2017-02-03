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


@import zmessaging;
@import ZMCDataModel;
@import avs;

#import "VoiceChannelV2Tests.h"
#import "ZMUserSession+Internal.h"

@import ZMCMockTransport;

extern id ZMFlowSyncInternalFlowManagerOverride;

@implementation VoiceChannelV2Tests (VideoCalling)


- (void)testThatItCallsIsSendingVideoForParticipantAndReturnValue_hasFlowManager
{
    // given
    XCTestExpectation *callExpectation = [self expectationWithDescription:@"Method called"];
    self.conversation.isVideoCall = YES;
    
    id flowManagerMock = [OCMockObject mockForClass:[MockFlowManager class]];
    [[[flowManagerMock stub] andReturnValue:@(YES)] isReady];
    [[[flowManagerMock stub] andReturnValue:@(YES)] isSendingVideoInConversation:[OCMArg checkWithBlock:^BOOL(id obj) {
        XCTAssertEqualObjects(obj, self.conversation.remoteIdentifier.transportString);
        [callExpectation fulfill];
        return YES;
    }]
                    forParticipant:[OCMArg checkWithBlock:^BOOL(id obj) {
        XCTAssertEqualObjects(obj, self.conversation.connection.to.remoteIdentifier.transportString);
        return YES;
    }]];

    ZMFlowSyncInternalFlowManagerOverride = flowManagerMock;
    
    // when
    NSError *error = nil;
    BOOL result = [self.conversation.voiceChannelRouter.v2 isSendingVideoForParticipant:self.conversation.connection.to error:&error];
    
    // then
    XCTAssertTrue(result);
    XCTAssertNil(error);
    XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0.5f]);
    
    ZMFlowSyncInternalFlowManagerOverride = nil;
}

- (void)testThatItCallsIsSendingVideoForParticipantAndReturnValue_noFlowManager
{
    // given
    ZMFlowSyncInternalFlowManagerOverride = nil;
    // when
    NSError *error = nil;
    BOOL result = [self.conversation.voiceChannelRouter.v2 isSendingVideoForParticipant:self.conversation.connection.to error:&error];
    
    // then
    XCTAssertFalse(result);
    XCTAssertNotNil(error);
    
    ZMFlowSyncInternalFlowManagerOverride = nil;
}

- (void)testThatItCallsIsSendingVideoForParticipantAndReturnValue_FlowManagerNotReady
{
    // given
    id flowManagerMock = [OCMockObject mockForClass:[MockFlowManager class]];
    [[[flowManagerMock stub] andReturnValue:@(NO)] isReady];
    ZMFlowSyncInternalFlowManagerOverride = flowManagerMock;

    // when
    NSError *error = nil;
    BOOL result = [self.conversation.voiceChannelRouter.v2 isSendingVideoForParticipant:self.conversation.connection.to error:&error];
    
    // then
    XCTAssertFalse(result);
    XCTAssertNotNil(error);
    
    ZMFlowSyncInternalFlowManagerOverride = nil;
}

- (void)testThatItCallsSetVideoSendActiveAndReturnValue_hasFlowManager
{
    // given
    XCTestExpectation *callExpectation = [self expectationWithDescription:@"Method called"];
    
    id flowManagerMock = [OCMockObject mockForClass:[MockFlowManager class]];
    [[[flowManagerMock stub] andReturnValue:@(YES)] isReady];

    [(MockFlowManager *)[[flowManagerMock stub] andDo:^(NSInvocation *invocation __unused) {
        [callExpectation fulfill];
    }] setVideoSendState:FLOWMANAGER_VIDEO_SEND
         forConversation:[OCMArg checkWithBlock:^BOOL(id obj) {
        XCTAssertEqualObjects(obj, self.conversation.remoteIdentifier.transportString);
        return YES;
    }]];
    
    [[[flowManagerMock stub] andReturnValue:@(YES)] isMediaEstablishedInConversation:OCMOCK_ANY];
    [[[flowManagerMock stub] andReturnValue:@(YES)] canSendVideoForConversation:OCMOCK_ANY];
    
    ZMFlowSyncInternalFlowManagerOverride = flowManagerMock;
    
    // when
    NSError *error = nil;
    BOOL result = [self.conversation.voiceChannelRouter.v2 setVideoSendState:FLOWMANAGER_VIDEO_SEND error:&error];
    
    // then
    XCTAssertTrue(result);
    XCTAssertNil(error);
    XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0.5f]);
    ZMFlowSyncInternalFlowManagerOverride = nil;
}

- (void)testThatItCallsSetVideoSendActiveAndReturnValue_noFlowManager
{
    // given
    
    ZMFlowSyncInternalFlowManagerOverride = nil;
    
    // when
    NSError *error = nil;
    BOOL result = [self.conversation.voiceChannelRouter.v2 setVideoSendState:FLOWMANAGER_VIDEO_SEND error:&error];
    
    // then
    XCTAssertFalse(result);
    XCTAssertNotNil(error);
    ZMFlowSyncInternalFlowManagerOverride = nil;
}

- (void)testThatItCallsSetVideoSendActiveAndReturnValue_noMedia
{
    // given
    id flowManagerMock = [OCMockObject mockForClass:[MockFlowManager class]];
    [[[flowManagerMock stub] andReturnValue:@(YES)] isReady];

    [[[flowManagerMock stub] andReturnValue:@(NO)] isMediaEstablishedInConversation:OCMOCK_ANY];
    [[[flowManagerMock stub] andReturnValue:@(YES)] canSendVideoForConversation:OCMOCK_ANY];
    
    ZMFlowSyncInternalFlowManagerOverride = flowManagerMock;
    
    // when
    NSError *error = nil;
    BOOL result = [self.conversation.voiceChannelRouter.v2 setVideoSendState:FLOWMANAGER_VIDEO_SEND error:&error];
    
    // then
    XCTAssertFalse(result);
    XCTAssertNotNil(error);
    XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0.5f]);
    ZMFlowSyncInternalFlowManagerOverride = nil;
}

- (void)testThatItCallsSetVideoSendActiveAndReturnValue_cannotSend
{
    // given
    id flowManagerMock = [OCMockObject mockForClass:[MockFlowManager class]];
    [[[flowManagerMock stub] andReturnValue:@(YES)] isReady];

    [[[flowManagerMock stub] andReturnValue:@(YES)] isMediaEstablishedInConversation:OCMOCK_ANY];
    [[[flowManagerMock stub] andReturnValue:@(NO)] canSendVideoForConversation:OCMOCK_ANY];
    
    ZMFlowSyncInternalFlowManagerOverride = flowManagerMock;
    
    // when
    NSError *error = nil;
    BOOL result = [self.conversation.voiceChannelRouter.v2 setVideoSendState:FLOWMANAGER_VIDEO_SEND error:&error];
    
    // then
    XCTAssertFalse(result);
    XCTAssertNotNil(error);
    XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0.5f]);
    ZMFlowSyncInternalFlowManagerOverride = nil;
}

// FIXME move to VoiceChannelRouterTests
- (void)testThatItCallsSetVideoCaptureDeviewAndReturnValue_hasFlowManager
{
    // given
    XCTestExpectation *callExpectation = [self expectationWithDescription:@"Method called"];
    self.conversation.isVideoCall = YES;

    id flowManagerMock = [OCMockObject mockForClass:[MockFlowManager class]];
    [[[flowManagerMock stub] andReturnValue:@(YES)] isReady];

    [[[flowManagerMock stub] andDo:^(NSInvocation *invocation __unused) {
        [callExpectation fulfill];
    }] setVideoCaptureDevice:[OCMArg checkWithBlock:^BOOL(id obj) {
        XCTAssertNotNil(obj);
        return YES;
    }]
     forConversation:[OCMArg checkWithBlock:^BOOL(id obj) {
        XCTAssertEqualObjects(obj, self.conversation.remoteIdentifier.transportString);
        return YES;
    }]];
    
    ZMFlowSyncInternalFlowManagerOverride = flowManagerMock;
    
    // when
    NSError *error = nil;
    BOOL result = [self.conversation.voiceChannel setVideoCaptureDeviceWithDevice:ZMCaptureDeviceFront error:&error];
    
    // then
    XCTAssertTrue(result);
    XCTAssertNil(error);
    XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0.5f]);
    ZMFlowSyncInternalFlowManagerOverride = nil;

}

// FIXME move to VoiceChannelRouterTests
- (void)testThatItCallsSetVideoCaptureDeviceAndReturnValue_noFlowManager
{
    // given
    ZMFlowSyncInternalFlowManagerOverride = nil;
    
    // when
    NSError *error = nil;
    BOOL result = [self.conversation.voiceChannel setVideoCaptureDeviceWithDevice:ZMCaptureDeviceFront error:&error];
    
    // then
    XCTAssertFalse(result);
    XCTAssertNotNil(error);
    ZMFlowSyncInternalFlowManagerOverride = nil;

}

- (void)testThatItSetsIsVideoCallWhenJoiningVideoCall
{
    // when
    NSError *error;
    [self.conversation.voiceChannelRouter.v2 joinVideoCall];
    
    // then
    XCTAssertTrue(self.conversation.isVideoCall);
    XCTAssertNil(error);
}

- (void)testThatItResetsIsVideoCallWhenLeavingVideoCall
{
    // givne
    NSError *error;
    [self.conversation.voiceChannelRouter.v2 joinVideoCall];
    XCTAssertNil(error);

    // when
    [self.conversation.voiceChannelRouter.v2 leave];
    
    // then
    XCTAssertFalse(self.conversation.isVideoCall);
}

- (void)testThatItFailsToStartVideoCallWhenAudioCallIsStarted;
{
    //given
    [self.conversation.voiceChannelRouter.v2 join];
    
    // when
    __block BOOL didJoin;
    [self performIgnoringZMLogError:^{
        didJoin = [self.conversation.voiceChannelRouter.v2 joinVideoCall];
    }];
    
    // then
    XCTAssertFalse(didJoin);
}

- (void)testThatItSetsIsSendingVideoOnParticipantsState_SelfUser
{
    // given
    self.conversation.isSendingVideo = YES;
    
    // when
    VoiceChannelV2ParticipantState *state = [self.conversation.voiceChannelRouter.v2 stateForParticipant:self.selfUser];
    
    // then
    XCTAssertTrue(state.isSendingVideo);
}

- (void)testThatItDoesNotSetIsSendingVideoOnParticipantsState_SelfUser_NotSendingVideo
{
    // given
    self.conversation.isSendingVideo = NO;
    
    // when
    VoiceChannelV2ParticipantState *state = [self.conversation.voiceChannelRouter.v2 stateForParticipant:self.selfUser];
    
    // then
    XCTAssertFalse(state.isSendingVideo);
}


- (void)testThatItSetsIsSendingVideoOnParticipantsState_OtherUser
{
    // given
    self.conversation.isFlowActive = YES;
    [self.conversation addActiveVideoCallParticipant:self.otherUser];
    
    // when
    VoiceChannelV2ParticipantState *state = [self.conversation.voiceChannelRouter.v2 stateForParticipant:self.otherUser];
    
    // then
    XCTAssertTrue(state.isSendingVideo);
}

- (void)testThatItDoesNotSetIsSendingVideoOnParticipantsState_OtherUser_NotSendingVideo
{
    // given
    self.conversation.isFlowActive = YES;
    [self.conversation removeActiveVideoCallParticipant:self.otherUser];
    
    // when
    VoiceChannelV2ParticipantState *state = [self.conversation.voiceChannelRouter.v2 stateForParticipant:self.otherUser];
    
    // then
    XCTAssertFalse(state.isSendingVideo);
}

@end

