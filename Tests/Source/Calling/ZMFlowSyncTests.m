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
@import ZMUtilities;
@import ZMCDataModel;
@import zmessaging;

#import "MessagingTest.h"
#import "AVSFlowManager.h"
#import "ZMOperationLoop.h"
#import "ZMUserSessionAuthenticationNotification.h"
#import "ZMOnDemandFlowManager.h"
#import "zmessaging_iOS_Tests-Swift.h"

static NSString * const FlowEventName1 = @"conversation.message-add";
static NSString * const FlowEventName2 = @"conversation.member-join";




@interface ZMFlowSyncTests : MessagingTest <ZMVoiceChannelVoiceGainObserver>

@property (nonatomic) ZMFlowSync<AVSFlowManagerDelegate, ZMRequestGenerator> *sut;
@property (nonatomic) id internalFlowManager;
@property (nonatomic) ZMOnDemandFlowManager *onDemandFlowManager;
@property (nonatomic) id deploymentEnvironment;
@property (nonatomic) NSMutableArray *voiceChannelGainNotifications;
@end



@implementation ZMFlowSyncTests

- (void)setUp
{
    [super setUp];
        
    self.internalFlowManager = [OCMockObject mockForClass:AVSFlowManager.class];
    ZMFlowSyncInternalFlowManagerOverride = self.internalFlowManager;
    self.onDemandFlowManager = [[ZMOnDemandFlowManager alloc] initWithMediaManager:nil];
    NSArray *events = @[FlowEventName1, FlowEventName2];
    [(AVSFlowManager *)[[self.internalFlowManager stub] andReturn:events] events];
    [[self.internalFlowManager stub] setValue:OCMOCK_ANY forKey:@"delegate"];
    
    self.deploymentEnvironment = [OCMockObject niceMockForClass:ZMDeploymentEnvironment.class];
    ZMFlowSyncInternalDeploymentEnvironmentOverride = self.deploymentEnvironment;
    [[[self.deploymentEnvironment stub] andReturnValue:OCMOCK_VALUE(ZMDeploymentEnvironmentTypeInternal)] environmentType];

    [self recreateSUT];
    self.voiceChannelGainNotifications = [NSMutableArray array];
    [ZMVoiceChannelParticipantVoiceGainChangedNotification addObserver:self];
    
    [[self.internalFlowManager expect] networkChanged]; // this will be caused by "simulatePushChannelOpen"
    [self verifyMockLater:self.internalFlowManager];
    [self simulatePushChannelOpen];
}

- (void)tearDown
{
    [ZMVoiceChannelParticipantVoiceGainChangedNotification removeObserver:self];
    self.voiceChannelGainNotifications = nil;
    
    [self.sut tearDown];
    self.sut = nil;
    [self.internalFlowManager stopMocking];

    self.deploymentEnvironment = nil;
    ZMFlowSyncInternalDeploymentEnvironmentOverride = nil;
    ZMFlowSyncInternalFlowManagerOverride = nil;
    
    [super tearDown];
}

- (void)recreateSUT;
{
    [self.sut tearDown];
    self.sut = (id) [[ZMFlowSync alloc] initWithMediaManager:nil onDemandFlowManager:self.onDemandFlowManager syncManagedObjectContext:self.syncMOC uiManagedObjectContext:self.uiMOC application:self.application];
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

- (void)voiceChannelParticipantVoiceGainDidChange:(ZMVoiceChannelParticipantVoiceGainChangedNotification *)note;
{
    [self.voiceChannelGainNotifications addObject:note];
}

- (void)testThatItReleasesTheFlowForCallDeviceIsActive_No
{
    [self.syncMOC performBlockAndWait:^{
        // given
        ZMConversation *conv = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
        conv.remoteIdentifier = [NSUUID UUID];
        conv.callDeviceIsActive = NO;
        
        // expect
        [[[self.internalFlowManager stub] andReturnValue:@YES] isReady];
        [[self.internalFlowManager stub] appendLogForConversation:OCMOCK_ANY message:OCMOCK_ANY];
        [[self.internalFlowManager expect] releaseFlows:conv.remoteIdentifier.transportString];
        [[self.internalFlowManager reject] acquireFlows:conv.remoteIdentifier.transportString];

        // when
        [self.sut updateFlowsForConversation:conv];
        
        // then
        [self.internalFlowManager verify];
        [conv.voiceChannel tearDown];
    }];
}

- (void)testThatItAcquiresTheFlowForCallDeviceIsActive_YES
{
    [self.syncMOC performBlockAndWait:^{
        // given
        ZMConversation *conv = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
        conv.remoteIdentifier = [NSUUID UUID];
        conv.callDeviceIsActive = YES;
        
        // expect
        [[[self.internalFlowManager stub] andReturnValue:@YES] isReady];
        [[self.internalFlowManager stub] appendLogForConversation:OCMOCK_ANY message:OCMOCK_ANY];
        [[self.internalFlowManager reject] releaseFlows:conv.remoteIdentifier.transportString];
        [[self.internalFlowManager expect] acquireFlows:conv.remoteIdentifier.transportString];

        // when
        [self.sut updateFlowsForConversation:conv];
        
        // then
        [self.internalFlowManager verify];
        [conv.voiceChannel tearDown];
    }];
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
        ZMTransportRequest *request = [self.sut.requestGenerators nextRequest];
        
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
            ZMTransportRequest *request = [self.sut.requestGenerators nextRequest];
            
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
        ZMTransportRequest *request1 = [self.sut.requestGenerators nextRequest];
        ZMTransportRequest *request2 = [self.sut.requestGenerators nextRequest];
        
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
        request = [self.sut.requestGenerators nextRequest];
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
        request = [self.sut.requestGenerators nextRequest];
    }];
    
    [request completeWithResponse:response];
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatUpdateEventsAreSentToTheFlowManager
{
    // given
    [[[self.internalFlowManager stub] andReturnValue:@YES] isReady];

    NSDictionary *payload = @{@"id": @"71bda6aa-bc34-4e9d-bceb-7e4198cc7512",
                              @"payload": @[@{@"conversation": @"1742ca1a-9256-47b1-9459-1e8d4bc9e4a3",
                                              @"data": @{
                                                      @"last_read": @"9.800122000a4aaa0c"
                                                      },
                                              @"from": @"39562cc3-717d-4395-979c-5387ae17f5c3",
                                              @"time": @"2014-06-20T14:04:38.133Z",
                                              @"type": FlowEventName1,}]
                              };
    ZMUpdateEvent *event = [ZMUpdateEvent eventsArrayFromPushChannelData:payload][0];
    
    NSData *innerPayloadData = [NSJSONSerialization dataWithJSONObject:event.payload options:0 error:nil];
    XCTAssertNotNil(innerPayloadData);
    
    // expect
    [[self.internalFlowManager expect] processEventWithMediaType:@"application/json" content:innerPayloadData];
    
    // when
    [self.sut processEvents:@[event] liveEvents:YES prefetchResult:nil];
}

- (void)testThatUpdateEventsThatTheFlowManagerIsNotInterestedInAreNotSentToTheFlowManager;
{
    // given
    [[[self.internalFlowManager stub] andReturnValue:@YES] isReady];

    NSDictionary *payload = @{@"id": @"71bda6aa-bc34-4e9d-bceb-7e4198cc7512",
                              @"payload": @[@{@"conversation": @"1742ca1a-9256-47b1-9459-1e8d4bc9e4a3",
                                              @"data": @{
                                                      @"last_read": @"9.800122000a4aaa0c"
                                                      },
                                              @"from": @"39562cc3-717d-4395-979c-5387ae17f5c3",
                                              @"time": @"2014-06-20T14:04:38.133Z",
                                              @"type": @"user.update",}]
                              };
    ZMUpdateEvent *event = [ZMUpdateEvent eventsArrayFromPushChannelData:payload][0];
    
    NSData *innerPayloadData = [NSJSONSerialization dataWithJSONObject:event.payload options:0 error:nil];
    XCTAssertNotNil(innerPayloadData);
    
    // expect
    [[self.internalFlowManager reject] processEventWithMediaType:OCMOCK_ANY content:OCMOCK_ANY];
    
    // when
    [self.sut processEvents:@[event] liveEvents:YES prefetchResult:nil];
}

- (void)testThatWhenErrorCallbackIsCalledWeLeaveTheCallOnTheConversation
{
    // given
    id context = @"This is the context";
    NSUUID *conversationID = [NSUUID createUUID];

    __block ZMConversation *conversation;
    [self.syncMOC performBlockAndWait:^{
        conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        conversation.conversationType = ZMConversationTypeOneOnOne;
        conversation.callDeviceIsActive = YES;
        conversation.remoteIdentifier = conversationID;
        [self.syncMOC saveOrRollback];
    }];
    [self.uiMOC.zm_callState mergeChangesFromState:self.syncMOC.zm_callState];
    
    // when
    [self.sut errorHandler:-34 conversationId:conversationID.transportString context:(const void*)context];
    WaitForAllGroupsToBeEmpty(0.5);
    [self.syncMOC.zm_callState mergeChangesFromState:self.uiMOC.zm_callState];

    // then
    ZMConversation *uiConv = (id)[self.uiMOC objectWithID:conversation.objectID];
    XCTAssertTrue(uiConv.hasLocalModificationsForCallDeviceIsActive);
    XCTAssertFalse(uiConv.callDeviceIsActive);

    [self.syncMOC performBlockAndWait:^{
        XCTAssertFalse(conversation.callDeviceIsActive);
    }];
}



// TODO make sure all requests receive a response, even if they time out/ have network error


- (void)testThatItReleasesAConversationsFlowsInTheFlowManager
{
    // given
    [[[self.internalFlowManager stub] andReturnValue:@YES] isReady];

    ZMConversation *conv = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    conv.remoteIdentifier = [NSUUID createUUID];
    
    // expect
    [[self.internalFlowManager expect] releaseFlows:conv.remoteIdentifier.transportString];
    
    // when
    [self.sut releaseFlowsForConversation:conv];
}


- (void)testThatItAcquiresAConversationsFlowsInTheFlowManager
{
    // given
    [[[self.internalFlowManager stub] andReturnValue:@YES] isReady];

    ZMConversation *conv = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    conv.remoteIdentifier = [NSUUID createUUID];
    
    // expect
    [[self.internalFlowManager expect] acquireFlows:conv.remoteIdentifier.transportString];
    
    // when
    [self.sut acquireFlowsForConversation:conv];
}

- (void)testThatItDoesNotForwardReleaseOrAquireFlowsWhenTheConversationHasNoRemoteID;
{
    // given
    [[[self.internalFlowManager stub] andReturnValue:@YES] isReady];

    ZMConversation *conv = [ZMConversation insertNewObjectInManagedObjectContext:self.uiMOC];
    conv.remoteIdentifier = nil;
    
    // reject
    [[self.internalFlowManager reject] acquireFlows:conv.remoteIdentifier.transportString];
    [[self.internalFlowManager reject] releaseFlows:conv.remoteIdentifier.transportString];
    
    // when
    [self performIgnoringZMLogError:^{
        [self.sut acquireFlowsForConversation:conv];
        [self.sut releaseFlowsForConversation:conv];
    }];
}

- (void)testThatItSetsFlowCategoryAndSavesWhen_didEstablishMediaInConversation_IsCalled
{
    __block ZMConversation *conv;
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        conv = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        conv.remoteIdentifier = [NSUUID createUUID];
        XCTAssertFalse(conv.isFlowActive);
        [self.syncMOC saveOrRollback];
        
        
        // when
        [self.sut didEstablishMediaInConversation:conv.remoteIdentifier.transportString];
    }];
    
    WaitForAllGroupsToBeEmpty(0.5);
    
    [self.syncMOC performGroupedBlockAndWait:^{
        // then
        XCTAssertTrue(conv.isFlowActive);
        XCTAssertFalse(conv.hasChanges); // this checks that it saves
    }];

}

- (void)testThatItSetsFlowCategoryAndSavesWhen_errorHandler_IsCalled
{
    __block ZMConversation *conv;
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        conv = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        conv.remoteIdentifier = [NSUUID createUUID];
        conv.isFlowActive = YES;
        [self.syncMOC saveOrRollback];
        
        // when
        [self.sut errorHandler:1 conversationId:conv.remoteIdentifier.transportString context:nil];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    [self.syncMOC performGroupedBlockAndWait:^{
        // then
        XCTAssertFalse(conv.isFlowActive);
        XCTAssertFalse(conv.hasChanges); // this checks that it saves
    }];
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
    id mockOperationLoop = [OCMockObject niceMockForClass:ZMOperationLoop.class];
    [[[mockOperationLoop expect] classMethod] notifyNewRequestsAvailable:OCMOCK_ANY];
    
    // when
    [[self.internalFlowManager stub] networkChanged];
    [self simulatePushChannelOpen];
    WaitForAllGroupsToBeEmpty(0.5);

    // then
    [mockOperationLoop verify];
    
    // after
    [mockOperationLoop stopMocking];
}

- (void)testThatItNotifiesTheOperationLoopWhenThereIsANewRquest_PushChannelOpen
{
    // given
    [[self.internalFlowManager stub] networkChanged];
    [self simulatePushChannelOpen];
    
    // expect
    id mockOperationLoop = [OCMockObject mockForClass:ZMOperationLoop.class];
    [[[mockOperationLoop expect] classMethod] notifyNewRequestsAvailable:OCMOCK_ANY];
    
    // when
    [self simulateAVSRequest];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    [mockOperationLoop verify];
    
    // after
    [mockOperationLoop stopMocking];
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

@end



@implementation ZMFlowSyncTests (VoiceGain)

- (void)testThatItSendsAVoiceGainNotification;
{
    __block NSManagedObjectID *conversationID;
    __block NSManagedObjectID *userID;
    // given
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMConversation *conv = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        conv.conversationType = ZMConversationTypeOneOnOne;
        conv.remoteIdentifier = [NSUUID createUUID];
        conv.connection = [ZMConnection insertNewObjectInManagedObjectContext:self.syncMOC];
        ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        user.connection = conv.connection;
        user.remoteIdentifier = NSUUID.createUUID;
        [conv.voiceChannel addCallParticipant:user];
        XCTAssert([self.syncMOC saveOrRollback]);
        conversationID = conv.objectID;
        userID = user.objectID;
        [conv.voiceChannel tearDown];
    }];
    WaitForAllGroupsToBeEmpty(0.5);

    // when
    ZMConversation *conversation = (id) [self.uiMOC objectWithID:conversationID];
    [self.sut didUpdateVolume:0.4 conversationId:conversation.remoteIdentifier.transportString participantId:FlowManagerOtherUserParticipantIdentifier];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    ZMUser *user = (id) [self.uiMOC objectWithID:userID];
    
    XCTAssertEqual(self.voiceChannelGainNotifications.count, 1u);
    ZMVoiceChannelParticipantVoiceGainChangedNotification *note = self.voiceChannelGainNotifications.firstObject;
    XCTAssertEqual(note.voiceChannel, conversation.voiceChannel);
    XCTAssertEqual(note.participant, user);
    XCTAssertEqualWithAccuracy(note.voiceGain, 0.4, 0.01);
}


- (void)testThatItSendsAVoiceGainNotification_ParticipantUUID;
{
    __block NSManagedObjectID *conversationID;
    __block NSManagedObjectID *userID;
    // given
    [self.syncMOC performGroupedBlockAndWait:^{
        ZMConversation *conv = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        conv.conversationType = ZMConversationTypeOneOnOne;
        conv.remoteIdentifier = [NSUUID createUUID];
        conv.connection = [ZMConnection insertNewObjectInManagedObjectContext:self.syncMOC];
        ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        user.connection = conv.connection;
        user.remoteIdentifier = NSUUID.createUUID;
        [conv.voiceChannel addCallParticipant:user];
        XCTAssert([self.syncMOC saveOrRollback]);
        conversationID = conv.objectID;
        userID = user.objectID;
        [conv.voiceChannel tearDown];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // when
    ZMConversation *conversation = (id) [self.uiMOC objectWithID:conversationID];
    ZMUser *user = (id) [self.uiMOC objectWithID:userID];

    [self.sut didUpdateVolume:0.4 conversationId:conversation.remoteIdentifier.transportString participantId:user.remoteIdentifier.transportString];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    
    XCTAssertEqual(self.voiceChannelGainNotifications.count, 1u);
    ZMVoiceChannelParticipantVoiceGainChangedNotification *note = self.voiceChannelGainNotifications.firstObject;
    XCTAssertEqual(note.voiceChannel, conversation.voiceChannel);
    XCTAssertEqual(note.participant, user);
    XCTAssertEqualWithAccuracy(note.voiceGain, 0.4, 0.01);
}

- (void)testThatItDoesNotSendNotificationsWhenConversationDoesNotExist;
{
    [self.syncMOC performGroupedBlockAndWait:^{
        // when
        [self.sut didUpdateVolume:0.4 conversationId:NSUUID.createUUID.transportString participantId:FlowManagerOtherUserParticipantIdentifier];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    [self.syncMOC performGroupedBlockAndWait:^{
        // then
        XCTAssertEqual(self.voiceChannelGainNotifications.count, 0u);
    }];
}

- (void)testThatItDoesNotSendNotificationsWhenTheParticipantIsNotInTheVoiceChannel
{
    __block ZMConversation *conv;
    __block ZMUser *user;
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        conv = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        conv.conversationType = ZMConversationTypeOneOnOne;
        conv.remoteIdentifier = [NSUUID createUUID];
        conv.connection = [ZMConnection insertNewObjectInManagedObjectContext:self.syncMOC];
        user = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        user.connection = conv.connection;
        user.remoteIdentifier = NSUUID.createUUID;
        [conv.voiceChannel addCallParticipant:user];
        
        // when
        [self.sut didUpdateVolume:0.4 conversationId:conv.remoteIdentifier.transportString participantId:NSUUID.createUUID.transportString];
        [self.syncMOC saveOrRollback];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    [self.syncMOC performGroupedBlockAndWait:^{
        // then
        XCTAssertEqual(self.voiceChannelGainNotifications.count, 0u);
        [conv.voiceChannel tearDown];
    }];
}

- (void)testThatItDropsTheCallWhenItReceivesAMediaWarning
{
    __block ZMConversation *conv;
    __block ZMUser *user;
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        conv = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        conv.conversationType = ZMConversationTypeOneOnOne;
        conv.remoteIdentifier = [NSUUID createUUID];
        conv.connection = [ZMConnection insertNewObjectInManagedObjectContext:self.syncMOC];
        user = [ZMUser insertNewObjectInManagedObjectContext:self.syncMOC];
        user.connection = conv.connection;
        user.remoteIdentifier = NSUUID.createUUID;
        
        conv.callDeviceIsActive = YES;
        [conv.voiceChannel addCallParticipant:user];
        XCTAssertEqual(conv.voiceChannel.state, ZMVoiceChannelStateSelfIsJoiningActiveChannel);
        [self.syncMOC saveOrRollback];
    }];
    [self.uiMOC.zm_callState mergeChangesFromState:self.syncMOC.zm_callState]; // This is done by ZMSyncStrategy when merging contexts

    
    ZMConversation *uiConv = (id)[self.uiMOC objectWithID:conv.objectID];
    XCTAssertTrue(uiConv.callDeviceIsActive);
    XCTAssertFalse(uiConv.hasLocalModificationsForCallDeviceIsActive);
    
    // when
    [self.syncMOC performGroupedBlockAndWait:^{
        [self.sut mediaWarningOnConversation:conv.remoteIdentifier.transportString];
        [conv.voiceChannel tearDown];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    [self.syncMOC.zm_callState mergeChangesFromState:self.uiMOC.zm_callState]; // This is done by ZMSyncStrategy when merging contexts

    // then
    XCTAssertFalse(uiConv.callDeviceIsActive);
    XCTAssertTrue(uiConv.hasLocalModificationsForCallDeviceIsActive);
    
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatItForwardsTheSessionIdentifierToTheFlowManager;
{
    // given
    NSString *sessionID = @"Foobar-session-id-1231241";
    NSUUID *conversationID = [NSUUID createUUID];
    
    // expect
    [[self.internalFlowManager expect] setSessionId:[OCMArg checkWithBlock:^BOOL(NSString *_sessionID) {
        return [_sessionID hasPrefix:sessionID];
    }] forConversation:conversationID.transportString];
    
    // when
    [self.sut setSessionIdentifier:sessionID forConversationIdentifier:conversationID];
    
    // then
    [self.internalFlowManager verify];
}

- (void)testThatItForwardsJoinedUsers
{
    [[[self.internalFlowManager stub] andReturnValue:@YES] isReady];

    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        ZMConversation *conv = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        conv.remoteIdentifier = [NSUUID createUUID];
        
        ZMUser *user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
        user.remoteIdentifier = [NSUUID createUUID];
        user.name = @"Super User";
        
        
        // expect
        [[self.internalFlowManager expect] addUser:conv.remoteIdentifier.transportString userId:user.remoteIdentifier.transportString name:user.name];
        
        // when
        [self.sut addJoinedCallParticipant:user inConversation:conv];
        
        // then
        [self.internalFlowManager verify];
    }];
}

- (void)testThatItForwardsAccessToken
{
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        NSString *token = @"fake-token";
        NSString *type = @"fake-type";
        
        // expect
        [[self.internalFlowManager expect] refreshAccessToken:token type:type];
        
        // when
        [self.sut accessTokenDidChangeWithToken:token ofType:type];
        
        // then
        [self.internalFlowManager verify];
    }];
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

@implementation ZMFlowSyncTests (VideoCall)

- (void)testThatItTellsAVSToEstablishVideoCall;
{
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        
        ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        conversation.remoteIdentifier = [NSUUID createUUID];
        conversation.isVideoCall = YES;
        [self.syncMOC saveOrRollback];
        
        // expect
        [(AVSFlowManager *)[[self.internalFlowManager expect] andReturnValue:OCMOCK_VALUE(YES)] canSendVideoForConversation:conversation.remoteIdentifier.transportString];
        [(AVSFlowManager *)[self.internalFlowManager expect] setVideoSendState:FLOWMANAGER_VIDEO_SEND forConversation:conversation.remoteIdentifier.transportString];
        
        // when
        [self.sut didEstablishMediaInConversation:conversation.remoteIdentifier.transportString];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    [self.internalFlowManager verify];
}

- (void)testThatItDoesNotTryToEstablishVideoCallIfCanNotSendVideoCall
{
    [self.syncMOC performGroupedBlockAndWait:^{
        // given

        ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        conversation.remoteIdentifier = [NSUUID createUUID];
        conversation.isVideoCall = YES;
        
        // expect
        [(AVSFlowManager *)[[self.internalFlowManager expect] andReturnValue:OCMOCK_VALUE(NO)] canSendVideoForConversation:conversation.remoteIdentifier.transportString];
        [(AVSFlowManager *)[self.internalFlowManager reject] setVideoSendState:FLOWMANAGER_VIDEO_SEND forConversation:OCMOCK_ANY];
        
        // when
        [self.sut didEstablishMediaInConversation:conversation.remoteIdentifier.transportString];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    [self.internalFlowManager verify];
}

- (void)testThatItNotifiesTheUIIfCanNotSendVideoCall;
{
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        
        ZMConversation *conversation = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        conversation.conversationType = ZMConversationTypeOneOnOne;
        conversation.remoteIdentifier = [NSUUID createUUID];
        conversation.isVideoCall = YES;
        
        id mockObserver = [OCMockObject niceMockForProtocol:@protocol(CallingInitialisationObserver)];
        id token = [conversation.voiceChannel addCallingInitializationObserver:mockObserver];
        [[mockObserver expect] couldNotInitialiseCallWithError:OCMOCK_ANY];
        
        // expect
        [(AVSFlowManager *)[[self.internalFlowManager expect] andReturnValue:OCMOCK_VALUE(NO)] canSendVideoForConversation:conversation.remoteIdentifier.transportString];
        [(AVSFlowManager *)[self.internalFlowManager reject] setVideoSendState:FLOWMANAGER_VIDEO_SEND forConversation:OCMOCK_ANY];
        
        // when
        [self.sut didEstablishMediaInConversation:conversation.remoteIdentifier.transportString];
        
        [mockObserver verify];
        [conversation.voiceChannel removeCallingInitialisationObserver:token];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    [self.internalFlowManager verify];
}

- (void)testThatItDoesNotCallAddUserWhenAVSIsNotReady
{
    //given
    [[[self.internalFlowManager expect] andReturnValue:@NO] isReady];
    
    __block ZMConversation *conv;
    __block ZMUser *user;
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        conv = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        conv.remoteIdentifier = [NSUUID createUUID];
        
        user = [ZMUser insertNewObjectInManagedObjectContext:self.uiMOC];
        user.remoteIdentifier = [NSUUID createUUID];
        user.name = @"Super User";
        
        // when
        [self.sut addJoinedCallParticipant:user inConversation:conv];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    [self.internalFlowManager verify];

    // expect
    [[[self.internalFlowManager expect] andReturnValue:@YES] isReady];
    [[self.internalFlowManager expect] addUser:conv.remoteIdentifier.transportString userId:user.remoteIdentifier.transportString name:user.name];
    
    // and when
    [self.application simulateApplicationDidBecomeActive];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    [self.internalFlowManager verify];
}


- (void)testThatItDoesNotUpdateFlowsWhenAVSIsNotReady
{
    //given
    [[[self.internalFlowManager expect] andReturnValue:@NO] isReady];
    
    __block ZMConversation *conv;
    [self.syncMOC performGroupedBlockAndWait:^{
        // given
        conv = [ZMConversation insertNewObjectInManagedObjectContext:self.syncMOC];
        conv.remoteIdentifier = [NSUUID createUUID];
        conv.callDeviceIsActive = NO;
        
        // when
        [self.sut releaseFlowsForConversation:conv];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    // we should not have called release flows yet
    [self.internalFlowManager verify];
    
    // expect
    [[[self.internalFlowManager expect] andReturnValue:@YES] isReady];
    [[self.internalFlowManager expect] releaseFlows:conv.remoteIdentifier.transportString];

    // and when
    [self.application simulateApplicationDidBecomeActive];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    [self.internalFlowManager verify];
}

- (void)testThatItDoesNotForwardEventsIfAVSIsNotReady
{
    // given
    [[[self.internalFlowManager expect] andReturnValue:@NO] isReady];
    __block NSData *innerPayloadData;
    
    [self.syncMOC performGroupedBlockAndWait:^{
        NSDictionary *payload = @{@"id": @"71bda6aa-bc34-4e9d-bceb-7e4198cc7512",
                                  @"payload": @[@{@"conversation": @"1742ca1a-9256-47b1-9459-1e8d4bc9e4a3",
                                                  @"data": @{
                                                          @"last_read": @"9.800122000a4aaa0c"
                                                          },
                                                  @"from": @"39562cc3-717d-4395-979c-5387ae17f5c3",
                                                  @"time": @"2014-06-20T14:04:38.133Z",
                                                  @"type": FlowEventName1,}]
                                  };
        ZMUpdateEvent *event = [ZMUpdateEvent eventsArrayFromPushChannelData:payload][0];
        
        innerPayloadData = [NSJSONSerialization dataWithJSONObject:event.payload options:0 error:nil];
        XCTAssertNotNil(innerPayloadData);
        
        
        // when
        [self.sut processEvents:@[event] liveEvents:YES prefetchResult:nil];
    }];
    
    // then
    // we should not have called processEventWithMediaType yet
    [self.internalFlowManager verify];
    
    // expect
    [[[self.internalFlowManager expect] andReturnValue:@YES] isReady];
    [[self.internalFlowManager expect] processEventWithMediaType:@"application/json" content:innerPayloadData];
    
    // and when
    [self.application simulateApplicationDidBecomeActive];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    [self.internalFlowManager verify];
}


@end


@implementation ZMFlowSyncTests (FlowManagerSetup)

- (void)testThatItSetsUpTheFlowManagerOnApplicationDidBecomeActive
{
    // given
    [self.application setBackground];
    
    // when
    self.onDemandFlowManager = [[ZMOnDemandFlowManager alloc] initWithMediaManager:nil];
    NSArray *events = @[FlowEventName1, FlowEventName2];
    [(AVSFlowManager *)[[self.internalFlowManager stub] andReturn:events] events];
    [self recreateSUT];
    
    // then
    XCTAssertNil(self.onDemandFlowManager.flowManager);
    
    
    // and when
    [self.application simulateApplicationDidBecomeActive];

    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertNotNil(self.onDemandFlowManager.flowManager);
}

- (void)testThatItSetsUpTheFlowManagerWhenApplicationStateChanged
{
    // given
    [self.application setBackground];
    [[[self.internalFlowManager expect] andReturnValue:@NO] isReady];

    // when
    self.onDemandFlowManager = [[ZMOnDemandFlowManager alloc] initWithMediaManager:nil];
    NSArray *events = @[FlowEventName1, FlowEventName2];
    [(AVSFlowManager *)[[self.internalFlowManager stub] andReturn:events] events];
    [self recreateSUT];
    [self simulatePushChannelOpen];

    // then
    XCTAssertNil(self.onDemandFlowManager.flowManager);
    
    
    // and when
    [self.application setActive];
    [self.sut nextRequest];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertNotNil(self.onDemandFlowManager.flowManager);

}

@end
