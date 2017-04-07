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


@import UIKit;
@import WireTransport;
@import WireDataModel;

static NSString * const ConversationIDStringKey = @"conversationIDString";
static NSString * const MessageNonceIDStringKey = @"messageNonceString";
static NSString * const SenderIDStringKey = @"senderIDString";
static NSString * const EventTimeKey = @"eventTime";

@implementation UILocalNotification (UserInfo)

- (NSUUID *)nsuuidForUserInfoKey:(NSString *)key
{
    NSString *uuidString = self.userInfo[key];
    return [NSUUID uuidWithTransportString:uuidString];
}

- (NSUUID *)zm_conversationRemoteID;
{
    return [self nsuuidForUserInfoKey:ConversationIDStringKey];
}

- (NSUUID *)zm_messageNonce;
{
    return [self nsuuidForUserInfoKey:MessageNonceIDStringKey];
}

- (NSUUID *)zm_senderUUID;
{
    return [self nsuuidForUserInfoKey:SenderIDStringKey];
}

- (NSDate *)zm_eventTime;
{
    return self.userInfo[EventTimeKey];
}

- (nullable ZMConversation *)conversationInManagedObjectContext:(nonnull NSManagedObjectContext *)MOC;
{
    if (self.zm_conversationRemoteID == nil) {
        return nil;
    }
    ZMConversation *conversation = [ZMConversation conversationWithRemoteID:self.zm_conversationRemoteID createIfNeeded:NO inContext:MOC];
    return conversation;
}

- (nullable ZMMessage *)messageInConversation:(ZMConversation *)conversation inManagedObjectContext:(nonnull NSManagedObjectContext *)MOC;
{
    if (conversation == nil || self.zm_messageNonce == nil) {
        return nil;
    }

    ZMMessage *message = [ZMMessage fetchMessageWithNonce:self.zm_messageNonce forConversation:conversation inManagedObjectContext:MOC];
    return message;
}

- (void)setupUserInfo:(ZMConversation *)conversation sender:(ZMUser *)sender
{
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    
    NSString *conversationIDString = conversation.remoteIdentifier.transportString;
    if (conversationIDString != nil) {
        info[ConversationIDStringKey] = conversationIDString;
    }
    
    NSString *senderUUIDString = sender.remoteIdentifier.transportString;
    if (senderUUIDString != nil) {
        info[SenderIDStringKey] = senderUUIDString;
    }
    
    self.userInfo = [info copy];
}

- (void)setupUserInfo:(ZMConversation *)conversation forEvent:(ZMUpdateEvent*)event;
{
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    NSString *conversationIDString = conversation.remoteIdentifier.transportString;
    if (conversationIDString != nil) {
        info[ConversationIDStringKey] = conversationIDString;
    }
    if (event == nil) {
        self.userInfo = [info copy];
        return;
    }
    
    NSString *senderUUIDString = event.senderUUID.transportString;
    NSString *mesageNonceString = event.messageNonce.transportString;
    NSDate *eventTime = event.timeStamp;
    if (senderUUIDString != nil) {
        info[SenderIDStringKey] = senderUUIDString;
    }
    if (mesageNonceString != nil) {
        info[MessageNonceIDStringKey] = mesageNonceString;
    }
    if (eventTime != nil) {
        info[EventTimeKey] = eventTime;
    }
    self.userInfo = [info copy];
}

- (void)setupUserInfo:(ZMMessage *)message
{
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    NSString *conversationIDString = message.conversation.remoteIdentifier.transportString;
    if (conversationIDString != nil) {
        info[ConversationIDStringKey] = conversationIDString;
    }
    
    NSString *senderUUIDString = message.sender.remoteIdentifier.transportString;
    NSString *mesageNonceString = message.nonce.transportString;
    NSDate *eventTime = message.serverTimestamp;
    if (senderUUIDString != nil) {
        info[SenderIDStringKey] = senderUUIDString;
    }
    if (mesageNonceString != nil) {
        info[MessageNonceIDStringKey] = mesageNonceString;
    }
    if (eventTime != nil) {
        info[EventTimeKey] = eventTime;
    }
    self.userInfo = [info copy];
}

@end
