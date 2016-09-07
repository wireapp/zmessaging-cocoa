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


@import ZMTransport;
@import ZMCDataModel;

#import "ZMIncompleteConversationsCache.h"

static const NSUInteger ConversationPriorityCount = 5;

@interface ZMIncompleteConversationsCache ()

@property (nonatomic) NSMutableOrderedSet *conversationsToFetch;
@property (nonatomic) NSMutableSet *whitelistedConversations;
@property (nonatomic) NSManagedObjectContext *context;
@property (nonatomic) NSMutableDictionary *conversationWindows;
@property (nonatomic) NSEntityDescription *conversationEntity;

@property (nonatomic) BOOL tornDown;

@end



@implementation ZMIncompleteConversationsCache

- (instancetype)init
{
    NSAssert(false, @"Disabled init for ZMIncompleteConversationsCache");
    return nil;
}

- (void)tearDown
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    self.tornDown = YES;
}

- (instancetype)initWithContext:(NSManagedObjectContext *)context
{
    Require(context != nil);
    self = [super init];
    if(self) {
        self.conversationsToFetch = [NSMutableOrderedSet orderedSet];
        self.whitelistedConversations = [NSMutableSet set];
        self.context = context;
        self.conversationWindows = [NSMutableDictionary dictionary];
        self.conversationEntity = self.context.persistentStoreCoordinator.managedObjectModel.entitiesByName[ZMConversation.entityName];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(windowSizeChanged:) name:ZMConversationDidChangeVisibleWindowNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(fetchConversation:) name:ZMConversationRequestToLoadConversationEventsNotification object:nil];
    }
    return self;
}

#if DEBUG
- (void)dealloc
{
    RequireString(self.tornDown, "Did not call -tearDown on %p", (__bridge void *) self);
}
#endif

- (void)addTrackedObjects:(NSSet *)objects;
{
    for (ZMConversation *conversation in objects) {
        ZMEventIDRange *gap = [conversation lastEventIDGapForVisibleWindow:nil];
        if (gap != nil && !gap.empty) {
            [self.conversationsToFetch addObject:conversation];
        }
    }
}

- (NSFetchRequest *)fetchRequestForTrackedObjects
{
    return [ZMConversation sortedFetchRequest];
}

- (void)whitelistTopConversationsIfIncomplete
{
    // force save so that it receives all updates
    [self.context saveOrRollback];
    
    if (self.conversationsToFetch.count == 0) {
        return;
    }
    
    // sort the conversations by lastmodifiedDate
    [self.conversationsToFetch sortUsingDescriptors:[ZMConversation defaultSortDescriptors]];

    // we don't fetch archived conversations or conversations wich blocked users at all
    NSPredicate *predicate = [NSPredicate predicateWithBlock:^BOOL(ZMConversation *conversation, ZM_UNUSED id bindings) {
            return !conversation.isArchived && !conversation.connectedUser.isBlocked;
        }];
    NSOrderedSet *conversationsToFetch = [self.conversationsToFetch filteredOrderedSetUsingPredicate:predicate];

    // pick only first 10 conversations to sync normally
    double minLength = conversationsToFetch.count;
    double maxLength = ConversationPriorityCount;
    NSUInteger length = (NSUInteger)MIN(minLength, maxLength);
    NSArray *conversationsWithPriority = [conversationsToFetch.array subarrayWithRange:NSMakeRange(0, length)];
    [self.whitelistedConversations addObjectsFromArray:conversationsWithPriority];
}

- (void)removeConversationToFetch:(ZMConversation *)conversation;
{
    [self.conversationsToFetch removeObject:conversation];
    [self.whitelistedConversations removeObject:conversation];
}

- (void)moveConversationToTopFetchPriority:(ZMConversation *)conversation;
{
    if ([self.conversationsToFetch containsObject:conversation]) {
        [self.conversationsToFetch removeObject:conversation];
    }
    [self.conversationsToFetch insertObject:conversation atIndex:0];
    [ZMRequestAvailableNotification notifyNewRequestsAvailable:self];
}

- (void)processConversationWhitelistingAndFetching:(ZMConversation *)conversation;
{
    ZMEventIDRange *gap = [conversation lastEventIDGap];
    if (!gap || gap.empty) {
        [self removeConversationToFetch:conversation];
        [[NSNotificationCenter defaultCenter] postNotificationName:ZMConversationDidFinishFetchingMessages
                                                            object:nil
                                                          userInfo:@{ZMNotificationConversationKey: conversation}];
        return;
    }
    
    [self.conversationsToFetch addObject:conversation];
    
    ZMEventIDRange *window = self.conversationWindows[conversation.objectID];
    if (window) {
        gap = [conversation lastEventIDGapForVisibleWindow:window];
        if (gap && !gap.empty) {
            [self replaceOrAddCurrentlyWhitelistedConversationIfNeeded:conversation];
            [self moveConversationToTopFetchPriority:conversation];
            [[NSNotificationCenter defaultCenter] postNotificationName:ZMConversationWillStartFetchingMessages
                                                                object:nil
                                                              userInfo:@{ZMNotificationConversationKey: conversation}];

            return;
        }
    }
    [self.whitelistedConversations removeObject:conversation];
    [[NSNotificationCenter defaultCenter] postNotificationName:ZMConversationDidFinishFetchingMessages
                                                        object:nil
                                                      userInfo:@{ZMNotificationConversationKey: conversation}];

}

- (void)objectsDidChange:(NSSet *)objects
{
    for (ZMConversation *conversation in objects) {
        if (conversation.entity != self.conversationEntity) {
            continue;
        }
        [self processConversationWhitelistingAndFetching:conversation];
    }
}

- (void)windowSizeChanged:(NSNotification *)note
{
    ZMEventIDRange *window = [self windowFromVisibleWindowNotification:note];
    NSManagedObjectID *conversationID = ((NSManagedObject *) note.object).objectID;
    ZM_WEAK(self);
    [self.context performGroupedBlock:^{
        ZM_STRONG(self);
        if(!self || self.tornDown) {
            return;
        }
        if (window == nil) {
            ZMConversation *conversation = [self.context objectWithID:conversationID];
            self.conversationWindows[conversationID] = nil;
            [self.whitelistedConversations removeObject:conversation];
            return;
        }

        self.conversationWindows[conversationID] = window;
        ZMConversation *syncConversation = (id) [self.context objectWithID:conversationID];
        [self processConversationWhitelistingAndFetching:syncConversation];
    }];
}

- (void)replaceOrAddCurrentlyWhitelistedConversationIfNeeded:(ZMConversation *)conversation
{
    // When initial fetching of the first top conversation is done, we would have at most 1 conversation being whitelisted
    // We consider at that point that only conversation that are in window would be and need whitelisting.
    if (self.whitelistedConversations.count == 1 && ![self.whitelistedConversations containsObject:conversation]) {
        [self.whitelistedConversations removeAllObjects];
    }
    [self.whitelistedConversations addObject:conversation];
}


- (void)fetchConversation:(NSNotification *)note
{
    NSManagedObjectID *conversationID = ((NSManagedObject *) note.object).objectID;
    ZM_WEAK(self);
    [self.context performGroupedBlock:^{
        ZM_STRONG(self);
        if(!self) {
            return;
        }
        ZMConversation *syncConversation = (id) [self.context objectWithID:conversationID];
        
        ZMEventIDRange *gap = [self gapForConversation:syncConversation];
        if (gap && !gap.empty) {
            [self replaceOrAddCurrentlyWhitelistedConversationIfNeeded:syncConversation];
            [self moveConversationToTopFetchPriority:syncConversation];
        } else if ([self.conversationsToFetch containsObject:syncConversation]) {
            [self removeConversationToFetch:syncConversation];
        }
    }];
}

- (ZMEventIDRange *)windowFromVisibleWindowNotification:(NSNotification *)note;
{
    ZMConversation *conversation = note.object;
    VerifyReturnNil(conversation != nil);
    
    ZMEventID *oldestEvent = [note.userInfo optionalEventForKey:ZMVisibleWindowLowerKey];
    ZMEventID *newestEvent = [note.userInfo optionalEventForKey:ZMVisibleWindowUpperKey];
    if(oldestEvent == nil && newestEvent == nil) {
        return nil;
    }
    
    if (newestEvent == nil) {
        newestEvent = conversation.lastEventID;
    }
    if (oldestEvent == nil) {
        oldestEvent = newestEvent;
    }
    
    ZMEventIDRange *window = [[ZMEventIDRange alloc] init];
    
    [window addEvent:oldestEvent];
    [window addEvent:newestEvent];
    
    return window;
}

- (NSOrderedSet *)incompleteNonWhitelistedConversations
{
    NSMutableOrderedSet *incompleteConversations = [self.conversationsToFetch mutableCopy];
    [incompleteConversations minusSet:self.whitelistedConversations];
    return incompleteConversations;
}

- (NSOrderedSet *)incompleteWhitelistedConversations
{
    NSMutableOrderedSet *incompleteConversations = [self.conversationsToFetch mutableCopy];
    [incompleteConversations intersectSet:self.whitelistedConversations];
    return incompleteConversations;
}

- (nullable ZMEventIDRange *)gapForConversation:(ZMConversation *)conversation
{
    ZMEventIDRange *gap = nil;
    if(![self.whitelistedConversations containsObject:conversation]) {
        gap = [conversation lastEventIDGap];
    } else {
        ZMEventIDRange *window = self.conversationWindows[conversation.objectID];
        gap = [conversation lastEventIDGapForVisibleWindow:window];
    }
    return gap;
}

@end
