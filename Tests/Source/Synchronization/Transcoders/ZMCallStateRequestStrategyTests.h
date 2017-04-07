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
@import WireDataModel;

#import "MessagingTest.h"
#import "ObjectTranscoderTests.h"
#import "ZMCallStateRequestStrategy.h"
#import "ZMCallFlowRequestStrategy.h"
#import "ZMObjectStrategyDirectory.h"
#import "ZMUserSession+Internal.h"
#import "ZMOperationLoop.h"
#import "ZMGSMCallHandler.h"

@interface ZMCallStateRequestStrategyTests : ObjectTranscoderTests

@property (nonatomic) ZMCallStateRequestStrategy<ZMDownstreamTranscoder, ZMUpstreamTranscoder> *sut;
@property (nonatomic) id callFlowRequestStrategy;
@property (nonatomic) ZMConversation *syncSelfToUser1Conversation;
@property (nonatomic) ZMConversation *syncSelfToUser2Conversation;
@property (nonatomic) ZMConversation *syncGroupConversation;
@property (nonatomic) ZMUser *syncSelfUser;
@property (nonatomic) ZMUser *syncOtherUser1;
@property (nonatomic) ZMUser *syncOtherUser2;
@property (nonatomic) NSSet *keys;
@property (nonatomic) id gsmCallHandler;

- (void)tearDownVoiceChannelForSyncConversation:(ZMConversation *)syncConversation;

@end
