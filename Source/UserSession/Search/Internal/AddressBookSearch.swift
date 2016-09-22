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

/// Search for contacts in the address book
class AddressBookSearch {
    
    /// Maximum number of contacts to consider when matching/searching,
    /// for performance reasons
    fileprivate let maximumSearchRange : UInt = 3000
    
    /// Address book
    fileprivate let addressBook : AddressBookAccessor?
    
    init(addressBook : AddressBookAccessor? = nil) {
        self.addressBook = addressBook ?? AddressBook()
    }
}

// MARK: - Match contacts to users

struct Match {
    let user : ZMUser?
    let contact : ZMAddressBookContact?
}

extension AddressBookSearch {

    /// Returns a contact matching a user based on email address or phone number.
    func contactForUser(_ user: ZMUser) -> ZMAddressBookContact? {
        for contact in self.limitedContactsRange() {
            if contact.matches(user) {
                return contact
            }
        }
        return nil
    }
    
    /// Returns a list of match for users that have a corresponding contact
    /// in the address book
    func matchInAddressBook(_ users: [ZMUser]) -> [Match] {
        
        var unmatchedUsers = Set(users)
        
        let emailToUser : [String: ZMUser] = { _ in
            var dict = [String: ZMUser]()
            users.forEach({ (user) in
                guard let email = user.emailAddress else {
                    return
                }
                dict[email] = user
            })
            return dict
        }()
        
        let phoneToUser : [String: ZMUser] = { _ in
            var dict = [String: ZMUser]()
            users.forEach({ (user) in
                guard let phone = user.phoneNumber else {
                    return
                }
                dict[phone] = user
            })
            return dict
        }()
        
        return self.limitedContactsRange().map { (contact) -> Match in
            for email in contact.emailAddresses {
                if let user = emailToUser[email] {
                    unmatchedUsers.remove(user)
                    return Match(user: user, contact: contact)
                }
            }
            for phone in contact.phoneNumbers {
                if let user = phoneToUser[phone] {
                    unmatchedUsers.remove(user)
                    return Match(user: user, contact: contact)
                }
            }
            return Match(user: nil, contact: contact)
        }
        + unmatchedUsers.map { user -> Match in
            return Match(user: user, contact: nil)
        }
    }
}

// MARK: - Search contacts
extension AddressBookSearch {

    /// Returns contacts filtered by the query
    func contactsMatchingQuery(_ query: String) -> LazySequence<AnyIterator<ZMAddressBookContact>> {
        guard !query.isEmpty else {
            return self.limitedContactsRange().lazy
        }
        let predicate = NSPredicate(format: "SELF.name CONTAINS[cd] %@", query)
        return AnyIterator(limitedContactsRange().lazy.filter {
            return predicate.evaluate(with: $0)
        }.makeIterator()).lazy
    }
}

extension AddressBookSearch {
    
    /// Returns an iterator on contacts within the range limit
    fileprivate func limitedContactsRange() -> AnyIterator<ZMAddressBookContact> {
        guard let addressBook = self.addressBook else {
            return AnyIterator(Array<ZMAddressBookContact>().makeIterator())
        }
        return addressBook.iterate().elements(0..<maximumSearchRange).lazy.makeIterator()
    }
    
}

extension ZMAddressBookContact {
    
    /// Returns whether the contact shares email or phone with the user
    fileprivate func matches(_ user: ZMUser) -> Bool {
        if let email = user.emailAddress , self.emailAddresses.contains(email) {
            return true
        }
        
        if let phone = user.phoneNumber , self.phoneNumbers.contains(phone) {
            return true
        }
        return false
    }
}
