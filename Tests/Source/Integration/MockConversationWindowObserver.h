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

@import WireSyncEngine;

#import "ZMConversationMessageWindow.h"

@interface MockConversationWindowObserver : NSObject <ZMConversationMessageWindowObserver>

@property (nonatomic, readonly) NSOrderedSet *computedMessages; //< this is the list of messages according to the inial list + applying all notifications so far
@property (nonatomic, readonly) ZMConversationMessageWindow *window;

- (instancetype)initWithConversation:(ZMConversation *)conversation size:(NSUInteger)size;

@end
