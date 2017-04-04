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


#import "MockConversationWindowObserver.h"

#import <WireSyncEngine/WireSyncEngine-Swift.h>

static NSString * const Placeholder = @"Placeholder";

@interface MockConversationWindowObserver ()

@property (nonatomic, readonly) NSMutableOrderedSet *mutableMessages;
@property (nonatomic, readonly) id opaqueToken;
@end


@implementation MockConversationWindowObserver

- (instancetype)initWithConversation:(ZMConversation *)conversation size:(NSUInteger)size
{
    self = [super init];
    if(self) {
        _window = [conversation conversationWindowWithSize:size];
        _mutableMessages = [self.window.messages mutableCopy];

        _opaqueToken = [self.window addConversationWindowObserver:self];
    }
    return self;
}

- (void)dealloc
{
    [self.window removeConversationWindowObserverToken:self.opaqueToken];
    _opaqueToken = nil;
}

- (void)conversationWindowDidChange:(MessageWindowChangeInfo *)note
{
    [note.deletedIndexes enumerateIndexesWithOptions:NSEnumerationReverse usingBlock:^(NSUInteger idx, BOOL *stop ZM_UNUSED) {
        [self.mutableMessages removeObjectAtIndex:idx];
    }];
    
    [note.insertedIndexes enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop ZM_UNUSED) {
        [self.mutableMessages insertObject:Placeholder atIndex:idx];
    }];
    
    [note.movedIndexPairs enumerateObjectsUsingBlock:^(ZMMovedIndex *moved, NSUInteger idx ZM_UNUSED, BOOL *stop ZM_UNUSED) {
        [self.mutableMessages moveObjectsAtIndexes:[NSIndexSet indexSetWithIndex:moved.from] toIndex:moved.to];
    }];
    
    for(NSUInteger i = 0; i < self.mutableMessages.count; ++i) {
        if(self.mutableMessages[i] == Placeholder) {
            [self.mutableMessages replaceObjectAtIndex:i withObject:self.window.messages[i]];
        }
    }
}

- (NSOrderedSet *)computedMessages
{
    return [self.mutableMessages copy];
}

@end
