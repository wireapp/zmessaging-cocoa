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


@import ZMCSystem;
@import ZMTransport;

#import "ZMNotifications+UserSession.h"
#import "ZMUserSession+Internal.h"

static NSString *const ZMNetworkAvailabilityChangeNotificationName = @"ZMNetworkAvailabilityChangeNotification";
static NSString *const ZMTypingChangeNotificationName = @"ZMTypingChangeNotification";
static NSString *const ZMConnectionLimitReachedNotificationName = @"ZMConnectionLimitReachedNotification";
static NSString *const ZMInitialSyncCompletedNotificationName = @"ZMInitialSyncCompletedNotification";


@interface ZMNetworkAvailabilityChangeNotification ()

@property (nonatomic) ZMNetworkState networkState;
@property (nonatomic, weak) ZMUserSession *userSession;

@end


@implementation ZMUserSession (InternalNotifications)

+ (void)notifyInitialSyncCompleted
{
    [[NSNotificationCenter defaultCenter] postNotificationName:ZMInitialSyncCompletedNotificationName object:nil];
}

@end


@implementation ZMUserSession (ZMInitialSyncCompletion)

+ (void)addInitalSyncCompletionObserver:(id<ZMInitialSyncCompletionObserver>)observer
{
    ZM_ALLOW_MISSING_SELECTOR(
                              [[NSNotificationCenter defaultCenter] addObserver:observer selector:@selector(initialSyncCompleted:) name:ZMInitialSyncCompletedNotificationName object:nil]
                              );
}

+ (void)removeInitalSyncCompletionObserver:(id<ZMInitialSyncCompletionObserver>)observer
{
    [[NSNotificationCenter defaultCenter] removeObserver:observer name:ZMInitialSyncCompletedNotificationName object:nil];
}

@end


@implementation ZMConversationMessageWindow (Notifications)


- (id<ZMConversationMessageWindowObserverOpaqueToken>)addConversationWindowObserver:(id<ZMConversationMessageWindowObserver>)observer;
{
    return (id) [self.conversation.managedObjectContext.globalManagedObjectContextObserver addConversationWindowObserver:observer window:self];
}


- (void)removeConversationWindowObserverToken:(id<ZMConversationMessageWindowObserverOpaqueToken>)token
{
    [self.conversation.managedObjectContext.globalManagedObjectContextObserver removeConversationWindowObserverForToken:(id)token];
}


@end



@implementation ZMNetworkAvailabilityChangeNotification

+ (instancetype)notificationWithNetworkState:(ZMNetworkState)networkState userSession:(ZMUserSession *)session;
{
    ZMNetworkAvailabilityChangeNotification *note = [[ZMNetworkAvailabilityChangeNotification alloc] initWithName:ZMNetworkAvailabilityChangeNotificationName object:session];
    if(note) {
        note.networkState = networkState;
        note.userSession = session;
    }
    return note;
}

+ (void)addNetworkAvailabilityObserver:(id<ZMNetworkAvailabilityObserver>)delegate userSession:(ZMUserSession *)session
{
    ZM_ALLOW_MISSING_SELECTOR
    ([[NSNotificationCenter defaultCenter] addObserver:delegate selector:@selector(didChangeAvailability:) name:ZMNetworkAvailabilityChangeNotificationName object:session]);
}

+ (void)removeNetworkAvailabilityObserver:(id<ZMNetworkAvailabilityObserver>)delegate
{
    [[NSNotificationCenter defaultCenter] removeObserver:delegate name:ZMNetworkAvailabilityChangeNotificationName object:nil];
}

@end



@implementation ZMTypingChangeNotification : ZMNotification

+ (instancetype)notificationWithConversation:(ZMConversation *)conversation typingUser:(NSSet *)typingUsers;
{
    ZMTypingChangeNotification *note = [[self alloc] initWithName:ZMTypingChangeNotificationName object:conversation];
    note.typingUsers = [typingUsers copy];
    return note;
}

- (ZMConversation *)conversation
{
    return self.object;
}

@end



@implementation ZMConversation (TypingNotification)

- (void)addTypingObserver:(id<ZMTypingChangeObserver>)observer;
{
    ZM_ALLOW_MISSING_SELECTOR
    ([[NSNotificationCenter defaultCenter] addObserver:observer selector:@selector(typingDidChange:) name:ZMTypingChangeNotificationName object:self]);
}

+ (void)removeTypingObserver:(id<ZMTypingChangeObserver>)observer;
{
    [[NSNotificationCenter defaultCenter] removeObserver:observer name:ZMTypingChangeNotificationName object:nil];
}

@end



@implementation ZMConnectionLimitNotification : ZMNotification

+ (instancetype)connectionLimitNotification;
{
    ZMConnectionLimitNotification *note = [[self alloc] initWithName:ZMConnectionLimitReachedNotificationName object:nil];
    return note;
}

+ (void)addConnectionLimitObserver:(id<ZMConnectionLimitObserver>)observer
{
    ZM_ALLOW_MISSING_SELECTOR([[NSNotificationCenter defaultCenter] addObserver:observer selector:@selector(connectionLimitReached:) name:ZMConnectionLimitReachedNotificationName object:self]);
}

+ (void)removeConnectionLimitObserver:(id<ZMConnectionLimitObserver>)observer
{
    [[NSNotificationCenter defaultCenter] removeObserver:observer name:ZMConnectionLimitReachedNotificationName object:self];
}

@end
