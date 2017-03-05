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
@import WireMessageStrategy;

#import "StateBaseTest.h"
#import "ZMBackgroundTaskState.h"
#import "ZMSyncStateMachine.h"
#import "ZMStateMachineDelegate.h"

@interface ZMBackgroundTaskStateTests : StateBaseTest

@property (nonatomic, readonly) ZMBackgroundTaskState *sut;
@property (nonatomic) NSMutableArray *results;
@property (nonatomic) NSMutableArray *forwardedRequests;

@end



@implementation ZMBackgroundTaskStateTests

- (void)setUp
{
    [super setUp];
    _sut = [[ZMBackgroundTaskState alloc] initWithAuthenticationCenter:self.authenticationStatus
                                               clientRegistrationStatus:self.clientRegistrationStatus
                                                objectStrategyDirectory:self.objectDirectory
                                                   stateMachineDelegate:self.stateMachine];
    
    NSMutableArray *results = [NSMutableArray array];
    self.results = results;
    self.sut.taskCompletionHandler = ^(ZMBackgroundTaskResult result){
        [results addObject:@(result)];
    };
    self.sut.maximumTimeInState = 1.0;
    
    self.forwardedRequests = [NSMutableArray array];
}

- (void)tearDown
{
    self.sut.taskCompletionHandler = nil;
    _sut = nil;
    [super tearDown];
}

- (void)testThatThePolicyIsToDiscardEvents
{
    XCTAssertEqual(self.sut.updateEventsPolicy, ZMUpdateEventPolicyIgnore);
}

- (void)testThatItDoesNotSwitchToSlowSyncState
{
    // expectation
    [[(id)self.stateMachine reject] startQuickSync];
    
    // when
    [self.sut didRequestSynchronization];
}

- (void)testThatItDoesNotSwitchToBackgroundState
{
    // expectation
    [[(id)self.stateMachine reject] goToState:OCMOCK_ANY];
    
    // when
    [self.sut didEnterBackground];
}

- (void)testThatItDoesSwitchToQuickSyncOnEnteringForeground
{
    // expectation
    [[(id)self.stateMachine expect] startQuickSync];
    
    // when
    [self.sut didEnterForeground];
}

- (void)simulateRequest
{
    ZMTransportRequest *request = [ZMTransportRequest requestGetFromPath:@"path"];
    [[[(id)self.objectDirectory.clientMessageTranscoder expect] andReturn:request] nextRequest];
}

- (void)simulateNoRequest
{
    [[[(id)self.objectDirectory.clientMessageTranscoder expect] andReturn:nil] nextRequest];
}

- (void)testThatItWaitsForResponse;
{
    // given
    [self simulateRequest];

    // expect
    [[(id) self.stateMachine reject] goToState:OCMOCK_ANY];

    // when
    ZMTransportRequest *receivedRequest = [self.sut nextRequest];
    XCTAssertNotNil(receivedRequest);
}

- (void)testThatItTransistionsAfterResponse_Success;
{
    // given
    [self simulateRequest];
    
    // when
    ZMTransportRequest *receivedRequest = [self.sut nextRequest];
    XCTAssertNotNil(receivedRequest);
    
    // and when
    [receivedRequest completeWithResponse:[ZMTransportResponse responseWithPayload:@{} HTTPStatus:200 transportSessionError:nil]];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // expect
    [self simulateNoRequest];
    [[[(id) self.stateMachine expect] andDo:^(NSInvocation *inv) {
        NOT_USED(inv);
        [self.sut didLeaveState];
    }] goToState:self.stateMachine.preBackgroundState];
    
    // when
    (void)[self.sut nextRequest];
    WaitForAllGroupsToBeEmpty(0.5);

    // then
    NSNumber *result = self.results.lastObject;
    XCTAssertEqualObjects(result, @(ZMBackgroundTaskResultSucceed));
}


- (void)testThatItTransistionsAfterResponse_PermanentError;
{
    // given
    [self simulateRequest];
    
    // when
    ZMTransportRequest *receivedRequest = [self.sut nextRequest];
    XCTAssertNotNil(receivedRequest);
    
    // and when
    NSError *error = [NSError errorWithDomain:ZMTransportSessionErrorDomain code:ZMTransportSessionErrorCodeAuthenticationFailed userInfo:nil];
    [receivedRequest completeWithResponse:[ZMTransportResponse responseWithPayload:@{} HTTPStatus:0 transportSessionError:error]];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // expect
    [self simulateNoRequest];
    [[[(id) self.stateMachine expect] andDo:^(NSInvocation *inv) {
        NOT_USED(inv);
        [self.sut didLeaveState];
    }] goToState:self.stateMachine.preBackgroundState];
    
    // when
    (void)[self.sut nextRequest];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    NSNumber *result = self.results.lastObject;
    XCTAssertEqualObjects(result, @(ZMBackgroundTaskResultFailed));
}

- (void)testThatItDoesNotTransistionsAfterResponse_MissingClients
{
    // given
    [self simulateRequest];
    
    // when
    ZMTransportRequest *receivedRequest = [self.sut nextRequest];
    XCTAssertNotNil(receivedRequest);
    
    // and when
    NSError *error = [NSError errorWithDomain:ZMTransportSessionErrorDomain code:ZMTransportSessionErrorCodeAuthenticationFailed userInfo:nil];
    [receivedRequest completeWithResponse:[ZMTransportResponse responseWithPayload:@{@"missing": @{@"client": @"someID"}} HTTPStatus:0 transportSessionError:error]];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // expect
    [self simulateNoRequest];
    [[(id) self.stateMachine reject] goToState:OCMOCK_ANY];
    
    // when
    (void)[self.sut nextRequest];
    
    // and when
    [self.sut didLeaveState];
    
    // then
    NSNumber *result = self.results.lastObject;
    XCTAssertEqualObjects(result, @(ZMBackgroundTaskResultFailed));
}

- (void)testThatItTransistionsAfterResponse_Expired;
{
    // given
    [self simulateRequest];
    
    // when
    ZMTransportRequest *receivedRequest = [self.sut nextRequest];
    XCTAssertNotNil(receivedRequest);
    
    // and when
    NSError *error = [NSError errorWithDomain:ZMTransportSessionErrorDomain code:ZMTransportSessionErrorCodeRequestExpired userInfo:nil];
    [receivedRequest completeWithResponse:[ZMTransportResponse responseWithPayload:@{} HTTPStatus:0 transportSessionError:error]];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // expect
    [self simulateNoRequest];
    [[[(id) self.stateMachine expect] andDo:^(NSInvocation *inv) {
        NOT_USED(inv);
        [self.sut didLeaveState];
    }] goToState:self.stateMachine.preBackgroundState];
    
    // when
    (void)[self.sut nextRequest];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    NSNumber *result = self.results.lastObject;
    XCTAssertEqualObjects(result, @(ZMBackgroundTaskResultFailed));
}

- (void)testThatItTransitionsToThePreBackgroundStateWhenTimerFinishes;
{
    // expect
    [[(id) self.stateMachine expect] goToState:self.stateMachine.preBackgroundState];
    [(ZMSyncStateMachine *)[[(id) self.stateMachine expect] andReturn:self.sut] currentState];
    [[(id) self.stateMachine reject] goToState:OCMOCK_ANY];
    
    // when
    [self.sut didEnterState];
    
    [self performIgnoringZMLogError:^{
        [self spinMainQueueWithTimeout:self.sut.maximumTimeInState+0.5];
    }];
    
    // then
    [(id) self.stateMachine verify];
    
    XCTAssertEqual(self.results.count, 1u);
    NSNumber *result = self.results.lastObject;
    XCTAssertEqualObjects(result, @(ZMBackgroundTaskResultFailed));
}


@end

