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

import UIKit

/**
 * An object that detects shared identity session request wihtin the pasteboard.
 *
 * A session request is a string formatted as `wire-[UUID]`.
 */

@objc public final class SharedIdentitySessionRequestDetector: NSObject {

    private let pasteboard: Pasteboard
    private let processQueue = DispatchQueue(label: "WireSyncEngine.SharedIdentitySessionRequestDetector")

    // MARK: - Initialization

    /// Returns the detector that uses the system pasteboard to detect session requests.
    @objc public static let shared = SharedIdentitySessionRequestDetector(pasteboard: UIPasteboard.general)

    /// Creates a detector that uses the specified pasteboard to detect session requests.
    public init(pasteboard: Pasteboard) {
        self.pasteboard = pasteboard
    }

    // MARK: - Detection

    /**
     * Tries to extract the session request code from the current pasteboard.
     *
     * The processing will be done on a background queue, and the completion
     * handler will be called on the main thread with the result.
     */

    @objc public func detectRequestCode(_ completionHandler: @escaping (UUID?) -> Void) {
        func complete(_ code: UUID?) {
            DispatchQueue.main.async {
                completionHandler(code)
            }
        }

        processQueue.async {
            if #available(iOS 10, *) {
                guard self.pasteboard.hasString else {
                    complete(nil)
                    return
                }
            }

            guard let string = self.pasteboard.string else {
                complete(nil)
                return
            }

            guard let prefixRange = string.range(of: "wire-") else {
                complete(nil)
                return
            }

            let codeString = string[prefixRange.upperBound ..< string.endIndex]
            let code = UUID(uuidString: String(codeString))

            complete(code)
        }
    }

}
