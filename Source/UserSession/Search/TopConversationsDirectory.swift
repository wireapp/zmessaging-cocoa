//
// Wire
// Copyright (C) 2016 Wire Swiss GmbH
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
import ZMCDataModel

/// Directory of various conversation lists
/// This object is expected to be used on the UI context only
@objc public class TopConversationsDirectory : NSObject {

    fileprivate let managedObjectContext : NSManagedObjectContext

    /// Cached top conversations
    /// - warning: Might include deleted or blocked conversations
    fileprivate var topConversationsCache : [ZMConversation] = []
    
    fileprivate(set) var fetchingTopConversations : Bool = false
    
    public init(managedObjectContext: NSManagedObjectContext) {
        self.managedObjectContext = managedObjectContext
        super.init()
        self.loadList()
    }
}

// MARK: - Top conversation
private let topConversationsObjectIDKey = "WireTopConversationsObjectIDKey"

extension TopConversationsDirectory {

    public func refreshTopConversations() {
        self.fetchingTopConversations = true
        RequestAvailableNotification.notifyNewRequestsAvailable(nil)
    }
    
    func didDownloadTopConversations(conversations: [ZMConversation]) {
        self.fetchingTopConversations = false
        self.managedObjectContext.perform {
            self.topConversationsCache = conversations.flatMap { self.managedObjectContext.object(with: $0.objectID) as? ZMConversation }
            self.persistList()
        }
    }
    
    /// Top conversations
    public var topConversations : [ZMConversation] {
        return self.topConversationsCache.filter { !$0.isZombieObject && $0.connection?.status == .accepted }
    }
    
    /// Persist list of conversations to persistent store
    private func persistList() {
        let valueToSave = self.topConversations.map { $0.objectID.uriRepresentation() }
        self.managedObjectContext.setPersistentStoreMetadata(valueToSave, forKey: topConversationsObjectIDKey)
    }

    /// Load list from persistent store
    fileprivate func loadList() {
        guard let ids = self.managedObjectContext.persistentStoreMetadata(forKey: topConversationsObjectIDKey) as? [URL] else {
            return
        }
        let managedObjectIDs = ids.flatMap { self.managedObjectContext.persistentStoreCoordinator?.managedObjectID(forURIRepresentation: $0) }
        self.topConversationsCache = managedObjectIDs.flatMap { self.managedObjectContext.object(with: $0) as? ZMConversation }
    }
}
