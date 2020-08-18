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
@import WireSyncEngine;

#import "WireSyncEngine_iOS_Tests-Swift.h"
#import "ObjectTranscoderTests.h"
#import "ZMLastUpdateEventIDTranscoder+Internal.h"
#import "ZMObjectStrategyDirectory.h"
#import "ZMMissingUpdateEventsTranscoder+Internal.h"

@interface ZMLastUpdateEventIDTranscoderTests : ObjectTranscoderTests

@property (nonatomic) ZMLastUpdateEventIDTranscoder *sut;
@property (nonatomic) id<ZMObjectStrategyDirectory> directory;
@property (nonatomic) ZMSingleRequestSync *downstreamSync;
@property (nonatomic) MockSyncStatus *mockSyncStatus;
@property (nonatomic) id syncStateDelegate;

@end

@implementation ZMLastUpdateEventIDTranscoderTests

- (void)setUp {
    [super setUp];
    
    self.downstreamSync = [OCMockObject mockForClass:ZMSingleRequestSync.class];
    [self verifyMockLater:self.downstreamSync];
    
    self.directory = [self createMockObjectStrategyDirectoryInMoc:self.uiMOC];
    self.syncStateDelegate = [OCMockObject niceMockForProtocol:@protocol(ZMSyncStateDelegate)];
    self.mockSyncStatus = [[MockSyncStatus alloc] initWithManagedObjectContext:self.syncMOC syncStateDelegate:self.syncStateDelegate];
    self.mockSyncStatus.mockPhase = SyncPhaseDone;
    self.mockApplicationStatus.mockSynchronizationState = ZMSynchronizationStateSynchronizing;

    self.sut = [[ZMLastUpdateEventIDTranscoder alloc] initWithManagedObjectContext:self.uiMOC applicationStatus:self.mockApplicationStatus syncStatus:self.mockSyncStatus objectDirectory:self.directory];
    self.sut.lastUpdateEventIDSync = self.downstreamSync;
    
    [self verifyMockLater:self.syncStrategy];
}

- (void)tearDown {
    self.downstreamSync = nil;
    self.directory = nil;
    [self.syncStateDelegate stopMocking];
    self.syncStateDelegate = nil;
    self.mockSyncStatus = nil;
    self.syncStrategy = nil;
    self.sut = nil;
    [super tearDown];
}

- (void)injectLastUpdateEventID:(NSString *)updateEventID
{
    NSDictionary *payload = @{ @"id" : updateEventID };
    ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:payload HTTPStatus:200 transportSessionError:nil];
    [self.sut didReceiveResponse:response forSingleRequest:self.downstreamSync];
}

- (void)testThatItOnlyProcessesLastUpdateEventsRequests;
{
    // when
    NSArray *generators = self.sut.requestGenerators;
    
    // then
    XCTAssertEqual(generators.count, 1u);
    XCTAssertTrue([generators.firstObject isKindOfClass:ZMSingleRequestSync.class]);
}

- (void)testThatItDoesNotReturnAContextChangeTracker;
{
    // when
    NSArray *trackers = self.sut.contextChangeTrackers;
    
    // then
    XCTAssertEqual(trackers.count, 0u);
}

- (void)testThatItReturnsTheDownstreamSync
{
    XCTAssertEqual(self.sut.lastUpdateEventIDSync, self.downstreamSync);
}

- (void)testThatItCreatesTheRightDownstreamSync
{
    // when
    ZMLastUpdateEventIDTranscoder *sut = [[ZMLastUpdateEventIDTranscoder alloc] initWithManagedObjectContext:self.uiMOC applicationStatus:self.mockApplicationStatus syncStatus:self.mockSyncStatus objectDirectory:self.directory];
    id transcoder = sut.lastUpdateEventIDSync.transcoder;
    
    // then
    XCTAssertNotNil(sut.lastUpdateEventIDSync);
    XCTAssertEqual(sut.lastUpdateEventIDSync.groupQueue, self.uiMOC);
    XCTAssertEqual(transcoder, sut);
}

- (void)testThatItIsDownloadingLastUpdateEventIDWhenTheDownstreamIsInProgress
{
    // given
    (void)[(ZMSingleRequestSync *)[[(id) self.downstreamSync stub] andReturnValue:OCMOCK_VALUE(ZMSingleRequestInProgress)] status];
    
    // then
    XCTAssertTrue(self.sut.isDownloadingLastUpdateEventID);
    
}

- (void)testThatItIsNotDownloadingLastUpdateEventIDWhenTheDownstreamIsIdle
{
    // given
    (void)[(ZMSingleRequestSync *)[[(id) self.downstreamSync stub] andReturnValue:OCMOCK_VALUE(ZMSingleRequestIdle)] status];
    
    // then
    XCTAssertFalse(self.sut.isDownloadingLastUpdateEventID);
}

- (void)testThatItIsNotDownloadingLastUpdateEventIDWhenTheDownstreamIsCompleted
{
    // given
    (void)[(ZMSingleRequestSync *)[[(id) self.downstreamSync stub] andReturnValue:OCMOCK_VALUE(ZMSingleRequestCompleted)] status];
    
    // then
    XCTAssertFalse(self.sut.isDownloadingLastUpdateEventID);
}

- (void)testThatItStartsTheSingleRequestWhenAskedToRequestLastUpdateEventID
{
    // given
    [(ZMSingleRequestSync *)[[(id)self.downstreamSync stub] andReturnValue:OCMOCK_VALUE(ZMSingleRequestCompleted)] status];
    
    // expect
    [[(id)self.downstreamSync expect] readyForNextRequest];
    [[(id)self.downstreamSync expect] resetCompletionState];
    [[(id)self.downstreamSync expect] nextRequest];

    // when
    self.mockSyncStatus.mockPhase = SyncPhaseFetchingLastUpdateEventID;
    XCTAssertNil([self.sut nextRequest]);
}

- (void)testThatItForwardsNextRequestToTheSingleRequestSync
{
    // given
    ZMTransportRequest *dummyRequest = [ZMTransportRequest requestGetFromPath:@"abc"];
    self.mockSyncStatus.mockPhase = SyncPhaseFetchingLastUpdateEventID;
    [(ZMSingleRequestSync *)[[(id)self.downstreamSync stub] andReturnValue:OCMOCK_VALUE(ZMSingleRequestCompleted)] status];

    // expect
    [[(id)self.downstreamSync expect] readyForNextRequest];
    [[(id)self.downstreamSync expect] resetCompletionState];
    [[[(id)self.downstreamSync expect] andReturn:dummyRequest] nextRequest];
    
    // when
    ZMTransportRequest *request = [self.sut nextRequest];
    
    // then
    XCTAssertEqual(request, dummyRequest);
}

- (void)testThatItTheLastUpdateEventIDIsPersistedAfterBeingParsed
{
    // given
    NSUUID *uuid = [NSUUID createUUID];
    [[(id) self.syncStrategy stub] storeAndProcessUpdateEvents:OCMOCK_ANY ignoreBuffer:YES];
    [[(id) self.syncStrategy stub] storeAndProcessUpdateEvents:OCMOCK_ANY ignoreBuffer:NO];
    [self injectLastUpdateEventID:uuid.transportString];
    
    // expect
    [[(id)self.directory.missingUpdateEventsTranscoder expect] setLastUpdateEventID:uuid];
    
    // when
    [self.sut persistLastUpdateEventID];
}

- (void)testThatItDoesNotPersistTheLastUpdateEventMoreThanOnceIfItIsNotInjectedAgain
{
    // given
    NSUUID *uuid = [NSUUID createUUID];
    [[(id) self.syncStrategy stub] storeAndProcessUpdateEvents:OCMOCK_ANY ignoreBuffer:YES];
    [[(id) self.syncStrategy stub] storeAndProcessUpdateEvents:OCMOCK_ANY ignoreBuffer:NO];
    [self injectLastUpdateEventID:uuid.transportString];
    
    // expect
    [[(id)self.directory.missingUpdateEventsTranscoder expect] setLastUpdateEventID:uuid];
    [[(id)self.directory.missingUpdateEventsTranscoder reject] setLastUpdateEventID:OCMOCK_ANY];
    
    // when
    [self.sut persistLastUpdateEventID];
    [self.sut persistLastUpdateEventID];
}

- (void)testThatItPersistTheLastUpdateEventMoreThanOnceIfItIsInjectedAgain
{
    // given
    NSUUID *uuid = [NSUUID createUUID];
    [[(id) self.syncStrategy stub] storeAndProcessUpdateEvents:OCMOCK_ANY ignoreBuffer:YES];
    [[(id) self.syncStrategy stub] storeAndProcessUpdateEvents:OCMOCK_ANY ignoreBuffer:NO];
    [self injectLastUpdateEventID:uuid.transportString];
    
    // expect
    [[(id)self.directory.missingUpdateEventsTranscoder expect] setLastUpdateEventID:uuid];
    [[(id)self.directory.missingUpdateEventsTranscoder expect] setLastUpdateEventID:uuid];
    
    // when
    [self.sut persistLastUpdateEventID];
    [self injectLastUpdateEventID:uuid.transportString];
    [self.sut persistLastUpdateEventID];
}

- (void)testThatItTheLastUpdateEventIDIsNotPersistedIfTheResponseWasInvalid
{
    // given
    [[(id) self.syncStrategy stub] storeAndProcessUpdateEvents:OCMOCK_ANY ignoreBuffer:YES];
    [[(id) self.syncStrategy stub] storeAndProcessUpdateEvents:OCMOCK_ANY ignoreBuffer:NO];
    [self performIgnoringZMLogError:^{
        [self injectLastUpdateEventID:@"foo"];
    }];
    
    // expect
    [[(id)self.directory.missingUpdateEventsTranscoder reject] setLastUpdateEventID:OCMOCK_ANY];
    
    // when
    [self.sut persistLastUpdateEventID];
}

- (void)testThatTheLastUpdateEventIDIsNotPersistedIfTheResponseIsAPermanentError
{
    // given
    ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:nil HTTPStatus:400 transportSessionError:nil];
    [self.sut didReceiveResponse:response forSingleRequest:self.downstreamSync];
    
    // expect
    [[(id)self.directory.missingUpdateEventsTranscoder reject] setLastUpdateEventID:OCMOCK_ANY];
    
    // when
    [self.sut persistLastUpdateEventID];
}

- (void)testThatItEncodesTheRightRequestWithoutClient
{
    // when
    ZMTransportRequest *request = [self.sut requestForSingleRequestSync:self.downstreamSync];
    
    // then
    XCTAssertNotNil(request);
    XCTAssertEqual(request.method, ZMMethodGET);
    XCTAssertEqualObjects(request.path, @"/notifications/last");
}

- (void)testThatItEncodesTheRightRequestWithClient
{
    // given
    UserClient *selfClient = [self setupSelfClientInMoc:self.uiMOC];
    XCTAssertNotNil(selfClient);
    
    // when
    ZMTransportRequest *request = [self.sut requestForSingleRequestSync:self.downstreamSync];
    
    // then
    XCTAssertNotNil(request);
    XCTAssertEqual(request.method, ZMMethodGET);
    NSString *expectedPath = [NSString stringWithFormat:@"/notifications/last?client=%@", selfClient.remoteIdentifier];
    XCTAssertEqualObjects(request.path, expectedPath);
}

@end
