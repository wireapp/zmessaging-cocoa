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

    var teamRegisteredCalled = 0
    func teamRegistered() {
        teamRegisteredCalled += 1
    }

    var teamRegistrationFailedCalled = 0
    var teamRegistrationFailedError: Error?
    func teamRegistrationFailed(with error: Error) {
        teamRegistrationFailedCalled += 1
        teamRegistrationFailedError = error
    }
}

class RegistrationStatusTests : MessagingTest{
    var sut : WireSyncEngine.RegistrationStatus!
    var delegate: TestRegistrationStatusDelegate!
    var email: String!
    var code: String!
    var team: TeamToRegister!

    override func setUp() {
        super.setUp()
        
        sut = WireSyncEngine.RegistrationStatus()
        delegate = TestRegistrationStatusDelegate()
        sut.delegate = delegate
        email = "some@foo.bar"
        code = "123456"
        team = WireSyncEngine.TeamToRegister(teamName: "Dream Team", email: email, fullName: "M. Jordan", password: "qwerty", accentColor: .brightOrange)
    }

    override func tearDown() {
        sut = nil
        delegate = nil
        email = nil
        code = nil
        team = nil
        super.tearDown()
    }

    // MARK: - .none state tests

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

    // MARK: - Send activation code tests

    func testThatItAdvancesToSendActivationCodeStateAfterTrigerringSendingStarts() {
        // when
        sut.sendActivationCode(to: email)

        // then
        XCTAssertEqual(sut.phase, .sendActivationCode(email: email))
    }

    func testThatItInformsTheDelegateAboutActivationCodeSendingSuccess() {
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

    func testThatItInformsTheDelegateAboutActivationCodeSendingError() {
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

    // MARK: - Check activation code tests
    func testThatItAdvancesToCheckActivationCodeStateAfterTriggeringCheck() {
        // when
        sut.checkActivationCode(email: email, code: code)

        // then
        XCTAssertEqual(sut.phase, .checkActivationCode(email: email, code: code))
    }

    func testThatItInformsTheDelegateAboutCheckActivationCodeSuccess() {
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

    func testThatItInformsTheDelegateAboutCheckActivationCodeError() {
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

    // MARK: - Team creation

    func testThatItAdvancesToCreateTeamStateAfterTriggeringCreationStarts() {
        // when
        sut.create(team: team)

        // then
        XCTAssertEqual(sut.phase, .createTeam(team: team))
    }

    func testThatItInformsTheDelegateAboutCreateTeamSuccess() {
        // given
        sut.create(team: team)
        XCTAssertEqual(delegate.teamRegisteredCalled, 0)
        XCTAssertEqual(delegate.teamRegistrationFailedCalled, 0)

        // when
        sut.success()

        //then
        XCTAssertEqual(delegate.teamRegisteredCalled, 1)
        XCTAssertEqual(delegate.teamRegistrationFailedCalled, 0)
    }

    func testThatItInformsTheDelegateAboutCreateTeamError() {
        // given
        let error = NSError(domain: "some", code: 2, userInfo: [:])
        sut.create(team: team)
        XCTAssertEqual(delegate.teamRegisteredCalled, 0)
        XCTAssertEqual(delegate.teamRegistrationFailedCalled, 0)

        // when
        sut.handleError(error)

        //then
        XCTAssertEqual(delegate.teamRegisteredCalled, 0)
        XCTAssertEqual(delegate.teamRegistrationFailedCalled, 1)
        XCTAssertEqual(delegate.teamRegistrationFailedError as NSError?, error)
    }

}

