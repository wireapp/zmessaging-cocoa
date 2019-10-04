//
// Wire
// Copyright (C) 2017 Wire Swiss GmbH
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
@import WireRequestStrategy;
@import WireTransport;
@import WireMockTransport;
@import WireSyncEngine;
@import WireDataModel;

#import "MessagingTest.h"
#import "ZMUserSession+Internal.h"
#import "ZMUserSession+Internal.h"
#import "ZMLoginTranscoder+Internal.h"
#import "ZMConversationTranscoder.h"
#import "ZMConversation+Testing.h"
#import "WireSyncEngine_iOS_Tests-Swift.h"


@interface SlowSyncTests : IntegrationTest

@end

@implementation SlowSyncTests

- (void)setUp
{
    [super setUp];
    [self createSelfUserAndConversation];
    [self createExtraUsersAndConversations];
}

- (void)testThatWeCanGetConnections
{
    // when
    XCTAssertTrue([self login]);
    
    // then
    NSFetchRequest *fetchRequest = [ZMConnection sortedFetchRequest];
    
    __block NSString *user1Identifier;
    __block NSString *user2Identifier;
    [self.mockTransportSession.managedObjectContext performGroupedBlockAndWait:^{
        user1Identifier = self.user1.identifier;
        user2Identifier = self.user2.identifier;
    }];

    NSArray *connections = [self.userSession.managedObjectContext executeFetchRequestOrAssert:fetchRequest];
    XCTAssertNotNil(connections);
    XCTAssertEqual(connections.count, 2u);

    XCTAssertTrue([connections containsObjectMatchingWithBlock:^BOOL(ZMConnection *obj){
        return [obj.to.remoteIdentifier.transportString isEqual:user1Identifier];
    }]);
    
    XCTAssertTrue([connections containsObjectMatchingWithBlock:^BOOL(ZMConnection *obj){
        return [obj.to.remoteIdentifier.transportString isEqual:user2Identifier];
    }]);
}


- (void)testThatWeCanGetUsers
{
    // when
    XCTAssertTrue([self login]);
    
    // then
    NSFetchRequest *fetchRequest = [ZMUser sortedFetchRequest];
    NSArray *users = [self.userSession.managedObjectContext executeFetchRequestOrAssert:fetchRequest];
    ZMUser *fetchedSelfUser = [ZMUser selfUserInContext:self.userSession.managedObjectContext];
    
    XCTAssertNotNil(users);
    
    XCTAssertTrue(users.count >= 3u);

    XCTAssertTrue([self isActualUser:fetchedSelfUser equalToMockUser:self.selfUser failureRecorder:NewFailureRecorder()]);
    
    ZMUser *actualUser1 = [self userForMockUser:self.user1];
    XCTAssertTrue([self isActualUser:actualUser1 equalToMockUser:self.user1 failureRecorder:NewFailureRecorder()]);
    
    ZMUser *actualUser2 = [self userForMockUser:self.user2];
    XCTAssertTrue([self isActualUser:actualUser2 equalToMockUser:self.user2 failureRecorder:NewFailureRecorder()]);
}


- (void)testThatWeCanGetConversations
{
    // given
    __block NSString *selfConversationIdentifier;
    __block NSString *selfToUser1ConversationIdentifier;
    __block NSString *selfToUser2ConversationIdentifier;
    __block NSString *groupConversationIdentifier;
    
    [self.mockTransportSession.managedObjectContext performGroupedBlockAndWait:^{
        selfConversationIdentifier =  self.selfConversation.identifier;
        selfToUser1ConversationIdentifier = self.selfToUser1Conversation.identifier;
        selfToUser2ConversationIdentifier = self.selfToUser2Conversation.identifier;
        groupConversationIdentifier = self.groupConversation.identifier;
    }];
    
    // when
    XCTAssertTrue([self login]);
    
    // then
    NSFetchRequest *fetchRequest = [ZMConversation sortedFetchRequest];
    NSArray *conversations = [self.userSession.managedObjectContext executeFetchRequestOrAssert:fetchRequest];
    
    XCTAssertNotNil(conversations);
    XCTAssertEqual(conversations.count, 3u);
    
    
    ZMConversation *actualSelfConversation = [ZMConversation conversationWithRemoteID:[NSUUID uuidWithTransportString:selfConversationIdentifier] createIfNeeded:NO inContext:self.userSession.managedObjectContext];
    [actualSelfConversation assertMatchesConversation:self.selfConversation failureRecorder:NewFailureRecorder()];
    
    ZMConversation *actualSelfToUser1Conversation = [self findConversationWithIdentifier:selfToUser1ConversationIdentifier inMoc:self.userSession.managedObjectContext];
    [actualSelfToUser1Conversation assertMatchesConversation:self.selfToUser1Conversation failureRecorder:NewFailureRecorder()];
    
    ZMConversation *actualSelfToUser2Conversation = [self findConversationWithIdentifier:selfToUser2ConversationIdentifier inMoc:self.userSession.managedObjectContext];
    [actualSelfToUser2Conversation assertMatchesConversation:self.selfToUser2Conversation failureRecorder:NewFailureRecorder()];
    
    ZMConversation *actualGroupConversation = [self findConversationWithIdentifier:groupConversationIdentifier inMoc:self.userSession.managedObjectContext];
    [actualGroupConversation assertMatchesConversation:self.groupConversation failureRecorder:NewFailureRecorder()];
}

- (NSArray *)commonRequestsOnLogin
{
    __block NSString *selfConversationIdentifier;
    __block NSString *selfToUser1ConversationIdentifier;
    __block NSString *selfToUser2ConversationIdentifier;
    __block NSString *groupConversationIdentifier;
    __block NSString *user1Identifier;
    __block NSString *user2Identifier;
    __block NSString *user3Identifier;
    
    [self.mockTransportSession.managedObjectContext performGroupedBlockAndWait:^{
        selfConversationIdentifier =  self.selfConversation.identifier;
        selfToUser1ConversationIdentifier = self.selfToUser1Conversation.identifier;
        selfToUser2ConversationIdentifier = self.selfToUser2Conversation.identifier;
        groupConversationIdentifier = self.groupConversation.identifier;
        user1Identifier = self.user1.identifier;
        user2Identifier = self.user2.identifier;
        user3Identifier = self.user3.identifier;
    }];
    
    return @[
             [[ZMTransportRequest alloc] initWithPath:ZMLoginURL method:ZMMethodPOST payload:@{@"email":[IntegrationTest.SelfUserEmail copy], @"password":[IntegrationTest.SelfUserPassword copy], @"label": CookieLabel.current.value} authentication:ZMTransportRequestAuthCreatesCookieAndAccessToken],
             [ZMTransportRequest requestGetFromPath:@"/self"],
             [ZMTransportRequest requestGetFromPath:@"/self"], // second request during slow sync
             [ZMTransportRequest requestGetFromPath:@"/clients"],
             [ZMTransportRequest requestGetFromPath:[NSString stringWithFormat:@"/notifications/last?client=%@",  [ZMUser selfUserInContext:self.userSession.managedObjectContext].selfClient.remoteIdentifier]],
             [ZMTransportRequest requestGetFromPath:@"/connections?size=90"],
             [ZMTransportRequest requestGetFromPath:@"/conversations/ids?size=100"],
             [ZMTransportRequest requestGetFromPath:[NSString stringWithFormat:@"/conversations?ids=%@,%@,%@,%@", selfConversationIdentifier, selfToUser1ConversationIdentifier, selfToUser2ConversationIdentifier, groupConversationIdentifier]],
             [ZMTransportRequest requestGetFromPath:[NSString stringWithFormat:@"/users?ids=%@,%@", user1Identifier, user2Identifier]],
             [ZMTransportRequest requestGetFromPath:[NSString stringWithFormat:@"/users?ids=%@", user3Identifier]],
             [ZMTransportRequest requestGetFromPath:@"/teams?size=50"],
             [ZMTransportRequest requestGetFromPath:@"/properties/labels"]
             ];

}

- (void)testThatItGeneratesOnlyTheExpectedRequestsForSelfUserProfilePicture
{
    // when
    XCTAssertTrue([self login]);

    __block NSString *previewProfileAssetIdentifier = nil;
    __block NSString *completeProfileAssetIdentifier = nil;
    [self.mockTransportSession.managedObjectContext performGroupedBlockAndWait:^{
        previewProfileAssetIdentifier = self.selfUser.previewProfileAssetIdentifier;
        completeProfileAssetIdentifier = self.selfUser.completeProfileAssetIdentifier;
    }];
    
    // given
    NSArray *expectedRequests = [[self commonRequestsOnLogin] arrayByAddingObjectsFromArray: @[
                                  [ZMTransportRequest imageGetRequestFromPath:[NSString stringWithFormat:@"/assets/v3/%@", previewProfileAssetIdentifier]],
                                  [ZMTransportRequest imageGetRequestFromPath:[NSString stringWithFormat:@"/assets/v3/%@", completeProfileAssetIdentifier]],
                                  [ZMTransportRequest requestWithPath:@"properties/WIRE_RECEIPT_MODE" method:ZMMethodGET payload:nil],
                                  ]];
    
    // then
    NSMutableArray *mutableRequests = [self.mockTransportSession.receivedRequests mutableCopy];
    __block NSUInteger clientRegistrationCallCount = 0;
    __block NSUInteger notificationStreamCallCount = 0;
    [self.mockTransportSession.receivedRequests enumerateObjectsUsingBlock:^(ZMTransportRequest *request, NSUInteger idx, BOOL *stop) {
        NOT_USED(stop);
        NOT_USED(idx);
        if ([request.path containsString:@"clients"] && request.method == ZMMethodPOST) {
            [mutableRequests removeObject:request];
            clientRegistrationCallCount++;
        }
        
        if ([request.path hasPrefix:@"/notifications?size=500"]) {
            [mutableRequests removeObject:request];
            notificationStreamCallCount++;
        }
    }];
    XCTAssertEqual(clientRegistrationCallCount, 1u);
    XCTAssertEqual(notificationStreamCallCount, 1u);
    
    AssertArraysContainsSameObjects(expectedRequests, mutableRequests);
}

- (void)testThatItDoesAQuickSyncOnStartupIfAfterARestartWithoutAnyPushNotification
{
    // given
    XCTAssertTrue([self login]);
    
    [self.mockTransportSession resetReceivedRequests];
    
    // when
    [self recreateSessionManager];
    
    // then
    BOOL hasNotificationsRequest = NO;
    for (ZMTransportRequest *request in self.mockTransportSession.receivedRequests) {
        
        if ([request.path hasPrefix:@"/notifications"]) {
            hasNotificationsRequest = YES;
        }
        
        XCTAssertFalse([request.path hasPrefix:@"/conversations"]);
        XCTAssertFalse([request.path hasPrefix:@"/connections"]);
    }
    
    XCTAssertTrue(hasNotificationsRequest);
}


- (void)testThatItDoesAQuickSyncOnStartupIfItHasReceivedNotificationsEarlier
{
    // given
    XCTAssertTrue([self login]);

    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        NOT_USED(session);
        ZMGenericMessage *message = [ZMGenericMessage messageWithContent:[ZMText textWith:@"Hello, Test!" mentions:@[] linkPreviews:@[] replyingTo:nil] nonce:NSUUID.createUUID];
        [self.groupConversation encryptAndInsertDataFromClient:self.user1.clients.anyObject toClient:self.selfUser.clients.anyObject data:message.data];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    [self.mockTransportSession resetReceivedRequests];
    
    // when
    [self recreateSessionManager];
    
    // then
    BOOL hasNotificationsRequest = NO;
    for (ZMTransportRequest *request in self.mockTransportSession.receivedRequests) {
        
        if ([request.path hasPrefix:@"/notifications"]) {
            hasNotificationsRequest = YES;
        }
        
        XCTAssertFalse([request.path hasPrefix:@"/conversations"]);
        XCTAssertFalse([request.path hasPrefix:@"/connections"]);
    }
    
    XCTAssertTrue(hasNotificationsRequest);
}

- (void)testThatItDoesAQuickSyncAfterTheWebSocketWentDown
{
    // given
    XCTAssertTrue([self login]);
    
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        NOT_USED(session);
        ZMGenericMessage *message = [ZMGenericMessage messageWithContent:[ZMText textWith:@"Hello, Test!" mentions:@[] linkPreviews:@[] replyingTo:nil] nonce:NSUUID.createUUID];
        [self.groupConversation encryptAndInsertDataFromClient:self.user1.clients.anyObject toClient:self.selfUser.clients.anyObject data:message.data];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    [self.mockTransportSession resetReceivedRequests];
    
    // when
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        [session simulatePushChannelClosed];
        [session simulatePushChannelOpened];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    BOOL hasNotificationsRequest = NO;
    for (ZMTransportRequest *request in self.mockTransportSession.receivedRequests) {
        
        if ([request.path hasPrefix:@"/notifications"]) {
            hasNotificationsRequest = YES;
        }
        
        XCTAssertFalse([request.path hasPrefix:@"/conversations"]);
        XCTAssertFalse([request.path hasPrefix:@"/connections"]);
    }
    
    XCTAssertTrue(hasNotificationsRequest);
}


- (void)testThatItDoesASlowSyncAfterTheWebSocketWentDownAndNotificationsReturnsAnError
{
    // given
    XCTAssertTrue([self login]);
    
    [self.mockTransportSession resetReceivedRequests];

    // make /notifications fail
    __block BOOL hasNotificationsRequest = NO;
    __block BOOL hasConversationsRequest = NO;
    __block BOOL hasConnectionsRequest = NO;
    __block BOOL hasUserRequest = NO;
    
    self.mockTransportSession.responseGeneratorBlock = ^ZMTransportResponse *(ZMTransportRequest *request) {
        if([request.path hasPrefix:@"/notifications"]) {
            if (!(hasConnectionsRequest && hasConversationsRequest && hasUserRequest)) {
                return [ZMTransportResponse responseWithPayload:nil HTTPStatus:404 transportSessionError:nil];
            }
            hasNotificationsRequest = YES;
        }
        if ([request.path hasPrefix:@"/users"]) {
            hasUserRequest = YES;
        }
        if ([request.path hasPrefix:@"/conversations?ids="]) {
            hasConversationsRequest = YES;
        }
        if ([request.path hasPrefix:@"/connections?size="]) {
            hasConnectionsRequest = YES;
        }
        return nil;
    };
    
    // when
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        [session simulatePushChannelClosed];
        [session simulatePushChannelOpened];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then

    XCTAssertTrue(hasNotificationsRequest);
    XCTAssertTrue(hasUserRequest);
    XCTAssertTrue(hasConversationsRequest);
    XCTAssertTrue(hasConnectionsRequest);
}

- (void)testThatTheUIIsNotifiedWhenTheSyncIsComplete
{
    // given
    NetworkStateRecorder *stateRecoder = [[NetworkStateRecorder alloc] init];
    id token = [ZMNetworkAvailabilityChangeNotification addNetworkAvailabilityObserver:stateRecoder userSession:self.userSession];
    
    // when
    XCTAssertTrue([self login]);
    
    // then
    XCTAssertEqual(stateRecoder.stateChanges.count, 2u);
    ZMNetworkState state1 = (ZMNetworkState)[stateRecoder.stateChanges.firstObject intValue];
    ZMNetworkState state2 = (ZMNetworkState)[stateRecoder.stateChanges.lastObject intValue];

    XCTAssertEqual(state1, ZMNetworkStateOnlineSynchronizing);
    XCTAssertEqual(state2, ZMNetworkStateOnline);
    XCTAssertEqual(self.userSession.networkState, ZMNetworkStateOnline);
    
    token = nil;
}

- (void)testThatItHasTheSelfUserEmailAfterTheSlowSync
{
    // given
    XCTAssertTrue([self login]);
    
    // then
    XCTAssertNotNil([[ZMUser selfUserInUserSession:self.userSession] emailAddress]);
}

- (void)testThatItUpdatesExistingTeamDuringSlowSync
{
    // given
    __block MockTeam *mockTeam;
    [self.mockTransportSession performRemoteChanges:^(id<MockTransportSessionObjectCreation> _Nonnull session) {
        mockTeam = [session insertTeamWithName:@"Foo" isBound:YES users:[NSSet setWithArray:@[self.selfUser, self.user1]]];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    XCTAssertTrue([self login]);
    ZMUser *localUser1 = [self userForMockUser:self.user1];
    ZMUser *localUser2 = [self userForMockUser:self.user2];
    ZMUser *localSelfUser = [self userForMockUser:self.selfUser];
    
    XCTAssertNotNil(localUser1.team);
    XCTAssertNil(localUser2.team);
    XCTAssertNotNil(localSelfUser.team);

    // when
    // block requests to /notifications to enforce slowSync
    __block BOOL hasNotificationsRequest = NO;
    __block BOOL hasTeamRequest = NO;
    __block BOOL hasMemberRequest = NO;

    self.mockTransportSession.responseGeneratorBlock = ^ZMTransportResponse *(ZMTransportRequest *request) {
        if([request.path hasPrefix:@"/notifications"]) {
            if (!(hasTeamRequest && hasMemberRequest)){
                return [ZMTransportResponse responseWithPayload:nil HTTPStatus:404 transportSessionError:nil];
            }
            hasNotificationsRequest = YES;
        }
        if ([request.path hasPrefix:@"/teams"]) {
            hasTeamRequest = YES;
        }
        if ([request.path hasPrefix:@"/teams"] && [request.path containsString:@"members"]) {
            hasMemberRequest = YES;
        }
        return nil;
    };
    
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        [session simulatePushChannelClosed];
        [session removeMemberWithUser:self.user1 fromTeam:mockTeam];
        [session insertMemberWithUser:self.user2 inTeam:mockTeam];

        [session saveAndCreatePushChannelEvents]; // clears the team.member-leave event from the push channel events
        [session simulatePushChannelOpened];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertNil(localUser1.team);
    XCTAssertNotNil(localUser2.team);
    XCTAssertNotNil(localSelfUser.team);
    XCTAssertTrue(hasNotificationsRequest);
    XCTAssertTrue(hasTeamRequest);
    XCTAssertTrue(hasMemberRequest);

}

- (void)testThatAccountDeletedIfTeamIsDiscoveredToBeDeletedDuringSlowSync
{
    // given
    __block MockTeam *mockTeam;
    [self.mockTransportSession performRemoteChanges:^(id<MockTransportSessionObjectCreation> _Nonnull session) {
        mockTeam = [session insertTeamWithName:@"Foo" isBound: YES users:[NSSet setWithObject:self.selfUser]];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    XCTAssertTrue([self login]);
    XCTAssertNotNil([ZMUser selfUserInUserSession:self.userSession].team);
    
    // when
    // block requests to /notifications to enforce slowSync
    __block BOOL hasTeamRequest = NO;

    self.mockTransportSession.responseGeneratorBlock = ^ZMTransportResponse *(ZMTransportRequest *request) {
        if([request.path hasPrefix:@"/notifications"]) {
            if (!hasTeamRequest){
                return [ZMTransportResponse responseWithPayload:nil HTTPStatus:404 transportSessionError:nil];
            }
        }
        if ([request.path hasPrefix:@"/teams"]) {
            hasTeamRequest = YES;
        }
        return nil;
    };
    
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        [session simulatePushChannelClosed];
        [session removeMemberWithUser:self.selfUser fromTeam:mockTeam];
        [session saveAndCreatePushChannelEvents]; // clears the team.member-leave event from the push channel events
        [session simulatePushChannelOpened];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertTrue(hasTeamRequest);
    XCTAssertNil(self.userSession); // user session has been closed
    XCTAssertEqual(self.sessionManager.accountManager.accounts.count, 0ul); // account has been deleted
}


- (ZMUser *)findUserWithUUID:(NSString *)UUIDString inMoc:(NSManagedObjectContext *)moc {
    ZMUser *user = [ZMUser userWithRemoteID:[UUIDString UUID] createIfNeeded:NO inContext:moc];
    XCTAssertNotNil(user);
    return user;
}


- (BOOL)isActualUser:(ZMUser *)user equalToMockUser:(MockUser *)mockUser failureRecorder:(ZMTFailureRecorder *)failureRecorder;
{
    __block NSDictionary *values;
    [mockUser.managedObjectContext performBlockAndWait:^{
        values = [[mockUser committedValuesForKeys:nil] copy];
    }];
    
    BOOL emailAndPhoneMatches = YES;
    if (user.isSelfUser) {
        FHAssertEqualObjects(failureRecorder, user.emailAddress, values[@"email"]);
        FHAssertEqualObjects(failureRecorder, user.phoneNumber, values[@"phone"]);
        emailAndPhoneMatches = (user.emailAddress == values[@"email"] || [user.emailAddress isEqualToString:values[@"email"]]) &&
                               (user.phoneNumber == values[@"phone"] || [user.phoneNumber isEqualToString:values[@"phone"]]);
    }
    FHAssertEqualObjects(failureRecorder, user.name, values[@"name"]);
    FHAssertEqual(failureRecorder, user.accentColorValue, (ZMAccentColor) [values[@"accentID"] intValue]);
    
    return ((user.name == values[@"name"] || [user.name isEqualToString:values[@"name"]])
            && emailAndPhoneMatches
            && (user.accentColorValue == (ZMAccentColor) [values[@"accentID"] intValue]));
}

- (ZMConversation *)findConversationWithIdentifier:(NSString *)identifier inMoc:(NSManagedObjectContext *)moc
{
    ZMConversation *conversation = [ZMConversation conversationWithRemoteID:[NSUUID uuidWithTransportString:identifier] createIfNeeded:NO inContext:moc];
    XCTAssertNotNil(conversation);
    return conversation;
}

@end


@implementation SlowSyncTests (BackgroundFetch)

- (void)testThatItFetchesTheNotificationStreamDuringBackgroundFetch
{
    // given
    XCTAssertTrue([self login]);
    
    [self.application setBackground];
    [self.application simulateApplicationDidEnterBackground];
    WaitForAllGroupsToBeEmpty(0.5);
    
    [self.mockTransportSession resetReceivedRequests];
    
    // when
    XCTestExpectation *expectation = [self expectationWithDescription:@"fetchCompleted"];
    [self.userSession application:self.application performFetchWithCompletionHandler:^(UIBackgroundFetchResult result) {
        NOT_USED(result);
        ZMTransportRequest *request = self.mockTransportSession.receivedRequests.lastObject;
        XCTAssertNotNil(request);
        XCTAssertTrue([request.path containsString:@"notifications"]);
        [expectation fulfill];
    }];
    
    // then
    XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0.5]);
    WaitForAllGroupsToBeEmpty(0.5);
}

@end
