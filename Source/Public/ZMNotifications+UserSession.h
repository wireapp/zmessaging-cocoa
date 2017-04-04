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
#import <WireDataModel/ZMNotifications.h>

#import "ZMNetworkState.h"
#import "ZMUserSession.h"

@class ZMTypingChangeNotification;
@class ZMConnectionLimitNotification;
@class ZMInvitationStatusChangedNotification;
@class ZMIncompleteRegistrationUser;


@protocol ZMInitialSyncCompletionObserver <NSObject>
- (void)initialSyncCompleted:(NSNotification *)notification;
@end

@protocol ZMTypingChangeObserver <NSObject>
- (void)typingDidChange:(ZMTypingChangeNotification *)note;
@end


@protocol ZMConnectionLimitObserver <NSObject>
- (void)connectionLimitReached:(ZMConnectionLimitNotification *)note;
@end




@interface ZMUserSession (ZMInitialSyncCompletion)
+ (void)addInitalSyncCompletionObserver:(id<ZMInitialSyncCompletionObserver>)observer;
+ (void)removeInitalSyncCompletionObserver:(id<ZMInitialSyncCompletionObserver>)observer;
@end



@protocol ZMNetworkAvailabilityObserver;

@interface ZMNetworkAvailabilityChangeNotification : ZMNotification

@property (nonatomic, readonly) ZMNetworkState networkState;
@property (nonatomic, readonly, weak) ZMUserSession *userSession;


+ (void)addNetworkAvailabilityObserver:(id<ZMNetworkAvailabilityObserver>)delegate userSession:(ZMUserSession *)session;
+ (void)removeNetworkAvailabilityObserver:(id<ZMNetworkAvailabilityObserver>)delegate;

@end



@protocol ZMNetworkAvailabilityObserver <NSObject>

- (void)didChangeAvailability:(ZMNetworkAvailabilityChangeNotification *)note;

@end



@interface ZMTypingChangeNotification : ZMNotification

@property (nonatomic, readonly) ZMConversation* conversation;
@property (nonatomic, readonly) NSSet *typingUsers;

@end



@interface ZMConversation (TypingNotification)

- (void)addTypingObserver:(id<ZMTypingChangeObserver>)observer;
+ (void)removeTypingObserver:(id<ZMTypingChangeObserver>)observer;

@end



@interface ZMConnectionLimitNotification : ZMNotification

+ (void)addConnectionLimitObserver:(id<ZMConnectionLimitObserver>)observer;
+ (void)removeConnectionLimitObserver:(id<ZMConnectionLimitObserver>)observer;

@end
