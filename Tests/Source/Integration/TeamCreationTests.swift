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

    override func setUp() {
        super.setUp()
        delegate = TestRegistrationStatusDelegate()
        sessionManager?.unauthenticatedSession?.registrationStatus.delegate = delegate
    }

    override func tearDown() {
        delegate = nil
        super.tearDown()
    }

    func testThatIsActivationCodeIsSentToSpecifiedEmail(){
        // Given
        let email = "john@smith.com"
        XCTAssertEqual(delegate.emailActivationCodeSentCalled, 0)
        XCTAssertEqual(delegate.emailActivationCodeSendingFailedCalled, 0)

        // When
        sessionManager?.unauthenticatedSession?.registrationStatus.sendActivationCode(to: email)
        XCTAssertTrue(waitForAllGroupsToBeEmpty(withTimeout: 0.5))

        // Then
        XCTAssertEqual(delegate.emailActivationCodeSentCalled, 1)
        XCTAssertEqual(delegate.emailActivationCodeSendingFailedCalled, 0)
    }
}
