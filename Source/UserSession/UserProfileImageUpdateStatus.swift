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

public enum ImageSize {
    case preview
    case complete
    
    var imageFormat: ZMImageFormat {
        switch self {
        case .preview:
            return .medium
        case .complete:
            return .profile
        }
    }
}

public enum UserProfileImageUpdateError: Error {
    case preprocessingFailed
    case uploadFailed(NSError)
}

public protocol UserProfileImageUpdateStateDelegate: class {
    func failed(withError: UserProfileImageUpdateError)
}

internal protocol UserProfileImageUploadStatusProtocol: class {
    var allSizes: [ImageSize] { get }
    func consumeImage(for size: ImageSize) -> Data?
    func hasImageToUpload(for size: ImageSize) -> Bool
    func uploadingDone(imageSize: ImageSize, assetId: String)
    func uploadingFailed(imageSize: ImageSize, error: NSError)
}

public final class UserProfileImageUpdateStatus: NSObject {
    
    internal enum State {
        case ready
        case preprocessing
        case upload(image: Data)
        case uploading
        case uploaded(assetId: String)
        case completed
        case failed(UserProfileImageUpdateError)
    }
    
    internal var preprocessor: ZMAssetsPreprocessorProtocol?
    internal let queue: OperationQueue
    
    fileprivate var changeDelegates: [UserProfileImageUpdateStateDelegate] = []
    fileprivate var imageOwner: ImageOwner?
    
    fileprivate var state = [ImageSize : State]()
    
    init(preprocessor: ZMAssetsPreprocessorProtocol, queue: OperationQueue = ZMImagePreprocessor.createSuitableImagePreprocessingQueue()){
        self.queue = queue
        self.preprocessor = preprocessor
        super.init()
    }
    
    internal func state(for imageSize: ImageSize) -> State {
        return state[imageSize] ?? .ready
    }
    
    internal func setState(state newState: State, for imageSize: ImageSize) {
        let currentState = state(for: imageSize)
        guard canTransition(from: currentState, to: newState) else {
            // Trying to transition to invalids state - ignore
            return
        }
        
        state[imageSize] = newState
    }
    
    internal func canTransition(from currentState: State, to newState: State) -> Bool {
        switch (currentState, newState) {
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

extension UserProfileImageUpdateStatus: ZMAssetsPreprocessorDelegate {
    
    public func updateImage(imageData: Data, size: CGSize) {
        allSizes.forEach {
            setState(state: .preprocessing, for: $0)
        }
        
        preprocessor?.delegate = self
        let imageOwner = UserProfileImageOwner(imageData: imageData, size: size)
        guard let operations = preprocessor?.operations(forPreprocessingImageOwner: imageOwner), !operations.isEmpty else {
            allSizes.forEach {
                setState(state: .failed(.preprocessingFailed), for: $0)
            }
            return
        }
        
        queue.addOperations(operations, waitUntilFinished: false)
    }
    
    public func completedDownsampleOperation(_ operation: ZMImageDownsampleOperationProtocol, imageOwner: ZMImageOwner) {
        allSizes.forEach {
            if operation.format == $0.imageFormat {
                setState(state: .upload(image: operation.downsampleImageData), for: $0)
            }
        }
    }
    
    public func failedPreprocessingImageOwner(_ imageOwner: ZMImageOwner) {
        allSizes.forEach {
            setState(state: .failed(.preprocessingFailed), for: $0)
        }
    }
    
    public func didCompleteProcessingImageOwner(_ imageOwner: ZMImageOwner) {}
    
    public func preprocessingCompleteOperation(for imageOwner: ZMImageOwner) -> Operation? { return nil }
}

extension UserProfileImageUpdateStatus: UserProfileImageUploadStatusProtocol {
    internal var allSizes: [ImageSize] {
        return [.preview, .complete]
    }
    
    internal func hasImageToUpload(for size: ImageSize) -> Bool {
        switch state(for: size) {
        case .upload:
            return true
        default:
            return false
        }
    }
    
    internal func consumeImage(for size: ImageSize) -> Data? {
        switch state(for: size) {
        case .upload(image: let image):
            setState(state: .uploading, for: size)
            return image
        default:
            return nil
        }
    }
    
    internal func uploadingDone(imageSize: ImageSize, assetId: String) {
        setState(state: .uploaded(assetId: assetId), for: imageSize)
    }
    
    internal func uploadingFailed(imageSize: ImageSize, error: NSError) {
        setState(state: .failed(.uploadFailed(error)), for: imageSize)
    }
}
