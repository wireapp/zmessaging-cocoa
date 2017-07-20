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


@import WireSystem;
@import WireUtilities;
@import WireTransport;
@import WireDataModel;

#import "ZMLocalNotification.h"

#import "ZMLocalNotificationLocalization.h"
#import "UILocalNotification+StringProcessing.h"
#import "ZMUserSession+UserNotificationCategories.h"
#import "WireSyncEngine/WireSyncEngine-Swift.h"
#import "UILocalNotification+UserInfo.h"


NSString * const ZMLocalNotificationConversationObjectURLKey = @"conversationObjectURLString";
NSString * const ZMLocalNotificationUserInfoSenderKey = @"senderUUID";
NSString * const ZMLocalNotificationUserInfoNonceKey = @"nonce";

static NSString * const FailedMessageInGroupConversationText = @"failed.message.group";
static NSString * const FailedMessageInOneOnOneConversationText = @"failed.message.oneonone";

NSString * const ZMPushStringDefault = @"default";
NSString * const ZMPushStringEphemeral = @"ephemeral";


// These are the "base" keys for messages. We append to these for the specific case.
//
//
//
// 1 user, 1 conversation, 1 string
// %1$@    %2$@            %3$@
NSString *const ZMPushStringMessageAdd = @"add.message"; // "[senderName] in [conversationName] - [messageText]"
NSString *const ZMPushStringImageAdd = @"add.image"; // "[senderName] shared a picture in [conversationName]"
NSString *const ZMPushStringVideoAdd = @"add.video"; // "[senderName] shared a video in [conversationName]"
NSString *const ZMPushStringAudioAdd = @"add.audio"; // "[senderName] shared an audio message in [conversationName]"
NSString *const ZMPushStringFileAdd = @"add.file"; // "[senderName] shared a file in [conversationName]"
NSString *const ZMPushStringLocationAdd = @"add.location"; // "[senderName] shared a location in [conversationName]"
NSString *const ZMPushStringUnknownAdd = @"add.unknown"; // "[senderName] sent a message in [conversationName]"
NSString *const ZMPushStringMessageAddMany = @"add.message.many"; // "x new messages in [conversationName] / from [senderName]"

/// 2 users, 1 conversation
NSString *const ZMPushStringMemberJoin = @"member.join";
// "[senderName] added you / [userName] to [conversationName]"
NSString *const ZMPushStringMemberLeave = @"member.leave";
// "[senderName] removed you / [userName] from [conversationName]"


NSString *const ZMPushStringMemberJoinMany = @"member.join.many";
// "[senderName] added people to [conversationName]"
NSString *const ZMPushStringMemberLeaveMany = @"member.leave.many";
// "[senderName] removed people from [conversationName]"

NSString *const ZMPushStringKnock = @"knock"; // "[senderName] pinged you x times in [conversationName]" // "x pings in
NSString *const ZMPushStringReaction = @"reaction"; // "[senderName] [emoji] your message in [conversationName]"

NSString *const ZMPushStringVideoCallStarts = @"call.started.video"; // "[senderName] wants to talk"
NSString *const ZMPushStringCallStarts = @"call.started"; // "[senderName] wants to talk"
NSString *const ZMPushStringCallMissed = @"call.missed"; // "[senderName] called you x times"
NSString *const ZMPushStringCallMissedMany = @"call.missed.many"; // "You have x missed calls in a conversation"

NSString *const ZMPushStringConnectionRequest = @"connection.request"; // "[senderName] wants to connect: [messageText]"
NSString *const ZMPushStringConnectionAccepted = @"connection.accepted"; // "[senderName] accepted your connection request"

NSString *const ZMPushStringConversationCreate = @"conversation.create";
NSString *const ZMPushStringNewConnection = @"new_user";

#pragma mark - ZMLocalNotification


@interface ZMLocalNotification ()

@end


@implementation ZMLocalNotification


- (instancetype)initWithConversationID:(NSUUID *)conversationID
{
    self = [super init];
    if (self) {
        _conversationID = conversationID;
    }
    return self;
}

- (NSArray<UILocalNotification *> *)uiNotifications
{
    return  @[];
}

@end



#pragma mark - ZMLocalNotificationForExpiredMessage


@implementation ZMLocalNotificationForExpiredMessage



- (instancetype)initWithExpiredMessage:(ZMMessage *)message
{
    self = [super initWithConversationID:message.conversation.remoteIdentifier];
    if(self) {
        _message = message;
        UILocalNotification *note = [[UILocalNotification alloc] init];
        [self createBodyForConversation:message.conversation notification:note];
        _uiNotification = note;
    }
    return self;
}

- (NSArray<UILocalNotification *> *)uiNotifications
{
    return @[self.uiNotification];
}

- (instancetype)initWithConversation:(ZMConversation *)conversation
{
    self = [super initWithConversationID:conversation.remoteIdentifier];
    if(self) {
        UILocalNotification *note = [[UILocalNotification alloc] init];
        [self createBodyForConversation:conversation notification:note];
        _uiNotification = note;
    }
    return self;
}

- (void)createBodyForConversation:(ZMConversation *)conversation notification:(UILocalNotification *)notification
{
    if(conversation.conversationType == ZMConversationTypeGroup) {
        notification.alertBody = [FailedMessageInGroupConversationText localizedStringWithConversation:conversation count:nil];
    }
    else {
        notification.alertBody = [FailedMessageInOneOnOneConversationText localizedStringWithUser:conversation.connectedUser count:nil];
    }
    [notification setupUserInfo:conversation forEvent:nil];
}

@end


