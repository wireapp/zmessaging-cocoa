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
@import ZMUtilities;

#import "ZMSearch.h"
#import "ZMSearchResult+Internal.h"
#import "ZMSearchRequestCodec.h"
#import "ZMUserSession+Internal.h"
#import "ZMSearchRequest+Internal.h"

@interface ZMSearchRequest (ZMSearchToken) <ZMSearchToken>
@end



@interface ZMSearch ()

@property (nonatomic, readonly) NSManagedObjectContext *searchContext;
@property (nonatomic, readonly) NSManagedObjectContext *userInterfaceContext;
@property (nonatomic, readonly) ZMUserSession *userSession;
@property (nonatomic, readonly) NSCache *resultCache;

@property (nonatomic) NSTimer *timeoutTimer;
@property (nonatomic) NSTimer *updateDelayTimer;

@property (nonatomic) ZMSearchState state; //May only be accessed / modified from ui queue

// If local search finishes first, this is the local search result. If remote finishes first, this is the remote search result.
@property (nonatomic) ZMSearchResult *remoteSearchResult;
@property (nonatomic) ZMSearchResult *localSearchResult;


@end



@implementation ZMSearch

- (instancetype)initWithRequest:(ZMSearchRequest *)request
                        context:(NSManagedObjectContext *)context
                    userSession:(ZMUserSession *)userSession
                    resultCache:(NSCache *)resultCache
{
    self = [super init];
    
    if (self) {
        _state = ZMSearchStateNotStarted;
        _request = request;
        _searchContext = context;
        _userInterfaceContext = userSession.managedObjectContext;
        _userSession = userSession;
        _resultCache = resultCache;
        
        _token = [self.class tokenForRequest:request];
        
    }
    
    return self;
}

@synthesize token = _token;

// Only ZMSearch has the knowledge that the token is actually the search request
+ (ZMSearchToken)tokenForRequest:(ZMSearchRequest *)request
{
    return request;
}

- (void)start {
    
    if([self tryToSendCachedResult]) {
        return;
    }
    
    self.state = ZMSearchStateInProgress;
    
    [self startLocalSearch];
    [self startTimeout];
    [self startRemoteSearch];
}


- (void)tearDown {
    _userInterfaceContext = nil;
    _searchContext = nil;
    _userSession = nil;
    _resultCache = nil;

    [self.timeoutTimer invalidate];
    [self.updateDelayTimer invalidate];
    self.timeoutTimer = nil;
    self.updateDelayTimer = nil;
}

- (BOOL)tryToSendCachedResult {
    ZMSearchResult *cached = [self.resultCache objectForKey:self];
    if (cached != nil) {
        [self sendSearchResult:cached];
        return YES;
    }

    return NO;
}

- (void)startLocalSearch
{
    ZM_WEAK(self);
    
    [self.searchContext performGroupedBlock:^{

        ZM_STRONG(self);
        if(!self) {
            return;
        }
        
        NSArray *userResults = @[];
        NSArray *conversations = @[];
        
        if (self.request.includeContacts) {
            userResults = [self connectedUsersMatchingSearchString:self.request.query];
        }
        
        if (self.request.includeGroupConversations) {
            conversations = [self conversationsMatchingSearchString:self.request.query];
        }
        
        [self handleLocalUserResults:userResults conversationResults:conversations];
    }];
}

- (NSArray *)connectedUsersMatchingSearchString:(NSString *)searchString
{
    NSFetchRequest *userFetchRequest = [ZMUser sortedFetchRequestWithPredicate:[ZMUser predicateForConnectedUsersWithSearchString:searchString]];
    return [self.searchContext executeFetchRequestOrAssert:userFetchRequest];
}

- (NSArray *)conversationsMatchingSearchString:(NSString *)searchString
{
    NSFetchRequest *conversationFetchRequest = [ZMConversation sortedFetchRequestWithPredicate:[ZMConversation predicateForSearchString:searchString]];
    NSSortDescriptor *sortDescriptor = [NSSortDescriptor sortDescriptorWithKey:ZMNormalizedUserDefinedNameKey ascending:YES];
    conversationFetchRequest.sortDescriptors = @[sortDescriptor];
    
    NSArray *conversationResults = [self.searchContext executeFetchRequestOrAssert:conversationFetchRequest];
    if([searchString hasPrefix:@"@"]) { // ignore group conversations if query is for usernames
        conversationResults = [conversationResults filterWithBlock:^BOOL(ZMConversation *conversation) {
            return [conversation.displayName containsString:@"@"];
        }];
    }
    
    NSArray *sortedConversations = [self sortedConversationResults:conversationResults forSearchString:searchString];
    
    return sortedConversations;
}

- (NSArray *)sortedConversationResults:(NSArray *)conversationResults forSearchString:(NSString *)searchString
{
    NSMutableArray *matchingConv = [NSMutableArray array];
    NSMutableArray *nonMatchingConv = [NSMutableArray array];
    
    NSPredicate *convNamePredicate = [ZMConversation userDefinedNamePredicateForSearchString:searchString];
    for (ZMConversation *conv in conversationResults){
        if ([convNamePredicate evaluateWithObject:conv]) {
            [matchingConv addObject:conv];
        } else {
            [nonMatchingConv addObject:conv];
        }
    }
    
    [matchingConv addObjectsFromArray:nonMatchingConv];
    return matchingConv;
}

- (void)handleLocalUserResults:(NSArray *)userResults
           conversationResults:(NSArray *)conversationResults
{
    ZM_WEAK(self);
    [self.userInterfaceContext performGroupedBlock:^{

        ZM_STRONG(self);
        if(!self) {
            return;
        }
        
        ZMSearchResult *searchResult = [[ZMSearchResult alloc] init];
        
        NSArray *localUserResults = [self uiObjectsForSearchObjects:userResults];
        NSArray *searchUsers = [self createSearchUsersForActualUsers:localUserResults];
        [searchResult addUsersInContacts:searchUsers];
        
        NSArray *localConversationResults = [self uiObjectsForSearchObjects:conversationResults];
        [searchResult addGroupConversations:localConversationResults];
        
        switch (self.state) {
            case ZMSearchStateDone:
                break;
                
            case ZMSearchStateFirstSearchDone: //local search already finished
                {
                    ZMSearchResult *combined = [self combineLocalResult:searchResult withRemoteResult:self.remoteSearchResult];
                    [self finishSearchWithSearchResult:combined];
                }
                break;
            
            case ZMSearchStateFirstSearchDidNotFinish:
                [self finishSearchWithSearchResult:searchResult];
                break;
                
            case ZMSearchStateInProgress: //local search not finished yet
                self.localSearchResult = searchResult;
                self.state = ZMSearchStateFirstSearchDone;
                break;
                
            case ZMSearchStateNotStarted:
                VerifyString(NO, "Invalid state in ZMSearch: %u", (unsigned) self.state);
                break;
                
            default:
                break;
        }

        
    }];
}


- (NSArray *)uiObjectsForSearchObjects:(NSArray *)searchResults
{
    NSMutableArray *uiResults = [NSMutableArray array];
    for (ZMManagedObject *obj in searchResults) {
        [uiResults addObject:[self.userInterfaceContext objectWithID:obj.objectID]];
    }
    return uiResults;
}


- (NSArray *)createSearchUsersForActualUsers:(NSArray *)actualUsers
{
    ZMUser *selfUser = [ZMUser selfUserInContext:self.userInterfaceContext];
    NSMutableArray *usersToTransform = [NSMutableArray array];
    
    for (ZMUser *user in actualUsers) {
        if ([self.request.ignoredIDs containsObject:user.remoteIdentifier] || [user isEqual:selfUser]) {
            continue;
        }
        [usersToTransform addObject:user];
    }
    
    NSArray *searchUsers = [ZMSearchUser usersWithUsers:usersToTransform userSession:self.userSession];
    return searchUsers;
}


- (void)startTimeout
{
    self.timeoutTimer = [NSTimer scheduledTimerWithTimeInterval:self.timeout
                                                         target:self
                                                       selector:@selector(remoteRequestDidNotFinish:)
                                                       userInfo:nil
                                                        repeats:NO];
}

- (void)remoteRequestDidNotFinish:(id)sender
{
    NOT_USED(sender);
    [self.userInterfaceContext performBlock:^{
        
        switch (self.state) {
            case ZMSearchStateDone:
                break;
            
            case ZMSearchStateFirstSearchDone:
                // local search already finished
                // OR remote search finished before local, but timer was not invalidated in time because it runs on a different thread
                // if localSearchResult is nil then local search did not finish yet
                if (self.localSearchResult != nil) {
                    [self finishSearchWithSearchResult:self.localSearchResult];
                }
                break;
                
            case ZMSearchStateInProgress: //local search not finished yet
                self.state = ZMSearchStateFirstSearchDidNotFinish;
                break;
        
            case ZMSearchStateNotStarted:
            case ZMSearchStateFirstSearchDidNotFinish:
                VerifyString(NO, "Invalid state in ZMSearch: %u", (unsigned) self.state);
                break;
                
            default:
                break;
        }
        
    }];
}


- (void)startRemoteSearch
{
    ZM_WEAK(self);
    if (! self.request.includeRemoteResults) {
        // We pretend that the remote call timed out. Same as skipping it.
        [self remoteRequestDidNotFinish:nil];
        return;
    }
    
    ZMTransportRequest *request = [ZMSearchRequestCodec searchRequestForQueryString:self.request.query fetchLimit:10];
    [request setDebugInformationTranscoder:self];
    [request addCompletionHandler:[ZMCompletionHandler handlerOnGroupQueue:self.userInterfaceContext block:^(ZMTransportResponse *response) {
        ZM_STRONG(self);
        if (!self || self.userSession == nil) {
            // the session has been tornDown but not deallocated
            return;
        }

        ZMSearchResult *searchResult = [ZMSearchRequestCodec searchResultFromTransportResponse:response ignoredIDs:self.request.ignoredIDs userSession:self.userSession query:self.request.query];

        if (response.result != ZMTransportResponseStatusSuccess) {
            [self.timeoutTimer fire];
        }
        
        switch (self.state) {
            case ZMSearchStateDone:
                break;
                
            case ZMSearchStateFirstSearchDone: //local search already finished
                {
                    ZMSearchResult *combined = [self combineLocalResult:self.localSearchResult withRemoteResult:searchResult];
                    [self finishSearchWithSearchResult:combined];
                }
                break;
                
            case ZMSearchStateInProgress: //local search not finished yet
                self.remoteSearchResult = searchResult;
                self.state = ZMSearchStateFirstSearchDone;
                [self.timeoutTimer invalidate];
                break;
                
            case ZMSearchStateNotStarted:
            case ZMSearchStateFirstSearchDidNotFinish:
                VerifyString(NO, "Invalid state in ZMSearch: %u", (unsigned) self.state);
                break;
                
            default:
                break;
        }
        
    }]];
    
    [self enqueueSearchRequest:request];
}


- (void)enqueueSearchRequest:(ZMTransportRequest *)request;
{
    ZMTransportSession *session = self.userSession.transportSession;
    Require(session != nil);
    [session enqueueSearchRequest:request];
}

- (ZMSearchResult *)combineLocalResult:(ZMSearchResult *)localResult withRemoteResult:(ZMSearchResult *)remoteResult
{
    ZMSearchResult *combined = [[ZMSearchResult alloc] init];
    
    [combined addUsersInContacts:  remoteResult.usersInContacts  ?: localResult.usersInContacts];
    [combined addUsersInDirectory: remoteResult.usersInDirectory ?: localResult.usersInDirectory];
    [combined addGroupConversations:localResult.groupConversations];
    
    return combined;
}

- (void)finishSearchWithSearchResult:(ZMSearchResult *)searchResult
{
    self.state = ZMSearchStateDone;
    self.remoteSearchResult = nil;
    self.localSearchResult = nil;
    if (searchResult != nil) {
        [self.resultCache setObject:searchResult forKey:self];
        [self startCacheInvalidationTimer];
    }
    [self sendSearchResult:searchResult];
}

- (void)startCacheInvalidationTimer
{
    self.updateDelayTimer = [NSTimer scheduledTimerWithTimeInterval:self.updateDelay
                                                             target:self
                                                           selector:@selector(cacheDidTimeOut:)
                                                           userInfo:nil
                                                            repeats:NO];
}

- (void)cacheDidTimeOut:(id)sender
{
    NOT_USED(sender);
    [self.resultCache removeObjectForKey:self];
}

- (void)sendSearchResult:(ZMSearchResult *)searchResult
{
    if (self.resultHandler == nil) {
        return;
    }
    
    self.resultHandler(searchResult);
}


@end


