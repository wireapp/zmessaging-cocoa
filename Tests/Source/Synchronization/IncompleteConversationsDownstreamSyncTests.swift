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


import XCTest
@testable import zmessaging

class IncompleteConversationsDownstreamSyncTests: MessagingTest {

    class HistorySynchronizationStatusStub : NSObject, HistorySynchronizationStatus {
        func didCompleteSync() {}
        func didStartSync() {}
        var shouldDownloadFullHistory : Bool = false
    }
    
    class RequestEncoderMock : NSObject, ConversationEventsRequestEncoder {
        
        var requestForFetchingRange_Mock : ((_ range: ZMEventIDRange, _ conversation: ZMConversation)->ZMTransportRequest)?
        
        func requestForFetchingRange(_ range: ZMEventIDRange, conversation: ZMConversation) -> ZMTransportRequest {
            return requestForFetchingRange_Mock!(range, conversation)
        }
        
    }
    
    class EventsParserMock : NSObject, DownloadedConversationEventsParser {
        
        var updateRangeInvocation_Mock : ((_ range: ZMEventIDRange, _ conversation: ZMConversation, _ response: ZMTransportResponse)->())?
        
        func updateRange(_ range: ZMEventIDRange, conversation: ZMConversation, response: ZMTransportResponse) {
            self.updateRangeInvocation_Mock!(range, conversation, response)
        }
    }
    
    class IncompleteConversationsCacheStub : ZMIncompleteConversationsCache {
    
        var incompleteNonWhitelistedConversations_Stub = NSOrderedSet()
        var incompleteWhitelistedConversations_Stub = NSOrderedSet()

        var gapForConversation_Stub : [ZMConversation : ZMEventIDRange] = [:]
        
        override var incompleteWhitelistedConversations: NSOrderedSet { return self.incompleteWhitelistedConversations_Stub
        }
        override var incompleteNonWhitelistedConversations: NSOrderedSet { return self.incompleteNonWhitelistedConversations_Stub
        }
        override func gap(for conversation: ZMConversation) -> ZMEventIDRange? {
            return gapForConversation_Stub[conversation]!
        }
    }
    
    var historySynchronizationStatusStub : HistorySynchronizationStatusStub! = nil
    var requestEncoderMock : RequestEncoderMock! = nil
    var eventsParserMock : EventsParserMock! = nil
    var conversationCache : IncompleteConversationsCacheStub! = nil

    override func setUp() {
        super.setUp()
        self.historySynchronizationStatusStub = HistorySynchronizationStatusStub()
        self.requestEncoderMock = RequestEncoderMock()
        self.eventsParserMock = EventsParserMock()
        self.conversationCache = IncompleteConversationsCacheStub(context: self.uiMOC)
    }
    
    func createSut(_ cooldownInterval : TimeInterval = 0) -> IncompleteConversationsDownstreamSync {
        return IncompleteConversationsDownstreamSync(
            requestEncoder: self.requestEncoderMock,
            responseParser: self.eventsParserMock,
            conversationsCache: self.conversationCache,
            historySynchronizationStatus: self.historySynchronizationStatusStub,
            lowPriorityRequestsCooldownInterval: cooldownInterval,
            managedObjectContext: self.uiMOC)
    }
    
    override func tearDown() {
        self.historySynchronizationStatusStub = nil
        self.requestEncoderMock = nil
        self.eventsParserMock = nil
        self.conversationCache.tearDown()
        self.conversationCache = nil
        
        super.tearDown()
    }
    
}

// MARK: - Requests

extension IncompleteConversationsDownstreamSyncTests {
    
    
    func testThatRequestIsNilIfThereIsNoConversationInTheCaches() {
        // given
        let sut = createSut()
        
        // when
        let request = sut.nextRequest()
        
        // then
        XCTAssertNil(request);
    }
    
    func testThatWhenCallingNextRequestItAsksForAConversationToTheHighPriorityIncompleteConvCache() {
    
        // given
        let conv1 = ZMConversation.insertNewObject(in: self.uiMOC)
        let conv2 = ZMConversation.insertNewObject(in: self.uiMOC)
        let range1 = ZMEventIDRange(eventIDs: [ZMEventID(major: 15, minor: 100)])!
        let range2 = ZMEventIDRange(eventIDs: [ZMEventID(major: 10, minor: 100)])!
        let dummyRequest = ZMTransportRequest(getFromPath: "Dummy")
        let sut = createSut()
        
        self.conversationCache.incompleteWhitelistedConversations_Stub = NSOrderedSet(object: conv1)
        self.conversationCache.gapForConversation_Stub = [conv1 : range1!]
        self.conversationCache.incompleteNonWhitelistedConversations_Stub = NSOrderedSet(object: conv2)
        self.conversationCache.gapForConversation_Stub = [conv1: range1, conv2 : range2]
        
        // expect
        self.requestEncoderMock.requestForFetchingRange_Mock = { (_range, _conversation) in
            XCTAssertEqual(range1, _range)
            XCTAssertEqual(conv1, _conversation)
            return dummyRequest
        }
        
        // when
        let request = sut.nextRequest()
        
        // then
        XCTAssertEqual(request, dummyRequest)
    }
    
    func testThatItDoesNotRequestsFromTheFullHistoryIncompleteConvCacheIfThereIsNoHighPriorityAndHistoryIsSynching() {
        
        // given
        self.conversationCache.incompleteWhitelistedConversations_Stub = NSOrderedSet()
        let sut = createSut()

        // when
        let request = sut.nextRequest()
    
        // then
        XCTAssertNil(request);
    }
    
    func testThatItRequestsFromTheFullHistoryIncompleteConvCacheIfThereIsNoHighPriorityAndHistoryIsNotSynching() {

        if(!IncompleteConversationsDownstreamSync.DownloadEntireHistory) {
            return
        }
        
        // given
        let conv = ZMConversation.insertNewObject(in: self.uiMOC)
        let range = ZMEventIDRange()
        let dummyRequest = ZMTransportRequest(getFromPath: "Dummy")
        self.historySynchronizationStatusStub.shouldDownloadFullHistory = true
        self.conversationCache.incompleteWhitelistedConversations_Stub = NSOrderedSet()
        self.conversationCache.incompleteNonWhitelistedConversations_Stub = NSOrderedSet(object: conv)
        self.conversationCache.gapForConversation_Stub = [conv : range]
        let sut = createSut()
    
        // expect
        self.requestEncoderMock.requestForFetchingRange_Mock = { (_range, _conversation) in
            XCTAssertEqual(range, _range)
            XCTAssertEqual(conv, _conversation)
            return dummyRequest
        }
    
        // when
        let request = sut.nextRequest()
        
        // then
        XCTAssertEqual(request, dummyRequest)
    }
    
    func testThatItDoesNotReturnARequestForTheSameConversationIfOneIsStillRunning() {
        
        // given
        let conv = ZMConversation.insertNewObject(in: self.uiMOC)
        let range = ZMEventIDRange()
        let dummyRequest = ZMTransportRequest(getFromPath: "Dummy")
        let sut = createSut()
    
        self.conversationCache.incompleteWhitelistedConversations_Stub = NSOrderedSet(object: conv)
        self.conversationCache.gapForConversation_Stub = [conv : range]
        
        // expect
        var alreadyRequested = false
        self.requestEncoderMock.requestForFetchingRange_Mock = { (_range, _conversation) in
            XCTAssertEqual(range, _range)
            XCTAssertEqual(conv, _conversation)
            XCTAssertFalse(alreadyRequested)
            alreadyRequested = true
            return dummyRequest
        }
        
        // when
        let request1 = sut.nextRequest()
        let request2 = sut.nextRequest()
        
        // then
        XCTAssertEqual(request1, dummyRequest)
        XCTAssertNil(request2)
    }

    func testThatItDoesReturnARequestForTheSameConversationIfTheLastRequestWasSuccessful() {
        
        // given
        let conv = ZMConversation.insertNewObject(in: self.uiMOC)
        let range1 = ZMEventIDRange(eventIDs: [ZMEventID(major: 15, minor: 100)])
        let range2 = ZMEventIDRange(eventIDs: [ZMEventID(major: 10, minor: 100)])
        let dummyRequest1 = ZMTransportRequest(getFromPath: "dummy1")
        let dummyRequest2 = ZMTransportRequest(getFromPath: "dummy2")
        let sut = createSut()
        self.eventsParserMock.updateRangeInvocation_Mock = {_,_,_ in }
        
        self.conversationCache.incompleteWhitelistedConversations_Stub = NSOrderedSet(object: conv)
        self.conversationCache.gapForConversation_Stub = [conv : range1!]
        
        // expect (first request)
        self.requestEncoderMock.requestForFetchingRange_Mock = { (_range, _conversation) in
            XCTAssertEqual(range1, _range)
            XCTAssertEqual(conv, _conversation)
            return dummyRequest1
        }
        
        // when
        let request1 = sut.nextRequest()
        request1?.complete(with: ZMTransportResponse(payload: [] as ZMTransportData, httpStatus: 200, transportSessionError: nil))
        
        // then
        XCTAssertTrue(self.waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        XCTAssertEqual(request1, dummyRequest1)
        
        // and expect (second request)
        self.conversationCache.gapForConversation_Stub = [conv : range2!] // modify the range so that we can test it picks the new one
        self.requestEncoderMock.requestForFetchingRange_Mock = { (_range, _conversation) in
            XCTAssertEqual(range2, _range)
            XCTAssertEqual(conv, _conversation)
            return dummyRequest2
        }
        
        // when
        let request2 = sut.nextRequest()
        
        // then
        XCTAssertEqual(request2, dummyRequest2)
    }
    
    func testThatConversationIsStillIsTheListOfBeingFetchedIfServerRespondToBackoff() {
        
        // given
        let conv = ZMConversation.insertNewObject(in: self.uiMOC)
        let range = ZMEventIDRange()
        let dummyRequest = ZMTransportRequest(getFromPath: "Dummy")
        let sut = createSut()
        
        let expectation = self.expectation(description: "requestCalled")
        
        self.conversationCache.incompleteWhitelistedConversations_Stub = NSOrderedSet(object: conv)
        self.conversationCache.gapForConversation_Stub = [conv : range]
        self.requestEncoderMock.requestForFetchingRange_Mock = { _,_ in
            return dummyRequest
        }

        self.eventsParserMock.updateRangeInvocation_Mock = {_,_,_ in
            expectation.fulfill()
        }
        
        // when
        let failedRequest = sut.nextRequest()
        failedRequest?.complete(with: ZMTransportResponse(payload: [] as ZMTransportData, httpStatus : 429, transportSessionError: nil))

        XCTAssertTrue(self.waitForCustomExpectations(withTimeout: 0.5))
        
        let request = sut.nextRequest()
        
        // then
        XCTAssertNotNil(request)
        XCTAssertEqual(request, dummyRequest)
    }

}

// MARK: - Parse result

extension IncompleteConversationsDownstreamSyncTests {
    
    func testThatItCallsTheTranscoderWithTheTransportResult() {
        
        // given
        let conv = ZMConversation.insertNewObject(in: self.uiMOC)
        let range = ZMEventIDRange()
        let dummyRequest = ZMTransportRequest(getFromPath: "Dummy")
        let response = ZMTransportResponse(payload: ["Foo"] as ZMTransportData, httpStatus: 205, transportSessionError: nil)
        let sut = createSut()
        
        self.conversationCache.incompleteWhitelistedConversations_Stub = NSOrderedSet(object: conv)
        self.conversationCache.gapForConversation_Stub = [conv : range]
        
        self.requestEncoderMock.requestForFetchingRange_Mock = { _,_ in
            return dummyRequest
        }
        
        // expect
        let expectation = self.expectation(description: "update range invoked")
        self.eventsParserMock.updateRangeInvocation_Mock = { (_range, _conversation, _response) in
            XCTAssertEqual(range, _range)
            XCTAssertEqual(conv, _conversation)
            XCTAssertEqual(response, _response)
            expectation.fulfill()
        }
        
        // when
        let request = sut.nextRequest()
        request?.complete(with: response)
        
        // then
        XCTAssertTrue(self.waitForCustomExpectations(withTimeout: 0.5))
    }

}

// MARK: - Cooldown period

extension IncompleteConversationsDownstreamSyncTests {
    
    func testThatItGeneratesMultipleRequestsForConversationsWithLowPriorityIfThereIsNoCooldown() {
        
        if(!IncompleteConversationsDownstreamSync.DownloadEntireHistory) {
            return
        }

        
        // given
        let conv1 = ZMConversation.insertNewObject(in: self.uiMOC)
        let conv2 = ZMConversation.insertNewObject(in: self.uiMOC)
        let range = ZMEventIDRange(eventIDs: [ZMEventID(major: 15, minor: 100)])!
        self.historySynchronizationStatusStub.shouldDownloadFullHistory = true
        
        let dummyRequest = ZMTransportRequest(getFromPath: "dummy")
        let sut = createSut()
        
        self.conversationCache.incompleteNonWhitelistedConversations_Stub = NSOrderedSet(array: [conv1, conv2])
        self.conversationCache.gapForConversation_Stub = [conv1 : range, conv2 : range]
        
        var receivedConversationRequests = [ZMConversation]()
        
        // expect (first request)
        self.requestEncoderMock.requestForFetchingRange_Mock = { _,conversation in
            receivedConversationRequests.append(conversation)
            return dummyRequest
        }
        
        // when
        let request1 = sut.nextRequest()
        let request2 = sut.nextRequest()

        // then
        XCTAssertEqual(request1, dummyRequest)
        XCTAssertEqual(request2, dummyRequest)
        XCTAssertEqual(receivedConversationRequests, [conv1, conv2])
    }
    
    func testThatItGeneratesOnlyOneRequestForConversationsWithLowPriorityIfThereIsACooldownPeriod() {
        
        if(!IncompleteConversationsDownstreamSync.DownloadEntireHistory) {
            return
        }
        
        // given
        let conv1 = ZMConversation.insertNewObject(in: self.uiMOC)
        let conv2 = ZMConversation.insertNewObject(in: self.uiMOC)
        let range = ZMEventIDRange(eventIDs: [ZMEventID(major: 15, minor: 100)])!
        self.historySynchronizationStatusStub.shouldDownloadFullHistory = true
        
        let dummyRequest = ZMTransportRequest(getFromPath: "dummy")
        let sut = createSut(1000)
        
        self.conversationCache.incompleteNonWhitelistedConversations_Stub = NSOrderedSet(array: [conv1, conv2])
        self.conversationCache.gapForConversation_Stub = [conv1 : range, conv2 : range]
        
        // expect (first request)
        self.requestEncoderMock.requestForFetchingRange_Mock = { _,_conversation in
            XCTAssertEqual(_conversation, conv1)
            return dummyRequest
        }
        
        // when
        let request1 = sut.nextRequest()
        let request2 = sut.nextRequest()
        
        // then
        XCTAssertEqual(request1, dummyRequest)
        XCTAssertNil(request2)
    }
    
    func testThatItGeneratesAnotherRequestForConversationsWithLowPriorityAfterACooldownPeriod() {
        
        if(!IncompleteConversationsDownstreamSync.DownloadEntireHistory) {
            return
        }
        
        // given
        let startDate = Date()
        let conv1 = ZMConversation.insertNewObject(in: self.uiMOC)
        let conv2 = ZMConversation.insertNewObject(in: self.uiMOC)
        let range = ZMEventIDRange(eventIDs: [ZMEventID(major: 15, minor: 100)])!
        self.historySynchronizationStatusStub.shouldDownloadFullHistory = true
        
        let dummyRequest = ZMTransportRequest(getFromPath: "dummy")
        let sut = createSut(0.5)
        
        self.conversationCache.incompleteNonWhitelistedConversations_Stub = NSOrderedSet(array: [conv1, conv2])
        self.conversationCache.gapForConversation_Stub = [conv1 : range, conv2 : range]
        
        // expect (first request)
        self.requestEncoderMock.requestForFetchingRange_Mock = { _,_ in
            return dummyRequest
        }
        
        // when
        let request1 = sut.nextRequest()
        let request2 = sut.nextRequest() // this is supposed to be nil because < 0.5 seconds
        
        // then
        XCTAssertEqual(request1, dummyRequest)
        XCTAssertNil(request2)
        
        // and when
        var lastRequest : ZMTransportRequest? = nil
        
        while lastRequest == nil && Date().timeIntervalSince(startDate) < 5 { // eventually this will return
            lastRequest = sut.nextRequest()
            self.spinMainQueue(withTimeout: 0.1)
        }
        
        // then
        XCTAssertNotNil(lastRequest)
    }
}
