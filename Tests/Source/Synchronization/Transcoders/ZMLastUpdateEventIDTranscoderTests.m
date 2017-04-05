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

#import "MessagingTest.h"
#import "ZMLastUpdateEventIDTranscoder+Internal.h"
#import "ZMSyncStrategy.h"
#import "ZMObjectStrategyDirectory.h"
#import "ZMMissingUpdateEventsTranscoder+Internal.h"
#import <WireSyncEngine/WireSyncEngine-Swift.h>

@interface ZMLastUpdateEventIDTranscoderTests : MessagingTest

@property (nonatomic) ZMLastUpdateEventIDTranscoder *sut;
@property (nonatomic) id<ZMObjectStrategyDirectory> directory;
@property (nonatomic) ZMSingleRequestSync *downstreamSync;
@property (nonatomic) ZMSyncStrategy *syncStrategy;
@end

@implementation ZMLastUpdateEventIDTranscoderTests

- (void)setUp {
    [super setUp];
    
    self.downstreamSync = [OCMockObject mockForClass:ZMSingleRequestSync.class];
    [self verifyMockLater:self.downstreamSync];
    
    self.directory = [self createMockObjectStrategyDirectoryInMoc:self.uiMOC];
    self.syncStrategy = [OCMockObject mockForClass:ZMSyncStrategy.class];
    self.sut = [[ZMLastUpdateEventIDTranscoder alloc] initWithManagedObjectContext:self.uiMOC objectDirectory:self.directory];
    self.sut.lastUpdateEventIDSync = self.downstreamSync;
    
    [self verifyMockLater:self.syncStrategy];
}

- (void)tearDown {

    self.directory = nil;
    self.syncStrategy = nil;
    [self.sut tearDown];
    self.sut = nil;
    self.downstreamSync = nil;
    [super tearDown];
}

- (void)injectLastUpdateEventID:(NSString *)updateEventID
{
    NSDictionary *payload =
    @{
      @"id" : updateEventID,
      @"payload" :
          @[
              @{
                  @"conversation" : @"34d6f5d2-56aa-4f2b-99b7-b130efdf724c",
                  @"participants" : @{
                          @"1f7481fc-61ca-45f5-8dfb-5a27627a3539" :
                              @{
                                  @"state" : @"joined"
                                  },
                          },
                  @"self" : [NSNull null],
                  @"type" : @"call.state"
                  }
              ],
      @"time" : @"1437654971",
      };
    ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:payload HTTPStatus:200 transportSessionError:nil];
    [self.sut didReceiveResponse:response forSingleRequest:nil];
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
    ZMLastUpdateEventIDTranscoder *sut = [[ZMLastUpdateEventIDTranscoder alloc] initWithManagedObjectContext:self.uiMOC objectDirectory:self.directory];
    id transcoder = sut.lastUpdateEventIDSync.transcoder;
    
    // then
    XCTAssertNotNil(sut.lastUpdateEventIDSync);
    XCTAssertEqual(sut.lastUpdateEventIDSync.moc, self.uiMOC);
    XCTAssertEqual(transcoder, sut);
    [sut tearDown];
    
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
    // expect
    [[(id)self.downstreamSync expect] readyForNextRequest];
    [[(id)self.downstreamSync expect] resetCompletionState];
    
    // when
    [self.sut startRequestingLastUpdateEventIDWithoutPersistingIt];
}

- (void)testThatItForwardsNextRequestToTheSingleRequestSync
{
    // given
    ZMTransportRequest *dummyRequest = [ZMTransportRequest requestGetFromPath:@"abc"];
    
    // expect
    [[[(id)self.downstreamSync expect] andReturn:dummyRequest] nextRequest];
    
    // when
    ZMTransportRequest *request = [self.sut.requestGenerators nextRequest];
    
    // then
    XCTAssertEqual(request, dummyRequest);
}

- (void)testThatItTheLastUpdateEventIDIsPersistedAfterBeingParsed
{
    // given
    NSUUID *uuid = [NSUUID createUUID];
    [[(id) self.syncStrategy stub] processUpdateEvents:OCMOCK_ANY ignoreBuffer:YES];
    [[(id) self.syncStrategy stub] processUpdateEvents:OCMOCK_ANY ignoreBuffer:NO];
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
    [[(id) self.syncStrategy stub] processUpdateEvents:OCMOCK_ANY ignoreBuffer:YES];
    [[(id) self.syncStrategy stub] processUpdateEvents:OCMOCK_ANY ignoreBuffer:NO];
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
    [[(id) self.syncStrategy stub] processUpdateEvents:OCMOCK_ANY ignoreBuffer:YES];
    [[(id) self.syncStrategy stub] processUpdateEvents:OCMOCK_ANY ignoreBuffer:NO];
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
    [[(id) self.syncStrategy stub] processUpdateEvents:OCMOCK_ANY ignoreBuffer:YES];
    [[(id) self.syncStrategy stub] processUpdateEvents:OCMOCK_ANY ignoreBuffer:NO];
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
    [self.sut didReceiveResponse:response forSingleRequest:nil];
    
    // expect
    [[(id)self.directory.missingUpdateEventsTranscoder reject] setLastUpdateEventID:OCMOCK_ANY];
    
    // when
    [self.sut persistLastUpdateEventID];
}

- (void)testThatItEncodesTheRightRequestWithoutClient
{
    // when
    ZMTransportRequest *request = [self.sut requestForSingleRequestSync:nil];
    
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
    ZMTransportRequest *request = [self.sut requestForSingleRequestSync:nil];
    
    // then
    XCTAssertNotNil(request);
    XCTAssertEqual(request.method, ZMMethodGET);
    NSString *expectedPath = [NSString stringWithFormat:@"/notifications/last?client=%@", selfClient.remoteIdentifier];
    XCTAssertEqualObjects(request.path, expectedPath);
}

@end
