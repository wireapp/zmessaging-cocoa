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

class TeamCreationTests : IntegrationTest {

    var delegate: TestRegistrationStatusDelegate!
    var registrationStatus: WireSyncEngine.RegistrationStatus? {
        return sessionManager?.unauthenticatedSession?.registrationStatus
    }
    var teamToRegister: UnregisteredTeam!

    override func setUp() {
        super.setUp()
        delegate = TestRegistrationStatusDelegate()
        sessionManager?.unauthenticatedSession?.registrationStatus.delegate = delegate
        teamToRegister = UnregisteredTeam(teamName: "A-Team", email: "ba@a-team.de", emailCode: "911", fullName: "Bosco B. A. Baracus", password: "BadAttitude", accentColor: .vividRed)
    }

    override func tearDown() {
        delegate = nil
        teamToRegister = nil
        super.tearDown()
    }


    // MARK: - send activation code tests
    func testThatIsActivationCodeIsSentToSpecifiedEmail(){
        // Given
        let email = "john@smith.com"
        XCTAssertEqual(delegate.activationCodeSentCalled, 0)
        XCTAssertEqual(delegate.activationCodeSendingFailedCalled, 0)

        // When
        registrationStatus?.sendActivationCode(to: .email(email))
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))

        // Then
        XCTAssertEqual(delegate.activationCodeSentCalled, 1)
        XCTAssertEqual(delegate.activationCodeSendingFailedCalled, 0)
    }

    func testThatIsActivationCodeSendingFailWhenEmailAlreadyRegistered(){
        // Given
        let email = "john@smith.com"
        XCTAssertEqual(delegate.activationCodeSentCalled, 0)
        XCTAssertEqual(delegate.activationCodeSendingFailedCalled, 0)

        // When
        self.mockTransportSession.performRemoteChanges { (session) in
            let user = session.insertUser(withName: "john")
            user.email = email
        }

        registrationStatus?.sendActivationCode(to: .email(email))

        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))

        // Then
        XCTAssertEqual(delegate.activationCodeSentCalled, 0)
        XCTAssertEqual(delegate.activationCodeSendingFailedCalled, 1)

        let error: NSError? = (delegate.activationCodeSendingFailedError) as NSError?

        XCTAssertNotNil(error)
        XCTAssertEqual(error?.code, Int(ZMUserSessionErrorCode.emailIsAlreadyRegistered.rawValue))
    }

    // MARK: - check activation code tests
    func testThatIsActivationCodeIsVerifiedToSpecifiedEmail(){
        // Given
        let email = "john@smith.com"
        self.mockTransportSession.performRemoteChanges { (session) in
            session.whiteListEmail(email)
        }
        let code = self.mockTransportSession.emailActivationCode
        XCTAssertEqual(delegate.activationCodeValidatedCalled, 0)
        XCTAssertEqual(delegate.activationCodeValidationFailedCalled, 0)

        // When
        registrationStatus?.checkActivationCode(credential: .email(email), code: code)
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))

        // Then
        XCTAssertEqual(delegate.activationCodeValidatedCalled, 1)
        XCTAssertEqual(delegate.activationCodeValidationFailedCalled, 0)
    }

    // MARK: - create team tests

    func testThatWeCanRegisterAndLogInIfWeHaveAValidCode() {
        // given
        XCTAssertEqual(delegate.teamRegisteredCalled, 0)
        XCTAssertEqual(delegate.teamRegistrationFailedCalled, 0)

        // When
        registrationStatus?.create(team: teamToRegister)
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))

        // Then
        XCTAssertEqual(delegate.teamRegisteredCalled, 1)
        XCTAssertEqual(delegate.teamRegistrationFailedCalled, 0)
    }

    func testThatAfterRegisteringWeHaveAnAccountAndValidCookie() {
        // When
        registrationStatus?.create(team: teamToRegister)
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))

        // Then
        let selected = sessionManager?.accountManager.selectedAccount
        XCTAssertNotNil(selected)
        XCTAssertEqual(selected?.cookieStorage().isAuthenticated, true)
    }

    func testThatItSignalsAnErrorIfTeamCreationFails() {
        // Given
        self.mockTransportSession.performRemoteChanges { (session) in
            let user = session.insertUser(withName: "john")
            user.email = self.teamToRegister.email
        }

        registrationStatus?.create(team: teamToRegister)
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))

        // Then
        XCTAssertEqual(delegate.teamRegisteredCalled, 0)
        XCTAssertEqual(delegate.teamRegistrationFailedCalled, 1)
        let error = (delegate.teamRegistrationFailedError) as NSError?
        XCTAssertNotNil(error)
        XCTAssertEqual(error?.code, Int(ZMUserSessionErrorCode.emailIsAlreadyRegistered.rawValue))
    }
}
