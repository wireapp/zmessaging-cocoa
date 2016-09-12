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

#import "ZMPushRegistrant.h"
#import "ZMContextChangeTracker.h"
#import "ZMObjectSyncStrategy.h"

@class ZMUpdateEvent;
@class ZMConversation;
@class ZMBadge;
@class ZMLocalNotificationForEvent;
@class ZMLocalNotificationForExpiredMessage;
@class ZMMessage;
@class ZMLocalNotificationSet;
@protocol ZMApplication;

extern NSString * _Null_unspecified const ZMConversationCancelNotificationForIncomingCallNotificationName;
extern NSString * _Null_unspecified const ZMShouldHideNotificationContentKey;

@interface ZMLocalNotificationDispatcher : NSObject

@property (nonatomic, readonly, nonnull) ZMLocalNotificationSet *eventsNotifications;
@property (nonatomic, readonly, nonnull) ZMLocalNotificationSet *messageNotifications;
@property (nonatomic, readonly, nonnull) id<ZMApplication> sharedApplication;
@property (nonatomic, readonly, nonnull) id sharedApplicationForSwift;

- (nullable instancetype)initWithManagedObjectContext:(nonnull NSManagedObjectContext *)moc sharedApplication:(nonnull id<ZMApplication>)sharedApplication;

- (void)tearDown;

// Can be used for cancelling all conversations if need
// Notifications for a specific conversation are otherwise deleted automatically when the message window changes and
// ZMConversationDidChangeVisibleWindowNotification is called
- (void)cancelAllNotifications;
- (void)cancelNotificationForConversation:(nonnull ZMConversation *)conversation;

@end



@interface ZMLocalNotificationDispatcher (EventProcessing) <ZMEventConsumer>
@end



@interface ZMLocalNotificationDispatcher (FailedMessages)

- (void)didFailToSentMessage:(nonnull ZMMessage *)message;
- (void)didFailToSendMessageInConversation:(nonnull ZMConversation *)conversation;

@end


