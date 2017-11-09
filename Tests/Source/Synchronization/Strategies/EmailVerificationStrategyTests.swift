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

class TestRegistrationStatus: WireSyncEngine.RegistrationStatusProtocol {
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

    var phase: WireSyncEngine.RegistrationStatus.Phase = .none
}

class EmailVerificationStrategyTests : MessagingTest {

    var registrationStatus : TestRegistrationStatus!
    var sut : WireSyncEngine.EmailVerificationStrategy!

    override func setUp() {
        super.setUp()
        registrationStatus = TestRegistrationStatus()
        sut = WireSyncEngine.EmailVerificationStrategy(status : registrationStatus, groupQueue: self.syncMOC)
    }

    override func tearDown() {
        sut = nil
        registrationStatus = nil

        super.tearDown()
    }

    func testThatItDoesNotReturnRequestIfThePhaseIsNone(){
        let request = sut.nextRequest()
        XCTAssertNil(request);
    }

    func testThatItReturnsARequestWhenStateIsVerifyEmail(){
        //given
        let email = "john@smith.com"
        let path = "/activate/send"
        let payload = ["email": email,
                       "locale": NSLocale.formattedLocaleIdentifier()!]

        let transportRequest = ZMTransportRequest(path: path, method: .methodPOST, payload: payload as ZMTransportData)
        registrationStatus.phase = .verify(email: email)

        //when

        let request = sut.nextRequest()

        //then
        XCTAssertNotNil(request);
        XCTAssertEqual(request, transportRequest)
    }

    func testThatItNotifiesStatusAfterSuccessfulResponseToEmailVerify() {
        // given
        let email = "john@smith.com"
        registrationStatus.phase = .verify(email: email)
        let response = ZMTransportResponse(payload: nil, httpStatus: 200, transportSessionError: nil)

        // when
        XCTAssertEqual(registrationStatus.successCalled, 0)
        sut.didReceive(response, forSingleRequest: sut.codeSendingSync)

        // then
        XCTAssertEqual(registrationStatus.successCalled, 1)
    }

    func testThatItNotifiesStatusAfterErrorToEmailVerify_BlacklistEmail() {
        checkResponseError(with: .blacklistedEmail, errorLabel: "blacklisted-email", httpStatus: 403)
    }

    func testThatItNotifiesStatusAfterErrorToEmailVerify_EmailExists() {
        checkResponseError(with: .emailIsAlreadyRegistered, errorLabel: "key-exists", httpStatus: 409)
    }

    func testThatItNotifiesStatusAfterErrorToEmailVerify_InvalidEmail() {
        checkResponseError(with: .invalidEmail, errorLabel: "invalid-email", httpStatus: 400)
    }

    func testThatItNotifiesStatusAfterErrorToEmailVerify_OtherError() {
        checkResponseError(with: .unknownError, errorLabel: "not-clear-what-happened", httpStatus: 414)
    }

    func checkResponseError(with code: ZMUserSessionErrorCode, errorLabel: String, httpStatus: NSInteger, file: StaticString = #file, line: UInt = #line) {
        // given
        let email = "john@smith.com"
        registrationStatus.phase = .verify(email: email)

        let expectedError = NSError.userSessionErrorWith(code, userInfo: [:])
        let payload = [
            "label": errorLabel,
            "message":"some"
        ]
        let response = ZMTransportResponse(payload: payload as ZMTransportData, httpStatus: httpStatus, transportSessionError: nil)

        // when
        XCTAssertEqual(registrationStatus.successCalled, 0, "Success should not be called", file: file, line: line)
        XCTAssertEqual(registrationStatus.handleErrorCalled, 0, "HandleError should not be called", file: file, line: line)
        sut.didReceive(response, forSingleRequest: sut.codeSendingSync)

        // then
        XCTAssertEqual(registrationStatus.successCalled, 0, "Success should not be called", file: file, line: line)
        XCTAssertEqual(registrationStatus.handleErrorCalled, 1, "HandleError should be called", file: file, line: line)
        XCTAssertEqual(registrationStatus.handleErrorError as NSError?, expectedError, "HandleError should be called with error: \(expectedError), but was \(registrationStatus.handleErrorError?.localizedDescription ?? "nil")", file: file, line: line)
    }

}
