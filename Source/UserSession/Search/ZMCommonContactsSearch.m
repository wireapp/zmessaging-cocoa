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


@import ZMUtilities;
@import ZMTransport;
@import ZMCDataModel;

#import "ZMCommonContactsSearch.h"


static NSTimeInterval CacheValidityInterval = 60 * 10; // 10 minutes
static NSString * const ZMSearchEndPoint = @"/search/contacts";


@implementation ZMCommonContactsSearchCachedEntry

- (instancetype)initWithExpirationDate:(NSDate *)expirationDate commonConnectionCount:(NSUInteger)commonConnectionCount;
{
    self = [super init];
    if(self) {
        _expirationDate = expirationDate;
        _commonConnectionCount = commonConnectionCount;
    }
    return self;
}

@end



@interface ZMCommonContactsSearch ()

@property (nonatomic) id<ZMCommonContactsSearchToken> searchToken;
@property (nonatomic) ZMTransportSession* transportSession;
@property (nonatomic) NSUUID* userID;
@property (nonatomic) NSManagedObjectContext* syncMOC;
@property (nonatomic) NSManagedObjectContext *uiMOC;
@property (nonatomic, weak) id<ZMCommonContactsSearchDelegate> delegate;
@property (nonatomic) NSCache* resultsCache;

@end


@implementation ZMCommonContactsSearch : NSObject

- (instancetype)initWithTransportSession:(ZMTransportSession *)transportSession
                                  userID:(NSUUID *)userID
                                   token:(id<ZMCommonContactsSearchToken>)token
                                 syncMOC:(NSManagedObjectContext *)syncMOC
                                   uiMOC:(NSManagedObjectContext *)uiMOC
                          searchDelegate:(id<ZMCommonContactsSearchDelegate>)delegate
                             resultsCache:(NSCache *)resultsCache;
{
    self = [super init];
    if(self) {
        self.searchToken = token;
        self.transportSession = transportSession;
        self.userID = userID;
        self.syncMOC = syncMOC;
        self.uiMOC = uiMOC;
        self.delegate = delegate;
        self.resultsCache = resultsCache;
    }
    
    return self;
}

// return NO if the value is not in cache
- (BOOL)checkCacheAndNotify
{
    ZMCommonContactsSearchCachedEntry *cached = [self.resultsCache objectForKey:self.userID];
    if (cached != nil) {
        if(cached.expirationDate.timeIntervalSinceNow < 0) {
            [self.resultsCache removeObjectForKey:self.userID];
        } else {
            [self notifyDelegateWithResult:cached.commonConnectionCount];
            return YES;
        }
    }
    return NO;
}

- (void)notifyDelegateWithResult:(NSUInteger)numberOfConnections
{
    NSDate *expirationDate = [NSDate dateWithTimeIntervalSinceNow:CacheValidityInterval];
    ZMCommonContactsSearchCachedEntry *entry = [[ZMCommonContactsSearchCachedEntry alloc] initWithExpirationDate:expirationDate commonConnectionCount:numberOfConnections];
    [self.resultsCache setObject:entry forKey:self.userID];

    [self.uiMOC performGroupedBlock:^{
        [self.delegate didReceiveNumberOfTotalMutualConnections:numberOfConnections forSearchToken:self.searchToken];
    }];
}

- (void)parseResponse:(ZMTransportResponse *)response
{
    if (response.result != ZMTransportResponseStatusSuccess) {
        return;
    }

    NSDictionary *result = [response.payload.asDictionary arrayForKey:@"documents"].asDictionaries.firstObject;
    NSUUID *userID = [result uuidForKey:@"id"];

    if (![self.userID isEqual:userID]) {
        // This should not happen
        [self notifyDelegateWithResult:0];
        return;
    }

    NSUInteger numberOfConnections = [result optionalNumberForKey:@"total_mutual_friends"].unsignedIntegerValue;
    [self notifyDelegateWithResult:numberOfConnections];
}

- (NSString *)fetchUsernameForUserWithID:(NSUUID *)userID
{
    if (nil == userID) {
        return nil;
    }

    ZMUser *user = [ZMUser fetchObjectWithRemoteIdentifier:userID inManagedObjectContext:self.syncMOC];
    return user.handle;
}

- (void)startRequest
{
    NSString *username = [self fetchUsernameForUserWithID:self.userID];
    if (nil == username) {
        [self notifyDelegateWithResult:0];
        return;
    }

    NSMutableCharacterSet *set = NSCharacterSet.URLQueryAllowedCharacterSet.mutableCopy;
    [set removeCharactersInString:@"=&+"];
    NSString *urlEncodedQuery = [username stringByAddingPercentEncodingWithAllowedCharacters:set];
    NSString *path = [NSString stringWithFormat:@"%@?q=%@&size=%d", ZMSearchEndPoint, urlEncodedQuery, 1];

    ZMTransportRequest *request = [ZMTransportRequest requestWithPath:path method:ZMMethodGET payload:nil];
    [request addCompletionHandler:[ZMCompletionHandler handlerOnGroupQueue:self.syncMOC block:^(ZMTransportResponse *response) {
        // Do not weakify. Keep a reference to self or the delegate will not be called
        [self parseResponse:response];
    }]];
    
    [self.transportSession enqueueSearchRequest:request];
}

+ (void)startSearchWithTransportSession:(ZMTransportSession *)transportSession
                                 userID:(NSUUID *)userID
                                  token:(id<ZMCommonContactsSearchToken>)token
                                syncMOC:(NSManagedObjectContext *)syncMoc
                                  uiMOC:(NSManagedObjectContext *)uiMOC
                         searchDelegate:(id<ZMCommonContactsSearchDelegate>)delegate
                           resultsCache:(NSCache *)resultsCache
{
    if(delegate == nil) {
        return;
    }
    
    ZMCommonContactsSearch *search = [[ZMCommonContactsSearch alloc] initWithTransportSession:transportSession
                                                                                       userID:userID
                                                                                        token:token
                                                                                      syncMOC:syncMoc
                                                                                        uiMOC:uiMOC
                                                                               searchDelegate:delegate
                                                                                 resultsCache:resultsCache];
    
    if([search checkCacheAndNotify]) {
        return;
    }
    
    [search startRequest];
}

@end
