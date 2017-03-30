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
@import ZMTransport;
@import ZMCMockTransport;
@import zmessaging;
@import ZMCDataModel;

#import "MessagingTest.h"
#import "ZMUserSession+Internal.h"
#import "IntegrationTestBase.h"
#import "ZMUserSession+Internal.h"
#import "ZMLoginTranscoder+Internal.h"
#import "ZMConversationTranscoder.h"
#import "ZMConversation+Testing.h"


@interface SlowSyncTests : IntegrationTestBase

@end



@implementation SlowSyncTests

- (void)testThatWeCanGetConnections
{
    // when
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    
    // then
    NSFetchRequest *fetchRequest = [ZMConnection sortedFetchRequest];


    NSArray *connections = [self.userSession.managedObjectContext executeFetchRequestOrAssert:fetchRequest];
    XCTAssertNotNil(connections);
    XCTAssertEqual(connections.count, 2u);

    XCTAssertTrue([connections containsObjectMatchingWithBlock:^BOOL(ZMConnection *obj){
        return [obj.to.remoteIdentifier isEqual:[self remoteIdentifierForMockObject:self.user1]];
    }]);
    
    XCTAssertTrue([connections containsObjectMatchingWithBlock:^BOOL(ZMConnection *obj){
        return [obj.to.remoteIdentifier isEqual:[self remoteIdentifierForMockObject:self.user2]];
    }]);
}


- (void)testThatWeCanGetUsers
{
    // when
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    
    // then
    NSFetchRequest *fetchRequest = [ZMUser sortedFetchRequest];

    
    NSArray *users = [self.uiMOC executeFetchRequestOrAssert:fetchRequest];
    ZMUser *fetchedSelfUser = [ZMUser selfUserInContext:self.uiMOC];
    
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
    
    // when
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    WaitForEverythingToBeDone();
    
    // then
    NSFetchRequest *fetchRequest = [ZMConversation sortedFetchRequest];
    NSArray *conversations = [self.uiMOC executeFetchRequestOrAssert:fetchRequest];
    
    XCTAssertNotNil(conversations);
    XCTAssertEqual(conversations.count, 3u);
    
    
    ZMConversation *actualSelfConversation = [ZMConversation conversationWithRemoteID:[self remoteIdentifierForMockObject:self.selfConversation] createIfNeeded:NO inContext:self.uiMOC];
    [actualSelfConversation assertMatchesConversation:self.selfConversation failureRecorder:NewFailureRecorder()];
    
    ZMConversation *actualSelfToUser1Conversation = [self findConversationWithUUID:[self remoteIdentifierForMockObject:self.selfToUser1Conversation] inMoc:self.uiMOC];
    [actualSelfToUser1Conversation assertMatchesConversation:self.selfToUser1Conversation failureRecorder:NewFailureRecorder()];
    
    ZMConversation *actualSelfToUser2Conversation = [self findConversationWithUUID:[self remoteIdentifierForMockObject:self.selfToUser2Conversation] inMoc:self.uiMOC];
    [actualSelfToUser2Conversation assertMatchesConversation:self.selfToUser2Conversation failureRecorder:NewFailureRecorder()];
    
    ZMConversation *actualGroupConversation = [self findConversationWithUUID:[self remoteIdentifierForMockObject:self.groupConversation] inMoc:self.uiMOC];
    [actualGroupConversation assertMatchesConversation:self.groupConversation failureRecorder:NewFailureRecorder()];
}

- (void)testThatItGeneratesOnlyTheExpectedRequests
{
    // when
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    [NSThread sleepForTimeInterval:0.2]; // sleep to wait for spurious calls
    
    // given
    NSArray *expectedRequests = @[
                                  [[ZMTransportRequest alloc] initWithPath:ZMLoginURL method:ZMMethodPOST payload:@{@"email":[self.selfUser.email copy], @"password":[self.selfUser.password copy], @"label": self.userSession.authenticationStatus.cookieLabel} authentication:ZMTransportRequestAuthCreatesCookieAndAccessToken],
                                  [ZMTransportRequest requestGetFromPath:@"/self"],
                                  [ZMTransportRequest requestGetFromPath:@"/clients"],
                                  [ZMTransportRequest requestGetFromPath:[NSString stringWithFormat:@"/notifications/last?client=%@",  [ZMUser selfUserInContext:self.syncMOC].selfClient.remoteIdentifier]],
                                  [ZMTransportRequest requestGetFromPath:@"/connections?size=90"],
                                  [ZMTransportRequest requestGetFromPath:@"/conversations/ids?size=100"],
                                  [ZMTransportRequest requestGetFromPath:[NSString stringWithFormat:@"/conversations?ids=%@,%@,%@,%@", self.selfConversation.identifier,self.selfToUser1Conversation.identifier,self.selfToUser2Conversation.identifier,self.groupConversation.identifier]],
                                  [ZMTransportRequest requestGetFromPath:[NSString stringWithFormat:@"/users?ids=%@,%@,%@", self.selfUser.identifier, self.user1.identifier, self.user2.identifier]],
                                  [ZMTransportRequest requestGetFromPath:[NSString stringWithFormat:@"/users?ids=%@", self.user3.identifier]],
                                  [ZMTransportRequest requestGetFromPath:@"/self"],
                                  [ZMTransportRequest imageGetRequestFromPath:[NSString stringWithFormat:@"/assets/%@?conv_id=%@",self.selfUser.smallProfileImageIdentifier,self.selfUser.identifier]],
                                  [ZMTransportRequest imageGetRequestFromPath:[NSString stringWithFormat:@"/assets/%@?conv_id=%@",self.selfUser.mediumImageIdentifier, self.selfUser.identifier]],
                                  [ZMTransportRequest requestWithPath:@"/onboarding/v3" method:ZMMethodPOST payload:@{
                                                                                                                      @"cards" : @[],
                                                                                                                      @"self" : @[@"r6E0oILa7PsAlgL+tap6ZEYhOm2y3SVfKJe1eDTVKcw="]
                                                                                                                      }]
                                  ];
    
    // then
    NSMutableArray *mutableRequests = [self.mockTransportSession.receivedRequests mutableCopy];
    __block NSUInteger clientRegistrationCallCount = 0;
    [self.mockTransportSession.receivedRequests enumerateObjectsUsingBlock:^(ZMTransportRequest *request, NSUInteger idx, BOOL *stop) {
        NOT_USED(stop);
        if ([request.path containsString:@"clients"] && request.method == ZMMethodPOST) {
            [mutableRequests removeObjectAtIndex:idx];
            clientRegistrationCallCount++;
        }
    }];
    XCTAssertEqual(clientRegistrationCallCount, 1u);
    
    AssertArraysContainsSameObjects(expectedRequests, mutableRequests);
}

- (void)testThatItDoesAQuickSyncOnStartupIfAfterARestartWithoutAnyPushNotification
{
    // given
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    WaitForEverythingToBeDone();
    
    [self.mockTransportSession resetReceivedRequests];
    
    // when
    [self recreateUserSessionAndWipeCache:NO];
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    WaitForEverythingToBeDone();
    
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
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);

    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        NOT_USED(session);
        ZMGenericMessage *message = [ZMGenericMessage messageWithText:@"Hello, Test!" nonce:NSUUID.createUUID.transportString expiresAfter:nil];
        [self.groupConversation encryptAndInsertDataFromClient:self.user1.clients.anyObject toClient:self.selfUser.clients.anyObject data:message.data];
    }];
    WaitForEverythingToBeDone();
    
    [self.mockTransportSession resetReceivedRequests];
    
    // when
    [self recreateUserSessionAndWipeCache:NO];
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    WaitForEverythingToBeDone();
    
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
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        NOT_USED(session);
        ZMGenericMessage *message = [ZMGenericMessage messageWithText:@"Hello, Test!" nonce:NSUUID.createUUID.transportString expiresAfter:nil];
        [self.groupConversation encryptAndInsertDataFromClient:self.user1.clients.anyObject toClient:self.selfUser.clients.anyObject data:message.data];
    }];
    WaitForEverythingToBeDone();
    
    [self.mockTransportSession resetReceivedRequests];
    
    // when
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        [session simulatePushChannelClosed];
        [session simulatePushChannelOpened];
    }];
    WaitForEverythingToBeDone();
    
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
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        NOT_USED(session);
        ZMGenericMessage *message = [ZMGenericMessage messageWithText:@"Hello, Test!" nonce:NSUUID.createUUID.transportString expiresAfter:nil];
        [self.groupConversation encryptAndInsertDataFromClient:self.user1.clients.anyObject toClient:self.selfUser.clients.anyObject data:message.data];
    }];
    WaitForEverythingToBeDone();
    
    [self.mockTransportSession resetReceivedRequests];

    // make /notifications fail
    self.mockTransportSession.responseGeneratorBlock = ^ZMTransportResponse *(ZMTransportRequest *request) {
        if([request.path hasPrefix:@"/notifications"]) {
            return [ZMTransportResponse responseWithPayload:nil HTTPStatus:400 transportSessionError:nil];
        }
        return nil;
    };

    
    // when
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        [session simulatePushChannelClosed];
        [session simulatePushChannelOpened];
    }];
    WaitForEverythingToBeDone();
    
    // then
    BOOL hasNotificationsRequest = NO;
    BOOL hasConversationsRequest = NO;
    BOOL hasConnectionsRequest = NO;
    
    for (ZMTransportRequest *request in self.mockTransportSession.receivedRequests) {
        
        if ([request.path hasPrefix:@"/notifications"]) {
            hasNotificationsRequest = YES;
        }
        if ([request.path hasPrefix:@"/conversations?ids="]) {
            hasConversationsRequest = YES;
        }
        if ([request.path hasPrefix:@"/connections?size="]) {
            hasConnectionsRequest = YES;
        }
    }
    
    XCTAssertTrue(hasNotificationsRequest);
    XCTAssertTrue(hasConversationsRequest);
    XCTAssertTrue(hasConnectionsRequest);
}

- (void)testThatTheUIIsNotifiedWhenTheSyncIsComplete
{
    // given
    id observer = [OCMockObject mockForProtocol:@protocol(ZMNetworkAvailabilityObserver)];
    [ZMNetworkAvailabilityChangeNotification addNetworkAvailabilityObserver:observer userSession:self.userSession];
    
    // expect
    NSMutableArray *receivedNotes = [NSMutableArray array];
    [[observer stub] didChangeAvailability:[OCMArg checkWithBlock:^BOOL(ZMNetworkAvailabilityChangeNotification *note) {
        [receivedNotes addObject:note];
        return YES;
    }]];
    
    // when
    XCTAssertTrue([self logInAndWaitForSyncToBeComplete]);
    
    // then
    [observer verify];
    [ZMNetworkAvailabilityChangeNotification removeNetworkAvailabilityObserver:observer];
    
    XCTAssertEqual(receivedNotes.count, 2u);
    ZMNetworkAvailabilityChangeNotification *note1 = receivedNotes[0];
    ZMNetworkAvailabilityChangeNotification *note2 = receivedNotes[1];

    XCTAssertNotNil(note1);
    XCTAssertNotNil(note2);

    XCTAssertEqual(note1.networkState, ZMNetworkStateOnlineSynchronizing);
    XCTAssertEqual(note2.networkState, ZMNetworkStateOnline);
    
    XCTAssertEqual(self.userSession.networkState, ZMNetworkStateOnline);
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

- (ZMConversation *)findConversationWithUUID:(NSUUID *)UUID inMoc:(NSManagedObjectContext *)moc
{
    ZMConversation *conversation = [ZMConversation conversationWithRemoteID:UUID createIfNeeded:NO inContext:moc];
    XCTAssertNotNil(conversation);
    return conversation;
}

@end
