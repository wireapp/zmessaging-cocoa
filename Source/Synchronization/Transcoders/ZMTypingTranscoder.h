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

@import WireRequestStrategy;


@class ZMTyping;
@class ZMConversation;


extern NSString * const ZMTypingNotificationName;

@interface ZMTypingTranscoder : ZMObjectSyncStrategy <ZMObjectStrategy>

- (instancetype)initWithManagedObjectContext:(NSManagedObjectContext *)moc
                        userInterfaceContext:(NSManagedObjectContext *)uiMoc;

- (instancetype)initWithManagedObjectContext:(NSManagedObjectContext *)moc
                        userInterfaceContext:(NSManagedObjectContext *)uiMoc
                                      typing:(ZMTyping *)typing;
@end


@interface ZMTypingTranscoder (ZMConversation)

/// (Asynchronously) sends an @c NSNotification to the @c ZMTypingTranscoder
+ (void)notifyTranscoderThatUserIsTyping:(BOOL)isTyping inConversation:(ZMConversation *)conversation;

/// (Asynchronously) clears the typing state by sends an @c NSNotification to the @c ZMTypingTranscoder
/// This is used when a new message is being sent. A subsequent call to +notifyTranscoderThatUserIsTyping:inConversation:
/// will always trigger a request to the backend.
+ (void)clearTranscoderStateForTypingInConversation:(ZMConversation *)conversation;

@end
