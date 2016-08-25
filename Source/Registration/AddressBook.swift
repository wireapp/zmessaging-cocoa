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

/// Wraps the system address book to return `ZMAddressBookContact` when iterating, filtering out those
/// without a valid email or phone
@objc class AddressBook : NSObject {
    
    typealias Normalizer = (String)->(String?)
    typealias AccessCheck = ()->(Bool)
    
    /// Reference to the AB
    let ref : ABAddressBook
    
    /// normalizer for phone numbers
    private let phoneNormalizer : NBPhoneNumberUtil
    
    /// Closure used to generate iterator. Used in testing
    private let allPeopleClosure : AllPeopleClosure
    typealias AllPeopleClosure = (ref: ABAddressBook) -> (AnyGenerator<ABRecordRef>)
    
    /// Closure to get number of people. Used in testing
    private let numberOfPeopleClosure : NumberOfPeopleClosure
    typealias NumberOfPeopleClosure = (ref: ABAddressBook) -> (Int)

    /// Address book. Will fail if it has no authorization to access AB
    /// - parameter allPeopleClosure: custom function to return an iterator (used for testing)
    /// - parameter addressBookAccessCheck: custom function to check if user granted access to AB (used for testing)
    /// - parameter numberOfPeopleClosure: custom function to retrieve the number of people in the AB (used for testing)
    init?(allPeopleClosure: AllPeopleClosure? = nil,
          addressBookAccessCheck: AccessCheck? = nil,
          numberOfPeopleClosure: NumberOfPeopleClosure? = nil) {
        
        // fail if no access
        guard AddressBook.checkAccessToAB(addressBookAccessCheck) else {
            return nil
        }
        self.ref = ABAddressBookCreate().takeRetainedValue()
        self.allPeopleClosure = AddressBook.customOrDefaultAllPeopleClosure(allPeopleClosure)
        self.numberOfPeopleClosure = AddressBook.customOrDefaultNumberOfPeopleClosure(numberOfPeopleClosure)
        self.phoneNormalizer = NBPhoneNumberUtil()
    }
}

// MARK: - Debugging
extension AddressBook {
    
    override var description : String {
        return "AB with \(self.numberOfContacts) contacts"
    }
    
}

// MARK: - Access

extension AddressBook {
    /// Whether the use authorized access to the AB
    static var userHasAuthorizedAccess : Bool {
        return ABAddressBookGetAuthorizationStatus() == .Authorized
    }

}

// MARK: - Iterating contacts

/// Protocol that allow iterating the address book contacts
protocol AddressBookAccessor {
    
    /// Number of contacts in the address book
    var numberOfContacts : UInt {get}
    
    /// Iterator for contacts
    func iterate() -> LazySequence<AnyGenerator<ZMAddressBookContact>>
    
    /// Encodes an arbitraty part the address book asynchronously. Will invoke the completion handler when done.
    /// - parameter groupQueue: group queue to enter while executing, and where to invoke callback
    /// - parameter completion: closure invoked when the address book encoding ended. It will receive nil parameter
    ///     if there are no contacts to upload
    /// - parameter maxNumberOfContacts: do not include more than this number of contacts
    /// - parameter startingContactIndex: include contacts starting from this index in the address book
    func encodeWithCompletionHandler(groupQueue: ZMSGroupQueue,
                                     startingContactIndex: UInt,
                                     maxNumberOfContacts: UInt,
                                     completion: (EncodedAddressBookChunk?)->()
    )
}

extension AddressBook : AddressBookAccessor {
    
    /// Number of contacts in the address book
    var numberOfContacts : UInt {
        return UInt(self.numberOfPeopleClosure(ref: self.ref))
    }
    
    /// Returns a generator that will generate all elements of the address book
    func iterate() -> LazySequence<AnyGenerator<ZMAddressBookContact>> {
        return AnyGenerator(AddressBookIterator(
            phoneNumberNormalizer: { self.phoneNormalizer.normalize($0)?.validatedPhoneNumber },
            emailNormalizer: { $0.validatedEmail },
            allPeople: self.allPeopleClosure(ref: self.ref)
        )).lazy
    }
}

/// Iterator for address book
public class AddressBookIterator : SequenceType, GeneratorType {
    
    /// All people in the AB
    private let people : AnyGenerator<ABRecordRef>
    
    /// normalizer for phone numbers
    private let phoneNumberNormalizer : AddressBook.Normalizer
    
    /// normalized for email
    private let emailNormalizer: AddressBook.Normalizer
    
    public typealias Element = ZMAddressBookContact
    
    public func next() -> ZMAddressBookContact? {
        var recordRef = self.people.next()
        
        while recordRef != nil {
            if let parsed = ZMAddressBookContact(ref: recordRef!,
                                        phoneNumberNormalizer: self.phoneNumberNormalizer,
                                        emailNormalizer: self.emailNormalizer) {
                return parsed
            } else {
                recordRef = self.people.next()
            }
        }
        return nil
    }
    
    private init(phoneNumberNormalizer: AddressBook.Normalizer,
                 emailNormalizer: AddressBook.Normalizer,
                 allPeople: AnyGenerator<ABRecordRef>
    ) {
        self.people = allPeople
        self.phoneNumberNormalizer = phoneNumberNormalizer
        self.emailNormalizer = emailNormalizer
    }
}

// MARK: - Contact parsing

extension ZMAddressBookContact {
    
    convenience init?(ref: ABRecordRef,
                      phoneNumberNormalizer: AddressBook.Normalizer,
                      emailNormalizer: AddressBook.Normalizer) {
        self.init()
        
        // names
        self.firstName = ABRecordCopyValue(ref, kABPersonFirstNameProperty)?.takeRetainedValue() as? String
        self.lastName = ABRecordCopyValue(ref, kABPersonLastNameProperty)?.takeRetainedValue() as? String
        self.middleName = ABRecordCopyValue(ref, kABPersonMiddleNameProperty)?.takeRetainedValue() as? String
        self.nickname = ABRecordCopyValue(ref, kABPersonNicknameProperty)?.takeRetainedValue() as? String
        self.organization = ABRecordCopyValue(ref, kABPersonOrganizationProperty)?.takeRetainedValue() as? String
        
        // email
        if let emailsRef = ABRecordCopyValue(ref, kABPersonEmailProperty)?.takeRetainedValue() where ABMultiValueGetCount(emailsRef) > 0 {
            self.emailAddresses = ((ABMultiValueCopyArrayOfAllValues(emailsRef).takeRetainedValue() as NSArray) as! [String])
                .flatMap { emailNormalizer($0) }
        } else {
            self.emailAddresses = []
        }
        
        // phone
        if let phonesRef = ABRecordCopyValue(ref, kABPersonPhoneProperty)?.takeRetainedValue() where ABMultiValueGetCount(phonesRef) > 0 {
            self.rawPhoneNumbers = (ABMultiValueCopyArrayOfAllValues(phonesRef).takeRetainedValue() as NSArray) as! [String]
        } else {
            self.rawPhoneNumbers = []
        }
        
        // normalize phone
        self.phoneNumbers = self.rawPhoneNumbers.flatMap { phoneNumberNormalizer($0) }
        
        // ignore contacts with no email nor phones
        guard self.emailAddresses.count > 0 || self.phoneNumbers.count > 0 else {
            return nil
        }
    }
}

// MARK: - Phone number and email normalization


extension NBPhoneNumberUtil {
    
    /// Returns a normalized version of the phone number, or nil 
    /// if the phone number was not normalizable.
    /// - note: numbers starting with "+0", a prefix that is not
    /// assigned to any real number, are considered test numbers
    /// used for QA automation and will always be accepted, without being
    /// normalized through the normalization library but just sanitized 
    /// from any non-numberic character
    func normalize(phoneNumber: String) -> String? {
        let testingNumberPrefix = "+0"
        guard !phoneNumber.hasPrefix(testingNumberPrefix) else {
            return phoneNumber.validatedPhoneNumber
        }
    
        guard let parsedNumber = try? self.parseWithPhoneCarrierRegion(phoneNumber) else {
            return nil
        }
        guard let normalizedNumber = try? self.format(parsedNumber, numberFormat: .E164) else {
            return nil
        }
        return normalizedNumber
    }
    
}

extension String {
    
    /// Returns a normalized phone number or nil
    var validatedPhoneNumber : String? {
        
        // allow +0 numbers
        if self.hasPrefix("+0") {
            return "+" + (self
                .componentsSeparatedByCharactersInSet(NSCharacterSet.decimalDigitCharacterSet().invertedSet)
                .joinWithSeparator("")) // remove all non-digit
        }
        
        var number : AnyObject? = self
        do {
            try ZMPhoneNumberValidator.validateValue(&number)
            return number as? String
        } catch {
            return nil
        }
    }
    
    /// Returns a normalized email or nil
    var validatedEmail : String? {
        var email : AnyObject? = self
        do {
            try ZMEmailAddressValidator.validateValue(&email)
            return email as? String
        } catch {
            return nil
        }
    }
}

// MARK: - Default behaviour (test injection)

extension AddressBook {
    
    /// Uses the passed in closure, or the standard method it the closure is nil, to
    /// check if the AB access was granted. Returns whether it was granted.
    static private func checkAccessToAB(checkClosure: (()->(Bool))?) -> Bool {
        return checkClosure?() ?? AddressBook.userHasAuthorizedAccess
    }
    
    /// Returns either the custom passed closure to get all people or, if the passed generating function is nil,
    /// the standard function
    static private func customOrDefaultAllPeopleClosure(custom: AllPeopleClosure?) -> AllPeopleClosure {
        return custom != nil ? custom! : { AnyGenerator((ABAddressBookCopyArrayOfAllPeople($0).takeRetainedValue() as [ABRecordRef]).generate()) }
    }
    
    /// Returns either the custom passed closure to get the number of people or, if the passed generating function is nil,
    /// the standard function
    static private func customOrDefaultNumberOfPeopleClosure(custom: NumberOfPeopleClosure?) -> NumberOfPeopleClosure {
        return custom != nil ? custom! : { ABAddressBookGetPersonCount($0) }
    }
}