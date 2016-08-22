//
//  AddressbookEncoder.swift
//  zmessaging-cocoa
//
//  Created by Marco Conti on 15/08/16.
//  Copyright © 2016 Zeta Project Gmbh. All rights reserved.
//

import Foundation
import ZMUtilities

/// Mark: - Encoding
extension AddressBook {
    
    func encodeWithCompletionHandler(groupQueue: ZMSGroupQueue,
                                     startingContactIndex: UInt,
                                     maxNumberOfContacts: UInt,
                                     completion: (EncodedAddressBookChunk?)->()
        ) {
        groupQueue.dispatchGroup.asyncOnQueue(addressBookProcessingQueue) { [weak self] in
            guard let strongSelf = self else {
                return
            }
            
            let range = startingContactIndex..<(startingContactIndex+maxNumberOfContacts)
            let cards = strongSelf.generateContactCards(range)
            guard cards.count > 0 else {
                groupQueue.performGroupedBlock({
                    completion(nil)
                })
                return
            }
            let cardsRange = startingContactIndex..<(startingContactIndex+UInt(cards.count))
            let encodedAB = EncodedAddressBookChunk(numberOfTotalContacts: strongSelf.numberOfContacts,
                                                    otherContactsHashes: cards,
                                                    includedContacts: cardsRange)
            groupQueue.performGroupedBlock({ 
                completion(encodedAB)
            })
        }
    }
    
    /// Generate contact cards for the given range of contacts
    private func generateContactCards(range: Range<UInt>) -> [[String]]
    {
        return self.iterate()
            .elements(range)
            .map { (contact: ZMAddressBookContact) -> [String] in
                return (contact.emailAddresses.map { $0.base64EncodedSHADigest })
                    + (contact.phoneNumbers.map { $0.base64EncodedSHADigest })
            }   
    }
}

// MARK: - Encoded address book chunk
struct EncodedAddressBookChunk {
    
    /// Total number of contacts in the address book
    let numberOfTotalContacts : UInt
    
    /// Data to upload for contacts other that the self user
    let otherContactsHashes : [[String]]
    
    /// Contacts included in this chuck, according to AB order
    let includedContacts : Range<UInt>
}


// MARK: - Utilities
extension String {
    
    /// Returns the base64 encoded string of the SHA hash of the string
    var base64EncodedSHADigest : String {
        return self.dataUsingEncoding(NSUTF8StringEncoding)!.zmSHA256Digest().base64EncodedStringWithOptions([])
    }
    
}


/// Private AB processing queue
private let addressBookProcessingQueue = dispatch_queue_create("Address book processing", DISPATCH_QUEUE_SERIAL)

extension SequenceType {
    
    /// Returns the elements of the sequence in the positions indicated by the range
    func elements(range: Range<UInt>) -> Array<Self.Generator.Element> {
        var count : UInt = 0
        var selectedElements : Array<Self.Generator.Element> = []
        for element in self {
            defer {
                count += 1
            }
            if count < range.startIndex {
                continue
            }
            if count == range.endIndex {
                break
            }
            selectedElements.append(element)
        }
        return selectedElements
    }
}
