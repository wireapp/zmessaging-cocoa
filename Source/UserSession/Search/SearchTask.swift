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
import WireUtilities

typealias ResultHandler = (_ result: SearchResult) -> Void

public class SearchTask {
 
    fileprivate let session : ZMUserSession
    fileprivate let context : NSManagedObjectContext
    fileprivate let request : SearchRequest
    fileprivate var taskIdentifier : ZMTaskIdentifier?
    fileprivate var resultHandlers : [ResultHandler] = []
    fileprivate var result : SearchResult = SearchResult(contacts: [], teamMembers: [], directory: [], conversations: [])
    
    public init(request: SearchRequest, context: NSManagedObjectContext, session: ZMUserSession) {
        self.request = request
        self.session = session
        self.context = context
    }
    
    func onResult(_ resultHandler : @escaping ResultHandler) {
        resultHandlers.append(resultHandler)
    }
    
    func start() {
        performLocalSearch()
        performRemoteSearch()
    }
    
    func cancel() {
        resultHandlers.removeAll()
        
        if let taskIdentifier = taskIdentifier {
            session.transportSession.cancelTask(with: taskIdentifier)
        }
    }
    
    func update(_ result : SearchResult) {
        resultHandlers.forEach { $0(result) }
    }
    
}

extension SearchTask {
    
    func performLocalSearch() {
        context.performGroupedBlock {
            
            let connectedUsers = self.request.searchOptions.contains(.contacts) ? self.connectedUsers(matchingQuery: self.request.query) : []
            let teamMembers = self.request.searchOptions.contains(.teamMembers) ? self.teamMembers(matchingQuery: self.request.query) : []
            let conversations = self.request.searchOptions.contains(.conversations) ? self.conversations(matchingQuery: self.request.query) : []
            let result = SearchResult(contacts: connectedUsers, teamMembers: teamMembers, directory: [], conversations: conversations)
            
            self.session.managedObjectContext.performGroupedBlock {
                self.result = result.union(withLocalResult: result.copy(on: self.session.managedObjectContext))
                self.update(self.result)
            }
        }
    }
    
    func teamMembers(matchingQuery query : String) -> [Member] {
        return request.team?.members(matchingQuery: query) ?? []
    }
    
    func connectedUsers(matchingQuery query: String) -> [ZMUser] {
        let fetchRequest = ZMUser.sortedFetchRequest(with: ZMUser.predicateForConnectedUsers(withSearch: query))
        return context.executeFetchRequestOrAssert(fetchRequest) as? [ZMUser] ?? []
    }
    
    func conversations(matchingQuery query: String) -> [ZMConversation] {
        let fetchRequest = ZMConversation.sortedFetchRequest(with: ZMConversation.predicate(forSearchQuery: query, team: request.team))
        fetchRequest?.sortDescriptors = [NSSortDescriptor(key: ZMNormalizedUserDefinedNameKey, ascending: true)]
        var conversations = context.executeFetchRequestOrAssert(fetchRequest) as? [ZMConversation] ?? []
        
        if query.hasPrefix("@") {
            // if we are searching for a username only include conversations with matching displayName
            conversations = conversations.filter { $0.displayName.contains(query)}
        }
        
        let matchingPredicate = ZMConversation.userDefinedNamePredicate(forSearch: query)
        var matching : [ZMConversation] = []
        var nonMatching : [ZMConversation] = []
        
        conversations.forEach { (conversation) in
            if matchingPredicate.evaluate(with: conversation) {
                matching.append(conversation)
            } else {
                nonMatching.append(conversation)
            }
        }
        
        return matching + nonMatching
    }
    
}

extension SearchTask {
    
    func performRemoteSearch() {
        guard request.searchOptions.contains(.directoryMatches) else { return }
        
        context.performGroupedBlock {
            let request = self.searchRequestInDirectory(withQuery: self.request.query)
            
            request.add(ZMCompletionHandler(on: self.session.managedObjectContext, block: { (response) in
                guard
                    let payload = response.payload?.asDictionary(),
                    let result = SearchResult(payload: payload, query: self.request.query, userSession: self.session)
                else {
                    return
                }
                
                self.result = result.union(withRemoteResult: result)
                self.update(result)
            }))
            
            request.add(ZMTaskCreatedHandler(on: self.context, block: { (taskIdentifier) in
                self.taskIdentifier = taskIdentifier
            }))
            
            self.session.transportSession.enqueueSearch(request)
        }
    }
    
    func searchRequestInDirectory(withQuery query : String, fetchLimit: Int = 10) -> ZMTransportRequest {
        var query = query
        
        if query.hasPrefix("@") {
            query = query.substring(from: query.index(after: query.startIndex))
        }
        
        var queryCharacterSet = CharacterSet.urlQueryAllowed
        queryCharacterSet.remove(charactersIn: "=&+")
        let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: queryCharacterSet) ?? ""
        
        return ZMTransportRequest(getFromPath: "/search/contacts?q=\(encodedQuery)&size=\(fetchLimit)")
    }
    
}
