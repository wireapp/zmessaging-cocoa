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
import AddressBook
import libPhoneNumber

/// iOS AddressBook-based address book
class AddressBookIOS8 : AddressBook {
    
    /// Reference to the AB
    let ref : ABAddressBook
    
    /// Closure used to generate iterator. Used in testing
    fileprivate let allPeopleClosure : AllPeopleClosure
    typealias AllPeopleClosure = (_ ref: ABAddressBook) -> (AnyIterator<ABRecord>)
    
    /// Closure to get number of people. Used in testing
    fileprivate let numberOfPeopleClosure : NumberOfPeopleClosure
    typealias NumberOfPeopleClosure = (_ ref: ABAddressBook) -> (Int)

    /// Address book
    /// - parameter allPeopleClosure: custom function to return an iterator (used for testing)
    /// - parameter addressBookAccessCheck: custom function to check if user granted access to AB (used for testing)
    /// - parameter numberOfPeopleClosure: custom function to retrieve the number of people in the AB (used for testing)
    init(allPeopleClosure: AllPeopleClosure? = nil,
          addressBookAccessCheck: AddressBook.AccessCheck? = nil,
          numberOfPeopleClosure: NumberOfPeopleClosure? = nil) {
        
        self.ref = ABAddressBookCreate().takeRetainedValue()
        self.allPeopleClosure = AddressBookIOS8.customOrDefaultAllPeopleClosure(allPeopleClosure)
        self.numberOfPeopleClosure = AddressBookIOS8.customOrDefaultNumberOfPeopleClosure(numberOfPeopleClosure)
    }
}

// MARK: - Debugging
extension AddressBookIOS8 : CustomStringConvertible {
    
    var description : String {
        return "AB with \(self.numberOfContacts) contacts"
    }
    
}

// MARK: - Iterating contacts

extension AddressBookIOS8 : AddressBookAccessor {
    
    /// Gets a specific address book user by the local address book indentifier
    internal func contact(identifier: String) -> ContactRecord? {
        return nil
    }

    
    /// Returns contacts matching search query
    func rawContacts(matchingQuery: String) -> [ContactRecord] {
        return self.firstRawContacts(number: addressBookContactsSearchLimit).filter {
            guard !matchingQuery.isEmpty else {
                return true
            }
            return $0.displayName.range(of: matchingQuery, options: .caseInsensitive) != .none
        }
    }

    /// Enumerates the contacts, invoking the block for each contact.
    /// If the block returns false, it will stop enumerating them.
    func enumerateRawContacts(block: @escaping (ContactRecord) -> (Bool)) {
        for recordRef in self.allPeopleClosure(self.ref) {
            if !block(ABRecordWrapper(ref: recordRef)) {
                break
            }
        }
    }

    /// Number of contacts in the address book
    var numberOfContacts : UInt {
        return UInt(self.numberOfPeopleClosure(self.ref))
    }
}

// MARK: - Contact parsing

struct ABRecordWrapper : ContactRecord {
    
    let ref : ABRecord
    
    var firstName: String {
        return ABRecordCopyValue(ref, kABPersonFirstNameProperty)?.takeRetainedValue() as? String ?? ""
    }
    
    var lastName: String {
        return ABRecordCopyValue(ref, kABPersonLastNameProperty)?.takeRetainedValue() as? String ?? ""
    }
    
    var middleName : String {
        return ABRecordCopyValue(ref, kABPersonMiddleNameProperty)?.takeRetainedValue() as? String ?? ""
    }
    
    var nickname : String {
        return ABRecordCopyValue(ref, kABPersonNicknameProperty)?.takeRetainedValue() as? String ?? ""
    }
    
    var organization : String {
        return ABRecordCopyValue(ref, kABPersonOrganizationProperty)?.takeRetainedValue() as? String ?? ""
    }
    
    var rawEmails: [String] {
        if let emailsRef = ABRecordCopyValue(ref, kABPersonEmailProperty)?.takeRetainedValue() , ABMultiValueGetCount(emailsRef) > 0 {
            return ((ABMultiValueCopyArrayOfAllValues(emailsRef).takeRetainedValue() as NSArray) as! [String])
        } else {
            return []
        }
    }
    
    var rawPhoneNumbers: [String] {
        if let phonesRef = ABRecordCopyValue(ref, kABPersonPhoneProperty)?.takeRetainedValue() , ABMultiValueGetCount(phonesRef) > 0 {
            return (ABMultiValueCopyArrayOfAllValues(phonesRef).takeRetainedValue() as NSArray) as! [String]
        } else {
            return []
        }
    }
    
    var localIdentifier: String {
        let id = ABRecordGetRecordID(ref)
        return "\(id)"
    }
}

// MARK: - Default behaviour (test injection)

extension AddressBookIOS8 {
    
    /// Returns either the custom passed closure to get all people or, if the passed generating function is nil,
    /// the standard function
    static fileprivate func customOrDefaultAllPeopleClosure(_ custom: AllPeopleClosure?) -> AllPeopleClosure {
        return custom != nil ? custom! : { AnyIterator((ABAddressBookCopyArrayOfAllPeople($0).takeRetainedValue() as [ABRecord]).makeIterator()) }
    }
    
    /// Returns either the custom passed closure to get the number of people or, if the passed generating function is nil,
    /// the standard function
    static fileprivate func customOrDefaultNumberOfPeopleClosure(_ custom: NumberOfPeopleClosure?) -> NumberOfPeopleClosure {
        return custom != nil ? custom! : { ABAddressBookGetPersonCount($0) }
    }
}
