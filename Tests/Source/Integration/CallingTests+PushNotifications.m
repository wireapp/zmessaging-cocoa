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


@interface CallingTests (PushNotifications)

@end

@implementation CallingTests (PushNotifications)

- (void)simulateReceivePushNotification:(NSDictionary *)payload
{
    PKPushPayload *pkPayload = [OCMockObject niceMockForClass:[PKPushPayload class]];
    [(PKPushPayload *)[[(id)pkPayload stub] andReturn:payload] dictionaryPayload];
    [(PKPushPayload *)[[(id)pkPayload stub] andReturn:PKPushTypeVoIP] type];
    [self.userSession.pushRegistrant pushRegistry:nil didReceiveIncomingPushWithPayload:pkPayload forType:pkPayload.type];
}

- (void)testThatItJoinsACallFromPushNotifications
{
    // given
    [self otherJoinCall];
    WaitForAllGroupsToBeEmpty(0.5);
    
    XCTAssert([self logIn]);
    WaitForAllGroupsToBeEmpty(0.5);
    
    id application = self.userSession.application;
    [(UIApplication *)[[application expect] andReturnValue:@(UIApplicationStateBackground)] applicationState];
    [(UIApplication *)[[application expect] andReturnValue:@(UIApplicationStateBackground)] applicationState];
    [(UIApplication *)[[application expect] andReturnValue:@(UIApplicationStateBackground)] applicationState];
    __block UILocalNotification *notification;
    [[application expect] scheduleLocalNotification:[OCMArg checkWithBlock:^BOOL(id obj) {
        notification = obj;
        return YES;
    }]];
    XCTAssertEqual(self.conversationUnderTest.callParticipants.count, 0u);
    
    NSDictionary *payload = [self payloadForCallStateEventInConversation:self.conversationUnderTest othersAreJoined:YES selfIsJoined:NO otherIsSendingVideo:NO selfIsSendingVideo:NO sequence:nil];
    
    // (1) when we recieve a push notification
    {
        [self simulateReceivePushNotification:@{@"data": @{@"payload": @[payload],
                                                           @"id": [NSUUID createUUID].transportString
                                                           }
                                                }];
        WaitForAllGroupsToBeEmpty(0.5);
        
        // then
        [application verify];
        XCTAssertNotNil(notification);
        XCTAssertEqualObjects(notification.alertBody, @"Extra User2 is calling");
        XCTAssertEqual(self.conversationUnderTest.callParticipants.count, 1u);
    }
    
    [self.mockTransportSession resetReceivedRequests];
    [application stopMocking];

    // (2) we press on the action
    {
        XCTestExpectation *expectation = [self expectationWithDescription:@"call state event sent"];
        self.mockTransportSession.responseGeneratorBlock = ^ZMTransportResponse *(ZMTransportRequest *request){
            if ([request.path containsString:@"call/state"]) {
                [expectation fulfill];
            }
            return nil;
        };
        [(UIApplication *)[[application expect] andReturnValue:@(UIApplicationStateInactive)] applicationState];
        [self.userSession application:self.userSession.application handleActionWithIdentifier:ZMCallAcceptAction forLocalNotification:notification responseInfo:nil completionHandler:nil];

        XCTAssert([self waitForCustomExpectationsWithTimeout:0.5]);
        WaitForAllGroupsToBeEmpty(0.5);

        // then
        XCTAssertTrue([self lastRequestContainsSelfStateJoined]);
        XCTAssertEqual(self.conversationUnderTest.callParticipants.count, 2u);
    }
    [application stopMocking];
}

- (void)testThatItJoinsAVideoCallFromAPushNotification_DuringEventProcessingState
{
    // given
    [self otherJoinVideoCall];
    WaitForAllGroupsToBeEmpty(0.5);
    
    XCTAssert([self logIn]);
    WaitForAllGroupsToBeEmpty(0.5);
    
    id application = self.userSession.application;
    [(UIApplication *)[[application expect] andReturnValue:@(UIApplicationStateBackground)] applicationState];
    [(UIApplication *)[[application expect] andReturnValue:@(UIApplicationStateBackground)] applicationState];
    [(UIApplication *)[[application expect] andReturnValue:@(UIApplicationStateBackground)] applicationState];
    
    __block UILocalNotification *notification;
    [[application expect] scheduleLocalNotification:[OCMArg checkWithBlock:^BOOL(id obj) {
        notification = obj;
        return YES;
    }]];
    
    NSDictionary *payload = [self payloadForCallStateEventInConversation:self.conversationUnderTest othersAreJoined:YES selfIsJoined:NO otherIsSendingVideo:YES selfIsSendingVideo:NO sequence:nil];
    
    // (1) when we recieve a push notification
    {
        [self simulateReceivePushNotification:@{@"data": @{@"payload": @[payload],
                                                           @"id": [NSUUID createUUID].transportString
                                                           }
                                                }];
        WaitForAllGroupsToBeEmpty(0.5);
        
        // then
        [application verify];
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
        [(UIApplication *)[[application expect] andReturnValue:@(UIApplicationStateInactive)] applicationState];
        [self.userSession application:self.userSession.application handleActionWithIdentifier:ZMCallAcceptAction forLocalNotification:notification responseInfo:nil completionHandler:nil];

        XCTAssert([self waitForCustomExpectationsWithTimeout:0.5]);
        WaitForAllGroupsToBeEmpty(0.5);

        // then
        XCTAssertTrue([self lastRequestContainsSelfStateJoined]);
        XCTAssertEqual(self.conversationUnderTest.callParticipants.count, 2u);
    }
    
    [application stopMocking];
}

- (void)simulateRestartWithoutEnteringEventProcessing
{
    __block BOOL shouldBlockRequests = NO;
    self.mockTransportSession.responseGeneratorBlock = ^ZMTransportResponse *(ZMTransportRequest *request){
        if ([request.path containsString:@"/notifications"]) {
            shouldBlockRequests = YES;
        }
        
        if (shouldBlockRequests && ! [request.path containsString:@"fallback"]) {
            return ResponseGenerator.ResponseNotCompleted;
        }
        
        return nil;
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
}

- (void)testThatItJoinsAVideoCallFromAPushNotification_DuringSyncState
{
    // given
    [self otherJoinCall];
    WaitForAllGroupsToBeEmpty(0.5);
    
    XCTAssert([self logInAndWaitForSyncToBeComplete]);
    WaitForAllGroupsToBeEmpty(0.5);
    [self.mockTransportSession performRemoteChanges:^(MockTransportSession<MockTransportSessionObjectCreation> *session) {
        [session simulatePushChannelClosed];
    }];
    WaitForAllGroupsToBeEmpty(0.5);

    [self simulateRestartWithoutEnteringEventProcessing];
    
    XCTestExpectation *notificationExpectation = [self expectationWithDescription:@"Schedule notification"];
    
    id application = self.userSession.application;
    [(UIApplication *)[[application expect] andReturnValue:@(UIApplicationStateBackground)] applicationState];
    [(UIApplication *)[[application expect] andReturnValue:@(UIApplicationStateBackground)] applicationState];
    [(UIApplication *)[[application expect] andReturnValue:@(UIApplicationStateBackground)] applicationState];
    
    __block UILocalNotification *notification;
    
    [[application expect] scheduleLocalNotification:[OCMArg checkWithBlock:^BOOL(id obj) {
        notification = obj;
        [notificationExpectation fulfill];
        return YES;
    }]];
    XCTAssertEqual(self.conversationUnderTest.callParticipants.count, 0u);

    NSDictionary *payload = [self payloadForCallStateEventInConversation:self.conversationUnderTest othersAreJoined:YES selfIsJoined:NO otherIsSendingVideo:YES selfIsSendingVideo:NO sequence:nil];
    
    // (1) when we recieve a push notification
    {
        [self simulateReceivePushNotification:@{@"data": @{@"payload": @[payload],
                                                           @"id": [NSUUID createUUID].transportString
                                                           }
                                                }];
        
        XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0.5]);
        WaitForAllGroupsToBeEmpty(0.5);
        
        // then
        [application verify];
        XCTAssertNotNil(notification);
        XCTAssertEqualObjects(notification.alertBody, @"Extra User2 is video calling");
        XCTAssertEqual(self.conversationUnderTest.callParticipants.count, 1u);
    }

    
    // (2) we press on the action
    {
        [(UIApplication *)[[application expect] andReturnValue:@(UIApplicationStateInactive)] applicationState];
        [self.userSession application:self.userSession.application handleActionWithIdentifier:ZMCallAcceptAction forLocalNotification:notification responseInfo:nil completionHandler:nil];
        WaitForAllGroupsToBeEmpty(0.5);
        
        // then
        XCTAssertFalse([self lastRequestContainsSelfStateJoined]);
        XCTAssertTrue(self.userSession.didStartInitialSync);
        XCTAssertTrue(self.userSession.isPerformingSync);
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

        [self.mockTransportSession completeAllBlockedRequests];
        
        XCTAssert([self waitForCustomExpectationsWithTimeout:0.5]);
        WaitForAllGroupsToBeEmpty(0.5);

        // then
        XCTAssertTrue([self lastRequestContainsSelfStateJoined]);
        XCTAssertTrue(self.userSession.didStartInitialSync);
        XCTAssertFalse(self.userSession.isPerformingSync);
        XCTAssertEqual(self.conversationUnderTest.callParticipants.count, 2u);
    }
    [application stopMocking];
}

@end