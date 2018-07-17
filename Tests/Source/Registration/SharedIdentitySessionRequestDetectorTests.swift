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

class SharedIdentitySessionRequestDetectorTests: XCTestCase {

    var pasteboard: MockPasteboard!
    var detector: SharedIdentitySessionRequestDetector!

    override func setUp() {
        super.setUp()
        pasteboard = MockPasteboard()
        detector = SharedIdentitySessionRequestDetector(pasteboard: pasteboard)
    }

    override func tearDown() {
        detector = nil
        pasteboard = nil
        super.tearDown()
    }

    func testThatItDetectsValidWireCode_Uppercase() {
        // GIVEN
        pasteboard.text = "wire-46A17D7F-2351-495E-AEDA-E7C96AC74994"

        // WHEN
        var detectedCode: UUID?
        let detectionExpectation = expectation(description: "Detector returns a result")

        detector.detectCopiedRequestCode {
            detectedCode = $0
            detectionExpectation.fulfill()
        }

        waitForExpectations(timeout: 1, handler: nil)

        // THEN
        XCTAssertEqual(detectedCode?.uuidString, "46A17D7F-2351-495E-AEDA-E7C96AC74994")
    }

    func testThatItDetectsValidWireCode_Lowercase() {
        // GIVEN
        pasteboard.text = "wire-70488875-13dd-4ba7-9636-a983e1831f5f"

        // WHEN
        var detectedCode: UUID?
        let detectionExpectation = expectation(description: "Detector returns a result")

        detector.detectCopiedRequestCode {
            detectedCode = $0
            detectionExpectation.fulfill()
        }

        waitForExpectations(timeout: 1, handler: nil)

        // THEN
        XCTAssertEqual(detectedCode?.uuidString, "70488875-13DD-4BA7-9636-A983E1831F5F")
    }

    func testThatItDetectsValidCode_UserInput() {
        // GIVEN
        let text = "wire-81DD91BA-B3D0-46F0-BC29-E491938F0A54"

        // WHEN
        let detectedCode = detector.detectRequestCode(in: text)

        // THEN
        XCTAssertEqual(detectedCode?.uuidString, "81DD91BA-B3D0-46F0-BC29-E491938F0A54")
    }

    func testThatItDetectsInvalidCode_MissingPrefix() {
        // GIVEN
        pasteboard.text = "8FBF187C-2039-409B-B16F-5FCF485514E1"

        // WHEN
        var detectedCode: UUID?
        let detectionExpectation = expectation(description: "Detector returns a result")

        detector.detectCopiedRequestCode {
            detectedCode = $0
            detectionExpectation.fulfill()
        }

        waitForExpectations(timeout: 1, handler: nil)

        // THEN
        XCTAssertNil(detectedCode)
    }

    func testThatItDetectsInvalidCode_WrongUUIDFormat() {
        // GIVEN
        pasteboard.text = "wire-D82916EA"

        // WHEN
        var detectedCode: UUID?
        let detectionExpectation = expectation(description: "Detector returns a result")

        detector.detectCopiedRequestCode {
            detectedCode = $0
            detectionExpectation.fulfill()
        }

        waitForExpectations(timeout: 1, handler: nil)

        // THEN
        XCTAssertNil(detectedCode)
    }

    func testThatItFailsWhenPasteboardIsEmpty() {
        // GIVEN
        pasteboard.text = nil

        // WHEN
        var detectedCode: UUID?
        let detectionExpectation = expectation(description: "Detector returns a result")

        detector.detectCopiedRequestCode {
            detectedCode = $0
            detectionExpectation.fulfill()
        }

        waitForExpectations(timeout: 1, handler: nil)

        // THEN
        XCTAssertNil(detectedCode)
    }

}
