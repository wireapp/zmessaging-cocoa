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


#import "ZMCallStateTranscoderTests.h"


@implementation ZMCallStateTranscoderTests (VideoCalling)

- (void)testThatItSetsIsVideoWhenIsVideoCallIsTrue
{
    // given
    ZMConversation *conversation = self.syncSelfToUser1Conversation;
    conversation.isVideoCall = YES;
    conversation.callDeviceIsActive = YES;
    
    NSDictionary *expectedPayload = @{@"self" : @{
                                              @"state" : @"joined",
                                              @"suspended" : @(NO),
                                              @"videod" : @(YES)
                                              },
                                      @"cause": @"requested"
                                      };
    
    // when
    [[[self.gsmCallHandler expect] andReturnValue:OCMOCK_VALUE(NO)] isInterruptedCallConversation:conversation];
    ZMTransportRequest *request = [self.sut requestForUpdatingObject:conversation forKeys:self.keys].transportRequest;
    
    // then
    XCTAssertEqualObjects([request.payload asDictionary], expectedPayload);
}

- (void)testThatItDoesNotSetVideoWhenCallIsAlreadyOngoingAndVideoIsNotSending
{
    // given
    ZMConversation *conversation = self.syncSelfToUser1Conversation;
    [[conversation mutableOrderedSetValueForKey:ZMConversationCallParticipantsKey] addObject:self.syncOtherUser1];
    conversation.isVideoCall = YES;
    conversation.callDeviceIsActive = YES;
    
    NSDictionary *expectedPayload = @{@"self" : @{
                                              @"state" : @"joined",
                                              @"suspended" : @(NO),
                                              @"videod" : @(NO)
                                              },
                                      @"cause": @"requested"
                                      };
    
    // when
    [[[self.gsmCallHandler expect] andReturnValue:OCMOCK_VALUE(NO)] isInterruptedCallConversation:conversation];
    ZMTransportRequest *request = [self.sut requestForUpdatingObject:conversation forKeys:self.keys].transportRequest;
    
    // then
    XCTAssertEqualObjects([request.payload asDictionary], expectedPayload);
}

- (void)testThatItSetsVideoWhenCallIsAlreadyOngoingAndVideoIsSending
{
    // given
    ZMConversation *conversation = self.syncSelfToUser1Conversation;
    [[conversation mutableOrderedSetValueForKey:ZMConversationCallParticipantsKey] addObject:self.syncOtherUser1];
    conversation.isVideoCall = YES;
    conversation.isSendingVideo = YES;
    conversation.callDeviceIsActive = YES;
    
    NSDictionary *expectedPayload = @{@"self" : @{
                                              @"state" : @"joined",
                                              @"suspended" : @(NO),
                                              @"videod" : @(YES)
                                              },
                                      @"cause": @"requested"
                                      };
    
    // when
    [[[self.gsmCallHandler expect] andReturnValue:OCMOCK_VALUE(NO)] isInterruptedCallConversation:conversation];
    ZMTransportRequest *request = [self.sut requestForUpdatingObject:conversation forKeys:self.keys].transportRequest;
    
    // then
    XCTAssertEqualObjects([request.payload asDictionary], expectedPayload);
}

- (void)testThatItDoesNotSetIsVideoWhenIsVideoCallIsFalse
{
    // given
    ZMConversation *conversation = self.syncSelfToUser1Conversation;
    conversation.isVideoCall = NO;
    conversation.callDeviceIsActive = YES;
    
    NSDictionary *expectedPayload = @{@"self" : @{
                                              @"state" : @"joined",
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

- (void)testThatItDoesNotSetIsVideoWhenCallDeviceIsNotActive
{
    // given
    ZMConversation *conversation = self.syncSelfToUser1Conversation;
    conversation.isVideoCall = YES;
    conversation.callDeviceIsActive = NO;
    
    NSDictionary *expectedPayload = @{@"self" : @{
                                              @"state" : @"idle",
                                              },
                                      @"cause": @"requested"};
    
    // when
    [[[self.gsmCallHandler expect] andReturnValue:OCMOCK_VALUE(NO)] isInterruptedCallConversation:conversation];
    ZMTransportRequest *request = [self.sut requestForUpdatingObject:conversation forKeys:self.keys].transportRequest;
    
    // then
    XCTAssertEqualObjects([request.payload asDictionary], expectedPayload);
}

- (ZMUpdateEvent *)eventForOtherSendsVideo:(BOOL)otherSendsVideo selfSendsVideo:(BOOL)selfSendsVideo inConversation:(ZMConversation *)conversation
{
    NSDictionary *payload = @{
                              @"id" : NSUUID.createUUID.transportString,
                              @"payload" : @[
                                      @{
                                          @"type": @"call.state",
                                          @"conversation": conversation.remoteIdentifier.transportString,
                                          @"self" : @{
                                                  @"state" : @"idle",
                                                  },
                                          @"participants": @{
                                                  self.syncOtherUser1.remoteIdentifier.transportString : @{@"state": @"joined", @"videod": otherSendsVideo ? @YES : @NO},
                                                  self.syncSelfUser.remoteIdentifier.transportString: @{@"state": @"joined", @"videod": selfSendsVideo ? @YES : @NO}
                                                  },
                                          }
                                      ]
                              };
    
    ZMUpdateEvent *event = [ZMUpdateEvent eventsArrayFromPushChannelData:payload].firstObject;
    XCTAssertNotNil(event);
    return event;
}

- (void)testThatItSetsIsVideoCallWhenOneParticipantsHasVideodSetToYES
{
    // given
    ZMConversation *conversation = self.syncSelfToUser1Conversation;
    
    // when
    ZMUpdateEvent *event = [self eventForOtherSendsVideo:YES selfSendsVideo:NO inConversation:conversation];
    [self.sut processEvents:@[event] liveEvents:YES prefetchResult:nil];
    
    // then
    XCTAssertTrue(conversation.isVideoCall);
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatItAddsParticipantsWithActiveuserToOtherActiveVideoCallParticipants
{
    // given
    ZMConversation *conversation = self.syncSelfToUser1Conversation;
    conversation.isFlowActive = YES;
    XCTAssertFalse([conversation.otherActiveVideoCallParticipants containsObject:self.syncOtherUser1]);

    // when
    ZMUpdateEvent *event = [self eventForOtherSendsVideo:YES selfSendsVideo:NO inConversation:conversation];
    [self.sut processEvents:@[event] liveEvents:YES prefetchResult:nil];
    
    // then
    XCTAssertEqual(conversation.otherActiveVideoCallParticipants.count, 1u);
    XCTAssertTrue([conversation.otherActiveVideoCallParticipants containsObject:self.syncOtherUser1]);
}

- (void)testThatItRemovesParticipantsWithActiveuserToOtherActiveVideoCallParticipants
{
    // given
    ZMConversation *conversation = self.syncSelfToUser1Conversation;
    conversation.isFlowActive = YES;
    conversation.isVideoCall = YES;
    [conversation addActiveVideoCallParticipant:self.syncOtherUser1];
    XCTAssertTrue([conversation.otherActiveVideoCallParticipants containsObject:self.syncOtherUser1]);

    // when
    ZMUpdateEvent *event = [self eventForOtherSendsVideo:NO selfSendsVideo:NO inConversation:conversation];
    [self.sut processEvents:@[event] liveEvents:YES prefetchResult:nil];

    // then
    XCTAssertFalse([conversation.otherActiveVideoCallParticipants containsObject:self.syncOtherUser1]);
}

- (void)testThatItResetsIsSendingVideoAndCallDeviceIsActiveForTimeOutErrors_JoinRequest_BothKeysIncluded
{
    // given
    ZMConversation *conversation = self.syncSelfToUser1Conversation;
    conversation.callDeviceIsActive = YES;
    [conversation syncLocalModificationsOfIsSendingVideo];
    XCTAssertTrue(conversation.hasLocalModificationsForIsSendingVideo);
    
    // expect
    [self.flowTranscoder releaseFlowsForConversation:conversation];
    
    // when
    [self.sut requestExpiredForObject:conversation forKeys:self.keys];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertFalse(conversation.hasLocalModificationsForIsSendingVideo);
    XCTAssertFalse(conversation.callDeviceIsActive);
}

- (void)testThatItResetsIsSendingVideoButNotCallDeviceIsActiveForTimeOutErrors_JoinRequest_OnlyIsSendingVideoIncluded
{
    // given
    ZMConversation *conversation = self.syncSelfToUser1Conversation;
    conversation.callDeviceIsActive = YES;
    [conversation syncLocalModificationsOfIsSendingVideo];
    XCTAssertTrue(conversation.hasLocalModificationsForIsSendingVideo);
    
    // expect
    [self.flowTranscoder releaseFlowsForConversation:conversation];
    
    // when
    [self.sut requestExpiredForObject:conversation forKeys:[NSSet setWithObject:ZMConversationIsSendingVideoKey]];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertFalse(conversation.hasLocalModificationsForIsSendingVideo);
    XCTAssertTrue(conversation.callDeviceIsActive);
}

- (void)testThatItDoesNotResetCallDeviceIsActiveWhenTheKeyWasNotIncluded_PermanentError
{
    // given
    ZMConversation *conversation = self.syncSelfToUser1Conversation;
    [conversation syncLocalModificationsOfIsSendingVideo];
    XCTAssertTrue(conversation.hasLocalModificationsForIsSendingVideo);
    
    ZMUpstreamRequest *request = [self.sut requestForUpdatingObject:conversation forKeys:[NSSet setWithObject:ZMConversationIsSendingVideoKey]];
    ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:@{} HTTPStatus:0 transportSessionError:[NSError errorWithDomain:ZMTransportSessionErrorDomain code:500 userInfo:nil]];
    XCTAssertNotNil(request);
    
    // expect
    [self.flowTranscoder releaseFlowsForConversation:conversation];
    
    // when
    [request.transportRequest completeWithResponse:response];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertFalse(conversation.hasLocalModificationsForIsSendingVideo);
}



@end
