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

private let topPeopleCount = 24

@objc public class TopConversationsRequestStrategy : ZMAbstractRequestStrategy {
    
    let conversationDirectory : TopConversationsDirectory
    fileprivate var topPeopleSync : ZMSingleRequestSync! = nil
    
    /// Defines when requests for this Strategy are allowed to be sent
    public override var configuration: ZMStrategyConfigurationOption { return .allowsRequestsDuringEventProcessing }

    @available (*, unavailable, message: "use `init(managedObjectContext:appStateDelegate:conversationDirectory)`instead")
    override init(managedObjectContext moc: NSManagedObjectContext, appStateDelegate: ZMAppStateDelegate) {
        fatalError()
    }
    
    public init(managedObjectContext: NSManagedObjectContext,
                appStateDelegate: ZMAppStateDelegate,
                conversationDirectory: TopConversationsDirectory)
    {
        self.conversationDirectory = conversationDirectory
        super.init(managedObjectContext: managedObjectContext, appStateDelegate: appStateDelegate)
        self.topPeopleSync = ZMSingleRequestSync(singleRequestTranscoder: self, managedObjectContext: managedObjectContext)
    }
}

extension TopConversationsRequestStrategy : ZMSingleRequestTranscoder {
    
    public func request(for sync: ZMSingleRequestSync!) -> ZMTransportRequest! {
        return ZMTransportRequest(getFromPath: "/search/top?size=\(topPeopleCount)")
    }
    
    public func didReceive(_ response: ZMTransportResponse!, forSingleRequest sync: ZMSingleRequestSync!) {
        if response.result == .success {
            guard let payload = response.payload as? [String:Any],
                let documents = payload["documents"] as? [[String:Any]] else {
                    return
            }
            
            let ids = documents.flatMap { ($0["id"] as? String).flatMap { NSUUID(transport: $0) as? UUID } }
            let fetchedUsers = ZMUser.fetchObjects(withRemoteIdentifiers: NSOrderedSet(array: ids), in: self.managedObjectContext)!.array as! [ZMUser]
            
            // I need to maintain the order, but ZMUser.fetchObjects might mess up the order
            var mapping = [UUID:ZMUser]()
            fetchedUsers.forEach { (user) in
                mapping[user.remoteIdentifier!] = user
            }
            let sortedUsers = ids.flatMap { mapping[$0] }
            
            let conversations = sortedUsers.flatMap { $0.connection?.conversation }
            self.conversationDirectory.didDownloadTopConversations(conversations: conversations)
        }
    }
}

extension TopConversationsRequestStrategy : RequestStrategy {

    public override func nextRequestIfAllowed() -> ZMTransportRequest? {
        if self.conversationDirectory.fetchingTopConversations {
            self.topPeopleSync.readyForNextRequestIfNotBusy()
            return self.topPeopleSync.nextRequest()
        }
        return nil
    }
}
