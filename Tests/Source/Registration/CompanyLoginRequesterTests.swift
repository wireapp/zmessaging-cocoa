//
// Wire
// Copyright (C) 2018 Wire Swiss GmbH
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

import XCTest
@testable import WireSyncEngine

class CompanyLoginRequesterTests: XCTestCase {

    func testThatItGeneratesLoginURLForToken() {
        // GIVEN
        let defaults = UserDefaults(suiteName: name)!
        let requester: CompanyLoginRequester = CompanyLoginRequester(
            backendHost: "localhost",
            callbackScheme: "wire",
            defaults: defaults
        )

        let userID = UUID(uuidString: "A0ACF9C2-2000-467F-B640-14BF4FCCC87A")!

        // WHEN
        var url: URL?
        let callbackExpectation = expectation(description: "Requester calls delegate to handle URL")

        let delegate = MockCompanyLoginRequesterDelegate {
            url = $0
            callbackExpectation.fulfill()
        }

        requester.delegate = delegate
        requester.requestIdentity(for: userID)
        waitForExpectations(timeout: 1, handler: nil)

        guard let validationToken = CompanyLoginVerificationToken.current(in: defaults) else { return XCTFail("no token") }
        let validationIdentifier = validationToken.uuid.transportString()
        let expectedURL = URL(string: "https://localhost/sso/initiate-login/\(userID)?success_redirect=wire://login/success?cookie=$cookie&userid=$userid&validation_token=\(validationIdentifier)&error_redirect=wire://login/failure?label=$label&validation_token=\(validationIdentifier)")!

        // THEN
        guard let validationURL = url else {
            XCTFail("The requester did not call the delegate.")
            return
        }

        guard let components = URLComponents(url: validationURL, resolvingAgainstBaseURL: false) else {
            XCTFail("The requester did not request to open a valid URL.")
            return
        }

        XCTAssertEqual(components.query(for: "success_redirect"), "wire://login/success?cookie=$cookie&userid=$userid&validation_token=\(validationIdentifier)")
        XCTAssertEqual(components.query(for: "error_redirect"), "wire://login/failure?label=$label&validation_token=\(validationIdentifier)")
        XCTAssertEqual(validationURL.absoluteString.removingPercentEncoding, expectedURL.absoluteString)
    }

}
