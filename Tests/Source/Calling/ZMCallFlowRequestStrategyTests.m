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
#import "ZMOnDemandFlowManager.h"
#import "WireSyncEngine_iOS_Tests-Swift.h"



@interface ZMCallFlowRequestStrategyTests : ObjectTranscoderTests

@property (nonatomic) ZMCallFlowRequestStrategy<AVSFlowManagerDelegate, ZMRequestGenerator> *sut;
@property (nonatomic) id internalFlowManager;
@property (nonatomic) ZMOnDemandFlowManager *onDemandFlowManager;
@property (nonatomic) id deploymentEnvironment;

@end



@implementation ZMCallFlowRequestStrategyTests

- (void)setUp
{
    [super setUp];
        
    self.internalFlowManager = [OCMockObject mockForClass:AVSFlowManager.class];
    ZMCallFlowRequestStrategyInternalFlowManagerOverride = self.internalFlowManager;
    self.onDemandFlowManager = [[ZMOnDemandFlowManager alloc] initWithMediaManager:nil];
    [[self.internalFlowManager stub] setValue:OCMOCK_ANY forKey:@"delegate"];
    
    self.deploymentEnvironment = [OCMockObject niceMockForClass:ZMDeploymentEnvironment.class];
    ZMCallFlowRequestStrategyInternalDeploymentEnvironmentOverride = self.deploymentEnvironment;
    [[[self.deploymentEnvironment stub] andReturnValue:OCMOCK_VALUE(ZMDeploymentEnvironmentTypeInternal)] environmentType];
    
    self.mockApplicationStatus.mockSynchronizationState = ZMSynchronizationStateEventProcessing;

    [self recreateSUT];
    
    [[self.internalFlowManager expect] networkChanged]; // this will be caused by "simulatePushChannelOpen"
    [self verifyMockLater:self.internalFlowManager];
    [self simulatePushChannelOpen];
}

- (void)tearDown
{
    [self.sut tearDown];
    self.sut = nil;
    [self.internalFlowManager stopMocking];
    self.internalFlowManager = nil;
    self.onDemandFlowManager = nil;
    
    self.deploymentEnvironment = nil;
    ZMCallFlowRequestStrategyInternalDeploymentEnvironmentOverride = nil;
    ZMCallFlowRequestStrategyInternalFlowManagerOverride = nil;
    
    [super tearDown];
}

- (void)recreateSUT;
{
    self.sut = (id) [[ZMCallFlowRequestStrategy alloc] initWithMediaManager:nil onDemandFlowManager:self.onDemandFlowManager managedObjectContext:self.syncMOC applicationStatus:self.mockApplicationStatus application:self.application];
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

- (void)testThatItReturnsARequestWhenRequested
{
    // given
    NSString *path = @"/this/is/a/url";
    ZMTransportRequestMethod method = ZMMethodDELETE;
    NSString *mediaType = @"This is a media type";
    NSData *content = [@"fdsgdghsdfgsdfgafg3425rreg" dataUsingEncoding:NSUTF8StringEncoding];
    [[[self.internalFlowManager stub] andReturnValue:@YES] isReady];

    [self.sut requestWithPath:path method:@"DELETE" mediaType:mediaType content:content context:nil];
    
    // when
    [self.syncMOC performBlockAndWait:^{
        ZMTransportRequest *request = [self.sut nextRequest];
        
        // then
        XCTAssertNotNil(request);
        XCTAssertEqual(method, request.method);
        XCTAssertEqualObjects(path, request.path);
        XCTAssertEqualObjects(content, request.binaryData);
        XCTAssertEqualObjects(mediaType, request.binaryDataType);
        XCTAssertTrue(request.shouldUseVoipSession);
    }];
}

- (void)testThatItReturnsARequestWithTheRightMethod
{
    // given
    NSString *path = @"/this/is/a/url";
    NSString *mediaType = @"This is a media type";
    NSData *content = [@"fdsgdghsdfgsdfgafg3425rreg" dataUsingEncoding:NSUTF8StringEncoding];
    [[[self.internalFlowManager stub] andReturnValue:@YES] isReady];

    
    NSArray *methodsToTest = @[];
    
    for(NSString *methodString in methodsToTest)
    {
        [self.sut requestWithPath:path method:methodString mediaType:mediaType content:content context:nil];
        
        // when
        [self.syncMOC performBlockAndWait:^{
            ZMTransportRequest *request = [self.sut nextRequest];
            
            // then
            XCTAssertNotNil(request);
            XCTAssertEqual([ZMTransportRequest methodFromString:methodString], request.method);
        }];
    }

}

- (void)testThatItReturnsARequestOnlyOnce
{
    // given
    NSString *path = @"/this/is/a/url";
    NSString *mediaType = @"This is a media type";
    NSData *content = [@"fdsgdghsdfgsdfgafg3425rreg" dataUsingEncoding:NSUTF8StringEncoding];
    id context = @"This is the context";
    [[[self.internalFlowManager stub] andReturnValue:@YES] isReady];

    [self.sut requestWithPath:path method:@"DELETE" mediaType:mediaType content:content context:(void *)context];
    
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
    NSString *path = @"/this/is/a/url";
    NSString *inMediaType = @"This is a media type";
    NSData *inContent = [@"fdsgdghsdfgsdfgafg3425rreg" dataUsingEncoding:NSUTF8StringEncoding];
    id context = @"This is the context";
    [[[self.internalFlowManager stub] andReturnValue:@YES] isReady];

    [self.sut requestWithPath:path method:@"DELETE" mediaType:inMediaType content:inContent context:(void *)context];
    
    NSDictionary *payload = @{@"foo": @"bar"};
    ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:payload HTTPStatus:200 transportSessionError:nil];
    
    
    //expect
    NSError *error;
    NSData *outContent = [NSJSONSerialization dataWithJSONObject:payload options:0 error:&error];
    XCTAssertNotNil(outContent);
    
    [[self.internalFlowManager expect] processResponseWithStatus:200 reason:OCMOCK_ANY mediaType:@"application/json" content:outContent context:(const void*)context];
    
    
    // when
    __block ZMTransportRequest *request;
    [self.syncMOC performBlockAndWait:^{
        request = [self.sut nextRequest];
    }];
    

    [request completeWithResponse:response];
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatFlowManagerRequestCompletedIsCalledWithTheRightContextWithFailure
{
    // given
    NSString *path = @"/this/is/a/url";
    NSString *inMediaType = @"This is a media type";
    NSData *inContent = [@"fdsgdghsdfgsdfgafg3425rreg" dataUsingEncoding:NSUTF8StringEncoding];
    id context = @"This is the context";
    [[[self.internalFlowManager stub] andReturnValue:@YES] isReady];

    [self.sut requestWithPath:path method:@"DELETE" mediaType:inMediaType content:inContent context:(void *)context];
    
    ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:nil HTTPStatus:400 transportSessionError:nil];
    
    
    //expect
    [[self.internalFlowManager expect] processResponseWithStatus:400 reason:OCMOCK_ANY mediaType:@"application/json" content:nil context:(const void*)context];
    
    
    // when
    __block ZMTransportRequest *request;
    [self.syncMOC performBlockAndWait:^{
        request = [self.sut nextRequest];
    }];
    
    [request completeWithResponse:response];
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)simulateAVSRequest
{
    NSString *path = @"/this/is/a/url";
    NSString *inMediaType = @"This is a media type";
    NSData *inContent = [@"fdsgdghsdfgsdfgafg3425rreg" dataUsingEncoding:NSUTF8StringEncoding];
    id context = @"This is the context";
    
    [self.sut requestWithPath:path method:@"DELETE" mediaType:inMediaType content:inContent context:(void *)context];
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatItNotifiestheOperationLoopWhenThePushChannelStateChangesToOpen
{
    // given
    [self simulatePushChannelClose];
    [self simulateAVSRequest];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // expect
    id mockRequestAvailableNotification = [OCMockObject niceMockForClass:ZMRequestAvailableNotification.class];
    [[[mockRequestAvailableNotification expect] classMethod] notifyNewRequestsAvailable:OCMOCK_ANY];
    
    // when
    [[self.internalFlowManager stub] networkChanged];
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
    [[self.internalFlowManager stub] networkChanged];
    [self simulatePushChannelOpen];
    
    // expect
    id mockRequestAvailableNotification = [OCMockObject mockForClass:ZMRequestAvailableNotification.class];
    [[[mockRequestAvailableNotification expect] classMethod] notifyNewRequestsAvailable:OCMOCK_ANY];
    
    // when
    [self simulateAVSRequest];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    [mockRequestAvailableNotification verify];
    
    // after
    [mockRequestAvailableNotification stopMocking];
}

- (void)testThatItNotifiesAVSOfNetworkChangeWhenThePushChannelIsOpened
{
    // expect
    [[self.internalFlowManager expect] networkChanged];
    
    // when
    [self simulatePushChannelOpen];
    
    // then
    [self.internalFlowManager verify];
}

- (void)testThatItDoesNotNotifyAVSOfNetworkChangeWhenThePushChannelIsClosed
{
    // expect
    [[self.internalFlowManager reject] networkChanged];
    
    // when
    [self simulatePushChannelClose];
    
    // then
    [self.internalFlowManager verify];
}

- (void)testThatItCompressesAVSRequests
{
    // given
    [[[self.internalFlowManager stub] andReturnValue:@YES] isReady];
    [[self.internalFlowManager expect] networkChanged];
    [self simulatePushChannelOpen];
    [self simulateAVSRequest];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // when
    ZMTransportRequest *request = [self.sut nextRequest];
    
    // then
    XCTAssertNotNil(request);
    XCTAssertTrue(request.shouldCompress);
}

- (void)testThatItAllowsRequestForCallsConfigWhenPushChannelIsClosed
{
    // given
    [[[self.internalFlowManager stub] andReturnValue:@YES] isReady];
    [self simulatePushChannelClose];
    [self.sut requestWithPath:@"/calls/config" method:@"GET" mediaType:nil content:nil context:nil];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // when
    ZMTransportRequest *request = [self.sut nextRequest];
    
    // then
    XCTAssertEqual(request.path, @"/calls/config");
}

- (void)testThatItRejectsRequestWhenPushChannelIsClosed
{
    // given
    [[[self.internalFlowManager stub] andReturnValue:@YES] isReady];
    [self simulatePushChannelClose];
    [self.sut requestWithPath:@"/calls/foo" method:@"GET" mediaType:nil content:nil context:nil];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // when
    ZMTransportRequest *request = [self.sut nextRequest];
    
    // then
    XCTAssertNil(request);
}

- (void)testThatItRegisteresSelfUser
{
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        ZMUser *selfUser = [ZMUser selfUserInContext:self.syncMOC];
        selfUser.remoteIdentifier = [NSUUID createUUID];
        
        // expect
        [(AVSFlowManager *)[self.internalFlowManager expect] setSelfUser:selfUser.remoteIdentifier.transportString];
        
        // when
        [ZMUserSessionAuthenticationNotification notifyAuthenticationDidSucceed];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    [self.internalFlowManager verify];
}

@end
