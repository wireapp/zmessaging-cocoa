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
@import zmessaging;
@import ZMCDataModel;

#import "MessagingTest.h"
#import "ZMRemovedSuggestedPeopleTranscoder.h"
#import "ZMSuggestionSearch.h"



@interface ZMRemovedSuggestedPeopleTranscoderTests : MessagingTest

@property (nonatomic) ZMRemovedSuggestedPeopleTranscoder *sut;
@property (nonatomic) NSUUID *remoteIdentifierA;
@property (nonatomic) NSUUID *remoteIdentifierB;

@end



@implementation ZMRemovedSuggestedPeopleTranscoderTests

- (void)setUp
{
    [super setUp];
    
    self.sut = [[ZMRemovedSuggestedPeopleTranscoder alloc] initWithManagedObjectContext:self.syncMOC];
    self.remoteIdentifierA = NSUUID.createUUID;
    self.remoteIdentifierB = NSUUID.createUUID;
}

- (void)tearDown
{
    [self.sut tearDown];
    self.sut = nil;
    self.remoteIdentifierA = nil;
    self.remoteIdentifierB = nil;
    
    [super tearDown];
}

- (void)testThatItDoesNotGenerateARequestWhenThereAreNotRemovedIDs;
{
    // when
    ZMTransportRequest *request = [self.sut.requestGenerators nextRequest];
    
    // then
    XCTAssertNil(request);
}

- (void)testThatItGeneratesRequestsForRemovedIDs;
{
    [self.syncMOC performGroupedBlockAndWait:^{
        // expect
        [self expectationForNotification:@"ZMOperationLoopNewRequestAvailable" object:self.sut handler:nil];
        
        // when
        self.syncMOC.removedSuggestedContactRemoteIdentifiers = @[self.remoteIdentifierA, self.remoteIdentifierB];
    }];
    XCTAssert([self waitForCustomExpectationsWithTimeout:0.5]);
    [self.syncMOC performGroupedBlockAndWait:^{
        
        ZMTransportRequest *request1 = [self.sut.requestGenerators nextRequest];
        ZMTransportRequest *request2 = [self.sut.requestGenerators nextRequest];
        ZMTransportRequest *request3 = [self.sut.requestGenerators nextRequest];
        
        // then
        XCTAssertNotNil(request1);
        XCTAssertEqual(request1.method, ZMMethodPUT);
        XCTAssertNil(request1.payload);
        
        XCTAssertNotNil(request2);
        XCTAssertEqual(request2.method, ZMMethodPUT);
        XCTAssertNil(request2.payload);
        
        NSArray *expectedPaths = @[[NSString stringWithFormat:@"/search/suggestions/%@/ignore", self.remoteIdentifierA.transportString],
                                   [NSString stringWithFormat:@"/search/suggestions/%@/ignore", self.remoteIdentifierB.transportString]];
        XCTAssertTrue([expectedPaths containsObject:request1.path]);
        XCTAssertTrue([expectedPaths containsObject:request2.path]);
        XCTAssertNotEqualObjects(request1.path, request2.path);
        
        XCTAssertNil(request3);
    }];
}

- (void)testThatItRemovesIdentifiersOnceTheyHaveBeenSentToTheBackend_1;
{
    // given
    ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:nil HTTPStatus:200 transportSessionError:nil];
    [self.syncMOC performGroupedBlockAndWait:^{
        // expect
        [self expectationForNotification:@"ZMOperationLoopNewRequestAvailable" object:self.sut handler:nil];
        
        // when
        self.syncMOC.removedSuggestedContactRemoteIdentifiers = @[self.remoteIdentifierA, self.remoteIdentifierB];
    }];
    XCTAssert([self waitForCustomExpectationsWithTimeout:0.5]);
    [self.syncMOC performGroupedBlockAndWait:^{
        
        ZMTransportRequest *request = [self.sut.requestGenerators nextRequest];
        [request completeWithResponse:response];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    [self.syncMOC performGroupedBlockAndWait:^{
        // then
        XCTAssertEqual(self.syncMOC.removedSuggestedContactRemoteIdentifiers.count, 1u);
    }];
}

- (void)testThatItRemovesIdentifiersOnceTheyHaveBeenSentToTheBackend_2;
{
    // given
    ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:nil HTTPStatus:200 transportSessionError:nil];
    [self.syncMOC performGroupedBlockAndWait:^{
        // expect
        [self expectationForNotification:@"ZMOperationLoopNewRequestAvailable" object:self.sut handler:nil];
        
        // when
        self.syncMOC.removedSuggestedContactRemoteIdentifiers = @[self.remoteIdentifierA, self.remoteIdentifierB];
    }];
    XCTAssert([self waitForCustomExpectationsWithTimeout:0.5]);
    [self.syncMOC performGroupedBlockAndWait:^{
        
        ZMTransportRequest *request1 = [self.sut.requestGenerators nextRequest];
        ZMTransportRequest *request2 = [self.sut.requestGenerators nextRequest];
        [request1 completeWithResponse:response];
        [request2 completeWithResponse:response];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    [self.syncMOC performGroupedBlockAndWait:^{
        
        // then
        XCTAssertEqual(self.syncMOC.removedSuggestedContactRemoteIdentifiers.count, 0u);
    }];
}

- (void)testThatItDoesNotRemoveAnIdentifierWhenTheResponseIs_TryAgain;
{
    // given
    ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:nil HTTPStatus:0 transportSessionError:[NSError tryAgainLaterError]];
    [self.syncMOC performGroupedBlockAndWait:^{
        // when
        self.syncMOC.removedSuggestedContactRemoteIdentifiers = @[self.remoteIdentifierA, self.remoteIdentifierB];
    }];
    XCTAssert([self waitForCustomExpectationsWithTimeout:0.5]);
    [self.syncMOC performGroupedBlockAndWait:^{
        
        ZMTransportRequest *request = [self.sut.requestGenerators nextRequest];
        [request completeWithResponse:response];
    }];
    WaitForAllGroupsToBeEmpty(0.5);
    [self.syncMOC performGroupedBlockAndWait:^{
        
        // then
        XCTAssertEqual(self.syncMOC.removedSuggestedContactRemoteIdentifiers.count, 2u);
    }];
}

@end
