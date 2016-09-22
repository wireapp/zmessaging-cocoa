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
@import CoreData;
@import WireRequestStrategy;

@class ZMEventIDRange;
@class ZMConversation;
@class ZMUpdateEvent;
@class ZMEventID;

NS_ASSUME_NONNULL_BEGIN

/// Keeps track of which conversations have missing messages, based on the message event ID. It will take into account
/// whitelisting (only conversations that have been opened will be marked as incomplete) and visible message window (only
/// conversation that have missing messages inside the visible window will be marked as incomplete)
@interface ZMIncompleteConversationsCache : NSObject <ZMContextChangeTracker>

/// If @c ignoreVisibleWindowAndWhitelist is true, it will keeps track of conversations with any message gap, even if they are not whitelisted.
/// If false, will only keep track of conversation with gaps in the current visible window that are whitelisted.
- (instancetype)initWithContext:(NSManagedObjectContext *)context;

/// Checks which are the top conversations and adds them to the whitelist
- (void)whitelistTopConversationsIfIncomplete;

/// List of conversations that are currently incomplete
@property (nonatomic, readonly) NSOrderedSet *incompleteNonWhitelistedConversations;
@property (nonatomic, readonly) NSOrderedSet *incompleteWhitelistedConversations;

/// Returns the first gap that should be fetched for the given conversation
- (nullable ZMEventIDRange *)gapForConversation:(ZMConversation *)conversation;

- (void)tearDown;

@end

NS_ASSUME_NONNULL_END
