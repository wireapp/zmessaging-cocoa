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
@testable import WireSyncEngine
import WireUtilities

var sampleUploadState: UserProfileImageUpdateStatus.ImageState {
    return UserProfileImageUpdateStatus.ImageState.upload(image: Data())
}
var sampleUploadedState: UserProfileImageUpdateStatus.ImageState {
    return UserProfileImageUpdateStatus.ImageState.uploaded(assetId: "foo")
}
var sampleFailedImageState: UserProfileImageUpdateStatus.ImageState {
    return UserProfileImageUpdateStatus.ImageState.failed(.preprocessingFailed)
}

var samplePreprocessState: UserProfileImageUpdateStatus.ProfileUpdateState {
    return UserProfileImageUpdateStatus.ProfileUpdateState.preprocess(image: Data())
}
var sampleUpdateState: UserProfileImageUpdateStatus.ProfileUpdateState {
    return UserProfileImageUpdateStatus.ProfileUpdateState.update(previewAssetId: "id1", completeAssetId: "id2")
}
var sampleFailedState: UserProfileImageUpdateStatus.ProfileUpdateState {
    return UserProfileImageUpdateStatus.ProfileUpdateState.failed(.preprocessingFailed)
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

typealias ProfileUpdateState = WireSyncEngine.UserProfileImageUpdateStatus.ProfileUpdateState
typealias ImageState = WireSyncEngine.UserProfileImageUpdateStatus.ImageState

class MockChangeDelegate: WireSyncEngine.UserProfileImageUploadStateChangeDelegate {
    var states = [ProfileUpdateState]()
    func didTransition(from oldState: ProfileUpdateState, to currentState: ProfileUpdateState) {
        states.append(currentState)
    }
    
    var imageStates = [ProfileImageSize : [ImageState]]()

    func didTransition(from oldState: ImageState, to currentState: ImageState, for size: ProfileImageSize) {
        var states = imageStates[size] ?? [ImageState]()
        states.append(currentState)
        imageStates[size] = states
    }
}

enum MockUploadError: String, Error {
    case failed
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

protocol StateTransition: Equatable {
    func canTransition(to: Self) -> Bool
    static var allStates: [Self] { get }
}

extension StateTransition {
    func checkThatTransition(to newState: Self, isValid: Bool, file: StaticString = #file, line: UInt = #line) {
        let result = self.canTransition(to: newState)
        if isValid {
            XCTAssertTrue(result, "Should transition: [\(self)] -> [\(newState)]", file: file, line: line)
        } else {
            XCTAssertFalse(result, "Should not transition: [\(self)] -> [\(newState)]", file: file, line: line)
        }
    }
    
    static func canTransition(from oldState: Self, onlyTo newStates: [Self], file: StaticString = #file, line: UInt = #line) {
        for state in Self.allStates {
            let isValid = newStates.contains(state)
            oldState.checkThatTransition(to: state, isValid: isValid, file: file, line: line)
        }
    }
}

typealias UserProfileImageUpdateStatus = WireSyncEngine.UserProfileImageUpdateStatus

extension UserProfileImageUpdateStatus.ImageState: Equatable {
    public static func ==(lhs: UserProfileImageUpdateStatus.ImageState, rhs: UserProfileImageUpdateStatus.ImageState) -> Bool {
        return String(describing: lhs) == String(describing: rhs)
    }
}

extension UserProfileImageUpdateStatus.ImageState: StateTransition {
    static var allStates: [ImageState] {
        return [.ready, .preprocessing, sampleUploadState, .uploading, sampleUploadedState, sampleFailedImageState]
    }
}

extension ProfileUpdateState: Equatable {
    public static func ==(lhs: ProfileUpdateState, rhs: ProfileUpdateState) -> Bool {
        return String(describing: lhs) == String(describing: rhs)
    }
}

extension ProfileUpdateState: StateTransition {
    static var allStates: [ProfileUpdateState] {
        return [.ready, samplePreprocessState, sampleUpdateState, sampleFailedState]
    }
}

class UserProfileImageUpdateStatusTests: MessagingTest {
    var sut : UserProfileImageUpdateStatus!
    var preprocessor : MockPreprocessor!
    var tinyImage: Data!
    var imageOwner: ZMImageOwner!
    var changeDelegate: MockChangeDelegate!
    
    override func setUp() {
        super.setUp()
        preprocessor = MockPreprocessor()
        preprocessor.operations = [Operation()]
        sut = UserProfileImageUpdateStatus(managedObjectContext: syncMOC, preprocessor: preprocessor, queue: ZMImagePreprocessor.createSuitableImagePreprocessingQueue(), delegate: nil)
        tinyImage = data(forResource: "tiny", extension: "jpg")
        imageOwner = UserProfileImageOwner(imageData: tinyImage)
        changeDelegate = MockChangeDelegate()
        sut.changeDelegate = changeDelegate
    }
    
    func operationWithExpectation(description: String) -> Operation {
        let expectation = self.expectation(description: description)
        return BlockOperation {
            expectation.fulfill()
        }
    }
}

// MARK: Image state transitions
extension UserProfileImageUpdateStatusTests {
    func testThatImageStateStartsWithReadyState() {
        XCTAssertEqual(sut.imageState(for: .preview), .ready)
        XCTAssertEqual(sut.imageState(for: .complete), .ready)
    }
    
    func testImageStateTransitions() {
        ImageState.canTransition(from: .ready, onlyTo: [sampleFailedImageState, .preprocessing, sampleUploadState])
        ImageState.canTransition(from: .preprocessing, onlyTo: [sampleFailedImageState, sampleUploadState])
        ImageState.canTransition(from: sampleUploadState, onlyTo: [sampleFailedImageState, .uploading])
        ImageState.canTransition(from: .uploading, onlyTo: [sampleFailedImageState, sampleUploadedState])
        ImageState.canTransition(from: sampleUploadedState, onlyTo: [sampleFailedImageState, .ready])
        ImageState.canTransition(from: sampleFailedImageState, onlyTo: [.ready])
    }
    
    func testThatImageStateCanTransitionToValidState() {
        // WHEN
        sut.setState(state: .preprocessing, for: .complete)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))

        // THEN
        XCTAssertEqual(sut.imageState(for: .complete), .preprocessing)
        XCTAssertEqual(sut.imageState(for: .preview), .ready)
    }
    
    func testThatImageStateDoesntTransitionToInvalidState() {
        // WHEN
        sut.setState(state: .uploading, for: .preview)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))

        // THEN
        XCTAssertEqual(sut.imageState(for: .preview), .ready)
        XCTAssertEqual(sut.imageState(for: .complete), .ready)
    }
    
    func testThatImageStateMaintainsSeparateStatesForDifferentSizes() {
        // WHEN
        sut.setState(state: .preprocessing, for: .preview)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))

        // THEN
        XCTAssertEqual(sut.imageState(for: .preview), .preprocessing)
        XCTAssertEqual(sut.imageState(for: .complete), .ready)
    }
    
    func testThatProfileUpdateStateIsSetToUpdateAfterAllImageStatesAreUploaded() {
        // GIVEN
        sut.setState(state: samplePreprocessState)
        sut.setState(state: .preprocessing, for: .preview)
        sut.setState(state: .preprocessing, for: .complete)
        sut.setState(state: sampleUploadState, for: .preview)
        sut.setState(state: sampleUploadState, for: .complete)
        sut.setState(state: .uploading, for: .preview)
        sut.setState(state: .uploading, for: .complete)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))

        XCTAssertEqual(sut.imageState(for: .preview), .uploading)
        XCTAssertEqual(sut.imageState(for: .complete), .uploading)
        let delegate = MockChangeDelegate()

        // WHEN
        let previewAssetId = "asset_preview"
        let completeAssetId = "asset_complete"
        
        sut.changeDelegate = delegate
        sut.setState(state: .uploaded(assetId: previewAssetId), for: .preview)
        sut.setState(state: .uploaded(assetId: completeAssetId), for: .complete)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))

        // THEN
        let states: [ProfileUpdateState] = [.update(previewAssetId: previewAssetId, completeAssetId: completeAssetId), .ready]
        XCTAssertEqual(delegate.states, states)
    }
    
    func testThatProfileUpdateStateIsSetToFailedAfterAnyImageStatesIsFailed() {
        // WHEN
        sut.setState(state: .preprocessing, for: .preview)
        sut.setState(state: sampleUploadState, for: .preview)
        sut.setState(state: sampleFailedImageState, for: .preview)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))

        // THEN
        XCTAssertEqual(sut.state, .failed(.preprocessingFailed))
    }

}

// MARK: Main state transitions
extension UserProfileImageUpdateStatusTests {
    func testThatProfileUpdateStateStartsWithReadyState() {
        XCTAssertEqual(sut.state, .ready)
    }
    
    func testProfileUpdateStateTransitions() {
        ProfileUpdateState.canTransition(from: .ready, onlyTo: [sampleFailedState, samplePreprocessState, sampleUpdateState])
        ProfileUpdateState.canTransition(from: samplePreprocessState, onlyTo: [sampleFailedState, sampleUpdateState])
        ProfileUpdateState.canTransition(from: sampleUpdateState, onlyTo: [sampleFailedState, .ready])
        ProfileUpdateState.canTransition(from: sampleFailedState, onlyTo: [.ready])
    }
    
    func testThatProfileUpdateStateCanTransitionToValidState() {
        // WHEN
        sut.setState(state: samplePreprocessState)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))

        // THEN
        XCTAssertEqual(sut.state, samplePreprocessState)
    }
    
    func testThatProfileUpdateStateDoesntTransitionToInvalidState() {
        // WHEN
        sut.setState(state: sampleUpdateState)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))

        // THEN
        XCTAssertEqual(sut.state, .ready)
    }
    
    func testThatWhenProfileUpdateStateIsFailedImageStatesAreBackToReady() {
        // GIVEN
        sut.setState(state: .preprocessing, for: .preview)
        sut.setState(state: .preprocessing, for: .complete)

        // WHEN
        sut.setState(state: .failed(.preprocessingFailed))
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))

        // THEN
        XCTAssertEqual(sut.state, .failed(.preprocessingFailed))
        XCTAssertEqual(sut.imageState(for: .preview), .ready)
        XCTAssertEqual(sut.imageState(for: .complete), .ready)
    }
}

// MARK: Preprocessing
extension UserProfileImageUpdateStatusTests {
    func testThatItSetsPreprocessorDelegateWhenProcessing() {
        // WHEN
        sut.updateImage(imageData: tinyImage)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))

        // THEN
        XCTAssertNotNil(preprocessor.delegate)
    }
    
    func testThatItAsksPreprocessorForOperationsWithCorrectImageOwner() {
        // WHEN
        sut.updateImage(imageData: tinyImage)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))

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
        sut.updateImage(imageData: tinyImage)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))

        // THEN
        XCTAssertEqual(sut.state, .failed(.preprocessingFailed))
        XCTAssertEqual(sut.imageState(for: .preview), .ready)
        XCTAssertEqual(sut.imageState(for: .complete), .ready)
    }
    
    func testThatResizeOperationsAreEnqueued() {
        // GIVEN
        let e1 = self.operationWithExpectation(description: "#1 Image processing done")
        let e2 = self.operationWithExpectation(description: "#2 Image processing done")
        preprocessor.operations = [e1, e2]
        
        // WHEN
        sut.updateImage(imageData: tinyImage)

        // THEN 
        XCTAssertTrue(self.waitForCustomExpectations(withTimeout: 0.5))
    }

    func testThatItSetsTheOriginalProfileImageDataOnTheSelfUser() {
        // GIVEN
        let selfUser = ZMUser.selfUser(in: uiMOC)
        let oldData = selfUser.originalProfileImageData
        let newData = mediumJPEGData()
        XCTAssertNotEqual(oldData, newData)

        // WHEN
        sut.updateImage(imageData: newData)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))

        // THEN
        XCTAssertEqual(selfUser.originalProfileImageData, newData)
    }
    
    func testThatAfterDownsamplingImageItSetsCorrectState() {
        // GIVEN
        sut.setState(state: .preprocessing, for: .complete)
        sut.setState(state: .preprocessing, for: .preview)
        
        let previewOperation = MockOperation(downsampleImageData: "preview".data(using: .utf8)!, format: ProfileImageSize.preview.imageFormat)
        let completeOperation = MockOperation(downsampleImageData: "complete".data(using: .utf8)!, format: ProfileImageSize.complete.imageFormat)

        // WHEN
        sut.completedDownsampleOperation(previewOperation, imageOwner: imageOwner)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))

        // THEN
        XCTAssertEqual(sut.imageState(for: .preview), .upload(image: previewOperation.downsampleImageData))
        XCTAssertEqual(sut.imageState(for: .complete), .preprocessing)

        // WHEN
        sut.completedDownsampleOperation(completeOperation, imageOwner: imageOwner)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))

        // THEN
        XCTAssertEqual(sut.imageState(for: .preview), .upload(image: previewOperation.downsampleImageData))
        XCTAssertEqual(sut.imageState(for: .complete), .upload(image: completeOperation.downsampleImageData))
    }
    
    func testThatIfDownsamplingFailsStateForAllSizesIsSetToFail() {
        // GIVEN
        sut.setState(state: .preprocessing, for: .complete)
        sut.setState(state: .preprocessing, for: .preview)
        
        // WHEN
        sut.failedPreprocessingImageOwner(imageOwner)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))

        // THEN
        XCTAssertEqual(sut.state, .failed(.preprocessingFailed))
        XCTAssertEqual(sut.imageState(for: .preview), .ready)
        XCTAssertEqual(sut.imageState(for: .complete), .ready)
    }
    
    func testThatItIsNotPossibleToStartPreprocessingAgainIfProfileUpdateFails() {
        // GIVEN
        sut.updateImage(imageData: Data())
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))
        XCTAssertEqual(sut.state, .preprocess(image: Data()))
        XCTAssertEqual(sut.imageState(for: .preview), .preprocessing)
        XCTAssertEqual(sut.imageState(for: .complete), .preprocessing)
        sut.setState(state: .failed(.preprocessingFailed))

        // WHEN
        sut.updateImage(imageData: Data())
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))

        // THEN
        XCTAssertEqual(sut.state, .failed(.preprocessingFailed))
        XCTAssertEqual(sut.imageState(for: .preview), .ready)
        XCTAssertEqual(sut.imageState(for: .complete), .ready)

    }
}

// MARK: - Image upload status
extension UserProfileImageUpdateStatusTests {
    
    func testThatItReturnsImageToUploadOnlyWhenInUploadState() {
        // GIVEN
        XCTAssertFalse(sut.hasImageToUpload(for: .preview))
        sut.setState(state: .preprocessing, for: .preview)
        sut.setState(state: .upload(image: Data()), for: .preview)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))

        // THEN
        XCTAssertTrue(sut.hasImageToUpload(for: .preview))
        XCTAssertFalse(sut.hasImageToUpload(for: .complete))
    }
    
    func testThatItAdvancesStateAfterConsumingImage() {
        // GIVEN
        let data = "some".data(using: .utf8)!
        sut.setState(state: .preprocessing, for: .preview)
        sut.setState(state: .upload(image: data), for: .preview)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))

        // WHEN
        let dataToUpload = sut.consumeImage(for: .preview)
        XCTAssertNil(sut.consumeImage(for: .complete))
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))

        // THEN
        XCTAssertEqual(data, dataToUpload)
        XCTAssertEqual(sut.imageState(for: .preview), .uploading)
    }
    
    func testThatItAdvancesStateAfterUploadIsDone() {
        // GIVEN
        sut.setState(state: .preprocessing, for: .preview)
        sut.setState(state: .upload(image: Data()), for: .preview)
        sut.setState(state: .uploading, for: .preview)
        
        // WHEN
        let assetId = "1234"
        sut.uploadingDone(imageSize: .preview, assetId: assetId)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))

        // THEN
        XCTAssertEqual(sut.imageState(for: .preview), .uploaded(assetId: assetId))
    }
 
    func testThatItAdvancesStateAndPropogatesErrorWhenUploadFails() {
        // GIVEN
        sut.setState(state: .preprocessing, for: .preview)
        sut.setState(state: .upload(image: Data()), for: .preview)
        sut.setState(state: .uploading, for: .preview)
        
        // WHEN
        sut.uploadingFailed(imageSize: .preview, error: MockUploadError.failed)
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))

        // THEN
        XCTAssertEqual(sut.imageState(for: .preview), .ready)
        XCTAssertEqual(sut.state, .failed(.uploadFailed(MockUploadError.failed)))
    }
    
    func testThatItSignalsThereIsRequestAvailableAfterPreprocessingCompletes() {
        // GIVEN
        sut.setState(state: .preprocessing, for: .preview)
        expectation(forNotification: "RequestAvailableNotification", object: sut)
        
        // WHEN
        sut.setState(state: .upload(image: Data()), for: .preview)
        
        
        // THEN
        XCTAssert(waitForCustomExpectations(withTimeout:0.1))
    }

}

// MARK: - User profile update
extension UserProfileImageUpdateStatusTests {
    func testThatItUpdatesUserProfileAndMarksPropertiesToBeUploaded() {
        // GIVEN
        preprocessor.operations = [Operation()]
        let previewId = "foo"
        let completeId = "bar"
        sut.setState(state: .preprocess(image: Data()))
        
        // WHEN
        sut.setState(state: .update(previewAssetId: previewId, completeAssetId: completeId))
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))

        // THEN
        let selfUser = ZMUser.selfUser(in: syncMOC)
        XCTAssertEqual(selfUser.previewProfileAssetIdentifier, previewId)
        XCTAssertEqual(selfUser.completeProfileAssetIdentifier, completeId)
        XCTAssert(selfUser.hasLocalModifications(forKey: #keyPath(ZMUser.previewProfileAssetIdentifier)))
        XCTAssert(selfUser.hasLocalModifications(forKey: #keyPath(ZMUser.completeProfileAssetIdentifier)))
    }
    
    func testThatItSetsResizedImagesToSelfUserAfterCompletion() {
        // GIVEN
        let previewData = "small".data(using: .utf8)!
        let completeData = "laaaarge".data(using: .utf8)!
        let previewId = "foo"
        let completeId = "bar"

        // WHEN
        sut.updatePreprocessedImages(preview: previewData, complete: completeData)
        syncMOC.performGroupedBlock {
            _ = self.sut.consumeImage(for: .preview)
            _ = self.sut.consumeImage(for: .complete)
            self.sut.uploadingDone(imageSize: .preview, assetId: previewId)
            self.sut.uploadingDone(imageSize: .complete, assetId: completeId)
        }
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))

        // THEN
        let selfUser = ZMUser.selfUser(in: syncMOC)
        XCTAssertEqual(selfUser.imageSmallProfileData, previewData)
        XCTAssertEqual(selfUser.imageMediumData, completeData)
        XCTAssertEqual(selfUser.previewProfileAssetIdentifier, previewId)
        XCTAssertEqual(selfUser.completeProfileAssetIdentifier, completeId)
    }
}

// MARK: - Reuploading alreday preprocessed images
extension UserProfileImageUpdateStatusTests {

    func testThatItAdvancesStateWhenReuploadingPreprocessedImageData() {
        // GIVEN
        sut.updatePreprocessedImages(preview: verySmallJPEGData(), complete: mediumJPEGData())
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))

        // WHEN
        _ = sut.consumeImage(for: .preview)
        _ = sut.consumeImage(for: .complete)

        // THEN
        XCTAssertEqual(sut.imageState(for: .preview), .uploading)
        XCTAssertEqual(sut.imageState(for: .complete), .uploading)
    }

    func testThatItSetsTheCorrectStateWhenThereIsASelfUserWithoutV3AssetIDs() {
        // GIVEN
        let selfUser = createSelfClient().user!
        selfUser.imageMediumData = mediumJPEGData()
        selfUser.imageSmallProfileData = verySmallJPEGData()
        selfUser.needsToBeUpdatedFromBackend = false
        XCTAssertNil(selfUser.completeProfileAssetIdentifier)
        XCTAssertNil(selfUser.previewProfileAssetIdentifier)
        XCTAssertFalse(selfUser.needsToBeUpdatedFromBackend)

        // WHEN
        sut.reuploadExisingImageIfNeeded()
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))

        // THEN
        XCTAssertEqual(sut.imageState(for: .preview), .upload(image: verySmallJPEGData()))
        XCTAssertEqual(sut.imageState(for: .complete), .upload(image: mediumJPEGData()))
    }

    func testThatItDoesNotSetTheCorrectStateWhenThereIsASelfUserWithV3AssetIDs() {
        // GIVEN
        let selfUser = createSelfClient().user!
        selfUser.completeProfileAssetIdentifier = "complete-ID"
        selfUser.previewProfileAssetIdentifier = "preview-ID"
        XCTAssertNotNil(selfUser.completeProfileAssetIdentifier)
        XCTAssertNotNil(selfUser.previewProfileAssetIdentifier)

        // WHEN
        sut.reuploadExisingImageIfNeeded()
        XCTAssert(waitForAllGroupsToBeEmpty(withTimeout: 0.5))

        // THEN
        XCTAssertEqual(sut.imageState(for: .preview), .ready)
        XCTAssertEqual(sut.imageState(for: .complete), .ready)
    }

}
