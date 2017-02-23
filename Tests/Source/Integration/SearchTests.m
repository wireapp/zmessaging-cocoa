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
@import ZMCMockTransport;
@import ZMCDataModel;

#import "IntegrationTestBase.h"
#import "ZMSearchDirectory.h"
#import "ZMUserSession.h"


@interface SearchTests : IntegrationTestBase <ZMSearchResultObserver, ZMUserObserver>

@property (nonatomic) XCTestExpectation *expectation;
@property (nonatomic) NSMutableDictionary *searchResults;
@property (nonatomic) NSMutableArray *userNotifications;
@end

@implementation SearchTests


- (void)didReceiveSearchResult:(ZMSearchResult *)result forToken:(ZMSearchToken)searchToken;
{
    self.searchResults[searchToken] = result;
    [self.expectation fulfill];
}

- (void)setUp {
    [super setUp];
    self.searchResults = [NSMutableDictionary dictionary];
    self.userNotifications = [NSMutableArray array];
}

- (void)tearDown {
    self.userNotifications = nil;
    self.searchResults = nil;
    [super tearDown];
}


- (void)userDidChange:(UserChangeInfo *)note
{
    [self.userNotifications addObject:note];
}



- (void)testThatItConnectsToAUserInASearchResult
{
    // given
    NSString *userName = @"JohnnyMnemonic";
    __block MockUser *user;
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        user = [session insertUserWithName:userName];
        user.email = @"johnny@example.com";
        user.phone = @"";
        
        [self storeRemoteIDForObject:user];
    }];
    
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    ZMSearchDirectory *searchDirectory = [[ZMSearchDirectory alloc] initWithUserSession:self.userSession];
    [searchDirectory addSearchResultObserver:self];
    
    // find user
    self.expectation = [self expectationWithDescription:@"wait for search results"];
    ZMSearchToken token = [searchDirectory searchForUsersAndConversationsMatchingQueryString:@"Johnny"];

    XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0.5]);
    WaitForAllGroupsToBeEmpty(0.5);
    
    ZMSearchResult *searchResult = self.searchResults[token];
    XCTAssertNotNil(searchResult);
    ZMSearchUser *searchUser = searchResult.usersInDirectory.firstObject;
    XCTAssertNotNil(searchUser);
    
    // connect
    XCTestExpectation *waitForConnection = [self expectationWithDescription:@"wait for connection"];
    [searchUser connectWithMessageText:@"Hello" completionHandler:^{
        [waitForConnection fulfill];
    }];
    
    XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0.5]);
    WaitForAllGroupsToBeEmpty(0.5);
    
    // check local user and conversation
    ZMUser *newUser = [self userForMockUser:user];
    
    XCTAssertNotNil(newUser);
    XCTAssertEqualObjects(newUser.name, userName);
    
    ZMConversation *oneOnOneConversation = newUser.oneToOneConversation;
    XCTAssertNotNil(oneOnOneConversation);
    
    WaitForAllGroupsToBeEmpty(0.5);
    
    XCTAssertFalse(newUser.isConnected);
    XCTAssertFalse(newUser.isBlocked);
    XCTAssertFalse(newUser.isIgnored);
    XCTAssertFalse(newUser.isPendingApprovalBySelfUser);
    XCTAssertTrue(newUser.isPendingApprovalByOtherUser);
    
    
    // remote user accepts connection
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        [session remotelyAcceptConnectionToUser:user];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // check changes
    XCTAssertTrue(newUser.isConnected);
    XCTAssertFalse(newUser.isBlocked);
    XCTAssertFalse(newUser.isIgnored);
    XCTAssertFalse(newUser.isPendingApprovalBySelfUser);
    XCTAssertFalse(newUser.isPendingApprovalByOtherUser);

    XCTAssertTrue([oneOnOneConversation.activeParticipants containsObject:newUser]);

    [searchDirectory tearDown];
}

- (void)testThatItReturnsCommonUsersWithAUser
{
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    WaitForAllGroupsToBeEmpty(0.5);
    __block id<ZMCommonContactsSearchToken> receivedToken;
    __block NSOrderedSet *receivedUsers;
    
    // given
    ZMUser *user1 = [self userForMockUser:self.user1];
    id delegate = [OCMockObject mockForProtocol:@protocol(ZMCommonContactsSearchDelegate)];
    [[delegate expect] didReceiveCommonContactsUsers:[OCMArg checkWithBlock:^BOOL(id obj) {
        receivedUsers = obj;
        return YES;
    }] forSearchToken:[OCMArg checkWithBlock:^BOOL(id obj) {
        receivedToken = obj;
        return YES;
    }]];
    
    // when
    id<ZMCommonContactsSearchToken> token = [user1 searchCommonContactsInUserSession:self.userSession withDelegate:delegate];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    [delegate verify];
    XCTAssertEqual(token, receivedToken);
    NSArray *expectedUsers = @[self.user1, self.user2];
    for(MockUser *user in expectedUsers) {
        ZMUser *realUser = [self userForMockUser:user];
        
        XCTAssertTrue([receivedUsers containsObject:realUser]);
    }
}

- (void)testThatTheSelfUserCanAcceptAConnectionRequest
{
    // given
    NSUUID *userRemoteIdentifier = [NSUUID createUUID];
    __block MockUser *user;
    __block MockConnection *connection;
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        user = [session insertUserWithName:@"Johnny Mnemonic"];
        user.email = @"johnny@example.com";
        user.phone = @"";
        user.identifier = userRemoteIdentifier.transportString;

        // Send connection request
        connection = [session createConnectionRequestFromUser:user toUser:self.selfUser message:@"boo"];
        connection.status = @"pending";
    }];
    
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    WaitForAllGroupsToBeEmpty(0.5);

    NSArray *pendingConnections = [ZMConversationList pendingConnectionConversationsInUserSession:self.userSession];
    XCTAssertEqual(pendingConnections.count, 1u);

    // TODO: QUICK continue
}


- (void)testThatItNotifiesObserversWhenTheConnectionStatusChanges_InsertedUser
{
    // given
    NSString *userName = @"JohnnyMnemonic";
    __block MockUser *user;
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        user = [session insertUserWithName:userName];
        user.email = @"johnny@example.com";
        user.phone = @"";
        
        [self storeRemoteIDForObject:user];
    }];
    
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    ZMUser *newUser = [self userForMockUser:user];
    XCTAssertNil(newUser);
    
    ZMSearchDirectory *searchDirectory = [[ZMSearchDirectory alloc] initWithUserSession:self.userSession];
    [searchDirectory addSearchResultObserver:self];
    
    // find user
    self.expectation = [self expectationWithDescription:@"wait for search results"];
    ZMSearchToken token = [searchDirectory searchForUsersAndConversationsMatchingQueryString:@"Johnny"];
    
    XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0.5]);
    WaitForAllGroupsToBeEmpty(0.5);
    
    ZMSearchResult *searchResult = self.searchResults[token];
    ZMSearchUser *searchUser = searchResult.usersInDirectory.firstObject;
    
    id userToken = [UserChangeInfo addObserver:self forBareUser:searchUser];
    XCTAssertNil(searchUser.user);
    
    XCTAssertEqual(self.userNotifications.count, 0u);
    
    // connect
    XCTestExpectation *waitForConnection = [self expectationWithDescription:@"wait for connection"];
    [searchUser connectWithMessageText:@"Hello" completionHandler:^{
        [waitForConnection fulfill];
    }];
    
    XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0.5]);
    WaitForAllGroupsToBeEmpty(0.5);
    
    newUser = [self userForMockUser:user];
    XCTAssertNotNil(newUser);

    // then a userNotification should be sent
    XCTAssertEqual(self.userNotifications.count, 1u);
    
    UserChangeInfo *note = self.userNotifications.firstObject;
    XCTAssertEqualObjects(note.user, searchUser);
    XCTAssertTrue(note.connectionStateChanged);
    
    [searchDirectory tearDown];
    (void)userToken;
}

- (void)testThatItNotifiesObserversWhenTheConnectionStatusChanges_LocalUser
{
    // given
    
    NSString *userName = @"JohnnyMnemonic";
    __block MockUser *user;
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        user = [session insertUserWithName:userName];
        user.email = @"johnny@example.com";
        user.phone = @"";
        
        [self storeRemoteIDForObject:user];
        
        [self.groupConversation addUsersByUser:session.selfUser addedUsers:@[user]];
    }];
    
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    ZMUser *newUser = [self userForMockUser:user];
    XCTAssertNotNil(newUser);
    
    
    ZMSearchDirectory *searchDirectory = [[ZMSearchDirectory alloc] initWithUserSession:self.userSession];
    [searchDirectory addSearchResultObserver:self];
    
    // find user
    self.expectation = [self expectationWithDescription:@"wait for search results"];
    ZMSearchToken token = [searchDirectory searchForUsersAndConversationsMatchingQueryString:@"Johnny"];
    
    XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0.5]);
    WaitForAllGroupsToBeEmpty(0.5);
    
    ZMSearchResult *searchResult = self.searchResults[token];
    ZMSearchUser *searchUser = searchResult.usersInDirectory.firstObject;
    XCTAssertNotNil(searchUser.user);
    
    id userToken = [UserChangeInfo addObserver:self forBareUser:searchUser];

    
    // connect
    XCTestExpectation *waitForConnection = [self expectationWithDescription:@"wait for connection"];
    [searchUser connectWithMessageText:@"Hello" completionHandler:^{
        [waitForConnection fulfill];
    }];
    
    XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0.5]);
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then a userNotification should be sent
    XCTAssertEqual(self.userNotifications.count, 1u);
    
    UserChangeInfo *note1 = self.userNotifications.firstObject;
    XCTAssertEqualObjects(note1.user, searchUser);
    XCTAssertTrue(note1.connectionStateChanged);
    
    [searchDirectory tearDown];
    (void)userToken;
}

@end


@implementation SearchTests (SearchUserImages)

- (void)testThatItReturnsTheProfileImageForAConnectedSearchUser
{
    // given
    __block NSData *profileImageData;
    __block NSString *connectedUserName;
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        
        NOT_USED(session);
        profileImageData = [MockAsset assetInContext:self.mockTransportSession.managedObjectContext forID:self.user1.smallProfileImageIdentifier].data;
        XCTAssertNotNil(profileImageData);
        
        NSArray *names = [self.user1.name componentsSeparatedByString:@" "];
        connectedUserName = names.lastObject;
        XCTAssertNotNil(connectedUserName);
    }];
    
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    WaitForAllGroupsToBeEmpty(0.5);

    // when
    ZMSearchDirectory *searchDirectory = [[ZMSearchDirectory alloc] initWithUserSession:self.userSession];
    [searchDirectory addSearchResultObserver:self];
    
    self.expectation = [self expectationWithDescription:@"wait for search results"];
    ZMSearchToken token = [searchDirectory searchForUsersAndConversationsMatchingQueryString:connectedUserName];
    
    
    
    XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0.5]);
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    ZMSearchResult *searchResult = self.searchResults[token];
    XCTAssertNotNil(searchResult);
    ZMSearchUser *searchUser = searchResult.usersInContacts.firstObject;
    XCTAssertNotNil(searchUser);
    
    [searchUser requestSmallProfileImageInUserSession:self.userSession];
    WaitForAllGroupsToBeEmpty(0.5);
    
    AssertEqualData(searchUser.imageSmallProfileData, profileImageData);

    [searchDirectory tearDown];
}

- (void)testThatItReturnsTheProfileImageForAnUnconnectedSearchUser
{
    // given
    __block NSData *profileImageData;
    __block NSString *connectedUserName;
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        
        NOT_USED(session);
        
        profileImageData = [MockAsset assetInContext:self.mockTransportSession.managedObjectContext forID:self.user4.smallProfileImageIdentifier].data;
        XCTAssertNotNil(profileImageData);
        
        NSArray *names = [self.user4.name componentsSeparatedByString:@" "];
        connectedUserName = names.lastObject;
        XCTAssertNotNil(connectedUserName);
    }];
    
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    WaitForAllGroupsToBeEmpty(0.5);
    
    // when
    ZMSearchDirectory *searchDirectory = [[ZMSearchDirectory alloc] initWithUserSession:self.userSession];
    [searchDirectory addSearchResultObserver:self];
    
    self.expectation = [self expectationWithDescription:@"wait for search results"];
    ZMSearchToken token = [searchDirectory searchForUsersAndConversationsMatchingQueryString:connectedUserName];
    
    XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0.5]);
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    ZMSearchResult *searchResult = self.searchResults[token];
    XCTAssertNotNil(searchResult);
    ZMSearchUser *searchUser = searchResult.usersInDirectory.firstObject;
    XCTAssertNotNil(searchUser);
    
    AssertEqualData(searchUser.imageSmallProfileData, profileImageData);

    [searchDirectory tearDown];
}


- (void)testThatItNotifiesWhenANewImageIsAvailableForAnUnconnectedSearchUser
{
    // given
    __block NSData *profileImageData;
    __block NSString *connectedUserName;
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        
        NOT_USED(session);
        
        profileImageData = [MockAsset assetInContext:self.mockTransportSession.managedObjectContext forID:self.user4.smallProfileImageIdentifier].data;
        XCTAssertNotNil(profileImageData);
        
        NSArray *names = [self.user4.name componentsSeparatedByString:@" "];
        connectedUserName = names.lastObject;
        XCTAssertNotNil(connectedUserName);
    }];
    
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    WaitForAllGroupsToBeEmpty(0.5);
    
    // expect
    id searchListener = [OCMockObject mockForProtocol:@protocol(ZMSearchResultObserver)];
    id userListener = [OCMockObject mockForProtocol:@protocol(ZMUserObserver)];
    
    XCTestExpectation *expectation = [self expectationWithDescription:@"image new"];
    [(id<ZMUserObserver>)[userListener expect] userDidChange:[OCMArg checkWithBlock:^BOOL(UserChangeInfo *note) {
        [expectation fulfill];
        return note.imageSmallProfileDataChanged;
    }]];
    
    __block dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    // delay mock transport session response
    self.mockTransportSession.responseGeneratorBlock = ^ZMTransportResponse *(ZMTransportRequest *request) {
        if([request.path hasPrefix:@"/asset"]) {
            dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
        }
        return nil;
    };
    
    __block id token;
    [[searchListener expect] didReceiveSearchResult:[OCMArg checkWithBlock:^BOOL(ZMSearchResult *result) {
        XCTAssertEqual(result.usersInDirectory.count, 1u);
        ZMSearchUser *user = result.usersInDirectory.firstObject;
        XCTAssertNil(user.imageSmallProfileData);
        token = [UserChangeInfo addObserver:userListener forBareUser:user];
        dispatch_semaphore_signal(sem);
        return YES;
    }] forToken:OCMOCK_ANY];
    
    // when
    ZMSearchDirectory *searchDirectory = [[ZMSearchDirectory alloc] initWithUserSession:self.userSession];
    [searchDirectory addSearchResultObserver:searchListener];
    [searchDirectory searchForUsersAndConversationsMatchingQueryString:connectedUserName];
    
    XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0.5]);
    
    // then
    [searchListener verify];
    [userListener verify];
    
    [searchDirectory tearDown];
}

- (void)testThatItReturnsNoImageIfTheUnconnectedSearchUserHasNoImage
{
    // given

    __block NSString *connectedUserName;
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        
        NOT_USED(session);
        
        NSArray *names = [self.user5.name componentsSeparatedByString:@" "];
        connectedUserName = names.lastObject;
        XCTAssertNotNil(connectedUserName);
    }];
    
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    WaitForAllGroupsToBeEmpty(0.5);
    
    // when
    ZMSearchDirectory *searchDirectory = [[ZMSearchDirectory alloc] initWithUserSession:self.userSession];
    [searchDirectory addSearchResultObserver:self];
    
    self.expectation = [self expectationWithDescription:@"wait for search results"];
    ZMSearchToken token = [searchDirectory searchForUsersAndConversationsMatchingQueryString:connectedUserName];
    
    XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0.5]);
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    ZMSearchResult *searchResult = self.searchResults[token];
    XCTAssertNotNil(searchResult);
    ZMSearchUser *searchUser = searchResult.usersInDirectory.firstObject;
    XCTAssertNotNil(searchUser);
    
    XCTAssertNil(searchUser.imageSmallProfileData);
    [searchDirectory tearDown];
}


- (void)testThatItSetsTheMediumImageForAnUnconnectedSearchUser
{
    // given
    __block NSData *profileImageData;
    __block NSString *unConnectedUserName;
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        
        NOT_USED(session);
        profileImageData = [MockAsset assetInContext:self.mockTransportSession.managedObjectContext forID:self.user4.mediumImageIdentifier].data;
        XCTAssertNotNil(profileImageData);
        
        NSArray *names = [self.user4.name componentsSeparatedByString:@" "];
        unConnectedUserName = names.lastObject;
        XCTAssertNotNil(unConnectedUserName);
    }];
    
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    WaitForAllGroupsToBeEmpty(0.5);
    

    // search for user
    ZMSearchDirectory *searchDirectory = [[ZMSearchDirectory alloc] initWithUserSession:self.userSession];
    [searchDirectory addSearchResultObserver:self];
    
    self.expectation = [self expectationWithDescription:@"wait for search results"];
    ZMSearchToken token = [searchDirectory searchForUsersAndConversationsMatchingQueryString:unConnectedUserName];
    XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0.5]);

    WaitForAllGroupsToBeEmpty(0.5);
    
    ZMSearchResult *searchResult = self.searchResults[token];
    XCTAssertNotNil(searchResult);
    ZMSearchUser *searchUser = searchResult.usersInDirectory.firstObject;
    XCTAssertNotNil(searchUser);
    
    NSCache *mediumAssetIDCache = [ZMSearchUser searchUserToMediumAssetIDCache];
    NSCache *mediumImageCache = [ZMSearchUser searchUserToMediumImageCache];
    NSUUID *userRemoteIdentifier = [NSUUID uuidWithTransportString:self.user4.identifier];
    NSUUID *mediumImageIdentifier = [NSUUID uuidWithTransportString:self.user4.mediumImageIdentifier];

    XCTAssertEqualObjects([mediumAssetIDCache objectForKey:userRemoteIdentifier], mediumImageIdentifier);
    XCTAssertNil([mediumImageCache objectForKey:userRemoteIdentifier]);

    // when requesting medium image
    [self.userSession performChanges:^{
        [searchUser requestMediumProfileImageInUserSession:self.userSession];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    AssertEqualData(searchUser.imageMediumData, profileImageData);
    XCTAssertEqualObjects([mediumAssetIDCache objectForKey:userRemoteIdentifier], mediumImageIdentifier);
    XCTAssertEqualObjects([mediumImageCache objectForKey:userRemoteIdentifier], profileImageData);

    [searchDirectory tearDown];
}


- (void)testThatItRefetchesTheSearchUserIfTheMediumImageDataGotDeletedFromTheCache
{
    // given
    __block NSData *profileImageData;
    __block NSString *unConnectedUserName;
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        
        NOT_USED(session);
        profileImageData = [MockAsset assetInContext:self.mockTransportSession.managedObjectContext forID:self.user4.mediumImageIdentifier].data;
        XCTAssertNotNil(profileImageData);
        
        NSArray *names = [self.user4.name componentsSeparatedByString:@" "];
        unConnectedUserName = names.lastObject;
        XCTAssertNotNil(unConnectedUserName);
    }];
    
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    WaitForAllGroupsToBeEmpty(0.5);
    
    
    NSCache *mediumAssetIDCache = [ZMSearchUser searchUserToMediumAssetIDCache];
    NSCache *mediumImageCache = [ZMSearchUser searchUserToMediumImageCache];
    NSUUID *userRemoteIdentifier = [NSUUID uuidWithTransportString:self.user4.identifier];
    NSUUID *mediumImageIdentifier = [NSUUID uuidWithTransportString:self.user4.mediumImageIdentifier];
    ZMSearchUser *searchUser1;
    ZMSearchUser *searchUser2;

    // (1)First Search
    {
        // search for user
        ZMSearchDirectory *searchDirectory = [[ZMSearchDirectory alloc] initWithUserSession:self.userSession];
        [searchDirectory addSearchResultObserver:self];
        
        self.expectation = [self expectationWithDescription:@"wait for search results"];
        ZMSearchToken token = [searchDirectory searchForUsersAndConversationsMatchingQueryString:unConnectedUserName];
        XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0.5]);
        
        WaitForAllGroupsToBeEmpty(0.5);
        
        ZMSearchResult *searchResult = self.searchResults[token];
        XCTAssertNotNil(searchResult);
        searchUser1 = searchResult.usersInDirectory.firstObject;
        XCTAssertNotNil(searchUser1);
        
        XCTAssertEqualObjects([mediumAssetIDCache objectForKey:userRemoteIdentifier], mediumImageIdentifier);
        XCTAssertNil([mediumImageCache objectForKey:userRemoteIdentifier]);
        
        // when requesting medium image
        [self.userSession performChanges:^{
            [searchUser1 requestMediumProfileImageInUserSession:self.userSession];
        }];
        WaitForAllGroupsToBeEmpty(0.5);
        
        // then
        AssertEqualData(searchUser1.imageMediumData, profileImageData);
        XCTAssertEqualObjects([mediumAssetIDCache objectForKey:userRemoteIdentifier], mediumImageIdentifier);
        XCTAssertEqualObjects([mediumImageCache objectForKey:userRemoteIdentifier], profileImageData);
        [searchDirectory tearDown];
    }
    
    // (2) remove mediumData and assetID from caches (the cache is emptied due to memory limitations)
    {
        [mediumImageCache removeObjectForKey:userRemoteIdentifier];
        [mediumAssetIDCache removeObjectForKey:userRemoteIdentifier];
        
        XCTAssertNil([mediumAssetIDCache objectForKey:userRemoteIdentifier]);
        XCTAssertNil([mediumImageCache objectForKey:userRemoteIdentifier]);
    }
    
    // (3) Second Search
    {
        // search for user
        ZMSearchDirectory *searchDirectory = [[ZMSearchDirectory alloc] initWithUserSession:self.userSession];
        [searchDirectory addSearchResultObserver:self];
        
        self.expectation = [self expectationWithDescription:@"wait for search results"];
        ZMSearchToken token = [searchDirectory searchForUsersAndConversationsMatchingQueryString:unConnectedUserName];
        XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0.5]);
        
        WaitForAllGroupsToBeEmpty(0.5);
        
        ZMSearchResult *searchResult = self.searchResults[token];
        XCTAssertNotNil(searchResult);
        searchUser2 = searchResult.usersInDirectory.firstObject;
        XCTAssertNotNil(searchUser2);
        
        XCTAssertEqualObjects([mediumAssetIDCache objectForKey:userRemoteIdentifier], mediumImageIdentifier);
        XCTAssertNil([mediumImageCache objectForKey:userRemoteIdentifier]);
        
        // when requesting medium image
        [self.userSession performChanges:^{
            [searchUser2 requestMediumProfileImageInUserSession:self.userSession];
        }];
        WaitForAllGroupsToBeEmpty(0.5);
        
        // then
        AssertEqualData(searchUser2.imageMediumData, profileImageData);
        XCTAssertEqualObjects([mediumAssetIDCache objectForKey:userRemoteIdentifier], mediumImageIdentifier);
        XCTAssertEqualObjects([mediumImageCache objectForKey:userRemoteIdentifier], profileImageData);
        
        XCTAssertNotEqual(searchUser1, searchUser2);
        XCTAssertEqualObjects(searchUser1.remoteIdentifier, searchUser2.remoteIdentifier);

        [searchDirectory tearDown];
    }
}


- (void)testThatItRefetchesTheSearchUserIfTheMediumAssetIDIsNotSet
{
    // given
    __block NSData *profileImageData;
    __block NSString *unConnectedUserName;
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        
        NOT_USED(session);
        profileImageData = [MockAsset assetInContext:self.mockTransportSession.managedObjectContext forID:self.user4.mediumImageIdentifier].data;
        XCTAssertNotNil(profileImageData);
        
        NSArray *names = [self.user4.name componentsSeparatedByString:@" "];
        unConnectedUserName = names.lastObject;
        XCTAssertNotNil(unConnectedUserName);
    }];
    
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    WaitForAllGroupsToBeEmpty(0.5);
    
    
    NSCache *mediumAssetIDCache = [ZMSearchUser searchUserToMediumAssetIDCache];
    NSCache *mediumImageCache = [ZMSearchUser searchUserToMediumImageCache];
    NSUUID *userRemoteIdentifier = [NSUUID uuidWithTransportString:self.user4.identifier];
    NSUUID *mediumImageIdentifier = [NSUUID uuidWithTransportString:self.user4.mediumImageIdentifier];
    ZMSearchUser *searchUser1;
    
    // (1)First Search
    {
        // search for user
        ZMSearchDirectory *searchDirectory = [[ZMSearchDirectory alloc] initWithUserSession:self.userSession];
        [searchDirectory addSearchResultObserver:self];
        
        self.expectation = [self expectationWithDescription:@"wait for search results"];
        ZMSearchToken token = [searchDirectory searchForUsersAndConversationsMatchingQueryString:unConnectedUserName];
        XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0.5]);
        
        WaitForAllGroupsToBeEmpty(0.5);
        
        ZMSearchResult *searchResult = self.searchResults[token];
        XCTAssertNotNil(searchResult);
        searchUser1 = searchResult.usersInDirectory.firstObject;
        XCTAssertNotNil(searchUser1);
        
        XCTAssertEqualObjects([mediumAssetIDCache objectForKey:userRemoteIdentifier], mediumImageIdentifier);
        XCTAssertNil([mediumImageCache objectForKey:userRemoteIdentifier]);
        [searchDirectory tearDown];
    }
    
    // (2) remove mediumAssetID from Cache
    {
        [mediumAssetIDCache removeObjectForKey:userRemoteIdentifier];
        XCTAssertNil(searchUser1.mediumAssetID);
    }
    
    // (3) when requesting medium image
    {
        [self.userSession performChanges:^{
            [searchUser1 requestMediumProfileImageInUserSession:self.userSession];
        }];
        WaitForAllGroupsToBeEmpty(0.5);
        
        // then it refetches the user and sets the mediumAssetID to fetch the data
        AssertEqualData(searchUser1.imageMediumData, profileImageData);
        XCTAssertEqualObjects([mediumAssetIDCache objectForKey:userRemoteIdentifier], mediumImageIdentifier);
        XCTAssertEqualObjects([mediumImageCache objectForKey:userRemoteIdentifier], profileImageData);
    }
}

- (void)testThatItNotifiesWhenANewMediumImageIsAvailableForAnUnconnectedSearchUser
{
    // given
    
    id userListener = [OCMockObject mockForProtocol:@protocol(ZMUserObserver)];
    id searchListener = [OCMockObject mockForProtocol:@protocol(ZMSearchResultObserver)];

    __block NSData *profileImageData;
    __block NSString *unConnectedUserName;
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        
        NOT_USED(session);
        profileImageData = [MockAsset assetInContext:self.mockTransportSession.managedObjectContext forID:self.user4.mediumImageIdentifier].data;
        XCTAssertNotNil(profileImageData);
        
        NSArray *names = [self.user4.name componentsSeparatedByString:@" "];
        unConnectedUserName = names.lastObject;
        XCTAssertNotNil(unConnectedUserName);
    }];
    
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    WaitForAllGroupsToBeEmpty(0.5);
    
    __block ZMSearchUser *searchUser;
    __block id userToken;
    __block ZMSearchDirectory *searchDirectory;
    
    // search for user
    {
        XCTestExpectation *expectation1 = [self expectationWithDescription:@"wait for search results"];

        [(id<ZMUserObserver>)[userListener expect] userDidChange:[OCMArg checkWithBlock:^BOOL(UserChangeInfo *note) {
            [expectation1 fulfill];
            return note.imageSmallProfileDataChanged;
        }]];
        
        __block dispatch_semaphore_t sem = dispatch_semaphore_create(0);
        __block BOOL didRun = NO;
        // delay mock transport session response
        self.mockTransportSession.responseGeneratorBlock = ^ZMTransportResponse *(ZMTransportRequest *request) {
            if([request.path hasPrefix:@"/asset"] && !didRun) {
                didRun = YES;
                dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
            }
            return nil;
        };
        
        [[searchListener expect] didReceiveSearchResult:[OCMArg checkWithBlock:^BOOL(ZMSearchResult *result) {
            XCTAssertEqual(result.usersInDirectory.count, 1u);
            searchUser = result.usersInDirectory.firstObject;
            userToken = [UserChangeInfo addObserver:userListener forBareUser:searchUser];
            dispatch_semaphore_signal(sem);
            return YES;
        }] forToken:OCMOCK_ANY];
        
        searchDirectory = [[ZMSearchDirectory alloc] initWithUserSession:self.userSession];
        [searchDirectory addSearchResultObserver:searchListener];
        
        [searchDirectory searchForUsersAndConversationsMatchingQueryString:unConnectedUserName];
        XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0.5]);
        
        WaitForAllGroupsToBeEmpty(0.5);
    }
    
    // when requesting medium image
    {
        // expect
        XCTestExpectation *expectation2 = [self expectationWithDescription:@"image received"];

        [(id<ZMUserObserver>)[userListener expect] userDidChange:[OCMArg checkWithBlock:^BOOL(UserChangeInfo *note) {
            [expectation2 fulfill];
            return note.imageMediumDataChanged;
        }]];
        
        // when
        [self.userSession performChanges:^{
            [searchUser requestMediumProfileImageInUserSession:self.userSession];
        }];
        
        XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0.5]);
        WaitForAllGroupsToBeEmpty(1.0);
    }
    
    // then
    [searchDirectory tearDown];
    [userListener verify];
}

- (void)DISABLED_testThatItDoesNotDownloadCachedImagesAgainButNotifiesObservers
{
    // given
    
    id userListener = [OCMockObject mockForProtocol:@protocol(ZMUserObserver)];
    id searchListener = [OCMockObject mockForProtocol:@protocol(ZMSearchResultObserver)];
    
    __block NSData *profileImageData;
    __block NSString *unConnectedUserName;
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        
        NOT_USED(session);
        profileImageData = [MockAsset assetInContext:self.mockTransportSession.managedObjectContext forID:self.user4.mediumImageIdentifier].data;
        XCTAssertNotNil(profileImageData);
        
        NSArray *names = [self.user4.name componentsSeparatedByString:@" "];
        unConnectedUserName = names.lastObject;
        XCTAssertNotNil(unConnectedUserName);
    }];
    
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    WaitForAllGroupsToBeEmpty(0.5);
    
    __block ZMSearchUser *searchUser;
    __block id userToken;
    
    // search for user
    {
        XCTestExpectation *expectation1 = [self expectationWithDescription:@"wait for search results"];
        
        [(id<ZMUserObserver>)[userListener expect] userDidChange:[OCMArg checkWithBlock:^BOOL(UserChangeInfo *note) {
            [expectation1 fulfill];
            return note.imageSmallProfileDataChanged;
        }]];
        
        __block dispatch_semaphore_t sem = dispatch_semaphore_create(0);
        __block BOOL didRun = NO;
        // delay mock transport session response
        self.mockTransportSession.responseGeneratorBlock = ^ZMTransportResponse *(ZMTransportRequest *request) {
            if([request.path hasPrefix:@"/asset"] && !didRun) {
                didRun = YES;
                dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
            }
            return nil;
        };
        
        [[searchListener expect] didReceiveSearchResult:[OCMArg checkWithBlock:^BOOL(ZMSearchResult *result) {
            XCTAssertEqual(result.usersInDirectory.count, 1u);
            searchUser = result.usersInDirectory.firstObject;
            userToken = [UserChangeInfo addObserver:userListener forBareUser:searchUser];
            dispatch_semaphore_signal(sem);
            return YES;
        }] forToken:OCMOCK_ANY];
        
        ZMSearchDirectory *searchDirectory = [[ZMSearchDirectory alloc] initWithUserSession:self.userSession];
        [searchDirectory addSearchResultObserver:searchListener];
        
        [searchDirectory searchForUsersAndConversationsMatchingQueryString:unConnectedUserName];
        XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0.5]);
        
        WaitForAllGroupsToBeEmpty(0.5);
        [searchDirectory tearDown];
    }
    
    // when requesting medium image
    {
        // expect
        XCTestExpectation *expectation2 = [self expectationWithDescription:@"image received"];
        
        [(id<ZMUserObserver>)[userListener expect] userDidChange:[OCMArg checkWithBlock:^BOOL(UserChangeInfo *note) {
            [expectation2 fulfill];
            return note.imageMediumDataChanged;
        }]];
        
        // when
        [self.mockTransportSession resetReceivedRequests];
        [self.userSession performChanges:^{
            [searchUser requestMediumProfileImageInUserSession:self.userSession];
        }];
        
        XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0.5]);
        WaitForAllGroupsToBeEmpty(1.0);
        XCTAssertEqual(self.mockTransportSession.receivedRequests.count, 1u);

    }
    
    // when requesting the image again
    {
        XCTestExpectation *expectation3 = [self expectationWithDescription:@"resend image notification"];
        [(id<ZMUserObserver>)[userListener expect] userDidChange:[OCMArg checkWithBlock:^BOOL(UserChangeInfo *note) {
            [expectation3 fulfill];
            return note.imageMediumDataChanged;
        }]];
        
        // when
        [self.mockTransportSession resetReceivedRequests];
        [self.userSession performChanges:^{
            [searchUser requestMediumProfileImageInUserSession:self.userSession];
        }];
        
        XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0.5]);
        WaitForAllGroupsToBeEmpty(1.0);
        XCTAssertEqual(self.mockTransportSession.receivedRequests.count, 0u);
    }
    
    
    // then
    [userListener verify];
}

@end
