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

    fileprivate let uiMOC : NSManagedObjectContext
    fileprivate let syncMOC : NSManagedObjectContext
    fileprivate static let topConversationSize = 25

    /// Cached top conversations
    /// - warning: Might include deleted or blocked conversations
    fileprivate var topConversationsCache : [ZMConversation] = []
    
    public init(managedObjectContext: NSManagedObjectContext) {
        uiMOC = managedObjectContext
        syncMOC = managedObjectContext.zm_sync
        super.init()
        self.loadList()
    }
}

// MARK: - Top conversation
private let topConversationsObjectIDKey = "WireTopConversationsObjectIDKey"

extension TopConversationsDirectory {

    public func refreshTopConversations() {
        syncMOC.performGroupedBlock {
            let conversations = self.fetchOneOnOneConversations()
            // Mapping from conversation to message count in the last month
            let countByConversation = conversations.mapToDictionary { $0.lastMonthMessageCount() }
            let sorted = countByConversation.sorted {  $0.1 > $1.1 }.prefix(TopConversationsDirectory.topConversationSize)
            let identifiers = sorted.flatMap { $0.0.objectID }
            self.updateUIList(with: identifiers)
        }
    }

    private func updateUIList(with identifiers: [NSManagedObjectID]) {
        uiMOC.performGroupedBlock {
            self.topConversationsCache = identifiers.flatMap {
                (try? self.uiMOC.existingObject(with: $0)) as? ZMConversation
            }
            self.persistList()
        }
    }

    private func fetchOneOnOneConversations() -> [ZMConversation] {
        let request = ZMConversation.sortedFetchRequest(with: ZMConversation.predicateForActiveOneOnOneConversations)
        return syncMOC.executeFetchRequestOrAssert(request) as! [ZMConversation]
    }
    
    /// Top conversations
    public var topConversations : [ZMConversation] {
        return self.topConversationsCache.filter { !$0.isZombieObject && $0.connection?.status == .accepted }
    }
    
    /// Persist list of conversations to persistent store
    private func persistList() {
        let valueToSave = self.topConversations.map { $0.objectID.uriRepresentation().absoluteString }
        self.uiMOC.setPersistentStoreMetadata(array: valueToSave, key: topConversationsObjectIDKey)
        TopConversationsDirectoryNotification.post()
    }

    /// Load list from persistent store
    fileprivate func loadList() {
        guard let ids = self.uiMOC.persistentStoreMetadata(forKey: topConversationsObjectIDKey) as? [String] else {
            return
        }
        let managedObjectIDs = ids.flatMap(URL.init).flatMap { self.uiMOC.persistentStoreCoordinator?.managedObjectID(forURIRepresentation: $0) }
        self.topConversationsCache = managedObjectIDs.flatMap { self.uiMOC.object(with: $0) as? ZMConversation }
    }
}

// MARK: – Observation
@objc public protocol TopConversationsDirectoryObserver {

    @objc func topConversationsDidChange()

}


struct TopConversationsDirectoryNotification {
    fileprivate static let name = NSNotification.Name(rawValue: "TopConversationsDirectoryNotification")

    static func post() {
        NotificationCenter.default.post(name: name, object: nil, userInfo: nil)
    }
}

@objc public class TopConversationsDirectoryObserverToken: NSObject {
    let innerToken: Any

    init(_ token: Any) {
        self.innerToken = token
    }
}


extension TopConversationsDirectory {

    @objc(addObserver:) public func add(observer: TopConversationsDirectoryObserver) -> TopConversationsDirectoryObserverToken {
        let token = NotificationCenter.default.addObserver(forName: TopConversationsDirectoryNotification.name, object: nil, queue: .main) { [weak observer] _ in
            observer?.topConversationsDidChange()
        }

        return TopConversationsDirectoryObserverToken(token)
    }

    @objc(removeObserver:) public func removeObserver(with token: TopConversationsDirectoryObserverToken) {
        NotificationCenter.default.removeObserver(token.innerToken, name: TopConversationsDirectoryNotification.name, object: nil)
    }

}

fileprivate extension ZMConversation {

    static var predicateForActiveOneOnOneConversations: NSPredicate {
        let oneOnOnePredicate = NSPredicate(format: "%K == %d", #keyPath(ZMConversation.conversationType), ZMConversationType.oneOnOne.rawValue)
        let acceptedPredicate = NSPredicate(format: "%K == %d", #keyPath(ZMConversation.connection.status), ZMConnectionStatus.accepted.rawValue)
        return NSCompoundPredicate(andPredicateWithSubpredicates: [oneOnOnePredicate, acceptedPredicate])
    }

    func lastMonthMessageCount() -> Int {
        guard let identifier = remoteIdentifier, let moc = managedObjectContext else { return 0 }
        guard let predicate = ZMMessage.predicateForNonSystemMessagesInTheLastMonth(in: identifier) else { return 0 }
        guard let request = ZMMessage.sortedFetchRequest(with: predicate) else { return 0 }
        return (try? moc.count(for: request)) ?? 0
    }

}


fileprivate extension ZMMessage {

    static func predicateForNonSystemMessagesInTheLastMonth(in identifier: UUID) -> NSPredicate? {
        guard let oneMonthAgo = Calendar.current.date(byAdding: .month, value: -1, to: Date()) else { return nil }
        let lastMonthPredicate = NSPredicate(format: "%K >= %@", #keyPath(ZMMessage.serverTimestamp), oneMonthAgo as NSDate)
        let conversationPredicate = NSPredicate(
            format: "%K.%K == %@",
            ZMMessageConversationKey,
            ZMConversationRemoteIdentifierDataKey,
            (identifier as NSUUID).data() as NSData
        )

        return NSCompoundPredicate(andPredicateWithSubpredicates: [lastMonthPredicate, conversationPredicate])
    }

}

