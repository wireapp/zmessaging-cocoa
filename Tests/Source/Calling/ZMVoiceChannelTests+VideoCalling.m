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

#import "ZMVoiceChannelTests.h"
#import <avs/AVSFlowManager.h> //TODO: remove when new avs framework complete
#import "ZMUserSession+Internal.h"

@import ZMCMockTransport;

extern id ZMFlowSyncInternalFlowManagerOverride;

@implementation ZMVoiceChannelTests (VideoCalling)


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
    BOOL result = [self.conversation.voiceChannel isSendingVideoForParticipant:self.conversation.connection.to error:&error];
    
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
    BOOL result = [self.conversation.voiceChannel isSendingVideoForParticipant:self.conversation.connection.to error:&error];
    
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
    BOOL result = [self.conversation.voiceChannel isSendingVideoForParticipant:self.conversation.connection.to error:&error];
    
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
    BOOL result = [self.conversation.voiceChannel setVideoSendState:FLOWMANAGER_VIDEO_SEND error:&error];
    
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
    BOOL result = [self.conversation.voiceChannel setVideoSendState:FLOWMANAGER_VIDEO_SEND error:&error];
    
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
    BOOL result = [self.conversation.voiceChannel setVideoSendState:FLOWMANAGER_VIDEO_SEND error:&error];
    
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
    BOOL result = [self.conversation.voiceChannel setVideoSendState:FLOWMANAGER_VIDEO_SEND error:&error];
    
    // then
    XCTAssertFalse(result);
    XCTAssertNotNil(error);
    XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0.5f]);
    ZMFlowSyncInternalFlowManagerOverride = nil;
}

- (void)testThatItCallsSetVideoCaptureDeviewAndReturnValue_hasFlowManager
{
    // given
    XCTestExpectation *callExpectation = [self expectationWithDescription:@"Method called"];
    NSString *deviceID = @"FRONT#1";
    self.conversation.isVideoCall = YES;

    id flowManagerMock = [OCMockObject mockForClass:[MockFlowManager class]];
    [[[flowManagerMock stub] andReturnValue:@(YES)] isReady];

    [[[flowManagerMock stub] andDo:^(NSInvocation *invocation __unused) {
        [callExpectation fulfill];
    }] setVideoCaptureDevice:[OCMArg checkWithBlock:^BOOL(id obj) {
        XCTAssertEqual(obj, deviceID);
        return YES;
    }]
     forConversation:[OCMArg checkWithBlock:^BOOL(id obj) {
        XCTAssertEqualObjects(obj, self.conversation.remoteIdentifier.transportString);
        return YES;
    }]];
    
    ZMFlowSyncInternalFlowManagerOverride = flowManagerMock;
    
    // when
    NSError *error = nil;
    BOOL result = [self.conversation.voiceChannel setVideoCaptureDevice:deviceID error:&error];
    
    // then
    XCTAssertTrue(result);
    XCTAssertNil(error);
    XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0.5f]);
    ZMFlowSyncInternalFlowManagerOverride = nil;

}

- (void)testThatItCallsSetVideoCaptureDeviceAndReturnValue_noFlowManager
{
    // given
    NSString *deviceID = @"FRONT#1";

    
    ZMFlowSyncInternalFlowManagerOverride = nil;
    
    // when
    NSError *error = nil;
    BOOL result = [self.conversation.voiceChannel setVideoCaptureDevice:deviceID error:&error];
    
    // then
    XCTAssertFalse(result);
    XCTAssertNotNil(error);
    ZMFlowSyncInternalFlowManagerOverride = nil;

}

- (void)testThatItStartingVideoSetsCurrentVideoToDefaultBack;
{
    // given
    id flowManagerMock = [OCMockObject mockForClass:[MockFlowManager class]];
    [[[flowManagerMock stub] andReturnValue:@(YES)] isReady];

    [(MockFlowManager *)[flowManagerMock stub] setVideoSendState:FLOWMANAGER_VIDEO_SEND forConversation:OCMOCK_ANY];
    
    [[[flowManagerMock stub] andReturnValue:@(YES)] isMediaEstablishedInConversation:OCMOCK_ANY];
    [[[flowManagerMock stub] andReturnValue:@(YES)] canSendVideoForConversation:OCMOCK_ANY];
    
    ZMFlowSyncInternalFlowManagerOverride = flowManagerMock;
    
    // when
    NSError *error = nil;
    BOOL result = [self.conversation.voiceChannel setVideoSendState:FLOWMANAGER_VIDEO_SEND error:&error];
    
    // then
    XCTAssertTrue(result);
    XCTAssertNil(error);
    XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0.5f]);
    XCTAssertEqualObjects(self.conversation.voiceChannel.currentVideoDeviceID, ZMFrontCameraDeviceID);
    ZMFlowSyncInternalFlowManagerOverride = nil;

}

- (void)testThatQueryingDeviceIDReturnsTheCorrectOne
{
    // given
    self.conversation.isVideoCall = YES;

    id flowManagerMock = [OCMockObject mockForClass:[MockFlowManager class]];
    [[[flowManagerMock stub] andReturnValue:@(YES)] isReady];

    [(MockFlowManager *)[flowManagerMock expect] setVideoSendState:FLOWMANAGER_VIDEO_SEND forConversation:OCMOCK_ANY];
    
    [[[flowManagerMock stub] andReturnValue:@(YES)] isMediaEstablishedInConversation:OCMOCK_ANY];
    [[[flowManagerMock stub] andReturnValue:@(YES)] canSendVideoForConversation:OCMOCK_ANY];
    [[flowManagerMock stub] setVideoCaptureDevice:OCMOCK_ANY forConversation:OCMOCK_ANY];
    
    ZMFlowSyncInternalFlowManagerOverride = flowManagerMock;
    
    NSError *error = nil;
    XCTAssertTrue([self.conversation.voiceChannel setVideoSendState:FLOWMANAGER_VIDEO_SEND error:&error]);
    
    XCTAssertNil(error); // sanity check
    
    //when
    [self.conversation.voiceChannel setVideoCaptureDevice:[ZMFrontCameraDeviceID copy] error:&error];
    XCTAssertNil(error);
    XCTAssertEqualObjects(self.conversation.voiceChannel.currentVideoDeviceID, ZMFrontCameraDeviceID);
    ZMFlowSyncInternalFlowManagerOverride = nil;

}

- (void)testThatSettingVideoCaptureWithoutHAvingVideoActiveTriggerAnError
{
    // given
    id flowManagerMock = [OCMockObject mockForClass:[MockFlowManager class]];
    [[[flowManagerMock stub] andReturnValue:@(YES)] isReady];

    [(MockFlowManager *)[flowManagerMock expect] setVideoSendState:FLOWMANAGER_VIDEO_SEND forConversation:OCMOCK_ANY];
    
    [[[flowManagerMock stub] andReturnValue:@(YES)] isMediaEstablishedInConversation:OCMOCK_ANY];
    [[[flowManagerMock stub] andReturnValue:@(YES)] canSendVideoForConversation:OCMOCK_ANY];
    
    ZMFlowSyncInternalFlowManagerOverride = flowManagerMock;
    
    NSError *error = nil;
    //when
    [self.conversation.voiceChannel setVideoCaptureDevice:[ZMFrontCameraDeviceID copy] error:&error];
    
    //then
    XCTAssertNotNil(error);
    XCTAssertEqual(error.code, (long)ZMVoiceChannelErrorCodeVideoNotActive);
    XCTAssertEqualObjects(error.domain, ZMVoiceChannelVideoCallErrorDomain);
    ZMFlowSyncInternalFlowManagerOverride = nil;

}

- (void)testThatItSetsIsVideoCallWhenJoinignVideoCall
{
    // when
    NSError *error;
    [self.conversation.voiceChannel joinVideoCall:&error];
    
    // then
    XCTAssertTrue(self.conversation.isVideoCall);
    XCTAssertNil(error);
}

- (void)testThatItResetsIsVideoCallWhenLeavingVideoCall
{
    // givne
    NSError *error;
    [self.conversation.voiceChannel joinVideoCall:&error];
    XCTAssertNil(error);

    // when
    [self.conversation.voiceChannel leave];
    
    // then
    XCTAssertFalse(self.conversation.isVideoCall);
}

- (void)testThatItNotifyObserverWhenInitialisingVideoCallFails;
{
    //given
    [self.conversation.voiceChannel join];
    
    // when
    NSError *error;
    BOOL didJoin = [self.conversation.voiceChannel joinVideoCall:&error];
    
    // then
    XCTAssertFalse(didJoin);
    XCTAssertNotNil(error);
    ZMVoiceChannelErrorCode expectedErrorType = ZMVoiceChannelErrorCodeSwitchToVideoNotAllowed;
    XCTAssertEqual(error.code, expectedErrorType);
}

- (void)testThatItSetsIsSendingVideoOnParticipantsState_SelfUser
{
    // given
    self.conversation.isSendingVideo = YES;
    
    // when
    ZMVoiceChannelParticipantState *state = [self.conversation.voiceChannel participantStateForUser:self.selfUser];
    
    // then
    XCTAssertTrue(state.isSendingVideo);
}

- (void)testThatItDoesNotSetIsSendingVideoOnParticipantsState_SelfUser_NotSendingVideo
{
    // given
    self.conversation.isSendingVideo = NO;
    
    // when
    ZMVoiceChannelParticipantState *state = [self.conversation.voiceChannel participantStateForUser:self.selfUser];
    
    // then
    XCTAssertFalse(state.isSendingVideo);
}


- (void)testThatItSetsIsSendingVideoOnParticipantsState_OtherUser
{
    // given
    self.conversation.isFlowActive = YES;
    [self.conversation addActiveVideoCallParticipant:self.otherUser];
    
    // when
    ZMVoiceChannelParticipantState *state = [self.conversation.voiceChannel participantStateForUser:self.otherUser];
    
    // then
    XCTAssertTrue(state.isSendingVideo);
}

- (void)testThatItDoesNotSetIsSendingVideoOnParticipantsState_OtherUser_NotSendingVideo
{
    // given
    self.conversation.isFlowActive = YES;
    [self.conversation removeActiveVideoCallParticipant:self.otherUser];
    
    // when
    ZMVoiceChannelParticipantState *state = [self.conversation.voiceChannel participantStateForUser:self.otherUser];
    
    // then
    XCTAssertFalse(state.isSendingVideo);
}

@end

