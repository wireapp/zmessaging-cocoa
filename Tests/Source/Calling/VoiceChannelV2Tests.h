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


#import "MessagingTest.h"


@interface VoiceChannelV2Tests : MessagingTest <CallingInitialisationObserver>

@property (nonatomic) ZMConversation *conversation;
@property (nonatomic) ZMConversation *otherConversation;
@property (nonatomic) ZMConversation *groupConversation;

@property (nonatomic) ZMUser *selfUser;
@property (nonatomic) ZMUser *otherUser;

@property (nonatomic) ZMConversation *syncGroupConversation;
@property (nonatomic) ZMConversation *syncOneOnOneConversation;

@property (nonatomic) ZMUser *syncUser1;
@property (nonatomic) ZMUser *syncUser2;
@property (nonatomic) ZMUser *syncUser3;
@property (nonatomic) ZMUser *syncSelfUser;


@property (nonatomic) NSMutableArray *receivedErrors;

@end
