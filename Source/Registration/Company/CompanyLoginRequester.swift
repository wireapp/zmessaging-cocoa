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
     * The login requester asks the user to verify their identity on the given website.
     *
     * - parameter requester: The requester asking for validation.
     * - parameter url: The URL where the user should be taken to perform validation.
     */

    func companyLoginRequester(_ requester: CompanyLoginRequester, didRequestIdentityValidationAtURL url: URL)

}

/**
 * An object that validates the identity of the user and creates a session using company login.
 */

public class CompanyLoginRequester {

    /// The URL scheme that where the callback will be provided.
    public let callbackScheme: String

    /// The object that observes events and performs the required actions.
    public weak var delegate: CompanyLoginRequesterDelegate?

    let backendHost: String

    /// Creates a session requester that uses the specified parameters.
    public init(backendHost: String, callbackScheme: String) {
        self.backendHost = backendHost
        self.callbackScheme = callbackScheme
    }

    // MARK: - Identity Request

    /**
     * Starts the company login flow for the user with the given login token.
     *
     * This method constructs the login URL, and calls the `delegate`, that will
     * handle opening the URL. Typically, this initiates the login flow, which will
     * open Safari. The `SessionManager` will handle the callback URL.
     *
     * - parameter token: The user login token, constructed from the request code.
     */

    public func requestIdentity(for token: UUID) {
        var urlComponents = URLComponents()
        urlComponents.scheme = "https"
        urlComponents.host = backendHost
        urlComponents.path = "/sso/initiate-login/\(token.uuidString)"

        urlComponents.queryItems = [
            URLQueryItem(name: "success_redirect", value: makeSuccessCallbackString()),
            URLQueryItem(name: "error_redirect", value: makeFailureCallbackString())
        ]

        guard let url = urlComponents.url else {
            fatalError("Invalid company login URL. This is a developer error.")
        }

        delegate?.companyLoginRequester(self, didRequestIdentityValidationAtURL: url)
    }

    // MARK: - Utilities

    private func makeSuccessCallbackString() -> String {
        var components = URLComponents()
        components.scheme = callbackScheme
        components.host = "login"
        components.path = "/success"

        components.queryItems = [
            URLQueryItem(name: "cookie", value: "$cookie"),
            URLQueryItem(name: "user_id", value: "$userid")
        ]

        return components.url!.absoluteString
    }

    private func makeFailureCallbackString() -> String {
        var components = URLComponents()
        components.scheme = callbackScheme
        components.host = "login"
        components.path = "/failure"

        components.queryItems = [
            URLQueryItem(name: "label", value: "$label")
        ]

        return components.url!.absoluteString
    }

}
