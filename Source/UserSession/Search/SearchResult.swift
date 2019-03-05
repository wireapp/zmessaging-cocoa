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

public struct SearchResult {
    public let contacts:      [ZMUser]
    public let teamMembers:   [Member]
    public let addressBook:   [ZMSearchUser]
    public let directory:     [ZMSearchUser]
    public let conversations: [ZMConversation]
    public let services:      [ServiceUser]
}

extension SearchResult {
    
    public init?(payload: [AnyHashable : Any], query: String, userSession: ZMUserSession) {
        guard let documents = payload["documents"] as? [[String : Any]] else {
            return nil
        }
        
        let isHandleQuery = query.hasPrefix("@")
        let queryWithoutAtSymbol = (isHandleQuery ? String(query[query.index(after: query.startIndex)...]) : query).lowercased()

        let filteredDocuments = documents.filter { (document) -> Bool in
            let name = document["name"] as? String
            let handle = document["handle"] as? String
            
            return !isHandleQuery || name?.hasPrefix("@") ?? true || handle?.contains(queryWithoutAtSymbol) ?? false
        }
        
        let searchUsers = ZMSearchUser.searchUsers(from: filteredDocuments, contextProvider: userSession)
        
        contacts = []
        teamMembers = []
        addressBook = []
        directory = searchUsers.filter({ !$0.isConnected && !$0.isTeamMember })
        conversations = []
        services = []
    }
    
    public init?(servicesPayload servicesFullPayload: [AnyHashable : Any], query: String, userSession: ZMUserSession) {
        guard let servicesPayload = servicesFullPayload["services"] as? [[String : Any]] else {
            return nil
        }
        
        let searchUsersServices = ZMSearchUser.searchUsers(from: servicesPayload, contextProvider: userSession)
        
        contacts = []
        teamMembers = []
        addressBook = []
        directory = []
        conversations = []
        services = searchUsersServices
    }
    
    func copy(on context: NSManagedObjectContext) -> SearchResult {
        
        let copiedContacts = contacts.compactMap { context.object(with: $0.objectID) as? ZMUser }
        let copiedTeamMembers = teamMembers.compactMap { context.object(with: $0.objectID) as? Member }
        let copiedConversations = conversations.compactMap { context.object(with: $0.objectID) as? ZMConversation }
        
        return SearchResult(contacts: copiedContacts, teamMembers: copiedTeamMembers, addressBook: addressBook, directory: directory, conversations: copiedConversations, services: services)
    }
    
    func union(withLocalResult result: SearchResult) -> SearchResult {
        return SearchResult(contacts: result.contacts, teamMembers: result.teamMembers, addressBook: result.addressBook, directory: directory, conversations: result.conversations, services: services)
    }
    
    func union(withServiceResult result: SearchResult) -> SearchResult {
        return SearchResult(contacts: contacts,
                            teamMembers: teamMembers,
                            addressBook: addressBook,
                            directory: directory,
                            conversations: conversations,
                            services: result.services)
    }
    
    func union(withDirectoryResult result: SearchResult) -> SearchResult {
        return SearchResult(contacts: contacts,
                            teamMembers: teamMembers,
                            addressBook: addressBook,
                            directory: result.directory,
                            conversations: conversations,
                            services: services)
    }
    
}
