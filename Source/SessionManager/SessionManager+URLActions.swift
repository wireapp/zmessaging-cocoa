//
// Wire
// Copyright (C) 2020 Wire Swiss GmbH
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

/// URLActionDelegate supports observing and controlling which URLAction are performed.

public protocol URLActionDelegate: class {
    
    /// Called when an attempt was made to process a URLAction but failed
    ///
    /// - parameter action: Action which failed to be performed.
    /// - parameter error: Error describing why the action failed.
    func failedToPerformAction(_ action: URLAction, error: Error)
    
    /// Called before attempt is made to process a URLAction, this is a opportunity for asking the user
    /// to confirm the action. The answer is provided via the decisionHandler.
    ///
    /// - parameter action: Action which will be performed.
    /// - parameter decisionHandler: Block which should be executed when the decision has been to perform the action or not.
    /// - parameter shouldPerformAction: **true**: perform the action, **false**: abort the action
    func shouldPerformAction(_ action: URLAction, decisionHandler: @escaping (_ shouldPerformAction: Bool) -> Void)
    
    /// Called when an URLAction was successfully performed.
    func completedURLAction(_ action: URLAction)
}

/// URLActionProcessor has the capabillity of processing a URLAction

protocol URLActionProcessor {

    /// Process an URL action
    ///
    /// - parameter urlAction: URLAction to process.
    /// - parameter delegate: Delegate which observes the attempt of processing the action.
    func process(urlAction: URLAction, delegate: URLActionDelegate?)
    
}

extension SessionManager {
    
    
    /// React to the application being opened via a URL
    ///
    /// - parameter url: URL the application was launched with
    /// - parameter options: options associated with the URL
    @discardableResult
    public func openURL(_ url: URL, options: [UIApplication.OpenURLOptionsKey: Any]) throws -> Bool {
        guard let action = try URLAction(url: url) else { return false }
        
        if action.requiresAuthentication, let userSession = activeUserSession {
            process(urlAction: action, on: userSession)
        } else if action.requiresAuthentication {
            guard isSelectedAccountAuthenticated else {
                throw DeepLinkRequestError.notLoggedIn
            }
            
            pendingURLAction = action
        } else {
            process(urlAction: action, on: activeUnauthenticatedSession)
        }
        
        return true
    }
    
    func process(urlAction action: URLAction, on processor: URLActionProcessor) {
        urlActionDelegate?.shouldPerformAction(action, decisionHandler: { [weak self] (shouldPerformAction) in
            guard shouldPerformAction, let strongSelf = self else { return }
            processor.process(urlAction: action, delegate: strongSelf.urlActionDelegate)
        })
    }
    
    func processPendingURLAction() {
        if let action = pendingURLAction, let userSession = activeUserSession {
            process(urlAction: action, on: userSession)
        }
        
        pendingURLAction = nil
    }
    
}
