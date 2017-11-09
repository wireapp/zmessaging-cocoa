//
// Wire
// Copyright (C) 2017 Wire Swiss GmbH
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

import Foundation
@testable import WireSyncEngine

class TestActivationStatus: WireSyncEngine.ActivationStatusProtocol {
    var handleErrorCalled = 0
    var handleErrorError: Error?
    func handleError(_ error: Error) {
        handleErrorCalled += 1
        handleErrorError = error
    }

    var successCalled = 0
    func success() {
        successCalled += 1
    }

    var phase: WireSyncEngine.EmailActivationStatus.Phase = .none
}

class EmailActivationStrategyTests : MessagingTest {

    var activationStatus : TestActivationStatus!
    var sut : WireSyncEngine.EmailActivationStrategy!

    let email = "john@smith.com"
    let code = "123456"

    override func setUp() {
        super.setUp()
        activationStatus = TestActivationStatus()
        sut = WireSyncEngine.EmailActivationStrategy(status : activationStatus, groupQueue: self.syncMOC)
    }

    override func tearDown() {
        sut = nil
        activationStatus = nil

        super.tearDown()
    }

    func testThatItDoesNotReturnRequestIfThePhaseIsNone(){
        let request = sut.nextRequest()
        XCTAssertNil(request);
    }

    func testThatItReturnsARequestWhenStateIsactivateEmail(){
        //given
        let path = "/activate"
        let payload = ["email": email,
                       "code": code,
                       "dryrun": true] as [String : Any]

        let transportRequest = ZMTransportRequest(path: path, method: .methodPOST, payload: payload as ZMTransportData)
        activationStatus.phase = .activate(email: email, code: code)

        //when

        let request = sut.nextRequest()

        //then
        XCTAssertNotNil(request);
        XCTAssertEqual(request, transportRequest)
    }

    func testThatItNotifiesStatusAfterSuccessfulResponseToEmailactivate() {
        // given
        activationStatus.phase = .activate(email: email, code: code)
        let response = ZMTransportResponse(payload: nil, httpStatus: 200, transportSessionError: nil)

        // when
        XCTAssertEqual(activationStatus.successCalled, 0)
        sut.didReceive(response, forSingleRequest: sut.codeActivationSync)

        // then
        XCTAssertEqual(activationStatus.successCalled, 1)
    }

    func testThatItNotifiesStatusAfterErrorToEmailactivate_InvalidCode() {
        checkResponseError(with: .invalidActivationCode, errorLabel: "invalid-code", httpStatus: 404)
    }
    func checkResponseError(with code: ZMUserSessionErrorCode, errorLabel: String, httpStatus: NSInteger, file: StaticString = #file, line: UInt = #line) {
        // given
        activationStatus.phase = .activate(email: email, code: self.code)

        let expectedError = NSError.userSessionErrorWith(code, userInfo: [:])
        let payload = [
            "label": errorLabel,
            "message":"some"
        ]
        let response = ZMTransportResponse(payload: payload as ZMTransportData, httpStatus: httpStatus, transportSessionError: nil)

        // when
        XCTAssertEqual(activationStatus.successCalled, 0, "Success should not be called", file: file, line: line)
        XCTAssertEqual(activationStatus.handleErrorCalled, 0, "HandleError should not be called", file: file, line: line)
        sut.didReceive(response, forSingleRequest: sut.codeActivationSync)

        // then
        XCTAssertEqual(activationStatus.successCalled, 0, "Success should not be called", file: file, line: line)
        XCTAssertEqual(activationStatus.handleErrorCalled, 1, "HandleError should be called", file: file, line: line)
        XCTAssertEqual(activationStatus.handleErrorError as NSError?, expectedError, "HandleError should be called with error: \(expectedError), but was \(activationStatus.handleErrorError?.localizedDescription ?? "nil")", file: file, line: line)
    }

}
