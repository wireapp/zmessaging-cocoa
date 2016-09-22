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
@import ZMCDataModel;

#import "MessagingTest.h"
#import "ZMUserSession+Internal.h"
#import <zmessaging/zmessaging-Swift.h>

@interface ZMSearchUserTests : MessagingTest <ZMUserObserver>
@property (nonatomic) NSMutableArray *userNotifications;
@end

@implementation ZMSearchUserTests

- (void)setUp {
    [super setUp];
    
    self.syncMOC.zm_userImageCache = [[UserImageLocalCache alloc] init];
    self.uiMOC.zm_userImageCache = self.syncMOC.zm_userImageCache;

    self.userNotifications = [NSMutableArray array];
}

- (void)tearDown {
    self.userNotifications = nil;
    [super tearDown];
}

- (void)userDidChange:(UserChangeInfo *)note
{
    [self.userNotifications addObject:note];
}

- (void)testThatItComparesEqualBasedOnRemoteID;
{
    // given
    NSUUID *remoteIDA = [NSUUID createUUID];
    NSUUID *remoteIDB = [NSUUID createUUID];
    ZMSearchUser *user1 = [[ZMSearchUser alloc] initWithName:@"A" accentColor:ZMAccentColorStrongLimeGreen remoteID:remoteIDA user:nil syncManagedObjectContext: self.syncMOC uiManagedObjectContext:self.uiMOC];


    // (1)
    ZMSearchUser *user2 = [[ZMSearchUser alloc] initWithName:@"B" accentColor:ZMAccentColorSoftPink remoteID:remoteIDA user:nil syncManagedObjectContext: self.syncMOC uiManagedObjectContext:self.uiMOC];

    XCTAssertEqualObjects(user1, user2);
    XCTAssertEqual(user1.hash, user2.hash);
    
    // (2)
    ZMSearchUser *user3 = [[ZMSearchUser alloc] initWithName:@"A" accentColor:ZMAccentColorStrongLimeGreen remoteID:remoteIDB user:nil syncManagedObjectContext: self.syncMOC uiManagedObjectContext:self.uiMOC];

    XCTAssertNotEqualObjects(user1, user3);
}

- (void)testThatItComparesEqualBasedOnContactWhenRemoteIDIsNil
{
    // Given
    ZMAddressBookContact *contact1 = [[ZMAddressBookContact alloc] init];
    contact1.firstName = @"A";
    
    ZMAddressBookContact *contact2  =[[ZMAddressBookContact alloc] init];
    contact2.firstName = @"B";
    
    OCMockObject *userSession = [OCMockObject niceMockForClass:ZMUserSession.class];
    [[[userSession stub] andReturn:self.syncMOC] syncManagedObjectContext];
    
    ZMSearchUser *user1 = [[ZMSearchUser alloc] initWithContact:contact1 user:nil userSession:(ZMUserSession *)userSession];
    ZMSearchUser *user2 = [[ZMSearchUser alloc] initWithContact:contact1 user:nil userSession:(ZMUserSession *)userSession];
    ZMSearchUser *user3 = [[ZMSearchUser alloc] initWithContact:contact2 user:nil userSession:(ZMUserSession *)userSession];
    
    // Then
    XCTAssertEqualObjects(user1, user2);
    XCTAssertNotEqualObjects(user1, user3);
}

- (void)testThatItHasAllDataItWasInitializedWith
{
    // given
    NSString *name = @"John Doe";
    NSUUID *remoteID = [NSUUID createUUID];
    
    // when
    ZMSearchUser *searchUser = [[ZMSearchUser alloc] initWithName:name accentColor:ZMAccentColorStrongLimeGreen remoteID:remoteID user:nil syncManagedObjectContext: self.syncMOC uiManagedObjectContext:self.uiMOC];

    
    // then
    XCTAssertEqualObjects(searchUser.displayName, name);
    XCTAssertEqualObjects(searchUser.remoteIdentifier, remoteID);
    XCTAssertEqual(searchUser.accentColorValue, ZMAccentColorStrongLimeGreen);
    XCTAssertEqual(searchUser.isConnected, NO);
    XCTAssertNil(searchUser.imageMediumData);
    XCTAssertNil(searchUser.imageSmallProfileData);
    XCTAssertNil(searchUser.user);
}


- (void)testThatItUsesDataFromAUserIfItHasOne
{
    // given
    ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    user.name = @"Actual name";
    user.accentColorValue = ZMAccentColorVividRed;
    user.connection = [ZMConnection insertNewObjectInManagedObjectContext:self.uiMOC];
    user.connection.status = ZMConnectionStatusAccepted;
    user.remoteIdentifier = [NSUUID createUUID];
    user.imageMediumData = [@"image medium data" dataUsingEncoding:NSUTF8StringEncoding];
    user.imageSmallProfileData = [@"image small profile data" dataUsingEncoding:NSUTF8StringEncoding];
    [self.uiMOC saveOrRollback];
    
    // when
    ZMSearchUser *searchUser = [[ZMSearchUser alloc] initWithName:@"Wrong name" accentColor:ZMAccentColorStrongLimeGreen remoteID:[NSUUID createUUID] user:user syncManagedObjectContext: self.syncMOC uiManagedObjectContext:self.uiMOC];

    
    // then
    XCTAssertEqualObjects(searchUser.name, user.name);
    XCTAssertEqualObjects(searchUser.displayName, user.displayName);
    XCTAssertEqual(searchUser.accentColorValue, user.accentColorValue);
    XCTAssertEqual(searchUser.isConnected, user.isConnected);
    XCTAssertEqualObjects(searchUser.remoteIdentifier, user.remoteIdentifier);
    XCTAssertEqualObjects(searchUser.imageMediumData, user.imageMediumData);
    XCTAssertEqualObjects(searchUser.imageSmallProfileData, user.imageSmallProfileData);
    XCTAssertEqual(searchUser.user, user);
}

- (void)testThatItCreatesSearchUserWhenInitialisedWithUser
{
    // given
    ZMUser *user1 = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    NSString *remoteIdentifierString1 = [NSUUID createUUID].UUIDString;
    user1.remoteIdentifier = remoteIdentifierString1.UUID;
    
    ZMUser *commonUser = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    NSString *remoteIdentifierString2 = [NSUUID createUUID].UUIDString;
    commonUser.remoteIdentifier = remoteIdentifierString2.UUID;
    
    OCMockObject *userSession = [OCMockObject niceMockForClass:ZMUserSession.class];
    [[[userSession stub] andReturn:self.uiMOC] managedObjectContext];
    
    OCMockObject *userClassMock = [OCMockObject niceMockForClass:ZMUser.class];
    [[[userClassMock stub] andReturn:[[NSOrderedSet alloc] initWithObject:user1]] usersWithRemoteIDs:OCMOCK_ANY inContext:OCMOCK_ANY];
    
    NSDictionary *payload = @{ZMSearchUserMutualFriendsKey: @[remoteIdentifierString2], ZMSearchUserTotalMutualFriendsKey: @1};
    self.uiMOC.commonConnectionsForUsers = @{ user1.remoteIdentifier : [[ZMSuggestedUserCommonConnections alloc] initWithPayload:payload] };
    [self.uiMOC saveOrRollback];
    
    // when
    ZMSearchUser *searchUser = [ZMSearchUser usersWithUsers:@[user1] userSession:(ZMUserSession *)userSession].firstObject;

    // then
    XCTAssertEqualObjects(searchUser.user, user1);
    XCTAssertEqual([(ZMUser *)searchUser.topCommonConnections.firstObject remoteIdentifier], commonUser.remoteIdentifier);
    XCTAssertEqual(searchUser.topCommonConnections.count, 1u);
}

@end


@implementation ZMSearchUserTests (Connections)

- (void)testThatItCreatesAConnectionForASeachUserThatHasNoLocalUser;
{
    // given
    
    ZMSearchUser *searchUser = [[ZMSearchUser alloc] initWithName:@"Hans" accentColor:ZMAccentColorStrongLimeGreen remoteID:[NSUUID createUUID] user:nil syncManagedObjectContext: self.syncMOC uiManagedObjectContext:self.uiMOC];

    
    OCMockObject *userSession = [OCMockObject niceMockForClass:ZMUserSession.class];
    [[[userSession stub] andReturn:self.syncMOC] syncManagedObjectContext];
    [[[userSession stub] andReturn:self.uiMOC] managedObjectContext];
    searchUser.remoteIdentifier = [NSUUID createUUID];
    XCTAssertFalse(searchUser.isPendingApprovalByOtherUser);
    
    // expect
    XCTestExpectation *callbackCalled = [self expectationWithDescription:@"Callback called"];
    [searchUser connectWithMessageText:@"Hey!" completionHandler:^{
        [callbackCalled fulfill];
        NSArray *connections = [self.uiMOC executeFetchRequestOrAssert:[ZMConnection sortedFetchRequest]];
        XCTAssertEqual(connections.count, 1u);
        ZMConnection *connection = connections[0];
        ZMUser *user = connection.to;
        XCTAssertNotNil(user);
        XCTAssertEqualObjects(user.name, @"Hans");
        XCTAssertEqual(user.accentColorValue, ZMAccentColorStrongLimeGreen);
        XCTAssertEqualObjects(user.remoteIdentifier, searchUser.remoteIdentifier);
        XCTAssertNotNil(connection.conversation);
        XCTAssertEqual(connection.status, ZMConnectionStatusSent);
        XCTAssertEqualObjects(connection.message, @"Hey!");
        XCTAssertTrue(searchUser.isPendingApprovalByOtherUser);
    }];
    XCTAssert([self waitForCustomExpectationsWithTimeout:0.5]);
}

- (void)testThatItNotifiesObserversWhenConnectingToASearchUserThatHasNoLocalUser;
{
    // given
    
    ZMSearchUser *searchUser = [[ZMSearchUser alloc] initWithName:@"Hans" accentColor:ZMAccentColorStrongLimeGreen remoteID:[NSUUID createUUID] user:nil syncManagedObjectContext: self.syncMOC uiManagedObjectContext:self.uiMOC];
    searchUser.remoteIdentifier = [NSUUID createUUID];
    XCTAssertFalse(searchUser.isPendingApprovalByOtherUser);
    
    id userToken = [ZMUser addUserObserver:self forUsers:@[searchUser] managedObjectContext:self.uiMOC];
    
    // expect
    XCTestExpectation *callbackCalled = [self expectationWithDescription:@"Callback called"];
    
    // when
    [searchUser connectWithMessageText:@"Hey!" completionHandler:^{
        [callbackCalled fulfill];
    }];
    XCTAssert([self waitForCustomExpectationsWithTimeout:0.5]);
    
    // then
    XCTAssertEqual(self.userNotifications.count, 1u);
    UserChangeInfo *note = self.userNotifications.firstObject;
    XCTAssertEqualObjects(note.user, searchUser);
    XCTAssertTrue(note.connectionStateChanged);
    
    [ZMUser removeUserObserverForToken:userToken];
}


- (void)testThatItDoesNotConnectIfTheSearchUserHasNoRemoteIdentifier;
{
    // given
    
    ZMSearchUser *user = [[ZMSearchUser alloc] initWithName:@"Hans" accentColor:ZMAccentColorStrongLimeGreen remoteID:[NSUUID createUUID] user:nil syncManagedObjectContext: self.syncMOC uiManagedObjectContext:self.uiMOC];

    user.remoteIdentifier = nil;
    
    // expect
    XCTestExpectation *callbackCalled = [self expectationWithDescription:@"Callback called"];
    [user connectWithMessageText:@"Hey!" completionHandler:^{
        [callbackCalled fulfill];
    }];
    XCTAssert([self waitForCustomExpectationsWithTimeout:0.5]);
    
    // then
    XCTAssertFalse(self.uiMOC.hasChanges);
    XCTAssertFalse(self.syncMOC.hasChanges);
    XCTAssertEqual([self.uiMOC executeFetchRequestOrAssert:[ZMConnection sortedFetchRequest]].count, 0u);
    XCTAssertEqual([self.syncMOC executeFetchRequestOrAssert:[ZMConnection sortedFetchRequest]].count, 0u);
}


- (void)testThatItStoresTheConnectionRequestMessage;
{
    // given
    
    ZMSearchUser *searchUser = [[ZMSearchUser alloc] initWithName:@"Hans" accentColor:ZMAccentColorStrongLimeGreen remoteID:[NSUUID createUUID] user:nil syncManagedObjectContext: self.syncMOC uiManagedObjectContext:self.uiMOC];

    searchUser.remoteIdentifier = [NSUUID createUUID];
    
    OCMockObject *userSession = [OCMockObject niceMockForClass:ZMUserSession.class];
    [[[userSession stub] andReturn:self.syncMOC] syncManagedObjectContext];
    [[[userSession stub] andReturn:self.uiMOC] managedObjectContext];
    
    NSString *connectionMessage = @"very unique connection message";
    
    // expect
    XCTestExpectation *callbackCalled = [self expectationWithDescription:@"Callback called"];
    [searchUser connectWithMessageText:connectionMessage completionHandler:^{
        [callbackCalled fulfill];
    }];
    XCTAssert([self waitForCustomExpectationsWithTimeout:0.5]);
    
    // then
    XCTAssertEqualObjects(searchUser.connectionRequestMessage, connectionMessage);
}


- (void)testThatItCanBeConnectedIfItIsNotAlreadyConnected
{
    // given
    ZMSearchUser *searchUser = [[ZMSearchUser alloc] initWithName:@"Hans" accentColor:ZMAccentColorStrongLimeGreen remoteID:[NSUUID createUUID] user:nil syncManagedObjectContext: self.syncMOC uiManagedObjectContext:self.uiMOC];

    
    // then
    XCTAssertTrue(searchUser.canBeConnected);
}


- (void)testThatItCanNotBeConnectedIfItHasNoRemoteIdentifier
{
    // given
    __block ZMSearchUser *searchUser;
    
    [self performIgnoringZMLogError:^{
        searchUser = [[ZMSearchUser alloc] initWithName:@"Hans" accentColor:ZMAccentColorStrongLimeGreen remoteID:nil user:nil syncManagedObjectContext: self.syncMOC uiManagedObjectContext:self.uiMOC];

    }];
    
    // then
    XCTAssertFalse(searchUser.canBeConnected);
}

- (void)testThatItConnectsIfTheSearchUserHasANonConnectedUser;
{
    // We expect the search user to only have a user, if that user has a (matching)
    // remote identifier. Hence this should have no effect even if the user does
    // in fact not have a remote identifier.
    
    // given
    ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    XCTAssert([self.uiMOC saveOrRollback]);
    
    __block ZMSearchUser *searchUser;
    [self performIgnoringZMLogError:^{
        searchUser = [[ZMSearchUser alloc] initWithName:nil accentColor:ZMAccentColorUndefined remoteID:nil user:user syncManagedObjectContext: self.syncMOC uiManagedObjectContext:self.uiMOC];

    }];
    searchUser.remoteIdentifier = nil;
    
    // expect
    XCTestExpectation *callbackCalled = [self expectationWithDescription:@"Callback called"];
    [searchUser connectWithMessageText:@"Hey!" completionHandler:^{
        [callbackCalled fulfill];
    }];
    XCTAssert([self waitForCustomExpectationsWithTimeout:0.5]);
    XCTAssert([self.uiMOC saveOrRollback]);
    
    // then
    XCTAssertFalse(self.uiMOC.hasChanges);
    XCTAssertFalse(self.syncMOC.hasChanges);
    XCTAssertEqual([self.uiMOC executeFetchRequestOrAssert:[ZMConnection sortedFetchRequest]].count, 1u);
    XCTAssertEqual([self.syncMOC executeFetchRequestOrAssert:[ZMConnection sortedFetchRequest]].count, 1u);
    XCTAssertEqual(user.connection.status, ZMConnectionStatusSent);
}


- (void)testThatItNotifiesObserverWhenConnectingToALocalUser;
{
    // given
    ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    user.remoteIdentifier = [NSUUID createUUID];
    XCTAssert([self.uiMOC saveOrRollback]);

    __block ZMSearchUser *searchUser;
    [self performIgnoringZMLogError:^{
        searchUser = [[ZMSearchUser alloc] initWithName:@"Hans" accentColor:ZMAccentColorUndefined remoteID:nil user:user syncManagedObjectContext: self.syncMOC uiManagedObjectContext:self.uiMOC];

    }];

    id userObserver = [OCMockObject niceMockForProtocol:@protocol(ZMUserObserver)];
    
    searchUser.remoteIdentifier = nil;
    id userToken1 = [ZMUser addUserObserver:self forUsers:@[searchUser] managedObjectContext:self.uiMOC];
    id userToken2 = [ZMUser addUserObserver:userObserver forUsers:@[searchUser] managedObjectContext:self.uiMOC];

    // expect
    XCTestExpectation *callbackCalled = [self expectationWithDescription:@"Callback called"];
    [(id<ZMUserObserver>)[userObserver expect] userDidChange:[OCMArg checkWithBlock:^BOOL(UserChangeInfo *changeInfo) {
        if (changeInfo.connectionStateChanged) {
            [callbackCalled fulfill];
            return YES;
        }
        return NO;
    }]];
    
    // when
    [searchUser connectWithMessageText:@"Hey!" completionHandler:nil];
    XCTAssert([self.uiMOC saveOrRollback]);

    XCTAssert([self waitForCustomExpectationsWithTimeout:1.5]);
    
    // then
    XCTAssertTrue(searchUser.user.isPendingApprovalByOtherUser);
    XCTAssertEqual(self.userNotifications.count, 1u);
    UserChangeInfo *note = self.userNotifications.firstObject;
    XCTAssertEqualObjects(note.user, searchUser);
    XCTAssertTrue(note.connectionStateChanged);
    
    [ZMUser removeUserObserverForToken:userToken1];
    [ZMUser removeUserObserverForToken:userToken2];

}


- (void)testThatItDoesNotConnectIfTheSearchUserHasAConnectedUser;
{
    // We expect the search user to only have a user, if that user has a (matching)
    // remote identifier. Hence this should have no effect even if the user does
    // in fact not have a remote identifier.
    
    // given
    ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    user.connection = [ZMConnection insertNewObjectInManagedObjectContext:self.uiMOC];
    user.connection.status = ZMConnectionStatusAccepted;
    XCTAssert([self.uiMOC saveOrRollback]);

    __block ZMSearchUser *searchUser;
    [self performIgnoringZMLogError:^{
        searchUser = [[ZMSearchUser alloc] initWithName:@"Hans" accentColor:ZMAccentColorStrongLimeGreen remoteID:[NSUUID createUUID] user:user syncManagedObjectContext: self.syncMOC uiManagedObjectContext:self.uiMOC];

    }];
    searchUser.remoteIdentifier = nil;
    
    // expect
    XCTestExpectation *callbackCalled = [self expectationWithDescription:@"Callback called"];
    [searchUser connectWithMessageText:@"Hey!" completionHandler:^{
        [callbackCalled fulfill];
    }];
    XCTAssert([self waitForCustomExpectationsWithTimeout:0.5]);
    
    // then
    XCTAssertFalse(self.uiMOC.hasChanges);
    XCTAssertFalse(self.syncMOC.hasChanges);
    XCTAssertEqual([self.uiMOC executeFetchRequestOrAssert:[ZMConnection sortedFetchRequest]].count, 1u);
    XCTAssertEqual([self.syncMOC executeFetchRequestOrAssert:[ZMConnection sortedFetchRequest]].count, 1u);
}

@end




@implementation ZMSearchUserTests (CommonContacts)

- (void)testThatTheCommonContactsSearchIsForwardedToTheUserSession
{
    // given
    ZMSearchUser *searchUser = [[ZMSearchUser alloc] initWithName:@"foo" accentColor:ZMAccentColorBrightYellow remoteID:[NSUUID createUUID] user:nil syncManagedObjectContext: self.syncMOC uiManagedObjectContext:self.uiMOC];

    
    id token = [OCMockObject mockForProtocol:@protocol(ZMCommonContactsSearchToken)];
    id session = [OCMockObject mockForClass:ZMUserSession.class];
    id delegate = [OCMockObject mockForProtocol:@protocol(ZMCommonContactsSearchDelegate)];
    
    // expect
    [[[session expect] andReturn:token] searchCommonContactsWithUserID:searchUser.remoteIdentifier searchDelegate:delegate];
    
    // when
    [searchUser searchCommonContactsInUserSession:session withDelegate:delegate];
    
    // then
    [session verify];
    [delegate verify];
    [token verify];
    
}

- (void)testThatItReturnsCommonConnectionsForUser;
{
    // given
    ZMUser *user1 = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    NSString *remoteIdentifierString1 = [NSUUID createUUID].UUIDString;
    user1.remoteIdentifier = remoteIdentifierString1.UUID;
    
    ZMUser *user2 = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    NSString *remoteIdentifierString2 = [NSUUID createUUID].UUIDString;
    user2.remoteIdentifier = remoteIdentifierString2.UUID;
    
    [self.uiMOC saveOrRollback];
    
    // when
    NSOrderedSet *identifiers = [NSOrderedSet orderedSetWithArray:@[remoteIdentifierString1, remoteIdentifierString2]];
    NSOrderedSet *commonConnections = [ZMSearchUser commonConnectionsWithIds:identifiers inContext:self.uiMOC];
    
    // then
    XCTAssertEqual(commonConnections.count, 2u);
    XCTAssertTrue([commonConnections containsObject:user1]);
    XCTAssertTrue([commonConnections containsObject:user2]);
}

- (void)testThatItFetchesAndReturnsCommonConnectionsForUserWhenNotInRegisteredObjects;
{
    // given
    ZMUser *user1 = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    NSString *remoteIdentifierString1 = [NSUUID createUUID].UUIDString;
    user1.remoteIdentifier = remoteIdentifierString1.UUID;
    
    ZMUser *user2 = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    NSString *remoteIdentifierString2 = [NSUUID createUUID].UUIDString;
    user2.remoteIdentifier = remoteIdentifierString2.UUID;
    
    [self.uiMOC saveOrRollback];
    [self.uiMOC reset];
    
    // when
    NSOrderedSet *identifiers = [NSOrderedSet orderedSetWithArray:@[remoteIdentifierString1, remoteIdentifierString2]];
    NSOrderedSet *commonConnections = [ZMSearchUser commonConnectionsWithIds:identifiers inContext:self.uiMOC];
    
    // then
    NSArray *objectIDs = [commonConnections.array mapWithBlock:^NSManagedObjectID *(ZMUser *user) {
        return user.objectID;
    }];
    XCTAssertEqual(commonConnections.count, 2u);
    XCTAssertTrue([objectIDs containsObject:user1.objectID]);
    XCTAssertTrue([objectIDs containsObject:user2.objectID]);
}

- (void)testThatItCreatesCommonConnectionsFromPayloadInitializer;
{
    // given
    ZMUser *user1 = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    NSString *remoteIdentifierString1 = [NSUUID createUUID].UUIDString;
    user1.remoteIdentifier = remoteIdentifierString1.UUID;
    
    ZMUser *user2 = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    NSString *remoteIdentifierString2 = [NSUUID createUUID].UUIDString;
    user2.remoteIdentifier = remoteIdentifierString2.UUID;
    
    OCMockObject *userSession = [OCMockObject niceMockForClass:ZMUserSession.class];
    [[[userSession stub] andReturn:self.uiMOC] managedObjectContext];
    
    [self.uiMOC saveOrRollback];
    
    NSDictionary *payload = @{
                              @"accent_id": @7,
                              @"blocked": @0,
                              @"connected": @1,
                              @"email": @"mail@example.com",
                              @"id": [NSUUID createUUID].UUIDString,
                              @"level": @1,
                              @"mutual_friends": @[remoteIdentifierString1, remoteIdentifierString2],
                              @"name": @"Test",
                              @"phone": @"+491234567890",
                              @"total_mutual_friends": @2,
                              @"weight": @20320,
                              };
    
    // when
    NSOrderedSet *identifiers = [NSOrderedSet orderedSetWithArray:@[remoteIdentifierString1, remoteIdentifierString2]];
    NSOrderedSet *connections = [ZMSearchUser commonConnectionsWithIds:identifiers inContext:self.uiMOC];
    ZMSearchUser *searchUser = [[ZMSearchUser alloc] initWithPayload:payload userSession:(ZMUserSession *)userSession globalCommonConnections:connections];
                                
    // then
    XCTAssertEqual(connections.count, 2u);
    XCTAssertEqual(searchUser.topCommonConnections.count, 2u);
    XCTAssertTrue([searchUser.topCommonConnections containsObject:user1]);
    XCTAssertTrue([searchUser.topCommonConnections containsObject:user2]);
}

- (void)testThatItCreatesCommonConnectionsFromPayloadFactoryInitializer;
{
    // given
    ZMUser *user1 = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    NSString *remoteIdentifierString1 = [NSUUID createUUID].UUIDString;
    user1.remoteIdentifier = remoteIdentifierString1.UUID;
    
    ZMUser *user2 = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    NSString *remoteIdentifierString2 = [NSUUID createUUID].UUIDString;
    user2.remoteIdentifier = remoteIdentifierString2.UUID;
    
    OCMockObject *userSession = [OCMockObject niceMockForClass:ZMUserSession.class];
    [[[userSession stub] andReturn:self.uiMOC] managedObjectContext];
    
    [self.uiMOC saveOrRollback];
    
    NSArray *payload = @[@{
                              @"accent_id": @7,
                              @"blocked": @0,
                              @"connected": @1,
                              @"email": @"mail@example.com",
                              @"id": [NSUUID createUUID].UUIDString,
                              @"level": @1,
                              @"mutual_friends": @[remoteIdentifierString1, remoteIdentifierString2],
                              @"name": @"Test",
                              @"phone": @"+491234567890",
                              @"total_mutual_friends": @2,
                              @"weight": @20320,
                              }];
    
    // when
    NSArray <ZMSearchUser *>*searchUsers = [ZMSearchUser  usersWithPayloadArray:payload userSession:(ZMUserSession *)userSession];
    
    // then
    XCTAssertEqual(searchUsers.count, 1u);
    XCTAssertEqual(searchUsers.firstObject.topCommonConnections.count, 2u);
    XCTAssertTrue([searchUsers.firstObject.topCommonConnections containsObject:user1]);
    XCTAssertTrue([searchUsers.firstObject.topCommonConnections containsObject:user2]);
}

@end



@implementation ZMSearchUserTests (SearchUserProfileImage)

- (void)testThatItReturnsSmallProfileImageFromCacheIfItHasNoUser
{
    // given
    NSData *mockImage = [@"bar" dataUsingEncoding:NSUTF8StringEncoding];
    ZMSearchUser *searchUser = [[ZMSearchUser alloc] initWithName:@"foo" accentColor:ZMAccentColorBrightYellow remoteID:[NSUUID createUUID] user:nil syncManagedObjectContext: self.syncMOC uiManagedObjectContext:self.uiMOC];

    NSCache *cache = [ZMSearchUser searchUserToSmallProfileImageCache];
    [cache setObject:mockImage forKey:searchUser.remoteIdentifier];
    
    // when
    NSData *image = searchUser.imageSmallProfileData;
    
    // then
    XCTAssertEqual(mockImage, image);
}

- (void)testThatItReturnsSmallProfileImageFromUserIfItHasAUser
{
    // given
    NSData *mockImage = [@"bar" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *mockImage2 = [@"bar2" dataUsingEncoding:NSUTF8StringEncoding];
    ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    user.remoteIdentifier = [NSUUID createUUID];
    user.smallProfileRemoteIdentifier = [NSUUID createUUID];
    user.imageSmallProfileData = mockImage;
    
    [self.uiMOC saveOrRollback];
    
    ZMSearchUser *searchUser = [[ZMSearchUser alloc] initWithName:@"foo" accentColor:ZMAccentColorBrightYellow remoteID:user.remoteIdentifier user:user syncManagedObjectContext: self.syncMOC uiManagedObjectContext:self.uiMOC];

    NSCache *cache = [ZMSearchUser searchUserToSmallProfileImageCache];
    [cache setObject:mockImage2 forKey:searchUser.remoteIdentifier];
    
    // when
    NSData *image = searchUser.imageSmallProfileData;
    
    
    // then
    XCTAssertEqualObjects(mockImage, image);
}

- (void)testThatItReturnsRemoteIdentifierAsTheSmallProfileImageIdentifierIfItHasACachedImage
{
    // given
    NSData *mockImage = [@"bar" dataUsingEncoding:NSUTF8StringEncoding];
    ZMSearchUser *searchUser = [[ZMSearchUser alloc] initWithName:@"foo" accentColor:ZMAccentColorBrightYellow remoteID:[NSUUID createUUID] user:nil syncManagedObjectContext: self.syncMOC uiManagedObjectContext:self.uiMOC];

    NSCache *cache = [ZMSearchUser searchUserToSmallProfileImageCache];
    [cache setObject:mockImage forKey:searchUser.remoteIdentifier];
    
    // when
    NSString *identifier = searchUser.imageSmallProfileIdentifier;
    
    // then
    XCTAssertEqualObjects(identifier, searchUser.remoteIdentifier.transportString);
}

- (void)testThatItReturnsANulRemoteIdentifierAsTheSmallProfileImageIdentifierIfItHasNoCachedImage
{
    // given
    ZMSearchUser *searchUser = [[ZMSearchUser alloc] initWithName:@"foo" accentColor:ZMAccentColorBrightYellow remoteID:[NSUUID createUUID] user:nil syncManagedObjectContext: self.syncMOC uiManagedObjectContext:self.uiMOC];

    
    // when
    NSString *identifier = searchUser.imageSmallProfileIdentifier;
    
    // then
    XCTAssertNil(identifier);
}

- (void)testThatItReturnsSmallProfileImageIdentifierFromUserIfItHasAUser
{
    // given
    NSData *mockImage = [@"bar" dataUsingEncoding:NSUTF8StringEncoding];

    ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    user.remoteIdentifier = [NSUUID createUUID];
    user.imageSmallProfileData = mockImage;
    user.localSmallProfileRemoteIdentifier = [NSUUID createUUID];
    
    [self.uiMOC saveOrRollback];
    
    ZMSearchUser *searchUser = [[ZMSearchUser alloc] initWithName:@"foo" accentColor:ZMAccentColorBrightYellow remoteID:user.remoteIdentifier user:user syncManagedObjectContext: self.syncMOC uiManagedObjectContext:self.uiMOC];

    NSCache *cache = [ZMSearchUser searchUserToSmallProfileImageCache];
    [cache setObject:mockImage forKey:searchUser.remoteIdentifier];
    
    // when
    NSString *imageIdentifier = searchUser.imageSmallProfileIdentifier;
    
    // then
    NSString *fetchedIdentifier = user.imageSmallProfileIdentifier;
    XCTAssertEqualObjects(imageIdentifier, fetchedIdentifier);
}

- (void)testThatItStoresTheCachedSmallProfileData;
{
    // given
    NSData *mockImage = [@"bar" dataUsingEncoding:NSUTF8StringEncoding];
    ZMSearchUser *searchUser = [[ZMSearchUser alloc] initWithName:@"foo" accentColor:ZMAccentColorBrightYellow remoteID:[NSUUID createUUID] user:nil syncManagedObjectContext: self.syncMOC uiManagedObjectContext:self.uiMOC];

    NSCache *cache = [ZMSearchUser searchUserToSmallProfileImageCache];
    [cache setObject:mockImage forKey:searchUser.remoteIdentifier];
    
    NSData *dataA = [searchUser imageSmallProfileData];
    XCTAssertNotNil(dataA);
    NSString *dataIdentifierA = [searchUser imageSmallProfileIdentifier];
    XCTAssertNotNil(dataIdentifierA);
    
    // when
    [cache removeObjectForKey:searchUser.remoteIdentifier];
    NSData *dataB = [searchUser imageSmallProfileData];
    NSString *dataIdentifierB = [searchUser imageSmallProfileIdentifier];
    
    // then
    AssertEqualData(dataA, dataB);
    XCTAssertEqualObjects(dataIdentifierA, dataIdentifierB);
}

- (void)testThat_isLocalOrHasCachedProfileImageData_returnsNo
{
    // given
    ZMSearchUser *searchUser = [[ZMSearchUser alloc] initWithName:@"foo" accentColor:ZMAccentColorBrightYellow remoteID:[NSUUID createUUID] user:nil syncManagedObjectContext: self.syncMOC uiManagedObjectContext:self.uiMOC];

    
    // then
    XCTAssertFalse(searchUser.isLocalOrHasCachedProfileImageData);
}

- (void)testThat_isLocalOrHasCachedProfileImageData_returnsYesForLocalUser
{
    // given
    ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    user.remoteIdentifier = [NSUUID createUUID];
    [self.uiMOC saveOrRollback];
    ZMSearchUser *searchUser = [[ZMSearchUser alloc] initWithName:nil accentColor:ZMAccentColorUndefined remoteID:nil user:user syncManagedObjectContext: self.syncMOC uiManagedObjectContext:self.uiMOC];

    
    // then
    XCTAssertTrue(searchUser.isLocalOrHasCachedProfileImageData);
}

- (void)testThat_isLocalOrHasCachedProfileImageData_returnsYesForAUserWithCachedData
{
    // given
    NSData *smallImage = [@"bar" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *mediumImage = [@"foo" dataUsingEncoding:NSUTF8StringEncoding];

    ZMSearchUser *searchUser = [[ZMSearchUser alloc] initWithName:@"foo" accentColor:ZMAccentColorBrightYellow remoteID:[NSUUID createUUID] user:nil syncManagedObjectContext: self.syncMOC uiManagedObjectContext:self.uiMOC];

    NSCache *smallCache = [ZMSearchUser searchUserToSmallProfileImageCache];
    [smallCache setObject:smallImage forKey:searchUser.remoteIdentifier];
    
    NSCache *mediumCache = [ZMSearchUser searchUserToMediumImageCache];
    [mediumCache setObject:mediumImage forKey:searchUser.remoteIdentifier];
    
    // then
    XCTAssertTrue(searchUser.isLocalOrHasCachedProfileImageData);
}

- (void)testThat_isLocalOrHasCachedProfileImageData_returnsYesForAUserWithCachedSmallData_MediumAssetID
{
    // given
    NSData *smallImage = [@"bar" dataUsingEncoding:NSUTF8StringEncoding];
    NSUUID *mediumAssetID = [NSUUID UUID];
    
    ZMSearchUser *searchUser = [[ZMSearchUser alloc] initWithName:@"foo" accentColor:ZMAccentColorBrightYellow remoteID:[NSUUID createUUID] user:nil syncManagedObjectContext: self.syncMOC uiManagedObjectContext:self.uiMOC];
    
    NSCache *smallImageCache = [ZMSearchUser searchUserToSmallProfileImageCache];
    [smallImageCache setObject:smallImage forKey:searchUser.remoteIdentifier];
    
    NSCache *mediumAssetCache = [ZMSearchUser searchUserToMediumAssetIDCache];
    [mediumAssetCache setObject:mediumAssetID forKey:searchUser.remoteIdentifier];
    
    // then
    XCTAssertTrue(searchUser.isLocalOrHasCachedProfileImageData);
}

- (void)testThat_isLocalOrHasCachedProfileImageData_returnsNoIfMediumAssetIDAndDataAreNotSet
{
    // given
    NSData *smallImage = [@"bar" dataUsingEncoding:NSUTF8StringEncoding];
    
    ZMSearchUser *searchUser = [[ZMSearchUser alloc] initWithName:@"foo" accentColor:ZMAccentColorBrightYellow remoteID:[NSUUID createUUID] user:nil syncManagedObjectContext: self.syncMOC uiManagedObjectContext:self.uiMOC];
    
    NSCache *smallImageCache = [ZMSearchUser searchUserToSmallProfileImageCache];
    [smallImageCache setObject:smallImage forKey:searchUser.remoteIdentifier];
    
    // then
    XCTAssertFalse(searchUser.isLocalOrHasCachedProfileImageData);
}

@end



@implementation ZMSearchUserTests (MediumImage)

- (void)testThatItReturnsMediumAssetIDFromCacheIfItHasNoMediumAssetID
{
    // given
    NSUUID *assetID = [NSUUID UUID];
    
    ZMSearchUser *searchUser = [[ZMSearchUser alloc] initWithName:@"foo" accentColor:ZMAccentColorBrightYellow remoteID:[NSUUID createUUID] user:nil syncManagedObjectContext: self.syncMOC uiManagedObjectContext:self.uiMOC];
    
    NSCache *cache = [ZMSearchUser searchUserToMediumAssetIDCache];
    [cache setObject:assetID forKey:searchUser.remoteIdentifier];
    
    // when
    NSUUID *mediumAssetID = searchUser.mediumAssetID;
    
    // then
    XCTAssertEqual(mediumAssetID, assetID);
}

- (void)testThatItReturnsMediumImageFromCacheIfItHasNoUser
{
    // given
    NSData *mockImage = [@"bar" dataUsingEncoding:NSUTF8StringEncoding];
    ZMSearchUser *searchUser = [[ZMSearchUser alloc] initWithName:@"foo" accentColor:ZMAccentColorBrightYellow remoteID:[NSUUID createUUID] user:nil syncManagedObjectContext: self.syncMOC uiManagedObjectContext:self.uiMOC];

    NSCache *cache = [ZMSearchUser searchUserToMediumImageCache];
    [cache setObject:mockImage forKey:searchUser.remoteIdentifier];
    
    // when
    NSData *image = searchUser.imageMediumData;
    
    // then
    XCTAssertEqual(mockImage, image);
}

- (void)testThatItReturnsMediumImageFromUserIfItHasAUser
{
    // given
    NSData *mockImage = [@"bar" dataUsingEncoding:NSUTF8StringEncoding];
    NSData *mockImage2 = [@"bar2" dataUsingEncoding:NSUTF8StringEncoding];
    ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    user.remoteIdentifier = [NSUUID createUUID];
    user.mediumRemoteIdentifier = [NSUUID createUUID];
    user.imageMediumData = mockImage;
    
    [self.uiMOC saveOrRollback];
    
    ZMSearchUser *searchUser = [[ZMSearchUser alloc] initWithName:@"foo" accentColor:ZMAccentColorBrightYellow remoteID:user.remoteIdentifier user:user syncManagedObjectContext: self.syncMOC uiManagedObjectContext:self.uiMOC];

    NSCache *cache = [ZMSearchUser searchUserToMediumImageCache];
    [cache setObject:mockImage2 forKey:searchUser.remoteIdentifier];
    
    // when
    NSData *image = searchUser.imageMediumData;
    
    // then
    XCTAssertEqualObjects(mockImage, image);
}

- (void)testThatItReturnsRemoteIdentifierAsTheMediumProfileImageIdentifierIfItHasACachedImage
{
    // given
    NSData *mockImage = [@"bar" dataUsingEncoding:NSUTF8StringEncoding];
    ZMSearchUser *searchUser = [[ZMSearchUser alloc] initWithName:@"foo" accentColor:ZMAccentColorBrightYellow remoteID:[NSUUID createUUID] user:nil syncManagedObjectContext: self.syncMOC uiManagedObjectContext:self.uiMOC];

    NSCache *cache = [ZMSearchUser searchUserToMediumImageCache];
    [cache setObject:mockImage forKey:searchUser.remoteIdentifier];
    
    // when
    NSString *identifier = searchUser.imageMediumIdentifier;
    
    // then
    XCTAssertEqualObjects(identifier, searchUser.remoteIdentifier.transportString);
}

- (void)testThatItReturnsANulRemoteIdentifierAsTheMediumProfileImageIdentifierIfItHasNoCachedImage
{
    // given
    ZMSearchUser *searchUser = [[ZMSearchUser alloc] initWithName:@"foo" accentColor:ZMAccentColorBrightYellow remoteID:[NSUUID createUUID] user:nil syncManagedObjectContext: self.syncMOC uiManagedObjectContext:self.uiMOC];

    
    // when
    NSString *identifier = searchUser.imageMediumIdentifier;
    
    // then
    XCTAssertNil(identifier);
}

- (void)testThatItReturnsMediumProfileImageIdentifierFromUserIfItHasAUser
{
    // given
    NSData *mockImage = [@"bar" dataUsingEncoding:NSUTF8StringEncoding];
    
    ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
    user.remoteIdentifier = [NSUUID createUUID];
    user.imageMediumData = mockImage;
    user.localMediumRemoteIdentifier = [NSUUID createUUID];
    
    [self.uiMOC saveOrRollback];
    
    ZMSearchUser *searchUser = [[ZMSearchUser alloc] initWithName:@"foo" accentColor:ZMAccentColorBrightYellow remoteID:user.remoteIdentifier user:user syncManagedObjectContext: self.syncMOC uiManagedObjectContext:self.uiMOC];

    NSCache *cache = [ZMSearchUser searchUserToMediumImageCache];
    [cache setObject:mockImage forKey:searchUser.remoteIdentifier];
    
    // when
    NSString *imageIdentifier = searchUser.imageMediumIdentifier;
    
    // then
    NSString *fetchedIdentifier = user.imageMediumIdentifier;
    XCTAssertEqualObjects(imageIdentifier, fetchedIdentifier);
}

- (void)testThatItStoresTheCachedMediumProfileData;
{
    // given
    NSData *mockImage = [@"bar" dataUsingEncoding:NSUTF8StringEncoding];
    ZMSearchUser *searchUser = [[ZMSearchUser alloc] initWithName:@"foo" accentColor:ZMAccentColorBrightYellow remoteID:[NSUUID createUUID] user:nil syncManagedObjectContext: self.syncMOC uiManagedObjectContext:self.uiMOC];

    NSCache *cache = [ZMSearchUser searchUserToMediumImageCache];
    NSCache *idCache = [ZMSearchUser searchUserToMediumAssetIDCache];
    
    [cache setObject:mockImage forKey:searchUser.remoteIdentifier];
    
    NSData *dataA = [searchUser imageMediumData];
    XCTAssertNotNil(dataA);
    NSString *dataIdentifierA = [searchUser imageMediumIdentifier];
    XCTAssertNotNil(dataIdentifierA);
    [idCache setObject:[NSUUID uuidWithTransportString:dataIdentifierA] forKey:searchUser.remoteIdentifier];
    
    // when
    [cache removeObjectForKey:searchUser.remoteIdentifier];
    NSData *dataB = [searchUser imageMediumData];
    NSString *dataIdentifierB = [searchUser imageMediumIdentifier];
    
    // then
    AssertEqualData(dataA, dataB);
    XCTAssertEqualObjects(dataIdentifierA, dataIdentifierB);
}




@end

