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


import XCTest
import WireTesting
@testable import WireSyncEngine

private final class TestPushDispatcherClient: NSObject, PushDispatcherOptionalClient {
    var pushTokens: [PushToken] = []
    var canHandlePayloads: [[AnyHashable: Any]] = []
    var receivedPayloads: [[AnyHashable: Any]] = []
    
    var canHandleNext: Bool = true
    
    func updatedPushToken(to token: PushToken) {
        pushTokens.append(token)
    }
    
    func canHandle(payload: [AnyHashable: Any]) -> Bool {
        canHandlePayloads.append(payload)
        return canHandleNext
    }
    
    func receivedPushNotification(with payload: [AnyHashable : Any], from source: ZMPushNotficationType, completion: ZMPushNotificationCompletionHandler?) {
        receivedPayloads.append(payload)
    }
}

public final class PushDispatcherTests: XCTestCase {
    let sut = PushDispatcher()
    
    func testThatItDoesNotRetainTheObservers() {
        weak var observerWeakReference: TestPushDispatcherClient?
        var observer: TestPushDispatcherClient?
        autoreleasepool { _ in
            // GIVEN
            observer = TestPushDispatcherClient()
            observerWeakReference = observer
            // WHEN 
            sut.add(client: observer!)
            observer = nil
        }
        // THEN
        
        XCTAssertNil(observerWeakReference)
    }
    
    func testThatItDoesNotRetainTheFallbackObserver() {
        
    }
    
    func testThatItForwardTheRegistrationEvent() {
        
    }
    
    func testThatItForwardsThePushTokenToNewObserver() {
        
    }
    
    func testThatItAsksObserverIfItCanHandleThePush() {
        
    }
    
    func testThatItInvokesFallbackObserverForPushWithoutUser() {
        
    }
    
    func testThatItForwardsTheNotificationToTheObserver() {
        
    }
    
    func testThatItForwardsTheNotificationToFallbackObserver() {
        
    }
    /*
     
     - (void)testThatItReregistersPushTokensOnDemand
     {
     XCTAssertTrue([self login]);
     
     // given
     NSData *token = [NSData dataWithBytes:@"abc" length:3];
     NSData *newToken = [NSData dataWithBytes:@"def" length:6];
     
     PushDispatcher *pushDispatcher = [[PushDispatcher alloc] init];
     pushDispatcher.
     // when
     XCTAssertTrue([self registerForNotifications:token]);
     
     // then
     ZMTransportRequest *request = self.mockTransportSession.receivedRequests.lastObject;
     XCTAssertEqualObjects(request.path, @"/push/tokens");
     [self.mockTransportSession resetReceivedRequests];
     
     // expect
     id mockPushRegistrant = [OCMockObject partialMockForObject:self.pushDispatcher.pushRegistrant];
     [(ZMPushRegistrant *)[[mockPushRegistrant expect] andReturn:newToken] pushToken];
     ZM_WEAK(self);
     self.application.registerForRemoteNotificationsCallback = ^{
     ZM_STRONG(self);
     [self.userSession performChanges:^{
     [self.userSession updatedPushTokenToVoipData:newToken];
     }];
     };
     
     // when
     [self.userSession resetPushTokens];
     WaitForAllGroupsToBeEmpty(0.5);
     
     // then
     BOOL didContainSignalingKeyRequest = NO;
     XCTAssertEqual(self.mockTransportSession.receivedRequests.count, 3u);
     for (ZMTransportRequest *aRequest in self.mockTransportSession.receivedRequests) {
     if ([aRequest.path containsString:@"/clients/"] && [aRequest.payload asDictionary][@"sigkeys"] != nil) {
     didContainSignalingKeyRequest = YES;
     }
     }
     XCTAssertTrue(didContainSignalingKeyRequest);
     XCTAssertTrue([self lastRequestsContainedTokenRequests]);
     XCTAssertEqual(self.application.registerForRemoteNotificationCount, 2u);
     [mockPushRegistrant verify];
     }
     
     - (void)testThatItReregistersPushTokensOnDemandEvenIfItDidNotChange
     {
     XCTAssertTrue([self login]);
     
     // given
     NSData *token = [NSData dataWithBytes:@"abc" length:3];
     
     [self registerForNotifications:token];
     XCTAssertTrue([self lastRequestsContainedTokenRequests]);
     [self.mockTransportSession resetReceivedRequests];
     
     // expect
     id mockPushRegistrant = [OCMockObject partialMockForObject:self.userSession.pushRegistrant];
     [(ZMPushRegistrant *)[[mockPushRegistrant expect] andReturn:token] pushToken];
     ZM_WEAK(self);
     self.application.registerForRemoteNotificationsCallback = ^{
     ZM_STRONG(self);
     [self.userSession performChanges:^{
     [self.userSession updatedPushTokenToVoipData:token];
     }];
     };
     
     // when
     [self.userSession performChanges:^{
     [self.userSession resetPushTokens];
     }];
     WaitForAllGroupsToBeEmpty(1.0);
     
     // then
     BOOL didContainSignalingKeyRequest = NO;
     XCTAssertEqual(self.mockTransportSession.receivedRequests.count, 3u);
     for (ZMTransportRequest *aRequest in self.mockTransportSession.receivedRequests) {
     if ([aRequest.path containsString:@"/clients/"] && [aRequest.payload asDictionary][@"sigkeys"] != nil) {
     didContainSignalingKeyRequest = YES;
     }
     }
     XCTAssertTrue(didContainSignalingKeyRequest);
     XCTAssertTrue([self lastRequestsContainedTokenRequests]);
     XCTAssertEqual(self.application.registerForRemoteNotificationCount, 2u);
     [mockPushRegistrant verify];
     }

 */
}
