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
        sut = WireSyncEngine.EmailVerificationStrategy(groupQueue: self.syncMOC, status: registrationStatus)
    }

    override func tearDown() {
        sut = nil
        registrationStatus = nil

        super.tearDown()
    }

    // MARK:- nil request tests

    func testThatItDoesNotReturnRequestIfThePhaseIsNone(){
        let request = sut.nextRequest()
        XCTAssertNil(request);
    }

    // MARK:- Send activation code tests

    func testThatItReturnsARequestWhenStateIsVerifyEmail(){
        //given
        let email = "john@smith.com"
        let path = "/activate/send"
        let payload = ["email": email,
                       "locale": NSLocale.formattedLocaleIdentifier()!]

        let transportRequest = ZMTransportRequest(path: path, method: .methodPOST, payload: payload as ZMTransportData)
        registrationStatus.phase = .sendActivationCode(email: email)

        //when

        let request = sut.nextRequest()

        //then
        XCTAssertNotNil(request);
        XCTAssertEqual(request, transportRequest)
    }

    func testThatItNotifiesStatusAfterSuccessfulResponseToEmailVerify() {
        // given
        let email = "john@smith.com"
        registrationStatus.phase = .sendActivationCode(email: email)
        let response = ZMTransportResponse(payload: nil, httpStatus: 200, transportSessionError: nil)

        // when
        XCTAssertEqual(registrationStatus.successCalled, 0)
        sut.didReceive(response, forSingleRequest: sut.codeSendingSync)

        // then
        XCTAssertEqual(registrationStatus.successCalled, 1)
    }

    // MARK:- Check activation code tests

    func testThatItReturnsARequestWhenStateIsactivateEmail(){
        //given
        let email = "john@smith.com"
        let code = "123456"
        let path = "/activate"
        let payload = ["email": email,
                       "code": code,
                       "dryrun": true] as [String : Any]

        let transportRequest = ZMTransportRequest(path: path, method: .methodPOST, payload: payload as ZMTransportData)
        registrationStatus.phase = .checkActivationCode(email: email, code: code)

        //when

        let request = sut.nextRequest()

        //then
        XCTAssertNotNil(request);
        XCTAssertEqual(request, transportRequest)
    }

    func testThatItNotifiesStatusAfterSuccessfulResponseToEmailactivate() {
        // given
        let email = "john@smith.com"
        let code = "123456"
        registrationStatus.phase = .checkActivationCode(email: email, code: code)
        let response = ZMTransportResponse(payload: nil, httpStatus: 200, transportSessionError: nil)

        // when
        XCTAssertEqual(registrationStatus.successCalled, 0)
        sut.didReceive(response, forSingleRequest: sut.codeSendingSync)

        // then
        XCTAssertEqual(registrationStatus.successCalled, 1)
    }


    // MARK:- error tests for verification

    func testThatItNotifiesStatusAfterErrorToEmailVerify_BlacklistEmail() {
        checkVerificationResponseError(with: .blacklistedEmail, errorLabel: "blacklisted-email", httpStatus: 403)
    }

    func testThatItNotifiesStatusAfterErrorToEmailVerify_EmailExists() {
        checkVerificationResponseError(with: .emailIsAlreadyRegistered, errorLabel: "key-exists", httpStatus: 409)
    }

    func testThatItNotifiesStatusAfterErrorToEmailVerify_InvalidEmail() {
        checkVerificationResponseError(with: .invalidEmail, errorLabel: "invalid-email", httpStatus: 400)
    }

    func testThatItNotifiesStatusAfterErrorToEmailVerify_OtherError() {
        checkVerificationResponseError(with: .unknownError, errorLabel: "not-clear-what-happened", httpStatus: 414)
    }

    // MARK:- error tests for activation

    func testThatItNotifiesStatusAfterErrorToEmailactivate_InvalidCode() {
        checkActivationResponseError(with: .invalidActivationCode, errorLabel: "invalid-code", httpStatus: 404)
    }

    func testThatItNotifiesStatusAfterErrorToEmailActivation_OtherError() {
        checkActivationResponseError(with: .unknownError, errorLabel: "not-clear-what-happened", httpStatus: 414)
    }

    func checkVerificationResponseError(with code: ZMUserSessionErrorCode, errorLabel: String, httpStatus: NSInteger, file: StaticString = #file, line: UInt = #line) {
        // given
        let email = "john@smith.com"
        let phase: RegistrationStatus.Phase = .sendActivationCode(email: email)

        // when & then
        checkResponseError(with: phase, code: code, errorLabel: errorLabel, httpStatus: httpStatus)
    }

    func checkActivationResponseError(with code: ZMUserSessionErrorCode, errorLabel: String, httpStatus: NSInteger, file: StaticString = #file, line: UInt = #line) {
        // given
        let email = "john@smith.com"
        let activationCode = "123456"
        let phase: RegistrationStatus.Phase = .checkActivationCode(email: email, code: activationCode)

        // when & then
        checkResponseError(with: phase, code: code, errorLabel: errorLabel, httpStatus: httpStatus)
    }

    func checkResponseError(with phase: RegistrationStatus.Phase, code: ZMUserSessionErrorCode, errorLabel: String, httpStatus: NSInteger, file: StaticString = #file, line: UInt = #line) {
        registrationStatus.phase = phase

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
