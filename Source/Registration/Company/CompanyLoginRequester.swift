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

import Foundation

public protocol CompanyLoginRequesterDelegate: class {

    /**
     * The session requester asks the user to verify their identity on the given website.
     *
     * - parameter requester: The session requester asking for validation.
     * - parameter url: The URL where the user should be taken to perform validation.
     * - parameter completionHandler: The block of code to call with the validation result.
     */

    func companyLoginSessionRequester(_ requester: CompanyLoginRequester, didRequestIdentityValidationAtURL url: URL)

}

/**
 * An object that validates the identity of the user and creates a session using company login.
 */

public class CompanyLoginRequester {

    let environment: ZMBackendEnvironment

    /// The object that observes events and performs the required actions.
    public weak var delegate: CompanyLoginRequesterDelegate?

    /// Creates a session requester that targets the specified Backend environment.
    public init(environment: ZMBackendEnvironment) {
        self.environment = environment
    }

    public func requestIdentity(for token: UUID, bundleIdentifier: String) {
        guard let buildType = BuildType(bundleID: bundleIdentifier) else {
            fatalError("This unofficial build of Wire doesn't support company login.")
        }

        var urlComponents = URLComponents()
        urlComponents.scheme = "https"
        urlComponents.host = environment.type.backendHost
        urlComponents.path = "/sso/initiate-login/\(token.uuidString)"

        let successCallback = "\(buildType.urlScheme)://login/success/$cookie"
        let failureCallback = "\(buildType.urlScheme)://login/failure/$label"

        urlComponents.queryItems = [
            URLQueryItem(name: "success_redirect", value: successCallback),
            URLQueryItem(name: "error_redirect", value: failureCallback)
        ]

        guard let url = urlComponents.url else {
            fatalError("Invalid company login URL. This is a developer error.")
        }

        delegate?.companyLoginSessionRequester(self, didRequestIdentityValidationAtURL: url)
    }

}
