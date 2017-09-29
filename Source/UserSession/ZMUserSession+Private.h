//
// Wire
// Copyright (C) 2017 Wire Swiss GmbH
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


@import WireUtilities;
@import WireTransport;
@import WireDataModel;

@class ZMStoredLocalNotification;

#import "ZMUserSession.h"

NS_ASSUME_NONNULL_BEGIN

@interface ZMUserSession ()

// Status flags.

@property (nonatomic) BOOL didStartInitialSync;
@property (nonatomic) BOOL networkIsOnline;
@property (nonatomic) BOOL isPerformingSync;
@property (nonatomic) BOOL pushChannelIsOpen;
@property (nonatomic) BOOL didNotifyThirdPartyServices;

@end

@interface ZMUserSession (Private)

@property (nonatomic, readonly) ZMTransportSession *transportSession;
@property (nonatomic, readonly) NSManagedObjectContext *searchManagedObjectContext;

- (void)tearDown;

// Notifications-related

// Notification that was received during the time when the sync engine is not ready to process it.
@property (nonatomic, nullable) ZMStoredLocalNotification *pendingLocalNotification;

/// When starting the app due to a push notification action, we store the notification information and wait until sync completed before processing pending local notifications.
/// This is important for possibly outdated calling notifications for which we need to fetch the call state before joining the call.
- (void)processPendingNotificationActions;

@end


@interface ZMUserSession (NotificationProcessing)

- (void)ignoreCallForNotification:(UILocalNotification *)notification withCompletionHandler:(void (^)())completionHandler;
- (void)replyToNotification:(UILocalNotification *)notification withReply:(NSString*)reply completionHandler:(void (^)())completionHandler;
- (void)muteConversationForNotification:(UILocalNotification *)notification withCompletionHandler:(void (^)())completionHandler;
- (void)likeMessageForNotification:(UILocalNotification *)note withCompletionHandler:(void (^)(void))completionHandler;
- (void)openConversation:(nullable ZMConversation *)conversation atMessage:(nullable ZMMessage *)message;

@end

NS_ASSUME_NONNULL_END
