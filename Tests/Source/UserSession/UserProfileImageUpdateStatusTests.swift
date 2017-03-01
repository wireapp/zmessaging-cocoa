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
    var operations = [Operation]()

    var imageOwner: ZMImageOwner? = nil
    var operationsCalled: Bool = false
    
    func operations(forPreprocessingImageOwner imageOwner: ZMImageOwner) -> [Operation]? {
        operationsCalled = true
        self.imageOwner = imageOwner
        return operations
    }
}

class MockOperation: NSObject, ZMImageDownsampleOperationProtocol {
    let downsampleImageData: Data
    let format: ZMImageFormat
    let properties : ZMIImageProperties
    
    init(downsampleImageData: Data = Data(), format: ZMImageFormat = .original, properties: ZMIImageProperties = ZMIImageProperties(size: .zero, length: 0, mimeType: "foo")) {
        self.downsampleImageData = downsampleImageData
        self.format = format
        self.properties = properties
    }
}

class MockImageOwner: NSObject, ZMImageOwner {
    public func requiredImageFormats() -> NSOrderedSet! { return NSOrderedSet() }
    public func imageData(for format: ZMImageFormat) -> Data! { return Data() }
    public func setImageData(_ imageData: Data!, for format: ZMImageFormat, properties: ZMIImageProperties!) {}
    public func originalImageData() -> Data! { return Data() }
    public func originalImageSize() -> CGSize { return .zero }
    public func isInline(for format: ZMImageFormat) -> Bool { return false }
    public func isPublic(for format: ZMImageFormat) -> Bool { return false }
    public func isUsingNativePush(for format: ZMImageFormat) -> Bool { return false }
    public func processingDidFinish() {}
}

extension UserProfileImageUpdateStatus.State {
    static var allStates: [UserProfileImageUpdateStatus.State] {
        return [.ready, .preprocessing, sampleUploadState, .uploading, sampleUploadedState, .completed, sampleFailedState]
    }
}

class UserProfileImageUpdateStatusTests: MessagingTest {
    var sut : UserProfileImageUpdateStatus!
    var preprocessor : MockPreprocessor!
    var tinyImage: Data!
    var imageOwner: ZMImageOwner!
    
    override func setUp() {
        super.setUp()
        preprocessor = MockPreprocessor()
        sut = UserProfileImageUpdateStatus(preprocessor: preprocessor)
        tinyImage = data(forResource: "tiny", extension: "jpg")
        imageOwner = UserProfileImageOwner(imageData: tinyImage, size: .zero)
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
    
    func operationWithExpectation(description: String) -> Operation {
        let expectation = self.expectation(description: description)
        return BlockOperation {
            expectation.fulfill()
        }
    }
}

// MARK: State transitions
extension UserProfileImageUpdateStatusTests {
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

// MARK: Preprocessing
extension UserProfileImageUpdateStatusTests {
    func testThatItSetsPreprocessorDelegateWhenProcessing() {
        // WHEN
        sut.updateImage(imageData: tinyImage, size: .zero)

        // THEN
        XCTAssertNotNil(preprocessor.delegate)
    }
    
    func testThatItAsksPreprocessorForOperationsWithCorrectImageOwner() {
        // WHEN
        sut.updateImage(imageData: tinyImage, size: .zero)

        // THEN
        XCTAssertTrue(preprocessor.operationsCalled)
        let imageOwner = preprocessor.imageOwner
        XCTAssertNotNil(imageOwner)
        XCTAssertEqual(imageOwner?.originalImageData(), tinyImage)
    }
    
    func testThatPreprocessingFailsWhenNoOperationsAreReturned() {
        // GIVEN
        preprocessor.operations = []
        
        // WHEN
        sut.updateImage(imageData: tinyImage, size: .zero)

        // THEN
        XCTAssertEqual(sut.state(for: .preview), .failed(.preprocessingFailed))
        XCTAssertEqual(sut.state(for: .complete), .failed(.preprocessingFailed))
    }
    
    func testThatResizeOperationsAreEnqueued() {
        // GIVEN
        let e1 = self.operationWithExpectation(description: "#1 Image processing done")
        let e2 = self.operationWithExpectation(description: "#2 Image processing done")
        preprocessor.operations = [e1, e2]
        
        // WHEN
        sut.updateImage(imageData: tinyImage, size: .zero)

        // THEN 
        XCTAssertTrue(self.waitForCustomExpectations(withTimeout: 0.5))
    }
    
    func testThatAfterDownsamplingImageItSetsCorrectState() {
        // GIVEN
        sut.setState(state: .preprocessing, for: .complete)
        sut.setState(state: .preprocessing, for: .preview)
        
        let previewOperation = MockOperation(downsampleImageData: "preview".data(using: .utf8)!, format: ImageSize.preview.imageFormat)
        let completeOperation = MockOperation(downsampleImageData: "complete".data(using: .utf8)!, format: ImageSize.complete.imageFormat)

        // WHEN
        sut.completedDownsampleOperation(previewOperation, imageOwner: imageOwner)
        
        // THEN
        XCTAssertEqual(sut.state(for: .preview), .upload(image: previewOperation.downsampleImageData))
        XCTAssertEqual(sut.state(for: .complete), .preprocessing)

        // WHEN
        sut.completedDownsampleOperation(completeOperation, imageOwner: imageOwner)
        
        // THEN
        XCTAssertEqual(sut.state(for: .preview), .upload(image: previewOperation.downsampleImageData))
        XCTAssertEqual(sut.state(for: .complete), .upload(image: completeOperation.downsampleImageData))
    }
    
    func testThatIfDownsamplingFailsStateForAllSizesIsSetToFail() {
        // GIVEN
        sut.setState(state: .preprocessing, for: .complete)
        sut.setState(state: .preprocessing, for: .preview)
        
        // WHEN
        sut.failedPreprocessingImageOwner(imageOwner)
        
        // THEN
        XCTAssertEqual(sut.state(for: .preview), .failed(.preprocessingFailed))
        XCTAssertEqual(sut.state(for: .complete), .failed(.preprocessingFailed))
    }

}
