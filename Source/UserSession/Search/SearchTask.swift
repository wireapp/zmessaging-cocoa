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

public class SearchTask {
    
    public typealias ResultHandler = (_ result: SearchResult, _ isCompleted: Bool) -> Void
 
    fileprivate let session: ZMUserSession
    fileprivate let context: NSManagedObjectContext
    fileprivate let request: SearchRequest
    fileprivate var directoryTaskIdentifier: ZMTaskIdentifier?
    fileprivate var handleTaskIdentifier: ZMTaskIdentifier?
    fileprivate var servicesTaskIdentifier: ZMTaskIdentifier?
    fileprivate var resultHandlers: [ResultHandler] = []
    fileprivate var result: SearchResult = SearchResult(contacts: [], teamMembers: [], addressBook: [],  directory: [], conversations: [], services: [])
    
    fileprivate var tasksRemaining = 0 {
        didSet {
            // only trigger handles if decrement to 0
            if oldValue > tasksRemaining {
                let isCompleted = tasksRemaining == 0
                resultHandlers.forEach { $0(result, isCompleted) }
                
                if isCompleted {
                    resultHandlers.removeAll()
                }
            }
        }
    }
    
    public init(request: SearchRequest, context: NSManagedObjectContext, session: ZMUserSession) {
        self.request = request
        self.session = session
        self.context = context
    }
    
    /// Add a result handler
    public func onResult(_ resultHandler : @escaping ResultHandler) {
        resultHandlers.append(resultHandler)
    }
    
    /// Cancel a previously started task
    public func cancel() {
        resultHandlers.removeAll()
        
        directoryTaskIdentifier.flatMap(session.transportSession.cancelTask)
        servicesTaskIdentifier.flatMap(session.transportSession.cancelTask)
        handleTaskIdentifier.flatMap(session.transportSession.cancelTask)
        
        tasksRemaining = 0
    }
    
    /// Start the search task. Results will be sent to the result handlers
    /// added via the `onResult()` method.
    public func start() {
        performLocalSearch()
        performRemoteSearch()
        performRemoteSearchForTeamUser()
        performRemoteSearchForServices()
    }
}

extension SearchTask {
    
    func performLocalSearch() {
        tasksRemaining += 1
        
        context.performGroupedBlock {
            
            var team : Team? = nil
            if let teamObjectID = self.request.team?.objectID {
                team = (try? self.context.existingObject(with: teamObjectID)) as? Team
            }
            
            let connectedUsers = self.request.searchOptions.contains(.contacts) ? self.connectedUsers(matchingQuery: self.request.query) : []
            let teamMembers = self.request.searchOptions.contains(.teamMembers) ? self.teamMembers(matchingQuery: self.request.query, team: team) : []
            let conversations = self.request.searchOptions.contains(.conversations) ? self.conversations(matchingQuery: self.request.query) : []
            let result = SearchResult(contacts: connectedUsers, teamMembers: teamMembers, addressBook: [], directory: [], conversations: conversations, services: [])
            
            self.session.managedObjectContext.performGroupedBlock {
                self.result = self.result.union(withLocalResult: result.copy(on: self.session.managedObjectContext))
                
                if self.request.searchOptions.contains(.addressBook) {
                    self.result = self.result.extendWithContactsFromAddressBook(self.request.query, userSession: self.session)
                }
                
                self.tasksRemaining -= 1
            }
        }
    }
    
    func teamMembers(matchingQuery query : String, team: Team?) -> [Member] {
        var result =  team?.members(matchingQuery: query) ?? []
        
        if request.searchOptions.contains(.onlyIncludeActiveTeamMembers) {
            let activeConversations = ZMUser.selfUser(in: context).activeConversations
            let activeContacts = Set(activeConversations.flatMap({ $0.activeParticipants }))
            
            result = result.filter({
                if let user = $0.user {
                    return activeContacts.contains(user)
                } else {
                    return false
                }
            })
        }
        
        return result
    }
    
    func connectedUsers(matchingQuery query: String) -> [ZMUser] {
        let fetchRequest = ZMUser.sortedFetchRequest(with: ZMUser.predicateForConnectedUsers(withSearch: query))
        return context.executeFetchRequestOrAssert(fetchRequest) as? [ZMUser] ?? []
    }
    
    func conversations(matchingQuery query: String) -> [ZMConversation] {
        let fetchRequest = ZMConversation.sortedFetchRequest(with: ZMConversation.predicate(forSearchQuery: query))
        fetchRequest?.sortDescriptors = [NSSortDescriptor(key: ZMNormalizedUserDefinedNameKey, ascending: true)]
        var conversations = context.executeFetchRequestOrAssert(fetchRequest) as? [ZMConversation] ?? []
        
        if query.hasPrefix("@") {
            // if we are searching for a username only include conversations with matching displayName
            conversations = conversations.filter { $0.displayName.contains(query)}
        }
        
        let matchingPredicate = ZMConversation.userDefinedNamePredicate(forSearch: query)
        var matching : [ZMConversation] = []
        var nonMatching : [ZMConversation] = []
        
        // re-sort conversations without a matching userDefinedName to the end of the result list
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
        guard request.searchOptions.contains(.directory) else { return }
        
        tasksRemaining += 1
        
        context.performGroupedBlock {
            let request = type(of: self).searchRequestInDirectory(withQuery: self.request.query)
            
            request.add(ZMCompletionHandler(on: self.session.managedObjectContext, block: { [weak self] (response) in
                
                defer {
                    self?.tasksRemaining -= 1
                }
                
                guard
                    let session = self?.session,
                    let query = self?.request.query,
                    let payload = response.payload?.asDictionary(),
                    let result = SearchResult(payload: payload, query: query, userSession: session)
                else {
                    return
                }
                
                if let updatedResult = self?.result.union(withDirectoryResult: result) {
                    self?.result = updatedResult
                }
            }))
            
            request.add(ZMTaskCreatedHandler(on: self.context, block: { [weak self] (taskIdentifier) in
                self?.directoryTaskIdentifier = taskIdentifier
            }))
            
            self.session.transportSession.enqueueOneTime(request)
        }
    }
    
    static func searchRequestInDirectory(withQuery query : String, fetchLimit: Int = 10) -> ZMTransportRequest {
        var query = query
        
        if query.hasPrefix("@") {
            query = String(query[query.index(after: query.startIndex)...])
        }
        
        var url = URLComponents()
        url.path = "/search/contacts"
        url.queryItems = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "size", value: String(fetchLimit))]
        let urlStr = url.string?.replacingOccurrences(of: "+", with: "%2B") ?? ""
        return ZMTransportRequest(getFromPath: urlStr)
    }
    
}

extension SearchTask {
    
    func performRemoteSearchForTeamUser() {
        guard request.searchOptions.contains(.directory) else { return }
        
        tasksRemaining += 1
        
        context.performGroupedBlock {
            let request = type(of: self).searchRequestInDirectory(withHandle: self.request.query)
            
            request.add(ZMCompletionHandler(on: self.session.managedObjectContext, block: { [weak self] (response) in
                
                defer {
                    self?.tasksRemaining -= 1
                }
                
                guard
                    let session = self?.session,
                    let query = self?.request.query,
                    let payload = response.payload?.asArray(),
                    let userPayload = (payload.first as? ZMTransportData)?.asDictionary()
                    else {
                        return
                }
                
                guard
                    let handle = userPayload["handle"] as? String,
                    let name = userPayload["name"] as? String,
                    let id = userPayload["id"] as? String
                    else {
                        return
                }
                
                let document = ["handle": handle, "name": name, "id": id]
                let documentPayload = ["documents": [document]]
                guard let result = SearchResult(payload: documentPayload, query: query, userSession: session) else {
                    return
                }
                
                if let user = result.directory.first, !user.isSelfUser {
                    if let prevResult = self?.result {
                        // prepend result to prevResult only if it doesn't contain it
                        if !prevResult.directory.contains(user) {
                            self?.result = SearchResult(
                                contacts: prevResult.contacts,
                                teamMembers: prevResult.teamMembers,
                                addressBook: prevResult.addressBook,
                                directory: result.directory + prevResult.directory,
                                conversations: prevResult.conversations,
                                services: prevResult.services
                            )
                        }
                    } else {
                        self?.result = result
                    }
                }
                
            }))
            
            request.add(ZMTaskCreatedHandler(on: self.context, block: { [weak self] (taskIdentifier) in
                self?.handleTaskIdentifier = taskIdentifier
            }))
            
            self.session.transportSession.enqueueOneTime(request)
        }
    }
    
    static func searchRequestInDirectory(withHandle handle : String) -> ZMTransportRequest {
        var handle = handle.lowercased()
        
        if handle.hasPrefix("@") {
            handle = String(handle[handle.index(after: handle.startIndex)...])
        }
        
        var url = URLComponents()
        url.path = "/users"
        url.queryItems = [URLQueryItem(name: "handles", value: handle)]
        let urlStr = url.string?.replacingOccurrences(of: "+", with: "%2B") ?? ""
        return ZMTransportRequest(getFromPath: urlStr)
    }
}

extension SearchTask {
    
    func performRemoteSearchForServices() {
        guard request.searchOptions.contains(.services) else { return }
        
        tasksRemaining += 1

        context.performGroupedBlock {
            let selfUser = ZMUser.selfUser(in: self.context)
            guard let teamIdentifier = selfUser.team?.remoteIdentifier else { return }

            let request = type(of: self).servicesSearchRequest(teamIdentifier: teamIdentifier, query: self.request.query)
            
            request.add(ZMCompletionHandler(on: self.session.managedObjectContext, block: { [weak self] (response) in
                
                defer {
                    self?.tasksRemaining -= 1
                }
                
                guard
                    let session = self?.session,
                    let query = self?.request.query,
                    let payload = response.payload?.asDictionary(),
                    let result = SearchResult(servicesPayload: payload, query: query, userSession: session)
                    else {
                        return
                }
                
                if let updatedResult = self?.result.union(withServiceResult: result) {
                    self?.result = updatedResult
                }
            }))
            
            request.add(ZMTaskCreatedHandler(on: self.context, block: { [weak self] (taskIdentifier) in
                self?.servicesTaskIdentifier = taskIdentifier
            }))
            
            self.session.transportSession.enqueueOneTime(request)
        }
    }
    
    static func servicesSearchRequest(teamIdentifier: UUID, query: String) -> ZMTransportRequest {
        var url = URLComponents()
        url.path = "/teams/\(teamIdentifier.transportString())/services/whitelisted"

        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedQuery.isEmpty {
            url.queryItems = [URLQueryItem(name: "prefix", value: trimmedQuery)]
        }
        let urlStr = url.string?.replacingOccurrences(of: "+", with: "%2B") ?? ""
        return ZMTransportRequest(getFromPath: urlStr)
    }
}
