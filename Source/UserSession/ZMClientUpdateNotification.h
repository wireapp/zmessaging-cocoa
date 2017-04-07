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


#import <WireDataModel/ZMNotifications.h>

typedef NS_ENUM (NSInteger, ZMClientUpdateNotificationType) {
    ZMClientUpdateNotificationTypeFetchCompleted,
    ZMClientUpdateNotificationTypeFetchFailed,
    ZMClientUpdateNotificationTypeDeletionCompleted,
    ZMClientUpdateNotificationTypeDeletionFailed,
};

@protocol ZMClientUpdateObserverToken;

@interface ZMClientUpdateNotification : ZMNotification

@property (nonatomic) NSError *error;
@property (nonatomic) NSArray<NSManagedObjectID *> *clientObjectIDs;
@property (nonatomic) ZMClientUpdateNotificationType type;

+ (id<ZMClientUpdateObserverToken>)addObserverWithBlock:(void (^)(ZMClientUpdateNotification *))block;
+ (void)removeObserver:(id<ZMClientUpdateObserverToken>)token;

@end
