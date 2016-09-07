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


#import <Foundation/Foundation.h>
@import WireRequestStrategy;

@class ZMMessage;
@class ZMLocalNotificationDispatcher;

/// Keeps track of messages and sets them to expired when their time has come
@interface ZMMessageExpirationTimer : NSObject <ZMContextChangeTracker>

@property (nonatomic, readonly) BOOL hasMessageTimersRunning;
@property (nonatomic, readonly) NSUInteger runningTimersCount;

- (instancetype)initWithManagedObjectContext:(NSManagedObjectContext *)moc entityName:(NSString *)entityName localNotificationDispatcher:(ZMLocalNotificationDispatcher *)notificationDispatcher;
- (instancetype)initWithManagedObjectContext:(NSManagedObjectContext *)moc entityName:(NSString *)entityName localNotificationDispatcher:(ZMLocalNotificationDispatcher *)notificationDispatcher filter:(NSPredicate *)filter;

- (void)stopTimerForMessage:(ZMMessage *)message;

- (void)tearDown;

@end
