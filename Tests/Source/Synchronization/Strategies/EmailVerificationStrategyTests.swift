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

}
