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
    fileprivate let phoneNormalizer : NBPhoneNumberUtil
    
    /// Closure used to generate iterator. Used in testing
    fileprivate let allPeopleClosure : AllPeopleClosure
    typealias AllPeopleClosure = (_ ref: ABAddressBook) -> (AnyIterator<ABRecord>)
    
    /// Closure to get number of people. Used in testing
    fileprivate let numberOfPeopleClosure : NumberOfPeopleClosure
    typealias NumberOfPeopleClosure = (_ ref: ABAddressBook) -> (Int)

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
        return ABAddressBookGetAuthorizationStatus() == .authorized
    }

}

// MARK: - Iterating contacts

/// Protocol that allow iterating the address book contacts
protocol AddressBookAccessor {
    
    /// Number of contacts in the address book
    var numberOfContacts : UInt {get}
    
    /// Iterator for contacts
    func iterate() -> LazySequence<AnyIterator<ZMAddressBookContact>>
    
    /// Encodes an arbitraty part the address book asynchronously. Will invoke the completion handler when done.
    /// - parameter groupQueue: group queue to enter while executing, and where to invoke callback
    /// - parameter completion: closure invoked when the address book encoding ended. It will receive nil parameter
    ///     if there are no contacts to upload
    /// - parameter maxNumberOfContacts: do not include more than this number of contacts
    /// - parameter startingContactIndex: include contacts starting from this index in the address book
    func encodeWithCompletionHandler(_ groupQueue: ZMSGroupQueue,
                                     startingContactIndex: UInt,
                                     maxNumberOfContacts: UInt,
                                     completion: @escaping (EncodedAddressBookChunk?)->()
    )
}

extension AddressBook : AddressBookAccessor {

    /// Number of contacts in the address book
    var numberOfContacts : UInt {
        return UInt(self.numberOfPeopleClosure(self.ref))
    }
    
    /// Returns a generator that will generate all elements of the address book
    func iterate() -> LazySequence<AnyIterator<ZMAddressBookContact>> {
        return AnyIterator(AddressBookIterator(
            phoneNumberNormalizer: { self.phoneNormalizer.normalize($0)?.validatedPhoneNumber },
            emailNormalizer: { $0.validatedEmail },
            allPeople: self.allPeopleClosure(self.ref)
        )).lazy
    }
    
    internal func encodeWithCompletionHandler(_ groupQueue: ZMSGroupQueue,
                                              startingContactIndex: UInt,
                                              maxNumberOfContacts: UInt,
                                              completion: @escaping (EncodedAddressBookChunk?) -> ()
        ) {
        // here we are explicitly capturing self, this is executed on a queue that is
        // never blocked indefinitely as this is the only function using it
        groupQueue.dispatchGroup.async(on: addressBookProcessingQueue) {
            
            let range: Range<UInt> = startingContactIndex..<(startingContactIndex+maxNumberOfContacts)
            let cards = self.generateContactCards(range)
            
            guard cards.count > 0 || startingContactIndex > 0 else {
                // this should happen if I have zero contacts
                groupQueue.performGroupedBlock({
                    completion(nil)
                })
                return
            }
            
            let cardsRange = startingContactIndex..<(startingContactIndex+UInt(cards.count))
            let encodedAB = EncodedAddressBookChunk(numberOfTotalContacts: self.numberOfContacts,
                                                    otherContactsHashes: cards,
                                                    includedContacts: cardsRange)
            groupQueue.performGroupedBlock({
                completion(encodedAB)
            })
        }
    }
    
    /// Generate contact cards for the given range of contacts
    fileprivate func generateContactCards(_ range: Range<UInt>) -> [[String]]
    {
        return self.iterate()
            .elements(range)
            .map { (contact: ZMAddressBookContact) -> [String] in
                return (contact.emailAddresses.map { $0.base64EncodedSHADigest })
                    + (contact.phoneNumbers.map { $0.base64EncodedSHADigest })
        }
    }
    
}

/// Iterator for address book
public final class AddressBookIterator : Sequence, IteratorProtocol {
    
    /// All people in the AB
    fileprivate let people : AnyIterator<ABRecord>
    
    /// normalizer for phone numbers
    fileprivate let phoneNumberNormalizer : AddressBook.Normalizer
    
    /// normalized for email
    fileprivate let emailNormalizer: AddressBook.Normalizer
    
    public typealias Element = ZMAddressBookContact
    
    open func next() -> ZMAddressBookContact? {
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
    
    fileprivate init(phoneNumberNormalizer: @escaping AddressBook.Normalizer,
                 emailNormalizer: @escaping AddressBook.Normalizer,
                 allPeople: AnyIterator<ABRecord>
    ) {
        self.people = allPeople
        self.phoneNumberNormalizer = phoneNumberNormalizer
        self.emailNormalizer = emailNormalizer
    }
}

// MARK: - Contact parsing

extension ZMAddressBookContact {
    
    convenience init?(ref: ABRecord,
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
        if let emailsRef = ABRecordCopyValue(ref, kABPersonEmailProperty)?.takeRetainedValue() , ABMultiValueGetCount(emailsRef) > 0 {
            self.emailAddresses = ((ABMultiValueCopyArrayOfAllValues(emailsRef).takeRetainedValue() as NSArray) as! [String])
                .flatMap { emailNormalizer($0) }
        } else {
            self.emailAddresses = []
        }
        
        // phone
        if let phonesRef = ABRecordCopyValue(ref, kABPersonPhoneProperty)?.takeRetainedValue() , ABMultiValueGetCount(phonesRef) > 0 {
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
    func normalize(_ phoneNumber: String) -> String? {
        let testingNumberPrefix = "+0"
        guard !phoneNumber.hasPrefix(testingNumberPrefix) else {
            return phoneNumber.validatedPhoneNumber
        }
    
        guard let parsedNumber = try? self.parse(withPhoneCarrierRegion: phoneNumber) else {
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
                .components(separatedBy: CharacterSet.decimalDigits.inverted)
                .joined(separator: "")) // remove all non-digit
        }
        
        var number : AnyObject? = self as AnyObject?
        do {
            try ZMPhoneNumberValidator.validateValue(&number)
            return number as? String
        } catch {
            return nil
        }
    }
    
    /// Returns a normalized email or nil
    var validatedEmail : String? {
        var email : AnyObject? = self as AnyObject?
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
    static fileprivate func checkAccessToAB(_ checkClosure: (()->(Bool))?) -> Bool {
        return checkClosure?() ?? AddressBook.userHasAuthorizedAccess
    }
    
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

// MARK: - Encoded address book chunk
struct EncodedAddressBookChunk {
    
    /// Total number of contacts in the address book
    let numberOfTotalContacts : UInt
    
    /// Data to upload for contacts other that the self user
    let otherContactsHashes : [[String]]
    
    /// Contacts included in this chuck, according to AB order
    let includedContacts : CountableRange<UInt>
}


// MARK: - Utilities
extension String {
    
    /// Returns the base64 encoded string of the SHA hash of the string
    var base64EncodedSHADigest : String {
        return self.data(using: String.Encoding.utf8)!.zmSHA256Digest().base64EncodedString(options: [])
    }
    
}


/// Private AB processing queue
private let addressBookProcessingQueue = DispatchQueue(label: "Address book processing", attributes: [])

extension Sequence {
    
    /// Returns the elements of the sequence in the positions indicated by the range
    func elements(_ range: Range<UInt>) -> AnyIterator<Self.Iterator.Element> {
        
        var generator = self.makeIterator()
        var count : UInt = 0
        
        return AnyIterator {
            
            while count < range.lowerBound {
                if generator.next() != nil {
                    count += 1
                    continue
                } else {
                    return nil
                }
            }
            if count == range.upperBound {
                return nil
            }
            count += 1
            return generator.next()
        }
    }
}
