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

/// BE onboarding endpoint
private let onboardingEndpoint = "/onboarding/v3"

/// Maximum entries in an address book chunk
let maxEntriesInAddressBookChunk : UInt = 1000

/// Key to mark the address book as uploadable
private let addressBookNeedsToBeUploadedKey = "ZMAddressBookTranscoderNeedsToBeUploaded"

/// Last contact index to be uploaded
private let addressBookLastUploadedIndex = "ZMAddressBookTranscoderLastIndexUploaded"

/// This request sync generates request to upload the address book
/// It will upload only after `markAddressBookAsNeedingToBeUploaded` is called
@objc public final class AddressBookUploadRequestStrategy: AbstractRequestStrategy {
    
    /// Request sync to upload the address book
    fileprivate var requestSync : ZMSingleRequestSync!
    
    /// Encoded address book chunk
    fileprivate var encodedAddressBookChunkToUpload : EncodedAddressBookChunk? = nil
    
    /// Is the payload being generated? This is an async operation
    fileprivate var isGeneratingPayload : Bool = false
    
    /// Address book
    fileprivate let addressBookGenerator : ()->(AddressBookAccessor?)
    
    public override convenience init(withManagedObjectContext moc: NSManagedObjectContext, applicationStatus: ApplicationStatus) {
        self.init(managedObjectContext: moc, applicationStatus: applicationStatus, addressBookGenerator: { return AddressBook.factory() })
    }
    
    /// Use for testing only
    internal init(managedObjectContext moc: NSManagedObjectContext, applicationStatus: ApplicationStatus, addressBookGenerator: @escaping ()->(AddressBookAccessor?) = { return AddressBook.factory() }) {
        // notify of denied access
        if addressBookGenerator() == nil {
            NotificationInContext(name: failedToAccessAddressBookNotificationName, context: moc.notificationContext).post()
        }
        self.addressBookGenerator = addressBookGenerator
        super.init(withManagedObjectContext: moc, applicationStatus: applicationStatus)
        self.requestSync = ZMSingleRequestSync(singleRequestTranscoder: self, groupQueue: moc)
    }
    
    public override func nextRequestIfAllowed() -> ZMTransportRequest? {
        // already encoded? just send it
        if self.encodedAddressBookChunkToUpload != nil {
            self.requestSync.readyForNextRequestIfNotBusy()
            return self.requestSync.nextRequest()
        }
        
        self.generateAddressBookPayloadIfNeeded()
        return nil
    }
}

// MARK: - Request generation logic
extension AddressBookUploadRequestStrategy : ZMSingleRequestTranscoder {
    
    public func request(for sync: ZMSingleRequestSync) -> ZMTransportRequest? {
        guard sync == self.requestSync, let encodedChunk = self.encodedAddressBookChunkToUpload else {
            return nil
        }
        let contactCards : [[String: AnyObject]] = encodedChunk.otherContactsHashes
            .keys
            .sorted()
            .map { index -> [String:AnyObject] in
                let hashes = encodedChunk.otherContactsHashes[index]!
                return [
                    "card_id" : index as NSString,
                    "contact" : hashes as NSArray
                ]
        }
        
        let allLocalContactIDs = Set(encodedChunk.otherContactsHashes.keys)
        let payload : [String: Any] = ["cards" : contactCards]
        let request = ZMTransportRequest(path: onboardingEndpoint, method: .methodPOST, payload: payload as ZMTransportData?, shouldCompress: true)
        request.add(ZMCompletionHandler(on: self.managedObjectContext, block: {
            [weak self] response in
            self?.parse(addressBookResponse: response, expectedContactIDs: allLocalContactIDs)
            })
        )
        return request
    }
    
    public func didReceive(_ response: ZMTransportResponse, forSingleRequest sync: ZMSingleRequestSync) {
        // no op
    }
    
    private func parse(addressBookResponse response: ZMTransportResponse, expectedContactIDs: Set<String>) {
        if response.result == .success {
            
            if let payload = response.payload as? [String: AnyObject],
                let results = payload["results"] as? [[String: AnyObject]]
            {
                self.updateLocalUsers(cards: results, expectedContactIDs: expectedContactIDs)
            }
            
            self.addressBookNeedsToBeUploaded = false
            self.encodedAddressBookChunkToUpload = nil
        }
    }
    
    /// Parse the cards response and updates the local users
    private func updateLocalUsers(cards: [[String:AnyObject]], expectedContactIDs: Set<String>) {
        
        // do a single fetch for all users
        let userIds = cards.compactMap { ($0["id"] as? String).flatMap { UUID(uuidString: $0 ) } }
        let users = Array(ZMUser.users(withRemoteIDs: Set(userIds), in: managedObjectContext))
        
        let idToUsers = users.dictionary {
            return (key: $0.remoteIdentifier!, value: $0)
        }
        
        guard let addressBook = self.addressBookGenerator() else {
            return
        }
        
        // add new matches
        var missingIDs = Set(expectedContactIDs)
        cards.forEach {
            guard let userid = ($0["id"] as? String).flatMap({ UUID(uuidString: $0 )}),
                let contactIds = $0["cards"] as? [String]
            else { return }
            
            let user : ZMUser = idToUsers[userid] ?? {
                let newUser = ZMUser.insertNewObject(in: self.managedObjectContext)
                newUser.remoteIdentifier = userid
                newUser.needsToBeUpdatedFromBackend = true
                return newUser
            }()

            contactIds.forEach { contactId in
                missingIDs.remove(contactId)

                if user.addressBookEntry == nil {
                    user.addressBookEntry = AddressBookEntry.insertNewObject(in: self.managedObjectContext)
                }
                user.addressBookEntry?.localIdentifier = contactId
                user.addressBookEntry?.cachedName = addressBook.contact(identifier: contactId)?.displayName
            }
        }
        
        // now remove all address book entries for those users that were previously using the missing IDs
        if #available(iOS 10.0, *) {
            self.deleteEntriesForUsers(contactIDs: missingIDs)
        }
    }
    
    /// Remove address book entries for users previously matching the given contact IDs
    private func deleteEntriesForUsers(contactIDs: Set<String>) {
        let fetch = AddressBookEntry.fetchRequest()
        fetch.predicate = NSPredicate(format: "%K IN %@", AddressBookEntry.Fields.localIdentifier.rawValue, contactIDs)
        guard let entries = (try? self.managedObjectContext.fetch(fetch) as? [AddressBookEntry]) else {
            return
        }
        entries.forEach {
            self.managedObjectContext.delete($0)
        }
    }
    
    /// Checks if it needs to generate address book payload. If it does,
    /// it will start generating it asynchronously
    fileprivate func generateAddressBookPayloadIfNeeded() {
        
        guard self.addressBookNeedsToBeUploaded &&
            !self.isGeneratingPayload,
            let addressBook = self.addressBookGenerator() else {
                return
        }
        
        self.isGeneratingPayload = true
        let startIndex = self.lastUploadedCardIndex
        addressBook.encodeWithCompletionHandler(self.managedObjectContext,
                                                startingContactIndex: startIndex,
                                                maxNumberOfContacts: maxEntriesInAddressBookChunk)
        {
            [weak self] encodedChunk in
            guard let strongSelf = self else {
                return
            }
            strongSelf.isGeneratingPayload = false
            if let encodedChunk = encodedChunk {
                strongSelf.checkIfShouldUpload(encodedChunk)
            }
        }
    }
    
    fileprivate func checkIfShouldUpload(_ encodedChunk: EncodedAddressBookChunk) {
        
        if !encodedChunk.isEmpty {
            // not empty? we are uploading it!
            self.startUpload(encodedChunk)
        }
        
        // reached the end, I had 1000 contacts and I was trying to encode 1001st ?
        let shouldEncodeFirstChunkInstead = encodedChunk.isEmpty && !encodedChunk.isFirst
        
        if shouldEncodeFirstChunkInstead {
            self.lastUploadedCardIndex = 0
            self.generateAddressBookPayloadIfNeeded()
        } else if encodedChunk.isLast {
            self.lastUploadedCardIndex = 0
        } else {
            self.lastUploadedCardIndex = encodedChunk.includedContacts.upperBound
        }
    }
    
    /// Start uploading a given chunk
    fileprivate func startUpload(_ encodedChunk: EncodedAddressBookChunk) {
        self.encodedAddressBookChunkToUpload = encodedChunk
        RequestAvailableNotification.notifyNewRequestsAvailable(self)
    }
}

extension EncodedAddressBookChunk {
    
    /// Whether this is the last chunk and no following chunk needs to be uploaded after this one
    var isLast : Bool {
        return UInt(self.otherContactsHashes.count) < maxEntriesInAddressBookChunk
    }
    
    /// Whether this is the first chunk
    var isFirst : Bool {
        return self.includedContacts.lowerBound == 0
    }
    
    /// Whether the chunk is empty
    var isEmpty : Bool {
        return self.otherContactsHashes.isEmpty
    }
}

// MARK: - Marking for upload
extension AddressBook {
    /// Sets the address book as needing to be uploaded
    static func markAddressBookAsNeedingToBeUploaded(_ moc: NSManagedObjectContext) {
        self.markAddressBook(moc, needsToBeUploaded: true)
    }
    
    /// Sets whether the address book needs to be uploaded
    fileprivate static func markAddressBook(_ moc: NSManagedObjectContext, needsToBeUploaded: Bool) {
        moc.setPersistentStoreMetadata(NSNumber(value: needsToBeUploaded), key: addressBookNeedsToBeUploadedKey)
    }
    
    /// Whether the address book needs to be uploaded
    fileprivate static func addressBookNeedsToBeUploaded(_ moc: NSManagedObjectContext) -> Bool {
        return (moc.persistentStoreMetadata(forKey: addressBookNeedsToBeUploadedKey) as? NSNumber)?.boolValue == true
    }
}

extension AddressBookUploadRequestStrategy {
    
    /// Whether the address book needs to be uploaded
    fileprivate var addressBookNeedsToBeUploaded : Bool {
        get {
            return AddressBook.addressBookNeedsToBeUploaded(self.managedObjectContext)
        }
        set {
            AddressBook.markAddressBook(self.managedObjectContext, needsToBeUploaded: newValue)
        }
    }
    
    /// Index of last uploaded contact card
    /// - note: This value does not offers any guarantee on which cards
    /// where uploaded, just on the index on the card uploaded. Cards might have
    /// changed since last time and the index might be pointing to a different card.
    /// However, since we want to upload all cards and then restart from the first, we
    /// uploaded the same cards over and over anyway and will eventually go through the
    /// entire AB.
    fileprivate var lastUploadedCardIndex : UInt {
        get {
            return UInt((self.managedObjectContext
                .persistentStoreMetadata(forKey: addressBookLastUploadedIndex) as? NSNumber)?.intValue ?? 0)
        }
        set {
            self.managedObjectContext
                .setPersistentStoreMetadata(NSNumber(value: Int(newValue)), key: addressBookLastUploadedIndex)
        }
    }
}
