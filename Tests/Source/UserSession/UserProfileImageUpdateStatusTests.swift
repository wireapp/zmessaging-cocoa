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

import XCTest
@testable import zmessaging
import ZMUtilities

extension UserProfileImageUpdateStatus.State: Equatable {
    public static func ==(lhs: UserProfileImageUpdateStatus.State, rhs: UserProfileImageUpdateStatus.State) -> Bool {
        return String(describing: lhs) == String(describing: rhs)
    }
}

var sampleUploadState: UserProfileImageUpdateStatus.State {
    return UserProfileImageUpdateStatus.State.upload(image: Data())
}
var sampleUploadedState: UserProfileImageUpdateStatus.State {
    return UserProfileImageUpdateStatus.State.uploaded(assetId: "foo")
}
var sampleFailedState: UserProfileImageUpdateStatus.State {
    return UserProfileImageUpdateStatus.State.failed(.preprocessingFailed)
}

class MockPreprocessor: NSObject, ZMAssetsPreprocessorProtocol {
    weak var delegate: ZMAssetsPreprocessorDelegate? = nil
    
    var imageOwner: ZMImageOwner? = nil
    
    func operations(forPreprocessingImageOwner imageOwner: ZMImageOwner) -> [Any]? {
        return []
    }
    
}

extension UserProfileImageUpdateStatus.State {
    static var allStates: [UserProfileImageUpdateStatus.State] {
        return [.ready, .preprocessing, sampleUploadState, .uploading, sampleUploadedState, .completed, sampleFailedState]
    }
}

class UserProfileImageUpdateStatusTests: MessagingTest {
    var sut : UserProfileImageUpdateStatus!
    var preprocessor : MockPreprocessor!

    override func setUp() {
        super.setUp()
        preprocessor = MockPreprocessor()
        sut = UserProfileImageUpdateStatus()
    }
    
    func checkThatTransition(from oldState: UserProfileImageUpdateStatus.State, to newState: UserProfileImageUpdateStatus.State, isValid: Bool, file: StaticString = #file, line: UInt = #line) {
        let result = sut.canTransition(from: oldState, to: newState)
        if isValid {
            XCTAssertTrue(result, "Should transition: [\(oldState)] -> [\(newState)]", file: file, line: line)
        } else {
            XCTAssertFalse(result, "Should not transition: [\(oldState)] -> [\(newState)]", file: file, line: line)
        }
    }
    
    func canTransition(from oldState: UserProfileImageUpdateStatus.State, onlyTo newStates: [UserProfileImageUpdateStatus.State], file: StaticString = #file, line: UInt = #line) {
        for state in UserProfileImageUpdateStatus.State.allStates {
            let isValid = newStates.contains(state)
            checkThatTransition(from: oldState, to: state, isValid: isValid, file: file, line: line)
        }
    }
    
    func testThatItStartsWithReadyState() {
        XCTAssertEqual(sut.state(for: .preview), .ready)
        XCTAssertEqual(sut.state(for: .complete), .ready)
    }
    
    func testTransitions() {
        canTransition(from: .ready, onlyTo: [sampleFailedState, .preprocessing])
        canTransition(from: .preprocessing, onlyTo: [sampleFailedState, sampleUploadState])
        canTransition(from: sampleUploadState, onlyTo: [sampleFailedState, .uploading])
        canTransition(from: .uploading, onlyTo: [sampleFailedState, sampleUploadedState])
        canTransition(from: sampleUploadedState, onlyTo: [sampleFailedState, .completed])
        canTransition(from: .completed, onlyTo: [sampleFailedState, .ready])
        canTransition(from: sampleFailedState, onlyTo: [.ready])
    }
    
    func testThatItCanTransitionToValidState() {
        // WHEN
        sut.setState(state: .preprocessing, for: .complete)
        
        // THEN
        XCTAssertEqual(sut.state(for: .complete), .preprocessing)
        XCTAssertEqual(sut.state(for: .preview), .ready)
    }
    
    func testThatItDoesntTransitionToInvalidState() {
        // WHEN
        sut.setState(state: .uploading, for: .preview)
        
        // THEN
        XCTAssertEqual(sut.state(for: .preview), .ready)
        XCTAssertEqual(sut.state(for: .complete), .ready)
    }
    
    func testThatItMaintainsSeparateStatesForDifferentSizes() {
        // WHEN
        sut.setState(state: sampleFailedState, for: .preview)
        
        // THEN
        XCTAssertEqual(sut.state(for: .preview), sampleFailedState)
        XCTAssertEqual(sut.state(for: .complete), .ready)
    }
}
