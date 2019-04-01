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

@class OperationStatus;
@class ManagedObjectContextChangeObserver;
@class LocalNotificationDispatcher;
@class AccountStatus;
@class ApplicationStatusDirectory;
@class UserExpirationObserver;
@class AVSMediaManager;

#import "ZMUserSession.h"

NS_ASSUME_NONNULL_BEGIN

@interface ZMUserSession ()

// Status flags.

@property (nonatomic) BOOL networkIsOnline;
@property (nonatomic) BOOL isPerformingSync;
@property (nonatomic) BOOL pushChannelIsOpen;
@property (nonatomic) BOOL didNotifyThirdPartyServices;

@end

@interface ZMUserSession (Private)

@property (nonatomic, readonly) ZMTransportSession *transportSession;
@property (nonatomic, readonly) NSManagedObjectContext *searchManagedObjectContext;
@property (nonatomic, readonly) OperationStatus *operationStatus;
@property (nonatomic, readonly) AccountStatus *accountStatus;
@property (nonatomic, readonly) ApplicationStatusDirectory *applicationStatusDirectory;
@property (nonatomic, readonly) NotificationDispatcher *notificationDispatcher;
@property (nonatomic, readonly) LocalNotificationDispatcher *localNotificationDispatcher;
@property (nonatomic, nullable) ManagedObjectContextChangeObserver *messageReplyObserver;
@property (nonatomic, nullable) ManagedObjectContextChangeObserver *likeMesssageObserver;
@property (nonatomic, nonnull)  UserExpirationObserver *userExpirationObserver;
@property (nonatomic, readonly) AVSMediaManager *mediaManager;

- (void)tearDown;

@end

NS_ASSUME_NONNULL_END
