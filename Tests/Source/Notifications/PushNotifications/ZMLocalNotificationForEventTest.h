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
@import ZMProtos;
@import ZMCDataModel;

#import "MessagingTest.h"
#import "ZMLocalNotification+Internal.h"
#import "ZMLocalNotificationLocalization.h"
#import "MessagingTest+EventFactory.h"
#import "ZMUserSession+UserNotificationCategories.h"




@interface ZMLocalNotificationForEventTest : MessagingTest
@property (nonatomic) ZMUser *sender;
@property (nonatomic) ZMConversation *oneOnOneConversation;
@property (nonatomic) ZMConversation *groupConversation;
@property (nonatomic) ZMConversation *groupConversationWithoutName;
@property (nonatomic) ZMUser *selfUser;
@property (nonatomic) ZMUser *otherUser;
@property (nonatomic) ZMUser *otherUser2;

@end
