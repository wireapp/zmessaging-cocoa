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
    [[[NotificationInContext alloc] initWithName:ZMOperationLoop.pushChannelStateChangeNotificationName
                                         context:self.uiMOC.notificationContext
                                          object:nil
                                       userInfo:@{ZMPushChannelIsOpenKey: @(NO)}] post];
}

- (void)simulatePushChannelOpen
{
    [[[NotificationInContext alloc] initWithName:ZMOperationLoop.pushChannelStateChangeNotificationName
                                         context:self.uiMOC.notificationContext
                                          object:nil
                                        userInfo:@{ZMPushChannelIsOpenKey: @(YES)}] post];
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

@end
