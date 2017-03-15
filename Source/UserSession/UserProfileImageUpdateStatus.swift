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

internal enum ProfileImageSize {
    case preview
    case complete
    
    internal var imageFormat: ZMImageFormat {
        switch self {
        case .preview:
            return .medium
        case .complete:
            return .profile
        }
    }
}

internal enum UserProfileImageUpdateError: Error {
    case preprocessingFailed
    case uploadFailed(Error)
}

internal protocol UserProfileImageUpdateStateDelegate: class {
    func failed(withError: UserProfileImageUpdateError)
}

internal protocol UserProfileImageUploadStatusProtocol: class {
    var allSizes: [ProfileImageSize] { get }
    func consumeImage(for size: ProfileImageSize) -> Data?
    func hasImageToUpload(for size: ProfileImageSize) -> Bool
    func uploadingDone(imageSize: ProfileImageSize, assetId: String)
    func uploadingFailed(imageSize: ProfileImageSize, error: Error)
}

@objc public protocol UserProfileImageUpdateProtocol: class {
    @objc(updateImageWithImageData:imageSize:)
    func updateImage(imageData: Data, size: CGSize)
}

internal final class UserProfileImageUpdateStatus: NSObject {
    
    internal enum ImageState {
        case ready
        case preprocessing
        case upload(image: Data)
        case uploading
        case uploaded(assetId: String)
        case completed
        case failed(UserProfileImageUpdateError)
        
        internal func canTransition(to newState: ImageState) -> Bool {
            switch (self, newState) {
            case (.ready, .preprocessing),
                 (.preprocessing, .upload),
                 (.upload, .uploading),
                 (.uploading, .uploaded),
                 (.uploaded, .completed):
                return true
            case (.completed, .ready),
                 (.failed, .ready):
                return true
            case (.failed, .failed):
                return false
            case (_, .failed):
                return true
            default:
                return false
            }
        }
    }
    
    internal enum ProfileUpdateState {
        case ready
        case preprocess(image: Data, size: CGSize)
        case update(previewAssetId: String, completeAssetId: String)
        case updating
        case completed
        case failed(UserProfileImageUpdateError)
        
        internal func canTransition(to newState: ProfileUpdateState) -> Bool {
            switch (self, newState) {
            case (.ready, .preprocess),
                 (.preprocess, .update),
                 (.update, .updating),
                 (.updating, .completed):
                return true
            case (.completed, .ready),
                 (.failed, .ready):
                return true
            case (.completed, .failed),
                 (.failed, .failed):
                return false
            case (_, .failed):
                return true
            default:
                return false
            }
        }
    }
    
    internal var preprocessor: ZMAssetsPreprocessorProtocol?
    internal let queue: OperationQueue
    
    fileprivate var changeDelegates: [UserProfileImageUpdateStateDelegate] = []
    fileprivate var imageOwner: ImageOwner?
    
    fileprivate var imageState = [ProfileImageSize : ImageState]()
    internal fileprivate(set) var state: ProfileUpdateState = .ready
    
    internal init(preprocessor: ZMAssetsPreprocessorProtocol, queue: OperationQueue = ZMImagePreprocessor.createSuitableImagePreprocessingQueue()){
        self.queue = queue
        self.preprocessor = preprocessor
        super.init()
        self.preprocessor?.delegate = self
    }
}

// MARK: Main state transitions
extension UserProfileImageUpdateStatus {
    internal func setState(state newState: ProfileUpdateState) {
        let currentState = state
        guard currentState.canTransition(to: newState) else {
            // Trying to transition to invalid state - ignore
            return
        }
        state = newState
        didTransition(from: currentState, to: newState)
    }
    
    internal func didTransition(from oldState: ProfileUpdateState, to currentState: ProfileUpdateState) {
        switch (oldState, currentState) {
        case let (_, .preprocess(image: data, size: size)):
            startPreprocessing(imageData: data, size: size)
        case (_, .failed):
            resetImageState()
        default:
            break
        }
    }
    
    fileprivate func startPreprocessing(imageData: Data, size: CGSize) {
        allSizes.forEach {
            setState(state: .preprocessing, for: $0)
        }
        
        let imageOwner = UserProfileImageOwner(imageData: imageData, size: size)
        guard let operations = preprocessor?.operations(forPreprocessingImageOwner: imageOwner), !operations.isEmpty else {
            resetImageState()
            setState(state: .failed(.preprocessingFailed))
            return
        }
        
        queue.addOperations(operations, waitUntilFinished: false)
    }
}

// MARK: Image state transitions
extension UserProfileImageUpdateStatus {
    internal func imageState(for imageSize: ProfileImageSize) -> ImageState {
        return imageState[imageSize] ?? .ready
    }
    
    internal func setState(state newState: ImageState, for imageSize: ProfileImageSize) {
        let currentState = imageState(for: imageSize)
        guard currentState.canTransition(to: newState) else {
            // Trying to transition to invalid state - ignore
            return
        }
        
        imageState[imageSize] = newState
        didTransition(from: currentState, to: newState)
    }
    
    internal func resetImageState() {
        imageState.removeAll()
    }
    
    internal func didTransition(from oldState: ImageState, to currentState: ImageState) {
        switch (oldState, currentState) {
        case (_, .uploaded):
            // When one image is uploaded we check state of all other images
            let previewState = imageState(for: .preview)
            let completeState = imageState(for: .complete)
            
            switch (previewState, completeState) {
            case let (.uploaded(assetId: previewAssetId), .uploaded(assetId: completeAssetId)):
                // If both images are uploaded we can update profile
                setState(state: .update(previewAssetId: previewAssetId, completeAssetId: completeAssetId))
            default:
                break // Need to wait until both images are uploaded
            }
        case let (_, .failed(error)):
            setState(state: .failed(error))
        default:
            break
        }
    }
}

extension UserProfileImageUpdateStatus: UserProfileImageUpdateProtocol {
    public func updateImage(imageData: Data, size: CGSize) {
        setState(state: .preprocess(image: imageData, size: size))
    }
}

extension UserProfileImageUpdateStatus: ZMAssetsPreprocessorDelegate {
    
    public func completedDownsampleOperation(_ operation: ZMImageDownsampleOperationProtocol, imageOwner: ZMImageOwner) {
        allSizes.forEach {
            if operation.format == $0.imageFormat {
                setState(state: .upload(image: operation.downsampleImageData), for: $0)
            }
        }
    }
    
    public func failedPreprocessingImageOwner(_ imageOwner: ZMImageOwner) {
        setState(state: .failed(.preprocessingFailed))
    }
    
    public func didCompleteProcessingImageOwner(_ imageOwner: ZMImageOwner) {}
    
    public func preprocessingCompleteOperation(for imageOwner: ZMImageOwner) -> Operation? { return nil }
}

extension UserProfileImageUpdateStatus: UserProfileImageUploadStatusProtocol {
    internal var allSizes: [ProfileImageSize] {
        return [.preview, .complete]
    }
    
    internal func hasImageToUpload(for size: ProfileImageSize) -> Bool {
        switch imageState(for: size) {
        case .upload:
            return true
        default:
            return false
        }
    }
    
    internal func consumeImage(for size: ProfileImageSize) -> Data? {
        switch imageState(for: size) {
        case .upload(image: let image):
            setState(state: .uploading, for: size)
            return image
        default:
            return nil
        }
    }
    
    internal func uploadingDone(imageSize: ProfileImageSize, assetId: String) {
        setState(state: .uploaded(assetId: assetId), for: imageSize)
    }
    
    internal func uploadingFailed(imageSize: ProfileImageSize, error: Error) {
        setState(state: .failed(.uploadFailed(error)), for: imageSize)
    }
}
