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
@objc public final class AddressBookUploadRequestStrategy: NSObject {
    
    /// Auth status to know whether we can make requests
    fileprivate let authenticationStatus : AuthenticationStatusProvider
    
    /// Client status to know whether we can make requests
    fileprivate let clientRegistrationStatus : ZMClientClientRegistrationStatusProvider
    
    /// Managed object context where to perform all operations
    fileprivate let managedObjectContext: NSManagedObjectContext
    
    /// Request sync to upload the address book
    fileprivate var requestSync : ZMSingleRequestSync!
    
    /// Encoded address book chunk
    fileprivate var encodedAddressBookChunkToUpload : EncodedAddressBookChunk? = nil
    
    /// Is the payload being generated? This is an async operation
    fileprivate var isGeneratingPayload : Bool = false
    
    /// Address book analytics events tracker
    fileprivate let tracker : AddressBookTracker
    
    /// Address book
    fileprivate let addressBookGenerator : ()->(AddressBookAccessor?)
    
    public convenience init(authenticationStatus: AuthenticationStatusProvider,
        clientRegistrationStatus: ZMClientClientRegistrationStatusProvider,
        moc: NSManagedObjectContext)
    {
        
        self.init(authenticationStatus: authenticationStatus,
            clientRegistrationStatus: clientRegistrationStatus,
            managedObjectContext: moc
        )
    }
    
    init(authenticationStatus: AuthenticationStatusProvider,
                clientRegistrationStatus: ZMClientClientRegistrationStatusProvider,
                managedObjectContext: NSManagedObjectContext,
                addressBookGenerator: @escaping ()->(AddressBookAccessor?) = { return AddressBook() },
                tracker: AddressBookTracker? = nil
                )
    {
        // notify of denied access
        if addressBookGenerator() == nil {
            NotificationCenter.default.post(name: Notification.Name(rawValue: failedToAccessAddressBookNotificationName), object: nil)
        }
        
        self.authenticationStatus = authenticationStatus
        self.clientRegistrationStatus = clientRegistrationStatus
        self.managedObjectContext = managedObjectContext
        self.addressBookGenerator = addressBookGenerator
        self.tracker = tracker ?? AddressBookAnalytics(analytics: managedObjectContext.analytics, managedObjectContext: managedObjectContext)
        super.init()
        self.requestSync = ZMSingleRequestSync(singleRequestTranscoder: self, managedObjectContext: managedObjectContext)
    }
}

// MARK: - Request generation logic
extension AddressBookUploadRequestStrategy : RequestStrategy, ZMSingleRequestTranscoder {
    
    public func nextRequest() -> ZMTransportRequest? {
        guard self.authenticationStatus.currentPhase == .authenticated &&
            self.clientRegistrationStatus.clientIsReadyForRequests else {
                return nil
        }
        
        // already encoded? just send it
        if self.encodedAddressBookChunkToUpload != nil {
            self.requestSync.readyForNextRequestIfNotBusy()
            return self.requestSync.nextRequest()
        }
        
        self.generateAddressBookPayloadIfNeeded()
        return nil
    }
    
    public func request(for sync: ZMSingleRequestSync!) -> ZMTransportRequest! {
        guard sync == self.requestSync, let encodedChunk = self.encodedAddressBookChunkToUpload else {
            return nil
        }
        let contactCards = encodedChunk.otherContactsHashes
            .enumerated()
            .map { (index, hashes) -> [String:AnyObject] in
                return [
                    "card_id" : "\(encodedChunk.includedContacts.lowerBound + UInt(index))" as AnyObject,
                    "contact" : hashes as AnyObject
                ]
        }
        let payload = ["cards" : contactCards, "self" : []]
        self.tracker.tagAddressBookUploadStarted(encodedChunk.numberOfTotalContacts)
        return ZMTransportRequest(path: onboardingEndpoint, method: .methodPOST, payload: payload as ZMTransportData?, shouldCompress: true)
    }
    
    public func didReceive(_ response: ZMTransportResponse!, forSingleRequest sync: ZMSingleRequestSync!) {
        if response.result == .success {

            if let payload = response.payload as? [String: AnyObject],
                let results = payload["results"] as? [[String: AnyObject]]
            {
                let suggestedIds = results.flatMap { $0["id"] as? String }
                // XXX: this will always overwrite previous ones, effectively linking the suggestion to
                // the batch size, i.e. only AB with less contacts than the batch size will have reliable
                // suggestions. On the other hand, appending instead of replacing could cause infinite 
                // growth. For the moment, we will live with having suggestions only from the last batch
                self.managedObjectContext.suggestedUsersForUser = NSOrderedSet(array: suggestedIds)
            }
            
            self.managedObjectContext.commonConnectionsForUsers = [:]
            self.addressBookNeedsToBeUploaded = false
            self.encodedAddressBookChunkToUpload = nil
            
            // tracking
            self.tracker.tagAddressBookUploadSuccess()
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
        moc.setPersistentStoreMetadata(NSNumber(value: needsToBeUploaded), forKey: addressBookNeedsToBeUploadedKey)
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
                .setPersistentStoreMetadata(NSNumber(value: Int(newValue)), forKey: addressBookLastUploadedIndex)
        }
    }
}
