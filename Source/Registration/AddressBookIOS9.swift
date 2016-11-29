//
//  AddressBookIOS10.swift
//  zmessaging-cocoa
//
//  Created by Marco Conti on 29/11/16.
//  Copyright © 2016 Zeta Project Gmbh. All rights reserved.
//

import Foundation
import Contacts

/// iOS Contacts-based address book
@available(iOS 9.0, *)
class AddressBookIOS9 : AddressBook {
    
    let store = CNContactStore()
}

@available(iOS 9.0, *)
extension AddressBookIOS9 : AddressBookAccessor {
    
    static var keysToFetch : [CNKeyDescriptor] {
        return  [CNContactPhoneNumbersKey as CNKeyDescriptor,
                 CNContactEmailAddressesKey as CNKeyDescriptor,
                 CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
                 CNContactOrganizationNameKey as CNKeyDescriptor]
    }
    
    func rawContacts(matchingQuery query: String) -> [ContactRecord] {
        if !AddressBook.accessGranted() {
            return []
        }
        let predicate: NSPredicate = CNContact.predicateForContacts(matchingName: query.lowercased())
        guard let foundContacts = try? CNContactStore().unifiedContacts(matching: predicate, keysToFetch: AddressBookIOS9.keysToFetch) else {
            return []
        }
        return foundContacts
    }


    /// Enumerates the contacts, invoking the block for each contact.
    /// If the block returns false, it will stop enumerating them.
    internal func enumerateRawContacts(block: @escaping (ContactRecord) -> (Bool)) {
        let request = CNContactFetchRequest(keysToFetch: AddressBookIOS9.keysToFetch)
        request.sortOrder = .userDefault
        try! store.enumerateContacts(with: request) { (contact, stop) in
            let shouldContinue = block(contact)
            stop.initialize(to: ObjCBool(!shouldContinue))
        }
    }

    /// Number of contacts in the address book
    internal var numberOfContacts: UInt {
        return 0
    }
}




@available(iOS 9.0, *)
extension CNContact : ContactRecord {
    
    var rawEmails : [String] {
        return self.emailAddresses.map { $0.value as String }
    }
    
    var rawPhoneNumbers : [String] {
        return self.phoneNumbers.map { $0.value.stringValue }
    }
    
    var firstName : String {
        return self.givenName
    }
    
    var lastName : String {
        return self.familyName
    }
    
    var organization : String {
        return self.organizationName
    }
    
    var localIdentifier : String {
        return self.identifier
    }
}

extension ZMAddressBookContact {
    
    @available(iOS 9.0, *)
    convenience init?(contact: CNContact,
                      phoneNumberNormalizer: @escaping AddressBook.Normalizer,
                      emailNormalizer: @escaping AddressBook.Normalizer) {
        self.init()
        
        // names
        self.firstName = contact.givenName
        self.lastName = contact.familyName
        self.middleName = contact.middleName
        self.nickname = contact.nickname
        self.organization = contact.organizationName
        
        // email
        self.emailAddresses = contact.emailAddresses.flatMap { emailNormalizer($0.value as String) }
        
        // phone
        self.rawPhoneNumbers = contact.phoneNumbers.map { $0.value.stringValue }
        
        // normalize phone
        self.phoneNumbers = self.rawPhoneNumbers.flatMap { phoneNumberNormalizer($0) }
        
        // ignore contacts with no email nor phones
        guard self.emailAddresses.count > 0 || self.phoneNumbers.count > 0 else {
            return nil
        }
    }
}
