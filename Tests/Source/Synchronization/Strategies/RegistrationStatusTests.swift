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

    override func setUp() {
        super.setUp()
        
        sut = WireSyncEngine.RegistrationStatus()
        delegate = TestRegistrationStatusDelegate()
        sut.delegate = delegate
        email = "some@foo.bar"
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

}

