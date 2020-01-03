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

class VerifyPasswordRequestStrategyTests: MessagingTest {
    var sut: VerifyPasswordRequestStrategy!
    var mockApplicationStatus: MockApplicationStatus!
    var verifyPasswordResult: VerifyPasswordResult?
    var didCallNewRequestAvailable: Bool!
    var sync: ZMSingleRequestSync!
    
    override func setUp() {
        super.setUp()
        verifyPasswordResult = nil
        sync = ZMSingleRequestSync()
        mockApplicationStatus = MockApplicationStatus()
        sut = VerifyPasswordRequestStrategy(withManagedObjectContext: syncMOC, applicationStatus: mockApplicationStatus)
        RequestAvailableNotification.addObserver(self)
        didCallNewRequestAvailable = false
    }
    
    override func tearDown() {
        NotificationCenter.default.removeObserver(self)
        sut = nil
        mockApplicationStatus = nil
        verifyPasswordResult = nil
        sync = nil
        super.tearDown()
    }
    
    func testThatItGeneratesCorrectRequestIfPasswordIsSet() {
        //given
        let password = "password"
        VerifyPasswordRequestStrategy.triggerPasswordVerification(with: password, completion: {_ in}, context: syncMOC)
        
        //when
        let request = sut.nextRequestIfAllowed()
        
        //then
        XCTAssertNotNil(request)
        let payload = request?.payload?.asDictionary()
        XCTAssertEqual(payload?["new_password"] as? String, password)
        XCTAssertEqual(payload?["old_password"] as? String, password)
        XCTAssertEqual(request?.path, "/self/password")
        XCTAssertEqual(request?.method, ZMTransportRequestMethod.methodPUT)
    }
    
    func testThatItOnlyGeneratesRequestWhenNeeded() {
        //given
        var request: ZMTransportRequest?
        //when
        request = sut.nextRequestIfAllowed()
        //then
        XCTAssertNil(request)

        //given
        VerifyPasswordRequestStrategy.triggerPasswordVerification(with: "password", completion: {_ in}, context: syncMOC)
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
    
    func testThat403ResponseIsProcessedAsDenied() {
        testThat(statusCode: 403, isProcessedAs: .denied)
    }
    
    func testThat408ResponseIsProcessedAsTimeout() {
        testThat(statusCode: 408, isProcessedAs: .timeout)
    }
    
    func testThat409ResponseIsProcessedAsValidated() {
        testThat(statusCode: 409, isProcessedAs: .validated)
    }
    
    func testThatBogusStatusCodeIsProcessedAsUnknown() {
        testThat(statusCode: 999, isProcessedAs: .unknown)
    }
    
    func testThatNotificationObserverReactsWhenObjectMatch() {
        //when
        VerifyPasswordRequestStrategy.triggerPasswordVerification(with: "", completion: {_ in}, context: syncMOC)
        //then
        XCTAssertTrue(didCallNewRequestAvailable)
    }
    
    func testThatNotificationObserverDoesntReactWhenObjectDontMatch() {
        //given
        let moc = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        moc.persistentStoreCoordinator = NSPersistentStoreCoordinator()
        
        //when
        VerifyPasswordRequestStrategy.triggerPasswordVerification(with: "", completion: {_ in}, context: moc)
        //then
        XCTAssertFalse(didCallNewRequestAvailable)
    }
}

extension VerifyPasswordRequestStrategyTests {
    func testThat(statusCode: Int, isProcessedAs result: VerifyPasswordResult) {
        //given
        var verifyPasswordResult: VerifyPasswordResult?
        VerifyPasswordRequestStrategy.triggerPasswordVerification(
            with: "password",
            completion: { verifyPasswordResult = $0 },
            context: syncMOC)
        let response = ZMTransportResponse(payload: nil, httpStatus: statusCode, transportSessionError: nil)
        //when
        sut.didReceive(response, forSingleRequest: sync)
        //then
        XCTAssertNotNil(verifyPasswordResult)
        XCTAssertEqual(verifyPasswordResult, result)
    }
}

extension VerifyPasswordRequestStrategyTests: RequestAvailableObserver {
    func newRequestsAvailable() {
        didCallNewRequestAvailable = true
    }
}
