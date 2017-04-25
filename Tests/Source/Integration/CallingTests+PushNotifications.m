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


@import PushKit;
#import "CallingTests.h"
#import "ZMUserSession+UserNotificationCategories.h"
#import "WireSyncEngine_iOS_Tests-Swift.h"



@interface CallingTests (PushNotifications)

@end

@implementation CallingTests (PushNotifications)

- (void)simulateReceivePushNotificationWithPayload:(NSDictionary *)payload identifier:(NSUUID *)identifier fromUser:(MockUser *)user
{
    NSDictionary *pushPayload = @{ @"data": @{ @"id": identifier.transportString, @"payload": @[payload] } };

    PKPushPayload *pkPayload = [OCMockObject niceMockForClass:[PKPushPayload class]];
    [(PKPushPayload *)[[(id)pkPayload stub] andReturn:pushPayload] dictionaryPayload];
    [(PKPushPayload *)[[(id)pkPayload stub] andReturn:PKPushTypeVoIP] type];
    PKPushRegistry *mockPushRegistry = [OCMockObject niceMockForClass:[PKPushRegistry class]];
    [self.userSession.pushRegistrant pushRegistry:mockPushRegistry didReceiveIncomingPushWithPayload:pkPayload forType:pkPayload.type];
    [self.mockTransportSession registerPushEvent:[MockPushEvent eventWithPayload:payload uuid:identifier fromUser:user isTransient:YES]];

    WaitForEverythingToBeDone();
}

- (ZMTransportResponse *)notificationFetchResponseForRequest:(ZMTransportRequest *)request payload:(NSDictionary *)payload identifier:(NSUUID *)identifier
{
    ZMUser *selfUser = [self userForMockUser:self.selfUser];
    NSString *suffix = [NSString stringWithFormat:@"&client=%@&cancel_fallback=%@",
                        selfUser.selfClient.remoteIdentifier, identifier.transportString];

    if (request.method == ZMMethodGET &&
        [request.path containsString:@"/notifications?size=500"] &&
        [request.path containsString:suffix]) {
        return [ZMTransportResponse responseWithPayload:@{ @"hasMore": @NO, @"notifications": @[payload] }
                                             HTTPStatus:200
                                  transportSessionError:nil];
    }

    return nil;
}

- (void)testThatItJoinsACallFromPushNotifications
{
    // given
    [self otherJoinCall];
    WaitForAllGroupsToBeEmpty(0.5);
    
    XCTAssert([self logIn]);
    WaitForAllGroupsToBeEmpty(0.5);
    
    [self.application setBackground];
    XCTAssertEqual(self.conversationUnderTest.callParticipants.count, 0u);
    
    ZMUser *user2 = [self userForMockUser:self.user2];
    NSDictionary *payload = [self payloadForCallStateEventInConversation:self.conversationUnderTest joinedUsers:@[user2] videoSendingUsers:@[] sequence:@1 session:@"session1"];
    UILocalNotification *notification;
    // (1) when we recieve a push notification
    {
        [self simulateReceivePushNotificationWithPayload:payload identifier:NSUUID.timeBasedUUID fromUser:self.user2];
        WaitForAllGroupsToBeEmpty(0.5);
        
        // then
        notification = self.application.scheduledLocalNotifications.firstObject;
        XCTAssertNotNil(notification);
        XCTAssertEqualObjects(notification.alertBody, @"Extra User2 is calling");
        XCTAssertEqual(self.conversationUnderTest.callParticipants.count, 1u);
    }
    
    [self.mockTransportSession resetReceivedRequests];

    // (2) we press on the action
    {
        XCTestExpectation *expectation = [self expectationWithDescription:@"call state event sent"];
        self.mockTransportSession.responseGeneratorBlock = ^ZMTransportResponse *(ZMTransportRequest *request){
            if ([request.path containsString:@"call/state"]) {
                [expectation fulfill];
            }
            return nil;
        };
        [self.application setInactive];
        [self.userSession application:self.userSession.application handleActionWithIdentifier:ZMCallAcceptAction forLocalNotification:notification responseInfo:nil completionHandler:nil];

        XCTAssert([self waitForCustomExpectationsWithTimeout:0.5]);
        WaitForAllGroupsToBeEmpty(0.5);

        // then
        XCTAssertTrue([self lastRequestContainsSelfStateJoined]);
        XCTAssertEqual(self.conversationUnderTest.callParticipants.count, 2u);
    }
}

- (void)testThatItJoinsAVideoCallFromAPushNotification_DuringEventProcessingState
{
    // given
    [self otherJoinVideoCall];
    WaitForAllGroupsToBeEmpty(0.5);
    
    XCTAssert([self logIn]);
    WaitForAllGroupsToBeEmpty(0.5);
    [self.application setBackground];
    ZMUser *user2 = [self userForMockUser:self.user2];
    NSDictionary *payload = [self payloadForCallStateEventInConversation:self.conversationUnderTest joinedUsers:@[user2] videoSendingUsers:@[user2] sequence:@1 session:@"session1"];
    
    // (1) when we recieve a push notification
    UILocalNotification *notification;
    {
        [self simulateReceivePushNotificationWithPayload:payload identifier:NSUUID.timeBasedUUID fromUser:self.user2];
        WaitForAllGroupsToBeEmpty(0.5);
        
        // then
        notification = self.application.scheduledLocalNotifications.firstObject;
        XCTAssertNotNil(notification);
        XCTAssertEqualObjects(notification.alertBody, @"Extra User2 is video calling");
        XCTAssertEqual(self.conversationUnderTest.callParticipants.count, 1u);
    }
    
    [self.mockTransportSession resetReceivedRequests];
    
    // (2) we press on the action
    {
        XCTestExpectation *expectation = [self expectationWithDescription:@"call state event sent"];
        self.mockTransportSession.responseGeneratorBlock = ^ZMTransportResponse *(ZMTransportRequest *request){
            if ([request.path containsString:@"call/state"]) {
                [expectation fulfill];
            }
            return nil;
        };
        [self.application setInactive];
        [self.userSession application:self.userSession.application handleActionWithIdentifier:ZMCallAcceptAction forLocalNotification:notification responseInfo:nil completionHandler:nil];

        XCTAssert([self waitForCustomExpectationsWithTimeout:0.5]);
        WaitForAllGroupsToBeEmpty(0.5);

        // then
        XCTAssertTrue([self lastRequestContainsSelfStateJoined]);
        XCTAssertEqual(self.conversationUnderTest.callParticipants.count, 2u);
    }
}

- (void)simulateRestartWithoutEnteringEventProcessingWithNotificationFetchResponse:(NSDictionary *)payload forIdentifier:(NSUUID *)identifier
{
    __block BOOL shouldBlockRequests = NO;
    self.mockTransportSession.responseGeneratorBlock = ^ZMTransportResponse *(ZMTransportRequest *request){
        if ([request.path containsString:@"/notifications"]) {
            shouldBlockRequests = YES;
        }
        
        if (shouldBlockRequests && ! [request.path containsString:@"cancel_fallback"]) {
            return ResponseGenerator.ResponseNotCompleted;
        }
        
        return [self notificationFetchResponseForRequest:request payload:payload identifier:identifier];
    };
    
    [self.mockTransportSession resetReceivedRequests];
    [self recreateUserSessionAndWipeCache:NO];
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        [session simulatePushChannelOpened];
    }];
    
    WaitForAllGroupsToBeEmpty(0.5);

    self.mockTransportSession.responseGeneratorBlock = nil;

    XCTAssertTrue(self.userSession.didStartInitialSync);
    XCTAssertTrue(self.userSession.isPerformingSync);

    WaitForEverythingToBeDone();
}

- (void)testThatItJoinsAVideoCallFromAPushNotification_DuringSyncState
{
    // given
    [self otherJoinCall];
    WaitForAllGroupsToBeEmpty(0.5);
    
    XCTAssert([self logInAndWaitForSyncToBeComplete]);
    WaitForAllGroupsToBeEmpty(0.5);
    
    ZMUser *user2 = [self userForMockUser:self.user2];
    NSDictionary *pushPayload = [self payloadForCallStateEventInConversation:self.conversationUnderTest
                                                                 joinedUsers:@[user2]
                                                           videoSendingUsers:@[user2]
                                                                    sequence:@1
                                                                     session:@"session2"];

    NSUUID *notificationId = NSUUID.timeBasedUUID;
    WaitForAllGroupsToBeEmpty(0.5);

    NSDictionary *streamPayload = @{ @"id": notificationId.transportString, @"payload": @[pushPayload] };
    [self simulateRestartWithoutEnteringEventProcessingWithNotificationFetchResponse:streamPayload forIdentifier:notificationId];
    
    UILocalNotification *notification;    
    
    [self.application setBackground];
    [self.application simulateApplicationDidEnterBackground];
    
    WaitForAllGroupsToBeEmpty(0.5);

    XCTAssertEqual(self.conversationUnderTest.callParticipants.count, 0u);
    
    // (1) when we recieve a push notification
    {
        [self simulateReceivePushNotificationWithPayload:pushPayload identifier:notificationId fromUser:self.user2];
        XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0.5]);
        WaitForAllGroupsToBeEmpty(0.5);
        
        // then
        notification = self.application.scheduledLocalNotifications.firstObject;
        XCTAssertNotNil(notification);
        XCTAssertEqualObjects(notification.alertBody, @"Extra User2 is video calling");
        XCTAssertEqual(self.conversationUnderTest.callParticipants.count, 1u);
    }
    
    // (2) we press on the action
    {
        [self.application setInactive];
        [self.userSession application:self.userSession.application handleActionWithIdentifier:ZMCallAcceptAction forLocalNotification:notification responseInfo:nil completionHandler:nil];
        WaitForAllGroupsToBeEmpty(0.5);

        // then
        XCTAssertFalse([self lastRequestContainsSelfStateJoined]);
        XCTAssertTrue(self.userSession.didStartInitialSync);
        XCTAssertEqual(self.conversationUnderTest.callParticipants.count, 1u);
    }

    // (3) we enter event processing state
    {
        XCTestExpectation *expectation = [self expectationWithDescription:@"call state event sent"];
        self.mockTransportSession.responseGeneratorBlock = ^ZMTransportResponse *(ZMTransportRequest *request){
            if ([request.path containsString:@"call/state"]) {
                [expectation fulfill];
            }
            return nil;
        };

        [[NSNotificationCenter defaultCenter] postNotificationName:UIApplicationWillEnterForegroundNotification object:nil];
        [self.mockTransportSession completeAllBlockedRequests];
        
        XCTAssert([self waitForCustomExpectationsWithTimeout:0.5]);
        WaitForAllGroupsToBeEmpty(0.5);

        // then
        XCTAssertTrue([self lastRequestContainsSelfStateJoined]);
        XCTAssertTrue(self.userSession.didStartInitialSync);
        XCTAssertFalse(self.userSession.isPerformingSync);
        XCTAssertEqual(self.conversationUnderTest.callParticipants.count, 2u);
    }
}

@end
