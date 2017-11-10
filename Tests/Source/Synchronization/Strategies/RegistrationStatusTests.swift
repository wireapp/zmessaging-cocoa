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

    var emailActivationCodeSentCalled = 0
    func emailActivationCodeSent() {
        emailActivationCodeSentCalled += 1
    }

    var emailActivationCodeSendingFailedCalled = 0
    var emailActivationCodeSendingFailedError: Error?
    func emailActivationCodeSendingFailed(with error: Error) {
        emailActivationCodeSendingFailedCalled += 1
        emailActivationCodeSendingFailedError = error
    }


    var emailActivationCodeValidatedCalled = 0
    func emailActivationCodeValidated() {
        emailActivationCodeValidatedCalled += 1
    }

    var emailActivationCodeValidationFailedCalled = 0
    var emailActivationCodeValidationFailedError: Error?
    func emailActivationCodeValidationFailed(with error: Error) {
        emailActivationCodeValidationFailedCalled += 1
        emailActivationCodeValidationFailedError = error
    }

}

class RegistrationStatusTests : MessagingTest{
    var sut : WireSyncEngine.RegistrationStatus!
    var delegate: TestRegistrationStatusDelegate!
    var email: String!
    var code: String!

    override func setUp() {
        super.setUp()
        
        sut = WireSyncEngine.RegistrationStatus(groupQueue: self.syncMOC)
        delegate = TestRegistrationStatusDelegate()
        sut.delegate = delegate
        email = "some@foo.bar"
        code = "123456"
    }

    override func tearDown() {
        sut = nil
        email = nil
        code = nil
        delegate = nil
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

// MARK:- Send activation code tests

    func testThatItAdvancesToVerifyEmailStateAfterVerificationStarts() {
        // when
        sut.sendActivationCode(to: email)

        // then
        XCTAssertEqual(sut.phase, .sendActivationCode(email: email))
    }

    func testThatItInformsTheDelegateAboutVerifyEmailSuccess() {
        // given
        sut.sendActivationCode(to: email)
        XCTAssertEqual(delegate.emailActivationCodeSentCalled, 0)
        XCTAssertEqual(delegate.emailActivationCodeSendingFailedCalled, 0)

        // when
        sut.success()

        //then
        XCTAssertEqual(delegate.emailActivationCodeSentCalled, 1)
        XCTAssertEqual(delegate.emailActivationCodeSendingFailedCalled, 0)
    }

    func testThatItInformsTheDelegateAboutVerifyEmailError() {
        // given
        let error = NSError(domain: "some", code: 2, userInfo: [:])
        sut.sendActivationCode(to: email)
        XCTAssertEqual(delegate.emailActivationCodeSentCalled, 0)
        XCTAssertEqual(delegate.emailActivationCodeSendingFailedCalled, 0)

        // when
        sut.handleError(error)

        //then
        XCTAssertEqual(delegate.emailActivationCodeSentCalled, 0)
        XCTAssertEqual(delegate.emailActivationCodeSendingFailedCalled, 1)
        XCTAssertEqual(delegate.emailActivationCodeSendingFailedError as NSError?, error)
    }

// MARK:- Check activation code tests
    func testThatItAdvancesToActivateEmailStateAfterActivationStarts() {
        // when
        sut.checkActivationCode(email: email, code: code)

        // then
        XCTAssertEqual(sut.phase, .checkActivationCode(email: email, code: code))
    }

    func testThatItInformsTheDelegateAboutactivateEmailSuccess() {
        // given
        sut.checkActivationCode(email: email, code: code)
        XCTAssertEqual(delegate.emailActivationCodeValidatedCalled, 0)
        XCTAssertEqual(delegate.emailActivationCodeValidationFailedCalled, 0)

        // when
        sut.success()

        //then
        XCTAssertEqual(delegate.emailActivationCodeValidatedCalled, 1)
        XCTAssertEqual(delegate.emailActivationCodeValidationFailedCalled, 0)
    }

    func testThatItInformsTheDelegateAboutactivateEmailError() {
        // given
        let error = NSError(domain: "some", code: 2, userInfo: [:])
        sut.checkActivationCode(email: email, code: code)
        XCTAssertEqual(delegate.emailActivationCodeValidatedCalled, 0)
        XCTAssertEqual(delegate.emailActivationCodeValidationFailedCalled, 0)

        // when
        sut.handleError(error)

        //then
        XCTAssertEqual(delegate.emailActivationCodeValidatedCalled, 0)
        XCTAssertEqual(delegate.emailActivationCodeValidationFailedCalled, 1)
        XCTAssertEqual(delegate.emailActivationCodeValidationFailedError as NSError?, error)
    }


}

