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


@objcMembers public class SearchDirectory : NSObject {
    
    let searchContext : NSManagedObjectContext
    let userSession : ZMUserSession
    var isTornDown = false
    
    deinit {
        assert(isTornDown, "`tearDown` must be called before SearchDirectory is deinitialized")
    }
    
    public init(userSession: ZMUserSession) {
        self.userSession = userSession
        self.searchContext = userSession.searchManagedObjectContext
    }

    /// Perform a search request.
    ///
    /// Returns a SearchTask which should be retained until the results arrive.
    public func perform(_ request: SearchRequest) -> SearchTask {
        let task = SearchTask(task: .search(searchRequest: request), context: searchContext, session: userSession)
        
        task.onResult { [weak self] (result, _) in
            self?.observeSearchUsers(result)
        }
        
        return task
    }
    
    /// Lookup a user by user Id and returns a search user in the directory results. If the user doesn't exists
    /// an empty directory result is returned.
    ///
    /// Returns a SearchTask which should be retained until the results arrive.
    public func lookup(userId: UUID) -> SearchTask {
        let task = SearchTask(task: .lookup(userId: userId), context: searchContext, session: userSession)
        
        task.onResult { [weak self] (result, _) in
            ///TODO: filter result here
            self?.observeSearchUsers(result)
        }
        
        return task
    }

    /*
    private func restrictPartnerResult(user: ZMUser) -> Bool {
        let showProfile: Bool
        let selfUser = ZMUser.selfUser(in: context)
        if selfUser.teamRole == .partner {
            if selfUser.membership?.createdBy == user {
                showProfile = true
            } else {
                let activeConversations = selfUser.activeConversations
                let activeContacts = Set(activeConversations.flatMap({ $0.activeParticipants }))

                if activeContacts.contains(user) {
                    showProfile = true
                } else {
                    showProfile = false
                }
            }
        } else {
            showProfile = true
        }
    }*/

    
    func observeSearchUsers(_ result : SearchResult) {
        let searchUserObserverCenter = userSession.managedObjectContext.searchUserObserverCenter
        result.directory.forEach(searchUserObserverCenter.addSearchUser)
        result.services.compactMap { $0 as? ZMSearchUser }.forEach(searchUserObserverCenter.addSearchUser)
    }
    
}

extension SearchDirectory: TearDownCapable {
    /// Tear down the SearchDirectory.
    ///
    /// NOTE: this must be called before releasing the instance
    public func tearDown() {
        // Evict all cached search users
        userSession.managedObjectContext.zm_searchUserCache?.removeAllObjects()

        // Reset search user observer center to remove unnecessarily observed search users
        userSession.managedObjectContext.searchUserObserverCenter.reset()

        isTornDown = true
    }
}
