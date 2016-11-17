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


@import CoreData;
@import ZMTransport;
@import ZMCDataModel;
@import ZMUtilities;

#import "ZMSearchDirectory+Internal.h"
#import "ZMUserSession+Internal.h"
#import "ZMSearch.h"
#import "ZMSearchRequestCodec.h"
#import "ZMSuggestionSearch.h"
#import "ZMSearchTopConversations.h"
#import "ZMUserIDsForSearchDirectoryTable.h"
#import "ZMSuggestionResult.h"
#import "ZMSearchResult+Internal.h"
#import "ZMSearchRequest.h"

static NSString * const TopConversationsDidChangeName = @"ZMTopConversationsDidChange";
static const NSTimeInterval DefaultRemoteSearchTimeout = 1.5;
static const NSTimeInterval DefaultUpdateDelay = 60;
static const NSTimeInterval TopConversationsTimeout = 60;
static const int SuggestedUsersFetchLimit = 30;

static ZMUserIDsForSearchDirectoryTable *userIDMissingProfileImageBySearch;

NSString * const InvalidateTopConversationCacheNotificationName = @"ZMInvalidateTopConversationCacheNotification";


@interface ZMSearchResult (AllSearchUsers)

@property (nonatomic, readonly) NSSet *allSearchUser;

@end



@implementation ZMSearchResult (AllSearchUsers)

- (NSSet *)allSearchUser
{
    NSMutableSet *allUsers = [NSMutableSet set];
    [allUsers addObjectsFromArray:self.usersInContacts];
    [allUsers addObjectsFromArray:self.usersInDirectory];
    return allUsers;
}

@end



@interface ZMSearchDirectory (TopConversations)

@property (nonatomic, readonly) BOOL cachedTopConversationsAreStale;
- (void)fetchTopConversationsIfCacheIsStale;
- (void)markCachedTopConversationsAsStale;

@end



@interface ZMSearchDirectory (SuggestedPeople)

- (void)suggestedUsersForUserDidChange:(NSNotification *)note;

@end



@interface ZMSearchDirectory ()

@property (nonatomic) NSHashTable *observers;
@property (nonatomic) NSManagedObjectContext *searchContext;
@property (nonatomic) NSManagedObjectContext *userInterfaceContext;
@property (nonatomic) ZMSearchTopConversations *cachedTopConversations;
@property (nonatomic) BOOL isFetchingTopConversations;
@property (nonatomic) BOOL isFetchingSuggestedPeople;
@property (nonatomic) NSMutableDictionary *searchMap;
@property (nonatomic) ZMUserSession *userSession;
@property (nonatomic) NSInteger maxTopConversationsCount;

@property (nonatomic) NSCache *searchResultsCache;

@property (nonatomic) BOOL isTornDown;

@end



@implementation ZMSearchDirectory

- (instancetype)init
{
    RequireString(NO, "ZMSearchDirectory needs to be initialized with initWithUserSession:");
    return nil;
}

- (instancetype)initWithUserSession:(ZMUserSession *)userSession
{
    return [self initWithUserSession:userSession 
                       searchContext:[NSManagedObjectContext createSearchContextWithStoreAtURL:userSession.storeURL]
            maxTopConversationsCount:24];
}

- (instancetype)initWithUserSession:(ZMUserSession *)userSession
           maxTopConversationsCount:(NSInteger)maxTopConversationsCount
{
    return [self initWithUserSession:userSession 
                       searchContext:[NSManagedObjectContext createSearchContextWithStoreAtURL:userSession.storeURL]
            maxTopConversationsCount:maxTopConversationsCount];
}

- (void)dealloc
{
    RequireString(self.isTornDown, "Deallocing a ZMSearchDirectory without calling tearDown is verboten");
    
}

- (void)tearDown
{
    [self.userSession.syncManagedObjectContext performGroupedBlock:^{
        [[ZMSearchDirectory userIDsMissingProfileImage] removeSearchDirectory:self];
        [[ZMSearchUser searchUserToMediumImageCache] removeAllObjects];
    }];
    
    self.searchContext = nil;
    self.userInterfaceContext = nil;
    self.userSession = nil;
    self.observers = nil;
    self.cachedTopConversations = nil;
    self.searchResultsCache = nil;
    self.isFetchingTopConversations = NO;
    self.isFetchingSuggestedPeople = NO;
    
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self tearDownSearchMap:self.searchMap];
    self.searchMap = nil;
    
    self.isTornDown = YES;
    

}

- (void)tearDownSearchMap:(NSMutableDictionary *)searchMap
{
    for(id<ZMSearch> search in searchMap.allValues) {
        [search tearDown];
    }
}

- (instancetype)initWithUserSession:(ZMUserSession *)userSession
                      searchContext:(NSManagedObjectContext *)searchContext
           maxTopConversationsCount:(NSInteger)maxTopConversationsCount
{
    self = [super init];
    if (self) {
        self.searchContext = searchContext;
        self.userInterfaceContext = userSession.managedObjectContext;
        self.observers = [[NSHashTable alloc] initWithOptions:NSHashTableWeakMemory capacity:10];
        self.userSession = userSession;
        self.searchMap = [NSMutableDictionary dictionary];
        
        _maxTopConversationsCount = maxTopConversationsCount;
        
        self.remoteSearchTimeout = DefaultRemoteSearchTimeout;
        self.updateDelay = DefaultUpdateDelay;
        
        self.searchResultsCache = [[NSCache alloc] init];
        
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(suggestedUsersForUserDidChange:) name:ZMSuggestedUsersForUserDidChange object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(requestedToInvalidateCache:) name:InvalidateTopConversationCacheNotificationName object:nil];
    }
    return self;
}

- (void)requestedToInvalidateCache:(NSNotification *)note
{
    NOT_USED(note);
    [self markCachedTopConversationsAsStale];
}

- (NSArray *)topConversations
{
    [self fetchTopConversationsIfCacheIsStale];
    NSArray *result = [self.cachedTopConversations conversationsInManagedObjectContext:self.userInterfaceContext];
    return result ?: @[];
}

- (ZMSearchToken)performRequest:(ZMSearchRequest *)searchRequest
{
    if (! searchRequest.query) {
        return nil;
    }
    
    ZMSearch *search;
    ZMSearchToken token = [ZMSearch tokenForRequest:searchRequest];
    ZMSearch *existingSearch = self.searchMap[token];
    
    if (existingSearch) {
        search = existingSearch;
    }
    else {
        search = [[ZMSearch alloc] initWithRequest:searchRequest context:self.searchContext userSession:self.userSession resultCache:self.searchResultsCache];
        search.timeout = self.remoteSearchTimeout;
        search.updateDelay = self.updateDelay;
    }
    
    
    NSString *query = searchRequest.query;
    ZM_WEAK(self);
    search.resultHandler = ^(ZMSearchResult *searchResult) {
        ZM_STRONG(self);
        if (self == nil) {
            return;
        }
        [self storeSearchResultUserIDsInCache:searchResult];
        
        if (searchRequest.includeAddressBookContacts) {
            searchResult = [searchResult extendWithContactsFromAddressBook:query
                                                              usersToMatch:self.connectedAndBlockedAndPendingUsers
                                                               userSession:self.userSession];
        }
        
        [self sendSearchResult:searchResult forToken:token];
    };
    
    self.searchMap[token] = search;
    [search start];
    
    return token;
}

- (ZMSearchToken)searchForUsersThatCanBeAddedToConversation:(ZMConversation *)conversation queryString:(NSString *)queryString;
{
    ZMSearchRequest *request = [[ZMSearchRequest alloc] init];
    
    request.query = queryString;
    request.includeContacts = YES;
    request.filteredConversation = conversation;
    
    return [self performRequest:request];
}

/// Searches users and conversations matching a string
- (ZMSearchToken)searchForUsersAndConversationsMatchingQueryString:(NSString *)queryString
{
    ZMSearchRequest *request = [[ZMSearchRequest alloc] init];
    
    request.query = queryString;
    request.includeContacts = YES;
    request.includeDirectory = YES;
    request.includeGroupConversations = YES;
    request.includeRemoteResults = YES;
    
    return [self performRequest:request];
}

/// Searches users and conversations matching a string (local only)
- (ZMSearchToken)searchForLocalUsersAndConversationsMatchingQueryString:(NSString *)queryString
{
    ZMSearchRequest *request = [[ZMSearchRequest alloc] init];
    
    request.query = queryString;
    request.includeContacts = YES;
    request.includeDirectory = NO;
    request.includeGroupConversations = NO;
    
    return [self performRequest:request];

}

- (ZMSearchToken)searchForSuggestedPeople;
{
    ZMSearchToken token = [ZMSuggestionSearch suggestionSearchToken];
    [self remotelySearchForSuggestedPeopleAndUpdateIdentifiersWithToken:token];

    ZMSuggestionSearch *search = self.searchMap[token];
    if (search == nil) {
        search = [self startSuggestedPeopleSearchForToken:token];
    }
    [search start];
    return search.token;
}

- (void)removeSearchUserFromSuggestedPeople:(ZMSearchUser *)searchUser;
{
    VerifyReturn(searchUser != nil);
    VerifyReturn(searchUser.remoteIdentifier != nil);
    ZMSuggestionSearch *search = [[ZMSuggestionSearch alloc] initWithSearchContext:self.searchContext userSession:self.userSession resultCache:self.searchResultsCache];
    [search removeSearchUser:searchUser];
    [search tearDown];
}

- (ZMSuggestionSearch *)startSuggestedPeopleSearchForToken:(ZMSearchToken)token
{
    ZMSuggestionSearch *search = [[ZMSuggestionSearch alloc] initWithSearchContext:self.searchContext userSession:self.userSession resultCache:self.searchResultsCache];
    self.searchMap[search.token] = search;
    search.resultHandler = ^(ZMSearchResult *searchResult) {
        [self storeSearchResultUserIDsInCache:searchResult];
        [self sendSearchResult:searchResult forToken:token];
    };
    
    return search;
}
- (void)restartSuggestedPeopleSearchForToken:(ZMSearchToken)token
{
    ZMSuggestionSearch *search = self.searchMap[token];
    if (search != nil) {
        [search tearDown];
    }
    search = [self startSuggestedPeopleSearchForToken:token];
    [search start];
}

- (void)remotelySearchForSuggestedPeopleAndUpdateIdentifiersWithToken:(ZMSearchToken)token;
{
    [self.userSession.managedObjectContext performGroupedBlock:^{
        if (self.isFetchingSuggestedPeople) {
            return;
        }
        self.isFetchingSuggestedPeople = YES;
        ZMTransportRequest *request = [ZMSearchRequestCodec searchRequestForSuggestedPeopleWithFetchLimit:SuggestedUsersFetchLimit];
        ZM_WEAK(self);
        [request addCompletionHandler:[ZMCompletionHandler handlerOnGroupQueue:self.userInterfaceContext block:^(ZMTransportResponse *response) {
            ZM_STRONG(self);
            NSOrderedSet *remoteSuggestedUsersForUser = [ZMSearchRequestCodec remoteIdentifiersForSuggestedPeopleSearchResponse:response];
            if (
                response.result == ZMTransportResponseStatusSuccess
                && ! [self.userSession.managedObjectContext.suggestedUsersForUser isEqual:remoteSuggestedUsersForUser])
            {
                self.userSession.managedObjectContext.suggestedUsersForUser = [remoteSuggestedUsersForUser valueForKey:@"userIdentifier"];
                
                NSMutableDictionary *commonConnectionsForUsers = [NSMutableDictionary dictionaryWithCapacity:remoteSuggestedUsersForUser.count];
                for (ZMSuggestionResult *suggestionResult in remoteSuggestedUsersForUser) {
                    [commonConnectionsForUsers setObject:suggestionResult.commonConnections forKey:suggestionResult.userIdentifier];
                }
                self.userSession.managedObjectContext.commonConnectionsForUsers = commonConnectionsForUsers;
                
                NSError *error;
                if (! [self.userSession.managedObjectContext save:&error]) {
                    ZMLogWarn(@"Failed to save remoteIdentifiers: %@", error);
                } else {
                    [self restartSuggestedPeopleSearchForToken:token];
                }
            }
            self.isFetchingSuggestedPeople = NO;
        }]];
        if (! self.isTornDown) {
            Require(self.userSession.transportSession != nil);
            [self.userSession.transportSession enqueueSearchRequest:request];            
        }
    }];
}

- (NSArray *)connectedAndBlockedAndPendingUsers
{
    NSArray *connectionStatuses = @[@(ZMConnectionStatusAccepted), @(ZMConnectionStatusPending), @(ZMConnectionStatusBlocked)];
    NSPredicate *predicate = [ZMUser predicateForUsersWithSearchString:@""
                                               connectionStatusInArray:connectionStatuses];
    NSFetchRequest *userFetchRequest = [ZMUser sortedFetchRequestWithPredicate:predicate];
    return [self.userInterfaceContext executeFetchRequestOrAssert:userFetchRequest];
}

- (void)storeSearchResultUserIDsInCache:(ZMSearchResult *)searchResult
{
    NSMutableSet *allSearchUsers = [NSMutableSet set];
    for(ZMSearchUser *user in searchResult.allSearchUser) {
        if(user.remoteIdentifier != nil && user.user == nil) {
            [allSearchUsers addObject:user];
        }
    }
    
    if(allSearchUsers.count > 0u) {
        NSSet *userWithoutImage = [allSearchUsers mapWithBlock:^id(ZMSearchUser *user) {
            return user.isLocalOrHasCachedProfileImageData ? nil : user;
        }];
        [[ZMSearchDirectory userIDsMissingProfileImage] setSearchUsers:userWithoutImage forSearchDirectory:self];
        [ZMRequestAvailableNotification notifyNewRequestsAvailable:nil];
    }
}

- (void)sendSearchResult:(ZMSearchResult *)searchResult forToken:(ZMSearchToken)token
{
    [self.userInterfaceContext performBlock:^{
        for (id<ZMSearchResultObserver> observer in self.observers) {
            [observer didReceiveSearchResult:searchResult forToken:token];
        }
    }];
}



- (void)addSearchResultObserver:(id<ZMSearchResultObserver>)observer;
{
    [self.observers addObject:observer];
}


- (void)removeSearchResultObserver:(id<ZMSearchResultObserver>)observer;
{
    [self.observers removeObject:observer];
}

- (void)addTopConversationsObserver:(id<ZMSearchTopConversationsObserver>)observer;
{
    ZM_ALLOW_MISSING_SELECTOR([[NSNotificationCenter defaultCenter] addObserver:observer selector:@selector(topConversationsDidChange:) name:TopConversationsDidChangeName object:self]);
}

- (void)removeTopConversationsObserver:(id<ZMSearchTopConversationsObserver>)observer;
{
    [[NSNotificationCenter defaultCenter] removeObserver:observer name:TopConversationsDidChangeName object:self];
}

+ (ZMUserIDsForSearchDirectoryTable *)userIDsMissingProfileImage;
{
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        userIDMissingProfileImageBySearch = [[ZMUserIDsForSearchDirectoryTable alloc] init];
    });
    return userIDMissingProfileImageBySearch;
}

@end



@implementation ZMSearchDirectory (TopConversations)

+ (void)invalidateCachedTopConversations
{
    [[NSNotificationCenter defaultCenter] postNotificationName:InvalidateTopConversationCacheNotificationName object:nil];
}

- (BOOL)cachedTopConversationsAreStale;
{
    return (self.cachedTopConversations == nil) || (self.cachedTopConversations.creationDate.timeIntervalSinceNow < -TopConversationsTimeout) || (self.cachedTopConversations.requestedConversationsCount != self.maxTopConversationsCount);
}

- (void)markCachedTopConversationsAsStale;
{
    // This is for testing only
    [self.cachedTopConversations setValue:[NSDate dateWithTimeIntervalSinceNow:-1000] forKey:@"creationDate"];
}

- (void)fetchTopConversationsIfCacheIsStale;
{
    if ([self cachedTopConversationsAreStale]) {
        if (self.cachedTopConversations == nil) {
            [self loadCachedTopConversations];
        }
        [self fetchTopConversations];
    }
}

- (void)fetchTopConversations
{
    if (self.isFetchingTopConversations) {
        return;
    }
    self.isFetchingTopConversations = YES;
    ZMTransportRequest *request = [ZMSearchRequestCodec searchRequestForTopConversationsWithFetchLimit:(int)self.maxTopConversationsCount];
    ZM_WEAK(self);
    [request addCompletionHandler:[ZMCompletionHandler handlerOnGroupQueue:self.userInterfaceContext block:^(ZMTransportResponse *response) {
        ZM_STRONG(self);
        [self updateTopConversationsFromTransportResponse:response];
        [self.userInterfaceContext performGroupedBlock:^{
            self.isFetchingTopConversations = NO;
        }];
    }]];
    Require(self.userSession.transportSession != nil);
    [self.userSession.transportSession enqueueSearchRequest:request];
}

- (void)updateTopConversationsFromTransportResponse:(ZMTransportResponse *)response;
{
    if (self.isTornDown) {
        return;
    }
    if (response.result != ZMTransportResponseStatusSuccess) {
        ZMLogWarn(@"Failed to get top conversations (%d): %@",
                  (int) response.HTTPStatus, response.transportSessionError);
        return;
    }
    ZMSearchResult *searchResult = [ZMSearchRequestCodec searchResultFromTransportResponse:response ignoredIDs:nil userSession:self.userSession];
    NSMutableArray *conversations = [NSMutableArray array];
    for (ZMSearchUser *searchUser in searchResult.usersInContacts) {
        ZMConversation *conversation = searchUser.user.connection.conversation;
        if (conversation != nil) {
            [conversations addObject:conversation];
        } else {
            ZMLogWarn(@"No local conversation for 'top' user <%@: %p> %@", searchUser.class, searchUser, searchUser.remoteIdentifier.transportString);
        }
    }
    Require(self.userInterfaceContext.dispatchGroup != nil);
    [self.userInterfaceContext.dispatchGroup asyncOnQueue:dispatch_get_main_queue() block:^{
        if ((conversations != nil) && ! [self.cachedTopConversations isEqual:conversations]) {
            ZMSearchTopConversations *update = [[ZMSearchTopConversations alloc] initWithConversations:conversations];
            update.requestedConversationsCount = self.maxTopConversationsCount;
            BOOL didChange = ! [update hasConversationsIdenticalTo:self.cachedTopConversations];
            self.cachedTopConversations = update;
            [self persistTopConversationsToPersistentStore];
            if (didChange) {
                [[NSNotificationCenter defaultCenter] postNotificationName:TopConversationsDidChangeName object:self];
            }
        }
    }];
}

static NSString * const TopConversationsKey = @"ZMSearchTopConversations";
static NSString * const ObjectIDURIsKey = @"objectIDURIs";

- (void)persistTopConversationsToPersistentStore;
{
    NSData * const data = [self.cachedTopConversations encode];
    NSData * const existingData = [self.userInterfaceContext persistentStoreMetadataForKey:TopConversationsKey];
    if ((existingData == data) || [existingData isEqual:data]) {
        // no change
        return;
    }
    [self.userInterfaceContext setPersistentStoreMetadata:data forKey:TopConversationsKey];
    NSError *error;
    if (! [self.userInterfaceContext save:&error]) {
        ZMLogError(@"Failed to save store for metadata changes: %@", error);
    }
}

- (void)loadCachedTopConversations;
{
    NSData *data = [self.userInterfaceContext persistentStoreMetadataForKey:TopConversationsKey];
    self.cachedTopConversations = [ZMSearchTopConversations decodeFromData:data];
}

@end



@implementation ZMSearchDirectory (SuggestedPeople)

- (void)suggestedUsersForUserDidChange:(NSNotification *)note;
{
    dispatch_block_t update = ^(){
        ZMSearchToken token = [ZMSuggestionSearch suggestionSearchToken];
        [self.searchResultsCache removeObjectForKey:token];
        // Re-start the search if we already have one. This will trigger a new notification to get sent out:
        ZMSuggestionSearch *search = self.searchMap[token];
        [search start];
    };
    
    if (note.object != self.userInterfaceContext) {
        [self.userInterfaceContext performGroupedBlock:update];
    } else {
        update();
    }
}

@end



