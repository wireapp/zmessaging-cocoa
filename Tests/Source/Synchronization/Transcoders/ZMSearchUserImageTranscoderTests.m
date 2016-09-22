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
@import zmessaging;
@import ZMCDataModel;

#import "MessagingTest.h"
#import "ZMSearchUserImageTranscoder.h"
#import "ZMSearchDirectory+Internal.h"
#import "ZMUserIDsForSearchDirectoryTable.h"
#import <zmessaging/zmessaging-Swift.h>

static NSString *const UserRequestURL = @"/users?ids=";

@interface ZMSearchUserImageTranscoderTests : MessagingTest

@property (nonatomic) ZMSearchUserImageTranscoder *sut;
@property (nonatomic) ZMUserIDsForSearchDirectoryTable *userIDsTable;
@property (nonatomic) NSCache *imagesCache;
@property (nonatomic) NSCache *assetIDCache;


- (ZMSearchUser *)createSearchUser;
- (NSSet *)userIDsFromSearchUserSet:(NSSet *)searchUsers;

@end

@implementation ZMSearchUserImageTranscoderTests

- (void)setUp {
    [super setUp];

    self.userIDsTable = [[ZMUserIDsForSearchDirectoryTable alloc] init];
    self.imagesCache = (id) [NSMutableDictionary dictionary];
    self.assetIDCache = (id) [NSMutableDictionary dictionary];
    
    self.sut = [[ZMSearchUserImageTranscoder alloc] initWithManagedObjectContext:self.uiMOC
                                                                       uiContext:self.uiMOC
                                                 userIDsWithoutProfileImageTable:self.userIDsTable
                                                             imagesByUserIDCache:self.imagesCache
                                                      mediumAssetIDByUserIDCache:self.assetIDCache];
}

- (void)tearDown {

    [self.sut tearDown];
    self.sut = nil;
    self.imagesCache = nil;
    self.userIDsTable = nil;
    [super tearDown];
}

- (ZMSearchUser *)createSearchUser
{
    return [[ZMSearchUser alloc] initWithName:@"foobar" accentColor:ZMAccentColorBrightYellow remoteID:[NSUUID createUUID] user:nil syncManagedObjectContext: self.syncMOC uiManagedObjectContext:self.uiMOC];
}

- (NSSet *)userIDsFromSearchUserSet:(NSSet *)searchUsers
{
    return [searchUsers mapWithBlock:^id(ZMSearchUser *user) {
        return user.remoteIdentifier;
    }];
    
}

- (void)testThatItGeneratesRequestsItSelf
{
    // when
    NSArray *generators = self.sut.requestGenerators;
    
    // then
    XCTAssertEqual(generators.count, 1u);
    XCTAssertEqual(generators.firstObject, self.sut);
}

- (void)testThatItReturnsTheContextChangeTrackers;
{
    // when
    NSArray *trackers = self.sut.contextChangeTrackers;
    
    // then
    XCTAssertEqual(trackers.count, 0u);
}

- (void)testThatTheRightValuesAreStoredByTheInit
{
    XCTAssertEqual(self.userIDsTable, self.sut.userIDsTable);
    XCTAssertEqual(self.imagesCache, self.sut.imagesByUserIDCache);
}

- (void)testThatTheDefaultInitCreatesTheCorrectTables
{
    // when
    ZMSearchUserImageTranscoder *sut = [[ZMSearchUserImageTranscoder alloc] initWithManagedObjectContext:self.syncMOC uiContext:self.uiMOC ];
    
    // then
    XCTAssertEqual(sut.userIDsTable, [ZMSearchDirectory userIDsMissingProfileImage]);
    XCTAssertEqual(sut.imagesByUserIDCache, [ZMSearchUser searchUserToSmallProfileImageCache]);
    
    // after
    [sut tearDown];
}

- (void)testThatItAlwaysReturnsIsSlowSyncDone
{
    // then
    XCTAssertTrue(self.sut.isSlowSyncDone);
    
    // and when
    [self.sut setNeedsSlowSync];
    
    // then
    XCTAssertTrue(self.sut.isSlowSyncDone);
}

- (void)testThatItReturnsNoContextChangeTracker
{
    // given
    NSArray *expected = @[];
    
    // then
    XCTAssertEqual(expected, self.sut.contextChangeTrackers);
}


@end



@implementation ZMSearchUserImageTranscoderTests (UserProfiles)

- (NSDictionary *)userDataWithSmallProfilePictureID:(NSUUID *)pictureID forUserID:(NSUUID *)userID
{
    return [self userDataWithSmallProfilePictureID:pictureID mediumPictureID:nil forUserID:userID];
}

- (NSDictionary *)userDataWithSmallProfilePictureID:(NSUUID *)pictureID mediumPictureID:(NSUUID *)mediumID forUserID:(NSUUID *)userID
{
    return @{
             @"id" : userID.transportString,
             @"picture": @[
                     @{
                         @"id": pictureID.transportString ?: [NSUUID createUUID].transportString,
                         @"info": @{
                                 @"tag": @"smallProfile",
                                 }
                         },
                     @{
                         @"id": mediumID.transportString ?: [NSUUID createUUID].transportString,
                         @"info": @{
                                 @"tag": @"medium",
                                 }
                         },
                     ]
             };
}

- (NSSet *)userIDsInGetRequest:(ZMTransportRequest *)request
{
    NSString *path = request.path;
    if( ! [path hasPrefix:UserRequestURL]) {
        return [NSSet set];
    }
    NSString *userIDs = [path substringFromIndex:UserRequestURL.length];
    NSArray *tokens = [[userIDs componentsSeparatedByString:@","] mapWithBlock:^id(NSString *s) {
        return [NSUUID uuidWithTransportString:s];
    }];
    return [NSSet setWithArray:tokens];
}


- (void)testThatItReturnsNoRequestIfThereIsNoUserIDMissingProfileImage
{
    // given
    XCTAssertEqual([ZMSearchDirectory userIDsMissingProfileImage].allUserIDs.count, 0u);
    
    // when
    ZMTransportRequest *request = [self.sut.requestGenerators nextRequest];
    
    // then
    XCTAssertNil(request);
}

- (void)testThatNextRequestCreatesARequestForAllUserIDsInTheUserTable
{
    // given
    ZMSearchUser *user1 = [self createSearchUser];
    ZMSearchUser *user2 = [self createSearchUser];
    ZMSearchUser *user3 = [self createSearchUser];
    
    id fakeSearchDirectory = @"foo";
    
    NSSet *searchSet = [NSSet setWithArray:@[user1, user2, user3]];
    
    [self.userIDsTable setSearchUsers:searchSet forSearchDirectory:fakeSearchDirectory];

    // when
    ZMTransportRequest *request = [self.sut.requestGenerators nextRequest];
    
    // then
    XCTAssertNotNil(request);
    XCTAssertEqual(request.method, ZMMethodGET);
    XCTAssertTrue(request.needsAuthentication);
    
    NSSet* expectedSet = [self userIDsFromSearchUserSet:searchSet];
    
    XCTAssertTrue([request.path hasPrefix:UserRequestURL]);
    XCTAssertEqualObjects([self userIDsInGetRequest:request], expectedSet);
}

- (void)testThatNextRequestCreatesARequestForAllUserIDsInTheUserTableThatWeAreNotAlreadyRequesting
{
    // given
    ZMSearchUser *user1 = [self createSearchUser];
    ZMSearchUser *user2 = [self createSearchUser];
    ZMSearchUser *user3 = [self createSearchUser];
    
    id fakeSearchDirectory1 = @"foo";
    id fakeSearchDirectory2 = @"bar";
    
    [self.userIDsTable setSearchUsers:[NSSet setWithObjects:user1, user2, nil] forSearchDirectory:fakeSearchDirectory1];
    [self.sut.requestGenerators nextRequest]; // start first request
    
    // when
    [self.userIDsTable setSearchUsers:[NSSet setWithObject:user3] forSearchDirectory:fakeSearchDirectory2];
    ZMTransportRequest *request2 = [self.sut.requestGenerators nextRequest];
    
    // then
    XCTAssertNotNil(request2);
    XCTAssertEqual(request2.method, ZMMethodGET);
    XCTAssertTrue(request2.needsAuthentication);
    
    XCTAssertEqualObjects([self userIDsInGetRequest:request2], [NSSet setWithObject:user3.remoteIdentifier]);

}

- (void)testThatCompletingARequestSetsTheAssetIDForThoseUsersOnTheTable
{
    // given
    ZMSearchUser *user1 = [self createSearchUser];
    ZMSearchUser *user2 = [self createSearchUser];
    
    NSUUID *assetID1 = [NSUUID createUUID];
    NSUUID *assetID2 = [NSUUID createUUID];

    id fakeSearchDirectory1 = @"foo";
    
    [self.userIDsTable setSearchUsers:[NSSet setWithObjects:user1, user2, nil] forSearchDirectory:fakeSearchDirectory1];
    
    NSArray *responsePayload = @[
                                 [self userDataWithSmallProfilePictureID:assetID1 forUserID:user1.remoteIdentifier],
                                 [self userDataWithSmallProfilePictureID:assetID2 forUserID:user2.remoteIdentifier],
                                 ];
    NSSet *expectedAssetIDs = [NSSet setWithObjects:
                               [[ZMSearchUserAndAssetID alloc] initWithSearchUser:user1 assetID:assetID1],
                               [[ZMSearchUserAndAssetID alloc] initWithSearchUser:user2 assetID:assetID2],
                               nil];
    
    
    // when
    ZMTransportRequest *request = [self.sut.requestGenerators nextRequest];
    [request completeWithResponse:[ZMTransportResponse responseWithPayload:responsePayload HTTPStatus:200 transportSessionError:nil]];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    
    NSSet *fetchedAssetIDs = [self.userIDsTable allAssetIDs];
    XCTAssertEqualObjects(fetchedAssetIDs, expectedAssetIDs);
    XCTAssertEqual(self.userIDsTable.allUserIDs.count, 0u);
}

- (void)testThatCompletingARequestWithoutAssetIDDeletesTheUserFromTheTable
{
    // given
    ZMSearchUser *user1 = [self createSearchUser];
    
    id fakeSearchDirectory1 = @"foo";
    
    [self.userIDsTable setSearchUsers:[NSSet setWithObject:user1] forSearchDirectory:fakeSearchDirectory1];
    
    NSArray *responsePayload = @[
                                 @{
                                     @"id" : user1.remoteIdentifier.transportString,
                                     @"picture" : @[]
                                     }
                                 ];
    
    
    // when
    ZMTransportRequest *request = [self.sut.requestGenerators nextRequest];
    [request completeWithResponse:[ZMTransportResponse responseWithPayload:responsePayload HTTPStatus:200 transportSessionError:nil]];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(self.userIDsTable.allUserIDs.count, 0u);
    XCTAssertEqual(self.userIDsTable.allAssetIDs.count, 0u);
}

- (void)testThatFailingARequestWithAPermanentErrorRemovesTheUsersFromTheTable
{
    // given
    ZMSearchUser *user1 = [self createSearchUser];
    ZMSearchUser *user2 = [self createSearchUser];
    
    id fakeSearchDirectory1 = @"foo";
    
    [self.userIDsTable setSearchUsers:[NSSet setWithObjects:user1, user2, nil] forSearchDirectory:fakeSearchDirectory1];
    
    // when
    ZMTransportRequest *request = [self.sut.requestGenerators nextRequest];
    [request completeWithResponse:[ZMTransportResponse responseWithPayload:nil HTTPStatus:400 transportSessionError:nil]];
    WaitForAllGroupsToBeEmpty(0.5);

    // then
    XCTAssertEqual(self.userIDsTable.allUserIDs.count, 0u);
}

- (void)testThatFailingARequestWithATemporaryErrorAllowsForThoseUserIDsToBeDownloadedAgain
{
    // given
    ZMSearchUser *user1 = [self createSearchUser];
    ZMSearchUser *user2 = [self createSearchUser];
    NSSet *expectedIDs = [NSSet setWithObjects:user1.remoteIdentifier, user2.remoteIdentifier, nil];
    
    id fakeSearchDirectory1 = @"foo";
    [self.userIDsTable setSearchUsers:[NSSet setWithObjects:user1, user2, nil] forSearchDirectory:fakeSearchDirectory1];
    
    // when
    ZMTransportRequest *request = [self.sut.requestGenerators nextRequest];
    [request completeWithResponse:[ZMTransportResponse responseWithPayload:nil HTTPStatus:500 transportSessionError:nil]];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // and when
    [self.userIDsTable setSearchUsers:[NSSet setWithObjects:user1, user2, nil] forSearchDirectory:fakeSearchDirectory1];
    ZMTransportRequest *request2 = [self.sut.requestGenerators nextRequest];
    XCTAssertEqualObjects([self userIDsInGetRequest:request2], expectedIDs);
    
}

- (void)testThatFailingARequestWithAPermanentErrorAllowsForThoseUserIDsToBeDownloadedAgain
{
    // given
    ZMSearchUser *user1 = [self createSearchUser];
    ZMSearchUser *user2 = [self createSearchUser];
    NSSet *expectedIDs = [NSSet setWithObjects:user1.remoteIdentifier, user2.remoteIdentifier, nil];
    
    id fakeSearchDirectory1 = @"foo";
    [self.userIDsTable setSearchUsers:[NSSet setWithObjects:user1, user2, nil] forSearchDirectory:fakeSearchDirectory1];
    
    // when
    ZMTransportRequest *request = [self.sut.requestGenerators nextRequest];
    [request completeWithResponse:[ZMTransportResponse responseWithPayload:nil HTTPStatus:400 transportSessionError:nil]];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // and when
    [self.userIDsTable setSearchUsers:[NSSet setWithObjects:user1, user2, nil] forSearchDirectory:fakeSearchDirectory1];
    ZMTransportRequest *request2 = [self.sut.requestGenerators nextRequest];
    XCTAssertEqualObjects([self userIDsInGetRequest:request2], expectedIDs);
}

- (void)testThatCompletingARequestDoesNotAllowForThoseUserIDsToBeDownloadedAgain
{
    // given
    ZMSearchUser *user1 = [self createSearchUser];
    ZMSearchUser *user2 = [self createSearchUser];
    
    NSUUID *assetID1 = [NSUUID createUUID];
    NSUUID *assetID2 = [NSUUID createUUID];
    
    id fakeSearchDirectory1 = @"foo";
    
    [self.userIDsTable setSearchUsers:[NSSet setWithObjects:user1, user2, nil] forSearchDirectory:fakeSearchDirectory1];
    
    NSArray *responsePayload = @[
                                 [self userDataWithSmallProfilePictureID:assetID1 forUserID:user1.remoteIdentifier],
                                 [self userDataWithSmallProfilePictureID:assetID2 forUserID:user2.remoteIdentifier],
                                 ];
    
    // when
    ZMTransportRequest *request = [self.sut.requestGenerators nextRequest];
    [request completeWithResponse:[ZMTransportResponse responseWithPayload:responsePayload HTTPStatus:200 transportSessionError:nil]];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    [self.userIDsTable setSearchUsers:[NSSet setWithObjects:user1, user2, nil] forSearchDirectory:fakeSearchDirectory1];
    ZMTransportRequest *request2 = [self.sut.requestGenerators nextRequest];
    XCTAssertEqual([self userIDsInGetRequest:request2].count, 0u);
}

- (void)testThatItCachesTheMediumAssetIDWhenDownloadingUserInfo
{
    // given
    ZMSearchUser *user1 = [self createSearchUser];
    NSUUID *assetID1 = [NSUUID createUUID];
    id fakeSearchDirectory1 = @"foo";
    
    
    [self.userIDsTable setSearchUsers:[NSSet setWithObject:user1] forSearchDirectory:fakeSearchDirectory1];
    NSArray *responsePayload = @[[self userDataWithSmallProfilePictureID:nil mediumPictureID:assetID1 forUserID:user1.remoteIdentifier]];
    
    // when
    ZMTransportRequest *request = [self.sut.requestGenerators nextRequest];
    [request completeWithResponse:[ZMTransportResponse responseWithPayload:responsePayload HTTPStatus:200 transportSessionError:nil]];
    WaitForAllGroupsToBeEmpty(0.5);
    
    
    // then
    XCTAssertEqualObjects([self.assetIDCache objectForKey:user1.remoteIdentifier], assetID1);
}

@end



@implementation ZMSearchUserImageTranscoderTests (ImageAssets)

- (NSString *)requestPathForAssetID:(NSUUID *)assetID ofUserID:(NSUUID *)userID
{
    return [NSString stringWithFormat:@"/assets/%@?conv_id=%@", assetID.transportString, userID.transportString];
    
}

- (void)testThatNextRequestCreatesARequestForAnAssetID
{
    // given
    ZMSearchUser *user = [self createSearchUser];
    NSUUID *assetID = [NSUUID createUUID];
    
    id fakeSearchDirectory = @"foo";
    
    [self.userIDsTable setSearchUsers:[NSSet setWithObject:user] forSearchDirectory:fakeSearchDirectory];
    [self.userIDsTable replaceUserIDToDownload:user.remoteIdentifier withAssetIDToDownload:assetID];
    
    // when
    ZMTransportRequest *request = [self.sut.requestGenerators nextRequest];
    
    // then
    XCTAssertNotNil(request);
    XCTAssertEqual(request.method, ZMMethodGET);
    XCTAssertTrue(request.needsAuthentication);

    NSString *expectedPath = [self requestPathForAssetID:assetID ofUserID:user.remoteIdentifier];
    XCTAssertEqualObjects(request.path, expectedPath);
}

- (void)testThatNextRequestDoesNotCreatesARequestForAnAssetIDIfTheFirstRequestIsStillRunning
{
    // given
    ZMSearchUser *user = [self createSearchUser];
    NSUUID *assetID = [NSUUID createUUID];
    
    id fakeSearchDirectory = @"foo";
    
    [self.userIDsTable setSearchUsers:[NSSet setWithObject:user] forSearchDirectory:fakeSearchDirectory];
    [self.userIDsTable replaceUserIDToDownload:user.remoteIdentifier withAssetIDToDownload:assetID];
    
    // when
    ZMTransportRequest *request1 = [self.sut.requestGenerators nextRequest];
    ZMTransportRequest *request2 = [self.sut.requestGenerators nextRequest];
    
    // then
    XCTAssertNotNil(request1);
    XCTAssertNil(request2);
}

- (void)testThatNextRequestCreatesARequestForAnAssetIDThatWeAreNotAlreadyRequesting
{
    // given
    ZMSearchUser *user1 = [self createSearchUser];
    NSUUID *assetID1 = [NSUUID createUUID];
    ZMSearchUser *user2 = [self createSearchUser];
    NSUUID *assetID2 = [NSUUID createUUID];
    
    id fakeSearchDirectory1 = @"foo";
    id fakeSearchDirectory2 = @"foo2";
    
    
    [self.userIDsTable setSearchUsers:[NSSet setWithObject:user1] forSearchDirectory:fakeSearchDirectory1];
    [self.userIDsTable setSearchUsers:[NSSet setWithObject:user2] forSearchDirectory:fakeSearchDirectory2];

    [self.userIDsTable replaceUserIDToDownload:user1.remoteIdentifier withAssetIDToDownload:assetID1];
    [self.userIDsTable replaceUserIDToDownload:user2.remoteIdentifier withAssetIDToDownload:assetID2];

    ZMTransportRequest *request1 = [self.sut.requestGenerators nextRequest];
    
    // when
    ZMTransportRequest *request2 = [self.sut.requestGenerators nextRequest];

    
    // then
    XCTAssertNotNil(request2);
    XCTAssertEqual(request2.method, ZMMethodGET);
    XCTAssertTrue(request2.needsAuthentication);
    
    NSString *expectedPath1 = [self requestPathForAssetID:assetID1 ofUserID:user1.remoteIdentifier];
    NSString *expectedPath2 = [self requestPathForAssetID:assetID2 ofUserID:user2.remoteIdentifier];
    
    XCTAssertTrue([request1.path isEqualToString:expectedPath1] || [request1.path isEqualToString:expectedPath2]);
    XCTAssertTrue([request2.path isEqualToString:expectedPath1] || [request2.path isEqualToString:expectedPath2]);
    XCTAssertNotEqualObjects(request1.path, request2.path);

    
}

- (void)testThatCompletingARequestSetsTheImageDataOnTheCache
{
    // given
    NSData *imageData = [MessagingTest dataForResource:@"tiny" extension:@"jpg"];
    ZMSearchUser *user1 = [self createSearchUser];
    NSUUID *assetID1 = [NSUUID createUUID];
    
    id fakeSearchDirectory1 = @"foo";
    
    [self.userIDsTable setSearchUsers:[NSSet setWithObject:user1] forSearchDirectory:fakeSearchDirectory1];
    [self.userIDsTable replaceUserIDToDownload:user1.remoteIdentifier withAssetIDToDownload:assetID1];
    
    ZMTransportResponse *response = [[ZMTransportResponse alloc ] initWithImageData:imageData HTTPStatus:200 transportSessionError:nil headers:nil];
    
    // when
    ZMTransportRequest *request = [self.sut.requestGenerators nextRequest];
    XCTAssertEqualObjects(request.path, [self requestPathForAssetID:assetID1 ofUserID:user1.remoteIdentifier]);
    [request completeWithResponse:response];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertNotNil([self.imagesCache objectForKey:user1.remoteIdentifier]);
    AssertEqualData([self.imagesCache objectForKey:user1.remoteIdentifier], imageData);
}



- (void)testThatCompletingARequestRemovesTheUserFromTheTable
{
    // given
    NSData *imageData = [MessagingTest dataForResource:@"tiny" extension:@"jpg"];
    ZMSearchUser *user1 = [self createSearchUser];
    NSUUID *assetID1 = [NSUUID createUUID];
    
    id fakeSearchDirectory1 = @"foo";
    
    [self.userIDsTable setSearchUsers:[NSSet setWithObject:user1] forSearchDirectory:fakeSearchDirectory1];
    [self.userIDsTable replaceUserIDToDownload:user1.remoteIdentifier withAssetIDToDownload:assetID1];
    
    ZMTransportResponse *response = [[ZMTransportResponse alloc ] initWithImageData:imageData HTTPStatus:200 transportSessionError:nil headers:nil];
    
    // when
    ZMTransportRequest *request = [self.sut.requestGenerators nextRequest];
    XCTAssertEqualObjects(request.path, [self requestPathForAssetID:assetID1 ofUserID:user1.remoteIdentifier]);
    [request completeWithResponse:response];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(self.userIDsTable.allUserIDs.count, 0u);
    XCTAssertEqual(self.userIDsTable.allAssetIDs.count, 0u);
}


- (void)testThatFailingAnAssetRequestWithAPermanentErrorRemovesTheUsersFromTheTable
{
    // given
    ZMSearchUser *user1 = [self createSearchUser];
    NSUUID *assetID1 = [NSUUID createUUID];
    
    id fakeSearchDirectory1 = @"foo";
    
    [self.userIDsTable setSearchUsers:[NSSet setWithObject:user1] forSearchDirectory:fakeSearchDirectory1];
    [self.userIDsTable replaceUserIDToDownload:user1.remoteIdentifier withAssetIDToDownload:assetID1];
    
    // when
    ZMTransportRequest *request = [self.sut.requestGenerators nextRequest];
    XCTAssertEqualObjects(request.path, [self requestPathForAssetID:assetID1 ofUserID:user1.remoteIdentifier]);
    [request completeWithResponse:[ZMTransportResponse responseWithPayload:nil HTTPStatus:400 transportSessionError:nil]];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(self.userIDsTable.allAssetIDs.count, 0u);
    XCTAssertEqual(self.userIDsTable.allUserIDs.count, 0u);

}


- (void)testThatFailingARequestWithATemporaryErrorAllowsForThoseAssetIDsToBeDownloadedAgain
{
    // given
    ZMSearchUser *user1 = [self createSearchUser];
    NSUUID *assetID1 = [NSUUID createUUID];
    
    id fakeSearchDirectory1 = @"foo";
    
    [self.userIDsTable setSearchUsers:[NSSet setWithObject:user1] forSearchDirectory:fakeSearchDirectory1];
    [self.userIDsTable replaceUserIDToDownload:user1.remoteIdentifier withAssetIDToDownload:assetID1];
    
    // when
    ZMTransportRequest *request1 = [self.sut.requestGenerators nextRequest];
    [request1 completeWithResponse:[ZMTransportResponse responseWithPayload:nil HTTPStatus:500 transportSessionError:nil]];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // and when
    [self.userIDsTable setSearchUsers:[NSSet setWithObject:user1] forSearchDirectory:fakeSearchDirectory1];
    [self.userIDsTable replaceUserIDToDownload:user1.remoteIdentifier withAssetIDToDownload:assetID1];
    ZMTransportRequest *request2 = [self.sut.requestGenerators nextRequest];
    
    // then
    XCTAssertNotNil(request1);
    XCTAssertNotNil(request2);
}

- (void)testThatFailingARequestWithAPermanentErrorAllowsForThoseAssetIDsToBeDownloadedAgain
{
    // given
    ZMSearchUser *user1 = [self createSearchUser];
    NSUUID *assetID1 = [NSUUID createUUID];
    
    id fakeSearchDirectory1 = @"foo";
    
    [self.userIDsTable setSearchUsers:[NSSet setWithObject:user1] forSearchDirectory:fakeSearchDirectory1];
    [self.userIDsTable replaceUserIDToDownload:user1.remoteIdentifier withAssetIDToDownload:assetID1];
    
    // when
    ZMTransportRequest *request1 = [self.sut.requestGenerators nextRequest];
    [request1 completeWithResponse:[ZMTransportResponse responseWithPayload:nil HTTPStatus:404 transportSessionError:nil]];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // and when
    [self.userIDsTable setSearchUsers:[NSSet setWithObject:user1] forSearchDirectory:fakeSearchDirectory1];
    [self.userIDsTable replaceUserIDToDownload:user1.remoteIdentifier withAssetIDToDownload:assetID1];
    ZMTransportRequest *request2 = [self.sut.requestGenerators nextRequest];
    
    // then
    XCTAssertNotNil(request1);
    XCTAssertNotNil(request2);
}

- (void)testThatCompletingARequestDoesNotAllowForThoseAssetIDsToBeDownloadedAgain
{
    // given
    NSData *imageData = [MessagingTest dataForResource:@"tiny" extension:@"jpg"];
    ZMSearchUser *user1 = [self createSearchUser];
    NSUUID *assetID1 = [NSUUID createUUID];
    
    id fakeSearchDirectory1 = @"foo";
    
    [self.userIDsTable setSearchUsers:[NSSet setWithObject:user1] forSearchDirectory:fakeSearchDirectory1];
    [self.userIDsTable replaceUserIDToDownload:user1.remoteIdentifier withAssetIDToDownload:assetID1];
    ZMTransportResponse *response = [[ZMTransportResponse alloc ] initWithImageData:imageData HTTPStatus:200 transportSessionError:nil headers:nil];
    
    // when
    ZMTransportRequest *request1 = [self.sut.requestGenerators nextRequest];
    [request1 completeWithResponse:response];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // and when

    ZMTransportRequest *request2 = [self.sut.requestGenerators nextRequest];
    
    // then
    XCTAssertNotNil(request1);
    XCTAssertNil(request2);
}

- (void)testThatItNotifiesTheSearchUserWhenAnImageIsDownloaded
{
    // given
    NSData *imageData = [MessagingTest dataForResource:@"tiny" extension:@"jpg"];
    ZMSearchUser *user1 = [self createSearchUser];
    NSUUID *assetID1 = [NSUUID createUUID];
    
    id fakeSearchDirectory1 = @"foo";
    
    [self.userIDsTable setSearchUsers:[NSSet setWithObject:user1] forSearchDirectory:fakeSearchDirectory1];
    [self.userIDsTable replaceUserIDToDownload:user1.remoteIdentifier withAssetIDToDownload:assetID1];
    ZMTransportResponse *response = [[ZMTransportResponse alloc ] initWithImageData:imageData HTTPStatus:200 transportSessionError:nil headers:nil];
    
    // expect
    id listener = [OCMockObject mockForProtocol:@protocol(ZMUserObserver)];
    [(id<ZMUserObserver>)[listener expect] userDidChange:[OCMArg checkWithBlock:^BOOL(UserChangeInfo *note) {
        return note.imageSmallProfileDataChanged && note.user == user1;
    }]];
    id token = [ZMUser addUserObserver:listener forUsers:@[user1] managedObjectContext:self.uiMOC];
    
    // when
    ZMTransportRequest *request = [self.sut.requestGenerators nextRequest];
    [request completeWithResponse:response];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    [listener verify];
    [ZMUser removeUserObserverForToken:token];
}

@end
