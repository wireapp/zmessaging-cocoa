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


@import Foundation;
@class ZMUser;
@class ZMConversation;



@interface NSString (ZMLocalNotificationLocalization)

- (NSString *)localizedStringWithUser:(ZMUser *)user conversation:(ZMConversation *)conversation otherUser:(ZMUser *)otherUser;

- (NSString *)localizedStringWithUser:(ZMUser *)user conversation:(ZMConversation *)conversation count:(NSNumber *)count;


- (NSString *)localizedStringWithUser:(ZMUser *)user conversation:(ZMConversation *)conversation text:(NSString *)text;
- (NSString *)localizedStringWithUser:(ZMUser *)user conversation:(ZMConversation *)conversation;


- (NSString *)localizedStringWithUser:(ZMUser *)user count:(NSNumber *)count text:(NSString *)text;
- (NSString *)localizedStringWithUser:(ZMUser *)user count:(NSNumber *)count;
- (NSString *)localizedStringWithUserName:(NSString *)userName;

- (NSString *)localizedStringWithConversation:(ZMConversation *)conversation count:(NSNumber *)count text:(NSString *)text;
- (NSString *)localizedStringWithConversation:(ZMConversation *)conversation count:(NSNumber *)count;

- (NSString *)localizedStringWithUser:(ZMUser *)user conversation:(ZMConversation *)conversation emoji:(NSString *)emoji;

- (NSString *)localizedStringForPushNotification;

- (NSString *)localizedStringWithConversationName:(NSString *)conversationName teamName:(NSString *)teamName;
- (NSString *)localizedCallKitStringWithUser:(ZMUser *)user conversation:(ZMConversation *)conversation;

@end
