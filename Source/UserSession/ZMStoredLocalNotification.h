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

@class ZMConversation;
@class ZMMessage;

@interface ZMStoredLocalNotification : NSObject

@property (nonatomic, readonly, nullable) ZMConversation *conversation;
@property (nonatomic, readonly, nullable) ZMMessage *message;
@property (nonatomic, readonly, nonnull) NSUUID *senderUUID;

@property (nonatomic, readonly, nullable) NSString *category;
@property (nonatomic, readonly, nullable) NSString *actionIdentifier;
@property (nonatomic, readonly, nullable) NSString *textInput;

- (instancetype _Nonnull)initWithNotification:(UILocalNotification * _Nonnull)notification
                managedObjectContext:(NSManagedObjectContext * _Nonnull)managedObjectContext
                    actionIdentifier:(NSString * _Nullable)identifier
                           textInput:(NSString * _Nullable)textInput;


@end

