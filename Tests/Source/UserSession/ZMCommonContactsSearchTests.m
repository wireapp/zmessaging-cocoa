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

#import "MessagingTest.h"
#import "ZMCommonContactsSearch.h"

static NSString const *SearchAPI = @"/search/common";

@interface ZMCommonContactsSearchTests : MessagingTest

@property (nonatomic) id transportSessionMock;
@property (nonatomic) ZMUser *user1;
@property (nonatomic) ZMUser *user2;
@property (nonatomic) NSCache *cache;

@end

@implementation ZMCommonContactsSearchTests

- (void)setUp {
    [super setUp];
    
    self.transportSessionMock = [OCMockObject mockForClass:ZMTransportSession.class];
    [self verifyMockLater:self.transportSessionMock];
    
    __block NSManagedObjectID *user1ID;
    __block NSManagedObjectID *user2ID;
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMUser *user1 = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        user1.remoteIdentifier = [NSUUID createUUID];
        user1.name = @"A"; // setting the name will ensure reliable ordering when fetching
        
        ZMUser *user2 = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        user2.remoteIdentifier = [NSUUID createUUID];
        user2.name = @"B"; // setting the name will ensure reliable ordering when fetching
        
        [self.syncMOC saveOrRollback];
        user1ID = user1.objectID;
        user2ID = user2.objectID;

    }];

    
    self.user1 = (ZMUser*)[self.uiMOC objectWithID:user1ID];
    self.user2 = (ZMUser*)[self.uiMOC objectWithID:user2ID];
    
    [self.uiMOC refreshObject:self.user1 mergeChanges:YES];
    [self.uiMOC refreshObject:self.user2 mergeChanges:YES];

    self.cache = [[NSCache alloc] init];
    
}

- (void)tearDown {

    self.transportSessionMock = nil;
    self.user1 = nil;
    self.user2 = nil;
    self.cache = nil;
    
    [super tearDown];
}

- (NSDictionary *)sampleSearchResponse
{
    return @{
             @"documents": @[
                     @{
                         @"id": self.user1.remoteIdentifier.transportString,
                         },
                     @{
                         @"id": self.user2.remoteIdentifier.transportString,
                         }
                     ],
             };
}

- (void)testThatItCallsTheDelegateOnTheMainQueueIfTheResultIsAlreadyInTheCache
{
    // given
    NSUUID *searchedID = [NSUUID createUUID];

    id token = @"token!";
    
    NSOrderedSet *expectedResult = [NSOrderedSet orderedSetWithArray:@[self.user1, self.user2]];
    
    ZMCommonContactsSearchCachedEntry *entry =  [[ZMCommonContactsSearchCachedEntry alloc] initWithExpirationDate:[NSDate dateWithTimeIntervalSinceNow:100000] userObjectsIDs:[NSOrderedSet orderedSetWithArray:@[self.user1.objectID, self.user2.objectID]]];
    [self.cache setObject:entry forKey:searchedID];
    
    // expect
    XCTestExpectation *expectation = [self expectationWithDescription:@"Delegate is called"];
    id delegate = [OCMockObject mockForProtocol:@protocol(ZMCommonContactsSearchDelegate)];
    [[[delegate expect] andDo:^(NSInvocation *i ZM_UNUSED) {
        [expectation fulfill];
        XCTAssertEqualObjects([NSOperationQueue currentQueue], [NSOperationQueue mainQueue]);
    }]didReceiveCommonContactsUsers:expectedResult forSearchToken:token];
    
    // when
    NSOperationQueue *queue = [NSOperationQueue zm_serialQueueWithName:self.name];
    [queue addOperationWithBlock:^{
        [ZMCommonContactsSearch startSearchWithTransportSession:self.transportSessionMock userID:searchedID token:token syncMOC:self.syncMOC uiMOC:self.uiMOC searchDelegate:delegate resultsCache:self.cache];
    }];
    XCTAssert([self waitForCustomExpectationsWithTimeout:0.5]);
    
    // then
    [delegate verify];
}


- (void)testThatItIgnoresAndDeleteTheValueInTheCacheIfTheEntryIsTooOld
{
    // given
    NSUUID *searchedID = [NSUUID createUUID];
    
    id token = @"token!";
    
    ZMCommonContactsSearchCachedEntry *entry =  [[ZMCommonContactsSearchCachedEntry alloc] initWithExpirationDate:[NSDate dateWithTimeIntervalSinceNow:-100] userObjectsIDs:[NSOrderedSet orderedSetWithArray:@[self.user1.objectID, self.user2.objectID]]];
    [self.cache setObject:entry forKey:searchedID];
    
    // expect
    XCTestExpectation *expectation = [self expectationWithDescription:@"Delegate is called"];

    id delegate = [OCMockObject mockForProtocol:@protocol(ZMCommonContactsSearchDelegate)];
    [[delegate reject] didReceiveCommonContactsUsers:OCMOCK_ANY forSearchToken:OCMOCK_ANY];
    [[self.transportSessionMock expect] enqueueSearchRequest:[OCMArg checkWithBlock:^BOOL(id obj){
        NOT_USED(obj);
        [expectation fulfill];
        return YES;
    }]];
    
    // when
    NSOperationQueue *queue = [NSOperationQueue zm_serialQueueWithName:self.name];
    [queue addOperationWithBlock:^{
        [ZMCommonContactsSearch startSearchWithTransportSession:self.transportSessionMock userID:searchedID token:token syncMOC:self.syncMOC uiMOC:self.uiMOC searchDelegate:delegate resultsCache:self.cache];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssert([self waitForCustomExpectationsWithTimeout:0.5]);

    [delegate verify];
    [self.transportSessionMock verify];
    XCTAssertNil([self.cache objectForKey:searchedID]);
}

- (void)testThatItEnqueuesASearchRequestIfTheResultIsNotInTheCache
{
    // given
    NSUUID *searchedID = [NSUUID createUUID];
    
    id token = @"token!";
    ZMTransportRequest *expectedRequest = [ZMTransportRequest requestWithPath:[NSString stringWithFormat:@"%@/%@", SearchAPI, searchedID.transportString] method:ZMMethodGET payload:nil];
    
    // expect
    id delegate = [OCMockObject mockForProtocol:@protocol(ZMCommonContactsSearchDelegate)];
    [[self.transportSessionMock expect] enqueueSearchRequest:expectedRequest];
    
    // when
    [ZMCommonContactsSearch startSearchWithTransportSession:self.transportSessionMock userID:searchedID token:token syncMOC:self.syncMOC uiMOC:self.uiMOC searchDelegate:delegate resultsCache:self.cache];
    
    // then
    [delegate verify];
}

- (void)testThatItCallsTheDelegateIfTheRequestIsCompletedSuccessfully
{
    // given
    NSUUID *searchedID = [NSUUID createUUID];
    
    __block ZMTransportRequest *request;
    
    id token = @"token!";
    
    NSDictionary *responsePayload = [self sampleSearchResponse];
    NSOrderedSet *expectedUsers = [NSOrderedSet orderedSetWithArray:@[self.user1, self.user2]];
    
    id delegate = [OCMockObject mockForProtocol:@protocol(ZMCommonContactsSearchDelegate)];
    
    // expect
    [[[delegate expect] andDo:^(NSInvocation *i ZM_UNUSED) {
        XCTAssertEqualObjects([NSOperationQueue currentQueue], [NSOperationQueue mainQueue]);
    }] didReceiveCommonContactsUsers:expectedUsers forSearchToken:token];
    [[self.transportSessionMock expect] enqueueSearchRequest:[OCMArg checkWithBlock:^BOOL(id obj) {
        request = obj;
        return YES;
    }]];
    
    // when
    [ZMCommonContactsSearch startSearchWithTransportSession:self.transportSessionMock userID:searchedID token:token syncMOC:self.syncMOC uiMOC:self.uiMOC searchDelegate:delegate resultsCache:self.cache];
    XCTAssertNotNil(request);
    [request completeWithResponse:[ZMTransportResponse responseWithPayload:responsePayload HTTPStatus:200 transportSessionError:nil]];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    [delegate verify];
}

- (void)testThatItDoesNotCallTheDelegateIfTheRequestFailedPermanentlyOrTemporarily
{
    // given
    NSUUID *searchedID = [NSUUID createUUID];
    
    __block ZMTransportRequest *request;
    
    id token = @"token!";
    
    id delegate = [OCMockObject mockForProtocol:@protocol(ZMCommonContactsSearchDelegate)];
    
    // expect
    [[delegate reject] didReceiveCommonContactsUsers:OCMOCK_ANY forSearchToken:OCMOCK_ANY];
    [[self.transportSessionMock expect] enqueueSearchRequest:[OCMArg checkWithBlock:^BOOL(id obj) {
        request = obj;
        return YES;
    }]];
    
    // when
    [ZMCommonContactsSearch startSearchWithTransportSession:self.transportSessionMock userID:searchedID token:token syncMOC:self.syncMOC uiMOC:self.uiMOC searchDelegate:delegate resultsCache:self.cache];
    XCTAssertNotNil(request);
    [request completeWithResponse:[ZMTransportResponse responseWithPayload:nil HTTPStatus:404 transportSessionError:nil]];
    WaitForAllGroupsToBeEmpty(0.5);
    [request completeWithResponse:[ZMTransportResponse responseWithPayload:nil HTTPStatus:0 transportSessionError:[NSError errorWithDomain:ZMTransportSessionErrorDomain code:ZMTransportSessionErrorCodeRequestExpired userInfo:nil]]];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    [delegate verify];
}

- (void)testThatTheValueIsSetInTheCacheIfTheRequestIsCompletedSuccessfully
{
    // given
    NSUUID *searchedID = [NSUUID createUUID];
    
    __block ZMTransportRequest *request;
    
    id token = @"token!";
    
    NSDictionary *responsePayload = [self sampleSearchResponse];
    NSOrderedSet *expectedUsers = [NSOrderedSet orderedSetWithArray:@[self.user1.objectID, self.user2.objectID]];
    
    id delegate = [OCMockObject mockForProtocol:@protocol(ZMCommonContactsSearchDelegate)];
    
    // expect
    [[delegate stub] didReceiveCommonContactsUsers:OCMOCK_ANY forSearchToken:OCMOCK_ANY];
    [[self.transportSessionMock expect] enqueueSearchRequest:[OCMArg checkWithBlock:^BOOL(id obj) {
        request = obj;
        return YES;
    }]];
    
    // when
    [ZMCommonContactsSearch startSearchWithTransportSession:self.transportSessionMock userID:searchedID token:token syncMOC:self.syncMOC uiMOC:self.uiMOC searchDelegate:delegate resultsCache:self.cache];
    XCTAssertNotNil(request);
    [request completeWithResponse:[ZMTransportResponse responseWithPayload:responsePayload HTTPStatus:200 transportSessionError:nil]];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    ZMCommonContactsSearchCachedEntry *cached = [self.cache objectForKey:searchedID];
    XCTAssertEqualObjects(expectedUsers, cached.userObjectIDs);
}

- (void)testThatSearchUsersAreNotOrderedAlphabetically
{
    // given
    NSUUID *searchedID = [NSUUID createUUID];
    
    __block ZMTransportRequest *request;
    
    id token = @"token!";
    
    NSDictionary *responsePayload = [self sampleSearchResponse];
    NSOrderedSet *expectedUsers = [NSOrderedSet orderedSetWithArray:@[self.user1.objectID, self.user2.objectID]];
    
    id delegate = [OCMockObject mockForProtocol:@protocol(ZMCommonContactsSearchDelegate)];
    
    // expect
    [[delegate stub] didReceiveCommonContactsUsers:OCMOCK_ANY forSearchToken:OCMOCK_ANY];
    [[self.transportSessionMock expect] enqueueSearchRequest:[OCMArg checkWithBlock:^BOOL(id obj) {
        request = obj;
        return YES;
    }]];
    
    {
        // when
        
        XCTAssertEqualObjects(self.user1.name, @"A");
        XCTAssertEqualObjects(self.user2.name, @"B");
        
        [ZMCommonContactsSearch startSearchWithTransportSession:self.transportSessionMock userID:searchedID token:token syncMOC:self.syncMOC uiMOC:self.uiMOC searchDelegate:delegate resultsCache:self.cache];
        XCTAssertNotNil(request);
        [request completeWithResponse:[ZMTransportResponse responseWithPayload:responsePayload HTTPStatus:200 transportSessionError:nil]];
        WaitForAllGroupsToBeEmpty(0.5);
        
        // then
        ZMCommonContactsSearchCachedEntry *cached1 = [self.cache objectForKey:searchedID];
        XCTAssertEqualObjects(expectedUsers, cached1.userObjectIDs);
    
    }
    
    {
        // when
        // swap name order
        [self.syncMOC performGroupedBlockAndWait:^{
            ZMUser *user1 = (id)[self.syncMOC objectWithID:self.user1.objectID];
            user1.name = @"B";
            ZMUser *user2 = (id)[self.syncMOC objectWithID:self.user2.objectID];
            user2.name = @"A";
            
            [self.syncMOC saveOrRollback];
        }];
        
        WaitForAllGroupsToBeEmpty(0.5);
        [self.uiMOC refreshObject:self.user1 mergeChanges:YES];
        [self.uiMOC refreshObject:self.user2 mergeChanges:YES];
        
        XCTAssertEqualObjects(self.user1.name, @"B");
        XCTAssertEqualObjects(self.user2.name, @"A");
        
        // perform search again
        
        [ZMCommonContactsSearch startSearchWithTransportSession:self.transportSessionMock userID:searchedID token:token syncMOC:self.syncMOC uiMOC:self.uiMOC searchDelegate:delegate resultsCache:self.cache];
        XCTAssertNotNil(request);
        [request completeWithResponse:[ZMTransportResponse responseWithPayload:responsePayload HTTPStatus:200 transportSessionError:nil]];
        WaitForAllGroupsToBeEmpty(0.5);
        
        // then
        // the order should not have changed
        ZMCommonContactsSearchCachedEntry *cached2 = [self.cache objectForKey:searchedID];
        XCTAssertEqualObjects(expectedUsers, cached2.userObjectIDs);
    }
}

@end
