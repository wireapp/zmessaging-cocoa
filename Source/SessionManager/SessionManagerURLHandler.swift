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

private struct URLWithOptions {
    private static let wireURLScheme = "wire"

    typealias Options = [UIApplicationOpenURLOptionsKey: AnyObject]
    let url: URL
    let options: Options
    
    init?(url: URL, options: Options) {
        guard url.scheme == URLWithOptions.wireURLScheme else {
            return nil
        }
        
        self.url = url
        self.options = options
    }
}

private enum URLAction {
    case connectBot(serviceUser: ServiceUserData)
    case companyLoginSuccess(cookie: String)
    case companyLoginFailure(errorLabel: String)
}

@objc public enum RawURLAction: Int {
    case connectBot
    case companyLoginSuccess
    case companyLoginFailure
}

extension URLComponents {
    func query(for key: String) -> String? {
        return self.queryItems?.first(where: { $0.name == key })?.value
    }
}

extension URLAction {
    init?(url: URL) {
        guard let host = url.host else {
            return nil
        }
        
        switch host {
        case "connect":
            guard let components = URLComponents(string: url.absoluteString),
                let service = components.query(for: "service"),
                let provider = components.query(for: "provider"),
                let serviceUUID = UUID(uuidString: service),
                let providerUUID = UUID(uuidString: provider) else {
                    return nil
            }
            self = .connectBot(serviceUser: ServiceUserData(provider: providerUUID, service: serviceUUID))

        case "login":
            let pathComponents = url.pathComponents

            guard pathComponents.count >= 3 else {
                return nil
            }

            let result = pathComponents[1]
            let data = pathComponents[2]

            switch result {
            case "success":
                self = .companyLoginSuccess(cookie: data)
            case "failure":
                self = .companyLoginFailure(errorLabel: data)
            default:
                return nil
            }

        default:
            return nil
        }
    }
    
    var rawAction: RawURLAction {
        switch self {
        case .connectBot:
            return .connectBot
        case .companyLoginFailure:
            return .companyLoginFailure
        case .companyLoginSuccess:
            return .companyLoginSuccess
        }
    }
    
    func execute(in session: ZMUserSession) {
        
        switch self {
        case .connectBot(let serviceUserData):
            session.startConversation(with: serviceUserData, completion: nil)

        case .companyLoginSuccess(_):
            fatalError("unimplemented -- we should start the session for the user")

        case .companyLoginFailure(_):
            fatalError("unimplemented -- we should notify the error")
        }
    }
}

public protocol SessionManagerURLHandlerDelegate: class {
    func sessionManagerShouldExecute(URLAction: RawURLAction, callback: @escaping (Bool)->(Void))
}

public final class SessionManagerURLHandler: NSObject {
    private weak var userSessionSource: UserSessionSource?
    public weak var delegate: SessionManagerURLHandlerDelegate?
    
    fileprivate var pendingOpenURL: URLWithOptions? = nil
    
    internal init(userSessionSource: UserSessionSource) {
        self.userSessionSource = userSessionSource
    }
    
    @objc @discardableResult
    public func openURL(_ url: URL, options: [UIApplicationOpenURLOptionsKey: AnyObject]) -> Bool {
        guard let urlWithOptions = URLWithOptions(url: url, options: options) else {
            return false
        }
        
        guard let userSession = userSessionSource?.activeUserSession else {
            pendingOpenURL = urlWithOptions
            return true
        }
        
        handle(urlWithOptions: urlWithOptions, in: userSession)
        
        return true
    }

    fileprivate func handle(urlWithOptions: URLWithOptions, in userSession: ZMUserSession) {
        guard let action = URLAction(url: urlWithOptions.url) else {
            return
        }
        delegate?.sessionManagerShouldExecute(URLAction: action.rawAction) { shouldExecute in
            if shouldExecute {
                action.execute(in: userSession)
            }
        }
    }
}

extension SessionManagerURLHandler: SessionActivationObserver {
    public func sessionManagerActivated(userSession: ZMUserSession) {
        if let pendingOpenURL = self.pendingOpenURL {
            self.handle(urlWithOptions: pendingOpenURL, in: userSession)
            self.pendingOpenURL = nil
        }
    }
}
