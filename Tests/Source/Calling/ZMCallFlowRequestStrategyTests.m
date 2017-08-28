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


@import WireTransport;
@import WireUtilities;
@import WireDataModel;
@import WireSyncEngine;
@import avs;

#import "ObjectTranscoderTests.h"
#import "ZMOperationLoop.h"
#import "ZMUserSessionAuthenticationNotification.h"
#import "WireSyncEngine_iOS_Tests-Swift.h"


@interface ZMCallFlowRequestStrategyTests : ObjectTranscoderTests

@property (nonatomic) ZMCallFlowRequestStrategy<AVSFlowManagerDelegate, ZMRequestGenerator> *sut;
@property (nonatomic) FlowManagerMock *flowManagerMock;

@end


@implementation ZMCallFlowRequestStrategyTests

- (void)setUp
{
    [super setUp];
    
    self.flowManagerMock = [[FlowManagerMock alloc] init];
    self.mockApplicationStatus.mockSynchronizationState = ZMSynchronizationStateEventProcessing;

    [self recreateSUT];
    [self simulatePushChannelOpen];
}

- (void)tearDown
{
    [self.sut tearDown];
    self.sut = nil;
    self.flowManagerMock = nil;
    
    [super tearDown];
}

- (void)recreateSUT;
{
    self.sut = (id) [[ZMCallFlowRequestStrategy alloc] initWithMediaManager:nil flowManager:self.flowManagerMock managedObjectContext:self.syncMOC applicationStatus:self.mockApplicationStatus application:self.application];
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)simulatePushChannelClose
{
    [[NSNotificationCenter defaultCenter] postNotificationName:ZMPushChannelStateChangeNotificationName object:nil
                                                      userInfo:@{ZMPushChannelIsOpenKey: @(NO)}];
}

- (void)simulatePushChannelOpen
{
    [[NSNotificationCenter defaultCenter] postNotificationName:ZMPushChannelStateChangeNotificationName object:nil
                                                      userInfo:@{ZMPushChannelIsOpenKey: @(YES)}];
}

- (void)testThatUsesCorrectRequestStrategyConfiguration
{
    ZMStrategyConfigurationOption options = ZMStrategyConfigurationOptionAllowsRequestsDuringEventProcessing
                                          | ZMStrategyConfigurationOptionAllowsRequestsDuringSync
                                          | ZMStrategyConfigurationOptionAllowsRequestsWhileInBackground
                                          | ZMStrategyConfigurationOptionAllowsRequestsDuringNotificationStreamFetch;

    XCTAssertEqual(self.sut.configuration, options);
}

- (void)testThatItReturnsARequestWhenCallConfigIsRequested
{
    // given
    NSObject *context = [[NSObject alloc] init];
    [self.flowManagerMock.delegate flowManagerDidRequestCallConfigWithContext:(__bridge const void * _Nonnull)(context)];
    
    // when
    [self.syncMOC performBlockAndWait:^{
        ZMTransportRequest *request = [self.sut nextRequest];
        
        // then
        XCTAssertNotNil(request);
        XCTAssertTrue(request.shouldUseVoipSession);
    }];
}

- (void)testThatItReturnsACallConfigRequestOnlyOnce
{
    // given
    NSObject *context = [[NSObject alloc] init];
    [self.flowManagerMock.delegate flowManagerDidRequestCallConfigWithContext:(__bridge const void * _Nonnull)(context)];
    
    // when
    [self.syncMOC performBlockAndWait:^{
        ZMTransportRequest *request1 = [self.sut nextRequest];
        ZMTransportRequest *request2 = [self.sut nextRequest];
        
        // then
        XCTAssertNotNil(request1);
        XCTAssertNil(request2);
    }];
}

- (void)testThatFlowManagerRequestCompletedIsCalledWithTheRightContext
{
    // given
    NSObject *context = [[NSObject alloc] init];
    [self.flowManagerMock.delegate flowManagerDidRequestCallConfigWithContext:(__bridge const void * _Nonnull)(context)];
    
    NSDictionary *payload = @{@"foo": @"bar"};
    ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:payload HTTPStatus:200 transportSessionError:nil];
    
    // when
    __block ZMTransportRequest *request;
    [self.syncMOC performBlockAndWait:^{
        request = [self.sut nextRequest];
    }];
    
    [request completeWithResponse:response];
    WaitForAllGroupsToBeEmpty(0.5);
    
    XCTAssertTrue(self.flowManagerMock.didReportCallConfig);
    XCTAssertEqualObjects(self.flowManagerMock.callConfigContext, context);
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatFlowManagerRequestCompletedIsCalledWithTheRightContextWithFailure
{
    // given
    NSObject *context = [[NSObject alloc] init];
    [self.flowManagerMock.delegate flowManagerDidRequestCallConfigWithContext:(__bridge const void * _Nonnull)(context)];
    
    // when
    __block ZMTransportRequest *request;
    [self.syncMOC performBlockAndWait:^{
        request = [self.sut nextRequest];
    }];
    
    ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:nil HTTPStatus:400 transportSessionError:nil];
    [request completeWithResponse:response];
    WaitForAllGroupsToBeEmpty(0.5);
    
    XCTAssertTrue(self.flowManagerMock.didReportCallConfig);
    XCTAssertEqualObjects(self.flowManagerMock.callConfig, nil);
    XCTAssertEqualObjects(self.flowManagerMock.callConfigContext, context);
    XCTAssertEqual(self.flowManagerMock.callConfigHttpStatus, (NSInteger)400);
    
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)simulateAVSRequest
{
    NSObject *context = [[NSObject alloc] init];
    [self.flowManagerMock.delegate flowManagerDidRequestCallConfigWithContext:(__bridge const void * _Nonnull)(context)];
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatItNotifiestheOperationLoopWhenThePushChannelStateChangesToOpen
{
    // given
    [self simulatePushChannelClose];
    [self simulateAVSRequest];
    
    // expect
    id mockRequestAvailableNotification = [OCMockObject niceMockForClass:ZMRequestAvailableNotification.class];
    [[[mockRequestAvailableNotification expect] classMethod] notifyNewRequestsAvailable:OCMOCK_ANY];
    
    // when
    [self simulatePushChannelOpen];
    WaitForAllGroupsToBeEmpty(0.5);

    // then
    [mockRequestAvailableNotification verify];
    
    // after
    [mockRequestAvailableNotification stopMocking];
}

- (void)testThatItNotifiesTheOperationLoopWhenThereIsANewRquest_PushChannelOpen
{
    // given
    [self simulatePushChannelOpen];
    
    // expect
    id mockRequestAvailableNotification = [OCMockObject mockForClass:ZMRequestAvailableNotification.class];
    [[[mockRequestAvailableNotification expect] classMethod] notifyNewRequestsAvailable:OCMOCK_ANY];
    
    // when
    [self simulateAVSRequest];
    
    // then
    [mockRequestAvailableNotification verify];
    
    // after
    [mockRequestAvailableNotification stopMocking];
}

- (void)testThatItNotifiesAVSOfNetworkChangeWhenThePushChannelIsOpened
{
    // when
    [self simulatePushChannelOpen];
    
    // then
    XCTAssertTrue(self.flowManagerMock.didReportNetworkChanged);
}

- (void)testThatItDoesNotNotifyAVSOfNetworkChangeWhenThePushChannelIsClosed
{
    // when
    [self simulatePushChannelClose];
    
    // then
    XCTAssertTrue(self.flowManagerMock.didReportNetworkChanged);
}

- (void)testThatItCompressesAVSRequests
{
    // given
    [self simulatePushChannelOpen];
    [self simulateAVSRequest];
    
    // when
    ZMTransportRequest *request = [self.sut nextRequest];
    
    // then
    XCTAssertNotNil(request);
    XCTAssertTrue(request.shouldCompress);
    XCTAssertTrue(self.flowManagerMock.didReportNetworkChanged);
}

- (void)testThatItAllowsRequestForCallsConfigWhenPushChannelIsClosed
{
    // given
    [self simulatePushChannelClose];
    [self simulateAVSRequest];
    
    // when
    ZMTransportRequest *request = [self.sut nextRequest];
    
    // then
    XCTAssertEqualObjects(request.path, @"/calls/config");
}

@end
