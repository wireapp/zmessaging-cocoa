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

#import "StateBaseTest.h"
#import "ZMBackgroundFetchState.h"
#import "ZMMissingUpdateEventsTranscoder.h"
#import "ZMAssetTranscoder.h"
#import "ZMSyncStateMachine.h"
#import "ZMStateMachineDelegate.h"


@interface ZMBackgroundFetchStateTests : StateBaseTest

@property (nonatomic, readonly) ZMBackgroundFetchState *sut;
@property (nonatomic) NSUUID *lastUpdateEventID;
@property (nonatomic) NSMutableArray *results;
@property (nonatomic) NSMutableArray *forwardedRequests;
@property (nonatomic) BOOL assetTranscoderHasOutstandingItems;
@property (nonatomic) BOOL missingUpdateEventsTranscoderIsDownloadingMissingNotifications;

@end



@implementation ZMBackgroundFetchStateTests

- (void)setUp
{
    [super setUp];
    _sut = [[ZMBackgroundFetchState alloc] initWithAuthenticationCenter:self.authenticationStatus
                                               clientRegistrationStatus:self.clientRegistrationStatus
                                                objectStrategyDirectory:self.objectDirectory
                                                   stateMachineDelegate:self.stateMachine];
    
    NSMutableArray *results = [NSMutableArray array];
    self.results = results;
    self.sut.fetchCompletionHandler = ^(ZMBackgroundFetchResult result){
        [results addObject:@(result)];
    };
    self.sut.maximumTimeInState = 1.0;
    
    self.lastUpdateEventID = [NSUUID createUUID];
    [[[(id) self.objectDirectory.missingUpdateEventsTranscoder stub] andCall:@selector(missingUpdateEventsTranscoderLastUpdateEventID) onObject:self] lastUpdateEventID];
    
    self.forwardedRequests = [NSMutableArray array];
}

- (void)tearDown
{
    self.sut.fetchCompletionHandler = nil;
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

- (void)testThatItStartDownloadingMissingEventsUponEnteringTheState;
{
    // given
    [[[(id) self.objectDirectory.missingUpdateEventsTranscoder stub] andCall:@selector(missingUpdateEventsTranscoderLastUpdateEventID) onObject:self] lastUpdateEventID];
    
    // expect
    [[(id) self.objectDirectory.missingUpdateEventsTranscoder expect] startDownloadingMissingNotifications];
    
    // when
    [self.sut didEnterState];
    
    // then
    [(id) self.objectDirectory.missingUpdateEventsTranscoder verify];
}

- (void)testThatItWaitsForMissingUpdateEvents;
{
    // given
    for (id transcoder in self.syncObjectsUsedByState) {
        [[[transcoder stub] andReturn:@[]] requestGenerators];
    }
    (void)[(ZMMissingUpdateEventsTranscoder *) [[(id) self.objectDirectory.missingUpdateEventsTranscoder stub] andReturnValue:@(YES)] isDownloadingMissingNotifications];
    (void)[(ZMAssetTranscoder *) [[(id) self.objectDirectory.assetTranscoder stub] andReturnValue:@(NO)] hasOutstandingItems];
    
    // expect
    [[(id) self.stateMachine reject] goToState:OCMOCK_ANY];
    
    // when
    (void) [self.sut nextRequest];
    (void) [self.sut nextRequest];
}

- (void)testThatItWaitsForAssets;
{
    // given
    for (id transcoder in self.syncObjectsUsedByState) {
        [[[transcoder stub] andReturn:@[]] requestGenerators];
    }
    (void)[(ZMMissingUpdateEventsTranscoder *) [[(id) self.objectDirectory.missingUpdateEventsTranscoder stub] andReturnValue:@(NO)] isDownloadingMissingNotifications];
    (void)[(ZMAssetTranscoder *) [[(id) self.objectDirectory.assetTranscoder stub] andReturnValue:@(YES)] hasOutstandingItems];
    
    // expect
    [[(id) self.stateMachine reject] goToState:OCMOCK_ANY];
    
    // when
    (void) [self.sut nextRequest];
    (void) [self.sut dataDidChange];
}

- (void)testThatItTransitionsToThePreBackgroundStateWhenDone;
{
    // given
    for (id transcoder in self.syncObjectsUsedByState) {
        [[[transcoder stub] andReturn:@[]] requestGenerators];
    }
    (void)[(ZMMissingUpdateEventsTranscoder *) [[(id) self.objectDirectory.missingUpdateEventsTranscoder stub] andReturnValue:@(NO)] isDownloadingMissingNotifications];
    (void)[(ZMAssetTranscoder *) [[(id) self.objectDirectory.assetTranscoder stub] andReturnValue:@(NO)] hasOutstandingItems];
    
    // expect
    [[(id) self.stateMachine expect] goToState:self.stateMachine.preBackgroundState];
    [[(id) self.stateMachine reject] goToState:OCMOCK_ANY];
    
    // when
    [self.sut nextRequest];
}

- (void)testThatItTransitionsToThePreBackgroundStateWhenTimerFinishes;
{
    // given
    [[[(id) self.objectDirectory.missingUpdateEventsTranscoder stub] andCall:@selector(missingUpdateEventsTranscoderLastUpdateEventID) onObject:self] lastUpdateEventID];
    [[(id) self.objectDirectory.missingUpdateEventsTranscoder stub] startDownloadingMissingNotifications];
    
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
    XCTAssertEqual(self.lastResult, ZMBackgroundFetchResultNoData);
}

- (void)testThatItCallsTheCompletionHandlerWithNewDataAfterDownloadingEvents;
{
    // given
    //
    // We have 1 /notifications request and 'lastUpdateEventID' changes.
    // But we have no asset request.
    [[(id) self.objectDirectory.missingUpdateEventsTranscoder stub] startDownloadingMissingNotifications];
    
    id requestGenerator = [OCMockObject niceMockForProtocol:@protocol(ZMRequestGenerator)];
    [[[requestGenerator stub] andCall:@selector(nextForwardedRequest) onObject:self] nextRequest];
    [[[(id) self.objectDirectory.missingUpdateEventsTranscoder stub] andReturn:@[requestGenerator]] requestGenerators];
    id request = [OCMockObject niceMockForClass:ZMTransportRequest.class];
    [self.forwardedRequests addObject:request];
    [[[(id) self.objectDirectory.assetTranscoder stub] andReturn:@[]] requestGenerators];
    
    
    (void)[(ZMMissingUpdateEventsTranscoder *) [[(id) self.objectDirectory.missingUpdateEventsTranscoder stub] andCall:@selector(missingUpdateEventsTranscoderIsDownloadingMissingNotifications) onObject:self] isDownloadingMissingNotifications];
    self.missingUpdateEventsTranscoderIsDownloadingMissingNotifications = YES;
    (void)[(ZMAssetTranscoder *) [[(id) self.objectDirectory.assetTranscoder stub] andReturnValue:@(NO)] hasOutstandingItems];
    
    // expect
    [[(id) self.stateMachine expect] goToState:self.stateMachine.preBackgroundState];
    
    // when (1)
    [self.sut didEnterState];
    XCTAssertNotNil([self.sut nextRequest]);
    XCTAssertNil([self.sut nextRequest]);
    self.missingUpdateEventsTranscoderIsDownloadingMissingNotifications = NO;
    self.lastUpdateEventID = [NSUUID createUUID];
    XCTAssertNil([self.sut nextRequest]);
    
    // then (1)
    XCTAssertEqual(self.results.count, 0u);
    
    // when (2)
    [(id) self.stateMachine verify];
    [self.sut didLeaveState];
    
    // then (2)
    XCTAssertEqual(self.results.count, 1u);
    XCTAssertEqual(self.lastResult, ZMBackgroundFetchResultNewData);
}

- (void)testThatItCallsTheCompletionHandlerWithNewDataAfterDownloadingAssets;
{
    // given
    //
    // 'lastUpdateEventID' does not change.
    // But we have 1 asset request.
    [[(id) self.objectDirectory.missingUpdateEventsTranscoder stub] startDownloadingMissingNotifications];
    [[[(id) self.objectDirectory.missingUpdateEventsTranscoder stub] andReturn:@[]] requestGenerators];
    id requestGenerator = [OCMockObject niceMockForProtocol:@protocol(ZMRequestGenerator)];
    [[[requestGenerator stub] andCall:@selector(nextForwardedRequest) onObject:self] nextRequest];
    [[[(id) self.objectDirectory.assetTranscoder stub] andReturn:@[requestGenerator]] requestGenerators];
    id request = [OCMockObject niceMockForClass:ZMTransportRequest.class];
    [self.forwardedRequests addObject:request];
    
    (void)[(ZMMissingUpdateEventsTranscoder *) [[(id) self.objectDirectory.missingUpdateEventsTranscoder stub] andReturnValue:@(NO)] isDownloadingMissingNotifications];
    (void)[(ZMAssetTranscoder *) [[(id) self.objectDirectory.assetTranscoder stub] andCall:@selector(assetTranscoderHasOutstandingItems) onObject:self] hasOutstandingItems];
    self.assetTranscoderHasOutstandingItems = YES;
    
    // expect
    [[(id) self.stateMachine expect] goToState:self.stateMachine.preBackgroundState];
    
    // when (1)
    [self.sut didEnterState];
    XCTAssertNotNil([self.sut nextRequest]);
    XCTAssertNil([self.sut nextRequest]);
    self.assetTranscoderHasOutstandingItems = NO;
    XCTAssertNil([self.sut nextRequest]);
    
    // then (1)
    XCTAssertEqual(self.results.count, 0u);
    
    // when (2)
    [(id) self.stateMachine verify];
    [self.sut didLeaveState];
    
    // then (2)
    XCTAssertEqual(self.results.count, 1u);
    XCTAssertEqual(self.lastResult, ZMBackgroundFetchResultNewData);
}

- (void)testThatItCallsTheCompletionHandlerWhenThereIsNoNewData;
{
    // given
    //
    // 'lastUpdateEventID' does not change. No assets to download.
    [[(id) self.objectDirectory.missingUpdateEventsTranscoder stub] startDownloadingMissingNotifications];
    [[[(id) self.objectDirectory.missingUpdateEventsTranscoder stub] andReturn:@[]] requestGenerators];
    [[[(id) self.objectDirectory.assetTranscoder stub] andReturn:@[]] requestGenerators];
    
    (void)[(ZMMissingUpdateEventsTranscoder *) [[(id) self.objectDirectory.missingUpdateEventsTranscoder stub] andReturnValue:@(NO)] isDownloadingMissingNotifications];
    (void)[(ZMAssetTranscoder *) [[(id) self.objectDirectory.assetTranscoder stub] andReturnValue:@(NO)] hasOutstandingItems];
    
    // expect
    [[(id) self.stateMachine expect] goToState:self.stateMachine.preBackgroundState];
    
    // when (1)
    [self.sut didEnterState];
    [self.sut nextRequest];
    
    // then (1)
    XCTAssertEqual(self.results.count, 0u);
    
    // when (2)
    [(id) self.stateMachine verify];
    [self.sut didLeaveState];
    
    // then (2)
    XCTAssertEqual(self.results.count, 1u);
    XCTAssertEqual(self.lastResult, ZMBackgroundFetchResultNoData);
}

- (void)testThatItCallsTheCompletionHandlerWithFailureUponFailure;
{
    // given
    //
    // We have 1 /notifications request that will fail.
    // 'lastUpdateEventID' changes.
    // But we have no asset request.
    [[(id) self.objectDirectory.missingUpdateEventsTranscoder stub] startDownloadingMissingNotifications];
    
    id requestGenerator = [OCMockObject niceMockForProtocol:@protocol(ZMRequestGenerator)];
    [[[requestGenerator stub] andCall:@selector(nextForwardedRequest) onObject:self] nextRequest];
    [[[(id) self.objectDirectory.missingUpdateEventsTranscoder stub] andReturn:@[requestGenerator]] requestGenerators];
    id request = [[ZMTransportRequest alloc] initWithPath:@"/foo" method:ZMMethodPOST payload:@{}];
    [self.forwardedRequests addObject:request];
    [[[(id) self.objectDirectory.assetTranscoder stub] andReturn:@[]] requestGenerators];
    NSError *error = [NSError errorWithDomain:ZMTransportSessionErrorDomain code:ZMTransportSessionErrorCodeAuthenticationFailed userInfo:nil];
    ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:nil HTTPStatus:0 transportSessionError:error];
    
    (void)[(ZMMissingUpdateEventsTranscoder *) [[(id) self.objectDirectory.missingUpdateEventsTranscoder stub] andCall:@selector(missingUpdateEventsTranscoderIsDownloadingMissingNotifications) onObject:self] isDownloadingMissingNotifications];
    self.missingUpdateEventsTranscoderIsDownloadingMissingNotifications = YES;
    (void)[(ZMAssetTranscoder *) [[(id) self.objectDirectory.assetTranscoder stub] andReturnValue:@(NO)] hasOutstandingItems];
    
    // expect
    [[(id) self.stateMachine expect] goToState:self.stateMachine.preBackgroundState];
    
    // when (1)
    [self.sut didEnterState];
    XCTAssertNotNil([self.sut nextRequest]);
    XCTAssertNil([self.sut nextRequest]);
    [request completeWithResponse:response];
    WaitForAllGroupsToBeEmpty(0.5);
    self.missingUpdateEventsTranscoderIsDownloadingMissingNotifications = NO;
    XCTAssertNil([self.sut nextRequest]);
    
    // then (1)
    XCTAssertEqual(self.results.count, 0u);
    
    // when (2)
    [(id) self.stateMachine verify];
    [self.sut didLeaveState];
    
    // then (2)
    XCTAssertEqual(self.results.count, 1u);
    XCTAssertEqual(self.lastResult, ZMBackgroundFetchResultFailed);
}

- (void)testThatItDoesNotDownloadEventsWhenWeHaveNoLastUpdateEventID;
{
    // given
    self.lastUpdateEventID = nil;
    
    // expect
    [[(id) self.stateMachine expect] goToState:self.stateMachine.preBackgroundState];
    
    // when (1)
    [self.sut didEnterState];
    
    // then (1)
    [(id) self.stateMachine verify];
    
    // when (2)
    [self.sut didLeaveState];
    
    // then (2)
    XCTAssertEqual(self.results.count, 1u);
    XCTAssertEqual(self.lastResult, ZMBackgroundFetchResultNoData);
}

- (void)testThatItReturnsTheFirstRequestReturnedByASync
{
    /*
     NOTE: a failure here might mean that you either forgot to add a new sync to
     self.syncObjectsUsedByThisState, or that the order of that array doesn't match
     the order used by the ZMEventProcessingState
     */
    
    [self checkThatItCallsRequestGeneratorsOnObjectsOfClass:[self syncObjectsUsedByState] creationOfStateBlock:^ZMSyncState *(id<ZMObjectStrategyDirectory> directory) {
        [[[(id) directory.missingUpdateEventsTranscoder stub] andCall:@selector(missingUpdateEventsTranscoderLastUpdateEventID) onObject:self] lastUpdateEventID];
        (void)[(ZMMissingUpdateEventsTranscoder *) [[(id) directory.missingUpdateEventsTranscoder stub] andReturnValue:@(YES)] isDownloadingMissingNotifications];
        (void)[(ZMAssetTranscoder *) [[(id) directory.assetTranscoder stub] andReturnValue:@(YES)] hasOutstandingItems];
        return [[ZMBackgroundFetchState alloc] initWithAuthenticationCenter:self.authenticationStatus clientRegistrationStatus:self.clientRegistrationStatus objectStrategyDirectory:directory stateMachineDelegate:self.stateMachine];
    }];
}

- (ZMBackgroundFetchResult)lastResult;
{
    return (ZMBackgroundFetchResult) [(NSNumber *) self.results.lastObject intValue];
}

- (NSUUID *)missingUpdateEventsTranscoderLastUpdateEventID;
{
    return self.lastUpdateEventID;
}

- (ZMTransportRequest *)nextForwardedRequest;
{
    ZMTransportRequest *forwardedRequest = [self.forwardedRequests firstObject];
    if (forwardedRequest != nil) {
        [self.forwardedRequests removeObjectAtIndex:0];
    }
    return forwardedRequest;
}

- (NSArray *)syncObjectsUsedByState
{
    return  @[ /* Note: these must be in the same order as in the class */
              self.objectDirectory.missingUpdateEventsTranscoder,
              self.objectDirectory.assetTranscoder,
              ];
}

- (BOOL)assetTranscoderHasOutstandingItems;
{
    return _assetTranscoderHasOutstandingItems;
}

- (BOOL)missingUpdateEventsTranscoderIsDownloadingMissingNotifications;
{
    return _missingUpdateEventsTranscoderIsDownloadingMissingNotifications;
}

@end
