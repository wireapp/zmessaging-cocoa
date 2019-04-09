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

public enum URLAction: Equatable {
    case connectBot(serviceUser: ServiceUserData)
    case companyLoginSuccess(userInfo: UserInfo)
    case companyLoginFailure(error: CompanyLoginError)

    case startCompanyLogin(code: UUID)
    case warnInvalidCompanyLogin(error: ConmpanyLoginRequestError)

    case openConversation(id: UUID, conversation: ZMConversation?)

    // The UI search for the user ID and open the profile view for connection request if not connected
    case openUserProfile(id: UUID)
    case warnInvalidDeepLink(error: DeepLinkRequestError)


    /// Update self's associated value with given userSession
    ///
    /// - Parameter userSession: the active ZMUserSession
    mutating func setUserSession(userSession: ZMUserSession) {
        guard let moc = userSession.managedObjectContext else {
            return
        }

        switch self {
        case .openConversation(let id, _):
            guard let conversation = ZMConversation(remoteID: id, createIfNeeded: false, in: moc) else {
                self = .warnInvalidDeepLink(error: .invalidConversationLink)
                return
            }

            self = .openConversation(id: id, conversation: conversation)
        default:
            break
        }
    }

    var causesLogout: Bool {
        switch self {
        case .startCompanyLogin: return true
        default: return false
        }
    }

    var requiresAuthentication: Bool {
        switch self {
        case .openConversation,
             .openUserProfile,
             .connectBot:
             return true
        default: return false
        }
    }

    var opensDeepLink: Bool {
        switch self {
        case .openConversation,
             .openUserProfile:
            return true
        default: return false
        }
    }
}

extension URLComponents {
    func query(for key: String) -> String? {
        return self.queryItems?.first(where: { $0.name == key })?.value
    }
}

extension URLAction {
    init?(url: URL, validatingIn defaults: UserDefaults = .shared()) {
        guard let components = URLComponents(string: url.absoluteString),
            let host = components.host,
            let scheme = components.scheme,
            scheme.starts(with: "wire") == true else {
            return nil
        }
        
        switch host {
        case URL.DeepLink.user:
            if let lastComponent = url.pathComponents.last,
                let uuid = UUID(uuidString: lastComponent) {
                self = .openUserProfile(id: uuid)
            } else {
                self = .warnInvalidDeepLink(error: .invalidUserLink)
            }

        case URL.DeepLink.conversation:
            if let lastComponent = url.pathComponents.last,
                let uuid = UUID(uuidString: lastComponent) {
                self = .openConversation(id: uuid, conversation: nil)
            } else {
                self = .warnInvalidDeepLink(error: .invalidConversationLink)
            }

        case URL.Host.startSSO:
            if let uuidCode = url.pathComponents.last.flatMap(CompanyLoginRequestDetector.requestCode) {
                self = .startCompanyLogin(code: uuidCode)
            } else {
                self = .warnInvalidCompanyLogin(error: .invalidLink)
            }

        case URL.Host.connect:
            guard let service = components.query(for: "service"),
                let provider = components.query(for: "provider"),
                let serviceUUID = UUID(uuidString: service),
                let providerUUID = UUID(uuidString: provider) else {
                    self = .warnInvalidDeepLink(error: .malformedLink)
                    return
            }
            self = .connectBot(serviceUser: ServiceUserData(provider: providerUUID, service: serviceUUID))

        case URL.Host.login:
            let pathComponents = url.pathComponents

            guard url.pathComponents.count >= 2 else {
                self = .warnInvalidCompanyLogin(error: .invalidLink)
                return
            }

            switch pathComponents[1] {
            case URL.Path.success:
                guard URLAction.validateURLSchemeRequest(with: components, in: defaults) else {
                    self = .companyLoginFailure(error: .tokenNotFound)
                    return
                }
                
                guard let cookieString = components.query(for: URLQueryItem.Key.cookie) else {
                    self = .companyLoginFailure(error: .missingRequiredParameter)
                    return
                }
                guard let userID = components.query(for: URLQueryItem.Key.userIdentifier).flatMap(UUID.init) else {
                    self = .companyLoginFailure(error: .missingRequiredParameter)
                    return
                }
                
                guard let cookieData = HTTPCookie.extractCookieData(from: cookieString, url: url) else {
                    self = .companyLoginFailure(error: .invalidCookie)
                    return
                }

                let userInfo = UserInfo(identifier: userID, cookieData: cookieData)
                self = .companyLoginSuccess(userInfo: userInfo)

            case URL.Path.failure:
                guard URLAction.validateURLSchemeRequest(with: components, in: defaults) else {
                    self = .companyLoginFailure(error: .tokenNotFound)
                    return
                }
                
                guard let label = components.query(for: URLQueryItem.Key.errorLabel) else {
                    self = .companyLoginFailure(error: .missingRequiredParameter)
                    return
                }

                let error = CompanyLoginError(label: label)
                self = .companyLoginFailure(error: error)
            default:
                self = .warnInvalidCompanyLogin(error: .invalidLink)
                return
            }

        default:
            self = .warnInvalidDeepLink(error: .malformedLink)
            return
        }
    }
    
    private static func validateURLSchemeRequest(with components: URLComponents, in defaults: UserDefaults) -> Bool {
        guard let storedToken = CompanyLoginVerificationToken.current(in: defaults) else { return false }
        guard let token = components.query(for: URLQueryItem.Key.validationToken).flatMap(UUID.init) else { return false }
        return storedToken.matches(identifier: token)
    }


    func execute(in session: ZMUserSession) {
        switch self {
        case .connectBot(let serviceUserData):
            session.startConversation(with: serviceUserData, completion: nil)
        default:
            fatalError("This action cannot be executed with an authenticated session.")
        }
    }

    func execute(in unauthenticatedSession: UnauthenticatedSession) {
        switch self {
        case .companyLoginSuccess(let userInfo):
            unauthenticatedSession.authenticationStatus.loginSucceeded(with: userInfo)
        case .startCompanyLogin(let code):
            unauthenticatedSession.authenticationStatus.notifyCompanyLoginCodeDidBecomeAvailable(code)
        case .companyLoginFailure, .warnInvalidCompanyLogin:
            break // no-op (error should be handled in UI)
        default:
            fatalError("This action cannot be executed with an unauthenticated session.")
        }
        
        // Delete the url scheme verification token
        CompanyLoginVerificationToken.flush()
    }
}

public protocol SessionManagerURLHandlerDelegate: class {

    /// sessionManager executes a URLAction
    ///
    /// - Parameters:
    ///   - action: the action to execute
    ///   - callback: the callback with a bool shouldExecute, it should be called after the action is executed.
    func sessionManagerShouldExecuteURLAction(_ action: URLAction, callback: @escaping (Bool) -> Void)
}

public final class SessionManagerURLHandler: NSObject {
    private weak var userSessionSource: UserSessionSource?
    public weak var delegate: SessionManagerURLHandlerDelegate?
    
    fileprivate var pendingAction: URLAction? = nil
    
    internal init(userSessionSource: UserSessionSource) {
        self.userSessionSource = userSessionSource
    }

    @objc @discardableResult
    public func openURL(_ url: URL, options: [UIApplication.OpenURLOptionsKey: AnyObject]) -> Bool {
        guard let action = URLAction(url: url) else {
            return false
        }


        if action.opensDeepLink {
            guard let userSessionSource = userSessionSource else {
                pendingAction = action
                return true
            }

            if let userSession = userSessionSource.activeUserSession {
                handle(action: action, in: userSession)
            } else if userSessionSource.isSelectedAccountAuthenticated {
                pendingAction = action
                return true
            } else {
                handle(action: .warnInvalidDeepLink(error: .notLoggedIn), in: userSessionSource.activeUnauthenticatedSession)
            }

        } else if action.requiresAuthentication {

            guard let userSession = userSessionSource?.activeUserSession else {
                pendingAction = action
                return true
            }

            handle(action: action, in: userSession)

        } else {
            guard let unauthenticatedSession = userSessionSource?.activeUnauthenticatedSession else {
                return false
            }

            handle(action: action, in: unauthenticatedSession)
        }

        return true
    }

    fileprivate func handle(action: URLAction, in userSession: ZMUserSession) {
        let callback: (Bool) -> () = { shouldExecute in
            if shouldExecute {
                action.execute(in: userSession)
            }
        }

        ///update openUserProfile's associated value with session
        var mutableAction = action
        mutableAction.setUserSession(userSession: userSession)

        delegate?.sessionManagerShouldExecuteURLAction(mutableAction, callback: callback)
    }

    fileprivate func handle(action: URLAction, in unauthenticatedSession: UnauthenticatedSession) {
        delegate?.sessionManagerShouldExecuteURLAction(action) { shouldExecute in
            if shouldExecute {
                action.execute(in: unauthenticatedSession)
            }
        }
    }
    
    private func executePendingAction(userSession: ZMUserSession) {
        if let pendingAction = self.pendingAction {
            handle(action: pendingAction, in: userSession)
            self.pendingAction = nil
        }
    }
}

extension SessionManagerURLHandler: SessionActivationObserver {
    public func sessionManagerActivated(userSession: ZMUserSession) {
        executePendingAction(userSession: userSession)
    }
}
