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
    
    public static var allSizes: [ImageSize] { return [.preview, .complete] }
}

public enum UserProfileImageUpdateError: Error {
    case preprocessingFailed
    case uploadFailed(NSError)
}

public protocol UserProfileImageUpdateStateDelegate: class {
    func failed(withError: UserProfileImageUpdateError)
}

public class UserProfileImageUpdateStatus {
    
    internal enum State {
        case ready
        case preprocessing
        case upload(image: UIImage)
        case uploading
        case uploaded(assetId: String)
        case completed
        case failed(UserProfileImageUpdateError)
    }
    
    fileprivate var changeDelegates: [UserProfileImageUpdateStateDelegate] = []
    
    fileprivate var state: [ImageSize : State] = [
        .preview : .ready,
        .complete : .ready
        ]
    
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
        
//        switch newState {
//        case .completed:
//            <#code#>
//        default:
//            <#code#>
//        }
        
//        switch newState {
//        case .failed(let error):
//        
//        case .ready:
//            break
//        default:
//            notifyDelegates(stateChanged: newState, for: imageSize)
//        }

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
        case (_, .failed):
            return true
        default:
            return false
        }
    }
    
    public func updateImage(image: UIImage) {
        setState(state: .preprocessing, for: .preview)
        setState(state: .preprocessing, for: .complete)
        // Create ZMAssetsPreprocessor and kick off preprocessing
    }
    
    public func preprocessingFailed(imageSize: ImageSize) {
        setState(state: .failed(.preprocessingFailed), for: imageSize)
    }
    
    public func preprocessingDone(imageSize: ImageSize, image: UIImage) {
        setState(state: .upload(image: image), for: imageSize)
    }
    
    func uploadingDone(imageSize: ImageSize, assetId: String) {
        setState(state: .uploaded(assetId: assetId), for: imageSize)
    }
    
    func uploadingFailed(imageSize: ImageSize, error: NSError) {
        setState(state: .failed(.uploadFailed(error)), for: imageSize)
    }
}
