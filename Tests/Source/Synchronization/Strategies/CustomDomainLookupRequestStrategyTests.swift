//
// Wire
// Copyright (C) 2020 Wire Swiss GmbH
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
@testable import WireSyncEngine

class CustomDomainLookupRequestStrategyTests: MessagingTest {
    var sut: CustomDomainLookupRequestStrategy!
    var mockApplicationStatus: MockApplicationStatus!
    var domainLookupResult: DomainLookupResult?
    var didCallNewRequestAvailable: Bool!
    var sync: ZMSingleRequestSync!
    
    override func setUp() {
        super.setUp()
        domainLookupResult = nil
        sync = ZMSingleRequestSync()
        mockApplicationStatus = MockApplicationStatus()
        sut = CustomDomainLookupRequestStrategy(withManagedObjectContext: syncMOC, applicationStatus: mockApplicationStatus)
        RequestAvailableNotification.addObserver(self)
        didCallNewRequestAvailable = false
    }
    
    override func tearDown() {
        NotificationCenter.default.removeObserver(self)
        sut = nil
        mockApplicationStatus = nil
        domainLookupResult = nil
        sync = nil
        super.tearDown()
    }
    
    func testThatItGeneratesCorrectRequestIfDomainIsSet() {
        //given
        let domain = "example.com"
        CustomDomainLookupRequestStrategy.triggerDomainLookup(domain: domain, completion: {_ in}, context: syncMOC)
        
        //when
        let request = sut.nextRequestIfAllowed()
        
        //then
        XCTAssertNotNil(request)
        XCTAssertEqual(request?.path, "/custom-instance/by-domain/example.com")
        XCTAssertEqual(request?.method, ZMTransportRequestMethod.methodGET)
    }
    
    func testThatItURLEncodeRequest() {
        //given
        let domain = "example com"
        CustomDomainLookupRequestStrategy.triggerDomainLookup(domain: domain, completion: {_ in}, context: syncMOC)
        
        //when
        let request = sut.nextRequestIfAllowed()
        
        //then
        XCTAssertNotNil(request)
        XCTAssertEqual(request?.path, "/custom-instance/by-domain/example%20com")
        XCTAssertEqual(request?.method, ZMTransportRequestMethod.methodGET)
    }
    
    func testThatItOnlyGeneratesRequestWhenNeeded() {
        //given
        var request: ZMTransportRequest?
        //when
        request = sut.nextRequestIfAllowed()
        //then
        XCTAssertNil(request)
        
        //given
        CustomDomainLookupRequestStrategy.triggerDomainLookup(domain: "example.com", completion: {_ in}, context: syncMOC)
        //when
        request = sut.nextRequestIfAllowed()
        //then
        XCTAssertNotNil(request)
        
        //given
        let response = ZMTransportResponse(payload: nil, httpStatus: 200, transportSessionError: nil)
        sut.didReceive(response, forSingleRequest: sync)
        //when
        request = sut.nextRequestIfAllowed()
        //then
        XCTAssertNil(request)
    }
    
    func testThat404ResponseWithNoMatchingLabelIsError() {
        testThat(statusCode: 404,
                 isProcessedAs: .error(httpCode: 404, label: nil),
                 payload: ["label": "foobar"] as ZMTransportData)
    }
    
    func testThat500ResponseIsError() {
        testThat(statusCode: 500, isProcessedAs: .error(httpCode: 500, label: nil))
    }
    
    func testThat200ResponseIsProcessedAsValid() {
        
        // GIVEN
        let url = URL(string: "https://wire.com/config.json")!
        let payload = ["foo": "bar", "config_json": url.absoluteString]
        
        // WHEN/THEN
        testThat(statusCode: 200,
                 isProcessedAs: .found(CustomDomainInformation(configJson: url)),
                 payload: payload as ZMTransportData)
    }
    
    func testThat200ResponseWithBadPayloadGeneratesParseError() {
        testThat(statusCode: 200,
                 isProcessedAs: .parsingError,
                 payload: nil)
    }
    
    func testThat200ResponseIsProcessedAsValid2() {
        testThat(statusCode: 200,
                 isProcessedAs: .parsingError,
                 payload: ["config_json": "22"] as ZMTransportData)
    }
    
    func testThatNotificationObserverReactsWhenObjectMatch() {
        //when
        CustomDomainLookupRequestStrategy.triggerDomainLookup(domain: "", completion: {_ in}, context: syncMOC)
        //then
        XCTAssertTrue(didCallNewRequestAvailable)
    }
    
    func testThatNotificationObserverReactsWhenObjectDoesNotMatch() {
        //when
        CustomDomainLookupRequestStrategy.triggerDomainLookup(domain: "", completion: {_ in}, context: uiMOC)
        //then
        XCTAssertFalse(didCallNewRequestAvailable)
    }
}

extension CustomDomainLookupRequestStrategyTests {
    func testThat(statusCode: Int,
                  isProcessedAs result: DomainLookupResult,
                  payload: ZMTransportData? = nil,
                  line: UInt = #line, file : StaticString = #file
                  ) {
        //given
        var domainLookupResult: DomainLookupResult?
        CustomDomainLookupRequestStrategy.triggerDomainLookup(
            domain: "example.com",
            completion: { domainLookupResult = $0 },
            context: syncMOC)
        let response = ZMTransportResponse(payload: payload, httpStatus: statusCode, transportSessionError: nil)
        //when
        sut.didReceive(response, forSingleRequest: sync)
        //then
        XCTAssertNotNil(domainLookupResult, file: file, line: line)
        XCTAssertEqual(domainLookupResult, result, file: file, line: line)
    }
}

extension CustomDomainLookupRequestStrategyTests: RequestAvailableObserver {
    func newRequestsAvailable() {
        didCallNewRequestAvailable = true
    }
}
