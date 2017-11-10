//
//  RegistrationStatusTests.swift
//  WireSyncEngine-ios
//
//  Created by Bill Chan on 08.11.17.
//  Copyright © 2017 Zeta Project Gmbh. All rights reserved.
//

import Foundation
@testable import WireSyncEngine

class TestRegistrationStatusDelegate: RegistrationStatusDelegate {
    var emailActivatedCalled = 0
    func emailActivated() {
        emailActivatedCalled += 1
    }

    var emailActivationFailedCalled = 0
    var emailActivationFailedError: Error?
    func emailActivationFailed(with error: Error) {
        emailActivationFailedCalled += 1
        emailActivationFailedError = error
    }


    var codeSentCalled = 0
    func emailVerificationCodeSent() {
        codeSentCalled += 1
    }

    var emailVerificationFailedCalled = 0
    var emailVerificationFailedError: Error?
    func emailVerificationCodeSendingFailed(with error: Error) {
        emailVerificationFailedCalled += 1
        emailVerificationFailedError = error
    }

}

class RegistrationStatusTests : MessagingTest{
    var sut : WireSyncEngine.RegistrationStatus!
    var delegate: TestRegistrationStatusDelegate!
    var email: String!
    var code: String!

    override func setUp() {
        super.setUp()
        
        sut = WireSyncEngine.RegistrationStatus()
        delegate = TestRegistrationStatusDelegate()
        sut.delegate = delegate
        email = "some@foo.bar"
        code = "123456"
    }

    override func tearDown() {
        sut = nil
        email = nil
        code = nil
        super.tearDown()
    }

// MARK:- .none state tests

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

// MARK:- Verification tests

    func testThatItAdvancesToVerifyEmailStateAfterVerificationStarts() {
        // when
        sut.verify(email: email)

        // then
        XCTAssertEqual(sut.phase, .verify(email: email))
    }

    func testThatItInformsTheDelegateAboutVerifyEmailSuccess() {
        // given
        sut.verify(email: email)
        XCTAssertEqual(delegate.emailVerificationFailedCalled, 0)
        XCTAssertEqual(delegate.codeSentCalled, 0)

        // when
        sut.success()

        //then
        XCTAssertEqual(delegate.emailVerificationFailedCalled, 0)
        XCTAssertEqual(delegate.codeSentCalled, 1)
    }

    func testThatItInformsTheDelegateAboutVerifyEmailError() {
        // given
        let error = NSError(domain: "some", code: 2, userInfo: [:])
        sut.verify(email: email)
        XCTAssertEqual(delegate.emailVerificationFailedCalled, 0)
        XCTAssertEqual(delegate.codeSentCalled, 0)

        // when
        sut.handleError(error)

        //then
        XCTAssertEqual(delegate.codeSentCalled, 0)
        XCTAssertEqual(delegate.emailVerificationFailedCalled, 1)
        XCTAssertEqual(delegate.emailVerificationFailedError as NSError?, error)
    }

// MARK:- Activation tests
    func testThatItAdvancesToActivateEmailStateAfterActivationStarts() {
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
        XCTAssertEqual(delegate.emailActivationFailedError as NSError?, error)
    }


}

