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


#import "ZMMessageTranscoder.h"

@class ZMMessageExpirationTimer;
@class ZMConversation;

@interface ZMMessageTranscoder (Internal) <ZMUpstreamTranscoder>

+ (instancetype)systemMessageTranscoderWithManagedObjectContext:(NSManagedObjectContext *)moc
                                    localNotificationDispatcher:(ZMLocalNotificationDispatcher *)dispatcher
                                         messageExpirationTimer:(ZMMessageExpirationTimer *)expirationTimer;

- (instancetype)initWithManagedObjectContext:(NSManagedObjectContext *)moc
                                  entityName:(NSString *)entityName
                 localNotificationDispatcher:(ZMLocalNotificationDispatcher *)dispatcher;

- (instancetype)initWithManagedObjectContext:(NSManagedObjectContext *)moc
                  upstreamInsertedObjectSync:(ZMUpstreamInsertedObjectSync *)upstreamObjectSync
                 localNotificationDispatcher:(ZMLocalNotificationDispatcher *)dispatcher
                      messageExpirationTimer:(ZMMessageExpirationTimer *)expirationTimer;

/// Generate messages from the given events and return those messages. Subclasses should provide their implementation of this method
- (NSArray<ZMMessage *> *)createMessagesFromEvents:(NSArray<ZMUpdateEvent *>*)events
                                    prefetchResult:(ZMFetchRequestBatchResult *)prefetchResult;

@property (nonatomic, readonly) ZMLocalNotificationDispatcher *localNotificationDispatcher;

@end



@interface ZMSystemMessageTranscoder : ZMMessageTranscoder <ZMObjectStrategy>

@end

