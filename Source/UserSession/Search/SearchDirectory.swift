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


public class SearchDirectory : NSObject {
    
    static let userIDsMissingProfileImage = SearchDirectoryUserIDTable()
    
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
        let task = SearchTask(request: request, context: searchContext, session: userSession)
        
        task.onResult { [weak self] (result, _) in
            self?.observeSearchUsers(result)
            self?.requestSearchUserProfileImages(result)
        }
        
        return task
    }
    
    func observeSearchUsers(_ result : SearchResult) {
        let searchUserObserverCenter = userSession.managedObjectContext.searchUserObserverCenter
        result.directory.forEach(searchUserObserverCenter.addSearchUser)
        result.services.flatMap { $0 as? ZMSearchUser }.forEach(searchUserObserverCenter.addSearchUser)
    }
    
    func requestSearchUserProfileImages(_ result : SearchResult) {
        let usersMissingProfileImage = Set(result.directory.filter({ !$0.isLocalOrHasCachedProfileImageData }))
        let botsMissingProfileImage = Set(result.services.flatMap { $0 as? ZMSearchUser }.filter({ !$0.isLocalOrHasCachedProfileImageData }))

        let allUsers = usersMissingProfileImage.union(botsMissingProfileImage)
        SearchDirectory.userIDsMissingProfileImage.setUsers(allUsers, forDirectory: self)
        RequestAvailableNotification.notifyNewRequestsAvailable(nil)
    }
    
}

extension SearchDirectory: TearDownCapable {
    /// Tear down the SearchDirectory.
    ///
    /// NOTE: this must be called before releasing the instance
    public func tearDown() {
        userSession.syncManagedObjectContext.performGroupedBlock {
            SearchDirectory.userIDsMissingProfileImage.removeDirectory(self)
            SearchDirectory.userIDsMissingProfileImage.clear()
            ZMSearchUser.searchUserToMediumImageCache().removeAllObjects()
        }

        // Reset search user observer center to remove unnecessarily observed search users
        userSession.managedObjectContext.searchUserObserverCenter.reset()

        isTornDown = true
    }
}
