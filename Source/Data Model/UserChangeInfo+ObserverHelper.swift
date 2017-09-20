//
//  UserChangeInfo.swift
//  WireSyncEngine
//
//  Created by Jacob on 19.09.17.
//  Copyright © 2017 Zeta Project Gmbh. All rights reserved.
//

import Foundation
import WireDataModel

public extension UserChangeInfo {
    
    // MARK: Registering ZMBareUser
    /// Adds an observer for the ZMUser or ZMSearchUser
    /// You must hold on to the token until you want to stop observing
    @objc(addObserver:forBareUser:userSession:)
    static func add(observer: ZMUserObserver, forBareUser user: ZMBareUser, userSession: ZMUserSession) -> NSObjectProtocol? {
        return UserChangeInfo.add(observer: observer, forBareUser: user, managedObjectContext: userSession.managedObjectContext)
    }
    
    // MARK: Registering SearchUserObservers
    /// Adds an observer for the searchUser if one specified or to all ZMSearchUser is none is specified
    /// You must hold on to the token until you want to stop observing
    @objc(addSearchUserObserver:for:userSession:)
    static func add(searchUserObserver observer: ZMUserObserver, for user: ZMSearchUser?, userSession: ZMUserSession) -> NSObjectProtocol {
        return UserChangeInfo.add(searchUserObserver: observer, for: user, managedObjectContext: userSession.searchManagedObjectContext)
    }
    
}
