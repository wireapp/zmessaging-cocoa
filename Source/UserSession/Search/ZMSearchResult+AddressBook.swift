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

/// This is used for testing only
var debug_searchResultAddressBookOverride : AddressBookAccessor? = nil

extension ZMSearchResult {
    
    /// Creates a new search result with the same results and additional
    /// results obtained by searching through the address book
    public func extendWithContactsFromAddressBook(_ query: String,
                                                  usersToMatch: [ZMUser],
                                                  userSession: ZMUserSession) -> ZMSearchResult {
        
        let addressBook = AddressBookSearch(addressBook: debug_searchResultAddressBookOverride)
        let queryContacts = Set(addressBook.contactsMatchingQuery(query))
        let queryUsers = Set(self.usersInContacts.map { $0.user })
        
        var matchedUsers : [ZMSearchUser] = []
        var localMatchedUsers : [ZMUser] = []
        
        addressBook.matchInAddressBook(usersToMatch).forEach { match in
            if let user = match.user , queryUsers.contains(user) && user.connection?.status == .accepted {
                if let contact = match.contact {
                    matchedUsers.append(ZMSearchUser(contact: contact, user: nil, userSession: userSession))
                } else {
                    localMatchedUsers.append(user)
                }
            } else if let contact = match.contact , queryContacts.contains(contact)
                && (match.user == nil || match.user?.connection?.status != .blocked) {
                matchedUsers.append(ZMSearchUser(contact: contact, user: match.user, userSession: userSession))
            }
        }
        
        matchedUsers.append(contentsOf: ZMSearchUser.users(with: localMatchedUsers, userSession: userSession) as [ZMSearchUser])
        
        return ZMSearchResult(usersInContacts: matchedUsers, usersInDirectory: self.usersInDirectory, groupConversations: self.groupConversations)
    }

}
