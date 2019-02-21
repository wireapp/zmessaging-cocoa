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
@import WireCryptobox;
@import WireDataModel;
@import avs;

#import "MessagingTest.h"
#import "ZMSyncStrategy.h"
#import <WireSyncEngine/WireSyncEngine-Swift.h>
#import <WireSyncEngine/ZMUserSession.h>
#import "MockModelObjectContextFactory.h"
#import "ZMOperationLoop+Private.h"
#import "ZMSyncStrategy+Internal.h"
#import "ZMSyncStrategy+ManagedObjectChanges.h"

@interface ZMOperationLoopTests : MessagingTest

@property (nonatomic) ZMOperationLoop *sut;
@property (nonatomic) id transportSession;
@property (nonatomic) id syncStrategy;
@property (nonatomic) PushNotificationStatus *pushNotificationStatus;
@property (nonatomic) CallEventStatus *callEventStatus;
@property (nonatomic) id mockPushChannel;
@property (nonatomic) NSMutableArray *pushChannelNotifications;
@property (nonatomic) id pushChannelObserverToken;
@end


@implementation ZMOperationLoopTests;

- (void)setUp
{
    [super setUp];
    self.pushChannelNotifications = [NSMutableArray array];
    self.transportSession = [OCMockObject niceMockForClass:[ZMTransportSession class]];
    self.syncStrategy = [OCMockObject niceMockForClass:[ZMSyncStrategy class]];
    id applicationStatusDirectory = [OCMockObject niceMockForClass:[ApplicationStatusDirectory class]];
    
    [self verifyMockLater:self.syncStrategy];
    [self verifyMockLater:self.transportSession];
    
    self.callEventStatus = [[CallEventStatus alloc] init];
    self.pushNotificationStatus = [[PushNotificationStatus alloc] initWithManagedObjectContext:self.syncMOC];
    self.mockPushChannel = [OCMockObject niceMockForClass:[ZMPushChannelConnection class]];
    
    // I expect this to be called, at least until we implement the soft sync
    [[[self.syncStrategy stub] andReturn:self.syncMOC] syncMOC];
    
    [(ApplicationStatusDirectory *)[[applicationStatusDirectory stub] andReturn:self.pushNotificationStatus] pushNotificationStatus];
    [(ApplicationStatusDirectory *)[[applicationStatusDirectory stub] andReturn:self.callEventStatus] callEventStatus];
    [(ZMSyncStrategy *)[[self.syncStrategy stub] andReturn:applicationStatusDirectory] applicationStatusDirectory];

    self.sut = [[ZMOperationLoop alloc] initWithTransportSession:self.transportSession
                                                    syncStrategy:self.syncStrategy
                                      applicationStatusDirectory:applicationStatusDirectory
                                                           uiMOC:self.uiMOC
                                                         syncMOC:self.syncMOC];
    self.pushChannelObserverToken = [NotificationInContext addObserverWithName:ZMOperationLoop.pushChannelStateChangeNotificationName
                                       context:self.uiMOC.notificationContext
                                        object:nil
                                         queue:nil
                                         using:^(NotificationInContext * note) {
                                             [self pushChannelDidChange:note];
                                         }];
}

- (void)tearDown;
{
    WaitForAllGroupsToBeEmpty(0.5);
    self.pushChannelObserverToken = nil;
    self.callEventStatus = nil;
    self.pushNotificationStatus = nil;
    [self.mockPushChannel stopMocking];
    self.mockPushChannel = nil;
    [self.transportSession stopMocking];
    self.transportSession = nil;
    [self.syncStrategy stopMocking];
    self.syncStrategy = nil;
    [self.sut tearDown];
    self.sut = nil;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [super tearDown];
}

- (void)pushChannelDidChange:(NotificationInContext *)note
{
    [self.pushChannelNotifications addObject:note];
}



- (void)testThatItNotifiesTheSyncStrategyWhenThePushChannelIsOpened
{
    // expect
    [[(id) self.syncStrategy expect] didEstablishUpdateEventsStream];
    
    // when
    [(id<ZMPushChannelConsumer>)self.sut pushChannelDidOpen:self.mockPushChannel withResponse:nil];
    
    // then
    [self.syncStrategy verify];
}

- (void)testThatItNotifiesTheSyncStrategyWhenThePushChannelIsClosed
{
    // expect
    [[(id) self.syncStrategy expect] didInterruptUpdateEventsStream];
    
    // when
    [(id<ZMPushChannelConsumer>)self.sut pushChannelDidClose:self.mockPushChannel withResponse:nil error:nil];
    
    // then
    [self.syncStrategy verify];
}

- (void)testThatItInitializesThePushChannel
{
    __block id<ZMPushChannelConsumer> receivedConsumer;
    
    // given
    id applicationStatusDirectory = [OCMockObject niceMockForClass:[ApplicationStatusDirectory class]];
    self.transportSession = [OCMockObject niceMockForClass:[ZMTransportSession class]];
    XCTestExpectation *expectation = [self expectationWithDescription:@"Open push channel opened"];
    [[self.transportSession expect] configurePushChannelWithConsumer:[OCMArg checkWithBlock:^BOOL(id obj) {
        receivedConsumer = obj;
        [expectation fulfill];
        return YES;
    }] groupQueue:OCMOCK_ANY];
    
    // when
    ZMOperationLoop *op = [[ZMOperationLoop alloc] initWithTransportSession:self.transportSession
                                                               syncStrategy:self.syncStrategy
                                                 applicationStatusDirectory:applicationStatusDirectory
                                                                      uiMOC:self.uiMOC
                                                                    syncMOC:self.syncMOC];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertNotNil(op);
    XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0.5]);
    [op tearDown];

    XCTAssertEqual(op, (id)receivedConsumer);
    
    [self.transportSession verify];
}



- (void)testThatItSendsTheNextOperation
{

    // given
    ZMTransportEnqueueResult *result = [ZMTransportEnqueueResult resultDidHaveLessRequestsThanMax:NO didGenerateNonNullRequest:NO];
    ZMTransportRequest *request = [[ZMTransportRequest alloc] initWithPath:@"/test"
                                                                   method:ZMMethodPOST
                                                                  payload:@{@"foo": @"bar"}];
    [[[self.syncStrategy stub] andReturn:request] nextRequest];
    XCTestExpectation *attemptExpectation = [self expectationWithDescription:@"attemptToEnqueue"];
    [[[[self.transportSession expect] andDo:^(NSInvocation *invocation ZM_UNUSED) {
        [attemptExpectation fulfill];
        
    }] andReturn:result] attemptToEnqueueSyncRequestWithGenerator:[OCMArg checkWithBlock:^BOOL(ZMTransportRequestGenerator gen) {
        ZMTransportRequest *generated = gen();
        BOOL equal = [request isEqual:generated];
        return equal;
    }]];
   
    // when
    [ZMRequestAvailableNotification notifyNewRequestsAvailable:self];
    
    // then
    XCTAssert([self waitForCustomExpectationsWithTimeout:0.5]);
    [self.transportSession verifyWithDelay:0.1];
}

- (void)testThatItDoesNotSendARequestIfThereAreNone
{
    // given
    ZMTransportEnqueueResult *result = [ZMTransportEnqueueResult resultDidHaveLessRequestsThanMax:NO didGenerateNonNullRequest:NO];
    [[[self.syncStrategy stub] andReturn:nil] nextRequest];

    [[[self.transportSession expect] andReturn:result] attemptToEnqueueSyncRequestWithGenerator:OCMOCK_ANY];
    
    // when
    [ZMRequestAvailableNotification notifyNewRequestsAvailable:self];
    
    // then
    [self.transportSession verifyWithDelay:0.15];
}


- (void)testThatItSendsAsManyCallsAsTheTransportSessionCanHandle
{
    // given
    ZMTransportEnqueueResult *resultOK = [ZMTransportEnqueueResult resultDidHaveLessRequestsThanMax:YES didGenerateNonNullRequest:YES];
    ZMTransportEnqueueResult *resultNO = [ZMTransportEnqueueResult resultDidHaveLessRequestsThanMax:NO didGenerateNonNullRequest:NO];
    
    ZMTransportRequest *request = [[ZMTransportRequest alloc] initWithPath:@"/test" method:ZMMethodPOST payload:@{}];
    int stopAt = 3;
    
    __block int numRequests = 0;
    BOOL(^verifier)(ZMTransportRequestGenerator) = ^BOOL(ZMTransportRequestGenerator generator) {
        ++numRequests;
        if(numRequests < stopAt) {
            // generator will create a new sendRequest
            ZMTransportRequest *generated = generator();
            return [request isEqual:generated];
        }
        else {
            // if I don't call generator, it should not invoke another sendRequest
            return YES;
        }
    };
    
    [[[self.syncStrategy stub] andReturn:request] nextRequest];


    [[[self.transportSession expect] andReturn:resultOK] attemptToEnqueueSyncRequestWithGenerator:[OCMArg checkWithBlock:verifier]];
    [[[self.transportSession expect] andReturn:resultOK] attemptToEnqueueSyncRequestWithGenerator:[OCMArg checkWithBlock:verifier]];
    
    XCTestExpectation *attemptExpectation = [self expectationWithDescription:@"attemptToEnqueue"];
    [[[[self.transportSession expect] andReturn:resultNO] andDo:^(NSInvocation *invocation ZM_UNUSED) {
        [attemptExpectation fulfill];
    }] attemptToEnqueueSyncRequestWithGenerator:[OCMArg checkWithBlock:verifier]];
    
    [[self.transportSession reject] attemptToEnqueueSyncRequestWithGenerator:OCMOCK_ANY];

    // when
    [ZMRequestAvailableNotification notifyNewRequestsAvailable:self];

    // then
    XCTAssert([self waitForCustomExpectationsWithTimeout:0.6]);
    [self.transportSession verifyWithDelay:0.2]; //a delay so that the last sendRequest call has a chance to fail
}

- (void)testThatExecuteNextOperationIsCalledWhenThePreviousRequestIsCompleted
{
    // given
    NSManagedObjectContext *moc = [OCMockObject mockForClass:NSManagedObjectContext.class];
    [[[self.syncStrategy stub] andReturn:moc] syncMOC];
    [[(id)moc stub] saveOrRollback];

    ZMTransportEnqueueResult *resultYES = [ZMTransportEnqueueResult resultDidHaveLessRequestsThanMax:YES didGenerateNonNullRequest:YES];
    ZMTransportEnqueueResult *resultNO = [ZMTransportEnqueueResult resultDidHaveLessRequestsThanMax:NO didGenerateNonNullRequest:NO];
    
    ZMTransportRequest *request = [ZMTransportRequest requestWithPath:@"/boo" method:ZMMethodGET payload:nil];

    [[[self.syncStrategy stub] andReturn:nil] syncMOC];

    // expect
    [[[self.syncStrategy expect] andReturn:request] nextRequest];
    
    BOOL(^checkGenerator)(ZMTransportRequestGenerator) = ^BOOL(ZMTransportRequestGenerator generator) {
        if(generator) {
            generator();
        }
        return YES;
    };
    
    [[[self.transportSession expect] andReturn:resultYES] attemptToEnqueueSyncRequestWithGenerator:[OCMArg checkWithBlock:checkGenerator]];
    [[[self.transportSession expect] andReturn:resultNO] attemptToEnqueueSyncRequestWithGenerator:OCMOCK_ANY];
    [[[self.transportSession expect] andReturn:resultNO] attemptToEnqueueSyncRequestWithGenerator:OCMOCK_ANY];
    [ZMRequestAvailableNotification notifyNewRequestsAvailable:self]; // this will enqueue `request`
    WaitForAllGroupsToBeEmpty(0.5);
    
    // when
    [request completeWithResponse:[ZMTransportResponse responseWithPayload:@{} HTTPStatus:200 transportSessionError:nil]];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    [self.transportSession verifyWithDelay:0.15];
    [self.syncStrategy verifyWithDelay:0.15];

}

- (void)testThatMOCIsSavedOnSuccessfulRequest
{
    // given
    id mockObserver = [OCMockObject observerMock];
    [[NSNotificationCenter defaultCenter] addMockObserver:mockObserver name:NSManagedObjectContextDidSaveNotification object:self.syncMOC];

    ZMTransportEnqueueResult *resultYES = [ZMTransportEnqueueResult resultDidHaveLessRequestsThanMax:YES didGenerateNonNullRequest:YES];
    ZMTransportEnqueueResult *resultNO = [ZMTransportEnqueueResult resultDidHaveLessRequestsThanMax:NO didGenerateNonNullRequest:NO];

    ZMTransportRequest *request = [ZMTransportRequest requestWithPath:@"/boo" method:ZMMethodGET payload:nil];

    // expect
    [[mockObserver expect] notificationWithName:NSManagedObjectContextDidSaveNotification object:OCMOCK_ANY userInfo:OCMOCK_ANY];
    [[[self.syncStrategy expect] andReturn:request] nextRequest];

    BOOL(^checkGenerator)(ZMTransportRequestGenerator) = ^BOOL(ZMTransportRequestGenerator generator) {
        if(generator) {
            generator();
        }
        return YES;
    };

    [[[self.transportSession expect] andReturn:resultYES] attemptToEnqueueSyncRequestWithGenerator:[OCMArg checkWithBlock:checkGenerator]];
    [[[self.transportSession stub] andReturn:resultNO] attemptToEnqueueSyncRequestWithGenerator:OCMOCK_ANY];
    [[self.syncStrategy stub] processSaveWithInsertedObjects:OCMOCK_ANY updateObjects:OCMOCK_ANY];

    [ZMRequestAvailableNotification notifyNewRequestsAvailable:self]; // this will enqueue `request`
    WaitForAllGroupsToBeEmpty(0.5);
    
    [request addCompletionHandler:[ZMCompletionHandler handlerOnGroupQueue:self.syncMOC block:^(ZMTransportResponse *resp ZM_UNUSED) {
        NOT_USED([[ZMClientMessage alloc] initWithNonce:NSUUID.createUUID managedObjectContext:self.syncMOC]);
    }]];
    
    // when
    [request completeWithResponse:[ZMTransportResponse responseWithPayload:@{} HTTPStatus:200 transportSessionError:nil]];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    [self.transportSession verifyWithDelay:0.15];
    [self.syncStrategy verifyWithDelay:0.15];
    
    WaitForAllGroupsToBeEmpty(0.5);
    [mockObserver verify];
    
    [[NSNotificationCenter defaultCenter] removeObserver:mockObserver];

}

- (void)testThatMOCIsSavedOnFailedRequest
{
    // given
    id mockObserver = [OCMockObject observerMock];
    [[NSNotificationCenter defaultCenter] addMockObserver:mockObserver name:NSManagedObjectContextDidSaveNotification object:self.syncMOC];
    
    ZMTransportEnqueueResult *resultYES = [ZMTransportEnqueueResult resultDidHaveLessRequestsThanMax:YES didGenerateNonNullRequest:YES];
    ZMTransportEnqueueResult *resultNO = [ZMTransportEnqueueResult resultDidHaveLessRequestsThanMax:NO didGenerateNonNullRequest:NO];
    
    ZMTransportRequest *request = [ZMTransportRequest requestWithPath:@"/boo" method:ZMMethodGET payload:nil];
    
    // expect
    [[mockObserver expect] notificationWithName:NSManagedObjectContextDidSaveNotification object:OCMOCK_ANY userInfo:OCMOCK_ANY];
    [[[self.syncStrategy expect] andReturn:request] nextRequest];
    
    BOOL(^checkGenerator)(ZMTransportRequestGenerator) = ^BOOL(ZMTransportRequestGenerator generator) {
        if(generator) {
            generator();
        }
        return YES;
    };
    
    [[[self.transportSession expect] andReturn:resultYES] attemptToEnqueueSyncRequestWithGenerator:[OCMArg checkWithBlock:checkGenerator]];
    [[[self.transportSession stub] andReturn:resultNO] attemptToEnqueueSyncRequestWithGenerator:OCMOCK_ANY];
    [[self.syncStrategy stub] processSaveWithInsertedObjects:OCMOCK_ANY updateObjects:OCMOCK_ANY];
    [ZMRequestAvailableNotification notifyNewRequestsAvailable:self]; // this will enqueue `request`
    WaitForAllGroupsToBeEmpty(0.5);
    
    [request addCompletionHandler:[ZMCompletionHandler handlerOnGroupQueue:self.syncMOC block:^(ZMTransportResponse *resp ZM_UNUSED) {
        NOT_USED([[ZMClientMessage alloc] initWithNonce:NSUUID.createUUID managedObjectContext:self.syncMOC]);
    }]];
    
    // when
    [request completeWithResponse:[ZMTransportResponse responseWithPayload:@{} HTTPStatus:400 transportSessionError:nil]];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    [self.transportSession verifyWithDelay:0.15];
    [self.syncStrategy verifyWithDelay:0.15];
    WaitForAllGroupsToBeEmpty(0.5);
    [mockObserver verify];
    
    [[NSNotificationCenter defaultCenter] removeObserver:mockObserver];
    
}



- (void)testThatWhenThereIsAnInsertionItAsksForNextRequest
{
    // given
    NOT_USED([[ZMClientMessage alloc] initWithNonce:NSUUID.createUUID managedObjectContext:self.uiMOC]);
    ZMTransportEnqueueResult *resultNO = [ZMTransportEnqueueResult resultDidHaveLessRequestsThanMax:NO didGenerateNonNullRequest:NO];

    BOOL(^checkGenerator)(ZMTransportRequestGenerator) = ^BOOL(ZMTransportRequestGenerator generator) {
        if(generator) {
            generator();
        }
        return YES;
    };


    // expect
    [[[self.syncStrategy expect] andReturnValue:@YES]
     processSaveWithInsertedObjects:OCMOCK_ANY updateObjects:OCMOCK_ANY];
    [[[self.syncStrategy expect] andReturn:nil] nextRequest];
    [[[self.transportSession expect] andReturn:resultNO] attemptToEnqueueSyncRequestWithGenerator:[OCMArg checkWithBlock:checkGenerator]];

    [self verifyMockLater:self.syncStrategy];
    [self verifyMockLater:self.transportSession];

    // when
    NSError *error;
    XCTAssertTrue([self.uiMOC save:&error]);
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatWhenThereIsAnUpdateItAsksForNextRequest
{
    ZMClientMessage *entity = [[ZMClientMessage alloc] initWithNonce:NSUUID.createUUID managedObjectContext:self.uiMOC];

    [[[self.syncStrategy expect] andReturnValue:@YES]
     processSaveWithInsertedObjects:OCMOCK_ANY updateObjects:OCMOCK_ANY];
    ZMTransportEnqueueResult *resultNO = [ZMTransportEnqueueResult resultDidHaveLessRequestsThanMax:NO didGenerateNonNullRequest:NO];
    [[[self.transportSession expect] andReturn:resultNO] attemptToEnqueueSyncRequestWithGenerator:OCMOCK_ANY];
    
    NSError *error;
    XCTAssertTrue([self.uiMOC save:&error]);
    WaitForAllGroupsToBeEmpty(0.5);
    
    entity.nonce = NSUUID.createUUID;

    BOOL(^checkGenerator)(ZMTransportRequestGenerator) = ^BOOL(ZMTransportRequestGenerator generator) {
        if(generator) {
            generator();
        }
        return YES;
    };

    // expect
    [[[self.syncStrategy expect] andReturn:nil] nextRequest];
    [[[self.syncStrategy expect] andReturnValue:@YES]
     processSaveWithInsertedObjects:OCMOCK_ANY updateObjects:OCMOCK_ANY];
    [[[self.transportSession expect] andReturn:resultNO] attemptToEnqueueSyncRequestWithGenerator:[OCMArg checkWithBlock:checkGenerator]];

    [self verifyMockLater:self.syncStrategy];
    [self verifyMockLater:self.transportSession];

    // when
    XCTAssertTrue([self.uiMOC save:&error]);
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatItCallsProcessSaveOnSyncStrategyEvenIfThereAreNoChanges
{
    // given
    ZMTransportEnqueueResult *resultNO = [ZMTransportEnqueueResult resultDidHaveLessRequestsThanMax:NO didGenerateNonNullRequest:NO];
    [[[self.transportSession stub] andReturn:resultNO] attemptToEnqueueSyncRequestWithGenerator:OCMOCK_ANY];
    
    // expect
    [[self.syncStrategy expect] processSaveWithInsertedObjects:OCMOCK_ANY updateObjects:OCMOCK_ANY];
    
    // when
    NSError *error;
    XCTAssertTrue([self.uiMOC save:&error]);
    WaitForAllGroupsToBeEmpty(0.5);
}


- (void)testThatItCallsSyncStrategyDidRegisterWithInsertedObjects
{
    // given
    ZMClientMessage *entity1 = [[ZMClientMessage alloc] initWithNonce:NSUUID.createUUID managedObjectContext:self.uiMOC];
    ZMClientMessage *entity2 = [[ZMClientMessage alloc] initWithNonce:NSUUID.createUUID managedObjectContext:self.uiMOC];
    
    NSSet *insertSet = [NSSet setWithObjects:entity1, entity2, nil];

    [[[self.syncStrategy expect] andReturnValue:@NO]
     processSaveWithInsertedObjects:[OCMArg checkWithBlock:^BOOL(NSSet *inserted) {
        [self checkThatObjectIDs:insertSet match:inserted];

        return YES;
    }] updateObjects:OCMOCK_ANY];
    [[self.transportSession stub] attemptToEnqueueSyncRequestWithGenerator:OCMOCK_ANY];
    
    // expect
    [self verifyMockLater:self.syncStrategy];
    
    // when
    NSError *error;
    XCTAssertTrue([self.uiMOC save:&error]);
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatItCallsSyncStrategyDidRegisterWithUpdatedObjects
{
    // given
    NOT_USED([[ZMClientMessage alloc] initWithNonce:NSUUID.createUUID managedObjectContext:self.uiMOC]);
    ZMClientMessage *entity2 = [[ZMClientMessage alloc] initWithNonce:NSUUID.createUUID managedObjectContext:self.uiMOC];

    [[[self.syncStrategy expect] andReturnValue:@NO]
     processSaveWithInsertedObjects:OCMOCK_ANY updateObjects:OCMOCK_ANY];
    
    __block NSError *error;
    XCTAssertTrue([self.uiMOC save:&error]);

    entity2.nonce = NSUUID.createUUID;
    
    NSSet *updatedSet = [NSSet setWithObjects:entity2, nil];

    [[[self.syncStrategy expect] andReturnValue:@NO]
     processSaveWithInsertedObjects:OCMOCK_ANY updateObjects:[OCMArg checkWithBlock:^BOOL(NSSet *updated) {
        [self checkThatObjectIDs:updatedSet match:updated];

        return YES;
    }]];
    [[self.transportSession stub] attemptToEnqueueSyncRequestWithGenerator:OCMOCK_ANY];

    
    // expect
    [self verifyMockLater:self.syncStrategy];
    
    // when
    XCTAssertTrue([self.uiMOC save:&error]);
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatSyncStrategyDidRegisterIsCalledWithInsertedObjectsFromTheSyncContext
{
    // given
    ZMClientMessage *entity1 = [[ZMClientMessage alloc] initWithNonce:NSUUID.createUUID managedObjectContext:self.uiMOC];
    ZMClientMessage *entity2 = [[ZMClientMessage alloc] initWithNonce:NSUUID.createUUID managedObjectContext:self.uiMOC];
    
    NSSet *insertSet = [NSSet setWithObjects:entity1, entity2, nil];

    [[[self.syncStrategy expect] andReturnValue:@NO]
     processSaveWithInsertedObjects:[OCMArg checkWithBlock:^BOOL(NSSet *inserted) {
        [self checkThatObjectIDs:insertSet match:inserted];

        return YES;
    }] updateObjects:OCMOCK_ANY];
    [[self.transportSession stub] attemptToEnqueueSyncRequestWithGenerator:OCMOCK_ANY];

    
    // expect
    [self verifyMockLater:self.syncStrategy];
    
    // when
    NSError *error;
    XCTAssertTrue([self.uiMOC save:&error], @"Error in saving %@", error);
    WaitForAllGroupsToBeEmpty(0.5);
}


- (void)checkThatObjectIDs:(NSSet *)expected match:(NSSet *)actualObjects {
    
    XCTAssertEqual(expected.count, actualObjects.count);
    for(NSManagedObject *obj in actualObjects){
        XCTAssertEqualObjects(obj.managedObjectContext, self.syncMOC);
        NSSet *matches = [expected objectsPassingTest:^BOOL(NSManagedObject *expectedObj, BOOL *stop) {
            NOT_USED(stop);
            return [expectedObj.objectID isEqual:obj.objectID];
        }];
        XCTAssertEqual(1u, matches.count);
    }
}

- (void)testThatSyncStrategyDidRegisterIsCalledWithUpdatedObjectsFromTheSyncContext
{
    // given
    NOT_USED([[ZMClientMessage alloc] initWithNonce:NSUUID.createUUID managedObjectContext:self.uiMOC]);
    ZMClientMessage *entity2 = [[ZMClientMessage alloc] initWithNonce:NSUUID.createUUID managedObjectContext:self.uiMOC];

    [[[self.syncStrategy expect] andReturnValue:@NO]
     processSaveWithInsertedObjects:OCMOCK_ANY updateObjects:OCMOCK_ANY];
    
    __block NSError *error;
    XCTAssertTrue([self.uiMOC save:&error]);
    
    entity2.nonce = NSUUID.createUUID;

    [[[self.syncStrategy expect] andReturnValue:@NO]
     processSaveWithInsertedObjects:OCMOCK_ANY updateObjects:[OCMArg checkWithBlock:^BOOL(NSSet *updated) {

        XCTAssertEqual(1u, updated.count);
        NSManagedObject *obj = [updated anyObject];
        XCTAssertEqualObjects(obj.managedObjectContext, self.syncMOC);
        XCTAssertEqualObjects(obj.objectID, entity2.objectID);

        return YES;
    }]];
    [[self.transportSession stub] attemptToEnqueueSyncRequestWithGenerator:OCMOCK_ANY];

    
    // expect
    [self verifyMockLater:self.syncStrategy];
    
    // when
    [self.uiMOC performBlockAndWait:^{
        XCTAssertTrue([self.uiMOC save:&error]);
    }];
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatItAsksSyncStrategyForNextOperationOnZMOperationLoopNewRequestAvailableNotification
{
    // given
    ZMTransportEnqueueResult *resultNO = [ZMTransportEnqueueResult resultDidHaveLessRequestsThanMax:NO didGenerateNonNullRequest:NO];

    BOOL(^checkGenerator)(ZMTransportRequestGenerator) = ^BOOL(ZMTransportRequestGenerator generator) {
        if(generator) {
            generator();
        }
        return YES;
    };
    
    [[[self.transportSession stub] andReturn:resultNO] attemptToEnqueueSyncRequestWithGenerator:[OCMArg checkWithBlock:checkGenerator]];

    
    // expect
    [[[self.syncStrategy expect] andReturn:nil] nextRequest];
    [self verifyMockLater:self.syncStrategy];
    
    // when
    [ZMRequestAvailableNotification notifyNewRequestsAvailable:self];
    WaitForAllGroupsToBeEmpty(0.5);
    
}


- (void)testThatPushChannelDataIsSplitAndForwardedToAllIndividualObjects
{
    // given
    NSString *eventType = @"user.update";
    
    NSDictionary *payload1 = @{
                               @"type" : eventType,
                               @"foo" : @"bar"
                               };
    NSDictionary *payload2 = @{
                               @"type" : eventType,
                               @"bar" : @"xxxxxxx"
                               };
    NSDictionary *payload3 = @{
                               @"type" : eventType,
                               @"baz" : @"barbar"
                               };
    
    NSDictionary *eventData = @{
                                @"id" : @"5cc1ab91-45f4-49ec-bb7a-a5517b7a4173",
                                @"payload" : @[payload1, payload2, payload3],
                                };
    
    NSMutableArray *expectedEvents = [NSMutableArray array];
    [expectedEvents addObjectsFromArray:[ZMUpdateEvent eventsArrayFromPushChannelData:eventData]];
    XCTAssertGreaterThan(expectedEvents.count, 0u);
    
    // expect
    [[self.syncStrategy expect] processUpdateEvents:expectedEvents ignoreBuffer:NO];
    
    // when
    [(id<ZMPushChannelConsumer>)self.sut pushChannel:self.mockPushChannel didReceiveTransportData:eventData];
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)testThatProcessSyncDataIsNotForwardedToAllSyncObjectsIfItIsNotAnArray
{
    // given
    NSDictionary *eventdata = @{
                                @"id" : @"16be010d-c284-4fc0-b636-837bcebed654",
                                @"payload" : @{
                                        @"type" : @"yyy",
                                        @"cat" : @"dog"
                                        },
                                };
    
    // expect
    [[self.syncStrategy reject] processUpdateEvents:OCMOCK_ANY ignoreBuffer:NO];
    [[self.syncStrategy reject] processUpdateEvents:OCMOCK_ANY ignoreBuffer:YES];
    
    // when
    [self performIgnoringZMLogError:^{
        [(id<ZMPushChannelConsumer>)self.sut pushChannel:self.mockPushChannel didReceiveTransportData:eventdata];
        WaitForAllGroupsToBeEmpty(0.5);
    }];
}

- (void)testThatProcessSyncDataIsNotForwardedToAllSyncObjectsIfEventsAreInvalid
{
    // given
    NSArray *eventdata = @[ @{ @"id" : @"16be010d-c284-4fc0-b636-837bcebed654" } ];
    
    // expect
    [[self.syncStrategy reject] processUpdateEvents:OCMOCK_ANY ignoreBuffer:NO];
    [[self.syncStrategy reject] processUpdateEvents:OCMOCK_ANY ignoreBuffer:YES];
    
    // when
    [self performIgnoringZMLogError:^{
        [(id<ZMPushChannelConsumer>)self.sut pushChannel:self.mockPushChannel didReceiveTransportData:eventdata];
        WaitForAllGroupsToBeEmpty(0.5);
    }];
}

- (void)testThatItSendsANotificationWhenClosingThePushChannelAndRemovingConsumers
{
    // given
    id fakeResponse = [OCMockObject niceMockForClass:[NSHTTPURLResponse class]];
    [[self.syncStrategy stub] didInterruptUpdateEventsStream];
    
    // when
    [(id<ZMPushChannelConsumer>)self.sut pushChannelDidClose:self.mockPushChannel withResponse:fakeResponse error:nil];
    
    // then
    XCTAssertEqual(self.pushChannelNotifications.count, 1u);
    NSNotification *note = self.pushChannelNotifications.firstObject;
    XCTAssertFalse([note.userInfo[ZMPushChannelIsOpenKey] boolValue]);
}

- (void)testThatItSendsANotificationWhenOpeningThePushChannel
{
    // given
    id fakeResponse = [OCMockObject niceMockForClass:[NSHTTPURLResponse class]];
    [[self.syncStrategy stub] didEstablishUpdateEventsStream];

    // when
    [(id<ZMPushChannelConsumer>)self.sut pushChannelDidOpen:self.mockPushChannel withResponse:fakeResponse];
    
    // then
    XCTAssertEqual(self.pushChannelNotifications.count, 1u);
    NSNotification *note = self.pushChannelNotifications.firstObject;
    XCTAssertTrue([note.userInfo[ZMPushChannelIsOpenKey] boolValue]);
}

- (void)testThatItInformsTransportSessionWhenEnteringForeground
{
    // expect
    [[self.transportSession expect] enterForeground];
    
    // when
    [self.sut operationStatusDidChangeState:SyncEngineOperationStateForeground];
    
    // then
    [self.transportSession verify];
}

- (void)testThatItInformsTransportSessionWhenEnteringBackground
{
    // expect
    [[self.transportSession expect] enterBackground];
    
    // when
    [self.sut operationStatusDidChangeState:SyncEngineOperationStateBackground];
    
    // then
    [self.transportSession verify];
}

@end



#if TARGET_OS_IPHONE

@implementation ZMOperationLoopTests (Background)

- (APSSignalingKeysStore *)prepareSelfClientForAPSSignalingStore
{
    [[self.syncStrategy stub] processSaveWithInsertedObjects:OCMOCK_ANY updateObjects:OCMOCK_ANY];
    
    NSString *macKey = @"OnuLUsjZT5ix8mebzewnNH7kVuLNYvDTxVFe8xiZ1u0=";
    NSString *encryptionKey = @"eiISyl78bYnFZaXsjvZh4v7d/mnNLDQNB+vRcsapovA=";
    
    NSData *macKeyData = [[NSData alloc] initWithBase64EncodedString:macKey options:0];
    NSData *encryptionKeyData = [[NSData alloc] initWithBase64EncodedString:encryptionKey options:0];
    
    UserClient *selfClient = [self createSelfClient];
    selfClient.apsDecryptionKey = encryptionKeyData;
    selfClient.apsVerificationKey = macKeyData;

    return [[APSSignalingKeysStore alloc] initWithUserClient:selfClient];
}

-(void)clearKeyChainData
{
    [ZMKeychain deleteAllKeychainItemsWithAccountName: @"APSVerificationKey"];
    [ZMKeychain deleteAllKeychainItemsWithAccountName: @"APSDecryptionKey"];
}

- (NSDictionary *)pushPayloadForEventPayload:(NSArray *)eventPayloads identifier:(NSUUID *)identifier
{
    return @{
             @"aps": @{ @"content-available": @1 },
             @"data": @{
                     @"type": @"plain",
                     @"data": @{
                             @"id": identifier.transportString,
                             @"payload": eventPayloads
                             }
                     }
             };
}

- (NSDictionary *)pushPayloadForEventPayload:(NSArray *)eventPayloads
{
    return [self pushPayloadForEventPayload:eventPayloads identifier:NSUUID.createUUID];
}

- (NSDictionary *)alertPushPayloadForEventPayload:(NSArray *)eventPayloads
{
    return @{
             @"aps": @{@"content-available": @1,
                       @"alert": @{@"foo": @"bar"}
                       },
             @"data": @{
                     @"type": @"plain",
                     @"data": @{
                             @"id": [[NSUUID createUUID] transportString],
                             @"payload": eventPayloads
                             }
                     }
             };
}

- (NSDictionary *)fallbackAPNSPayloadWithIdentifier:(NSUUID *)uuid
{
    return @{
             @"aps": @{
                     @"content-available": @1,
                     @"alert": @{ @"foo": @"bar" }
                     },
             @"data": @{
                     @"type": @"notice",
                     @"data": @{ @"id": uuid.transportString }
                     }
             };
}

- (NSDictionary *)payloadForMessageAddEvent
{
    return [self payloadForMessageAddEventWithNonce:NSUUID.createUUID];
}

- (NSDictionary *)payloadForMessageAddEventWithNonce:(NSUUID *)uuid
{
    return @{
            @"conversation": [[NSUUID createUUID] transportString],
            @"time": [NSDate date],
            @"data": @{
                    @"content": @"saf",
                    @"nonce": [uuid transportString],
                    },
            @"from": [[NSUUID createUUID] transportString],
            @"type": @"conversation.message-add"
            };
}

- (NSDictionary *)noticePushPayloadWithUUID:(NSUUID *)uuid
{
    return  @{@"aps" : @{},
              @"data" : @{
                      @"data" : @{ @"id" : uuid.transportString },
                      @"type" : @"notice"
                      }
              };
}

- (NSDictionary *)encryptedPushPayload
{
    return @{
             @"aps" : @{@"alert": @{@"loc-args": @[],
                                    @"loc-key": @"push.notification.new_message"}
                        },
             @"data": @{
                     @"data" : @"70XpQ4qri2D4YCU7lvSjaqk+SgN/s4dDv/J8uMUel0xY8quNetPF8cMXskAZwBI9EArjMY/NupWo8Bar14GHi9ISzlOswDsoQ6BQiFsEdnv4shT+ZpJ+wghmPF+sxWhys9048ny6WiSqywUNzsUPjDrudAAiG4bPjS2FjMou2/o7FpCg7+6p8fcSYCcvQllv6P8oidVbMlpnT1Bs7fK6fz9ceq6H3L+BKZai82H7gc6nxSS5Gjf56qvDqdc3J9jTowpdjyqHGO26YahMQtDf4tn6KuTSp4OG1qLPk6jFf4xO2q/WrxV2dnoXGXWbIZ4cnohkeA85QxMhpM9pIGAbZ58fRUt9fPXm6PmX3rqQY7MSv4TV1fLyb5Zqo/yqQbcE2qS/dJKRrzwW5MWlKVWfacuNRZnansMMGUYyt7iRpD/E8PdtSfW7QO/02Evureor7MqQ8AYf6Ivt3Ksf1wplXne0zl8CT5GMeExB7DLfyr8T1xK6H+u3y29FmI9/T01la5cbIq/E83Yh2LTNo3X4eOfZ6mhC0EIC8YEyo/0x2IHsLyCAjzvIFfTSD8tOpa1yQTBSQ3mGGDWiPJ3f6OypQFj+vY13Bq9WZoL9Q+UbYbxdzkaYILaX2UakZ5OafQ7nH0WslvfzjRsdYoruTGDV+E8mXB2JOZh9ij2PT8fWsyJJ9DqKg5Iw2EPfUlXBv3pXIpZuL6+g8c2von092bV2pHTWkPE4A2yvw3LTzI8e9puOr5K87JUQHdR7mfXYifErW+9TRrmBibF5wKZtVl97UOFOps4/ZXU9i6Lr0qKKMdX3iruo7o3fYcbJTajb+sZLttDPsKnJHnnMxJUB3D+I1UuA35hL6Fy2wLj2mRNAzWuitNj9MSDUhDHU42+bZnap",
                     @"mac": @"ZGe7fjgAEvTjfSSv2MuDHQe7BCRj2NT7qg8OAm8JZyI=",
                     @"type": @"cipher"
                     }
             };
}

- (void)testThatItForwardsEventsFromSilentPushesToThePushNotificationStatus
{
    // given
    NSUUID *identifier = NSUUID.timeBasedUUID;
    NSDictionary *eventPayload = [self payloadForMessageAddEvent];
    NSDictionary *pushPayload = [self pushPayloadForEventPayload:@[eventPayload] identifier:identifier];
    NSArray *events = [ZMUpdateEvent eventsArrayFromPushChannelData:pushPayload[@"data"][@"data"]];
    XCTAssertNotNil(events);
    
    // when
    [self.sut fetchEventsFromPushChannelPayload:pushPayload completionHandler:^{}];
    WaitForAllGroupsToBeEmpty(1.0);
    
    // then
    XCTAssertEqual(self.pushNotificationStatus.status, BackgroundNotificationFetchStatusInProgress);
}


- (void)testThatItForwardsEventsFromEncryptedPushesToThePushNotificationStatus
{
    // given
    self.sut.apsSignalKeyStore = [self prepareSelfClientForAPSSignalingStore];
    NSDictionary *pushPayload = [self encryptedPushPayload];
    
    // when
    [self.sut fetchEventsFromPushChannelPayload:pushPayload completionHandler:^{}];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(self.pushNotificationStatus.status, BackgroundNotificationFetchStatusInProgress);
    [self clearKeyChainData];
}

- (void)testThatItForwardsNoticeNotificationsToThePushNotificationStatus
{
    // given
    XCTAssertTrue([self.syncMOC saveOrRollback]);
    WaitForAllGroupsToBeEmpty(0.5);

    NSUUID *notificationID = NSUUID.timeBasedUUID;
    NSDictionary *pushPayload = [self noticePushPayloadWithUUID:notificationID];

    // when
    [self.sut fetchEventsFromPushChannelPayload:pushPayload completionHandler:^{}];
    WaitForAllGroupsToBeEmpty(1.0);

    // then
    XCTAssertEqual(self.pushNotificationStatus.status, BackgroundNotificationFetchStatusInProgress);
}

- (void)testThatItCallsCompletionHandlerWhenEventsAreDownloaded
{
    // given
    XCTAssertTrue([self.syncMOC saveOrRollback]);
    WaitForAllGroupsToBeEmpty(0.5);
    
    NSUUID *notificationID = NSUUID.timeBasedUUID;
    NSDictionary *pushPayload = [self noticePushPayloadWithUUID:notificationID];
    
    // expect
    XCTestExpectation *expectation = [self expectationWithDescription:@"Called completion handler"];
    [self.sut fetchEventsFromPushChannelPayload:pushPayload completionHandler:^{
        [expectation fulfill];
    }];
    WaitForAllGroupsToBeEmpty(1.0);
    
    // when
    [self.pushNotificationStatus didFetchEventIds:@[notificationID] lastEventId:notificationID finished:YES];
    
    XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0.5]);
}

- (void)testThatItCallsCompletionHandlerAfterCallEventsHaveBeenProcessed
{
    // given
    XCTAssertTrue([self.syncMOC saveOrRollback]);
    WaitForAllGroupsToBeEmpty(0.5);
    
    NSUUID *notificationID = NSUUID.timeBasedUUID;
    NSDictionary *pushPayload = [self noticePushPayloadWithUUID:notificationID];
    
    // expect
    __block BOOL completionHandlerHasBeenCalled = NO;
    XCTestExpectation *expectation = [self expectationWithDescription:@"Called completion handler"];
    [self.sut fetchEventsFromPushChannelPayload:pushPayload completionHandler:^{
        [expectation fulfill];
        completionHandlerHasBeenCalled = YES;
    }];
    WaitForAllGroupsToBeEmpty(1.0);
    
    // when
    [self.callEventStatus scheduledCallEventForProcessing];
    [self.pushNotificationStatus didFetchEventIds:@[notificationID] lastEventId:notificationID finished:YES];
    WaitForAllGroupsToBeEmpty(1.0);
    
    XCTAssertFalse(completionHandlerHasBeenCalled);
    
    [self.callEventStatus finishedProcessingCallEvent];
    XCTAssertTrue([self waitForCustomExpectationsWithTimeout:0.5]);
}

@end

#endif
