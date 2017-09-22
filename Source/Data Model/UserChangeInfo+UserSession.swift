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
import WireDataModel

public extension UserChangeInfo {
    
    
    // MARK: Registering UserObservers
    /// Adds an observer for the user if one specified or to all ZMUsers is none is specified
    /// You must hold on to the token and use it to unregister
    @objc(addObserver:forUser:userSession:)
    public static func add(observer: ZMUserObserver, for user: ZMUser?, userSession: ZMUserSession) -> NSObjectProtocol {
        return self.add(observer: observer, for: user, managedObjectContext: userSession.managedObjectContext)
    }
    
    // MARK: Registering ZMBareUser
    /// Adds an observer for the ZMUser or ZMSearchUser
    /// You must hold on to the token until you want to stop observing
    @objc(addObserver:forBareUser:userSession:)
    static func add(observer: ZMUserObserver, forBareUser user: ZMBareUser, userSession: ZMUserSession) -> NSObjectProtocol? {
        return self.add(observer: observer, forBareUser: user, managedObjectContext: userSession.managedObjectContext)
    }
    
    // MARK: Registering SearchUserObservers
    /// Adds an observer for the searchUser if one specified or to all ZMSearchUser is none is specified
    /// You must hold on to the token until you want to stop observing
    @objc(addObserver:forSearchUser:userSession:)
    static func add(searchUserObserver observer: ZMUserObserver, for user: ZMSearchUser?, userSession: ZMUserSession) -> NSObjectProtocol {
        return self.add(searchUserObserver: observer, for: user, managedObjectContext: userSession.managedObjectContext)
    }
}
