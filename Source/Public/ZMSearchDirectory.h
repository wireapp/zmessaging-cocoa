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

#import <ZMUtilities/ZMAccentColor.h>

@class ZMBareUser;
@class ZMConversation;
@class ZMUserSession;
@class ZMUser;
@class ZMSearchUser;
@class ZMSearchRequest;
@protocol ZMSearchResultObserver;
@protocol ZMSearchToken;
typedef id<ZMSearchToken> ZMSearchToken;
@class ZMSearchResult;
@protocol ZMSearchTopConversationsObserver;


@protocol ZMSearchResultStore <NSObject>
@end


/// This is the main entry point for searching for users and conversations.
///
/// Searches will return an opaque token and results will be delivered asynchronously for that token to the ZMSearchResultObserver.
@interface ZMSearchDirectory : NSObject <ZMSearchResultStore>

- (instancetype)initWithUserSession:(ZMUserSession *)userSession;
/// @p maxTopConversationsCount Maximum amount of top conversations to be returned.
- (instancetype)initWithUserSession:(ZMUserSession *)userSession 
           maxTopConversationsCount:(NSInteger)maxTopConversationsCount;
- (void)tearDown;

/// How long to wait for results from the backend before returning local search results.
@property (nonatomic) NSTimeInterval remoteSearchTimeout;

/// The time during which a cached result is returned when searching the same query again. After this time a query triggers a normal search.
@property (nonatomic) NSTimeInterval updateDelay;

@property (readonly, nonatomic) NSInteger maxTopConversationsCount;

/// List of current top conversations. If this list updates the ZMSearchTopConversationsObserver will be notified.
@property (readonly, nonatomic) NSArray *topConversations;

- (ZMSearchToken)performRequest:(ZMSearchRequest *)searchRequest;

/// Searches users to add to a conversation, with an optional string
- (ZMSearchToken)searchForUsersThatCanBeAddedToConversation:(ZMConversation *)conversation queryString:(NSString *)queryString;

/// Searches users and conversations matching a string
- (ZMSearchToken)searchForUsersAndConversationsMatchingQueryString:(NSString *)queryString;

/// Searches users and conversations matching a string (local only)
- (ZMSearchToken)searchForLocalUsersAndConversationsMatchingQueryString:(NSString *)queryString;

/// Searches for 'people you may want to connect to'
- (ZMSearchToken)searchForSuggestedPeople;
// This will trigger any observers for 'suggested people search' to receive an update.
- (void)removeSearchUserFromSuggestedPeople:(ZMSearchUser *)searchUser;

- (void)addSearchResultObserver:(id<ZMSearchResultObserver>)observer;
- (void)removeSearchResultObserver:(id<ZMSearchResultObserver>)observer;

- (void)addTopConversationsObserver:(id<ZMSearchTopConversationsObserver>)observer;
- (void)removeTopConversationsObserver:(id<ZMSearchTopConversationsObserver>)observer;

@end



@protocol ZMSearchResultObserver <NSObject>

- (void)didReceiveSearchResult:(ZMSearchResult *)result forToken:(ZMSearchToken)searchToken;

@end



@protocol ZMSearchTopConversationsObserver <NSObject>

- (void)topConversationsDidChange:(NSNotification *)note;

@end



@protocol ZMSearchToken <NSCopying, NSObject>
@end




@interface ZMSearchResult : NSObject

@property (nonatomic, readonly, copy) NSArray<ZMSearchUser *> *usersInContacts;
@property (nonatomic, readonly, copy) NSArray<ZMSearchUser *> *usersInDirectory;
@property (nonatomic, readonly, copy) NSArray<ZMConversation *> *groupConversations;

- (instancetype)initWithUsersInContacts:(NSArray<ZMSearchUser *> *)usersInContacts
                       usersInDirectory:(NSArray<ZMSearchUser *> *)usersInDirectory
                     groupConversations:(NSArray<ZMConversation *> *)groupConversations;

@end
