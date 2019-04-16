//
// Wire
// Copyright (C) 2019 Wire Swiss GmbH
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

extension SessionManager {

    public enum SwitchBackendError: Swift.Error {
        case loggedInAccounts
        case invalidBackend
    }
    
    public typealias OnBackendSwitchError = (SwitchBackendError) -> ()
    public typealias MakeSwitch = () -> ()
    public typealias CompletedSwitch = (BackendEnvironment?) -> ()
    
    public func switchBackend(configuration url: URL, onError: @escaping OnBackendSwitchError, completed: @escaping CompletedSwitch) -> MakeSwitch? {
        let authenticatedAccounts = accountManager.accounts.filter { environment.isAuthenticated($0) }
        guard authenticatedAccounts.isEmpty else { onError(.loggedInAccounts); return nil }
        
        return {
            BackendEnvironment.fetchEnvironment(url: url) { result in
                switch result {
                case .success(let environment):
                    self.environment = environment
                    self.unauthenticatedSession = nil
                    completed(environment)
                case .failure:
                    completed(nil)
                    onError(.invalidBackend)
                }
            }
        }
    }
}
