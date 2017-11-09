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

class TestActivationStatusDelegate: ActivationStatusDelegate {

    var emailActivatedCalled = 0
    func emailActivated() {
        emailActivatedCalled += 1
    }

    var emailActivationFailedCalled = 0
    var emailVerificationFailedError: Error?
    func emailActivationFailed(with error: Error) {
        emailActivationFailedCalled += 1
        emailVerificationFailedError = error
    }

}

class CodeVerificationStatusTest : MessagingTest{
    var sut : WireSyncEngine.EmailActivationStatus!
    var delegate: TestActivationStatusDelegate!
    var email: String!
    var code: String!

    override func setUp() {
        super.setUp()
        
        sut = WireSyncEngine.EmailActivationStatus()
        delegate = TestActivationStatusDelegate()
        sut.delegate = delegate
        email = "some@foo.bar"
        code = "123456"
    }

    override func tearDown() {
        sut = nil
        email = nil
        super.tearDown()
    }

    func testStartWithPhaseNone(){
        XCTAssertEqual(sut.phase, .none)
    }

    func testThatItIgnoresHandleErrorWhenInNoneState() {
        // given
        let error = NSError(domain: "some", code: 2, userInfo: [:])

        // when
        sut.handleError(error)

        // then
        XCTAssertEqual(sut.phase, .none)
    }

    func testThatItIgnoresSuccessWhenInNoneState() {
        // when
        sut.success()

        // then
        XCTAssertEqual(sut.phase, .none)
    }

    func testThatItAdvancesToactivateEmailStateAfterVerificationStarts() {
        // when
        sut.activate(email: email, code: code)

        // then
        XCTAssertEqual(sut.phase, .activate(email: email, code: code))
    }

    func testThatItInformsTheDelegateAboutactivateEmailSuccess() {
        // given
        sut.activate(email: email, code: code)
        XCTAssertEqual(delegate.emailActivationFailedCalled, 0)
        XCTAssertEqual(delegate.emailActivatedCalled, 0)

        // when
        sut.success()

        //then
        XCTAssertEqual(delegate.emailActivationFailedCalled, 0)
        XCTAssertEqual(delegate.emailActivatedCalled, 1)
    }

    func testThatItInformsTheDelegateAboutactivateEmailError() {
        // given
        let error = NSError(domain: "some", code: 2, userInfo: [:])
        sut.activate(email: email, code: code)
        XCTAssertEqual(delegate.emailActivationFailedCalled, 0)
        XCTAssertEqual(delegate.emailActivatedCalled, 0)

        // when
        sut.handleError(error)

        //then
        XCTAssertEqual(delegate.emailActivatedCalled, 0)
        XCTAssertEqual(delegate.emailActivationFailedCalled, 1)
        XCTAssertEqual(delegate.emailVerificationFailedError as NSError?, error)
    }

}

