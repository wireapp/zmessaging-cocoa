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

#import "MessagingTest.h"
#import "ZMSingleRequestSync.h"



@interface ZMSingleRequestSyncTests : MessagingTest

@property (nonatomic, readonly) ZMSingleRequestSync *sut;
@property (nonatomic, readonly) id transcoder;

@end



@implementation ZMSingleRequestSyncTests

- (void)setUp {
    [super setUp];
    
    _transcoder = [OCMockObject mockForProtocol:@protocol(ZMSingleRequestTranscoder)];
    [self verifyMockLater:self.transcoder];
    
    _sut = [[ZMSingleRequestSync alloc] initWithSingleRequestTranscoder:self.transcoder managedObjectContext:self.uiMOC];
}

- (void)tearDown {

    _sut = nil;
    _transcoder = nil;
    [super tearDown];
}

- (void)sendRequestAndReplyWithResponse:(ZMTransportResponse *)response
{
    ZMTransportRequest *expectedRequest = [ZMTransportRequest requestGetFromPath:@"/baa"];
    XCTAssertEqual(self.sut.status, ZMSingleRequestIdle);
    [self.sut readyForNextRequest];
    [[[self.transcoder stub] andReturn:expectedRequest] requestForSingleRequestSync:self.sut];
    ZMTransportRequest *request = [self.sut nextRequest];
    [request completeWithResponse:response];
    WaitForAllGroupsToBeEmpty(0.5);
}

- (void)sendRequestAndReplyWithStatus:(NSInteger)status
{
    ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:nil HTTPstatus:status transportSessionError:nil];
    [self sendRequestAndReplyWithResponse:response];
}

- (void)testThatItStartsInStateIdle
{
    XCTAssertEqual(self.sut.status, ZMSingleRequestIdle);
}

- (void)testThatItExposesTheRightTranscoderAndMoc
{
    id transcoder = self.sut.transcoder;
    XCTAssertEqual(transcoder, self.transcoder);
    XCTAssertEqual(self.sut.moc, self.uiMOC);
}

- (void)testThatItReturnsInProgressWhenAskedToRequest
{
    // given
    XCTAssertEqual(self.sut.status, ZMSingleRequestIdle);
    [[[self.transcoder stub] andReturn:nil] requestForSingleRequestSync:self.sut];
    
    // when
    [self.sut readyForNextRequest];
    
    // then
    XCTAssertEqual(self.sut.status, ZMSingleRequestInProgress);
}

- (void)testThatItReturnsInProgressWhenAskedToPrepareForNextRequest
{
    // given
    XCTAssertEqual(self.sut.status, ZMSingleRequestIdle);
    [[[self.transcoder stub] andReturn:nil] requestForSingleRequestSync:self.sut];
    
    // when
    [self.sut readyForNextRequestIfNotBusy];
    
    // then
    XCTAssertEqual(self.sut.status, ZMSingleRequestInProgress);
}

- (void)testThatItReturnsNoRequestWhenIdle
{
    // given
    XCTAssertEqual(self.sut.status, ZMSingleRequestIdle);
    
    // expect
    [[self.transcoder reject] requestForSingleRequestSync:OCMOCK_ANY];
    
    // when
    ZMTransportRequest *request = [self.sut nextRequest];
    
    // then
    XCTAssertNil(request);
}


- (void)testThatItAsksRequestToTranscoderWhenStartingRequestAndTheStatusIsInProgress
{
    // given
    ZMTransportRequest *expectedRequest = [ZMTransportRequest requestGetFromPath:@"/baa"];
    [self.sut readyForNextRequest];
    
    // expect
    [[[self.transcoder expect] andReturn:expectedRequest] requestForSingleRequestSync:self.sut];
    
    // when
    ZMTransportRequest *request = [self.sut nextRequest];
    
    // then
    XCTAssertEqualObjects(expectedRequest, request);
    XCTAssertEqual(self.sut.status, ZMSingleRequestInProgress);
}

- (void)testThatItAsksRequestToTranscoderOnlyOnce
{
    // given
    ZMTransportRequest *expectedRequest = [ZMTransportRequest requestGetFromPath:@"/baa"];
    XCTAssertEqual(self.sut.status, ZMSingleRequestIdle);
    [self.sut readyForNextRequest];
    
    // expect
    [[[self.transcoder expect] andReturn:expectedRequest] requestForSingleRequestSync:self.sut];
    [[self.transcoder reject] requestForSingleRequestSync:OCMOCK_ANY];
    
    // when
    [self.sut nextRequest];
    [self.sut nextRequest];
}

- (void)testThatItSetsTheStatusToCompletedIfTheTranscoderReturnsANilRequest
{
    // given
    [self.sut readyForNextRequest];
    
    // expect
    [[[self.transcoder expect] andReturn:nil] requestForSingleRequestSync:self.sut];
    
    // when
    ZMTransportRequest *request = [self.sut nextRequest];
    
    // then
    XCTAssertNil(request);
    XCTAssertEqual(self.sut.status, ZMSingleRequestCompleted);
}

- (void)testThatItCallsDidReceiveResponseOnTranscoder
{
    
    // given
    ZMTransportResponse *response = [ZMTransportResponse responseWithPayload:@{} HTTPstatus:200 transportSessionError:nil];
    
    // expect
    [[self.transcoder expect] didReceiveResponse:response forSingleRequest:self.sut];
    
    // when
    [self sendRequestAndReplyWithResponse:response];
}

- (void)testThatItSetsTheStatusToCompletedAndReturnsNoRequestWhenTheRequestCompletesSuccessfully
{
    // expect
    [[self.transcoder expect] didReceiveResponse:OCMOCK_ANY forSingleRequest:self.sut];
    
    // given
    [self sendRequestAndReplyWithStatus:200];
    
    // then
    XCTAssertEqual(self.sut.status, ZMSingleRequestCompleted);
    XCTAssertNil([self.sut nextRequest]);
}

- (void)testThatItSetsTheStatusToCompletedAndReturnsNoRequestWhenTheRequestCompletesFailsOnPermantentError
{
    // expect
    [[self.transcoder expect] didReceiveResponse:OCMOCK_ANY forSingleRequest:self.sut];
    
    // given
    [self sendRequestAndReplyWithStatus:404];
    
    // then
    XCTAssertEqual(self.sut.status, ZMSingleRequestCompleted);
    XCTAssertNil([self.sut nextRequest]);
}

- (void)testThatItLeavesTheStatusToInProgressAndFiresAnotherRequestWhenTheRequestFailsOnNetwork
{
    // given
    [self sendRequestAndReplyWithStatus:500];
    
    // expect
    [[self.transcoder reject] didReceiveResponse:OCMOCK_ANY forSingleRequest:OCMOCK_ANY];
    
    // then
    XCTAssertEqual(self.sut.status, ZMSingleRequestInProgress);
    ZMTransportRequest *secondRequest = [self.sut nextRequest];
    XCTAssertNotNil(secondRequest);
}

- (void)testThatItLeavesTheStatusToInProgressAndFiresAnotherRequestWhenTheRequestFailsWith_TryAgainLater
{
    // given
    NSError *error = [NSError errorWithDomain:ZMTransportSessionErrorDomain code:ZMTransportSessionErrorCodeTryAgainLater userInfo:nil];
    ZMTransportResponse *response = [ZMTransportResponse responseWithTransportSessionError:error];
    [self sendRequestAndReplyWithResponse:response];
    
    // expect
    [[self.transcoder reject] didReceiveResponse:OCMOCK_ANY forSingleRequest:OCMOCK_ANY];
    
    // then
    XCTAssertEqual(self.sut.status, ZMSingleRequestInProgress);
    ZMTransportRequest *secondRequest = [self.sut nextRequest];
    XCTAssertNotNil(secondRequest);
}

- (void)testThatTheStatusIsIdleAfterCallingResetCompletionStateWhenItWasCompleted
{
    
    // expect
    [[self.transcoder stub] didReceiveResponse:OCMOCK_ANY forSingleRequest:self.sut];
    
    // given
    [self sendRequestAndReplyWithStatus:200];
    XCTAssertEqual(self.sut.status, ZMSingleRequestCompleted);

    
    // when
    [self.sut resetCompletionState];
    
    // then
    XCTAssertEqual(self.sut.status, ZMSingleRequestIdle);
}

- (void)testThatItReturnsInProgressWhenAskedToPrepareForNextRequest_WheItWasCompleted
{
    // expect
    [[self.transcoder stub] didReceiveResponse:OCMOCK_ANY forSingleRequest:self.sut];
    
    // given
    [self sendRequestAndReplyWithStatus:200];
    XCTAssertEqual(self.sut.status, ZMSingleRequestCompleted);
    
    // when
    [self.sut readyForNextRequestIfNotBusy];
    
    // then
    XCTAssertEqual(self.sut.status, ZMSingleRequestInProgress);
}


- (void)testThatResetCompletionStateDoesNotDoAnythingIfTheRequestIsInProgress
{
    // given
    [self.sut readyForNextRequest];
    XCTAssertEqual(self.sut.status, ZMSingleRequestInProgress);
    
    // when
    [self performIgnoringZMLogError:^{
        [self.sut resetCompletionState];
    }];
    
    // then
    XCTAssertEqual(self.sut.status, ZMSingleRequestInProgress);
}

- (void)testThatItCreatesAnotherRequestWhenNeedDonwloadIsCalledWhileInProgress
{
    // given
    ZMTransportRequest *request1 = [ZMTransportRequest requestGetFromPath:@"one"];
    ZMTransportRequest *request2 = [ZMTransportRequest requestGetFromPath:@"one"];
    [self.sut readyForNextRequest];
    
    // expect
    [[[self.transcoder expect] andReturn:request1] requestForSingleRequestSync:self.sut];
    [[[self.transcoder expect] andReturn:request2] requestForSingleRequestSync:self.sut];
    
    // when
    ZMTransportRequest *generatedRequest1 = [self.sut nextRequest];
    [self.sut readyForNextRequest];
    ZMTransportRequest *generatedRequest2 = [self.sut nextRequest];
    
    // then
    XCTAssertEqualObjects(request1, generatedRequest1);
    XCTAssertEqualObjects(request2, generatedRequest2);

}

- (void)testThatIfReadyForNextRequestIsCalledWhileDownloadingANewRequestIsGeneratedAndTheFirstIsIgnored
{
    // given
    ZMTransportRequest *requestThatShouldNotComplete = [ZMTransportRequest requestGetFromPath:@"req-nope"];
    ZMTransportRequest *requestThatShouldComplete = [ZMTransportRequest requestGetFromPath:@"req-yep"];
    
    ZMTransportResponse *responseThatShouldNotProcess = [ZMTransportResponse responseWithPayload:@[@"resp-nope"] HTTPstatus:200 transportSessionError:nil];
    ZMTransportResponse *responseThatShouldProcess = [ZMTransportResponse responseWithPayload:@[@"resp-yep"] HTTPstatus:200 transportSessionError:nil];
    
    [[[self.transcoder expect] andReturn:requestThatShouldNotComplete] requestForSingleRequestSync:self.sut];
    [[[self.transcoder expect] andReturn:requestThatShouldComplete] requestForSingleRequestSync:self.sut];
    
    
    // expect
    [[self.transcoder reject] didReceiveResponse:responseThatShouldNotProcess forSingleRequest:self.sut];
    [[self.transcoder expect] didReceiveResponse:responseThatShouldProcess forSingleRequest:self.sut];
    
    // given - first download
    [self.sut readyForNextRequest];
    ZMTransportRequest *request1 = [self.sut nextRequest];
    XCTAssertEqualObjects(request1, requestThatShouldNotComplete);
    
    // given - second download
    [self.sut readyForNextRequest];
    ZMTransportRequest *request2 = [self.sut nextRequest];
    XCTAssertEqualObjects(request2, requestThatShouldComplete);
    
    // when
    [request1 completeWithResponse:responseThatShouldNotProcess];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(self.sut.status, ZMSingleRequestInProgress);
    
    // when
    [request2 completeWithResponse:responseThatShouldProcess];
    WaitForAllGroupsToBeEmpty(0.5);
    
    // then
    XCTAssertEqual(self.sut.status, ZMSingleRequestCompleted);
}

@end
